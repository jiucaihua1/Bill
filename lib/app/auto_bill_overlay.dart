import 'dart:async';

import 'package:flutter/services.dart';

import 'auto_bill_rules.dart';
import 'backup/backup_coordinator.dart';
import 'category_icon_presets.dart';
import 'currency_math.dart';
import 'l10n_outside_context.dart';
import 'ledger_math.dart';
import 'models.dart';
import 'veri_fin_controller.dart';
import 'widgets/widget_service.dart';

String autoBookkeepingNotificationSummary(VeriFinController controller) {
  final expense = dayExpenseTotal(controller.entries, DateTime.now());
  return l10nForPreference(
    controller.localePreference,
  ).autoCaptureTodayExpense(formatExpenseAmount(expense));
}

class AutoBillReviewData {
  AutoBillReviewData(this.fields);

  factory AutoBillReviewData.fromController(
    VeriFinController controller,
    Map<Object?, Object?> draft,
  ) {
    return AutoBillReviewData({
      ...AutoBillSuggestions.forDraft(controller, draft).toFields(),
      'bookId': controller.activeBook.id,
      'bookName': controller.activeBook.name,
      'baseCurrency': controller.activeBook.baseCurrencyCode,
      'categories': [
        for (final category in controller.categories) category.toJson(),
      ],
      'accounts': [
        for (final account in controller.accounts)
          if (!account.hidden && account.currencyCode == 'CNY')
            {'id': account.id, 'name': account.name},
      ],
      'tags': [for (final tag in controller.tags) tag.toJson()],
      'theme': controller.themePreference.name,
      'numberPadLayout': controller.numberPadLayout.name,
      'themeColors': controller.themeColorPreference.encode(),
      'locale': controller.localePreference.name,
      'categoryIconPreset': controller.categoryIconThemes.preset.name,
    });
  }

  final Map<String, Object?> fields;

  String get bookName => fields['bookName']! as String;
  String get bookId => fields['bookId']! as String;
  bool get canSave => fields['baseCurrency'] == 'CNY';
  NumberPadLayout get numberPadLayout =>
      NumberPadLayout.fromStorage(fields['numberPadLayout'] as String?);
  CategoryIconPreset get categoryIconPreset =>
      CategoryIconPreset.fromStorage(fields['categoryIconPreset']);
  late final categories = _list('categories').map(Category.fromJson).toList();
  late final tags = _list('tags').map(Tag.fromJson).toList();
  late final accounts = {
    for (final account in _list('accounts'))
      account['id']! as String: account['name']! as String,
  };

  Iterable<Map<String, Object?>> _list(String key) =>
      (fields[key]! as List<Object?>).cast<Map<Object?, Object?>>().map(
        Map<String, Object?>.from,
      );
}

/// Only the ledger engine can resolve the book or commit the edits from Android.
class AutoBillOverlayBridge {
  static const _channel = MethodChannel('verifin/auto_bill_overlay');
  static const _alipay = 'com.eg.android.AlipayGphone';
  static const _receiptTimeToleranceMs = 60000;
  static final _remarkWhitespace = RegExp(r'\s+');
  static final _alipayDefaultRemark = RegExp(
    r'^支付宝(?:(?:扫码)?(?:支付|付款|收款|转账)(?:成功|完成)?|账单)?'
    r'(?:[·:：\-—]?自动识别)?[。.!！]?$',
  );
  static Future<void> _lastLedgerWrite = Future<void>.value();

  static String entryIdForDraft(String id) => 'auto-bill-$id';

  static Future<T> runLedgerWrite<T>(Future<T> Function() operation) {
    final next = _lastLedgerWrite.then((_) => operation());
    _lastLedgerWrite = next.then<void>(
      (_) {},
      // The caller sees the error and the next write can proceed.
      onError: (Object error, StackTrace stackTrace) {},
    );
    return next;
  }

