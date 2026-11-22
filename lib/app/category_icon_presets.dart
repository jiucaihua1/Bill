/// Built-in category icon preset definitions and resolvers.
library;

/// Active category icon preset mode.
enum CategoryIconPreset {
  /// Default Material [IconData] icons.
  builtin,

  /// Monochrome thin-line SVG assets tinted by category/type accent color.
  line,

  /// Multi-color flat/duotone SVG assets.
  colored,

  /// Curated emoji glyphs for every category.
  emoji,
}

/// Maps Chinese category names (from user bills & default seeds) to preset keys.
const Map<String, String> categoryNameToPresetKey = <String, String>{
  // 食品餐饮
  '食品餐饮': 'dining',
  '早餐': 'breakfast',
  '午餐': 'lunch',
  '晚餐': 'dinner',
  '饮料酒水': 'drink',
  '休闲零食': 'snack',
  '水果': 'fruit',
  '生鲜食品': 'fresh',
  '请客吃饭': 'treat',
  '粮油调味': 'seasoning',

  // 购物消费
  '购物消费': 'shopping',
  '日常家居': 'home_goods',
  '服饰运动': 'clothing',
  '手机数码': 'digital',
  '个护美妆': 'beauty',
  '配饰腕表': 'watch',
  '虚拟充值': 'topup',
  '生活电器': 'appliance',
  '装修装饰': 'decor',

  // 出行交通
  '出行交通': 'transport',
  '公共交通': 'bus',
  '地铁': 'metro',
  '打车': 'taxi',
  '共享单车': 'bike',
  '火车': 'train',
  '酒店': 'hotel',
  '保养修车': 'car_service',

  // 居家生活
  '居家生活': 'housing',
  '校园卡': 'campus_card',
  '话费宽带': 'telecom',
  '个人清洁': 'personal_care',
  '电费': 'electricity',
  '水费': 'water',
  '水电煤': 'utilities',
  '家政清洁': 'housekeeping',
  '空调': 'ac',

  // 休闲娱乐
  '休闲娱乐': 'entertainment',
  '游戏': 'game',
  '运动健身': 'fitness',
  '旅游度假': 'travel',

  // 文化教育
  '文化教育': 'education',
  '学费': 'tuition',
  '培训考试': 'exam',
  '书报杂志': 'books',

  // 送礼人情
  '送礼人情': 'social',
  '红包': 'redpacket',
  '礼物': 'gift',
  '打赏': 'tip',
  '孝敬长辈': 'elder',
  '借出': 'lend',

  // 健康医疗 & 其他
  '健康医疗': 'medical',
  '买药': 'medicine',
  '医院': 'hospital',
  '其他': 'other',
  '无': 'other',

  // 收入
  '收入': 'income',
  '生活费': 'allowance',
  '收红包': 'redpacket_in',
  '二手闲置': 'secondhand',
  '研究生低保': 'subsidy',
  '奖金': 'bonus',
  '助学贷款': 'loan',
  '工资': 'salary',
  '兼职外快': 'part_time',
  '礼金人情': 'gift_money',

  // 转账 & 系统
  '转出': 'transfer_out',
  '转入': 'transfer_in',
  '还款': 'repayment',
  '余额调整': 'adjust',
};

/// Maps built-in [categoryIconCodes] to preset asset keys as fallback.
const Map<String, String> iconCodeToPresetKey = <String, String>{
  'category': 'other',
  'dining': 'dining',
  'coffee': 'drink',
  'drink': 'drink',
  'snack': 'snack',
  'cake': 'treat',
  'grocery': 'fresh',
  'shopping': 'shopping',
  'clothing': 'clothing',
  'beauty': 'beauty',
  'haircut': 'personal_care',
  'transport': 'transport',
  'car': 'car_service',
  'taxi': 'taxi',
  'fuel': 'car_service',
  'parking': 'car_service',
  'train': 'train',
  'flight': 'travel',
  'bike': 'bike',
  'housing': 'housing',
  'rent': 'housing',
  'utilities': 'utilities',
  'water': 'water',
  'phone': 'telecom',
  'internet': 'telecom',
  'repair': 'car_service',
  'furniture': 'home_goods',
  'laundry': 'housekeeping',
  'entertainment': 'entertainment',
  'game': 'game',
  'music': 'entertainment',
  'sports': 'fitness',
  'book': 'books',
  'education': 'education',
  'travel': 'travel',
  'hotel': 'hotel',
  'medical': 'medical',
  'medicine': 'medicine',
  'pet': 'other',
  'baby': 'elder',
  'family': 'elder',
  'love': 'gift',
  'gift': 'gift',
  'redpacket': 'redpacket',
  'charity': 'tip',
  'electronics': 'digital',
  'subscription': 'topup',
  'work': 'part_time',
  'salary': 'salary',
  'bonus': 'bonus',
  'savings': 'allowance',
  'interest': 'income',
  'investment': 'bonus',
  'insurance': 'medical',
  'tax': 'subsidy',
  'refund': 'transfer_in',
  'repayment': 'repayment',
  'transfer_out': 'transfer_out',
  'transfer_in': 'transfer_in',
  'star': 'tip',
  'adjust': 'adjust',
};

