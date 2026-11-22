/// 订阅分析优先采用交易的手动标注，未标注时在本机匹配支出备注。
library;

import 'calendar_days.dart';
import 'models/ledger_entry.dart';
import 'recurring.dart';

final _subscriptionTerms = RegExp(
  r'(?:京东|\bjd)\s*[-·]?\s*plus|88\s*vip|订阅|会员|连续包[月季年]|自动续费|'
  r'\b(?:subscription|membership)\b',
  caseSensitive: false,
);

// 先去掉描述折扣、普通购物或取消操作的片段，保留同一备注中独立的订阅词。
final _nonSubscriptionTerms = RegExp(
  r'(?:(?:京东\s*plus|88\s*vip)\s*(?:会员)?|会员)\s*(?:专享价|价|折扣|优惠券?|积分|店|超市)|'
  r'(?:取消|关闭|退订|未开通)\s*(?:京东\s*plus|88\s*vip|会员|订阅|自动续费)|订阅号',
  caseSensitive: false,
);

bool isSubscriptionNote(String note) =>
    note.isNotEmpty &&
    _subscriptionTerms.hasMatch(note.replaceAll(_nonSubscriptionTerms, ' '));

final _monthly = RegExp(
  r'月付|按月|月度|包月|月卡|月费|一个月|(?<![0-9])1个月|\bmonthly\b',
  caseSensitive: false,
);
final _yearly = RegExp(
  r'年付|按年|年度|包年|年卡|年费|一年|(?<![0-9])12个月|\b(?:annual(?:ly)?|yearly)\b',
  caseSensitive: false,
);

final _biennial = RegExp(
  r'(?:两|二|双|(?<![0-9])2)年|(?<![0-9])24\s*个?月|\b(?:biennial(?:ly)?|(?:two|2)[ -]years?)\b',
  caseSensitive: false,
);

final _monthCount = RegExp(
  r'(?<![\d.])([1-9]\d{0,3})\s*(?:个月|月付|[- ]?months?\b)',
  caseSensitive: false,
);
final _quarterly = RegExp(
  r'季付|季卡|包季|季度|按季|季费|三个月|\bquarterly\b',
  caseSensitive: false,
);
final _halfYear = RegExp(
  r'半年|六个月|\bsemi[- ]?annual(?:ly)?\b',
  caseSensitive: false,
);

SubscriptionMark? subscriptionPeriod(LedgerEntry entry) {
  if (entry.type != EntryType.expense ||
      entry.subscriptionMark == SubscriptionMark.excluded) {
    return null;
  }
  if (entry.subscriptionMark != SubscriptionMark.automatic) {
    return entry.subscriptionMark;
  }
  if (!isSubscriptionNote(entry.note)) return null;
  final explicitMonths = _monthCount.firstMatch(entry.note);
  if (explicitMonths != null) {
    return SubscriptionMark.forMonths(int.parse(explicitMonths[1]!));
  }
  if (_halfYear.hasMatch(entry.note)) return SubscriptionMark.forMonths(6);
  if (_quarterly.hasMatch(entry.note)) return SubscriptionMark.forMonths(3);
  if (_biennial.hasMatch(entry.note)) return SubscriptionMark.biennial;
  final monthly = _monthly.hasMatch(entry.note);
  final yearly = _yearly.hasMatch(entry.note);
  if (monthly == yearly) return SubscriptionMark.unspecified;
  return monthly ? SubscriptionMark.monthly : SubscriptionMark.yearly;
}

/// 将净实付均摊到从记账日（含）到下一周期同日（不含）的实际日历天数。
double subscriptionDailyCost(
  LedgerEntry entry,
  SubscriptionMark period,
  DateTime today,
) {
  final months = period.months;
  final start = entry.occurredAt;
  if (months == null || calendarDaysBetween(start, today) < 0) return 0;
  final end = addCalendarMonths(start, months, start.day);
  if (calendarDaysBetween(today, end) <= 0) return 0;
  return entry.netBaseAmount / calendarDaysBetween(start, end);
}
