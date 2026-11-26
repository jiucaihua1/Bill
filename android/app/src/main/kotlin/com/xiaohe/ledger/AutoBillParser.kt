package com.xiaohe.ledger

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

/**
 * 从已授权来源识别收支，产生待用户确认的本地草稿。
 */
object AutoBillParser {
    internal const val PKG_WECHAT = "com.tencent.mm"
    internal const val PKG_ALIPAY = "com.eg.android.AlipayGphone"
    internal const val ALIPAY_NFC_RESULT = "com.alipay.android.phone.businesscommon.ucdp.nfc.activity.NResPageActivity"
    internal const val ALIPAY_MSP_CONTAINER = "com.alipay.android.msp.ui.views.MspContainerActivity"
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
    private val namedPendingTransfer = Regex("""待\s*([^\n]{1,40}?)\s*确认收款""")
    private val ocrPaymentSuccessLine = Regex("""[^\p{IsHan}]*支付成功[^\p{IsHan}]*""")
    private val ocrTransferAmountLine = Regex("""[¥￥]?\s*($MONEY)""")
    private val ocrSpacing = Regex("""[\p{Zs}\t]+""")
    private val merchantPaymentAmountLine = Regex("""[¥￥]($MONEY)|($MONEY)元""")
    private val merchantCropCurrencyAmount = Regex("""[¥￥]($MONEY)(?![\d.,，])""")
    private val merchantDecimalSeparator = Regex("""(?<=\d)[·•。](?=\d)""")
    private val paymentNoticeStatus = Regex("""(?:支付|付款|扣款|消费)成功|(?:支付|付款|消费)通知|支付完成""")
    private val wechatPaidNotice = Regex("""已支付\s*[¥￥]\s*($MONEY)\s*元?""")
    private val paymentNoticeExcluded = Regex("""待支付|待付款|未支付|未付款|支付失败|付款失败|扣款失败|请支付|退款|退还|验证码|转账|收款成功|入账通知|撤销""")
    private val merchantField = Regex("""(?:商户名称|商户全称|收款方|交易对方|付款给|商家名称|商户)\s*[:：]\s*([^\n]+)""")
    private val orderNumberField = Regex("""(?:商户订单号|商户单号|订单编号|订单号)\s*[:：]?\s*([a-zA-Z0-9_-]{6,80})(?![a-zA-Z0-9_-])""")
    private const val OUTGOING_CARD = """(?:你|您)\s*发起了?\s*一笔转账"""
    private val outgoingCardCaption = Regex(OUTGOING_CARD)
    private const val CARD_MONEY = """(?:[¥￥]\s*$MONEY|$MONEY\s*元)"""
    private val wechatOutgoingCard = Regex(
        """$CARD_MONEY[\s,，:：·]*$OUTGOING_CARD|$OUTGOING_CARD[\s,，:：·]*$CARD_MONEY""",
    )

    private const val DRAFT_TTL_MS = 15 * 60 * 1000L
    private const val DRAFT_LIMIT = 16
    private const val RECENT_BILL_MS = 6_000L
    private const val DETAIL_FRESHNESS_MS = 35_000L
    private const val RECENT_WECHAT_PURCHASE_MS = 35_000L
    private const val WECHAT_DETAIL_TIME_TOLERANCE_MS = 15_000L
    private const val ALIPAY_DETAIL_TIME_TOLERANCE_MS = 60_000L
    private const val DRAFT_PREFIX = "pending_bill."
    private const val DETECTION_NOTIFICATION_ID = 4209
    const val DETECTION_CHANNEL_ID = "verifin_auto_bill_detected"
    private data class RecentBill(
        val pkg: String,
        val bill: ParsedBill,
        val capturedAt: Long,
        val wechatPurchaseSession: Long?,
    ) {
        val lifetime = if (wechatPurchaseSession == null) RECENT_BILL_MS else RECENT_WECHAT_PURCHASE_MS
        var draftId: String? = null
        var occurredAt: Long? = null
        var noteSupplement: String? = null
        var wechatRetryNotified = false
    }
    private val recentBills = mutableListOf<RecentBill>()
    private val lastScreenBills = mutableMapOf<String, Triple<String, Double, String?>>()
    private var lastAlipayDetail: ParsedBill? = null
    private var wechatPurchaseSession = 0L

    data class ParsedBill(
        val amount: Double,
        val type: String,
        val note: String,
        val sourceLabel: String,
        val categoryKey: String = "",
        val shoppingPlatform: String? = null,
        val orderNumber: String? = null,
        val merchant: String? = null,
        val product: String? = null,
        val paymentMethod: String? = null,
        val bankLast4: String? = null,
        val occurredAt: Long? = null,
        val discountAmount: Double = 0.0,
    )

    internal data class PaymentNotice(val source: String, val target: String, val amount: Double?)

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

