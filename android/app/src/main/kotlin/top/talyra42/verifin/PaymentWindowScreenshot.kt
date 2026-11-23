package top.talyra42.verifin

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Point
import android.graphics.Rect
import android.os.Build
import android.util.Log
import android.view.accessibility.AccessibilityWindowInfo
import androidx.annotation.RequiresApi
import com.google.android.gms.tasks.Task
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognizer

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal fun capturePaymentWindow(
    service: AccessibilityService,
    windowId: Int,
    isCurrent: () -> Boolean,
    onImage: (Bitmap?) -> Unit,
) = capturePaymentScreenshot(
    isCurrent,
    capture = { service.takeScreenshotOfWindow(windowId, service.mainExecutor, it) },
    onImage = onImage,
)

@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
internal fun captureVisiblePaymentRegion(
    service: AccessibilityService,
    displayId: Int,
    isCurrent: () -> Boolean,
    region: Rect,
    onImage: (Bitmap?) -> Unit,
) = capturePaymentScreenshot(
    isCurrent,
    region,
    capture = { service.takeScreenshot(displayId, service.mainExecutor, it) },
    onImage = onImage,
)

private fun capturePaymentScreenshot(
    isCurrent: () -> Boolean,
    region: Rect? = null,
    capture: (AccessibilityService.TakeScreenshotCallback) -> Unit,
    onImage: (Bitmap?) -> Unit,
) {
    try {
        capture(object : AccessibilityService.TakeScreenshotCallback {
            override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                val buffer = result.hardwareBuffer
                val image = try {
                    if (!isCurrent()) {
                        null
                    } else {
                        val hardware = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                        try {
                            val image = hardware?.copy(Bitmap.Config.ARGB_8888, false)
                            if (region == null || image == null) {
                                image
                            } else {
                                try {
                                    maskPaymentScreenshot(image, region)
                                } finally {
                                    image.recycle()
                                }
                            }
                        } finally {
                            hardware?.recycle()
                        }
                    }
                } catch (error: RuntimeException) {
                    Log.w("VeriAutoBill", "Could not convert payment window screenshot: ${error.javaClass.simpleName}")
                    null
                } finally {
                    buffer.close()
                }
                onImage(image)
            }

            override fun onFailure(errorCode: Int) {
                Log.w("VeriAutoBill", "Payment window screenshot unavailable: $errorCode")
                onImage(null)
            }
        })
    } catch (error: SecurityException) {
        Log.w("VeriAutoBill", "Payment window screenshot permission unavailable")
        onImage(null)
    }
}

internal fun maskPaymentScreenshot(image: Bitmap, region: Rect): Bitmap? {
    if (!Rect(0, 0, image.width, image.height).contains(region) || region.isEmpty) return null
    return Bitmap.createBitmap(image.width, image.height, Bitmap.Config.ARGB_8888).apply {
        eraseColor(Color.WHITE)
        Canvas(this).drawBitmap(image, region, region, null)
    }
}

internal fun visiblePaymentContentRegion(
    target: AccessibilityWindowInfo, windows: List<AccessibilityWindowInfo>, size: Point,
): Rect? {
    val above = windows.filter { it.layer > target.layer }
        .map { it.type to Rect().also(it::getBoundsInScreen) }
    val statusBarBottom = above.asSequence().filter { (type, bounds) ->
        type == AccessibilityWindowInfo.TYPE_SYSTEM && bounds.top == 0 &&
            bounds.width() >= size.x * 9 / 10 && bounds.bottom <= size.y / 8
    }.maxOfOrNull { (_, bounds) -> bounds.bottom } ?: 0
    val region = Rect(
        size.x / 7, maxOf(size.y / 19, statusBarBottom),
        size.x * 6 / 7, size.y * 9 / 20,
    )
    val targetBounds = Rect().also(target::getBoundsInScreen)
    if (targetBounds.width() < size.x * 9 / 10 ||
        targetBounds.height() < size.y * 4 / 5 || !targetBounds.contains(region) ||
        above.any { (_, bounds) -> Rect.intersects(region, bounds) }
    ) return null
    return region
}

internal fun paymentAmountRegion(bitmap: Bitmap, includeLowerAmount: Boolean): Rect = Rect(
    bitmap.width / 5,
    bitmap.height / 8,
    bitmap.width * 4 / 5,
    if (includeLowerAmount) bitmap.height * 3 / 8 else bitmap.height * 5 / 16,
)

internal fun paymentAmountLines(result: Text, region: Rect): String =
    result.textBlocks.asSequence().flatMap { it.lines.asSequence() }
        .filter { line ->
            val bounds = line.boundingBox ?: return@filter false
            region.contains(bounds.centerX(), bounds.centerY())
        }
        .sortedBy { it.boundingBox?.top }
        .joinToString("\n") { it.text }

internal fun recognizeScaledPaymentAmount(
    context: Context, bitmap: Bitmap, region: Rect, recognizer: TextRecognizer,
): Task<String> {
    val crop = Bitmap.createBitmap(bitmap, region.left, region.top, region.width(), region.height())
    val scaled = try {
        Bitmap.createScaledBitmap(crop, crop.width * 2 / 3, crop.height * 2 / 3, true)
    } finally {
        crop.recycle()
    }
    try {
        return recognizer.process(InputImage.fromBitmap(scaled, 0))
            .continueWith(context.mainExecutor) { task ->
                try {
                    if (task.isSuccessful) task.result.text else ""
                } finally {
                    scaled.recycle()
                }
            }
    } catch (error: RuntimeException) {
        scaled.recycle()
        throw error
    }
}
