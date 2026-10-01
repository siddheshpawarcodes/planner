package com.planner.planner_app

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.vosk.LibVosk
import org.vosk.LogLevel
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.StorageService
import java.io.IOException
import kotlin.math.sqrt

/**
 * "Hey Planner" with Vosk, fully offline. Planner records the microphone
 * itself (16 kHz mono) and runs two recognisers over it:
 *
 * - **Listening:** a recogniser limited to a small grammar spots the wake
 *   phrase (see WAKE_START and WAKE_WHOLE). The audio since the last pause
 *   is kept, a few seconds at most.
 * - **Transcribing:** when the phrase is heard mid-sentence, an unrestricted
 *   recogniser takes that kept audio and the live audio after it, so a
 *   request said in one breath ("Hey Planner, add gym tomorrow") arrives
 *   whole: there is no gap while another recogniser starts. Its words go to
 *   Dart as they form; after a pause the sentence is sent as the request.
 *   When only the wake phrase was said (the user paused for the orb), the
 *   microphone is handed to Android's recogniser instead, which is more
 *   accurate for a request said on its own.
 *
 * The model ships in the APK (assets/vosk-model) and is copied to app
 * storage once. Dart arms and disarms it (channel planner/wake). Events
 * (planner/wake/events): "wake", "partial:<text>", "level:<0..1>",
 * "request:<text>", "handoff". The microphone is held only while listening
 * or transcribing.
 */
class VoskWake(private val context: Context, messenger: BinaryMessenger) {
    companion object {
        private const val TAG = "VoskWake"
        private const val ASSET = "vosk-model"
        private const val RATE = 16000
        private const val CHUNK = 1600 // 0.1 s
        private const val KEEP_CHUNKS = 40 // audio kept since the last pause, at most 4 s
        private const val END_SILENCE_MS = 1200L // a pause this long ends the request
        private const val MAX_REQUEST_MS = 15000L

        // Tuned on the user's own voice (1 Oct): Vosk often drops a soft
        // "hey" and lands "planner" on a near sound, so the wake phrase is
        // the "(hey) plan…" family. A partial wakes when an utterance starts
        // with it; a final wakes when the whole utterance is one, in any of
        // the top three guesses scoring within 5% of the best. Sentences
        // that only contain "planner" ("I need a planner…") never wake it.
        private val WAKE_START = Regex("^(?:(?:hey|a) )?(?:planner|planet|plant|plan)( |$)")
        private val WAKE_WHOLE = Regex("^(?:(?:hey|a) )?(?:planner|planet|plant|plan(?: a| banner)?)$")

        /** The wake phrase (or how it was heard) at the start of a transcript. */
        private val WAKE_PREFIX = Regex("^(?:(?:hey|hi|a) )?(?:planners?|planet|plant|plan)\\b[ ,]*")

        private val GRAMMAR = listOf(
            "hey planner",
            // Other near words, so they are heard as themselves.
            "hey planet", "hey banner", "hey plan", "hey plant", "hey plane", "hey player",
            "okay planner", "a planner",
            "hey", "planner", "planet", "banner", "plan", "plant", "plane", "player", "okay",
            "[unk]",
        ).joinToString(",", "[", "]") { "\"$it\"" }
    }

    private enum class Mode { OFF, LISTENING, TRANSCRIBING }

    private val main = Handler(Looper.getMainLooper())
    private val debuggable = context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private var model: Model? = null
    private var spotter: Recognizer? = null
    private var transcriber: Recognizer? = null
    private var loading = false
    private var failure: String? = null
    private var events: EventChannel.EventSink? = null

    // Main thread only.
    private var wantListening = false
    private var thread: Thread? = null

    // Shared with the audio thread.
    @Volatile private var mode = Mode.OFF
    @Volatile private var running = false

