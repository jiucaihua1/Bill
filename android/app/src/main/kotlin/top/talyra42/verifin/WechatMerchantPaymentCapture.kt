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

    private enum class CheckoutKind { MERCHANT, SCAN, PERSONAL_QR, TRANSFER }

    private class Checkout(val orderWindowId: Int, val kind: CheckoutKind) {
        val startedAt = SystemClock.elapsedRealtime()
        val transfer get() = kind == CheckoutKind.TRANSFER
        val scan get() = kind == CheckoutKind.SCAN || kind == CheckoutKind.PERSONAL_QR
        var resultWindowId: Int? = null
        var recognized = false
        var retried = false
        var doneControlSeen = false
        var personalCapturePending = false
        var personalCaptureRunning = false
        var personalContentChanged = false
        var lastPersonalCaptureAt = 0L
        var controlsWindowId: Int? = null
        var sawSuccess = false
        var sawReturnToMerchant = false
    }

    fun onEvent(event: AccessibilityEvent, recognized: Boolean, visibleTexts: List<String>) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (event.packageName?.toString() != WECHAT || event.windowId < 0) return

        val stateChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        val className = event.className?.toString()
        val entry = when (className) {
            ORDER_HANDLER, PAY_ENTRY -> CheckoutKind.MERCHANT
            MERCHANT_SCAN -> CheckoutKind.SCAN
            QR_REMITTANCE -> CheckoutKind.PERSONAL_QR
            REMITTANCE -> CheckoutKind.TRANSFER
            else -> null
        }
        if (stateChanged && entry != null) {
            if (session?.orderWindowId != event.windowId || session?.kind != entry) {
                reset()
                AutoBillParser.beginWechatPayment()
                session = Checkout(event.windowId, entry)
                if (entry != CheckoutKind.TRANSFER) Log.i(TAG, "WeChat merchant checkout: ${entry.name}")
            }
            return
        }

        val checkout = session ?: return
        if (SystemClock.elapsedRealtime() - checkout.startedAt >= CHECKOUT_TIMEOUT_MS) {
            reset()
            return
        }
        if (checkout.kind == CheckoutKind.PERSONAL_QR) {
            onPersonalQrEvent(checkout, event, recognized, visibleTexts)
            return
        }
        if (checkout.resultWindowId == event.windowId && recognized) checkout.recognized = true
        val resultWindowChanged = stateChanged && when (checkout.kind) {
            CheckoutKind.TRANSFER, CheckoutKind.SCAN, CheckoutKind.PERSONAL_QR ->
                className == PAGE_FRAGMENT_CONTAINER && event.windowId != checkout.orderWindowId
            CheckoutKind.MERCHANT -> className == RESULT_CONTAINER
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
        if ((!resultWindowChanged && !successControls) || checkout.resultWindowId != null) return
        checkout.resultWindowId = event.windowId
        checkout.recognized = recognized
        if (recognized) return
        if (!checkout.transfer) Log.i(TAG, "WeChat merchant result detected: ${checkout.kind.name}")
        val windowId = event.windowId
        handler.postDelayed({ takeResultScreenshot(checkout, windowId) }, RESULT_SETTLE_MS)
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun onPersonalQrEvent(
        checkout: Checkout, event: AccessibilityEvent, recognized: Boolean, visibleTexts: List<String>,
    ) {
        if (checkout.recognized) return
        val windowId = event.windowId
        val stateChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
        val candidateChanged = stateChanged && event.className?.toString() == PAGE_FRAGMENT_CONTAINER &&
            windowId != checkout.orderWindowId && checkout.resultWindowId != windowId
        if (candidateChanged) {
            checkout.resultWindowId = windowId
            checkout.doneControlSeen = false
            checkout.retried = false
            checkout.personalCapturePending = false
            checkout.personalCaptureRunning = false
            checkout.personalContentChanged = false
            Log.i(TAG, "WeChat personal QR candidate window changed")
        }
        if (checkout.resultWindowId != windowId) return
        if (recognized) {
            checkout.recognized = true
            return
        }
        val doneAppeared = !checkout.doneControlSeen && visibleTexts.any { it.trim() == "完成" }
        if (doneAppeared) checkout.doneControlSeen = true
        val contentChanged = event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED &&
            (event.contentChangeTypes == 0 || event.contentChangeTypes and PAYMENT_CONTENT_CHANGES != 0)
        if (!stateChanged && !contentChanged && !doneAppeared) return
        if (checkout.personalCaptureRunning) {
            checkout.personalContentChanged = true
        } else if (!checkout.personalCapturePending) {
            checkout.retried = false
            schedulePersonalCapture(checkout, windowId, useVisibleRegion = false)
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun schedulePersonalCapture(checkout: Checkout, windowId: Int, useVisibleRegion: Boolean) {
        if (checkout.personalCapturePending) return
        checkout.personalCapturePending = true
        val sinceCapture = SystemClock.elapsedRealtime() - checkout.lastPersonalCaptureAt
        val delay = maxOf(RESULT_SETTLE_MS, PERSONAL_CAPTURE_INTERVAL_MS - sinceCapture)
        handler.postDelayed({
            if (session !== checkout || checkout.resultWindowId != windowId) return@postDelayed
            checkout.personalCapturePending = false
            if (!isCurrent(checkout, windowId)) return@postDelayed
            checkout.personalCaptureRunning = true
            checkout.personalContentChanged = false
            checkout.lastPersonalCaptureAt = SystemClock.elapsedRealtime()
            takeResultScreenshot(checkout, windowId, useVisibleRegion)
        }, delay)
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun finishPersonalCapture(checkout: Checkout, windowId: Int, allowVisibleRetry: Boolean = false) {
        if (checkout.kind != CheckoutKind.PERSONAL_QR ||
            session !== checkout || checkout.resultWindowId != windowId
        ) return
        checkout.personalCaptureRunning = false
        if (checkout.recognized) return
        if (allowVisibleRetry && !checkout.retried) {
            checkout.retried = true
            schedulePersonalCapture(checkout, windowId, useVisibleRegion = true)
        } else if (checkout.personalContentChanged) {
            checkout.retried = false
            schedulePersonalCapture(checkout, windowId, useVisibleRegion = false)
        }
    }

    fun reset() {
        session = null
        handler.removeCallbacksAndMessages(null)
    }

    private fun isCurrent(checkout: Checkout, windowId: Int): Boolean {
        if (session !== checkout || checkout.recognized || checkout.resultWindowId != windowId) return false
        if (SystemClock.elapsedRealtime() - checkout.startedAt >= CHECKOUT_TIMEOUT_MS) return false
        if (!AutoBillParser.isAutoEnabled(service) || !AutoBillParser.isPlatformEnabled(service, WECHAT)) {
            return false
        }
        if (service.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true) return false
        val root = service.rootInActiveWindow
        if (root != null) return root.windowId == windowId && root.packageName?.toString() == WECHAT
        // Some merchant result windows expose their ID before they expose a node tree.
        return !checkout.transfer && service.windows.any { window ->
            window.id == windowId && window.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                (window.isActive || window.isFocused)
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun takeResultScreenshot(checkout: Checkout, windowId: Int, useVisibleRegion: Boolean = false) {
        if (!isCurrent(checkout, windowId)) {
            if (checkout.kind == CheckoutKind.PERSONAL_QR) {
                finishPersonalCapture(checkout, windowId)
            } else if (!checkout.transfer && session === checkout && !checkout.recognized) {
                Log.i(TAG, "WeChat merchant result window no longer available")
                retryMerchantResult(checkout, windowId)
            }
            return
        }
        val visibleRegion = if (useVisibleRegion) visiblePersonalPaymentRegion(windowId) else null
        if (useVisibleRegion && visibleRegion == null) {
            Log.i(TAG, "Visible WeChat personal QR payment region unavailable")
        }
        if (visibleRegion != null) {
            Log.i(TAG, "Reading visible WeChat personal QR payment region")
            captureVisiblePaymentRegion(
                service, visibleRegion.displayId,
                {
                    isCurrent(checkout, windowId) &&
                        visiblePersonalPaymentRegion(windowId) == visibleRegion
                },
                visibleRegion.bounds,
            ) { image ->
                if (image != null) recognize(checkout, windowId, image)
                else finishPersonalCapture(checkout, windowId)
            }
            return
        }
        Log.i(TAG, "Reading WeChat payment result with local OCR")
        capturePaymentWindow(service, windowId, { isCurrent(checkout, windowId) }) { image ->
            if (image != null) recognize(checkout, windowId, image)
            else finishPersonalCapture(checkout, windowId)
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
    private fun recognize(checkout: Checkout, windowId: Int, bitmap: Bitmap) {
        val recognizer = try {
            TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        } catch (error: RuntimeException) {
            bitmap.recycle()
            finishPersonalCapture(checkout, windowId)
            Log.w(TAG, "WeChat payment OCR unavailable: ${error.javaClass.simpleName}")
            return
        }
        try {
            recognizer.process(InputImage.fromBitmap(bitmap, 0))
                .continueWithTask(service.mainExecutor) { task ->
                    val full = task.result
                    when {
                        !isCurrent(checkout, windowId) -> Tasks.forResult(OcrResult(full.text))
                        checkout.transfer -> recognizeTransferResult(bitmap, full, recognizer)
                        else -> recognizeMerchantResult(bitmap, full, recognizer, checkout)
                    }
                }
                .addOnCompleteListener(service.mainExecutor) { task ->
                    var allowVisibleRetry = false
                    try {
                        when {
                            !task.isSuccessful -> Log.w(TAG, "WeChat payment OCR failed")
                            isCurrent(checkout, windowId) -> {
                                val result = task.result
                                checkout.recognized = AutoBillParser.handleWechatResultScreenshot(
                                    service, result.text, checkout.transfer, result.amountText,
                                    merchantScan = checkout.scan,
                                    personalQrResult = checkout.kind == CheckoutKind.PERSONAL_QR,
                                    doneControlSeen = checkout.doneControlSeen,
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
                                            checkout.kind == CheckoutKind.PERSONAL_QR, checkout.doneControlSeen,
                                        )
                                        Log.i(TAG, "WeChat merchant OCR did not match: " +
                                            if (hasStatus) "MISSING_UNIQUE_AMOUNT" else "MISSING_RESULT_MARKERS")
                                        val compact = result.text.lineSequence().map { line ->
                                            line.filterNot(Char::isWhitespace)
                                        }.filter(String::isNotEmpty).toList()
                                        val doneInImage = "完成" in compact
                                        if (checkout.kind == CheckoutKind.PERSONAL_QR && hasStatus && doneInImage) {
                                            checkout.doneControlSeen = true
                                        }
                                        Log.i(TAG, "WeChat OCR input: ${bitmap.width}x${bitmap.height}, " +
                                            "lines=${compact.size}, payment=${compact.any { "支付" in it }}, " +
                                            "success=${compact.any { "成功" in it }}, done=$doneInImage")
                                        if (checkout.kind == CheckoutKind.PERSONAL_QR) {
                                            allowVisibleRetry = true
                                        } else {
                                            retryMerchantResult(checkout, windowId)
                                        }
                                    }
                                }
                            }
                        }
                    } finally {
                        bitmap.recycle()
                        recognizer.close()
                        finishPersonalCapture(checkout, windowId, allowVisibleRetry)
                    }
                }
        } catch (error: RuntimeException) {
            bitmap.recycle()
            recognizer.close()
            finishPersonalCapture(checkout, windowId)
            Log.w(TAG, "WeChat payment OCR failed to start: ${error.javaClass.simpleName}")
        }
    }

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun retryMerchantResult(checkout: Checkout, windowId: Int) {
        if (checkout.retried) return
        checkout.retried = true
        handler.postDelayed({ takeResultScreenshot(checkout, windowId) }, MERCHANT_RETRY_MS)
    }

    private fun recognizeMerchantResult(
        bitmap: Bitmap, full: Text, recognizer: TextRecognizer, checkout: Checkout,
    ): Task<OcrResult> {
        val region = paymentAmountRegion(bitmap, checkout.kind == CheckoutKind.PERSONAL_QR)
        val amountText = paymentAmountLines(full, region)
        if (!AutoBillParser.hasWechatMerchantResultMarkers(
                full.text, checkout.scan, checkout.kind == CheckoutKind.PERSONAL_QR, checkout.doneControlSeen,
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
        const val PAGE_FRAGMENT_CONTAINER = "com.tencent.mm.framework.app.UIPageFragmentActivity"
        const val RESULT_SETTLE_MS = 650L
        const val PERSONAL_CAPTURE_INTERVAL_MS = 1_000L
        const val PAYMENT_CONTENT_CHANGES = AccessibilityEvent.CONTENT_CHANGE_TYPE_SUBTREE or
            AccessibilityEvent.CONTENT_CHANGE_TYPE_TEXT or AccessibilityEvent.CONTENT_CHANGE_TYPE_PANE_APPEARED
        const val MERCHANT_RETRY_MS = 700L
        const val CHECKOUT_TIMEOUT_MS = 90_000L
    }
}
