import 'category_suggest.dart';
import 'category_tree.dart';
import 'models.dart';
import 'veri_fin_controller.dart';

enum _MealPeriod {
  breakfast('早餐'),
  lunch('午餐'),
  dinner('晚餐'),
  other(null);

  const _MealPeriod(this.categoryLabel);
  final String? categoryLabel;

  static _MealPeriod at(DateTime time) {
    final local = time.toLocal();
    final minutes = local.hour * 60 + local.minute;
    return switch (minutes) {
      >= 300 && < 630 => breakfast,
      >= 630 && < 930 => lunch,
      >= 990 && < 1320 => dinner,
      _ => other,
    };
  }
}

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
    final categoryById = {
      for (final category in categories)
        if (!category.isUncategorized && !category.isBalanceAdjust)
          category.id: category,
    };
    final history = controller.entries.where(
      (entry) => entry.type == type && !entry.occurredAt.isAfter(occurredAt),
    );
    final merchant = _merchantName(draft['merchant']);
    final merchantHistory = history.where(
      (entry) =>
          merchant.isNotEmpty && _merchantFromNote(entry.note) == merchant,
    );
    final period = _MealPeriod.at(occurredAt);
    final exact = _historicalCategory(
      merchantHistory,
      categoryById,
      merchant,
      period,
    );
    final category =
        exact.category ??
        (exact.matched
            ? null
            : _similarCategory(
                history,
                categoryById,
                type,
                draft,
                merchant,
                occurredAt,
                period,
              )) ??
        _suggestCategory(categories, type, draft, merchant, period) ??
        categories.where((category) => category.isUncategorized).firstOrNull;
    final tag = (draft['platformTag'] as String?)?.trim();
    return AutoBillSuggestions(
      categoryId: category?.id,
      accountId: _suggestAccount(
        controller,
        draft,
        history,
        merchant,
        merchantHistory,
      )?.id,
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

  static final _merchantSuffix = RegExp(
    r'\s*(?:\([^()]*\)|有限责任公司|股份有限公司|有限公司|分公司|个体工商户|(?:\s+|[-‐–—·])[^\s-‐–—·]+店|分店|门店|旗舰店)\s*$',
  );
  static const _genericRemarks = {
    '微信支付',
    '支付宝支付',
    '建设银行自动识别',
    '微信自动识别',
    '支付宝自动识别',
  };

  static String _merchantName(Object? value) {
    final name = _normalized(value);
    if (_genericRemarks.contains(name)) return '';
    var merchant = name;
    while (true) {
      final shorter = merchant.replaceFirst(_merchantSuffix, '');
      if (shorter == merchant || shorter.runes.length < 2) return merchant;
      merchant = shorter;
    }
  }

  static String _merchantFromNote(String note) {
    final separator = note.indexOf(' · ');
    return _merchantName(separator == -1 ? note : note.substring(0, separator));
  }

  static ({Category? category, bool matched}) _historicalCategory(
    Iterable<LedgerEntry> merchantHistory,
    Map<String, Category> categories,
    String merchant,
    _MealPeriod period,
  ) {
    Category? inPeriod;
    Category? lastMeal;
    Category? lastNonMeal;
    // The active ledger exposes its entries newest first.
    for (final entry in merchantHistory) {
      final category = categories[entry.categoryId];
      if (category == null) continue;
      if (_MealPeriod.at(entry.occurredAt) == period) {
        inPeriod ??= category;
        if (!_isDiningParent(inPeriod) || period == _MealPeriod.other) {
          return (category: inPeriod, matched: true);
        }
      }
      if (_isMealCategory(category)) {
        lastMeal ??= category;
      } else {
        lastNonMeal ??= category;
      }
    }
    final label = period.categoryLabel;
    if (inPeriod != null) {
      final meal =
          label != null && (_isMealMerchant(merchant) || lastMeal != null)
          ? _childWithLabel(categories.values, inPeriod, label)
          : null;
      return (category: meal ?? inPeriod, matched: true);
    }
    if (label != null && lastMeal != null) {
      final parent = categories[lastMeal.parentId];
      final sibling = _childWithLabel(categories.values, parent, label);
      final dining = _diningCategory(categories.values);
      return (
        category:
            sibling ??
            _childWithLabel(categories.values, dining, label) ??
            parent ??
            dining,
        matched: true,
      );
    }
    final meal =
        label != null &&
            lastNonMeal != null &&
            _isDiningParent(lastNonMeal) &&
            _isMealMerchant(merchant)
        ? _childWithLabel(categories.values, lastNonMeal, label)
        : null;
    return (
      category: meal ?? lastNonMeal,
      matched: lastNonMeal != null || lastMeal != null,
    );
  }

  static Category? _similarCategory(
    Iterable<LedgerEntry> history,
    Map<String, Category> categories,
    EntryType type,
    Map<Object?, Object?> draft,
    String merchant,
    DateTime time,
    _MealPeriod period,
  ) {
    final product = _normalized(draft['product']);
    final note = [
      merchant,
      product,
    ].where((value) => value.isNotEmpty).join(' · ');
    final query = note.isEmpty ? _normalized(draft['note']) : note;
    if (query.isEmpty || _genericRemarks.contains(query)) return null;
    final amount = draft['amount'];
    final ids = categories.keys.toSet();
    final suggestion = suggestEntry(
      history: history.where((entry) {
        final category = categories[entry.categoryId];
        return category != null &&
            !_genericRemarks.contains(_normalized(entry.note)) &&
            (!_isMealCategory(category) ||
                _MealPeriod.at(entry.occurredAt) == period);
      }),
      expenseCategoryIds: type == EntryType.expense ? ids : const {},
      incomeCategoryIds: type == EntryType.income ? ids : const {},
      note: query,
      amount: amount is num ? amount.toDouble() : 0,
      currencyCode: 'CNY',
      hour: time.toLocal().hour,
      forcedType: type,
      minimumNoteSimilarity: 0.5,
    );
    return categories[suggestion.categoryId];
  }

  static final _snacks = RegExp(r'零食|薯片|坚果|辣条|糕点|饼干');
  static final _drinks = RegExp(r'奶茶|咖啡|果茶|饮品|饮料|酒水|啤酒|星巴克|瑞幸|库迪');
  static final _restaurant = RegExp(r'餐厅|餐饮|餐馆|食堂|小吃|快餐|面馆|饭店|外卖|麦当劳|肯德基|海底捞');
  static final _retail = RegExp(r'超市|便利店|便利商店|杂货店');
  static final _meal = RegExp(r'早餐|午餐|晚餐');
  static const _mealLabels = {'早餐', '午餐', '晚餐'};
  static const _diningLabels = {'食品', '食品餐饮', '餐饮', '三餐'};

  static bool _isMealMerchant(String merchant) =>
      _restaurant.hasMatch(merchant) || merchant == '沈阳理工大学';

  static bool _isMealCategory(Category category) =>
      !category.isRoot && _mealLabels.contains(_normalized(category.label));

  static bool _isDiningParent(Category category) =>
      category.key == 'dining' ||
      _diningLabels.contains(_normalized(category.label));

  static Category? _diningCategory(Iterable<Category> categories) =>
      categories.where((category) => category.key == 'dining').firstOrNull ??
      categories
          .where((category) => category.isRoot && _isDiningParent(category))
          .singleOrNull;

  static Category? _childWithLabel(
    Iterable<Category> categories,
    Category? parent,
    String label,
  ) => parent == null
      ? null
      : categories
            .where(
              (category) =>
                  category.parentId == parent.id &&
                  _normalized(category.label) == label,
            )
            .firstOrNull;

  static Category? _suggestCategory(
    List<Category> categories,
    EntryType type,
    Map<Object?, Object?> draft,
    String merchant,
    _MealPeriod period,
  ) {
    final hint = draft['categoryKey'];
    final fallback = categories
        .where((category) => category.key == hint && hint != null && hint != '')
        .firstOrNull;
    if (type != EntryType.expense) return fallback;
    final dining = _diningCategory(categories);
    final rawMerchant = _normalized(draft['merchant']);
    final goods = _normalized(draft['product']);
    final text = '$rawMerchant $goods';
    final explicitMeal = _meal.firstMatch(text)?.group(0);
    final isRestaurant = _restaurant.hasMatch(rawMerchant);
    final label =
        explicitMeal ??
        switch (text) {
          _ when _drinks.hasMatch(text) && !_snacks.hasMatch(text) => '饮料酒水',
          _ when _snacks.hasMatch(text) && !_drinks.hasMatch(text) => '休闲零食',
          _ when isRestaurant || _isMealMerchant(merchant) =>
            period.categoryLabel,
          _ => null,
        };
    if (label != null && dining != null) {
      final child =
          _childWithLabel(categories, dining, label) ??
          categories
              .where((category) => category.isRoot && _isDiningParent(category))
              .map((parent) => _childWithLabel(categories, parent, label))
              .whereType<Category>()
              .singleOrNull;
      return child ?? dining;
    }
    final retail = _retail.hasMatch(rawMerchant)
        ? categories.where((category) => category.key == 'shopping').firstOrNull
        : null;
    return fallback ?? retail ?? (isRestaurant ? dining : null);
  }

  static final _cardSuffix = RegExp(r'^\d{4}$');
  static final _ccbName = RegExp(r'^(?:中国建设银行|建设银行|建行)');

  static Account? _suggestAccount(
    VeriFinController controller,
    Map<Object?, Object?> draft,
    Iterable<LedgerEntry> history,
    String merchant,
    Iterable<LedgerEntry> merchantHistory,
  ) {
    final available = controller.accounts.where(
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
      final explicit = ccbAccounts
          .where((account) => account.type.supportsCardLast4)
          .singleOrNull;
      if (explicit != null) return explicit;
    }
    final source = draft['sourcePackage'];
    final methodNames = switch (method) {
      '零钱' || '微信零钱' => const {'微信', '微信支付', '微信零钱', '零钱'},
      '零钱通' => const {'零钱通', '微信零钱通'},
      '余额宝' => const {'余额宝', '支付宝余额宝'},
      '余额' when source == 'com.eg.android.AlipayGphone' => const {
        '支付宝',
        '支付宝余额',
        '余额',
      },
      _ => const <String>{},
    };
    final explicitMethod = available
        .where((account) => methodNames.contains(_normalized(account.name)))
        .singleOrNull;
    if (explicitMethod != null) return explicitMethod;

    final accountsById = {for (final account in available) account.id: account};
    final sourceIds = source is String
        ? controller.autoBillAccountHistory(source)
        : const <String>[];
    final sourceIdSet = sourceIds.toSet();
    final historyById = sourceIds.isEmpty
        ? const <String, LedgerEntry>{}
        : {
            for (final entry in history)
              if (sourceIdSet.contains(entry.id)) entry.id: entry,
          };
    Account? sourceAccount;
    for (final id in sourceIds) {
      final entry = historyById[id];
      final account = accountsById[entry?.accountId];
      if (entry == null || account == null) continue;
      if (merchant.isNotEmpty && _merchantFromNote(entry.note) == merchant) {
        return account;
      }
      sourceAccount ??= account;
    }
    final merchantAccount = merchantHistory
        .map((entry) => accountsById[entry.accountId])
        .whereType<Account>()
        .firstOrNull;
    if (merchantAccount != null) return merchantAccount;
    if (sourceAccount != null) return sourceAccount;
    if (method.isNotEmpty) return null;
    final sourceNames = switch (source) {
      'com.tencent.mm' => const {'微信', '微信支付', '微信零钱', '零钱'},
      'com.eg.android.AlipayGphone' => const {'支付宝', '支付宝余额'},
      'com.chinamworld.main' => const {'建设银行', '中国建设银行', '建行'},
      'com.jingdong.app.mall' => const {'京东', '京东钱包'},
      'com.xunmeng.pinduoduo' => const {'拼多多', '多多钱包'},
      _ => const <String>{},
    };
    return available
        .where((a) => sourceNames.contains(_normalized(a.name)))
        .singleOrNull;
  }
}
