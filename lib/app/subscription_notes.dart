/// 仅根据支出备注识别订阅。规则在本机执行，原始交易不需要迁移。
library;

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
