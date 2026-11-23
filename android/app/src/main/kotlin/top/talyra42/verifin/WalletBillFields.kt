package top.talyra42.verifin

import top.talyra42.verifin.AutoBillParser.ParsedBill
import java.text.Normalizer
import java.text.ParsePosition
import java.text.SimpleDateFormat
import java.util.Locale
import kotlin.math.roundToLong

/** Extracts fields from the supported wallet and bank layouts. */
internal object WalletBillFields {
    val purchaseMerchantLabels = arrayOf("商户名称", "商户全称", "收款方", "交易对方", "商家名称", "付款给", "商户")
    val purchaseProductLabels = arrayOf("商品说明", "商品名称", "商品标题")

    private const val MONEY = """(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d{1,2})?"""
    private val alipayAlert = Regex("""你有一笔\s*($MONEY)\s*元的支出(?=\s*[,。!！]|\s*$)""")
    private val ccbAlert = Regex("""您尾号\s*(\d{4})\s*的储蓄账户\s*\d{1,2}月\s*\d{1,2}日\s*\d{1,2}时\s*\d{1,2}分\s*(收入|支出)\s*人民币\s*($MONEY)\s*元""")
    private val signedAmount = Regex("""([+\-−])\s*¥?\s*($MONEY)""")
    private val spokenDetailAmount = Regex("""(收入|支出)\s*¥?\s*($MONEY)\s*元""")
    private val cardSuffix = Regex("""\(\s*(\d{4})\s*\)|尾号\s*(\d{4})(?!\d)""")
    private val checkoutAmount = Regex("""¥\s*($MONEY)|($MONEY)\s*元|(\d[\d,]*\.\d{2})""")
    private val payeeAndAmount = Regex("""(.+?)\s*(¥.+)""")
    private val checkoutPaymentLabel = Regex("""付\s*款\s*方\s*式(?:(?:\s*:\s*|\s+)(.+))?""")
    private val checkoutDiscountLabel = Regex("""碰一下立减|优惠(?:金额)?""")
    private val checkoutDiscount = Regex("""(?:碰一下立减|优惠(?:金额)?):?([\-−]¥?($MONEY))?""")
    private val checkoutDeduction = Regex("""[\-−]¥?($MONEY)""")
    private val maskedWechatName = Regex("""(.+?)\s*\(\s*(?:\*\s*)+\p{L}+\s*\)""")
    private val decimalDot = Regex("""(?<=\d)[·•。](?=\d)""")
    private val cjkSpacing = Regex("""(?<=\p{IsHan})\s+(?=\p{IsHan})""")
    private val checkoutStatuses = setOf("支付成功", "付款成功", "支付完成")
    private val checkoutLabels = checkoutStatuses + setOf("付款方式", "回首页", "完成", "账单详情")

    fun alipayNotification(title: String, body: String): ParsedBill? {
        if (normalize(title).trim() != "交易提醒") return null
        val amount = alipayAlert.find(normalize(body))?.groupValues?.get(1)?.let(::money) ?: return null
        return ParsedBill(amount, "expense", "支付宝支付", "支付宝自动识别")
    }

    fun ccbNotification(title: String, body: String): ParsedBill? {
        if (normalize(title).trim() != "动账提醒") return null
        val text = normalize(body)
        if ("微信支付" in text || "财付通" in text) return null
        val match = ccbAlert.find(text) ?: return null
        val (last4, direction, value) = match.destructured
        val amount = money(value) ?: return null
        return ParsedBill(
            amount, if (direction == "支出") "expense" else "income", "", "建设银行自动识别",
            bankLast4 = last4, paymentMethod = "建设银行储蓄卡",
        )
    }

    fun wechatCheckoutName(text: String, amount: Double, personalQr: Boolean = false): String? {
        val lines = linesOf(text)
        val amountRow = lines.indices.singleOrNull { checkoutAmountOf(lines[it]) == amount } ?: return null
        val nameRow = if (lines.getOrNull(amountRow - 1) == "¥") amountRow - 2 else amountRow - 1
        val name = lines.getOrNull(nameRow) ?: return null
        if (personalQr) return maskedWechatName.matchEntire(name)?.groupValues?.get(1)?.let(::recipient)
        // Merchant receipt header: payment status, merchant name, actual amount.
        if (lines.getOrNull(nameRow - 1)?.replace(cjkSpacing, "") != "支付成功") return null
        return recipient(name)?.takeUnless { it == "微信支付" || it == "返回商家" }
    }

