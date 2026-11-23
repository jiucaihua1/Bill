package top.talyra42.verifin

import android.app.KeyguardManager
import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.RequiresApi
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.TextRecognizer
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import top.talyra42.verifin.AutoBillParser.PaymentNotice

/** A fresh payment notice can request OCR of the matching foreground window. */
internal class NotificationPaymentCapture(private val service: AutoBookkeepingAccessibilityService) {
    private val handler = Handler(Looper.getMainLooper())
    private var attempt: Attempt? = null
    private var newestWindow: WindowChange? = null
    private var lastAttempt: Attempt? = null

    private data class WindowChange(val pkg: String, val id: Int, val time: Long)
    private data class Attempt(
        val notice: PaymentNotice, val windowId: Int, val started: Long, val onMiss: (() -> Unit)?,
    )

    fun onWindowChanged(pkg: String, id: Int) {
        if (id < 0) return
        val previous = newestWindow
        if (previous?.pkg != pkg || previous.id != id) {
            newestWindow = WindowChange(pkg, id, SystemClock.elapsedRealtime())
        }
    }

    fun request(notice: PaymentNotice, onMiss: (() -> Unit)?): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE || attempt != null) return false
        val id = activeWindow(notice)
        if (id == null) {
            Log.i(TAG, "Payment notification did not have a matching foreground window")
            return false
        }
        if (readAlipayControls(notice, id)) return true
        val now = SystemClock.elapsedRealtime()
        if (notice.amount == null) {
            val window = newestWindow
            if (window?.id != id || window.pkg != notice.target || now - window.time > RECENT_WINDOW_MS) return false
        }
        val previous = lastAttempt
        if (previous?.windowId == id && previous.notice.target == notice.target &&
            (previous.notice.amount == notice.amount || previous.notice.amount == null || notice.amount == null) &&
            now - previous.started < RECENT_WINDOW_MS
        ) return false
        val next = Attempt(notice, id, now, onMiss)
        attempt = next
        lastAttempt = next
        handler.postDelayed({ capture(next) }, SETTLE_MS)
        if (onMiss != null) handler.postDelayed({ finish(next) }, FALLBACK_MS)
        return true
    }

    fun reset() {
        attempt?.let { finish(it) }
        newestWindow = null
        lastAttempt = null
        handler.removeCallbacksAndMessages(null)
    }

    private fun activeWindow(notice: PaymentNotice): Int? {
        if (!AutoBillParser.isAutoEnabled(service) ||
            !AutoBillParser.isPlatformEnabled(service, notice.source) ||
            !AutoBillParser.isPlatformEnabled(service, notice.target) ||
            service.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked == true
        ) return null
        val root = service.rootInActiveWindow ?: return null
        return root.windowId.takeIf { it >= 0 && root.packageName?.toString() == notice.target }
    }

    private fun current(request: Attempt): Boolean =
        attempt === request && activeWindow(request.notice) == request.windowId

    private fun readAlipayControls(notice: PaymentNotice, windowId: Int): Boolean =
        notice.target == AutoBillParser.PKG_ALIPAY &&
            service.readAlipayCheckout(windowId, noticeAmount = notice.amount)

    @RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
    private fun capture(request: Attempt) {
        if (!current(request)) {
            finish(request)
            return
        }
        if (readAlipayControls(request.notice, request.windowId)) {
            finish(request, matched = true)
            return
        }
        Log.i(TAG, "Payment notification requested foreground OCR")
        capturePaymentWindow(service, request.windowId, { current(request) }) { bitmap ->
            if (bitmap == null) finish(request) else recognize(request, bitmap)
        }
    }

    private fun recognize(request: Attempt, bitmap: Bitmap) {
        val model = try {
            TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        } catch (error: RuntimeException) {
            bitmap.recycle()
            finish(request)
            Log.w(TAG, "Payment notification OCR unavailable: ${error.javaClass.simpleName}")
            return
        }
        try {
            recognizeNotificationPaymentImage(service, bitmap, request.notice, model) { current(request) }
                .addOnCompleteListener(service.mainExecutor) { task ->
                    var matched = false
                    try {
                        if (task.isSuccessful && current(request)) {
                            val (text, amountText, receiptRows) = task.result
                            matched = AutoBillParser.handleNotificationPaymentScreen(
                                service, request.notice, text, amountText, receiptRows,
                            )
                            Log.i(TAG, if (matched) "Payment notification screen matched" else "Payment notification screen did not match")
                        }
                    } finally {
                        bitmap.recycle()
                        model.close()
                        finish(request, matched)
                    }
                }
        } catch (error: RuntimeException) {
            bitmap.recycle()
            model.close()
            finish(request)
            Log.w(TAG, "Payment notification OCR failed to start: ${error.javaClass.simpleName}")
        }
    }

    private fun finish(request: Attempt, matched: Boolean = false) {
        if (attempt !== request) return
        attempt = null
        if (!matched) request.onMiss?.invoke()
    }

    private companion object {
        const val TAG = "VeriAutoBill"
        const val SETTLE_MS = 1_000L
        const val FALLBACK_MS = 4_000L
        const val RECENT_WINDOW_MS = 8_000L
    }
}

internal data class NotificationPaymentText(val text: String, val amountText: String, val receiptRows: String?)

internal fun recognizeNotificationPaymentImage(
    context: Context, bitmap: Bitmap, notice: PaymentNotice, model: TextRecognizer,
    isCurrent: () -> Boolean,
): Task<NotificationPaymentText> = model.process(InputImage.fromBitmap(bitmap, 0))
    .continueWithTask(context.mainExecutor) { task ->
        val result = task.result
        val receiptRows = if (notice.target == AutoBillParser.PKG_ALIPAY) alipayReceiptRows(result) else null
        val region = paymentAmountRegion(bitmap, includeLowerAmount = true)
        val amountText = paymentAmountLines(result, region)
        if (isCurrent() &&
            AutoBillParser.hasNotificationPaymentScreenStatus(notice, result.text) &&
            AutoBillParser.wechatMerchantResultAmount(amountText, cropped = true) == null
        ) {
            recognizeScaledPaymentAmount(context, bitmap, region, model)
                .continueWith(context.mainExecutor) { NotificationPaymentText(result.text, it.result, receiptRows) }
        } else {
            Tasks.forResult(NotificationPaymentText(result.text, amountText, receiptRows))
        }
    }
