package com.planner.planner_app

import android.content.Context
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
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import org.vosk.android.StorageService
import java.io.IOException

/**
 * "Hey Planner" with Vosk: offline speech recognition restricted to a small
 * grammar. Near-miss phrases ("hey planet", "okay planner", "hey plan") are
 * in the grammar as decoys, so they are heard as themselves instead of being
 * forced onto the wake phrase; only "hey planner" wakes Planner.
 *
 * The model ships in the APK (assets/vosk-model) and is copied to app
 * storage once. Dart arms and disarms it (channel planner/wake) and gets a
 * "wake" event (planner/wake/events). The microphone is held only between
 * start and stop.
 */
class VoskWake(private val context: Context, messenger: BinaryMessenger) : RecognitionListener {
    companion object {
        private const val TAG = "VoskWake"
        private const val ASSET = "vosk-model"
        private const val RATE = 16000f
        private val WAKE = Regex("(^| )hey planner( |$)")
        private val GRAMMAR = listOf(
            "hey planner",
            // Decoys: close to the wake phrase, so they land here instead.
            "hey planet", "hey banner", "hey plan", "hey plant", "hey plane", "hey player",
            "okay planner", "a planner",
            "hey", "planner", "planet", "banner", "plan", "plant", "plane", "player", "okay",
            "[unk]",
        ).joinToString(",", "[", "]") { if (it == "[unk]") "\"[unk]\"" else "\"$it\"" }
    }

    private val main = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var service: SpeechService? = null
    private var loading = false
    private var wantRunning = false
    private var failure: String? = null
    private var events: EventChannel.EventSink? = null
    private var lastWake = 0L

    init {
        LibVosk.setLogLevel(LogLevel.WARNINGS)
        MethodChannel(messenger, "planner/wake").setMethodCallHandler { call, result ->
            when (call.method) {
                // Whether this build carries the model, or why not.
                "status" -> result.success(status())
                "start" -> {
                    wantRunning = true
                    ensureModelThenStart()
                    result.success(null)
                }
                "stop" -> {
                    wantRunning = false
                    stopListening()
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
            startListening()
            return
        }
        if (loading || failure != null) return
        loading = true
        // Copies the model out of the APK the first time (about 70 MB), then
        // loads it; both off the main thread, callbacks on it.
        StorageService.unpack(context, ASSET, "model", { m ->
            loading = false
            model = m
            recognizer = Recognizer(m, RATE, GRAMMAR)
            Log.d(TAG, "model ready")
            if (wantRunning) startListening()
        }, { e ->
            loading = false
            failure = "The wake-word model couldn't load: ${e.message}"
            Log.w(TAG, failure!!)
        })
    }

    private fun startListening() {
        val r = recognizer ?: return
        if (service != null) return
        try {
            r.reset()
            service = SpeechService(r, RATE).also { it.startListening(this) }
            Log.d(TAG, "listening")
        } catch (e: IOException) {
            // The microphone is busy or not allowed; Dart re-arms later.
            Log.w(TAG, "mic: ${e.message}")
            service = null
        }
    }

    private fun stopListening() {
        service?.let {
            it.stop()
            it.shutdown()
            Log.d(TAG, "stopped")
        }
        service = null
    }

    private fun check(json: String?, key: String) {
        val text = try {
            JSONObject(json ?: return).optString(key)
        } catch (e: Exception) {
            return
        }
        if (!WAKE.containsMatchIn(text)) return
        val now = SystemClock.elapsedRealtime()
        if (now - lastWake < 2000) return
        lastWake = now
        recognizer?.reset()
        Log.d(TAG, "wake: \"$text\"")
        main.post { events?.success("wake") }
    }

    override fun onPartialResult(hypothesis: String?) = check(hypothesis, "partial")
    override fun onResult(hypothesis: String?) = check(hypothesis, "text")
    override fun onFinalResult(hypothesis: String?) = check(hypothesis, "text")
    override fun onError(exception: Exception?) {
        Log.w(TAG, "error: ${exception?.message}")
        stopListening()
    }

    override fun onTimeout() {}

    fun dispose() {
        wantRunning = false
        stopListening()
        recognizer?.close()
        model?.close()
        recognizer = null
        model = null
    }
}