  void attach(VeriFinController controller) {
    _channel.setMethodCallHandler((call) async {
      if (!controller.privacyConsentAccepted ||
          !controller.onboardingCompleted ||
          controller.appLockEnabled) {
        return null;
      }
      final args = call.arguments;
      if (args is! Map<Object?, Object?>) return null;
      return switch (call.method) {
        'prepare' => _prepare(controller, args),
        'save' => commit(controller, args),
        'enrichWechatNote' => _enrichWechatNote(controller, args),
        'correctAlipayNote' => _correctAlipayNote(controller, args),
        _ => throw MissingPluginException(call.method),
      };
    });
    unawaited(_announceReady());
    unawaited(refreshNotificationSummary(controller));
  }

  static Future<void> refreshNotificationSummary(
    VeriFinController controller,
  ) async {
    try {
      await _channel.invokeMethod<void>(
        'updateNotificationSummary',
        autoBookkeepingNotificationSummary(controller),
      );
    } on MissingPluginException {
      // Desktop and widget tests have no Android status notification.
    } on PlatformException catch (error) {
      controller.logger?.warning(
        'Could not update auto-bookkeeping status: ${error.code}',
        source: 'auto-capture',
      );
    }
  }

  Future<Map<String, Object?>> _prepare(
    VeriFinController controller,
    Map<Object?, Object?> draft,
  ) async {
    await controller.categoryIconThemes.restore();
    return AutoBillReviewData.fromController(controller, draft).fields;
  }

  Future<void> _announceReady() async {
    try {
      await _channel.invokeMethod<void>('ledgerReady');
    } on MissingPluginException {
      // A Flutter-only host has no Android overlay.
    }
  }

  static String? _matchingDraftRemark(
    Map<Object?, Object?>? supplement, {
    required String note,
    required double amount,
    required int timestamp,
  }) {
    if (supplement == null ||
        supplement['before'] != note ||
        supplement['amount'] != amount ||
        supplement['occurredAt'] != timestamp) {
      return null;
    }
    return supplement['note'] as String?;
  }

  static Future<bool> _enrichWechatNote(
    VeriFinController controller,
    Map<Object?, Object?> supplement,
  ) => runLedgerWrite(() async {
    final id = supplement['id'];
    if (id is! String) return false;
    final entry = controller.entries
        .where((entry) => entry.id == entryIdForDraft(id))
        .firstOrNull;
    if (entry == null || entry.type != EntryType.expense) return false;
    final note = _matchingDraftRemark(
      supplement,
      note: entry.note,
      amount: entry.amount,
      timestamp: entry.occurredAt.millisecondsSinceEpoch,
    );
    if (note == null) return false;
    final result = await controller.saveEntryAggregateDraftResult(
      entry: entry.copyWith(note: note),
      isNew: false,
      refunds: controller.refundsForEntry(entry.id),
      attachments: controller.attachmentsForEntry(entry.id),
    );
    if (!result.isSuccess) {
      controller.logger?.warning(
        'Could not append a WeChat product to the existing remark',
        source: 'auto-capture',
      );
    }
    return result.isSuccess;
  });