/// Emoji representation for all 68 preset keys.
const Map<String, String> presetKeyToEmoji = <String, String>{
  'dining': '🍽️',
  'breakfast': '🍳',
  'lunch': '🍱',
  'dinner': '🍜',
  'drink': '🧋',
  'snack': '🍪',
  'fruit': '🍒',
  'fresh': '🥬',
  'treat': '🍲',
  'seasoning': '🧂',
  'shopping': '🛍️',
  'home_goods': '🛋️',
  'clothing': '👕',
  'digital': '📱',
  'beauty': '💄',
  'watch': '⌚',
  'topup': '🪙',
  'appliance': '🔌',
  'decor': '🪴',
  'transport': '🚗',
  'bus': '🚌',
  'metro': '🚇',
  'taxi': '🚕',
  'bike': '🚲',
  'train': '🚄',
  'hotel': '🏨',
  'car_service': '🔧',
  'housing': '🏠',
  'campus_card': '🪪',
  'telecom': '📶',
  'personal_care': '🧴',
  'electricity': '⚡',
  'water': '💧',
  'utilities': '🔌',
  'housekeeping': '🧹',
  'ac': '❄️',
  'entertainment': '🎬',
  'game': '🎮',
  'fitness': '🏋️',
  'travel': '✈️',
  'education': '🎓',
  'tuition': '🏫',
  'exam': '📝',
  'books': '📚',
  'social': '🤝',
  'redpacket': '🧧',
  'redpacket_in': '🧧',
  'gift': '🎁',
  'tip': '🌟',
  'elder': '🍵',
  'lend': '💸',
  'medical': '🩺',
  'medicine': '💊',
  'hospital': '🏥',
  'other': '📦',
  'income': '💰',
  'allowance': '🐷',
  'secondhand': '♻️',
  'subsidy': '🧾',
  'bonus': '🏆',
  'loan': '📜',
  'salary': '💵',
  'part_time': '💼',
  'gift_money': '💌',
  'transfer_out': '📤',
  'transfer_in': '📥',
  'repayment': '💳',
  'adjust': '⚖️',
};

/// Resolves the preset key for a category by its [categoryName] first,
/// then falls back to [iconCode], and finally `'other'`.
String resolveCategoryPresetKey({
  required String iconCode,
  String? categoryName,
}) {
  final trimmed = categoryName?.trim();
  if (trimmed != null && trimmed.isNotEmpty) {
    final byName = categoryNameToPresetKey[trimmed];
    if (byName != null) return byName;
  }
  final byCode = iconCodeToPresetKey[iconCode];
  if (byCode != null) return byCode;
  if (presetKeyToEmoji.containsKey(iconCode)) return iconCode;
  return 'other';
}

/// Returns the bundled SVG asset path for [preset] and [presetKey], or null
/// when [preset] does not use SVG assets.
String? categoryPresetSvgAsset(CategoryIconPreset preset, String presetKey) {
  switch (preset) {
    case CategoryIconPreset.line:
      return 'assets/category_icons/line/$presetKey.svg';
    case CategoryIconPreset.colored:
      return 'assets/category_icons/colored/$presetKey.svg';
    case CategoryIconPreset.builtin:
    case CategoryIconPreset.emoji:
      return null;
  }
}

/// Returns the preset emoji for [presetKey].
String categoryPresetEmoji(String presetKey) =>
    presetKeyToEmoji[presetKey] ?? '📦';
