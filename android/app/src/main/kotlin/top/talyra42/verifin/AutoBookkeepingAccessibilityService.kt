package top.talyra42.verifin

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 检查已选择应用可访问的支付或转账页面，提交待确认草稿。
 */
class AutoBookkeepingAccessibilityService : AccessibilityService() {
    private val merchantCapture = WechatMerchantPaymentCapture(this)
    private val notificationCapture = NotificationPaymentCapture(this)

    override fun onServiceConnected() {
        super.onServiceConnected()
        activeService = this
        connected = true
    }

    override fun onUnbind(intent: Intent?): Boolean {
        connected = false
        if (activeService === this) activeService = null
        merchantCapture.reset()
        notificationCapture.reset()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        connected = false
        if (activeService === this) activeService = null
        merchantCapture.reset()
        notificationCapture.reset()
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val pkg = event?.packageName?.toString() ?: return
        if (!AutoBillParser.isAutoEnabled(this) || !AutoBillParser.isPlatformEnabled(this, pkg)) {
            merchantCapture.reset()
            return
        }
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            notificationCapture.onWindowChanged(pkg, event.windowId)
        }
        val texts = ArrayList<String>(48)
        val root = rootInActiveWindow
        if (root?.packageName?.toString() == pkg &&
            (event.windowId < 0 || root.windowId == event.windowId)
        ) {
            collectTexts(root, texts, 0)
        } else {
            for (win in windows) {
                if (win.id != event.windowId) continue
                val windowRoot = win.root
                if (windowRoot?.packageName?.toString() == pkg) {
                    collectTexts(windowRoot, texts, 0)
                }
            }
            // Pinduoduo checkout can report the event through a different
            // window ID while its own visible window still contains the bill.
            if (texts.isEmpty() && AutoBillParser.isPinduoduo(pkg) &&
                root?.packageName?.toString() == pkg
            ) {
                collectTexts(root, texts, 0)
            }
        }
        val eventTexts = ArrayList<String>(16)
        val source = event.source
        if (source?.packageName?.toString() == pkg) {
            collectTexts(source, eventTexts, 0)
        }
        if (eventTexts.isEmpty()) {
            event.text.mapNotNullTo(eventTexts) { it?.toString()?.trim()?.takeIf(String::isNotEmpty) }
        }
        val recognized = if (texts.isNotEmpty() || eventTexts.isNotEmpty()) {
            AutoBillParser.handleScreenTexts(
                this,
                pkg,
                texts,
                eventTexts,
                windowChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            )
        } else false
        merchantCapture.onEvent(event, recognized, texts + eventTexts)
    }

    private fun collectTexts(node: AccessibilityNodeInfo?, out: MutableList<String>, depth: Int) {
        if (node == null || depth > 28 || out.size >= 120) return
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty()) {
            out.add(text)
        }
        val desc = node.contentDescription?.toString()?.trim()
        if (!desc.isNullOrEmpty() && desc != text) {
            out.add(desc)
        }
        for (i in 0 until node.childCount) {
            collectTexts(node.getChild(i), out, depth + 1)
        }
    }

    override fun onInterrupt() = Unit

    companion object {
        private var activeService: AutoBookkeepingAccessibilityService? = null

        internal fun requestPaymentScreen(notice: AutoBillParser.PaymentNotice) {
            activeService?.notificationCapture?.request(notice)
        }

        @Volatile
        var connected = false
            private set
    }
}