    init {
        LibVosk.setLogLevel(LogLevel.WARNINGS)
        MethodChannel(messenger, "planner/wake").setMethodCallHandler { call, result ->
            when (call.method) {
                // Whether this build carries the model, or why not.
                "status" -> result.success(status())
                "start" -> {
                    wantListening = true
                    ensureModelThenStart()
                    result.success(null)
                }
                // Disarm. A request being transcribed carries on: the voice
                // screen showing it ends it with "endRequest".
                "stop" -> {
                    wantListening = false
                    if (mode != Mode.TRANSCRIBING) stopRecording()
                    result.success(null)
                }
                "endRequest" -> {
                    if (mode == Mode.TRANSCRIBING) stopRecording()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "planner/wake/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })
    }

    private fun emit(e: String) {
        main.post { events?.success(e) }
    }

    private fun status(): String? {
        failure?.let { return it }
        val files = try {
            context.assets.list(ASSET)
        } catch (e: IOException) {
            null
        }
        return if (files.isNullOrEmpty() || !files.contains("uuid")) {
            "No Vosk model in this build (run tool/fetch_vosk_model.sh)."
        } else {
            null
        }
    }

    private fun ensureModelThenStart() {
        if (model != null) {
            startRecording()
            return
        }
        if (loading || failure != null) return
        loading = true
        // Copies the model out of the APK the first time (about 70 MB), then
        // loads it; both off the main thread, callbacks on it.
        StorageService.unpack(context, ASSET, "model", { m ->
            loading = false
            model = m
            spotter = Recognizer(m, RATE.toFloat(), GRAMMAR).apply { setMaxAlternatives(3) }
            transcriber = Recognizer(m, RATE.toFloat())
            Log.d(TAG, "model ready")
            if (wantListening) startRecording()
        }, { e ->
            loading = false
            failure = "The wake-word model couldn't load: ${e.message}"
            Log.w(TAG, failure!!)
        })
    }

    @SuppressLint("MissingPermission") // Dart starts it only with the microphone allowed.
    private fun startRecording() {
        if (thread?.isAlive == true || spotter == null) return
        val min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val rec = try {
            AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE, AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT, maxOf(min, CHUNK * 2 * 4)
            )
        } catch (e: Exception) {
            Log.w(TAG, "mic: ${e.message}")
            return
        }
        if (rec.state != AudioRecord.STATE_INITIALIZED) {
            // The microphone is busy or not allowed; Dart re-arms later.
            Log.w(TAG, "mic unavailable")
            rec.release()
            return
        }
        spotter?.reset()
        mode = Mode.LISTENING
        running = true
        thread = Thread({ loop(rec) }, "planner-wake").also { it.start() }
        Log.d(TAG, "listening")
    }

    private fun stopRecording() {
        running = false
        thread?.join(500)
        thread = null
        mode = Mode.OFF
        Log.d(TAG, "stopped")
    }

    /** The audio thread: reads the microphone and feeds the recogniser for the current mode. */
    private fun loop(rec: AudioRecord) {
        val buf = ShortArray(CHUNK)
        val kept = ArrayDeque<ShortArray>()
        var lastWake = 0L
        // Transcribing.
        val said = StringBuilder()
        var partial = ""
        var startedAt = 0L
        var quietSince = 0L
        try {
            rec.startRecording()
            loop@ while (running) {
                val n = rec.read(buf, 0, CHUNK)
                if (n <= 0) continue
                val chunk = buf.copyOf(n)
                val now = SystemClock.elapsedRealtime()
                when (mode) {
                    Mode.LISTENING -> {
                        kept.addLast(chunk)
                        while (kept.size > KEEP_CHUNKS) kept.removeFirst()
                        val r = spotter ?: break@loop
                        val final = r.acceptWaveForm(chunk, n)
                        val woke = if (final) wakeInFinal(r.result) else WAKE_START.containsMatchIn(partialOf(r.partialResult))
                        if (woke && now - lastWake > 2000) {
                            lastWake = now
                            r.reset()
                            emit("wake")
                            if (final) {
                                // The phrase on its own, then a pause:
                                // Android's recogniser takes the request.
                                Log.d(TAG, "wake, then a pause: handing over")
                                handOver(rec)
                                return
                            }
                            // Mid-sentence: transcribe it from its start.
                            Log.d(TAG, "wake mid-sentence: transcribing")
                            val t = transcriber ?: break@loop
                            t.reset()
                            for (c in kept) t.acceptWaveForm(c, c.size)
                            kept.clear()
                            said.setLength(0)
                            partial = ""
                            startedAt = now
                            quietSince = 0L
                            mode = Mode.TRANSCRIBING
                        } else if (final) {
                            kept.clear() // a pause: the next utterance starts here
                        }
                    }
                    Mode.TRANSCRIBING -> {
                        val t = transcriber ?: break@loop
                        emit("level:${"%.3f".format(level(chunk))}")
                        if (t.acceptWaveForm(chunk, n)) {
                            val seg = JSONObject(t.result).optString("text").trim()
                            if (seg.isNotEmpty()) said.append(if (said.isEmpty()) seg else " $seg")
                            partial = ""
                            if (said.isNotEmpty() && said.toString().replaceFirst(WAKE_PREFIX, "").isBlank()) {
                                // Only the wake phrase, then a pause.
                                Log.d(TAG, "heard only \"$said\": handing over")
                                handOver(rec)
                                return
                            }
                            quietSince = now
                        } else {
                            val p = partialOf(t.partialResult)
                            if (p.isNotEmpty() && p != partial) {
                                partial = p
                                quietSince = 0L
                                emit("partial:" + listOf(said.toString(), p).filter { it.isNotEmpty() }.joinToString(" "))
                            }
                        }
                        val quiet = quietSince > 0 && now - quietSince > END_SILENCE_MS
                        if (quiet || now - startedAt > MAX_REQUEST_MS) {
                            if (said.isEmpty()) said.append(JSONObject(t.finalResult).optString("text").trim())
                            Log.d(TAG, "request: \"$said\"")
                            emit("request:$said")
                            break@loop
                        }
                    }
                    Mode.OFF -> break@loop
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "audio: ${e.message}")
        } finally {
            running = false
            try {
                rec.stop()
            } catch (_: Exception) {
            }
            rec.release()
            mode = Mode.OFF
        }
    }

    /** Lets go of the microphone, then tells Dart to start Android's recogniser. */
    private fun handOver(rec: AudioRecord) {
        running = false
        try {
            rec.stop()
        } catch (_: Exception) {
        }
        rec.release()
        mode = Mode.OFF
        emit("handoff")
    }

    private fun partialOf(json: String?): String = try {
        JSONObject(json ?: "").optString("partial")
    } catch (e: Exception) {
        ""
    }

    /** A final's top three guesses: wake if a whole one is the phrase, close to the best. */
    private fun wakeInFinal(json: String?): Boolean {
        val alts = try {
            JSONObject(json ?: return false).optJSONArray("alternatives") ?: return false
        } catch (e: Exception) {
            return false
        }
        val list = (0 until alts.length()).map { alts.getJSONObject(it) }
        if (debuggable && list.any { it.optString("text").isNotEmpty() }) {
            Log.d(TAG, "heard: " + list.joinToString(" | ") {
                "${it.optString("text")} (${"%.0f".format(it.optDouble("confidence"))})"
            })
        }
        val top = list.firstOrNull()?.optDouble("confidence") ?: return false
        val margin = maxOf(3.0, 0.05 * Math.abs(top))
        return list.any { WAKE_WHOLE.matches(it.optString("text")) && it.optDouble("confidence") >= top - margin }
    }

    /** Mic level for the orb, 0..1 (RMS × 7, clamped, as the prototype maps it). */
    private fun level(s: ShortArray): Double {
        var sum = 0.0
        for (v in s) sum += v.toDouble() * v
        return minOf(1.0, sqrt(sum / s.size) / 32768.0 * 7)
    }

    fun dispose() {
        wantListening = false
        stopRecording()
        spotter?.close()
        transcriber?.close()
        model?.close()
        spotter = null
        transcriber = null
        model = null
    }
}
