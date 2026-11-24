part of 'auto_bill_rules.dart';

typedef _MealWindow = ({_MealPeriod period, int start, int end});

class _AutoBillRuleConfig {
  _AutoBillRuleConfig.fromJson(Map<String, Object?> json) {
    final windows = _object(json['mealWindows']);
    final labels = <String, String>{};
    final sortedWindows = <_MealWindow>[];
    for (final period in _MealPeriod.values) {
      final label = period.categoryLabel;
      if (label == null) continue;
      final window = _object(windows[period.name]);
      final start = _minutes(window['start']);
      final end = _minutes(window['end'], allowEndOfDay: true);
      if (start >= end) throw const FormatException('Empty meal window');
      sortedWindows.add((period: period, start: start, end: end));
      for (final keyword in _strings(window['keywords'])) {
        if (labels.containsKey(keyword)) {
          throw const FormatException('Duplicate meal keyword');
        }
        labels[keyword] = label;
      }
    }
    sortedWindows.sort((a, b) => a.start.compareTo(b.start));
    for (var index = 1; index < sortedWindows.length; index++) {
      if (sortedWindows[index].start < sortedWindows[index - 1].end) {
        throw const FormatException('Overlapping meal windows');
      }
    }
    mealWindows = List.unmodifiable(sortedWindows);
    _mealLabelsByKeyword = Map.unmodifiable(labels);
    _mealKeywords = _keywordPattern(labels.keys);

    final keywords = _object(json['keywords']);
    drinks = _keywordPattern(_strings(keywords['drinks']));
    snacks = _keywordPattern(_strings(keywords['snacks']));
    restaurant = _keywordPattern(_strings(keywords['restaurant']));
    retail = _keywordPattern(_strings(keywords['retail']));
    diningLabels = Set.unmodifiable(_strings(json['diningLabels']));
    genericRemarks = Set.unmodifiable(_strings(json['genericRemarks']));

    final suffixes = [
      // Patterns are tried first so a named branch is stripped as a whole.
      ..._strings(json['merchantSuffixPatterns'], normalize: false),
      ..._strings(json['merchantSuffixes']).map(RegExp.escape),
    ];
    merchantSuffix = suffixes.isEmpty
        ? RegExp(r'(?!)')
        : RegExp(r'\s*(?:' + suffixes.join('|') + r')\s*$');
    mealMerchants = Set.unmodifiable(_strings(json['mealMerchants']));
  }

  static const _assetPath = 'assets/rules/auto_bill_rules.json';
  static _AutoBillRuleConfig? _loaded;
  static Future<void>? _loading;
  static final _fallback = _AutoBillRuleConfig.fromJson(_defaultRules);

  static _AutoBillRuleConfig get current => _loaded ?? _fallback;

  static Future<void> preload(AppLogger? logger) => _loading ??= _load(logger);

  static Future<void> _load(AppLogger? logger) async {
    try {
      final json = jsonDecode(await rootBundle.loadString(_assetPath));
      _loaded = _AutoBillRuleConfig.fromJson(_object(json));
    } catch (error) {
      _loaded = _fallback;
      logger?.warning(
        'Bundled auto-bill rules unavailable; using defaults '
        '(${error.runtimeType})',
        source: 'auto-capture',
      );
      return;
    }
    logger?.info('Bundled auto-bill rules loaded', source: 'auto-capture');
  }

  late final List<_MealWindow> mealWindows;
  late final Map<String, String> _mealLabelsByKeyword;
  late final RegExp _mealKeywords;
  late final RegExp drinks;
  late final RegExp snacks;
  late final RegExp restaurant;
  late final RegExp retail;
  late final RegExp merchantSuffix;
  late final Set<String> diningLabels;
  late final Set<String> mealMerchants;
  late final Set<String> genericRemarks;

  String? explicitMealLabel(String text) =>
      _mealLabelsByKeyword[_mealKeywords.firstMatch(text)?.group(0)];

  static Map<String, Object?> _object(Object? value) {
    if (value is Map<String, Object?>) return value;
    throw const FormatException('Expected an object in auto-bill rules');
  }

  static Iterable<String> _strings(Object? value, {bool normalize = true}) {
    if (value is! List<Object?>) {
      throw const FormatException('Expected a list in auto-bill rules');
    }
    return value.map((item) {
      if (item is! String || item.trim().isEmpty) {
        throw const FormatException('Expected a nonempty rule');
      }
      return normalize ? normalizedCategoryLabel(item) : item;
    });
  }

  static RegExp _keywordPattern(Iterable<String> words) =>
      RegExp(words.isEmpty ? r'(?!)' : words.map(RegExp.escape).join('|'));

  static final _clock = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');

  static int _minutes(Object? value, {bool allowEndOfDay = false}) {
    if (allowEndOfDay && value == '24:00') return 24 * 60;
    if (value is! String || !_clock.hasMatch(value)) {
      throw const FormatException('Invalid time in auto-bill meal window');
    }
    return int.parse(value.substring(0, 2)) * 60 +
        int.parse(value.substring(3));
  }
}

/// Built-in defaults for missing or invalid bundled rules.
const _defaultRules = {
  'mealWindows': {
    'breakfast': {
      'start': '05:00',
      'end': '10:30',
      'keywords': ['早餐'],
    },
    'lunch': {
      'start': '10:30',
      'end': '15:30',
      'keywords': ['午餐'],
    },
    'dinner': {
      'start': '16:30',
      'end': '22:00',
      'keywords': ['晚餐'],
    },
  },
  'keywords': {
    'drinks': ['奶茶', '咖啡', '果茶', '饮品', '饮料', '酒水', '啤酒', '星巴克', '瑞幸', '库迪'],
    'snacks': ['零食', '薯片', '坚果', '辣条', '糕点', '饼干'],
    'restaurant': [
      '餐厅',
      '餐饮',
      '餐馆',
      '食堂',
      '小吃',
      '快餐',
      '面馆',
      '饭店',
      '外卖',
      '麦当劳',
      '肯德基',
      '海底捞',
    ],
    'retail': ['超市', '便利店', '便利商店', '杂货店'],
  },
  'mealMerchants': ['沈阳理工大学'],
  'diningLabels': ['食品', '食品餐饮', '餐饮', '三餐'],
  'merchantSuffixes': [
    '有限责任公司',
    '股份有限公司',
    '有限公司',
    '分公司',
    '个体工商户',
    '分店',
    '门店',
    '旗舰店',
  ],
  'merchantSuffixPatterns': [r'\([^()]*\)', r'(?:\s+|[-‐–—·])[^\s-‐–—·]+店'],
  'genericRemarks': ['微信支付', '支付宝支付', '建设银行自动识别', '微信自动识别', '支付宝自动识别'],
};
