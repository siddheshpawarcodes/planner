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
import java.io.File
import java.io.FileOutputStream

/**
 * Debug: can the phone's speech recogniser transcribe audio Planner hands
 * it (Android 13's EXTRA_AUDIO_SOURCE) instead of opening the microphone
 * itself? Plays a 16 kHz mono WAV from app storage into it in real time and
 * logs what comes back, for the default and the on-device recogniser.
 */
class AudioSourceProbe(private val context: Context) {
    companion object {
        private const val TAG = "AudioProbe"
    }

    fun run(path: String, onDevice: Boolean, done: (String) -> Unit, bias: Boolean = false, language: String? = null) {
        if (Build.VERSION.SDK_INT < 33) return done("needs Android 13")
        val file = File(path)
        if (!file.exists()) return done("no file at $path")
        val avail = if (onDevice) SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        else SpeechRecognizer.isRecognitionAvailable(context)
        if (!avail) return done("recogniser not available (onDevice=$onDevice)")
        val sr = if (onDevice) SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        else SpeechRecognizer.createSpeechRecognizer(context)
        val pipe = ParcelFileDescriptor.createPipe()
        var finished = false
        var last = ""
        fun finish(msg: String) {
            if (finished) return
            finished = true
            Log.d(TAG, "onDevice=$onDevice: $msg")
            try {
                sr.destroy()
            } catch (_: Exception) {
            }
            done(msg)
        }
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) { Log.d(TAG, "ready") }
            override fun onBeginningOfSpeech() { Log.d(TAG, "speech began") }
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() { Log.d(TAG, "speech ended") }
            override fun onError(error: Int) = finish(if (last.isNotBlank()) last else "error $error")
            override fun onResults(results: Bundle?) =
                finish(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: last)
            override fun onPartialResults(partialResults: Bundle?) {
                val t = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()
                if (!t.isNullOrBlank()) last = t.trim()
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, pipe[0])
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, 1)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
            putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, 16000)
            if (bias) putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(OnDeviceRequest.COMMANDS))
            if (language != null) putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
        }
        sr.startListening(intent)
        Thread {
            try {
                val bytes = file.readBytes().drop(44).toByteArray() // skip the WAV header
                FileOutputStream(pipe[1].fileDescriptor).use { out ->
                    var i = 0
                    while (i < bytes.size) {
                        val n = minOf(3200, bytes.size - i) // 0.1 s
                        out.write(bytes, i, n)
                        i += n
                        Thread.sleep(100)
                    }
                    val silence = ByteArray(3200)
                    repeat(20) {
                        out.write(silence)
                        Thread.sleep(100)
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "write: ${e.message}")
            } finally {
                pipe[1].close()
                pipe[0].close()
            }
        }.start()
    }
}
