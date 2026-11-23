import 'dart:async';

import 'package:flutter/services.dart';

import 'currency_math.dart';
import 'backup/backup_coordinator.dart';
import 'category_icon_presets.dart';
import 'models.dart';
import 'veri_fin_controller.dart';
import 'widgets/widget_service.dart';

class AutoBillReviewData {
  AutoBillReviewData(this.fields);

  factory AutoBillReviewData.fromController(VeriFinController controller) {
    return AutoBillReviewData({
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
      'themeColors': controller.themeColorPreference.encode(),
      'locale': controller.localePreference.name,
      'categoryIconPreset': controller.categoryIconThemes.preset.name,
    });
  }

  final Map<String, Object?> fields;

  String get bookName => fields['bookName']! as String;
  String get bookId => fields['bookId']! as String;
  bool get canSave => fields['baseCurrency'] == 'CNY';
  CategoryIconPreset get categoryIconPreset =>
      CategoryIconPreset.values.asNameMap()[fields['categoryIconPreset']] ??
      CategoryIconPreset.builtin;
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
  static Future<void> _lastLedgerWrite = Future<void>.value();

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
        'prepare' => _prepare(controller),
        'save' => commit(controller, args),
        _ => throw MissingPluginException(call.method),
      };
    });
    unawaited(_announceReady());
  }

  Future<Map<String, Object?>> _prepare(VeriFinController controller) async {
    await controller.categoryIconThemes.restore();
    return AutoBillReviewData.fromController(controller).fields;
  }

  Future<void> _announceReady() async {
    try {
      await _channel.invokeMethod<void>('ledgerReady');
    } on MissingPluginException {
      // A Flutter-only host has no Android overlay.
    }
  }

  static Future<bool> commit(
    VeriFinController controller,
    Map<Object?, Object?> args,
  ) => runLedgerWrite(() async {
    final id = args['id'];
    final book = controller.activeBook;
    final amount = args['amount'];
    final timestamp = args['occurredAt'];
    final category = args['categoryId'];
    final account = args['accountId'];
    final destination = args['toAccountId'];
    final note = args['note'];
    final tags = args['tagIds'];
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
        amount >= 1000000 ||
        timestamp is! int ||
        category is! String ||
        account is! String ||
        note is! String ||
        tags is! List<Object?> ||
        tags.any((tag) => tag is! String)) {
      return false;
    }

    final entryId = 'auto-bill-$id';
    if (controller.entries.any((entry) => entry.id == entryId)) return true;
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
    final result = await controller.saveEntryAggregateDraftResult(
      isNew: true,
      entry: LedgerEntry(
        id: entryId,
        bookId: book.id,
        type: type,
        amount: normalized,
        currencyCode: 'CNY',
        categoryId: category,
        accountId: account,
        accountAmount: account.isEmpty ? null : normalized,
        toAccountId: transfer ? destination as String : null,
        toAccountAmount: transfer ? normalized : null,
        baseAmount: transfer ? 0 : normalized,
        note: note.trim(),
        occurredAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
        tagIds: tags.cast<String>(),
        reimbursable: type == EntryType.expense && args['reimbursable'] == true,
        excludedFromBudget:
            type == EntryType.expense && args['excludedFromBudget'] == true,
      ),
    );
    if (result.isSuccess) {
      if (controller.onEntryAdded == null) {
        unawaited(BackupCoordinator.maybeBackupAfterEntry(controller));
      }
      if (controller.onWidgetDataChanged == null) {
        unawaited(pushWidgetProjection(controller, force: true));
      }
    }
    return result.isSuccess;
  });
}
