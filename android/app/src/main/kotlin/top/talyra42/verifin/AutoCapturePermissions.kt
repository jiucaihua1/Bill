package top.talyra42.verifin

import android.content.ComponentName
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.util.Log
import rikka.shizuku.Shizuku

/**
 * 自动记账与截图记账所需的系统权限检测与设置跳转工具。
 */
object AutoCapturePermissions {
    const val PREFS_NAME = "verifin_auto_bookkeeping"
    private const val KEY_AUTO_ENABLED = "auto_enabled"
    private const val KEY_PERSISTENT_NOTIFICATION = "persistent_notification"
    private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"

    private fun canPostDetectedNotifications(context: Context): Boolean {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return false
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return manager.getNotificationChannel(AutoBillParser.DETECTION_CHANNEL_ID)
            ?.importance != NotificationManager.IMPORTANCE_NONE
    }

    fun isAccessibilityGranted(context: Context): Boolean {
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val target = ComponentName(context, AutoBookkeepingAccessibilityService::class.java)
            .flattenToString()
        val shortTarget = ComponentName(context, AutoBookkeepingAccessibilityService::class.java)
            .flattenToShortString()
        return enabled.split(':').any {
            it.equals(target, ignoreCase = true) || it.equals(shortTarget, ignoreCase = true)
        }
    }

    fun isNotificationListenerGranted(context: Context): Boolean {
        val component = ComponentName(context, AutoBookkeepingNotificationService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            return context.getSystemService(NotificationManager::class.java)
                ?.isNotificationListenerAccessGranted(component) == true
        }
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val target = component.flattenToString()
        val shortTarget = component.flattenToShortString()
        return enabled.split(':').any {
            it.equals(target, ignoreCase = true) || it.equals(shortTarget, ignoreCase = true)
        }
    }

    fun isBatteryOptimizationIgnored(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    fun isShizukuInstalled(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    SHIZUKU_PACKAGE,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0)
            }
            true
        } catch (_: Exception) {
            false
        }
    }

    fun isShizukuGranted(): Boolean {
        return try {
            Shizuku.pingBinder() &&
                Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        } catch (_: Throwable) {
            false
        }
    }

    fun requestShizuku(context: Context): String {
        if (!isShizukuInstalled(context)) {
            return "not_installed"
        }
        try {
            if (Shizuku.pingBinder()) {
                if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) {
                    return "granted"
                }
                Shizuku.requestPermission(1001)
                return "requested"
            }
        } catch (_: Throwable) {
            // Binder 未就绪。
        }
        openPermissionSettings(context, "shizuku")
        return "not_running"
    }

    fun syncOnAppStart(context: Context) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_AUTO_ENABLED, false)
        val persistent = prefs.getBoolean(KEY_PERSISTENT_NOTIFICATION, true)
        if (enabled && persistent) {
            AutoBookkeepingForegroundService.sync(context, true, true, null)
        }
    }

    fun reconnectNotificationListener(context: Context): Boolean {
        if (!isNotificationListenerGranted(context)) return false
        if (AutoBookkeepingNotificationService.connected) return true
        return try {
            NotificationListenerService.requestRebind(
                ComponentName(context, AutoBookkeepingNotificationService::class.java),
            )
            true
        } catch (_: RuntimeException) {
            Log.w("VeriAutoBill", "Notification listener rebind was not accepted")
            false
        }
    }

    fun statusMap(context: Context): Map<String, Any> {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return mapOf(
            "overlayGranted" to Settings.canDrawOverlays(context),
            "accessibilityGranted" to isAccessibilityGranted(context),
            "accessibilityConnected" to AutoBookkeepingAccessibilityService.connected,
            "notificationGranted" to isNotificationListenerGranted(context),
            "notificationConnected" to AutoBookkeepingNotificationService.connected,
            "canPostNotifications" to canPostDetectedNotifications(context),
            "batteryIgnored" to isBatteryOptimizationIgnored(context),
            "shizukuInstalled" to isShizukuInstalled(context),
            "shizukuGranted" to isShizukuGranted(),
            "autoEnabled" to prefs.getBoolean(KEY_AUTO_ENABLED, false),
            "persistentNotification" to prefs.getBoolean(KEY_PERSISTENT_NOTIFICATION, true),
        )
    }

    fun setAutoEnabled(context: Context, enabled: Boolean, summary: String? = null) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_AUTO_ENABLED, enabled).apply()
        if (enabled) {
            reconnectNotificationListener(context)
        } else {
            AutoBillOverlay.clear()
            AutoBillParser.clearDrafts(context)
        }
        val persistent = prefs.getBoolean(KEY_PERSISTENT_NOTIFICATION, true)
        AutoBookkeepingForegroundService.sync(context, enabled, persistent, summary)
    }

    fun setPersistentNotification(context: Context, persistent: Boolean, summary: String? = null) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putBoolean(KEY_PERSISTENT_NOTIFICATION, persistent).apply()
        val enabled = prefs.getBoolean(KEY_AUTO_ENABLED, false)
        AutoBookkeepingForegroundService.sync(context, enabled, persistent, summary)
    }

    fun updateNotificationSummary(context: Context, summary: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean(KEY_AUTO_ENABLED, false)
        val persistent = prefs.getBoolean(KEY_PERSISTENT_NOTIFICATION, true)
        if (enabled && persistent) AutoBookkeepingForegroundService.updateSummary(context, summary)
    }

    fun openPermissionSettings(context: Context, kind: String): Boolean {
        val intent = when (kind) {
            "overlay" -> Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            )
            "accessibility" -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            "notification" -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            "post_notifications" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager = context.getSystemService(NotificationManager::class.java)
                val channel = manager?.getNotificationChannel(AutoBillParser.DETECTION_CHANNEL_ID)
                if (manager?.areNotificationsEnabled() == true && channel != null) {
                    Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, channel.id)
                } else {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                }
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
            }
            "battery" -> Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"),
            )
            "shizuku" -> context.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE)
            else -> null
        } ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