  /// False means a fresh payment notification may create its first draft.
  /// True means ignore the detail, or that a corresponding entry already exists.
  static Future<Object> _correctAlipayNote(
    VeriFinController controller,
    Map<Object?, Object?> receipt,
  ) => runLedgerWrite(() async {
    final paidAt = receipt['paidAt'];
    final amount = receipt['amount'];
    final type = switch (receipt['type']) {
      'expense' => EntryType.expense,
      'income' => EntryType.income,
      _ => null,
    };
    final method = receipt['paymentMethod'];
    if (paidAt is! int ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        type == null ||
        method is! String ||
        method.trim().isEmpty) {
      return true;
    }

    final paidAmount = normalizeCurrencyAmount(amount.toDouble(), 'CNY');
    int distance(LedgerEntry entry) =>
        (entry.occurredAt.millisecondsSinceEpoch - paidAt).abs();
    final possibleEntries = controller.entries.where(
      (entry) =>
          entry.type == type &&
          entry.currencyCode == 'CNY' &&
          entry.amount == paidAmount &&
          distance(entry) <= _receiptTimeToleranceMs,
    );
    final fundingAccount = AutoBillSuggestions.matchingPaymentAccount(
      controller.accounts.where((account) => account.currencyCode == 'CNY'),
      {...receipt, 'sourcePackage': _alipay},
    );
    final recentId = receipt['id'];
    final identifiedDraft = recentId is String
        ? possibleEntries
              .where((entry) => entry.id == entryIdForDraft(recentId))
              .firstOrNull
        : null;
    if (identifiedDraft != null &&
        fundingAccount != null &&
        identifiedDraft.accountId.isNotEmpty &&
        identifiedDraft.accountId != fundingAccount.id) {
      return true;
    }
    final LedgerEntry entry;
    if (identifiedDraft != null) {
      entry = identifiedDraft;
    } else {
      if (fundingAccount == null) {
        return possibleEntries.isNotEmpty || recentId != null;
      }
      final matches =
          possibleEntries
              .where((entry) => entry.accountId == fundingAccount.id)
              .toList()
            ..sort((a, b) => distance(a).compareTo(distance(b)));
      if (matches.isEmpty) {
        // An already captured transaction with no account is not evidence for a new draft.
        final confirmed = controller.autoBillAccountHistory(_alipay).toSet();
        return recentId != null ||
            possibleEntries.any(
              (entry) =>
                  entry.accountId.isEmpty && confirmed.contains(entry.id),
            );
      }
      entry = matches.first;
      if (matches.length > 1 && distance(matches[1]) == distance(entry)) {
        return true;
      }
    }

    final merchant = (receipt['merchant'] as String?)?.trim() ?? '';
    final product = (receipt['product'] as String?)?.trim() ?? '';
    final note = identifiedDraft != null
        ? (receipt['note'] as String?)?.trim() ?? ''
        : {merchant, product}.where((value) => value.isNotEmpty).join(' · ');
    if (note.isEmpty || entry.note == note) return true;
    final before = entry.note.trim();
    if (!_isAlipayRemarkPlaceholder(before, merchant) &&
        !(identifiedDraft != null && before == receipt['before'])) {
      return true;
    }

    final result = await controller.saveEntryAggregateDraftResult(
      entry: entry.copyWith(note: note),
      isNew: false,
      refunds: controller.refundsForEntry(entry.id),
      attachments: controller.attachmentsForEntry(entry.id),
    );
    if (!result.isSuccess) {
      controller.logger?.warning(
        'Could not correct the Alipay remark',
        source: 'auto-capture',
      );
      return true;
    }
    return {
      'title': l10nForPreference(
        controller.localePreference,
      ).autoCaptureAlipayRemarkUpdated,
      'note': note,
    };
  });

  static bool _isAlipayRemarkPlaceholder(String note, String merchant) {
    String compact(String text) => text
        .replaceAll(_remarkWhitespace, '')
        .replaceAll('（', '(')
        .replaceAll('）', ')');
    final before = compact(note);
    if (before.isEmpty || _alipayDefaultRemark.hasMatch(before)) return true;
    final name = compact(merchant);
    return name.isNotEmpty &&
        RegExp(
          r'^(?:支付宝(?:支付|付款|收款)?[:：·]|(?:商户(?:名称)?|收款方)[:：])?'
          '${RegExp.escape(name)}'
          r'[·:：。.!！]*$',
        ).hasMatch(before);
  }

