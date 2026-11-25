import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'category_suggest.dart';
import 'category_tree.dart';
import 'logging/app_logger.dart';
import 'models.dart';
import 'veri_fin_controller.dart';

part 'auto_bill_rule_config.dart';
part 'auto_bill_merchant_index.dart';

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
    for (final window in _AutoBillRuleConfig.current.mealWindows) {
      if (minutes >= window.start && minutes < window.end) {
        return window.period;
      }
    }
    return other;
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
    Iterable<LedgerEntry> history() sync* {
      yield* controller.entries.where(
        (entry) => entry.type == type && !entry.occurredAt.isAfter(occurredAt),
      );
    }

    final merchant = _merchantName(draft['merchant']);
    final index = controller.autoBillMerchantIndex;
    final merchantHistory = index._history(type, merchant, occurredAt);
    final period = _MealPeriod.at(occurredAt);
    final exact = _historicalCategory(
      merchantHistory,
      index._history(type, merchant, occurredAt, period),
      categoryById,
      merchant,
      period,
    );
    final category =
        exact.category ??
        (exact.matched
            ? null
            : _similarCategory(
                history(),
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
        index,
        type,
        occurredAt,
        merchant,
        merchantHistory,
      )?.id,
      platformTag: tag == null || tag.isEmpty ? null : tag,
    );
  }

  static const draftTagId = 'auto-bill-platform-suggestion';

  /// Load once in the ledger engine before it starts accepting drafts.
  static Future<void> preloadRules({AppLogger? logger}) =>
      _AutoBillRuleConfig.preload(logger);

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

  static String _merchantName(Object? value) {
    final rules = _AutoBillRuleConfig.current;
    var merchant = _normalized(value);
    while (true) {
      if (rules.genericRemarks.contains(merchant)) return '';
      final shorter = merchant.replaceFirst(rules.merchantSuffix, '');
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
    Iterable<LedgerEntry> periodHistory,
    Map<String, Category> categories,
    String merchant,
    _MealPeriod period,
  ) {
    final inPeriod = periodHistory
        .map((entry) => categories[entry.categoryId])
        .whereType<Category>()
        .firstOrNull;
    if (inPeriod != null &&
        (!_isDiningParent(inPeriod) || period == _MealPeriod.other)) {
      return (category: inPeriod, matched: true);
    }
    Category? lastMeal;
    Category? lastNonMeal;
    // The active ledger exposes its entries newest first.
    for (final entry in merchantHistory) {
      final category = categories[entry.categoryId];
      if (category == null) continue;
      if (_isMealCategory(category)) {
        lastMeal ??= category;
      } else {
        lastNonMeal ??= category;
      }
      if (lastMeal != null && lastNonMeal != null) break;
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
    final genericRemarks = _AutoBillRuleConfig.current.genericRemarks;
    if (query.isEmpty || genericRemarks.contains(query)) return null;
    final amount = draft['amount'];
    final ids = categories.keys.toSet();
    final suggestion = suggestEntry(
      history: history.where((entry) {
        final category = categories[entry.categoryId];
        return category != null &&
            !genericRemarks.contains(_normalized(entry.note)) &&
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

  static const _mealLabels = {'早餐', '午餐', '晚餐'};

  static bool _isMealMerchant(String merchant) {
    final rules = _AutoBillRuleConfig.current;
    return rules.restaurant.hasMatch(merchant) ||
        rules.mealMerchants.contains(merchant);
  }

  static bool _isMealCategory(Category category) =>
      !category.isRoot && _mealLabels.contains(_normalized(category.label));

  static bool _isDiningParent(Category category) =>
      category.key == 'dining' ||
      _AutoBillRuleConfig.current.diningLabels.contains(
        _normalized(category.label),
      );

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
    final rules = _AutoBillRuleConfig.current;
    final explicitMeal = rules.explicitMealLabel(text);
    final isRestaurant = rules.restaurant.hasMatch(rawMerchant);
    final hasDrinks = rules.drinks.hasMatch(text);
    final hasSnacks = rules.snacks.hasMatch(text);
    final label =
        explicitMeal ??
        switch ((hasDrinks, hasSnacks)) {
          (true, false) => '饮料酒水',
          (false, true) => '休闲零食',
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
    final retail = rules.retail.hasMatch(rawMerchant)
        ? categories.where((category) => category.key == 'shopping').firstOrNull
        : null;
    return fallback ?? retail ?? (isRestaurant ? dining : null);
  }

  static final _cardSuffix = RegExp(r'^\d{4}$');
  static final _ccbName = RegExp(r'^(?:中国建设银行|建设银行|建行)');

  /// Resolve a stated payment method without guessing from past transactions.
  static Account? matchingPaymentAccount(
    Iterable<Account> available,
    Map<Object?, Object?> draft,
  ) {
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
    return available
        .where((account) => methodNames.contains(_normalized(account.name)))
        .singleOrNull;
  }

  static Account? _suggestAccount(
    VeriFinController controller,
    Map<Object?, Object?> draft,
    AutoBillMerchantIndex index,
    EntryType type,
    DateTime occurredAt,
    String merchant,
    Iterable<LedgerEntry> merchantHistory,
  ) {
    final available = controller.accounts.where(
      (a) => !a.hidden && a.currencyCode == 'CNY',
    );
    final explicit = matchingPaymentAccount(available, draft);
    if (explicit != null ||
        _cardSuffix.hasMatch(_normalized(draft['bankLast4']))) {
      return explicit;
    }
    final method = _normalized(draft['paymentMethod']);
    final source = draft['sourcePackage'];
    final accountsById = {for (final account in available) account.id: account};
    final sourceIds = source is String
        ? controller.autoBillAccountHistory(source)
        : const <String>[];
    Account? sourceAccount;
    for (final id in sourceIds) {
      final entry = index._byId[id];
      if (entry == null ||
          entry.type != type ||
          entry.occurredAt.isAfter(occurredAt)) {
        continue;
      }
      final account = accountsById[entry.accountId];
      if (account == null) continue;
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
