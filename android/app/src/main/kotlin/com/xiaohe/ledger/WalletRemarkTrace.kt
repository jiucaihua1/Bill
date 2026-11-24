package com.xiaohe.ledger

import android.util.Log
import com.xiaohe.ledger.AutoBillParser.ParsedBill

/** Records field presence only. Adjacent text is a diagnostic hint, never a merchant value. */
internal object WalletRemarkTrace {
    private const val TAG = "VeriAutoBill"
    private val amountLine = Regex("""(?:[¥+\-−]\s*\d[\d,.]*|\d[\d,]*\.\d{2}|\d[\d,.]*\s*元)""")
    private val labelOrControl = setOf(
        "微信支付", "支付宝支付", "支付宝", "付款成功", "支付成功", "支付完成", "交易成功",
        "完成", "返回商家", "付款详情", "账单详情", "全部账单", "更多",
        "付款方式", "支付方式", "实付金额", "付款金额", "支付金额",
    )
    private val merchantLabels = WalletBillFields.purchaseMerchantLabels + arrayOf("收款方全称", "对方账户", "付款方")
    private val productLabels = WalletBillFields.purchaseProductLabels + arrayOf("转账备注")

    fun input(pkg: String, source: String, text: String, result: String, bill: ParsedBill?) {
        if (!isWallet(pkg)) return
        val lines = WalletBillFields.linesOf(text)
        val hasMerchantField = WalletBillFields.field(lines, *merchantLabels) != null
        val hasProductField = WalletBillFields.field(lines, *productLabels) != null
        val nearAmountText = lines.indices.any { index ->
            amountLine.matches(lines[index]) &&
                (maxOf(0, index - 2)..minOf(lines.lastIndex, index + 2)).any { adjacent ->
                    adjacent != index && isUnlabeledText(lines[adjacent])
                }
        }
        Log.i(
            TAG,
            "Payment remark input pkg=$pkg source=$source result=$result " +
                "merchantField=$hasMerchantField productField=$hasProductField nearAmountText=$nearAmountText " +
                "merchantParsed=${!bill?.merchant.isNullOrBlank()} productParsed=${!bill?.product.isNullOrBlank()} " +
                "paymentMethodParsed=${!bill?.paymentMethod.isNullOrBlank()} " +
                "discountParsed=${bill?.discountAmount?.let { it > 0 } == true}",
        )
    }

    fun draft(pkg: String, result: String, bill: ParsedBill, note: String = AutoBillRules.note(bill)) {
        if (!isWallet(pkg)) return
        val noteKind = when {
            note.isBlank() -> "empty"
            !bill.merchant.isNullOrBlank() || !bill.product.isNullOrBlank() -> "fields"
            else -> "default"
        }
        Log.i(TAG, "Payment remark draft pkg=$pkg result=$result note=$noteKind")
    }

    private fun isWallet(pkg: String): Boolean =
        pkg == AutoBillParser.PKG_WECHAT || pkg == AutoBillParser.PKG_ALIPAY

    private fun isUnlabeledText(line: String): Boolean =
        line.length in 2..60 && line.any(Char::isLetter) && line !in labelOrControl &&
            merchantLabels.none { line == it || line.startsWith("$it:") || line.startsWith("$it ") } &&
            productLabels.none { line == it || line.startsWith("$it:") || line.startsWith("$it ") }
}
