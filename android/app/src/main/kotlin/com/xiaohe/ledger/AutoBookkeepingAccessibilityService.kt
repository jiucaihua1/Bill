package com.xiaohe.ledger

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * 检查已选择应用可访问的支付或转账页面，提交待确认草稿。
 */
class AutoBookkeepingAccessibilityService : AccessibilityService() {
    private val merchantCapture = WechatMerchantPaymentCapture(this)
    private val notificationCapture = NotificationPaymentCapture(this)
    private var alipayCheckoutWindow: Pair<Int, String>? = null
    private var alipayCheckoutRecognized = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        if (BuildConfig.DEBUG) {
            serviceInfo?.let { info ->
                info.notificationTimeout = 0L
                info.eventTypes = info.eventTypes or AccessibilityEvent.TYPE_WINDOWS_CHANGED
                serviceInfo = info
            }
        }
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
        if (event == null) return
        if (BuildConfig.DEBUG && event.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            if (AutoBillParser.isAutoEnabled(this) && AutoBillParser.isPlatformEnabled(this, AutoBillParser.PKG_WECHAT)) {
                merchantCapture.onPaymentCodeWindowsChanged(event)
            }
            return
        }
        val pkg = event.packageName?.toString() ?: return
        if (!AutoBillParser.isAutoEnabled(this) || !AutoBillParser.isPlatformEnabled(this, pkg)) {
            if (pkg == AutoBillParser.PKG_ALIPAY) setAlipayCheckoutWindow(null)
            merchantCapture.reset()
            return
        }
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            notificationCapture.onWindowChanged(pkg, event.windowId)
            if (pkg == AutoBillParser.PKG_ALIPAY) {
                val name = event.className?.toString()
                if (event.windowId >= 0 &&
                    (name == AutoBillParser.ALIPAY_NFC_RESULT || name == AutoBillParser.ALIPAY_MSP_CONTAINER)
                ) {
                    setAlipayCheckoutWindow(event.windowId to name)
                } else if (name != null &&
                    (name.startsWith("com.alipay.") || name.startsWith("${AutoBillParser.PKG_ALIPAY}."))
                ) {
                    setAlipayCheckoutWindow(null)
                }
            }
        }
        val checkoutWindow = alipayCheckoutWindow
        if (pkg == AutoBillParser.PKG_ALIPAY && checkoutWindow?.first == event.windowId) {
            if (readAlipayCheckout(event.windowId, event) ||
                checkoutWindow.second == AutoBillParser.ALIPAY_NFC_RESULT
            ) return
        }
        val texts = ArrayList<String>(48)
        val receiptNodes = if (pkg == AutoBillParser.PKG_ALIPAY) mutableListOf<Pair<Rect, String>>() else null
        val root = rootInActiveWindow
        if (root?.packageName?.toString() == pkg &&
            (event.windowId < 0 || root.windowId == event.windowId)
        ) {
            collectWindowTexts(root, texts, receiptNodes)
        } else {
            for (win in windows) {
                if (win.id != event.windowId) continue
                val windowRoot = win.root
                if (windowRoot?.packageName?.toString() == pkg) {
                    collectWindowTexts(windowRoot, texts, receiptNodes)
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
                alipayRows = receiptNodes?.takeIf { it.isNotEmpty() }?.let(::paymentReceiptRows),
            )
        } else false
        merchantCapture.onEvent(event, recognized, texts + eventTexts)
    }

    private fun setAlipayCheckoutWindow(window: Pair<Int, String>?) {
        if (window == alipayCheckoutWindow) return
        alipayCheckoutWindow = window
        alipayCheckoutRecognized = false
    }

    internal fun readAlipayCheckout(
        windowId: Int,
        event: AccessibilityEvent? = null,
        noticeAmount: Double? = null,
    ): Boolean {
        if (alipayCheckoutWindow?.first != windowId) return false
        val root = rootInActiveWindow ?: return false
        if (root.windowId != windowId || root.packageName?.toString() != AutoBillParser.PKG_ALIPAY) return false
        val frame = Rect().also(root::getBoundsInScreen)
        if (frame.isEmpty) return false
        val bottom = frame.centerY()
        if (event?.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {
            val sourceBounds = event.source?.let { node -> Rect().also(node::getBoundsInScreen) }
            if (sourceBounds != null && !sourceBounds.isEmpty && sourceBounds.top >= bottom) {
                return alipayCheckoutRecognized
            }
        }
        val nodes = mutableListOf<Pair<Rect, String>>()
        collectReceiptNodes(root, bottom, nodes, 0)
        val matched = AutoBillParser.handleAlipayCheckoutControls(this, paymentReceiptRows(nodes), noticeAmount)
        if (matched) alipayCheckoutRecognized = true
        return matched
    }

    private fun collectReceiptNodes(
        node: AccessibilityNodeInfo,
        bottom: Int,
        out: MutableList<Pair<Rect, String>>,
        depth: Int,
    ) {
        if (depth > 28 || out.size >= 120) return
        val bounds = Rect().also(node::getBoundsInScreen)
        if (!bounds.isEmpty && bounds.top >= bottom) return
        if (node.isVisibleToUser && !bounds.isEmpty && bounds.centerY() < bottom) {
            receiptLabel(node)?.let { out.add(bounds to it) }
        }
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { collectReceiptNodes(it, bottom, out, depth + 1) }
        }
    }

    private fun receiptLabel(node: AccessibilityNodeInfo): String? =
        node.text?.toString()?.trim()?.takeIf(String::isNotEmpty)
            ?: node.contentDescription?.toString()?.trim()?.takeIf {
                node.childCount == 0 && it.isNotEmpty()
            }

    private fun collectWindowTexts(
        root: AccessibilityNodeInfo,
        texts: MutableList<String>,
        receiptNodes: MutableList<Pair<Rect, String>>?,
    ) {
        val receiptBottom = if (receiptNodes != null) {
            Rect().also(root::getBoundsInScreen).takeUnless(Rect::isEmpty)?.centerY()
        } else null
        collectTexts(root, texts, 0, receiptNodes, receiptBottom)
    }

    private fun collectTexts(
        node: AccessibilityNodeInfo?,
        out: MutableList<String>,
        depth: Int,
        receiptNodes: MutableList<Pair<Rect, String>>? = null,
        receiptBottom: Int? = null,
    ) {
        if (node == null || depth > 28 || out.size >= 120) return
        val text = node.text?.toString()?.trim()
        if (!text.isNullOrEmpty()) {
            out.add(text)
        }
        val desc = node.contentDescription?.toString()?.trim()
        if (!desc.isNullOrEmpty() && desc != text) {
            out.add(desc)
        }
        if (receiptNodes != null && receiptBottom != null && node.isVisibleToUser) {
            val label = receiptLabel(node)
            if (label != null) {
                val bounds = Rect()
                node.getBoundsInScreen(bounds)
                if (!bounds.isEmpty && bounds.centerY() < receiptBottom) {
                    receiptNodes.add(bounds to label)
                }
            }
        }
        for (i in 0 until node.childCount) {
            collectTexts(node.getChild(i), out, depth + 1, receiptNodes, receiptBottom)
        }
    }

    override fun onInterrupt() = Unit

    companion object {
        private var activeService: AutoBookkeepingAccessibilityService? = null

        internal fun requestPaymentScreen(
            notice: AutoBillParser.PaymentNotice, onMiss: (() -> Unit)? = null,
        ): Boolean = activeService?.notificationCapture?.request(notice, onMiss) == true

        @Volatile
        var connected = false
            private set
    }
}
