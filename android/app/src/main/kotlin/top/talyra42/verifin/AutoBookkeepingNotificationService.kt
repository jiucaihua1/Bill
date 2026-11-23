package top.talyra42.verifin

import android.app.Notification
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * 自动记账通知监听服务：读取微信、支付宝、京东、拼多多等支付通知，提取金额与收支方向并触发确认弹窗。
 */
class AutoBookkeepingNotificationService : NotificationListenerService() {
    override fun onListenerConnected() {
        super.onListenerConnected()
        connected = true
    }

    override fun onListenerDisconnected() {
        connected = false
        super.onListenerDisconnected()
    }

    override fun onDestroy() {
        connected = false
        super.onDestroy()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val pkg = sbn?.packageName ?: return
        if (!AutoBillParser.isAutoEnabled(this) || !AutoBillParser.isPlatformEnabled(this, pkg)) return
        val notification = sbn.notification ?: return
        if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        val extras = notification.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString().orEmpty()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString().orEmpty()
        val body = bigText.ifBlank {
            text.ifBlank {
                extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.joinToString("\n").orEmpty()
            }
        }
        val notice = AutoBillParser.paymentNotice(pkg, title, body)
        if (notice != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (System.currentTimeMillis() - sbn.postTime in 0L..10_000L) {
                AutoBookkeepingAccessibilityService.requestPaymentScreen(notice)
            }
            return
        }
        AutoBillParser.handleNotification(this, pkg, title, body)
    }

    companion object {
        @Volatile
        var connected = false
            private set
    }
}
