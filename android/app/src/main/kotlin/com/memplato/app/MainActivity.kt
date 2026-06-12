package com.memplato.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.IBinder
import android.provider.Settings
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.memplato.app/termux"
    private var methodChannel: MethodChannel? = null
    private var statusReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        )

        methodChannel!!.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {

                "isTermuxInstalled" -> {
                    result.success(isPackageInstalled("com.termux"))
                }

                "hasRunCommandPermission" -> {
                    val permission = checkCallingOrSelfPermission(
                        "com.termux.permission.RUN_COMMAND"
                    )
                    result.success(permission == PackageManager.PERMISSION_GRANTED)
                }

                "openUrl" -> {
                    val url = call.argument<String>("url") ?: ""
                    try {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_URL_ERROR", e.message, null)
                    }
                }

                "openAppSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:com.memplato.app")
                        )
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_SETTINGS_ERROR", e.message, null)
                    }
                }

                "openTermux" -> {
                    try {
                        val intent = packageManager.getLaunchIntentForPackage("com.termux")
                        if (intent != null) {
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            result.success(true)
                        } else {
                            result.error("TERMUX_NOT_FOUND", "Termux не встановлено", null)
                        }
                    } catch (e: Exception) {
                        result.error("OPEN_TERMUX_ERROR", e.message, null)
                    }
                }

                "runCommand" -> {
                    val command = call.argument<String>("command") ?: ""
                    try {
                        runTermuxCommand(command)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RUN_COMMAND_ERROR", e.message, null)
                    }
                }

                "areNotificationsEnabled" -> {
                    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    result.success(nm.areNotificationsEnabled())
                }

                "openNotificationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        intent.putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message, null)
                    }
                }

                "startInstallService" -> {
                    try {
                        registerStatusReceiver()
                        val intent = Intent(this, InstallForegroundService::class.java)
                        intent.putExtra("notification_text", "⏳ Починаємо встановлення...")
                        startForegroundService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                "stopInstallService" -> {
                    try {
                        unregisterStatusReceiver()
                        val intent = Intent(this, InstallForegroundService::class.java)
                        stopService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                "updateNotification" -> {
                    val text = call.argument<String>("text") ?: ""
                    try {
                        val intent = Intent(this, InstallForegroundService::class.java)
                        intent.putExtra("notification_text", text)
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                "sendBatteryNotification" -> {
                    try {
                        val intent = Intent(this, InstallForegroundService::class.java)
                        intent.putExtra("send_battery", true)
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                // ✅ НОВИЙ МЕТОД
                "sendSuccessNotification" -> {
                    try {
                        // Спочатку прибираємо повідомлення встановлення
                        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancel(2001)
                        // Потім надсилаємо success
                        val intent = Intent(this, InstallForegroundService::class.java)
                        intent.putExtra("send_success", true)
                        startService(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SERVICE_ERROR", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun registerStatusReceiver() {
        if (statusReceiver != null) return
        statusReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val step = intent.getStringExtra("step") ?: return
                val uid = intent.getStringExtra("uid") ?: ""
                runOnUiThread {
                    val args = mapOf("step" to step, "uid" to uid)
                    methodChannel?.invokeMethod("onInstallStatus", args)
                }
                val svcIntent = Intent(context, InstallForegroundService::class.java)
                svcIntent.putExtra("notification_text", step)
                startService(svcIntent)
            }
        }
        val filter = IntentFilter("com.memplato.STATUS")
        registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
    }

    private fun unregisterStatusReceiver() {
        if (statusReceiver != null) {
            try { unregisterReceiver(statusReceiver) } catch (e: Exception) {}
            statusReceiver = null
        }
    }

    override fun onDestroy() {
        unregisterStatusReceiver()
        super.onDestroy()
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun runTermuxCommand(command: String) {
        val intent = Intent()
        intent.setClassName("com.termux", "com.termux.app.RunCommandService")
        intent.action = "com.termux.RUN_COMMAND"
        intent.putExtra(
            "com.termux.RUN_COMMAND_PATH",
            "/data/data/com.termux/files/usr/bin/bash"
        )
        intent.putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf("-c", command))
        intent.putExtra(
            "com.termux.RUN_COMMAND_WORKDIR",
            "/data/data/com.termux/files/home"
        )
        intent.putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
        startService(intent)
    }
}

class InstallForegroundService : Service() {

    private val CHANNEL_ID = "memplato_install"
    private val BATTERY_CHANNEL_ID = "memplato_battery"
    private val NOTIF_ID = 2001
    private val BATTERY_NOTIF_ID = 1001
    private val SUCCESS_NOTIF_ID = 3001  // ✅ НОВИЙ ID

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannels()

        val text = intent?.getStringExtra("notification_text")
        val sendBattery = intent?.getBooleanExtra("send_battery", false) ?: false
        val sendSuccess = intent?.getBooleanExtra("send_success", false) ?: false  // ✅ НОВИЙ

        if (sendBattery) {
            sendBatteryNotification()
            return START_STICKY
        }

        // ✅ НОВИЙ БЛОК
        if (sendSuccess) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.cancel(NOTIF_ID)
            sendSuccessNotification()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        if (text != null) {
            startForeground(NOTIF_ID, buildNotification(text))
            updateNotification(text)
        } else {
            startForeground(NOTIF_ID, buildNotification("⏳ Починаємо встановлення..."))
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
    }

    private fun createChannels() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val installChannel = NotificationChannel(
            CHANNEL_ID, "MemPlato Встановлення", NotificationManager.IMPORTANCE_LOW
        )
        nm.createNotificationChannel(installChannel)
        val batteryChannel = NotificationChannel(
            BATTERY_CHANNEL_ID, "MemPlato Сервер", NotificationManager.IMPORTANCE_HIGH
        )
        batteryChannel.enableVibration(true)
        batteryChannel.enableLights(true)
        nm.createNotificationChannel(batteryChannel)
    }

    private fun buildNotification(text: String): android.app.Notification {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 0, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val isDone = text.contains("DONE", ignoreCase = true)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle("🏛️ MemPlato")
            .setContentText(text)
            .setContentIntent(pi)
            .setOngoing(!isDone)
            .setAutoCancel(isDone)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIF_ID, buildNotification(text))
    }

    private fun sendBatteryNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        intent.data = Uri.parse("package:com.termux")
        val pi = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, BATTERY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("⚠️ Вимкни енергозбереження!")
            .setContentText("Натисни щоб відкрити налаштування батареї")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Щоб Android не зупинив встановлення:\n\n" +
                            "1. Знайди Termux у списку\n" +
                            "2. Натисни → «Без обмежень»\n" +
                            "3. Повернись в MemPlato"
                )
            )
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        nm.notify(BATTERY_NOTIF_ID, notification)

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            sendMemplatoNotification()
        }, 30_000)
    }

    private fun sendMemplatoNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
        intent.data = Uri.parse("package:com.memplato.app")
        val pi = PendingIntent.getActivity(
            this, 1, intent, PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, BATTERY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle("⚠️ Ще один крок!")
            .setContentText("Вимкни енергозбереження для MemPlato")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Щоб MemPlato теж не зупинявся:\n\n" +
                            "1. Знайди MemPlato у списку\n" +
                            "2. Натисни → «Без обмежень»\n" +
                            "3. Повернись в MemPlato"
                )
            )
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        nm.notify(BATTERY_NOTIF_ID + 1, notification)
    }

    // ✅ НОВИЙ МЕТОД
    private fun sendSuccessNotification() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        val pi = PendingIntent.getActivity(
            this, 2, intent, PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(this, BATTERY_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("🎉 MemPlato готовий!")
            .setContentText("Сервер встановлено і запущено")
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "✅ Сервер встановлено і запущено!\n\n" +
                            "Тепер MemPlato працює на цьому телефоні.\n" +
                            "Можеш закрити додаток — сервер продовжить працювати."
                )
            )
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()
        nm.notify(SUCCESS_NOTIF_ID, notification)
    }
}