package com.planner.planner_app

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import java.io.FileOutputStream
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * A request transcribed by the phone's on-device recogniser from audio
 * Planner supplies (Android 13's EXTRA_AUDIO_SOURCE), so the microphone
 * never changes hands: no words are lost while a recogniser starts, and the
 * audio from before the wake can be included. On the Motorola only the
 * on-device recogniser accepts it (the default one answers "no match").
 *
 * Main thread: [start], [cancel]; the listener is called on it.
 * Audio thread: [offer].
 */
class OnDeviceRequest(
    private val context: Context,
    private val listener: Listener,
    /** Words to favour (Android 13 biasing): Planner's commands and the user's task names. */
    private val phrases: List<String> = emptyList(),
) {
    interface Listener {
        fun onWords(text: String)

        /** A pause after speech: [text] is everything heard so far. */
        fun onPause(text: String)
        fun onDone(text: String)

        /** This phone's recogniser can't take Planner's audio. */
        fun onUnsupported()
    }

    companion object {
        private const val TAG = "OnDeviceRequest"

        /** Quiet this long after a segment counts as a pause. */
        private const val PAUSE_MS = 1500L

        /** What people say to Planner, favoured over sound-alikes ("gym" came out as "details"). */
        val COMMANDS = listOf(
            "add", "add gym", "gym", "remind me to", "delete", "remove", "move", "reschedule", "mark",
            "complete", "done", "plan my evening", "what do I have tomorrow", "tomorrow", "today", "tonight",
            "this weekend", "next week", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
            "Sunday", "morning", "afternoon", "evening", "a.m.", "p.m.", "for one hour", "for 30 minutes",
            "hours", "minutes", "every day", "every Monday", "study", "exercise", "workout", "read", "call",
            "meeting", "groceries", "walk", "run",
        )

        fun available(context: Context): Boolean =
            Build.VERSION.SDK_INT >= 33 && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
    }

    private val queue = LinkedBlockingQueue<ShortArray>()
    @Volatile private var session = 0
    private var recognizer: SpeechRecognizer? = null
    private val main = android.os.Handler(android.os.Looper.getMainLooper())

    // With Planner's audio the recogniser dictates continuously: it splits
    // speech into segments, each with its own partials, and sends no final
    // result. The segments are joined here, and a pause ends a request.
    private val segments = mutableListOf<String>()
    private var current = ""
    private val pause = Runnable { listener.onPause(heard()) }

    private fun heard() = (segments + current).filter { it.isNotBlank() }.joinToString(" ")

    fun start(initial: List<ShortArray>) {
        initial.forEach { queue.offer(it) }
        begin()
    }


    fun cancel() = end()


    fun offer(chunk: ShortArray) {
        if (recognizer != null) queue.offer(chunk)
    }

    private fun end() {
        main.removeCallbacks(pause)
        session++
        recognizer?.let {
            try {
                it.destroy()
            } catch (_: Exception) {
            }
        }
        recognizer = null
    }

    private fun begin() {
        val id = ++session
        segments.clear()
        current = ""
        val pipe = ParcelFileDescriptor.createPipe()
        val r = SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        recognizer = r
        r.setRecognitionListener(object : RecognitionListener {
            private fun live() = id == session

            override fun onReadyForSpeech(params: Bundle?) {
                Log.d(TAG, "ready (session $id)")
            }

            override fun onBeginningOfSpeech() {
                Log.d(TAG, "speech began")
                main.removeCallbacks(pause)
            }

            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {
                Log.d(TAG, "speech ended")
                if (!live()) return
                main.removeCallbacks(pause)
                main.postDelayed(pause, PAUSE_MS)
            }

            override fun onEvent(eventType: Int, params: Bundle?) {}

            override fun onPartialResults(partialResults: Bundle?) {
                val t = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                Log.d(TAG, "partial \"$t\"")
                if (!live() || t == null) return
                // A segment's settled text arrives once, with a leading space
                // (or empty for noise); anything else is the live segment.
                // ("Speech ended" can come before its words when kept audio
                // arrives all at once, so it can't mark the boundary.)
                if (t.isEmpty() || t.startsWith(" ")) {
                    // Settled empty but it had live words ("add"): keep those.
                    val settled = t.trim().ifEmpty { current }
                    if (settled.isNotBlank()) segments.add(settled)
                    current = ""
                } else {
                    current = t.trim()
                }
                val all = heard()
                if (all.isNotBlank()) listener.onWords(all)
            }

            override fun onResults(results: Bundle?) {
                if (!live()) return
                // The final can come back empty when the partials had it all.
                val t = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                    ?.takeIf { it.isNotBlank() } ?: heard()
                end()
                listener.onDone(t)
            }

            override fun onError(error: Int) {
                if (!live()) return
                Log.d(TAG, "error $error")
                end()
                when (error) {
                    // Heard nothing, or nothing it knew: whatever it had.
                    SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> listener.onDone(heard())
                    else -> if (heard().isNotBlank()) listener.onDone(heard()) else listener.onUnsupported()
                }
            }
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
            if (Build.VERSION.SDK_INT >= 33) {
                putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList((COMMANDS + phrases).distinct()))
            }
        }
        try {
            r.startListening(intent)
        } catch (e: Exception) {
            Log.w(TAG, "start: ${e.message}")
            end()
            pipe.forEach { it.close() }
            listener.onUnsupported()
            return
        }
        // Writes queued audio into the pipe until this session ends.
        Thread({
            val bytes = ByteArray(3200)
            var written = 0
            try {
                FileOutputStream(pipe[1].fileDescriptor).use { out ->
                    while (id == session) {
                        val c = queue.poll(200, TimeUnit.MILLISECONDS) ?: continue
                        val b = if (c.size * 2 <= bytes.size) bytes else ByteArray(c.size * 2)
                        for (i in c.indices) {
                            b[2 * i] = (c[i].toInt() and 0xff).toByte()
                            b[2 * i + 1] = (c[i].toInt() shr 8 and 0xff).toByte()
                        }
                        out.write(b, 0, c.size * 2)
                        // The recogniser skips audio that arrives much faster
                        // than speech ("add gym" vanished when the kept audio
                        // went in at once), so a backlog goes in at about
                        // twice real time until it has caught up.
                        if (queue.size > 1) Thread.sleep(50)
                        written++
                        if (written % 50 == 1) Log.d(TAG, "fed $written chunks")
                    }
                }
            } catch (_: Exception) {
                // The recogniser closed its end: the session is over.
            } finally {
                pipe.forEach {
                    try {
                        it.close()
                    } catch (_: Exception) {
                    }
                }
            }
        }, "planner-request").start()
    }
}