    fun handleNotification(
        context: Context, pkg: String, title: String, text: String, postedAt: Long? = null,
    ) {
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, pkg)) return
        val explicit = when (pkg) {
            PKG_ALIPAY -> WalletBillFields.alipayNotification(title, text)
            PKG_CCB -> WalletBillFields.ccbNotification(title, text)
            else -> null
        }
        if (explicit != null) {
            WalletRemarkTrace.input(pkg, "notification", "$title\n$text", "parsed", explicit)
            dispatchIfFresh(context, pkg, explicit, observedAt = postedAt)
            return
        }
        val combined = "$title $text".trim()
        if (combined.isEmpty()) return
        val parsed = when (pkg) {
            PKG_WECHAT -> wechatPaidNoticeAmount(title, text)?.let { amount ->
                purchaseBill(amount, combined, "微信支付", "微信自动识别")
            } ?: parseWechat(combined, isScreen = false)
            PKG_ALIPAY -> parseAlipay(combined, isScreen = false)
            PKG_JD -> parseEcommerce(combined, "京东")
            PKG_PDD -> parsePinduoduo(combined)
            else -> null
        } ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            ((pkg == PKG_WECHAT && parsed.note == "微信支付") ||
                (pkg == PKG_ALIPAY && parsed.note == "支付宝支付" && !combined.contains("转账成功")))
        ) return
        dispatchIfFresh(context, pkg, parsed, observedAt = postedAt)
    }

    internal fun paymentNotice(pkg: String, title: String, body: String): PaymentNotice? {
        if (pkg != PKG_WECHAT && pkg != PKG_ALIPAY) return null
        val text = Normalizer.normalize("$title\n$body", Normalizer.Form.NFKC)
        if (paymentNoticeExcluded.containsMatchIn(text)) return null
        if (pkg == PKG_WECHAT) {
            wechatPaidNoticeAmount(title, body)?.let { return PaymentNotice(pkg, pkg, it) }
        }
        if (pkg == PKG_ALIPAY) {
            WalletBillFields.alipayNotification(title, body)?.let { return PaymentNotice(pkg, pkg, it.amount) }
        }
        if (!paymentNoticeStatus.containsMatchIn(text)) return null
        val amounts = distinctAmounts(labeledAmount.findAll(text))
            .ifEmpty { distinctAmounts(currencyAmount.findAll(text)) }
        if (amounts.size > 1) return null
        return PaymentNotice(pkg, pkg, amounts.singleOrNull())
    }

    private fun wechatPaidNoticeAmount(title: String, body: String): Double? {
        if (compactOcrLine(title) != "微信支付") return null
        val normalized = Normalizer.normalize(body, Normalizer.Form.NFKC).trim()
        val match = wechatPaidNotice.matchEntire(normalized) ?: return null
        return distinctAmounts(sequenceOf(match)).singleOrNull()
    }

    @Synchronized
    internal fun handleNotificationPaymentScreen(
        context: Context, notice: PaymentNotice, text: String, amountText: String, receiptRows: String? = null,
    ): Boolean {
        val pkg = notice.target
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, notice.source) ||
            !isPlatformEnabled(context, pkg)
        ) return false
        if (pkg == PKG_WECHAT && handleWechatDetail(context, text, receiptRows)) return true
        if (pkg == PKG_ALIPAY) {
            val detail = readAlipayDetail(text, receiptRows)
            if (detail != null) {
                if (detail.type != "expense" || notice.amount != detail.amount ||
                    !isFreshAlipayDetail(detail)
                ) return false
                WalletRemarkTrace.input(pkg, "notification_ocr_detail", text, "parsed", detail)
                correctAlipayDetail(context, detail) {
                    if (isFreshAlipayDetail(detail) && isPlatformEnabled(context, notice.source)) {
                        dispatchScreenBill(context, pkg, detail)
                    }
                }
                return true
            }
            if (isAlipayDetail(text, receiptRows)) return false
        }
        val bill = parseNotificationPaymentScreen(notice, text, amountText, receiptRows) ?: return false
        val amount = bill.amount
        val previous = lastScreenBills[pkg]
        if (previous?.first == bill.type && previous.second == amount &&
            (previous.third == null || bill.orderNumber == null || previous.third == bill.orderNumber)
        ) {
            WalletRemarkTrace.draft(pkg, "screen_duplicate", bill)
            if (pkg != PKG_ALIPAY) return true
            val now = SystemClock.elapsedRealtime()
            val wallTime = System.currentTimeMillis()
            return recentBills.any {
                it.pkg == pkg && now - it.capturedAt < RECENT_BILL_MS &&
                    sameRecentBill(it.bill, bill, wallTime)
            }
        }
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
            else -> false
        }
    }

    internal fun parseNotificationPaymentScreen(
        notice: PaymentNotice, text: String, amountText: String, receiptRows: String? = null,
    ): ParsedBill? {
        if (notice.target == PKG_ALIPAY) {
            val detail = readAlipayDetail(text, receiptRows)
            if (detail != null) {
                val time = detail.occurredAt
                // A fresh notification must not attach to an older open receipt.
                if (detail.type != "expense" || notice.amount != detail.amount ||
                    time == null || System.currentTimeMillis() - time !in 0L..DETAIL_FRESHNESS_MS
                ) return null
                WalletRemarkTrace.input(notice.target, "notification_ocr_detail", text, "parsed", detail)
                return detail
            }
            val checkout = receiptRows?.let(::parseAlipayCheckout) ?: parseAlipayCheckout(text)
            if (checkout != null) {
                if (notice.amount != null && checkout.amount != notice.amount) {
                    WalletRemarkTrace.input(notice.target, "notification_ocr", text, "amount_mismatch", null)
                    return null
                }
                WalletRemarkTrace.input(notice.target, "notification_ocr", text, "parsed", checkout)
                return checkout
            }
        }
        if (!hasNotificationPaymentScreenStatus(notice, text)) {
            WalletRemarkTrace.input(notice.target, "notification_ocr", text, "missing_status", null)
            return null
        }
        val amount = wechatMerchantResultAmount(amountText, cropped = true)
        if (amount == null || notice.amount != null && amount != notice.amount) {
            val result = if (amount == null) "missing_unique_amount" else "amount_mismatch"
            WalletRemarkTrace.input(notice.target, "notification_ocr", text, result, null)
            return null
        }
        val name = if (notice.target == PKG_WECHAT) "微信" else "支付宝"
        val bill = purchaseBill(amount, text, "${name}支付", "${name}自动识别")
        return (if (notice.target == PKG_WECHAT && bill.merchant == null) {
            bill.copy(merchant = WalletBillFields.wechatCheckoutName(text, amount))
        } else bill).also {
            WalletRemarkTrace.input(notice.target, "notification_ocr", text, "parsed", it)
        }
    }

    @Synchronized
    fun handleScreenTexts(
        context: Context, pkg: String, texts: List<String>, eventTexts: List<String>, windowChanged: Boolean,
        alipayRows: String? = null,
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
        if (pkg == PKG_ALIPAY) {
            val page = texts.joinToString("\n")
            val combined = (texts + eventTexts).distinct().joinToString("\n")
            if (isAlipayDetail(combined, alipayRows)) {
                val detail = readAlipayDetail(page, alipayRows) ?: readAlipayDetail(combined, null)
                if (detail != null && (windowChanged || detail != lastAlipayDetail)) {
                    lastAlipayDetail = detail
                    WalletRemarkTrace.input(pkg, "accessibility_detail", combined, "parsed", detail)
                    correctAlipayDetail(context, detail)
                }
                return true
            }
            if (windowChanged) lastAlipayDetail = null
        }
        val merchantReturn = wechatTexts.any { compactOcrLine(it) == "返回商家" }
        val merchantDone = wechatTexts.any { compactOcrLine(it) == "完成" } && !merchantReturn
        val alipayResult = if (pkg == PKG_ALIPAY) {
            alipayRows?.let(::parseAlipayCheckout)
                ?: parseAlipayCheckout(texts.joinToString("\n"))
                ?: parseAlipayCheckout((texts + eventTexts).joinToString("\n"))
        } else null
        val parsed = alipayResult ?: if (hasWechatTransferResultMarkers(wechatTexts)) {
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
        dispatchScreenBill(context, pkg, parsed) {
            if (pkg == PKG_ALIPAY || pkg == PKG_WECHAT) {
                WalletRemarkTrace.input(pkg, "accessibility", (texts + eventTexts).distinct().joinToString("\n"), "parsed", parsed)
            }
        }
        return true
    }

    @Synchronized
    fun beginWechatPayment(purchase: Boolean) {
        lastScreenBills.remove(PKG_WECHAT)
        if (purchase) wechatPurchaseSession++
    }

    @Synchronized
    fun handleWechatResultScreenshot(
        context: Context, text: String, transfer: Boolean, amountText: String? = null,
        merchantScan: Boolean = false, personalQrResult: Boolean = false, doneControlSeen: Boolean = false,
        receiptRows: String? = null,
    ): Boolean {
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, PKG_WECHAT)) return false
        if (handleWechatDetail(context, text, receiptRows)) return true
        val bill = if (transfer) {
            parseWechatTransferScreenshot(text, amountText)
        } else {
            parseWechatMerchantResult(text, amountText, merchantScan, personalQrResult, doneControlSeen)
        }
        WalletRemarkTrace.input(PKG_WECHAT, "result_ocr", text, if (bill == null) "unmatched" else "parsed", bill)
        if (bill == null) return false
        dispatchScreenBill(context, PKG_WECHAT, bill)
        return true
    }

    @Synchronized
    internal fun recentWechatPurchaseId(): String? {
        val now = SystemClock.elapsedRealtime()
        return recentBills.lastOrNull {
            it.wechatPurchaseSession == wechatPurchaseSession && now - it.capturedAt < DRAFT_TTL_MS &&
                it.draftId != null
        }?.draftId
    }

    @Synchronized
    internal fun handleWechatDetail(context: Context, text: String, receiptRows: String? = null): Boolean {
        if (!WalletBillFields.isWechatDetail(text) &&
            (receiptRows == null || !WalletBillFields.isWechatDetail(receiptRows))
        ) return false
        if (!isAutoEnabled(context) || !isPlatformEnabled(context, PKG_WECHAT)) return true
        val detail = receiptRows?.let(WalletBillFields::wechatDetail) ?: WalletBillFields.wechatDetail(text)
            ?: return true
        val now = SystemClock.elapsedRealtime()
        val original = recentBills.singleOrNull { candidate ->
            candidate.wechatPurchaseSession != null && candidate.draftId != null &&
                now - candidate.capturedAt < DRAFT_TTL_MS &&
                candidate.bill.amount == detail.amount && candidate.bill.merchant?.let {
                    WalletBillFields.sameWechatMerchant(it, detail.merchant)
                } != false && candidate.occurredAt?.let {
                    kotlin.math.abs(it - detail.paidAt) <= WECHAT_DETAIL_TIME_TOLERANCE_MS
                } == true
        } ?: return true
        val id = checkNotNull(original.draftId)
        if (!original.wechatRetryNotified) {
            val retry = original.bill.copy(
                merchant = detail.merchant,
                product = detail.product ?: original.bill.product,
                paymentMethod = detail.paymentMethod ?: original.bill.paymentMethod,
                bankLast4 = WalletBillFields.last4(detail.paymentMethod) ?: original.bill.bankLast4,
                occurredAt = detail.paidAt,
            )
            original.wechatRetryNotified = notifyWechatRetry(context, retry, id)
        }
        val product = detail.product ?: return true
        if (original.bill.merchant.isNullOrBlank()) return true
        val originalNote = AutoBillRules.note(original.bill)
        if (original.noteSupplement != null || originalNote.split(" · ").contains(product)) return true
        val note = "$originalNote · $product"
        original.noteSupplement = note
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        try {
            prefs.getString(DRAFT_PREFIX + id, null)?.let { raw ->
                val draft = JSONObject(raw)
                if (draft.optString("note") == originalNote) {
                    prefs.edit().putString(DRAFT_PREFIX + id, draft.put("note", note).toString()).apply()
                }
            }
        } catch (_: org.json.JSONException) {
            Log.w("VeriAutoBill", "Stored WeChat draft could not be enriched")
        }
        wechatNoteSupplement(id)?.let(AutoBillOverlay::enrichWechatNote)
        return true
    }

    @Synchronized
    internal fun wechatNoteSupplement(id: String): Map<String, Any>? {
        val recent = recentBills.firstOrNull { it.draftId == id } ?: return null
        if (SystemClock.elapsedRealtime() - recent.capturedAt >= DRAFT_TTL_MS) return null
        val note = recent.noteSupplement ?: return null
        val timestamp = recent.occurredAt ?: return null
        return mapOf(
            "id" to id, "before" to AutoBillRules.note(recent.bill), "note" to note,
            "amount" to recent.bill.amount, "occurredAt" to timestamp,
        )
    }

    private fun isAlipayDetail(text: String, rows: String?): Boolean =
        WalletBillFields.isAlipayDetail(text) ||
            rows?.let { WalletBillFields.isAlipayDetail(it, groupedRows = true) } == true

    private fun readAlipayDetail(text: String, rows: String?): ParsedBill? =
        WalletBillFields.alipayDetail(text) ?: rows?.let { WalletBillFields.alipayDetail(it, groupedRows = true) }

    private fun isFreshAlipayDetail(detail: ParsedBill): Boolean =
        detail.occurredAt?.let { System.currentTimeMillis() - it in 0L..DETAIL_FRESHNESS_MS } == true

    private fun correctAlipayDetail(context: Context, detail: ParsedBill, onMissing: (() -> Unit)? = null) {
        val paidAt = detail.occurredAt ?: return
        if (detail.paymentMethod.isNullOrBlank()) {
            onMissing?.invoke()
            return
        }
        val now = SystemClock.elapsedRealtime()
        fun distance(candidate: RecentBill) = kotlin.math.abs(checkNotNull(candidate.occurredAt) - paidAt)
        val sameAmountAndTime = recentBills.filter {
            it.pkg == PKG_ALIPAY && it.draftId != null && now - it.capturedAt < DRAFT_TTL_MS &&
                it.bill.amount == detail.amount && it.bill.type == detail.type &&
                it.occurredAt != null && distance(it) <= ALIPAY_DETAIL_TIME_TOLERANCE_MS
        }
        val candidates = sameAmountAndTime.filter { sameAlipayPaymentMethod(it.bill, detail) }.sortedBy(::distance)
        val original = candidates.firstOrNull()
        if (original != null && candidates.getOrNull(1)?.let(::distance) == distance(original)) {
            WalletRemarkTrace.draft(PKG_ALIPAY, "detail_ambiguous", detail)
            return
        }
        val fields = mutableMapOf<String, Any>("amount" to detail.amount, "type" to detail.type, "paidAt" to paidAt)
        fields["paymentMethod"] = detail.paymentMethod
        detail.merchant?.let { fields["merchant"] = it }
        detail.product?.let { fields["product"] = it }
        detail.bankLast4?.let { fields["bankLast4"] = it }
        if (original != null) {
            val id = checkNotNull(original.draftId)
            fields["id"] = id
            val before = AutoBillRules.note(original.bill)
            val note = AutoBillRules.note(original.bill.copy(
                merchant = detail.merchant ?: original.bill.merchant,
                product = detail.product ?: original.bill.product,
            ))
            fields["before"] = before
            fields["note"] = note
            if (note.isNotBlank() && note != before) {
                val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
                val raw = prefs.getString(DRAFT_PREFIX + id, null)
                if (raw != null) {
                    try {
                        val draft = JSONObject(raw)
                        if (draft.optString("note") in setOf(before, original.noteSupplement)) {
                            prefs.edit().putString(DRAFT_PREFIX + id, draft.put("note", note).toString()).apply()
                        }
                    } catch (_: org.json.JSONException) {
                        Log.w("VeriAutoBill", "Stored Alipay draft could not be enriched")
                    }
                }
                original.noteSupplement = note
            }
        }
        val possibleDraft = sameAmountAndTime.any { it.bill.paymentMethod.isNullOrBlank() }
        AutoBillOverlay.correctAlipayNote(context, fields, onMissing.takeUnless { original != null || possibleDraft })
    }

    private fun sameAlipayPaymentMethod(first: ParsedBill, second: ParsedBill): Boolean {
        if (first.bankLast4 != null || second.bankLast4 != null) {
            return first.bankLast4 != null && first.bankLast4 == second.bankLast4
        }
        fun normalized(method: String?): String = method.orEmpty().filterNot(Char::isWhitespace).removePrefix("支付宝")
        val method = normalized(first.paymentMethod)
        return method.isNotEmpty() && method == normalized(second.paymentMethod)
    }

    @Synchronized
    internal fun alipayNoteSupplement(id: String): Map<String, Any>? {
        val original = recentBills.firstOrNull { it.pkg == PKG_ALIPAY && it.draftId == id } ?: return null
        if (SystemClock.elapsedRealtime() - original.capturedAt >= DRAFT_TTL_MS) return null
        return mapOf(
            "before" to AutoBillRules.note(original.bill), "note" to (original.noteSupplement ?: return null),
            "amount" to original.bill.amount, "occurredAt" to (original.occurredAt ?: return null),
        )
    }

    @Synchronized
    private fun dispatchScreenBill(context: Context, pkg: String, bill: ParsedBill, onNew: () -> Unit = {}) {
        val key = Triple(bill.type, bill.amount, bill.orderNumber ?: bill.occurredAt?.toString())
        if (lastScreenBills.put(pkg, key) == key) return
        onNew()
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
        val bill = purchaseBill(amount, compact, note = "微信支付", sourceLabel = "微信自动识别")
        if (!bill.merchant.isNullOrBlank()) return bill
        val name = amountText?.takeIf { personalQrResult }?.let { WalletBillFields.wechatCheckoutName(it, amount) }
            ?: WalletBillFields.wechatCheckoutName(text, amount)
        return bill.copy(merchant = name)
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
        return pendingWechatTransfer(amount, text)
    }

    private fun parseWechatTransferResult(text: String): ParsedBill? {
        val lines = text.lineSequence().map(String::trim).toList()
        if (!hasWechatTransferResultMarkers(lines)) return null
        if (lines.any(::isRejectedTransferLine)) return null
        val amount = extractAmount(text, allowStandalone = true) ?: return null
        return pendingWechatTransfer(amount, text)
    }

    private fun isRejectedTransferLine(text: String): Boolean =
        text.contains("支付失败") || text.contains("转账失败") ||
            text.contains("已退还") || text.contains("已退款")

    private fun pendingWechatTransfer(amount: Double, text: String): ParsedBill {
        val recipient = WalletBillFields.linesOf(text)
            .mapNotNull { namedPendingTransfer.matchEntire(it)?.groupValues?.get(1)?.trim() }
            .distinct().singleOrNull()?.takeUnless { it == "对方" || it == "你" }
        return ParsedBill(amount, "expense", "微信转出（待对方收款）", "微信自动识别", merchant = recipient)
    }

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

    @Synchronized
    internal fun handleAlipayCheckoutControls(
        context: Context,
        rows: String,
        noticeAmount: Double? = null,
    ): Boolean {
        if (WalletBillFields.isAlipayDetail(rows, groupedRows = true)) return false
        val bill = parseAlipayCheckout(rows) ?: return false
        if (bill.merchant == null || bill.paymentMethod == null ||
            noticeAmount != null && noticeAmount != bill.amount
        ) return false
        dispatchScreenBill(context, PKG_ALIPAY, bill) {
            WalletRemarkTrace.input(PKG_ALIPAY, "accessibility_checkout", rows, "parsed", bill)
        }
        return true
    }

    private fun parseAlipayCheckout(text: String): ParsedBill? {
        val bill = WalletBillFields.alipayCheckout(text) ?: return null
        val merchant = bill.merchant.orEmpty()
        val shoppingPlatform = shoppingPlatformFor(merchant)
        return bill.copy(
            categoryKey = AutoBillRules.categoryHint(merchant, shoppingPlatform),
            shoppingPlatform = shoppingPlatform,
            orderNumber = shoppingOrderNumber(text, shoppingPlatform),
        )
    }

    private fun parseAlipay(rawText: String, isScreen: Boolean): ParsedBill? {
        val lines = WalletBillFields.linesOf(rawText)
        if (isScreen) {
            if ("账单详情" in lines) return null
            parseAlipayCheckout(rawText)?.let { return it }
        }
        val text = lines.filterNot { it.startsWith("我的消费图鉴") }.joinToString("\n")
        val isIncome = text.contains("收款成功") || text.contains("收款到账") ||
            text.contains("到账通知") || text.contains("向你付款")
        // Ordinary screen payments must match the receipt layout above.
        // A notification can supply its own status, but a home feed item cannot.
        val isTransfer = text.contains("转账成功")
        val paymentNotice = !isScreen &&
            listOf("付款成功", "支付成功", "支付完成", "扣款", "消费").any(text::contains)
        val isExpense = isTransfer || paymentNotice
        if (isIncome == isExpense) return null
        val amount = extractAmount(text, allowStandalone = isScreen) ?: return null
        val type = if (isIncome) "income" else "expense"
        val note = if (isIncome) "支付宝收款" else "支付宝支付"
        if (!isIncome && !isTransfer) {
            return purchaseBill(amount, text, note, "支付宝自动识别")
        }
        val method = WalletBillFields.field(WalletBillFields.linesOf(text), "付款方式", "支付方式")
        return ParsedBill(
            amount, type, note, "支付宝自动识别",
            merchant = WalletBillFields.field(lines, "交易对方", "对方账户", "付款方"),
            paymentMethod = method, bankLast4 = WalletBillFields.last4(method),
        )
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
        val shoppingPlatform = platform ?: shoppingPlatformFor(text)
        val lines = WalletBillFields.linesOf(text)
        val merchant = WalletBillFields.field(lines, *WalletBillFields.purchaseMerchantLabels)
        val method = WalletBillFields.field(lines, "付款方式", "支付方式")
        return ParsedBill(
            amount = amount,
            type = "expense",
            note = note,
            sourceLabel = sourceLabel,
            categoryKey = AutoBillRules.categoryHint(text, shoppingPlatform),
            shoppingPlatform = shoppingPlatform,
            merchant = merchant,
            product = WalletBillFields.field(lines, *WalletBillFields.purchaseProductLabels),
            paymentMethod = method,
            bankLast4 = WalletBillFields.last4(method),

            orderNumber = shoppingOrderNumber(text, shoppingPlatform),
        )
    }

    private fun shoppingPlatformFor(text: String): String? = text.lineSequence()
        .map(String::trim)
        .plus(merchantField.findAll(text).map { it.groupValues[1].trim() })
        .mapNotNull {
            when (it) {
                "拼多多", "拼多多商城" -> "拼多多"
                "京东", "京东商城" -> "京东"
                else -> null
            }
        }.distinct().singleOrNull()

    private fun shoppingOrderNumber(text: String, platform: String?): String? = platform?.let {
        orderNumberField.findAll(text).map { match -> match.groupValues[1] }
            .distinct().singleOrNull()
    }

    @Synchronized
    private fun rememberDraft(
        context: Context, pkg: String, bill: ParsedBill, observedAt: Long?,
    ): String? {
        if (!isAutoEnabled(context)) return null
        val ageClock = SystemClock.elapsedRealtime()
        val now = System.currentTimeMillis()
        recentBills.removeAll {
            val retention = if (it.draftId != null && (it.wechatPurchaseSession != null || it.pkg == PKG_ALIPAY)) {
                DRAFT_TTL_MS
            } else it.lifetime
            ageClock - it.capturedAt >= retention
        }
        val purchaseSession = wechatPurchaseSession.takeIf { pkg == PKG_WECHAT && bill.note == "微信支付" }
        if (recentBills.any {
                it.pkg == pkg && it.wechatPurchaseSession == purchaseSession && ageClock - it.capturedAt < it.lifetime &&
                    sameRecentBill(it.bill, bill, now, allowMissingOrder = purchaseSession != null)
            }
        ) {
            WalletRemarkTrace.draft(pkg, "recent_duplicate", bill)
            return null
        }
        val currentBill = RecentBill(pkg, bill, ageClock, purchaseSession)
        if (AutoBillRules.takeDuplicate(pkg, bill, ageClock, now)) {
            recentBills.add(currentBill)
            Log.i("VeriAutoBill", "Duplicate payment suppressed across platforms")
            WalletRemarkTrace.draft(pkg, "cross_platform_duplicate", bill)
            return null
        }
        val occurredAt = bill.occurredAt ?: observedAt ?: now
        val id = writeDraft(context, pkg, bill, now, occurredAt) ?: return null
        if (purchaseSession != null || pkg == PKG_ALIPAY) {
            currentBill.draftId = id
            currentBill.occurredAt = occurredAt
        }
        recentBills.add(currentBill)
        AutoBillRules.remember(pkg, bill, ageClock, now)
        return id
    }

    private fun writeDraft(
        context: Context,
        pkg: String,
        bill: ParsedBill,
        now: Long,
        occurredAt: Long,
        retryOf: String? = null,
    ): String? {
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
        val note = AutoBillRules.note(bill)
        val payload = JSONObject()
            .put("amount", bill.amount)
            .put("discountAmount", bill.discountAmount)
            .put("type", bill.type)
            .put("note", note)
            .put("sourceLabel", bill.sourceLabel)
            .put("categoryKey", bill.categoryKey)
            .put("occurredAt", occurredAt)
            .put("sourcePackage", pkg)
            .put("platformTag", AutoBillRules.platformTag(bill.shoppingPlatform))
            .put("merchant", bill.merchant)
            .put("product", bill.product)
            .put("paymentMethod", bill.paymentMethod)
            .put("bankLast4", bill.bankLast4)
            .put("retryOf", retryOf)

        if (!editor.putString(DRAFT_PREFIX + id, payload.toString()).commit()) {
            WalletRemarkTrace.draft(pkg, "write_failed", bill, note)
            return null
        }
        WalletRemarkTrace.draft(pkg, "written", bill, note)
        return id
    }

    private fun sameRecentBill(
        a: ParsedBill, b: ParsedBill, now: Long, allowMissingOrder: Boolean = false,
    ): Boolean {
        if (a.type != b.type || a.amount != b.amount) return false
        if (a.bankLast4 != null && b.bankLast4 != null && a.bankLast4 != b.bankLast4) return false
        if (a.orderNumber != null && b.orderNumber != null) return a.orderNumber == b.orderNumber
        if (!allowMissingOrder && (a.orderNumber != null || b.orderNumber != null)) return false
        if (a.occurredAt != null && b.occurredAt != null) return a.occurredAt == b.occurredAt
        val detailTime = a.occurredAt ?: b.occurredAt ?: return true
        return now - detailTime in 0L..DETAIL_FRESHNESS_MS
    }

    internal fun isShoppingApp(pkg: String): Boolean = pkg == PKG_PDD || pkg == PKG_JD

    fun hasDraft(context: Context, id: String): Boolean = readDraft(context, id) != null

    @Synchronized
    fun readNotificationDraft(context: Context, id: String): Map<String, Any>? {
        val payload = readDraftPayload(context, id) ?: return null
        val originalId = payload.optString("retryOf").takeIf(String::isNotEmpty)
        val draft = originalId?.let { readDraft(context, it) }
            ?: draftFields(originalId ?: id, payload)
            ?: return null
        return draft + ("notificationDraftId" to id)
    }

    @Synchronized
    fun consumeDraft(context: Context, id: String): Map<String, Any>? {
        val payload = readDraftPayload(context, id) ?: return null
        val retryOf = payload.optString("retryOf").takeIf(String::isNotEmpty)
        val original = retryOf?.let { readDraft(context, it) }
        // A retry may outlive the original pending draft, but both confirm the same payment.
        val draft = original ?: draftFields(retryOf ?: id, payload) ?: return null
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit().remove(DRAFT_PREFIX + id)
        if (original != null) editor.remove(DRAFT_PREFIX + retryOf)
        if (!editor.commit()) return null
        val manager = context.getSystemService(NotificationManager::class.java)
        manager?.cancel(id, DETECTION_NOTIFICATION_ID)
        if (original != null) manager?.cancel(retryOf, DETECTION_NOTIFICATION_ID)
        return draft
    }

    fun readDraft(context: Context, id: String): Map<String, Any>? =
        readDraftPayload(context, id)?.let { draftFields(id, it) }

    private fun readDraftPayload(context: Context, id: String): JSONObject? {
        if (!isAutoEnabled(context)) return null
        val prefs = context.getSharedPreferences(AutoCapturePermissions.PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(DRAFT_PREFIX + id, null) ?: return null
        return try {
            val payload = JSONObject(raw)
            val capturedAt = id.substringBefore('-').toLongOrNull() ?: return null
            if (System.currentTimeMillis() - capturedAt !in 0L until DRAFT_TTL_MS) return null
            if (payload.has("retryOf") && !isPlatformEnabled(context, PKG_WECHAT)) return null
            payload
        } catch (_: org.json.JSONException) {
            Log.w("VeriAutoBill", "Stored capture draft is invalid")
            null
        }
    }

    private fun draftFields(id: String, payload: JSONObject): Map<String, Any>? =
        try {
            mapOf(
                "id" to id,
                "amount" to payload.getDouble("amount"),
                "discountAmount" to payload.optDouble("discountAmount", 0.0),
                "type" to payload.getString("type"),
                "note" to payload.getString("note"),
                "sourceLabel" to payload.optString("sourceLabel"),
                "categoryKey" to payload.optString("categoryKey"),
                "occurredAt" to payload.getLong("occurredAt"),
                "sourcePackage" to payload.optString("sourcePackage"),
                "platformTag" to AutoBillRules.platformTag(payload.optString("platformTag")),
                "merchant" to payload.optString("merchant"),
                "product" to payload.optString("product"),
                "paymentMethod" to payload.optString("paymentMethod"),
                "bankLast4" to payload.optString("bankLast4"),
            )
        } catch (_: org.json.JSONException) {
            Log.w("VeriAutoBill", "Stored capture draft is invalid")
            null
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
        lastAlipayDetail = null
        AutoBillRules.clear()
    }

    private fun dispatchIfFresh(
        context: Context, pkg: String, bill: ParsedBill, observedAt: Long? = null,
    ) {
        val id = rememberDraft(context, pkg, bill, observedAt) ?: return
        Log.i("VeriAutoBill", "Payment draft created for $pkg")
        val app = context.applicationContext
        AutoBillOverlay.deliver(app, id) {
            val manager = draftNotificationManager(app) ?: return@deliver
            showDetectedNotification(app, manager, id, bill)
        }
    }

    private fun draftIntent(context: Context, id: String): Intent =
        Intent(context, MainActivity::class.java).apply {
            action = MainActivity.ACTION_AUTO_CONFIRM_DRAFT
            data = android.net.Uri.fromParts(MainActivity.AUTO_DRAFT_SCHEME, id, null)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

    private fun notifyWechatRetry(context: Context, bill: ParsedBill, originalId: String): Boolean {
        val manager = draftNotificationManager(context) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            manager.getNotificationChannel(DETECTION_CHANNEL_ID)?.importance == NotificationManager.IMPORTANCE_NONE
        ) return false
        val now = System.currentTimeMillis()
        val id = writeDraft(context, PKG_WECHAT, bill, now, checkNotNull(bill.occurredAt), retryOf = originalId)
            ?: return false
        showDetectedNotification(context, manager, id, bill, wechatRetry = true)
        return true
    }

    private fun draftNotificationManager(context: Context): NotificationManager? {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return null
        if (!manager.areNotificationsEnabled()) {
            Log.w("VeriAutoBill", "Payment draft notifications are disabled")
            return null
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
        return manager
    }

    private fun showDetectedNotification(
        context: Context,
        manager: NotificationManager,
        id: String,
        bill: ParsedBill,
        wechatRetry: Boolean = false,
    ) {
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            draftIntent(context, id),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val sign = if (bill.type == "income") "+" else "-"
        val title = if (wechatRetry) context.getString(R.string.wechat_retry_title)
            else "${bill.sourceLabel}：$sign¥${bill.amount}"
        val message = if (wechatRetry) context.getString(R.string.wechat_retry_message)
            else "${bill.note} · 点击确认入账"
        val notification = NotificationCompat.Builder(context, DETECTION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_quick_entry_tile)
            .setContentTitle(title)
            .setContentText(message)
            .apply {
                if (wechatRetry) {
                    setStyle(NotificationCompat.BigTextStyle().bigText(message))
                    setDefaults(NotificationCompat.DEFAULT_SOUND)
                }
            }
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setTimeoutAfter(DRAFT_TTL_MS)
            .setContentIntent(pendingIntent)
            .build()
        manager.notify(id, DETECTION_NOTIFICATION_ID, notification)
    }
}
