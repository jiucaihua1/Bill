package top.talyra42.verifin

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import java.text.Normalizer
import java.util.UUID
import org.json.JSONObject
import kotlin.math.roundToLong

/**
 * 从已授权来源识别收支，产生待用户确认的本地草稿。
 */
object AutoBillParser {
    internal const val PKG_WECHAT = "com.tencent.mm"
    internal const val PKG_ALIPAY = "com.eg.android.AlipayGphone"
    internal const val PKG_CCB = "com.chinamworld.main"
    private const val PKG_JD = "com.jingdong.app.mall"
    private const val PKG_PDD = "com.xunmeng.pinduoduo"

    private const val MONEY = """(?:\d{1,3}(?:[,，]\d{3})+|\d+)(?:\.\d{1,2})?"""
    private val labeledAmount = Regex(
        """(?:转账金额|付款金额|支付金额|收款金额|实付金额|到账金额)\s*[:：]?\s*[¥￥]?\s*[+\-−]?\s*($MONEY)(?![\d.,，])""",
    )
    private val currencyAmount = Regex(
        """[¥￥]\s*[+\-−]?\s*($MONEY)(?![\d.,，])|(?<![\d.,，])($MONEY)\s*元""",
    )
    private val standaloneAmount = Regex("""[+\-−]?\s*($MONEY)""")
    private val pinduoduoPaidAmount = Regex(
        """(?<!预计)(?<!预估)(?:实付款?(?:金额)?|实际支付)[\s:：,，]*[¥￥]?\s*($MONEY)(?![\d.]|[,，]\s*\d)""",
    )
    private val pinduoduoCompleted = Regex("""(?<!未)(?:支付成功|付款成功|已付款|已支付(?!金额))""")
    private val pinduoduoUnpaid = Regex("""待(?:付款|支付)|(?:尚)?未(?:付款|支付)|支付失败|预[计估]\s*实付""")
    private val wechatOutgoing = Regex("""(?:你|您)\s*向[^\n]{1,40}转账|转账给(?!你)|给[^\n]{1,30}转账""")
    private val wechatIncoming = Regex("""向\s*你\s*转账|转账给你|收到[^\n]{0,25}转账""")
    private val wechatWaitConfirm = Regex("""待[^\n]{1,20}(?:确认)?收款""")
    private val pendingTransferLine = Regex("""待\s*[^\n]{1,40}?确认收款""")
    private val ocrPaymentSuccessLine = Regex("""[^\p{IsHan}]*支付成功[^\p{IsHan}]*""")
    private val ocrTransferAmountLine = Regex("""[¥￥]?\s*($MONEY)""")
    private val ocrSpacing = Regex("""[\p{Zs}\t]+""")
    private val merchantPaymentAmountLine = Regex("""[¥￥]($MONEY)|($MONEY)元""")
    private val merchantCropCurrencyAmount = Regex("""[¥￥]($MONEY)(?![\d.,，])""")
    private val merchantDecimalSeparator = Regex("""(?<=\d)[·•。](?=\d)""")
    private val paymentNoticeStatus = Regex("""(?:支付|付款|扣款|消费)成功|(?:支付|付款|消费)通知|支付完成""")
    private val paymentNoticeExcluded = Regex("""待支付|待付款|未支付|未付款|支付失败|付款失败|扣款失败|请支付|退款|退还|验证码|转账|收款成功|入账通知|撤销""")
    private val bankDebitAmount = Regex(
        """(?:消费金额|支出金额|扣款金额|消费|支出|扣款)\s*[:：]?\s*(?:人民币\s*)?(?:[¥￥]\s*)?($MONEY)(?=\s*元|\s*人民币|\s*[,，。;；]|\s*$)""",
    )
    private val merchantField = Regex("""(?:商户名称|商户全称|收款方|交易对方|付款给|商家名称|商户)\s*[:：]\s*([^\n]+)""")
    private val orderNumberField = Regex("""(?:商户订单号|商户单号|订单编号|订单号)\s*[:：]?\s*([a-zA-Z0-9_-]{6,80})(?![a-zA-Z0-9_-])""")
    private val expenseCategories = mapOf(
        "dining" to Regex("星巴克|瑞幸|库迪|麦当劳|肯德基|海底捞|饿了么|美团外卖"),
        "transport" to Regex("滴滴出行|高德打车|曹操出行|铁路12306|地铁乘车|公交乘车"),
        "housing" to Regex("物业费|电费充值|燃气费|自来水费"),
        "entertainment" to Regex("哔哩哔哩|爱奇艺|腾讯视频|网易云音乐|猫眼电影"),
        "medical" to Regex("医院挂号|医院门诊|大药房|药店"),
    )
    private const val OUTGOING_CARD = """(?:你|您)\s*发起了?\s*一笔转账"""
    private val outgoingCardCaption = Regex(OUTGOING_CARD)
    private const val CARD_MONEY = """(?:[¥￥]\s*$MONEY|$MONEY\s*元)"""
    private val wechatOutgoingCard = Regex(
        """$CARD_MONEY[\s,，:：·]*$OUTGOING_CARD|$OUTGOING_CARD[\s,，:：·]*$CARD_MONEY""",
    )

