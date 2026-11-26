package com.xiaohe.ledger

import com.xiaohe.ledger.AutoBillParser.ParsedBill
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
    private val checkoutDiscountLabel = Regex(
        """(?:碰一下立减|随机立减|银行卡立减|商家优惠|优惠|红包|消费券|满减|积分抵扣|立减)(?:金额)?""",
    )
    private val checkoutDiscount = Regex("""(${checkoutDiscountLabel.pattern}):?[\-−]?¥?($MONEY)元?""")
    private val checkoutDeduction = Regex("""(?:.*?[^\d.,])?[\-−]¥?($MONEY)元?""")
    private val maskedWechatName = Regex("""(.+?)\s*\(\s*(?:\*\s*)+\p{L}+\s*\)""")
    private val decimalDot = Regex("""(?<=\d)[·•。](?=\d)""")
    private val cjkSpacing = Regex("""(?<=\p{IsHan})\s+(?=\p{IsHan})""")
    private val checkoutStatuses = setOf("支付成功", "付款成功", "支付完成")
    private val checkoutLabels = checkoutStatuses + setOf("付款方式", "回首页", "完成", "账单详情")
    private val wechatCheckoutLabels = checkoutLabels + setOf(
        "微信支付", "返回商家", "返回商户", "返回", "确认", "关闭", "查看详情", "已支付", "已付款",
        "交易成功", "付款金额", "支付金额", "实付金额", "支付方式", "查看账单", "收银台",
        "商户名称", "商户全称", "商家名称", "收款方",
    )
    private val statusAdornment = Regex("""^[^\p{L}]+|[^\p{L}]+$""")

    data class WechatDetail(
        val amount: Double,
        val paidAt: Long,
        val merchant: String,
        val product: String?,
        val paymentMethod: String?,
    )

    fun isWechatDetail(text: String): Boolean {
        val lines = linesOf(text).map { it.filterNot(Char::isWhitespace) }
        val hasStatus = lines.any { it.startsWith("当前状态") }
        val hasPaidAt = lines.any { it.startsWith("支付时间") }
        val hasOrder = lines.any { it.startsWith("交易单号") || it.startsWith("商户单号") }
        val hasAllBills = "全部账单" in lines
        return hasPaidAt && (hasStatus || hasOrder || hasAllBills) ||
            hasAllBills && (hasStatus || hasOrder) ||
            hasStatus && lines.none { it == "完成" || it == "返回商家" } &&
            lines.any { signedAmount.matchEntire(it)?.groupValues?.get(1)?.let { sign -> sign != "+" } == true }
    }

    fun wechatDetail(text: String): WechatDetail? {
        val lines = linesOf(text)
        val statusRow = lines.indexOfFirst { it.filterNot(Char::isWhitespace).startsWith("当前状态") }
        if (statusRow < 0) return null
        val fields = lines.drop(statusRow)
        if (detailField(fields, "当前状态")?.filterNot(Char::isWhitespace) != "支付成功") return null
        val amount = lines.take(statusRow).mapNotNull {
            val match = signedAmount.matchEntire(it.replace(decimalDot, ".")) ?: return@mapNotNull null
            match.takeUnless { it.groupValues[1] == "+" }?.groupValues?.get(2)?.let(::money)
        }.singleOrNull() ?: return null
        val paidAt = detailField(fields, "支付时间")?.let {
            parseDate(it.filterNot(Char::isWhitespace), "yyyy年M月d日HH:mm:ss")
        } ?: return null
        val merchant = detailField(fields, "商户全称", "商户名称")?.let(::recipient) ?: return null
        val product = detailField(fields, *purchaseProductLabels, "商品")?.let(::recipient)
        val method = detailField(fields, "支付方式", "付款方式")
        return WechatDetail(amount, paidAt, merchant, product, method)
    }

    private fun detailField(lines: List<String>, vararg labels: String): String? =
        field(lines, *labels) ?: field(lines.map { row ->
            val compact = row.replace(cjkSpacing, "")
            val label = labels.firstOrNull { compact.startsWith(it) }
            if (label == null || compact == label) compact else "$label: ${compact.removePrefix(label).trimStart(':', ' ')}"
        }, *labels)

    fun sameWechatMerchant(first: String, second: String): Boolean =
        normalize(first).filterNot(Char::isWhitespace) == normalize(second).filterNot(Char::isWhitespace)

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

    fun wechatCheckoutName(text: String, amount: Double): String? {
        val lines = linesOf(text)
        val amountRow = lines.indices.singleOrNull { checkoutAmountOf(lines[it]) == amount } ?: return null
        val nameRow = if (lines.getOrNull(amountRow - 1) == "¥") amountRow - 2 else amountRow - 1
        val name = lines.getOrNull(nameRow) ?: return null
        val displayName = maskedWechatName.matchEntire(name)?.groupValues?.get(1) ?: name
        return recipient(displayName)?.takeUnless { it.replace(statusAdornment, "") in wechatCheckoutLabels }
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
        val labeledPayee = field(rows, *purchaseMerchantLabels)?.let(::recipient)
        val receiptCharges = rows.mapIndexedNotNull { index, line ->
            val compact = line.filterNot(Char::isWhitespace).replace(decimalDot, ".")
            if (checkoutDeduction.matches(compact) || checkoutDiscount.matches(compact)) {
                return@mapIndexedNotNull null
            }
            val combined = payeeAndAmount.matchEntire(line)
            val payee = if (combined != null) combined.groupValues[1] else
                rows.getOrNull(index - if (rows.getOrNull(index - 1) == "¥") 2 else 1)
            val name = when (payee?.filterNot(Char::isWhitespace)?.trimEnd(':')) {
                "原价", "原金额", "订单金额" -> labeledPayee
                else -> payee?.let(::recipient)
            } ?: return@mapIndexedNotNull null
            if (checkoutDiscountLabel.matches(name.trimEnd(':'))) return@mapIndexedNotNull null
            val charge = checkoutAmountOf(combined?.groupValues?.get(2) ?: line)
                ?: return@mapIndexedNotNull null
            name to cents(charge)
        }.distinct()
        val net = cents(amount)
        val deductions = rows.mapNotNull { line ->
            val compact = line.filterNot(Char::isWhitespace).replace(decimalDot, ".")
            val value = checkoutDiscount.matchEntire(compact)?.groupValues?.get(2)
                ?: checkoutDeduction.matchEntire(compact)?.groupValues?.get(1)
            value?.let(::money)?.let(::cents)
        }.toSet()
        val discounted = receiptCharges.singleOrNull { (_, charge) -> charge - net in deductions }
        val payee = discounted?.first ?: receiptCharges.singleOrNull { (_, charge) -> charge == net }?.first
            ?: labeledPayee
        val deduction = discounted?.let { (_, charge) -> charge - net } ?: 0L
        return ParsedBill(
            amount, "expense", "支付宝支付", "支付宝自动识别",
            merchant = payee, paymentMethod = method, bankLast4 = last4(method),
            discountAmount = deduction / 100.0,
        )
    }

    private fun hasAlipayDetailTitle(lines: List<String>, groupedRows: Boolean): Boolean =
        lines.any { it == "账单详情" || groupedRows && "账单详情" in it.split(' ') }

    fun isAlipayDetail(text: String, groupedRows: Boolean = false): Boolean =
        hasAlipayDetailTitle(linesOf(text), groupedRows)

    fun alipayDetail(text: String, groupedRows: Boolean = false): ParsedBill? {
        val allLines = linesOf(text)
        // XRiver exposes the navigation title after the scroll body in tree order.
        if (!hasAlipayDetailTitle(allLines, groupedRows)) return null
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
        val time = field(lines, "支付时间", "创建时间")?.let { parseDate(it) }
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

    private fun parseDate(text: String, pattern: String = "yyyy-MM-dd HH:mm:ss"): Long? {
        val position = ParsePosition(0)
        val format = SimpleDateFormat(pattern, Locale.ROOT).apply { isLenient = false }
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
