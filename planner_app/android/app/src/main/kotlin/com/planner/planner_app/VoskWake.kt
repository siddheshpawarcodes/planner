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
 * "Hey Planner", fully offline. Planner records the microphone itself
 * (16 kHz mono) and never hands it over mid-request:
 *
 * - **Listening:** Vosk, limited to a small grammar, spots the wake phrase
 *   (see WAKE_START and WAKE_WHOLE). The audio since the last pause is kept,
 *   a few seconds at most.
 * - **Forwarding** (Android 13+ with an on-device recogniser): on a wake,
 *   the kept audio and the live audio go to the phone's on-device
 *   recogniser ([OnDeviceRequest]), which is far more accurate for a
 *   request than Vosk's small model. Said in one breath ("Hey Planner, add
 *   gym tomorrow"), the request arrives whole; if only the wake phrase was
 *   heard, a second pass takes the request after the pause.
 * - **Transcribing** (fallback): Vosk's unrestricted recogniser does the
 *   same from the kept audio, and a wake on its own hands the microphone to
 *   Android's usual recogniser ("handoff").
 *
 * The model ships in the APK (assets/vosk-model) and is copied to app
 * storage once. Dart arms and disarms it (channel planner/wake). Events
 * (planner/wake/events): "wake", "partial:<text>", "level:<0..1>",
 * "request:<text>", "handoff". The microphone is held only while listening
 * or taking a request.
 */
class VoskWake(private val context: Context, messenger: BinaryMessenger) {
    companion object {
        private const val TAG = "VoskWake"
        private const val ASSET = "vosk-model"
        private const val RATE = 16000
        private const val CHUNK = 1600 // 0.1 s
        private const val KEEP_CHUNKS = 40 // audio kept since the last pause, at most 4 s
        private const val END_SILENCE_MS = 1200L // a pause this long ends a Vosk transcript
        private const val MAX_REQUEST_MS = 20000L

        // Tuned on the user's own voice (1 Oct): Vosk often drops a soft
        // "hey" and lands "planner" on a near sound, so the wake phrase is
        // the "(hey) plan…" family. A partial wakes when an utterance starts
        // with it; a final wakes when the whole utterance is one, in any of
        // the top three guesses scoring within 5% of the best. Sentences
        // that only contain "planner" ("I need a planner…") never wake it.
        private val WAKE_START = Regex("^(?:(?:hey|a) )?(?:planner|planet|plant|plan)( |$)")
        private val WAKE_WHOLE = Regex("^(?:(?:hey|a) )?(?:planner|planet|plant|plan(?: a| banner)?)$")

        /** The wake phrase (or how it was heard) at the start of a transcript. */
        private val WAKE_PREFIX = Regex(
            "^\\W*(?:(?:hey|he|hi|ok|okay|a)\\W+)?(?:planners?|planet|plant|plan)\\b\\W*",
            RegexOption.IGNORE_CASE
        )

        private val GRAMMAR = listOf(
            "hey planner",
            // Other near words, so they are heard as themselves.
            "hey planet", "hey banner", "hey plan", "hey plant", "hey plane", "hey player",
            "okay planner", "a planner",
            "hey", "planner", "planet", "banner", "plan", "plant", "plane", "player", "okay",
            "[unk]",
        ).joinToString(",", "[", "]") { "\"$it\"" }
    }

    private enum class Mode { OFF, LISTENING, FORWARDING, TRANSCRIBING }

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
    private var request: OnDeviceRequest? = null

    /** The user's task names, to favour in requests (from Dart at each start). */
    private var phrases: List<String> = emptyList()

    /** Wait this long for a request after the wake phrase alone. */
    private val requestWaitMs = 8000L
    private var forwardedAt = 0L

    /** The on-device recogniser turned Planner's audio down once: use Vosk. */
    @Volatile private var forwardingBroken = false

    // Shared with the audio thread.
    @Volatile private var mode = Mode.OFF
    @Volatile private var running = false
    @Volatile private var forwardTo: OnDeviceRequest? = null

