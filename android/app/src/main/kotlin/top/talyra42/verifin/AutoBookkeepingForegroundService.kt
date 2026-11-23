package top.talyra42.verifin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * 自动记账常驻通知栏前台服务：
 * 在自动记账开启且用户启用「常驻通知栏」时运行，作为系统后台保活凭据并展示当前状态与今日支出摘要。
 */
class AutoBookkeepingForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!AutoBillParser.isAutoEnabled(this)) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val prefs = getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val summary = prefs.getString(KEY_SUMMARY, null)
            ?.substringBefore(" · 已适配：")
            ?: "正在后台监听支付动态"
        ensureChannel()
        val notification = buildNotification(this, summary)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf(startId)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "自动记账运行状态",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "开启自动记账与常驻通知栏时展示后台运行状态与今日支出"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "verifin_auto_bookkeeping_status"
        private const val NOTIFICATION_ID = 4208
        const val KEY_SUMMARY = "notification_summary"

        private fun buildNotification(context: Context, summary: String): Notification {
            val openIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }
            val pendingOpen = PendingIntent.getActivity(
                context,
                201,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_quick_entry_tile)
                .setContentTitle("小禾自动记账运行中")
                .setContentText(summary)
                .setStyle(NotificationCompat.BigTextStyle().bigText(summary))
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setSilent(true)
                .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setContentIntent(pendingOpen)
                .build()
        }

        fun updateSummary(context: Context, summary: String) {
            val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
            if (prefs.getString(KEY_SUMMARY, null) == summary) return
            prefs.edit().putString(KEY_SUMMARY, summary).apply()
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.activeNotifications.any { it.id == NOTIFICATION_ID && it.tag == null }) {
                manager.notify(NOTIFICATION_ID, buildNotification(context, summary))
            }
        }

        fun sync(context: Context, enabled: Boolean, persistent: Boolean, summary: String? = null) {
            val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
            if (summary != null) {
                prefs.edit().putString(KEY_SUMMARY, summary).apply()
            }
            if (enabled && persistent) {
                val intent = Intent(context, AutoBookkeepingForegroundService::class.java)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        context.startForegroundService(intent)
                    } else {
                        context.startService(intent)
                    }
                } catch (_: RuntimeException) {
                    Log.w("VeriAutoBill", "System declined the auto-bookkeeping status service")
                }
            } else {
                val stopIntent = Intent(context, AutoBookkeepingForegroundService::class.java)
                context.stopService(stopIntent)
            }
        }
    }
}
