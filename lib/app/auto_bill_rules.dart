import 'category_tree.dart';
import 'models.dart';
import 'veri_fin_controller.dart';

/// Suggestions derived from the current ledger for either confirmation UI.
class AutoBillSuggestions {
  const AutoBillSuggestions({
    this.categoryId,
    this.accountId,
    this.platformTag,
  });

  factory AutoBillSuggestions.forDraft(
    VeriFinController controller,
    Map<Object?, Object?> draft,
  ) {
    final type = EntryType.fromStorage(draft['type'] as String? ?? 'expense');
    final timestamp = draft['occurredAt'];
    final occurredAt = timestamp is int
        ? DateTime.fromMillisecondsSinceEpoch(timestamp)
        : DateTime.now();
    final categories = controller.categoriesForType(type);
    final merchant = _normalized(draft['merchant']);
    final category =
        _historicalCategory(
          controller.entries,
          categories,
          type,
          merchant,
          occurredAt,
        ) ??
        _suggestCategory(categories, type, draft, occurredAt) ??
        categories.where((category) => category.isUncategorized).firstOrNull;
    final tag = (draft['platformTag'] as String?)?.trim();
    return AutoBillSuggestions(
      categoryId: category?.id,
      accountId: _suggestAccount(controller.accounts, draft)?.id,
      platformTag: tag == null || tag.isEmpty ? null : tag,
    );
  }

  static const draftTagId = 'auto-bill-platform-suggestion';
  final String? categoryId;
  final String? accountId;
  final String? platformTag;

  Tag? tagFor(String bookId, Iterable<Tag> tags) {
    final label = platformTag;
    if (label == null) return null;
    return tags
            .where((tag) => tag.bookId == bookId && tag.label == label)
            .firstOrNull ??
        Tag(id: draftTagId, bookId: bookId, label: label);
  }

  Map<String, Object?> toFields() => {
    'suggestedCategoryId': categoryId,
    'suggestedAccountId': accountId,
    'suggestedPlatformTag': platformTag,
  };

  static String _normalized(Object? value) =>
      value is String ? normalizedCategoryLabel(value) : '';

  static Category? _historicalCategory(
    List<LedgerEntry> entries,
    List<Category> categories,
    EntryType type,
    String merchant,
    DateTime occurredAt,
  ) {
    if (merchant.isEmpty) return null;
    final byId = {
      for (final category in categories)
        if (!category.isUncategorized && !category.isBalanceAdjust)
          category.id: category,
    };
    LedgerEntry? latest;
    for (final entry in entries) {
      if (entry.type != type ||
          entry.occurredAt.isAfter(occurredAt) ||
          !byId.containsKey(entry.categoryId)) {
        continue;
      }
      final note = _normalized(entry.note);
      if (note != merchant && !note.startsWith('$merchant · ')) continue;
      if (latest == null || entry.occurredAt.isAfter(latest.occurredAt)) {
        latest = entry;
      }
    }
    return byId[latest?.categoryId];
  }

  static final _snacks = RegExp(r'零食|薯片|坚果|辣条|糕点|饼干');
  static final _drinks = RegExp(r'奶茶|咖啡|果茶|饮品|饮料|酒水|啤酒|星巴克|瑞幸|库迪');
  static final _restaurant = RegExp(r'餐厅|餐饮|餐馆|食堂|小吃|快餐|面馆|饭店|外卖|麦当劳|肯德基|海底捞');
  static final _meal = RegExp(r'早餐|午餐|晚餐');

