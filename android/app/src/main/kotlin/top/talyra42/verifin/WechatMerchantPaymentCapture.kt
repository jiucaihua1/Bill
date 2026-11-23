package top.talyra42.verifin

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.Rect
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityWindowInfo
import android.view.Display
import androidx.annotation.RequiresApi
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import top.talyra42.verifin.AutoBillParser.WechatTransferOcrStatus

/** Reads one authorized WeChat payment result window when its text is unavailable. */
internal class WechatMerchantPaymentCapture(private val service: AccessibilityService) {
    private val handler = Handler(Looper.getMainLooper())
    private var session: Checkout? = null

    private data class OcrResult(val text: String, val amountText: String? = null)
    private data class VisiblePaymentRegion(val displayId: Int, val bounds: Rect)

    private enum class CheckoutKind { MERCHANT, SCAN, PERSONAL_QR, TRANSFER, PAYMENT_CODE }

    private class Checkout(val orderWindowId: Int, val kind: CheckoutKind) {
        val startedAt = SystemClock.elapsedRealtime()
        val transfer get() = kind == CheckoutKind.TRANSFER
        val scan get() = kind == CheckoutKind.SCAN || kind == CheckoutKind.PERSONAL_QR
        var codeWindowId: Int? = null
        var lastCodeContentEvent: Triple<Int, Int, Long>? = null
        var result: ResultWindow? = null
        var recognized = false
        var lastCandidateCaptureAt = 0L
        var controlsWindowId: Int? = null
        var sawSuccess = false
        var sawReturnToMerchant = false
    }

    private class ResultWindow(val id: Int) {
        var retried = false
        var doneControlSeen = false
        var sawResultControls = false
        var capturePending = false
        var captureRunning = false
        var contentChanged = false
    }

    fun onEvent(event: AccessibilityEvent, recognized: Boolean, visibleTexts: List<String>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (event.packageName?.toString() != WECHAT || event.windowId < 0) return

        val stateChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        val className = event.className?.toString()
        val entry = checkoutKind(className)
        if (stateChanged && entry != null) {
            if (entry == CheckoutKind.PAYMENT_CODE && !BuildConfig.DEBUG) return
            if (session?.orderWindowId != event.windowId || session?.kind != entry) {
                reset()
                if (entry != CheckoutKind.PAYMENT_CODE) AutoBillParser.beginWechatPayment()
                session = Checkout(event.windowId, entry)
                if (entry == CheckoutKind.PAYMENT_CODE) {
                    WechatPaymentCodeTrace.record(service, "entry window=${event.windowId} class=$className")
                } else if (entry != CheckoutKind.TRANSFER) {
                    Log.i(TAG, "WeChat merchant checkout: ${entry.name}")
                }
            }
            return
        }

        val checkout = session ?: run {
            if (BuildConfig.DEBUG && stateChanged && className == PAGE_FRAGMENT_CONTAINER) {
                // The preceding short-lived entry may be absent from the accessibility events.
                session = Checkout(event.windowId, CheckoutKind.PAYMENT_CODE).apply {
                    codeWindowId = event.windowId
                }
                WechatPaymentCodeTrace.record(service, "unclassified display window=${event.windowId}")
            }
            return
        }
        val timeout = if (checkout.kind == CheckoutKind.PAYMENT_CODE) PAYMENT_CODE_TRACE_TIMEOUT_MS else CHECKOUT_TIMEOUT_MS
        if (SystemClock.elapsedRealtime() - checkout.startedAt >= timeout) {
            reset()
            return
        }
        if (checkout.kind == CheckoutKind.PAYMENT_CODE) {
            logPaymentCodeWindowEvent(checkout, event)
            return
        }
        // TalkBack focus events can expose success-page controls even when the
        // result container does not send the expected window-state event.
        if (checkout.controlsWindowId != event.windowId) {
            checkout.controlsWindowId = event.windowId
            checkout.sawSuccess = false
            checkout.sawReturnToMerchant = false
        }
        checkout.sawSuccess = checkout.sawSuccess || visibleTexts.any { it.contains("支付成功") }
        checkout.sawReturnToMerchant = checkout.sawReturnToMerchant ||
            visibleTexts.any { it.contains("返回商家") }
        val successControls = if (checkout.transfer) {
            AutoBillParser.hasWechatTransferResultMarkers(visibleTexts)
        } else {
            checkout.sawSuccess && (checkout.sawReturnToMerchant ||
                (checkout.scan && "完成" in visibleTexts))
        }
        if (checkout.kind != CheckoutKind.MERCHANT) {
            onCandidateEvent(checkout, event, recognized, visibleTexts, successControls)
            return
        }
        if (checkout.result?.id == event.windowId && recognized) checkout.recognized = true
        val resultWindowChanged = stateChanged && className == RESULT_CONTAINER
        if ((!resultWindowChanged && !successControls) || checkout.result != null) return
        val result = ResultWindow(event.windowId)
        checkout.result = result
        checkout.recognized = recognized
        if (recognized) return
        Log.i(TAG, "WeChat merchant result detected: ${checkout.kind.name}")
        handler.postDelayed({ takeResultScreenshot(checkout, result) }, RESULT_SETTLE_MS)
    }

