package com.planner.planner_app

import android.app.Activity
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import com.gdelataillade.alarm.alarm.AlarmReceiver
import com.gdelataillade.alarm.alarm.AlarmService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Planner's only activity. A full-screen task alarm launches it with the
 * alarm plugin's RING action: only then may it show over the lock screen and
 * turn the screen on, and once the alarm is answered it clears both and
 * steps back to whatever the alarm interrupted (the lock screen included).
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val QUIET_CHANNEL = "planner_alarm_quiet"
    }

    private var alarmLaunch = false
    private var preview: MediaPlayer? = null
    private var wake: VoskWake? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    override fun onDestroy() {
        stopPreview()
        wake?.dispose()
        wake = null
        super.onDestroy()
    }

    private fun handleIntent(i: Intent?) {
        if (i?.action == AlarmService.ACTION_RING) {
            alarmLaunch = true
            overLock(true)
        }
    }

    private fun overLock(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        } else {
            @Suppress("DEPRECATION")
            val flags = WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            if (on) window.addFlags(flags) else window.clearFlags(flags)
        }
    }

    private val keyguard get() = getSystemService(KeyguardManager::class.java)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        wake = VoskWake(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "planner/alarm").setMethodCallHandler { call, result ->
            when (call.method) {
                "launchedByAlarm" -> result.success(alarmLaunch)
                "isLocked" -> result.success(keyguard.isKeyguardLocked)
                // A ring that reached the app another way (already open).
                "showOverLock" -> {
                    overLock(true)
                    result.success(null)
                }
                // Answered (Done, Snooze): stop showing over the lock screen
                // and, if the alarm opened Planner, go back where we were.
                "release" -> {
                    val wasAlarm = alarmLaunch
                    alarmLaunch = false
                    overLock(false)
                    if (wasAlarm) moveTaskToBack(true)
                    result.success(null)
                }
                // Start now: ask to unlock, then stay in Planner.
                "unlockAndStay" -> {
                    alarmLaunch = false
                    if (!keyguard.isKeyguardLocked) {
                        overLock(false)
                        result.success(true)
                    } else {
                        keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                            override fun onDismissSucceeded() {
                                overLock(false)
                                result.success(true)
                            }

                            override fun onDismissCancelled() {
                                overLock(false)
                                moveTaskToBack(true)
                                result.success(false)
                            }

                            override fun onDismissError() = onDismissCancelled()
                        })
                    }
                }
                // Planner's alarm screen is showing: swap the plugin's
                // heads-up notification for a quiet one under the same id.
                "quietBanner" -> {
                    quietBanner(
                        call.argument<Int>("id") ?: 0,
                        call.argument<String>("title") ?: "Planner",
                        call.argument<String>("body") ?: ""
                    )
                    result.success(null)
                }
                "tones" -> result.success(alarmTones())
                "copyTone" -> {
                    val uri = call.argument<String>("uri")
                    val name = call.argument<String>("name") ?: "tone"
                    result.success(uri?.let { copyTone(Uri.parse(it), name) })
                }
                "preview" -> {
                    playPreview(call.argument<String>("uri"))
                    result.success(null)
                }
                "stopPreview" -> {
                    stopPreview()
                    result.success(null)
                }
                "canFullScreen" -> result.success(
                    Build.VERSION.SDK_INT < 34 ||
                        getSystemService(NotificationManager::class.java).canUseFullScreenIntent()
                )
                "allowFullScreen" -> {
                    if (Build.VERSION.SDK_INT >= 34) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * The alarm plugin posts its ringing notification on a high-importance
     * channel, so Android shows a heads-up banner when the phone is in use,
     * on top of Planner's own alarm screen. Re-posting it under the same id
     * (it stays the foreground service's notification) on a low-importance,
     * silent channel takes the banner down; the tone keeps playing, since
     * the service plays it, not the notification. Stop and tap-to-open stay
     * for the notification shade.
     */
    private fun quietBanner(id: Int, title: String, body: String) {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(QUIET_CHANNEL, "Ringing alarm", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "The alarm that is ringing while its screen is open"
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                }
            )
        }
        val open = PendingIntent.getActivity(
            this, id, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stop = PendingIntent.getBroadcast(
            this, id,
            Intent(this, AlarmReceiver::class.java).apply {
                action = "com.gdelataillade.alarm.ACTION_STOP"
                putExtra("id", id)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(this, QUIET_CHANNEL)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(0, "Stop", stop)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .build()
        nm.notify(id, n)
    }

    /** The phone's alarm tones: [{title, uri}]. */
    private fun alarmTones(): List<Map<String, String>> {
        val out = mutableListOf<Map<String, String>>()
        val rm = RingtoneManager(this as Activity)
        rm.setType(RingtoneManager.TYPE_ALARM)
        val c = rm.cursor
        while (c.moveToNext()) {
            val title = c.getString(RingtoneManager.TITLE_COLUMN_INDEX)
            val uri = rm.getRingtoneUri(c.position).toString()
            out.add(mapOf("title" to title, "uri" to uri))
        }
        return out
    }

    /** The alarm service plays files, so a chosen tone is copied in. */
    private fun copyTone(uri: Uri, name: String): String? = try {
        val dir = File(filesDir, "alarm_tones").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val safe = name.replace(Regex("[^A-Za-z0-9]+"), "_").take(40)
        val file = File(dir, "$safe.tone")
        contentResolver.openInputStream(uri)?.use { input ->
            file.outputStream().use { input.copyTo(it) }
        }
        if (file.length() > 0) file.absolutePath else null
    } catch (e: Exception) {
        null
    }

    private fun playPreview(uri: String?) {
        stopPreview()
        val source = when {
            uri == null -> RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            uri.startsWith("/") -> Uri.fromFile(File(uri))
            else -> Uri.parse(uri)
        } ?: return
        try {
            preview = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@MainActivity, source)
                setOnCompletionListener { stopPreview() }
                prepare()
                start()
            }
        } catch (e: Exception) {
            stopPreview()
        }
    }

    private fun stopPreview() {
        preview?.run {
            try {
                stop()
            } catch (_: Exception) {
            }
            release()
        }
        preview = null
    }
}