  static Category? _suggestCategory(
    List<Category> categories,
    EntryType type,
    Map<Object?, Object?> draft,
    DateTime time,
  ) {
    final hint = draft['categoryKey'];
    final fallback = categories
        .where((category) => category.key == hint && hint != null && hint != '')
        .firstOrNull;
    if (type != EntryType.expense) return fallback;
    final dining = categories
        .where((category) => category.key == 'dining')
        .firstOrNull;
    if (dining == null) return fallback;
    final merchant = _normalized(draft['merchant']);
    final goods = _normalized(draft['product']);
    final text = '$merchant $goods';
    final explicitMeal = _meal.firstMatch(text)?.group(0);
    final isRestaurant = _restaurant.hasMatch(merchant);
    final useMealTime = isRestaurant || merchant == '沈阳理工大学';
    final hour = time.hour;
    final label =
        explicitMeal ??
        switch (text) {
          _ when _drinks.hasMatch(text) && !_snacks.hasMatch(text) => '饮料酒水',
          _ when _snacks.hasMatch(text) && !_drinks.hasMatch(text) => '休闲零食',
          _ when useMealTime && hour >= 5 && hour < 10 => '早餐',
          _ when useMealTime && hour >= 11 && hour < 15 => '午餐',
          _ when useMealTime && hour >= 17 && hour < 22 => '晚餐',
          _ => null,
        };
    if (label != null) {
      return categories
              .where(
                (category) =>
                    category.parentId == dining.id &&
                    normalizedCategoryLabel(category.label) == label,
              )
              .firstOrNull ??
          dining;
    }
    return fallback ?? (isRestaurant ? dining : null);
  }

  static final _cardSuffix = RegExp(r'^\d{4}$');
  static final _ccbName = RegExp(r'^(?:中国建设银行|建设银行|建行)');

  static Account? _suggestAccount(
    List<Account> accounts,
    Map<Object?, Object?> draft,
  ) {
    final available = accounts.where(
      (a) => !a.hidden && a.currencyCode == 'CNY',
    );
    final method = _normalized(draft['paymentMethod']);
    final isCcb = _ccbName.hasMatch(method);
    final ccbCardType = switch (method) {
      _ when method.contains('储蓄卡') || method.contains('借记卡') =>
        AccountType.debitCard,
      _ when method.contains('信用卡') => AccountType.creditCard,
      _ => null,
    };
    final ccbAccounts = available.where(
      (account) =>
          _ccbName.hasMatch(_normalized(account.name)) &&
          (ccbCardType == null || account.type == ccbCardType),
    );
    final suffix = _normalized(draft['bankLast4']);
    if (_cardSuffix.hasMatch(suffix)) {
      return available
          .where(
            (account) =>
                account.type.supportsCardLast4 &&
                (account.cardLast4.isEmpty
                        ? cardLast4Of(account.cardNumber)
                        : account.cardLast4) ==
                    suffix,
          )
          .singleOrNull;
    }
    if (method == '余额宝') {
      final alipay = available
          .where((account) => _normalized(account.name) == '支付宝')
          .singleOrNull;
      if (alipay != null) return alipay;
    }
    if (method.isNotEmpty) {
      final explicit = available
          .where((a) => _normalized(a.name) == method)
          .singleOrNull;
      if (explicit != null) return explicit;
    }
    if (isCcb) {
      return ccbAccounts
          .where((account) => account.type.supportsCardLast4)
          .singleOrNull;
    }
    final source = draft['sourcePackage'];
    final names = switch (method) {
      '零钱' || '微信零钱' => const {'微信', '微信支付', '微信零钱', '零钱'},
      '零钱通' => const {'零钱通', '微信零钱通'},
      '余额宝' => const {'余额宝', '支付宝余额宝'},
      '余额' when source == 'com.eg.android.AlipayGphone' => const {
        '支付宝',
        '支付宝余额',
        '余额',
      },
      '' => switch (source) {
        'com.tencent.mm' => const {'微信', '微信支付', '微信零钱', '零钱'},
        'com.eg.android.AlipayGphone' => const {'支付宝', '支付宝余额'},
        'com.chinamworld.main' => const {'建设银行', '中国建设银行', '建行'},
        'com.jingdong.app.mall' => const {'京东', '京东钱包'},
        'com.xunmeng.pinduoduo' => const {'拼多多', '多多钱包'},
        _ => const <String>{},
      },
      _ => const <String>{},
    };
    return available
        .where((a) => names.contains(_normalized(a.name)))
        .singleOrNull;
  }
}
