package top.talyra42.verifin

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/** The foreground Activity and the overlay share the sole writable ledger controller. */
object LedgerFlutterRuntime {
    const val ENGINE_ID = "verifin-ledger"

    fun isRunning(): Boolean = FlutterEngineCache.getInstance().contains(ENGINE_ID)

    fun get(context: Context, fromOverlay: Boolean = false): FlutterEngine {
        val cache = FlutterEngineCache.getInstance()
        cache.get(ENGINE_ID)?.let { return it }
        val runtime = FlutterEngine(context.applicationContext)
        AutoBillOverlay.attach(runtime)
        val entrypoint = DartExecutor.DartEntrypoint.createDefault()
        if (fromOverlay) {
            runtime.dartExecutor.executeDartEntrypoint(entrypoint, listOf("auto-bill-overlay"))
        } else {
            runtime.dartExecutor.executeDartEntrypoint(entrypoint)
        }
        cache.put(ENGINE_ID, runtime)
        return runtime
    }
}
