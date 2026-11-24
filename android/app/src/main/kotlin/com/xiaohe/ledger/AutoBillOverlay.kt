package com.xiaohe.ledger

import android.app.Dialog
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import android.view.Display
import android.view.Window
import android.view.WindowManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodChannel

/** Hosts the shared Flutter confirmation sheet above the current Android app. */
object AutoBillOverlay {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var ledgerChannel: MethodChannel
    private var ready = false
    private var mainForeground = false
    private var current: Review? = null

    private class Review(
        val context: Context,
        val id: String,
        val fallback: () -> Unit,
        val sample: Map<String, Any>? = null,
        var previewResult: ((Boolean) -> Unit)? = null,
    ) {
        var dialog: Dialog? = null
        var view: FlutterView? = null
        var renderer: FlutterEngine? = null
        var screenOffReceiver: BroadcastReceiver? = null
        var displayed = false
        var saving = false
        var saved = false

        fun draft() = sample ?: AutoBillParser.readDraft(context, id)

        fun reportPreview(shown: Boolean) {
            previewResult?.invoke(shown)
            previewResult = null
        }
    }

    fun attach(context: Context, engine: FlutterEngine) {
        ledgerChannel = MethodChannel(engine.dartExecutor.binaryMessenger, "verifin/auto_bill_overlay")
        ledgerChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ledgerReady" -> {
                    ready = true
                    current?.takeIf { it.dialog == null }?.let(::prepare)
                    result.success(null)
                }
                "updateNotificationSummary" -> {
                    val summary = call.arguments as? String
                    if (summary != null) AutoCapturePermissions.updateNotificationSummary(context, summary)
                    result.success(null)
                }
                "wechatNoteSupplement" -> {
                    val id = call.arguments as? String
                    result.success(id?.let(AutoBillParser::wechatNoteSupplement))
                }
                else -> result.notImplemented()
            }
        }
    }

    internal fun enrichWechatNote(supplement: Map<String, Any>) {
        handler.post {
            if (ready && ::ledgerChannel.isInitialized) {
                ledgerChannel.invokeMethod("enrichWechatNote", supplement)
            }
        }
    }

    fun setMainForeground(foreground: Boolean) {
        mainForeground = foreground
        if (foreground) {
            current?.takeUnless { it.saving || it.sample != null }?.let { close(it, notify = !it.saved) }
        }
    }

    fun clear() {
        current?.takeUnless { it.saving }?.let { close(it) }
    }

    fun deliver(context: Context, id: String, fallback: () -> Unit) {
        handler.post {
            if (AutoBillParser.readDraft(context, id) == null) return@post
            if (current != null || !canDisplay(context)) {
                Log.i("VeriAutoBill", "Overlay unavailable, using notification")
                fallback()
                return@post
            }
            start(Review(context.applicationContext, id, fallback))
        }
    }

    fun preview(context: Context, finished: (Boolean) -> Unit) {
        val sample = AutoBillParser.previewWechatTransfer()
        if (sample == null || current != null || !canDisplay(context, preview = true)) {
            finished(false)
            return
        }
        start(Review(
            context.applicationContext, "", {}, sample + mapOf("type" to "expense"), finished,
        ))
    }

    private fun start(review: Review) {
        current = review
        try {
            LedgerFlutterRuntime.get(review.context, fromOverlay = true)
            if (ready) prepare(review)
        } catch (error: RuntimeException) {
            Log.w("VeriAutoBill", "Ledger runtime unavailable: ${error.javaClass.simpleName}")
            close(review, notify = true)
        }
        handler.postDelayed({
            if (current === review && !review.displayed && !review.saving) {
                Log.w("VeriAutoBill", "Confirmation overlay did not render")
                close(review, notify = true)
            }
        }, 10_000L)
    }

    private fun canDisplay(context: Context, preview: Boolean = false): Boolean {
        if (!Settings.canDrawOverlays(context) || AppLockPreferences.isEnabled(context) ||
            !preview && (mainForeground || !AutoBillParser.isAutoEnabled(context))
        ) return false
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        val power = context.getSystemService(PowerManager::class.java)
        return keyguard?.isKeyguardLocked == false && power?.isInteractive == true
    }

    private fun prepare(review: Review) {
        val draft = review.draft()
        val preview = review.sample != null
        if (draft == null || !canDisplay(review.context, preview)) {
            close(review, notify = draft != null)
            return
        }
        ledgerChannel.invokeMethod("prepare", draft, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (current !== review) return
                val ledger = result as? Map<*, *>
                if (ledger == null || (!preview && ledger["baseCurrency"] != "CNY") ||
                    !canDisplay(review.context, preview)
                ) {
                    Log.i("VeriAutoBill", "Ledger requires the full editor")
                    close(review, notify = true)
                    return
                }
                try {
                    show(review, draft, ledger)
                } catch (error: RuntimeException) {
                    Log.w("VeriAutoBill", "Confirmation window failed: ${error.javaClass.simpleName}")
                    close(review, notify = true)
                }
            }

            override fun error(code: String, message: String?, details: Any?) =
                close(review, notify = true)

            override fun notImplemented() = close(review, notify = true)
        })
    }

    private fun show(review: Review, draft: Map<String, Any>, ledger: Map<*, *>) {
        @Suppress("DEPRECATION")
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val base = review.context
        val display = base.getSystemService(DisplayManager::class.java)?.getDisplay(Display.DEFAULT_DISPLAY)
        val context = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && display != null) {
            base.createDisplayContext(display).createWindowContext(type, null)
        } else {
            base
        }
        // This engine only draws the sheet. It never registers storage plugins or opens SQLite.
        val engine = FlutterEngine(base, null, false)
        review.renderer = engine
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "verifin/auto_bill_overlay_view")
        channel.setMethodCallHandler { call, result ->
            if (current !== review) {
                result.error("closed", null, null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "load" -> result.success(mapOf(
                    "draft" to (review.draft() ?: draft), "ledger" to ledger, "preview" to (review.sample != null),
                ))
                "save" -> save(review, call.arguments as? Map<*, *>, result)
                "close" -> {
                    result.success(null)
                    handler.post { if (!review.saving) close(review, discard = true) }
                }
                else -> result.notImplemented()
            }
        }
        val surface = FlutterTextureView(context).apply { isOpaque = false }
        val view = FlutterView(context, surface).apply { filterTouchesWhenObscured = true }
        review.view = view
        view.addOnFirstFrameRenderedListener(object : FlutterUiDisplayListener {
            override fun onFlutterUiDisplayed() {
                review.displayed = true
                Log.i("VeriAutoBill", "Confirmation overlay rendered")
                review.reportPreview(true)
            }
            override fun onFlutterUiNoLongerDisplayed() = Unit
        })
        val dialog = object : Dialog(context) {
            @Deprecated("Android dispatches legacy dialog back here")
            override fun onBackPressed() {
                if (!review.saving) channel.invokeMethod("back", null)
            }
        }
        review.dialog = dialog
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE)
        val window = checkNotNull(dialog.window)
        window.setType(type)
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE or WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        window.setDimAmount(0.25f)
        @Suppress("DEPRECATION")
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
        dialog.setContentView(view)
        dialog.setCanceledOnTouchOutside(false)
        dialog.setOnCancelListener { if (!review.saving) close(review, discard = true) }
        dialog.show()
        window.setLayout(WindowManager.LayoutParams.MATCH_PARENT, WindowManager.LayoutParams.MATCH_PARENT)
        view.attachToFlutterEngine(engine)
        view.requestFocus()
        engine.lifecycleChannel.appIsResumed()
        val bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath()
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(bundle, "autoBillOverlayMain"))

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (review.saving) dialog.hide() else close(review, notify = !review.saved)
            }
        }
        ContextCompat.registerReceiver(
            base, receiver, IntentFilter(Intent.ACTION_SCREEN_OFF), ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        review.screenOffReceiver = receiver
        handler.postDelayed({
            if (current === review && !review.saving) close(review, notify = !review.saved)
        }, 120_000L)
    }

    private fun save(review: Review, changes: Map<*, *>?, result: MethodChannel.Result) {
        val draft = AutoBillParser.readDraft(review.context, review.id)
        if (review.sample != null || review.saving || changes == null ||
            draft == null || !canDisplay(review.context)
        ) {
            result.success(false)
            return
        }
        review.saving = true
        ledgerChannel.invokeMethod("save", changes + mapOf(
            "id" to review.id,
            "occurredAt" to draft.getValue("occurredAt"),
            "sourcePackage" to draft.getValue("sourcePackage"),
        ), object : MethodChannel.Result {
            override fun success(value: Any?) = finish(value == true)
            override fun error(code: String, message: String?, details: Any?) = finish(false)
            override fun notImplemented() = finish(false)

            private fun finish(saved: Boolean) {
                if (saved) AutoBillParser.consumeDraft(review.context, review.id)
                if (current !== review) return
                review.saving = false
                review.saved = saved
                result.success(saved)
                if (!saved && !canDisplay(review.context)) close(review, notify = true)
            }
        })
    }

    private fun close(review: Review, notify: Boolean = false, discard: Boolean = false) {
        if (current !== review) return
        current = null
        review.reportPreview(false)
        review.screenOffReceiver?.let { receiver ->
            runCatching { review.context.unregisterReceiver(receiver) }.onFailure {
                Log.w("VeriAutoBill", "Could not unregister overlay receiver", it)
            }
        }
        review.view?.detachFromFlutterEngine()
        review.dialog?.dismiss()
        review.renderer?.destroy()
        if (review.sample == null) {
            if (discard) AutoBillParser.consumeDraft(review.context, review.id)
            if (notify && review.draft() != null) review.fallback()
        }
    }
}