    private fun checkoutKind(className: String?): CheckoutKind? = when (className) {
        ORDER_HANDLER, PAY_ENTRY -> CheckoutKind.MERCHANT
        MERCHANT_SCAN -> CheckoutKind.SCAN
        QR_REMITTANCE -> CheckoutKind.PERSONAL_QR
        REMITTANCE -> CheckoutKind.TRANSFER
        PAYMENT_CODE_ENTRY, PAYMENT_CODE_SHORTCUT -> CheckoutKind.PAYMENT_CODE
        else -> null
    }

    private fun logPaymentCodeWindowEvent(checkout: Checkout, event: AccessibilityEvent) {
        val windowId = event.windowId
        val stateChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        val className = event.className?.toString()
        if (stateChanged &&
            (className == WECHAT_HOME || className == WECHAT_WALLET || className?.startsWith(WECHAT_COLLECT) == true)
        ) {
            WechatPaymentCodeTrace.record(service, "exit window=$windowId")
            reset()
            return
        }
        if (checkout.codeWindowId == null) {
            if (!stateChanged || className != PAGE_FRAGMENT_CONTAINER) return
            checkout.codeWindowId = windowId
            WechatPaymentCodeTrace.record(service, "display window=$windowId")
            return
        }
        if (!stateChanged) {
            if (event.eventType != AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) return
            val now = SystemClock.elapsedRealtime()
            val previous = checkout.lastCodeContentEvent
            if (previous?.first == windowId && previous.second == event.contentChangeTypes &&
                now - previous.third < CANDIDATE_CAPTURE_INTERVAL_MS
            ) return
            checkout.lastCodeContentEvent = Triple(windowId, event.contentChangeTypes, now)
        }
        val windowClass = className?.takeIf { it.startsWith("$WECHAT.") } ?: "view"
        val eventName = if (stateChanged) "state" else "content"
        val sameWindow = checkout.codeWindowId == windowId
        val activeWindow = service.rootInActiveWindow?.windowId
        WechatPaymentCodeTrace.record(
            service,
            "$eventName window=$windowId sameWindow=$sameWindow active=$activeWindow " +
                "class=$windowClass changes=${event.contentChangeTypes}",
        )
    }

