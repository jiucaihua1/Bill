package top.talyra42.verifin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/** Displays the opt-in status of the system-bound bookkeeping services. */
internal object AutoBookkeepingStatusNotification {
    private const val CHANNEL_ID = "verifin_auto_bookkeeping_status"
    private const val NOTIFICATION_ID = 4208
    private const val KEY_SUMMARY = "notification_summary"

    fun show(context: Context, summary: String? = null) {
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val previous = prefs.getString(KEY_SUMMARY, null)
        if (summary != null && previous != summary) {
            prefs.edit().putString(KEY_SUMMARY, summary).apply()
        }
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (!manager.areNotificationsEnabled()) return
        if ((summary == null || summary == previous) &&
            manager.activeNotifications.any { it.id == NOTIFICATION_ID && it.tag == null }
        ) return

        ensureChannel(manager)
        val text = (summary ?: previous)?.substringBefore(" · 已适配：") ?: "正在后台监听支付动态"
        manager.notify(NOTIFICATION_ID, buildNotification(context, text))
    }

    fun hide(context: Context) {
        context.getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
    }

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
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
}