    private const val DRAFT_TTL_MS = 15 * 60 * 1000L
    private const val DRAFT_LIMIT = 16
    private const val DRAFT_PREFIX = "pending_bill."
    private const val CROSS_PLATFORM_WINDOW_MS = 120_000L
    private const val CROSS_PLATFORM_LIMIT = 64
    private const val DETECTION_NOTIFICATION_ID = 4209
    const val DETECTION_CHANNEL_ID = "verifin_auto_bill_detected"
    private val recentBills = LinkedHashMap<String, Long>()
    private val lastScreenBills = mutableMapOf<String, Triple<String, Double, String?>>()
    private val unmatchedPurchases = mutableListOf<RecentPurchase>()

    data class ParsedBill(
        val amount: Double,
        val type: String,
        val note: String,
        val sourceLabel: String,
        val categoryKey: String = "",
        val shoppingPlatform: String? = null,
        val orderNumber: String? = null,
    )

    internal data class PaymentNotice(val source: String, val target: String, val amount: Double?)

    private data class RecentPurchase(
        val pkg: String,
        val platform: String,
        val cents: Long,
        val orderNumber: String?,
        val detectedAt: Long,
    )

    fun isAutoEnabled(context: Context): Boolean {
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getBoolean("auto_enabled", false)
    }

    fun isPlatformEnabled(context: Context, pkg: String): Boolean {
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val key = when (pkg) {
            PKG_WECHAT -> "flutter.verifin.auto_capture.app.wechat"
            PKG_ALIPAY -> "flutter.verifin.auto_capture.app.alipay"
            PKG_CCB -> "flutter.verifin.auto_capture.app.ccb"
            PKG_JD -> "flutter.verifin.auto_capture.app.jd"
            PKG_PDD -> "flutter.verifin.auto_capture.app.pdd"
            else -> return false
        }
        return flutterPrefs.getBoolean(key, pkg != PKG_CCB)
    }

    fun isPinduoduo(pkg: String): Boolean = pkg == PKG_PDD

    fun previewWechatTransfer(): Map<String, Any>? {
        val sample = "¥0.01\n你发起了一笔转账\n转账"
        val bill = parseWechat(sample, isScreen = true) ?: return null
        return mapOf("amount" to bill.amount, "note" to bill.note)
    }

