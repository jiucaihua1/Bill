package com.xiaohe.ledger

import com.xiaohe.ledger.AutoBillParser.ParsedBill
import kotlin.math.roundToLong

/** Shared draft metadata and pairing for all Android capture sources. */
internal object AutoBillRules {
    private const val BANK_WINDOW_MS = 75_000L
    private const val SHOPPING_WINDOW_MS = 120_000L
    private const val MAX_RECENT = 64

    private val recent = mutableListOf<Capture>()
    private val categoryKeywords = mapOf(
        "dining" to Regex("星巴克|瑞幸|库迪|麦当劳|肯德基|海底捞|饿了么|美团外卖"),
        "transport" to Regex("滴滴出行|高德打车|曹操出行|铁路12306|地铁乘车|公交乘车"),
        "housing" to Regex("物业费|电费充值|燃气费|自来水费"),
        "entertainment" to Regex("哔哩哔哩|爱奇艺|腾讯视频|网易云音乐|网易云|猫眼电影"),
        "medical" to Regex("医院挂号|医院门诊|大药房|药店"),
    )

    private data class Capture(val pkg: String, val bill: ParsedBill, val time: Long) {
        var bankPaired = false
        var shoppingPaired = false
    }

    fun categoryHint(text: String, shoppingPlatform: String?): String =
        categoryKeywords.entries.singleOrNull { it.value.containsMatchIn(text) }?.key
            ?: if (shoppingPlatform == null) "" else "shopping"

    fun platformTag(platform: String?): String = when (platform) {
        "京东", "拼多多" -> platform
        else -> ""
    }

    fun note(bill: ParsedBill): String = listOfNotNull(bill.merchant, bill.product)
        .map(String::trim).filter(String::isNotEmpty).distinct().joinToString(" · ").ifBlank { bill.note }

    // Invoked under the draft-store lock, with the same monotonic clock as the draft cache.
    fun takeDuplicate(pkg: String, bill: ParsedBill, now: Long, wallTime: Long): Boolean {
        expire(now)
        val current = Capture(pkg, bill, now)
        val bank = if (isRecentBankCandidate(current, wallTime)) recent.filter { other ->
            !other.bankPaired && now - other.time < BANK_WINDOW_MS &&
                isAlipayBankPair(pkg, other.pkg) && isRecentBankCandidate(other, wallTime) &&
                compatibleAmount(current, other) &&
                (bill.bankLast4 == null || other.bill.bankLast4 == null || bill.bankLast4 == other.bill.bankLast4)
        } else emptyList()
        val bankMatch = bank.firstOrNull { bill.bankLast4 != null && bill.bankLast4 == it.bill.bankLast4 }
            ?: bank.firstOrNull()
        val shopping = recent.filter {
            !it.shoppingPaired && compatibleAmount(current, it) && isShoppingPair(current, it)
        }
        val shoppingMatch = shopping.singleOrNull { bill.orderNumber != null && bill.orderNumber == it.bill.orderNumber }
            ?: shopping.singleOrNull()
        if (bankMatch == null && shoppingMatch == null) return false
        bankMatch?.bankPaired = true
        shoppingMatch?.shoppingPaired = true
        current.bankPaired = bankMatch != null
        current.shoppingPaired = shoppingMatch != null
        add(current)
        return true
    }

    fun remember(pkg: String, bill: ParsedBill, now: Long, wallTime: Long) {
        val capture = Capture(pkg, bill, now)
        if (bill.shoppingPlatform == null && !isRecentBankCandidate(capture, wallTime)) return
        add(capture)
    }

    private fun add(capture: Capture) {
        if (recent.size >= MAX_RECENT) recent.removeAt(0)
        recent.add(capture)
    }

    fun clear() = recent.clear()

    private fun expire(now: Long) = recent.removeAll { now - it.time >= SHOPPING_WINDOW_MS }

    private fun isRecentBankCandidate(capture: Capture, wallTime: Long): Boolean =
        (capture.pkg == AutoBillParser.PKG_ALIPAY || capture.pkg == AutoBillParser.PKG_CCB) &&
            capture.bill.occurredAt?.let { wallTime - it in 0L..BANK_WINDOW_MS } != false

    private fun isAlipayBankPair(pkg: String, other: String): Boolean =
        pkg == AutoBillParser.PKG_ALIPAY && other == AutoBillParser.PKG_CCB ||
            pkg == AutoBillParser.PKG_CCB && other == AutoBillParser.PKG_ALIPAY

    private fun compatibleAmount(first: Capture, second: Capture): Boolean {
        val a = first.bill
        val b = second.bill
        return a.type == b.type && (a.amount * 100).roundToLong() == (b.amount * 100).roundToLong()
    }

    private fun isShoppingPair(first: Capture, second: Capture): Boolean {
        val a = first.bill
        val b = second.bill
        return a.shoppingPlatform != null && a.shoppingPlatform == b.shoppingPlatform &&
            AutoBillParser.isShoppingApp(first.pkg) != AutoBillParser.isShoppingApp(second.pkg) &&
            (a.orderNumber == null || b.orderNumber == null || a.orderNumber == b.orderNumber)
    }
}
