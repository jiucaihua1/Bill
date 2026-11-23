package top.talyra42.verifin

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.util.concurrent.Executors

/** Keeps a bounded window-event trace on the phone for offline Debug diagnosis. */
internal object WechatPaymentCodeTrace {
    private val writer = Executors.newSingleThreadExecutor()
    private const val FILE_NAME = "wechat-payment-code-windows.log"
    private const val MAX_LINES = 128
    private const val TAG = "VeriAutoBill"

    fun record(context: Context, event: String) {
        if (!BuildConfig.DEBUG) return
        val line = "${System.currentTimeMillis()} $event"
        val path = File(context.filesDir, FILE_NAME)
        Log.i(TAG, event)
        writer.execute {
            val file = AtomicFile(path)
            try {
                val previous = try {
                    file.openRead().bufferedReader().use { it.readLines() }
                } catch (_: FileNotFoundException) {
                    emptyList()
                }
                val next = (previous.takeLast(MAX_LINES - 1) + line).joinToString("\n", postfix = "\n")
                val output = file.startWrite()
                try {
                    output.write(next.toByteArray(Charsets.UTF_8))
                    file.finishWrite(output)
                } catch (error: IOException) {
                    file.failWrite(output)
                    throw error
                }
            } catch (error: IOException) {
                Log.w(TAG, "Could not retain WeChat payment code event: ${error.javaClass.simpleName}")
            }
        }
    }
}