    init {
        LibVosk.setLogLevel(LogLevel.WARNINGS)
        MethodChannel(messenger, "planner/wake").setMethodCallHandler { call, result ->
            when (call.method) {
                // Whether this build carries the model, or why not.
                "status" -> result.success(status())
                "start" -> {
                    phrases = call.argument<List<String>>("phrases") ?: phrases
                    wantListening = true
                    ensureModelThenStart()
                    result.success(null)
                }
                // Disarm. A request being taken carries on: the voice screen
                // showing it ends it with "endRequest".
                "stop" -> {
                    wantListening = false
                    if (mode == Mode.LISTENING) stopRecording()
                    result.success(null)
                }
                "endRequest" -> {
                    if (mode == Mode.FORWARDING || mode == Mode.TRANSCRIBING) endRequest()
                    result.success(null)
                }
                // Debug: does the recogniser take Planner's own audio?
                "probe" -> {
                    val path = call.argument<String>("path") ?: ""
                    AudioSourceProbe(context).run(
                        path, call.argument<Boolean>("onDevice") ?: false,
                        { main.post { result.success(it) } },
                        bias = call.argument<Boolean>("bias") ?: false,
                        language = call.argument<String>("language"),
                    )
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

    private fun endRequest() {
        request?.cancel()
        request = null
        forwardTo = null
        stopRecording()
    }

    // ---------------------------------------------------------------- forwarding

    /** Main thread: starts the on-device recogniser on [kept] (empty when the wake phrase stood alone). */
    private fun startForwarding(kept: List<ShortArray>) {
        forwardedAt = SystemClock.elapsedRealtime()
        val r = OnDeviceRequest(context, object : OnDeviceRequest.Listener {
            override fun onWords(text: String) {
                val shown = text.replaceFirst(WAKE_PREFIX, "")
                if (shown.isNotBlank()) emit("partial:$shown")
            }

            override fun onPause(text: String) {
                val rest = text.replaceFirst(WAKE_PREFIX, "").trim()
                if (rest.isEmpty() && SystemClock.elapsedRealtime() - forwardedAt < requestWaitMs) {
                    // Only the wake phrase so far: the request comes after the pause.
                    Log.d(TAG, "heard \"$text\": waiting for the request")
                    return
                }
                finish(rest)
            }

            override fun onDone(text: String) = finish(text.replaceFirst(WAKE_PREFIX, "").trim())

            private fun finish(rest: String) {
                Log.d(TAG, "request: \"$rest\"")
                emit("request:$rest")
                endRequest()
            }

            override fun onUnsupported() {
                Log.w(TAG, "the on-device recogniser won't take Planner's audio; using Vosk")
                forwardingBroken = true
                request = null
                forwardTo = null
                // The audio already given is gone; let Android's recogniser
                // take the request from here.
                running = false
                thread?.join(500)
                thread = null
                mode = Mode.OFF
                emit("handoff")
            }
        }, phrases)
        request = r
        r.start(kept)
        forwardTo = r
    }

    // ---------------------------------------------------------------- audio thread

    /** Reads the microphone and feeds whatever the current mode needs. */
    private fun loop(rec: AudioRecord) {
        val buf = ShortArray(CHUNK)
        val kept = ArrayDeque<ShortArray>()
        var lastWake = 0L
        var startedAt = 0L
        // Transcribing with Vosk.
        val said = StringBuilder()
        var partial = ""
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
                        if (!woke || now - lastWake < 2000) {
                            if (final) kept.clear() // a pause: the next utterance starts here
                            continue@loop
                        }
                        lastWake = now
                        startedAt = now
                        r.reset()
                        emit("wake")
                        val alone = final // the phrase, then a pause
                        if (!forwardingBroken && OnDeviceRequest.available(context)) {
                            Log.d(TAG, if (alone) "wake, then a pause: forwarding live audio" else "wake mid-sentence: forwarding")
                            // The wake phrase and what follows: the last 2.5 s.
                            val start = if (alone) emptyList() else kept.toList().takeLast(25)
                            kept.clear()
                            forwardTo = null
                            mode = Mode.FORWARDING
                            main.post { startForwarding(start) }
                        } else if (alone) {
                            Log.d(TAG, "wake, then a pause: handing over")
                            handOver(rec)
                            return
                        } else {
                            Log.d(TAG, "wake mid-sentence: transcribing with Vosk")
                            val t = transcriber ?: break@loop
                            t.reset()
                            for (c in kept) t.acceptWaveForm(c, c.size)
                            kept.clear()
                            said.setLength(0)
                            partial = ""
                            quietSince = 0L
                            mode = Mode.TRANSCRIBING
                        }
                    }
                    Mode.FORWARDING -> {
                        // Until the recogniser is up, chunks wait here.
                        val to = forwardTo
                        if (to == null) {
                            kept.addLast(chunk)
                        } else {
                            while (kept.isNotEmpty()) to.offer(kept.removeFirst())
                            to.offer(chunk)
                        }
                        emit("level:${"%.3f".format(level(chunk))}")
                        if (now - startedAt > MAX_REQUEST_MS) {
                            main.post { request?.let { endRequest(); emit("request:") } }
                            break@loop
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
                            Log.d(TAG, "request (Vosk): \"$said\"")
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
        request?.cancel()
        request = null
        stopRecording()
        spotter?.close()
        transcriber?.close()
        model?.close()
        spotter = null
        transcriber = null
        model = null
    }
}