    fun alipayCheckout(text: String): ParsedBill? {
        val lines = linesOf(text)
        val status = lines.indexOfFirst { it.replace(cjkSpacing, "") in checkoutStatuses }
        if (status == -1) return null
        val payment = lines.indexOfFirst(checkoutPaymentLabel::matches)
        if (payment <= status + 1) return null
        val method = checkoutPaymentLabel.matchEntire(lines[payment])?.groups?.get(1)?.value
            ?: lines.getOrNull(payment + 1)
        if (method.isNullOrBlank() || method in checkoutLabels) return null
        val header = lines.subList(status + 1, payment)
        val valueRow = header.indexOfFirst { checkoutAmountOf(it) != null }
        if (valueRow == -1) return null
        val amount = checkoutAmountOf(header[valueRow]) ?: return null
        val rows = header.drop(valueRow + 1)
        val receiptCharges = rows.mapIndexedNotNull { index, line ->
            val combined = payeeAndAmount.matchEntire(line)
            val payee = if (combined != null) combined.groupValues[1] else
                rows.getOrNull(index - if (rows.getOrNull(index - 1) == "¥") 2 else 1)
            val name = payee?.let(::recipient) ?: return@mapIndexedNotNull null
            if (checkoutDiscountLabel.matches(name)) return@mapIndexedNotNull null
            val charge = checkoutAmountOf(combined?.groupValues?.get(2) ?: line)
                ?: return@mapIndexedNotNull null
            name to cents(charge)
        }.distinct()
        val net = cents(amount)
        val deduction = rows.mapIndexedNotNull { index, line ->
            val label = checkoutDiscount.matchEntire(line.filterNot(Char::isWhitespace))
                ?: return@mapIndexedNotNull null
            val value = label.groups[2]?.value
                ?: rows.getOrNull(index + 1)?.filterNot(Char::isWhitespace)?.let {
                    checkoutDeduction.matchEntire(it)?.groupValues?.get(1)
                }
            value?.let(::money)?.let(::cents)
        }.singleOrNull()?.takeIf { discount ->
            receiptCharges.any { (_, charge) -> charge == net + discount }
        } ?: 0L
        val payee = receiptCharges.filter { (_, charge) -> charge == net + deduction }
            .singleOrNull()?.first
        return ParsedBill(
            amount, "expense", "支付宝支付", "支付宝自动识别",
            merchant = payee, paymentMethod = method, bankLast4 = last4(method),
            discountAmount = deduction / 100.0,
        )
    }

    fun alipayDetail(text: String, groupedRows: Boolean = false): ParsedBill? {
        val allLines = linesOf(text)
        // XRiver exposes the navigation title after the scroll body in tree order.
        if (allLines.none { line ->
                line == "账单详情" || groupedRows && "账单详情" in line.split(' ')
            }
        ) return null
        val lines = allLines.takeWhile { !it.startsWith("账单管理") && !it.startsWith("我的消费图鉴") }
        val status = lines.indexOf("交易成功")
        if (status < 1) return null
        val signed = lines.take(status).mapIndexedNotNull { index, line ->
            (signedAmount.matchEntire(line) ?: spokenDetailAmount.matchEntire(line))?.let { index to it }
        }.singleOrNull() ?: return null
        val (amountIndex, match) = signed
        val amount = money(match.groupValues[2]) ?: return null
        val direction = match.groupValues[1]
        val type = if (direction == "+" || direction == "收入") "income" else "expense"
        val method = field(lines, "付款方式")
        val merchant = lines.getOrNull(amountIndex - 1)?.takeUnless { it in setOf("账单详情", "全部账单") }
            ?: field(lines, "对方账户", "收款方全称")
        val product = field(lines, "商品说明", "转账备注")
        val time = field(lines, "支付时间", "创建时间")?.let(::parseDate)
        return ParsedBill(
            amount, type, "", "支付宝自动识别",
            merchant = merchant, product = product, paymentMethod = method,
            bankLast4 = last4(method), occurredAt = time,
        )
    }

    fun linesOf(text: String): List<String> =
        normalize(text).lineSequence().map(String::trim).filter(String::isNotEmpty).toList()

    fun field(lines: List<String>, vararg labels: String): String? {
        for ((index, line) in lines.withIndex()) {
            for (label in labels) {
                if (line == label) return lines.getOrNull(index + 1)
                if (line.startsWith("$label:") || line.startsWith("$label ")) {
                    return line.removePrefix(label).trimStart(':', ' ').takeIf(String::isNotEmpty)
                }
            }
        }
        return null
    }

    fun last4(method: String?): String? = method?.let { cardSuffix.find(it) }
        ?.groupValues?.drop(1)?.firstOrNull(String::isNotEmpty)

    private fun parseDate(text: String): Long? {
        val position = ParsePosition(0)
        val format = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.ROOT).apply { isLenient = false }
        return format.parse(text, position)?.time?.takeIf { position.index == text.length }
    }

    private fun normalize(value: String) = Normalizer.normalize(value, Normalizer.Form.NFKC)

    private fun checkoutAmountOf(line: String): Double? =
        checkoutAmount.matchEntire(line.filterNot(Char::isWhitespace).replace(decimalDot, "."))
            ?.groupValues?.drop(1)?.firstOrNull(String::isNotEmpty)?.let(::money)

    private fun cents(value: Double): Long = (value * 100).roundToLong()

    private fun recipient(text: String): String? = text.trim().replace(cjkSpacing, "").takeIf {
        it.length <= 60 && it.any(Char::isLetter) && it !in checkoutLabels
    }

    private fun money(value: String): Double? =
        value.replace(",", "").toDoubleOrNull()?.takeIf { it > 0 && it < 1_000_000 }
}