  static Future<bool> commit(
    VeriFinController controller,
    Map<Object?, Object?> args,
  ) => runLedgerWrite(() async {
    final id = args['id'];
    final book = controller.activeBook;
    final amount = args['amount'];
    final discount = args['discountAmount'] ?? 0;
    final timestamp = args['occurredAt'];
    final category = args['categoryId'];
    final account = args['accountId'];
    final destination = args['toAccountId'];
    final note = args['note'];
    final source = args['sourcePackage'];
    final tags = args['tagIds'];
    final suggestedTag = args['suggestedTagLabel'];
    final type = switch (args['type']) {
      'expense' => EntryType.expense,
      'income' => EntryType.income,
      'transfer' => EntryType.transfer,
      _ => null,
    };
    if (id is! String ||
        args['bookId'] != book.id ||
        book.baseCurrencyCode != 'CNY' ||
        type == null ||
        amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        discount is! num ||
        !discount.isFinite ||
        discount < 0 ||
        (type != EntryType.expense && discount != 0) ||
        amount + discount >= 1000000 ||
        timestamp is! int ||
        category is! String ||
        account is! String ||
        note is! String ||
        suggestedTag != null && suggestedTag is! String ||
        tags is! List<Object?> ||
        tags.any((tag) => tag is! String)) {
      return false;
    }

    final entryId = entryIdForDraft(id);
    if (controller.containsEntryId(entryId)) return true;
    bool validAccount(String id) => controller.accounts.any(
      (a) => a.id == id && !a.hidden && a.currencyCode == 'CNY',
    );
    final transfer = type == EntryType.transfer;
    if (!controller.categoriesForType(type).any((c) => c.id == category) ||
        account.isNotEmpty && !validAccount(account) ||
        transfer &&
            (account.isEmpty ||
                destination is! String ||
                destination == account ||
                !validAccount(destination))) {
      return false;
    }

    final normalized = normalizeCurrencyAmount(amount, 'CNY');
    if (normalized <= 0) return false;
    var finalNote = note.trim();
    final supplementMethod = switch (source) {
      'com.tencent.mm' when type == EntryType.expense => 'wechatNoteSupplement',
      _alipay when type != EntryType.transfer => 'alipayNoteSupplement',
      _ => null,
    };
    if (supplementMethod != null) {
      try {
        final supplement = await _channel.invokeMapMethod<Object?, Object?>(
          supplementMethod,
          id,
        );
        finalNote =
            _matchingDraftRemark(
              supplement,
              note: finalNote,
              amount: normalized,
              timestamp: timestamp,
            ) ??
            finalNote;
      } on MissingPluginException {
        // Flutter-only hosts and older native bridges can save the original note.
      } on PlatformException catch (error) {
        controller.logger?.warning(
          'Could not read a payment remark supplement: ${error.code}',
          source: 'auto-capture',
        );
      }
      if (controller.activeBook.id != book.id) return false;
    }
    final result = await controller.saveEntryAggregateDraftResult(
      isNew: true,
      autoCaptureSourcePackage: source is String ? source : null,
      suggestedTagLabel: suggestedTag as String?,
      entry: LedgerEntry(
        id: entryId,
        bookId: book.id,
        type: type,
        amount: normalized,
        discountAmount: normalizeCurrencyAmount(discount, 'CNY'),
        currencyCode: 'CNY',
        categoryId: category,
        accountId: account,
        accountAmount: account.isEmpty ? null : normalized,
        toAccountId: transfer ? destination as String : null,
        toAccountAmount: transfer ? normalized : null,
        baseAmount: transfer ? 0 : normalized,
        note: finalNote,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
        tagIds: tags.cast<String>(),
        reimbursable: type == EntryType.expense && args['reimbursable'] == true,
        excludedFromBudget:
            type == EntryType.expense && args['excludedFromBudget'] == true,
        excludedFromStatistics: args['excludedFromStatistics'] == true,
      ),
    );
    if (result.isSuccess) {
      if (controller.onEntryAdded == null) {
        unawaited(BackupCoordinator.maybeBackupAfterEntry(controller));
      }
      if (controller.onWidgetDataChanged == null) {
        unawaited(refreshNotificationSummary(controller));
        unawaited(pushWidgetProjection(controller, force: true));
      }
    }
    return result.isSuccess;
  });
}