    fun onPaymentCodeWindowsChanged(event: AccessibilityEvent) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        val checkout = session?.takeIf { it.kind == CheckoutKind.PAYMENT_CODE } ?: return
        val codeWindow = checkout.codeWindowId ?: return
        if (SystemClock.elapsedRealtime() - checkout.startedAt >= PAYMENT_CODE_TRACE_TIMEOUT_MS) return
        val root = service.rootInActiveWindow
        if (event.windowId != codeWindow && root?.packageName?.toString() != WECHAT) return
        WechatPaymentCodeTrace.record(
            service,
            "windows window=${event.windowId} sameWindow=${event.windowId == codeWindow} " +
                "active=${root?.windowId} changes=${event.windowChanges}",
        )
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun onCandidateEvent(
        checkout: Checkout, event: AccessibilityEvent, recognized: Boolean, visibleTexts: List<String>,
        successControls: Boolean,
    ) {
        if (checkout.recognized) return
        val windowId = event.windowId
        val stateChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        // Confirmation and successful result screens can use the same class or window ID.
        val resultCandidate = stateChanged && event.className?.toString() == PAGE_FRAGMENT_CONTAINER
        if ((resultCandidate || successControls) && checkout.result?.id != windowId) {
            checkout.result = ResultWindow(windowId)
            Log.i(TAG, "WeChat payment candidate window changed: ${checkout.kind.name}")
        }
        val result = checkout.result?.takeIf { it.id == windowId } ?: return
        if (recognized) {
            checkout.recognized = true
            return
        }
        val doneAppeared = !result.doneControlSeen && visibleTexts.any { it.trim() == "完成" }
        if (doneAppeared) result.doneControlSeen = true
        val successAppeared = successControls && !result.sawResultControls
        if (successAppeared) result.sawResultControls = true
        val contentChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            (event.contentChangeTypes == 0 || event.contentChangeTypes and PAYMENT_CONTENT_CHANGES != 0)
        if (!stateChanged && !contentChanged && !doneAppeared && !successAppeared) return
        if (result.captureRunning) {
            result.contentChanged = true
        } else if (!result.capturePending) {
            result.retried = false
            scheduleCandidateCapture(checkout, result)
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun scheduleCandidateCapture(checkout: Checkout, result: ResultWindow, useVisibleRegion: Boolean = false) {
        if (result.capturePending) return
        result.capturePending = true
        val sinceCapture = SystemClock.elapsedRealtime() - checkout.lastCandidateCaptureAt
        val delay = maxOf(RESULT_SETTLE_MS, CANDIDATE_CAPTURE_INTERVAL_MS - sinceCapture)
        handler.postDelayed({
            result.capturePending = false
            if (!isCurrent(checkout, result)) return@postDelayed
            result.captureRunning = true
            result.contentChanged = false
            checkout.lastCandidateCaptureAt = SystemClock.elapsedRealtime()
            takeResultScreenshot(checkout, result, useVisibleRegion)
        }, delay)
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun finishCandidateCapture(checkout: Checkout, result: ResultWindow, retry: Boolean = false) {
        if (checkout.kind == CheckoutKind.MERCHANT || session !== checkout || checkout.result !== result) return
        result.captureRunning = false
        if (checkout.recognized) return
        if (retry && !result.retried) {
            result.retried = true
            scheduleCandidateCapture(checkout, result, useVisibleRegion = checkout.kind == CheckoutKind.PERSONAL_QR)
        } else if (result.contentChanged) {
            result.retried = false
            scheduleCandidateCapture(checkout, result)
        }
    }

    fun reset() {
        session = null
        handler.removeCallbacksAndMessages(null)
    }

    private fun isCurrent(checkout: Checkout, result: ResultWindow): Boolean {
        if (session !== checkout || checkout.recognized || checkout.result !== result) return false
        if (SystemClock.elapsedRealtime() - checkout.startedAt >= CHECKOUT_TIMEOUT_MS) return false
        if (!AutoBillParser.isAutoEnabled(service) || !AutoBillParser.isPlatformEnabled(service, WECHAT)) {
            return false
        }
        if (service.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true) return false
        val root = service.rootInActiveWindow
        if (root != null) return root.windowId == result.id && root.packageName?.toString() == WECHAT
        // Some merchant result windows expose their ID before they expose a node tree.
        return !checkout.transfer && service.windows.any { window ->
            window.id == result.id && window.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                (window.isActive || window.isFocused)
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun takeResultScreenshot(checkout: Checkout, result: ResultWindow, useVisibleRegion: Boolean = false) {
        if (!isCurrent(checkout, result)) {
            if (checkout.kind != CheckoutKind.MERCHANT) {
                finishCandidateCapture(checkout, result)
            } else if (session === checkout && !checkout.recognized) {
                Log.i(TAG, "WeChat merchant result window no longer available")
                retryMerchantResult(checkout, result)
            }
            return
        }
        val windowId = result.id
        val visibleRegion = if (useVisibleRegion) visiblePersonalPaymentRegion(windowId) else null
        if (useVisibleRegion && visibleRegion == null) {
            Log.i(TAG, "Visible WeChat personal QR payment region unavailable")
        }
        if (visibleRegion != null) {
            Log.i(TAG, "Reading visible WeChat personal QR payment region")
            captureVisiblePaymentRegion(
                service, visibleRegion.displayId,
                {
                    isCurrent(checkout, result) &&
                        visiblePersonalPaymentRegion(windowId) == visibleRegion
                },
                visibleRegion.bounds,
            ) { image ->
                if (image != null) recognize(checkout, result, image)
                else finishCandidateCapture(checkout, result)
            }
            return
        }
        Log.i(TAG, "Reading WeChat payment result with local OCR")
        capturePaymentWindow(service, windowId, { isCurrent(checkout, result) }) { image ->
            if (image != null) recognize(checkout, result, image)
            else finishCandidateCapture(checkout, result)
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    @Suppress("DEPRECATION")
    private fun visiblePersonalPaymentRegion(windowId: Int): VisiblePaymentRegion? {
        val windows = service.windows
        val target = windows.firstOrNull {
            it.id == windowId && it.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                (it.isActive || it.isFocused) && it.displayId == Display.DEFAULT_DISPLAY
        } ?: return null
        val display = service.getSystemService(DisplayManager::class.java)
            ?.getDisplay(target.displayId) ?: return null
        val size = Point().also(display::getRealSize)
        if (size.x <= 0 || size.y <= size.x) return null
        val region = visiblePaymentContentRegion(target, windows, size) ?: return null
        return VisiblePaymentRegion(target.displayId, region)
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun recognize(checkout: Checkout, candidate: ResultWindow, bitmap: Bitmap) {
        val recognizer = try {
            TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        } catch (error: RuntimeException) {
            bitmap.recycle()
            finishCandidateCapture(checkout, candidate)
            Log.w(TAG, "WeChat payment OCR unavailable: ${error.javaClass.simpleName}")
            return
        }
        try {
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .continueWithTask(service.mainExecutor) { task ->
                    val full = task.result
                    when {
                        !isCurrent(checkout, candidate) -> Tasks.forResult(OcrResult(full.text))
                        checkout.transfer -> recognizeTransferResult(bitmap, full, recognizer)
                        else -> recognizeMerchantResult(bitmap, full, recognizer, checkout, candidate.doneControlSeen)
                    }
                }
                .addOnCompleteListener(service.mainExecutor) { task ->
                    var retryCandidate = false
                    try {
                        when {
                            !task.isSuccessful -> Log.w(TAG, "WeChat payment OCR failed")
                            isCurrent(checkout, candidate) -> {
                                val result = task.result
                                checkout.recognized = AutoBillParser.handleWechatResultScreenshot(
                                    service, result.text, checkout.transfer, result.amountText,
                                    merchantScan = checkout.scan,
                                    personalQrResult = checkout.kind == CheckoutKind.PERSONAL_QR,
                                    doneControlSeen = candidate.doneControlSeen,
                                )
                                if (!checkout.recognized) {
                                    if (checkout.transfer) {
                                        val status = AutoBillParser.wechatTransferOcrStatus(result.text)
                                        val reason = if (status == WechatTransferOcrStatus.MATCHED) {
                                            "MISSING_UNIQUE_AMOUNT"
                                        } else {
                                            status.name
                                        }
                                        Log.i(TAG, "WeChat transfer OCR did not match: $reason")
                                    } else {
                                        val hasStatus = AutoBillParser.hasWechatMerchantResultMarkers(
                                            result.text, checkout.scan,
                                            checkout.kind == CheckoutKind.PERSONAL_QR, candidate.doneControlSeen,
                                        )
                                        Log.i(TAG, "WeChat merchant OCR did not match: " +
                                            if (hasStatus) "MISSING_UNIQUE_AMOUNT" else "MISSING_RESULT_MARKERS")
                                        val compact = result.text.lineSequence().map { line ->
                                            line.filterNot(Char::isWhitespace)
                                        }.filter(String::isNotEmpty).toList()
                                        val doneInImage = "完成" in compact
                                        if (checkout.kind == CheckoutKind.PERSONAL_QR && hasStatus && doneInImage) {
                                            candidate.doneControlSeen = true
                                        }
                                        Log.i(TAG, "WeChat OCR input: ${bitmap.width}x${bitmap.height}, " +
                                            "lines=${compact.size}, payment=${compact.any { "支付" in it }}, " +
                                            "success=${compact.any { "成功" in it }}, done=$doneInImage")
                                    }
                                    if (checkout.kind == CheckoutKind.MERCHANT) {
                                        retryMerchantResult(checkout, candidate)
                                    } else {
                                        retryCandidate = true
                                    }
                                }
                            }
                        }
                    } finally {
                        bitmap.recycle()
                        recognizer.close()
                        finishCandidateCapture(checkout, candidate, retryCandidate)
                    }
                }
        } catch (error: RuntimeException) {
            bitmap.recycle()
            recognizer.close()
            finishCandidateCapture(checkout, candidate)
            Log.w(TAG, "WeChat payment OCR failed to start: ${error.javaClass.simpleName}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun retryMerchantResult(checkout: Checkout, result: ResultWindow) {
        if (result.retried) return
        result.retried = true
        handler.postDelayed({ takeResultScreenshot(checkout, result) }, MERCHANT_RETRY_MS)
    }

    private fun recognizeMerchantResult(
        bitmap: Bitmap, full: Text, recognizer: TextRecognizer, checkout: Checkout, doneControlSeen: Boolean,
    ): Task<OcrResult> {
        val region = paymentAmountRegion(bitmap, checkout.kind == CheckoutKind.PERSONAL_QR)
        val amountText = paymentAmountLines(full, region)
        if (!AutoBillParser.hasWechatMerchantResultMarkers(
                full.text, checkout.scan, checkout.kind == CheckoutKind.PERSONAL_QR, doneControlSeen,
            ) ||
            AutoBillParser.wechatMerchantResultAmount(amountText, cropped = true) != null
        ) {
            return Tasks.forResult(OcrResult(full.text, amountText))
        }
        return recognizeScaledPaymentAmount(service, bitmap, region, recognizer)
            .continueWith(service.mainExecutor) { OcrResult(full.text, it.result) }
    }

    private fun recognizeTransferResult(
        bitmap: Bitmap, full: Text, recognizer: TextRecognizer,
    ): Task<OcrResult> {
        val status = AutoBillParser.wechatTransferOcrStatus(full.text)
        val needsStatus = status != WechatTransferOcrStatus.MATCHED
        if (status == WechatTransferOcrStatus.REJECTED ||
            (!needsStatus && AutoBillParser.wechatTransferOcrAmount(full.text) != null)
        ) {
            return Tasks.forResult(OcrResult(full.text))
        }
        val top = if (needsStatus) {
            // The status title, pending receipt and amount share the upper transfer card.
            0
        } else {
            val anchor = full.textBlocks.asSequence().flatMap { it.lines.asSequence() }
                .singleOrNull { AutoBillParser.isWechatTransferPendingLine(it.text) }
                ?.boundingBox ?: return Tasks.forResult(OcrResult(full.text))
            anchor.bottom.coerceIn(0, bitmap.height)
        }
        val height = if (needsStatus) {
            bitmap.height / 2
        } else {
            (bitmap.height * 3 / 20).coerceAtMost(bitmap.height - top)
        }
        if (height <= 0) return Tasks.forResult(OcrResult(full.text, ""))
        val crop = Bitmap.createBitmap(bitmap, bitmap.width / 5, top, bitmap.width * 3 / 5, height)
        try {
            return recognizer.process(InputImage.fromBitmap(crop, 0))
                .continueWith(service.mainExecutor) { task ->
                    try {
                        val text = if (task.isSuccessful) task.result.text else ""
                        // Keep the full window's failure or merchant markers in scope.
                        OcrResult(full.text + "\n" + text, text)
                    } finally {
                        crop.recycle()
                    }
                }
        } catch (error: RuntimeException) {
            crop.recycle()
            throw error
        }
    }

    private companion object {
        const val TAG = "VeriAutoBill"
        const val WECHAT = "com.tencent.mm"
        const val PAY_ENTRY = "com.tencent.mm.plugin.base.stub.WXPayEntryActivity"
        const val ORDER_HANDLER = "com.tencent.mm.plugin.wallet_index.ui.OrderHandlerUI"
        const val RESULT_CONTAINER = "com.tencent.mm.plugin.lite.ui.WxaLiteAppTransparentLiteUI"
        const val MERCHANT_SCAN = "com.tencent.mm.plugin.remittance.ui.WalletMerchantPayUI"
        const val QR_REMITTANCE = "com.tencent.mm.plugin.remittance.ui.RemittanceBusiUI"
        const val REMITTANCE = "com.tencent.mm.plugin.remittance.ui.RemittanceUI"
        const val PAYMENT_CODE_ENTRY = "com.tencent.mm.plugin.offline.ui.WalletOfflineEntranceUI"
        const val PAYMENT_CODE_SHORTCUT = "com.tencent.mm.plugin.offline.ui.WalletOfflineCoinPurseUI"
        const val WECHAT_HOME = "com.tencent.mm.ui.LauncherUI"
        const val WECHAT_WALLET = "com.tencent.mm.plugin.mall.ui.MallIndexUIv2"
        const val WECHAT_COLLECT = "com.tencent.mm.plugin.collect.ui."
        const val PAGE_FRAGMENT_CONTAINER = "com.tencent.mm.framework.app.UIPageFragmentActivity"
        const val RESULT_SETTLE_MS = 650L
        const val CANDIDATE_CAPTURE_INTERVAL_MS = 1_000L
        const val PAYMENT_CONTENT_CHANGES = AccessibilityEvent.CONTENT_CHANGE_TYPE_SUBTREE or
            AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT or AccessibilityEvent.CONTENT_CHANGE_TYPE_PANE_APPEARED
        const val MERCHANT_RETRY_MS = 700L
        const val CHECKOUT_TIMEOUT_MS = 90_000L
        const val PAYMENT_CODE_TRACE_TIMEOUT_MS = 300_000L
    }
}