    fun handleNotification(context: Context, pkg: String, title: String, text: String) {
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, pkg)) return
        val combined = "$title $text".trim()
        if (combined.isEmpty()) return
        val parsed = when (pkg) {
            PKG_WECHAT -> parseWechat(combined, isScreen = false)
            PKG_ALIPAY -> parseAlipay(combined, isScreen = false)
            PKG_JD -> parseEcommerce(combined, "京东")
            PKG_PDD -> parsePinduoduo(combined)
            else -> null
        } ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            ((pkg == PKG_WECHAT && parsed.note == "微信支付") ||
                (pkg == PKG_ALIPAY && parsed.note == "支付宝支付" && !combined.contains("转账成功")))
        ) return
        dispatchIfFresh(context, pkg, parsed)
    }

    internal fun paymentNotice(pkg: String, title: String, body: String): PaymentNotice? {
        if (pkg !in setOf(PKG_WECHAT, PKG_ALIPAY, PKG_CCB)) return null
        val text = Normalizer.normalize("$title\n$body", Normalizer.Form.NFKC)
        if (paymentNoticeExcluded.containsMatchIn(text)) return null
        if (pkg == PKG_CCB) {
            val amount = distinctAmounts(bankDebitAmount.findAll(text)).singleOrNull() ?: return null
            val alipay = text.contains("支付宝")
            val wechat = text.contains("微信支付") || text.contains("财付通")
            if (alipay && wechat) return null
            val target = when {
                alipay -> PKG_ALIPAY
                wechat -> PKG_WECHAT
                else -> PKG_CCB
            }
            return PaymentNotice(pkg, target, amount)
        }
        if (!paymentNoticeStatus.containsMatchIn(text)) return null
        val amounts = distinctAmounts(labeledAmount.findAll(text))
            .ifEmpty { distinctAmounts(currencyAmount.findAll(text)) }
        if (amounts.size > 1) return null
        return PaymentNotice(pkg, pkg, amounts.singleOrNull())
    }

    @Synchronized
    internal fun handleNotificationPaymentScreen(
        context: Context, notice: PaymentNotice, text: String, amountText: String,
    ): Boolean {
        val pkg = notice.target
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, notice.source) ||
            !isPlatformEnabled(context, pkg)
        ) return false
        val bill = parseNotificationPaymentScreen(notice, text, amountText) ?: return false
        if (pkg == PKG_CCB) {
            dispatchIfFresh(context, pkg, bill)
            return true
        }
        val amount = bill.amount
        val previous = lastScreenBills[pkg]
        if (previous?.first == bill.type && previous.second == amount &&
            (previous.third == null || bill.orderNumber == null || previous.third == bill.orderNumber)
        ) return true
        dispatchScreenBill(context, pkg, bill)
        return true
    }

    internal fun hasNotificationPaymentScreenStatus(notice: PaymentNotice, text: String): Boolean {
        val lines = text.lineSequence().map(::compactOcrLine).toList()
        if (lines.any { pendingTransferLine.matches(it) || isRejectedTransferLine(it) }) return false
        return when (notice.target) {
            PKG_WECHAT -> lines.any(ocrPaymentSuccessLine::matches) &&
                (notice.amount != null || lines.any { it == "完成" || it == "返回商家" })
            PKG_ALIPAY -> lines.any { it == "付款成功" || it == "支付成功" || it == "支付完成" }
            PKG_CCB -> lines.any { it == "支付成功" || it == "付款成功" || it == "扣款成功" || it == "消费成功" } &&
                lines.none { "支付宝" in it || "微信支付" in it || "财付通" in it }
            else -> false
        }
    }

    internal fun parseNotificationPaymentScreen(notice: PaymentNotice, text: String, amountText: String): ParsedBill? {
        if (!hasNotificationPaymentScreenStatus(notice, text)) return null
        val amount = wechatMerchantResultAmount(amountText, cropped = true) ?: return null
        if (notice.amount != null && amount != notice.amount) return null
        val name = when (notice.target) {
            PKG_WECHAT -> "微信"
            PKG_ALIPAY -> "支付宝"
            else -> "建设银行"
        }
        val normalized = text.lineSequence().map(::compactOcrLine).joinToString("\n")
        return purchaseBill(amount, normalized, "${name}支付", "${name}自动识别")
    }

    @Synchronized
    fun handleScreenTexts(
        context: Context, pkg: String, texts: List<String>, eventTexts: List<String>, windowChanged: Boolean,
    ): Boolean {
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, pkg)) return false
        fun parse(items: List<String>): ParsedBill? {
            if (items.isEmpty()) return null
            val combined = items.joinToString("\n")
            return when (pkg) {
                PKG_WECHAT -> parseWechat(combined, isScreen = true)
                PKG_ALIPAY -> parseAlipay(combined, isScreen = true)
                PKG_JD -> parseEcommerce(combined, "京东")
                PKG_PDD -> parsePinduoduo(combined)
                else -> null
            }
        }
        // A newly changed node can identify the actual transfer card when
        // older cards in the same chat have different amounts.
        val wechatTexts = if (pkg == PKG_WECHAT) texts + eventTexts else emptyList()
        val wechatPage = wechatTexts.joinToString("\n")
        val merchantReturn = wechatTexts.any { compactOcrLine(it) == "返回商家" }
        val merchantDone = wechatTexts.any { compactOcrLine(it) == "完成" } && !merchantReturn
        val parsed = if (hasWechatTransferResultMarkers(wechatTexts)) {
            parseWechatTransferResult(wechatPage)
        } else if ((merchantReturn || merchantDone) && hasWechatMerchantResultMarkers(wechatPage, merchantDone)) {
            parseWechatMerchantResult(wechatPage, null, merchantDone)
        } else if (isPinduoduo(pkg)) {
            parse(texts.ifEmpty { eventTexts })
        } else {
            val eventBill = parse(eventTexts)
            if (eventBill == null) {
                parse(texts)
            } else if (eventBill.type == "expense" && eventBill.note in setOf("微信支付", "支付宝支付")) {
                // The event source may have the amount but omit the merchant shown on the full page.
                val pageBill = parse(texts)
                pageBill?.takeIf {
                    it.type == eventBill.type && it.amount == eventBill.amount && it.note == eventBill.note
                } ?: eventBill
            } else eventBill
        }
        if (parsed == null) {
            if (windowChanged) lastScreenBills.remove(pkg)
            return false
        }
        dispatchScreenBill(context, pkg, parsed)
        return true
    }

    @Synchronized
    fun beginWechatPayment() {
        lastScreenBills.remove(PKG_WECHAT)
    }

    @Synchronized
    fun handleWechatResultScreenshot(
        context: Context, text: String, transfer: Boolean, amountText: String? = null,
        merchantScan: Boolean = false, personalQrResult: Boolean = false, doneControlSeen: Boolean = false,
    ): Boolean {
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, PKG_WECHAT)) return false
        val bill = if (transfer) {
            parseWechatTransferScreenshot(text, amountText)
        } else {
            parseWechatMerchantResult(text, amountText, merchantScan, personalQrResult, doneControlSeen)
        } ?: return false
        dispatchScreenBill(context, PKG_WECHAT, bill)
        return true
    }

    private fun dispatchScreenBill(context: Context, pkg: String, bill: ParsedBill) {
        val key = Triple(bill.type, bill.amount, bill.orderNumber)
        if (lastScreenBills.put(pkg, key) == key) return
        dispatchIfFresh(context, pkg, bill)
    }

    private fun distinctAmounts(matches: Sequence<MatchResult>): List<Double> = matches
            .mapNotNull { match ->
                match.groupValues.drop(1).firstOrNull { it.isNotEmpty() }
                    ?.replace(",", "")?.replace("，", "")?.toDoubleOrNull()
            }
            .filter { it > 0.0 && it < 1_000_000.0 }
            .distinct()
            .take(2)
            .toList()
    private fun extractAmount(text: String, allowStandalone: Boolean = false): Double? {
        val labeled = distinctAmounts(labeledAmount.findAll(text))
        if (labeled.isNotEmpty()) return labeled.singleOrNull()
        val withCurrency = distinctAmounts(currencyAmount.findAll(text))
        if (withCurrency.isNotEmpty()) return withCurrency.singleOrNull()
        if (!allowStandalone) return null
        return distinctAmounts(text.lineSequence().mapNotNull { line ->
            standaloneAmount.matchEntire(line.trim())?.takeIf { it.value.contains('.') }
        }).singleOrNull()
    }

    internal fun hasWechatMerchantResultMarkers(
        text: String, merchantScan: Boolean, personalQrResult: Boolean = false, doneControlSeen: Boolean = false,
    ): Boolean {
        val lines = text.lineSequence().map(::compactOcrLine).toList()
        if (lines.any { pendingTransferLine.matches(it) || isRejectedTransferLine(it) }) return false
        val successTitle = lines.any(ocrPaymentSuccessLine::matches)
        val personalQrDone = personalQrResult && (doneControlSeen || "完成" in lines)
        return (successTitle || personalQrDone) && (merchantScan || "返回商家" in lines)
    }

    internal fun wechatMerchantResultAmount(amountText: String, cropped: Boolean = false): Double? {
        val lines = amountText.lineSequence().map(::compactOcrLine)
            .map { it.replace(merchantDecimalSeparator, ".") }
            .filter(String::isNotEmpty)
            .toList()
        val candidates = distinctAmounts(lines.asSequence().mapIndexed { index, line ->
            if (line == "¥") line + lines.getOrNull(index + 1).orEmpty() else line
        }.flatMap { line ->
            val standalone = merchantPaymentAmountLine.matchEntire(line)
            when {
                standalone != null -> sequenceOf(standalone)
                cropped -> merchantCropCurrencyAmount.findAll(line)
                else -> emptySequence()
            }
        }.filter { match ->
            match.groupValues.drop(1).any { it.substringAfterLast('.', "").length == 2 }
        })
        if (candidates.isNotEmpty()) return candidates.singleOrNull()
        return if (cropped) wechatTransferOcrAmount(lines.joinToString("\n")) else null
    }

    private fun parseWechatMerchantResult(
        text: String, amountText: String?, merchantScan: Boolean,
        personalQrResult: Boolean = false, doneControlSeen: Boolean = false,
    ): ParsedBill? {
        if (!hasWechatMerchantResultMarkers(text, merchantScan, personalQrResult, doneControlSeen)) return null
        val amount = if (amountText != null) {
            wechatMerchantResultAmount(amountText, cropped = true)
        } else {
            wechatMerchantResultAmount(text) ?: distinctAmounts(labeledAmount.findAll(text)).singleOrNull()
        } ?: return null
        val compact = text.lineSequence().map(::compactOcrLine).joinToString("\n")
        return purchaseBill(amount, compact, note = "微信支付", sourceLabel = "微信自动识别")
    }

    fun hasWechatTransferResultMarkers(texts: List<String>): Boolean =
        "支付成功" in texts && "完成" in texts && texts.any(pendingTransferLine::matches)

    fun isWechatTransferPendingLine(text: String): Boolean =
        pendingTransferLine.matches(compactOcrLine(text))

    internal enum class WechatTransferOcrStatus {
        MATCHED, MISSING_PAYMENT_SUCCESS, MISSING_PENDING_RECEIPT, REJECTED
    }

    internal fun wechatTransferOcrStatus(text: String): WechatTransferOcrStatus {
        val lines = text.lineSequence().map(::compactOcrLine).toList()
        return when {
            lines.any { it.contains("返回商家") || isRejectedTransferLine(it) } ->
                WechatTransferOcrStatus.REJECTED
            lines.none(ocrPaymentSuccessLine::matches) -> WechatTransferOcrStatus.MISSING_PAYMENT_SUCCESS
            lines.none(pendingTransferLine::matches) -> WechatTransferOcrStatus.MISSING_PENDING_RECEIPT
            else -> WechatTransferOcrStatus.MATCHED
        }
    }

    fun wechatTransferOcrAmount(text: String): Double? =
        distinctAmounts(text.lineSequence().mapNotNull { line ->
            // OCR can drop the decimal point. Require cents on this result layout.
            ocrTransferAmountLine.matchEntire(compactOcrLine(line))
                ?.takeIf { it.groupValues[1].substringAfterLast('.', "").length == 2 }
        }).singleOrNull()

    private fun compactOcrLine(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFKC).replace(ocrSpacing, "").trim()

    private fun parseWechatTransferScreenshot(text: String, amountText: String?): ParsedBill? {
        if (wechatTransferOcrStatus(text) != WechatTransferOcrStatus.MATCHED) return null
        val amount = wechatTransferOcrAmount(amountText ?: text) ?: return null
        return pendingWechatTransfer(amount)
    }

    private fun parseWechatTransferResult(text: String): ParsedBill? {
        val lines = text.lineSequence().map(String::trim).toList()
        if (!hasWechatTransferResultMarkers(lines)) return null
        if (lines.any(::isRejectedTransferLine)) return null
        val amount = extractAmount(text, allowStandalone = true) ?: return null
        return pendingWechatTransfer(amount)
    }

    private fun isRejectedTransferLine(text: String): Boolean =
        text.contains("支付失败") || text.contains("转账失败") ||
            text.contains("已退还") || text.contains("已退款")

    private fun pendingWechatTransfer(amount: Double) =
        ParsedBill(amount, "expense", "微信转出（待对方收款）", "微信自动识别")

    private fun parseWechat(text: String, isScreen: Boolean): ParsedBill? {
        val transferPage = text.contains("微信转账") || text.contains("转账详情") ||
            text.contains("转账金额") || text.contains("转账说明")
        if (isScreen && !transferPage && outgoingCardCaption.containsMatchIn(text)) {
            val amount = wechatOutgoingCard.findAll(text)
                .mapNotNull { extractAmount(it.value) }
                .distinct()
                .take(2)
                .toList()
                .singleOrNull() ?: return null
            return ParsedBill(
                amount = amount, type = "expense", note = "微信转出", sourceLabel = "微信自动识别",
            )
        }
        val incoming = wechatIncoming.containsMatchIn(text)
        val received = text.contains("收款成功") || text.contains("已存入零钱") ||
            text.contains("微信收款到账") || incoming && (text.contains("已收款") || text.contains("已接收"))
        val hasOutgoingDirection = wechatOutgoing.containsMatchIn(text)
        val pendingOut = text.contains("待对方收款") ||
            (hasOutgoingDirection && !incoming && text.contains("待收款")) ||
            (transferPage && !incoming && wechatWaitConfirm.containsMatchIn(text))
        val outgoing = pendingOut || text.contains("发起了一笔转账") ||
            (hasOutgoingDirection &&
                (!isScreen || transferPage || text.contains("已收款") || text.contains("已接收"))) ||
            (!incoming && text.contains("转账成功"))
        val purchase = text.contains("支付成功") || text.contains("付款成功") ||
            text.contains("扣款成功") || text.contains("微信支付") && text.contains("支付金额")
        if (outgoing && (incoming || received)) return null
        val (type, note) = when {
            pendingOut -> "expense" to "微信转出（待对方收款）"
            outgoing -> "expense" to "微信转出"
            received -> "income" to "微信收款"
            incoming && (transferPage || !isScreen) -> "income" to "微信转入（待收款）"
            purchase -> "expense" to "微信支付"
            else -> return null
        }
        if (type == "expense" && note == "微信支付") {
            val amount = extractAmount(text, allowStandalone = isScreen) ?: return null
            return purchaseBill(amount, text, note, "微信自动识别")
        }
        val amount = extractAmount(text, allowStandalone = isScreen) ?: return null
        return ParsedBill(amount = amount, type = type, note = note, sourceLabel = "微信自动识别")
    }

    private fun parseAlipay(text: String, isScreen: Boolean): ParsedBill? {
        val isIncome = text.contains("收款成功") || text.contains("收款到账") ||
            text.contains("到账通知") || text.contains("向你付款")
        val isExpense = text.contains("付款成功") ||
            text.contains("支付成功") ||
            text.contains("扣款") ||
            text.contains("消费") ||
            text.contains("转账成功")
        if (isIncome == isExpense) return null
        val amount = extractAmount(text, allowStandalone = isScreen) ?: return null
        val type = if (isIncome) "income" else "expense"
        val note = if (isIncome) "支付宝收款" else "支付宝支付"
        if (!isIncome && !text.contains("转账成功")) {
            return purchaseBill(amount, text, note, "支付宝自动识别")
        }
        return ParsedBill(amount = amount, type = type, note = note, sourceLabel = "支付宝自动识别")
    }

    private fun parseEcommerce(text: String, appName: String): ParsedBill? {
        val isPay = text.contains("支付成功") || text.contains("付款成功") || text.contains("已付款")
        if (!isPay) return null
        val amount = extractAmount(text) ?: return null
        return purchaseBill(amount, text, "${appName}订单", "${appName}自动识别", appName)
    }

    private fun parsePinduoduo(text: String): ParsedBill? {
        val completed = pinduoduoCompleted.containsMatchIn(text)
        val paid = distinctAmounts(pinduoduoPaidAmount.findAll(text))
        if (paid.size > 1) return null
        if (!completed && (paid.isEmpty() || pinduoduoUnpaid.containsMatchIn(text))) return null
        val amount = paid.singleOrNull() ?: extractAmount(text) ?: return null
        return purchaseBill(amount, text, "拼多多订单", "拼多多自动识别", "拼多多")
    }

    private fun purchaseBill(
        amount: Double,
        text: String,
        note: String,
        sourceLabel: String,
        platform: String? = null,
    ): ParsedBill {
        val shoppingPlatform = platform ?: text.lineSequence()
            .map(String::trim)
            .plus(merchantField.findAll(text).map { it.groupValues[1].trim() })
            .mapNotNull {
                when (it) {
                    "拼多多", "拼多多商城" -> "拼多多"
                    "京东", "京东商城" -> "京东"
                    else -> null
                }
            }.distinct().singleOrNull()
        val category = expenseCategories.entries
            .filter { (_, keywords) -> keywords.containsMatchIn(text) }
            .singleOrNull()?.key
        return ParsedBill(
            amount = amount,
            type = "expense",
            note = note,
            sourceLabel = sourceLabel,
            categoryKey = category ?: if (shoppingPlatform != null) "shopping" else "",
            shoppingPlatform = shoppingPlatform,
            orderNumber = shoppingPlatform?.let {
                orderNumberField.findAll(text).map { match -> match.groupValues[1] }
                    .distinct().singleOrNull()
            },
        )
    }

    @Synchronized
    private fun rememberDraft(context: Context, pkg: String, bill: ParsedBill): String? {
        if (!isAutoEnabled(context)) return null
        val ageClock = SystemClock.elapsedRealtime()
        val key = "$pkg|${bill.type}|${bill.amount}|${bill.orderNumber.orEmpty()}"
        recentBills.entries.removeAll { ageClock - it.value >= 6_000L }
        if (recentBills.containsKey(key)) return null
        unmatchedPurchases.removeAll { ageClock - it.detectedAt >= CROSS_PLATFORM_WINDOW_MS }
        val purchase = bill.shoppingPlatform?.let {
            RecentPurchase(pkg, it, (bill.amount * 100).roundToLong(), bill.orderNumber, ageClock)
        }
        if (purchase != null) {
            val opposite = unmatchedPurchases.filter { other ->
                other.platform == purchase.platform && other.cents == purchase.cents &&
                    isShoppingApp(other.pkg) != isShoppingApp(pkg) &&
                    (other.orderNumber == null || purchase.orderNumber == null ||
                        other.orderNumber == purchase.orderNumber)
            }
            val match = opposite.singleOrNull { purchase.orderNumber != null && it.orderNumber == purchase.orderNumber }
                ?: opposite.singleOrNull()
            if (match != null) {
                unmatchedPurchases.remove(match)
                recentBills[key] = ageClock
                Log.i("VeriAutoBill", "Duplicate shopping payment suppressed across platforms")
                return null
            }
        }

        val now = System.currentTimeMillis()
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val manager = context.getSystemService(NotificationManager::class.java)
        val drafts = prefs.all.keys.filter { it.startsWith(DRAFT_PREFIX) }.sorted()
        val editor = prefs.edit()
        val current = drafts.filter { stored ->
            val createdAt = stored.removePrefix(DRAFT_PREFIX).substringBefore('-').toLongOrNull()
            val fresh = createdAt != null && now - createdAt in 0L until DRAFT_TTL_MS
            if (!fresh) {
                editor.remove(stored)
                manager?.cancel(stored.removePrefix(DRAFT_PREFIX), DETECTION_NOTIFICATION_ID)
            }
            fresh
        }
        for (stored in current.dropLast(DRAFT_LIMIT - 1)) {
            editor.remove(stored)
            manager?.cancel(stored.removePrefix(DRAFT_PREFIX), DETECTION_NOTIFICATION_ID)
        }
        val id = "$now-${UUID.randomUUID()}"
        val payload = JSONObject()
            .put("amount", bill.amount)
            .put("type", bill.type)
            .put("note", bill.note)
            .put("sourceLabel", bill.sourceLabel)
            .put("categoryKey", bill.categoryKey)
            .put("occurredAt", now)
        if (!editor.putString(DRAFT_PREFIX + id, payload.toString()).commit()) return null
        recentBills[key] = ageClock
        if (purchase != null) {
            if (unmatchedPurchases.size >= CROSS_PLATFORM_LIMIT) unmatchedPurchases.removeAt(0)
            unmatchedPurchases.add(purchase)
        }
        return id
    }

    private fun isShoppingApp(pkg: String): Boolean = pkg == PKG_PDD || pkg == PKG_JD

    fun hasDraft(context: Context, id: String): Boolean = readDraft(context, id) != null

    @Synchronized
    fun consumeDraft(context: Context, id: String): Map<String, Any>? {
        val draft = readDraft(context, id) ?: return null
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.edit().remove(DRAFT_PREFIX + id).commit()) return null
        context.getSystemService(NotificationManager::class.java)?.cancel(id, DETECTION_NOTIFICATION_ID)
        return draft
    }

    fun readDraft(context: Context, id: String): Map<String, Any>? {
        if (!isAutoEnabled(context)) return null
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(DRAFT_PREFIX + id, null) ?: return null
        return try {
            val payload = JSONObject(raw)
            val capturedAt = payload.getLong("occurredAt")
            if (System.currentTimeMillis() - capturedAt !in 0L until DRAFT_TTL_MS) return null
            mapOf(
                "id" to id,
                "amount" to payload.getDouble("amount"),
                "type" to payload.getString("type"),
                "note" to payload.getString("note"),
                "sourceLabel" to payload.optString("sourceLabel"),
                "categoryKey" to payload.optString("categoryKey"),
                "occurredAt" to capturedAt,
            )
        } catch (_: org.json.JSONException) {
            Log.w("VeriAutoBill", "Stored capture draft is invalid")
            null
        }
    }

    @Synchronized
    fun clearDrafts(context: Context) {
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        val manager = context.getSystemService(NotificationManager::class.java)
        for (key in prefs.all.keys.filter { it.startsWith(DRAFT_PREFIX) }) {
            manager?.cancel(key.removePrefix(DRAFT_PREFIX), DETECTION_NOTIFICATION_ID)
            editor.remove(key)
        }
        editor.apply()
        recentBills.clear()
        lastScreenBills.clear()
        unmatchedPurchases.clear()
    }

    private fun dispatchIfFresh(context: Context, pkg: String, bill: ParsedBill) {
        val id = rememberDraft(context, pkg, bill) ?: return
        Log.i("VeriAutoBill", "Payment draft created for $pkg")

        val intent = Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_AUTO_CONFIRM_DRAFT
            data = android.net.Uri.fromParts(MainActivity.AUTO_DRAFT_SCHEME, id, null)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        val app = context.applicationContext
        AutoBillOverlay.deliver(app, id) {
            showDetectedNotification(app, id, bill, intent)
        }
    }

    private fun showDetectedNotification(context: Context, id: String, bill: ParsedBill, intent: Intent) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (!manager.areNotificationsEnabled()) {
            Log.w("VeriAutoBill", "Payment draft notifications are disabled")
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(DETECTION_CHANNEL_ID) == null
        ) {
            val channel = NotificationChannel(
                DETECTION_CHANNEL_ID,
                "自动识别待确认账单",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "检测到支付或转账时弹出确认记账通知"
            }
            manager.createNotificationChannel(channel)
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE,
        )
        val sign = if (bill.type == "income") "+" else "-"
        val notification = NotificationCompat.Builder(context, DETECTION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_quick_entry_tile)
            .setContentTitle("${bill.sourceLabel}：$sign¥${bill.amount}")
            .setContentText("${bill.note} · 点击确认入账")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setTimeoutAfter(DRAFT_TTL_MS)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        manager.notify(id, DETECTION_NOTIFICATION_ID, notification)
    }
}
