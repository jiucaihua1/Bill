import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app/common_widgets.dart';
import '../app/currency_catalog.dart';
import '../app/currency_math.dart';
import '../app/entry_currency_draft.dart';
import '../app/ledger_math.dart';
import '../app/model_lookup.dart';
import '../app/models.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'sheets.dart';

class RefundEditResult {
  const RefundEditResult.saved(this.refund) : deleted = false;

  const RefundEditResult.deleted() : refund = null, deleted = true;

  final LedgerEntry? refund;
  final bool deleted;
}

/// Controlled refund editor section used by the transaction aggregate draft.
class RefundSection extends StatelessWidget {
  const RefundSection({
    super.key,
    required this.expense,
    required this.refunds,
    required this.onChanged,
  });

  final LedgerEntry expense;
  final List<LedgerEntry> refunds;
  final ValueChanged<List<LedgerEntry>> onChanged;

  double get _remaining => remainingRefundableAmount(expense, refunds);

  double get _settledBaseTotal => refunds
      .where((refund) => refund.isSettledRefund)
      .fold<double>(0, (sum, refund) => sum + refund.baseAmount);

  List<LedgerEntry> get _sortedRefunds =>
      List<LedgerEntry>.of(refunds)..sort((a, b) {
        final aDate = a.settledAt ?? a.occurredAt;
        final bDate = b.settledAt ?? b.occurredAt;
        return bDate.compareTo(aDate);
      });

  Future<void> _edit(BuildContext context, LedgerEntry? existing) async {
    final result = await showRefundSheet(
      context: context,
      expense: expense,
      refunds: refunds,
      existing: existing,
    );
    if (result == null || !context.mounted) {
      return;
    }
    final next = List<LedgerEntry>.of(refunds);
    if (result.deleted) {
      next.removeWhere((refund) => refund.id == existing?.id);
    } else {
      final refund = result.refund!;
      final index = next.indexWhere((item) => item.id == refund.id);
      if (index == -1) {
        next.add(refund);
      } else {
        next[index] = refund;
      }
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    if (expense.type != EntryType.expense) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final controller = VeriFinScope.of(context);
    final netBaseAmount = (expense.baseAmount - _settledBaseTotal)
        .clamp(0.0, expense.baseAmount)
        .toDouble();

    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.refundRecordsTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              if (refunds.isNotEmpty)
                Text(
                  l10n.refundNetLabel(
                    formatUserMoney(
                      netBaseAmount,
                      controller.activeBook.baseCurrencyCode,
                    ),
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (refunds.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                l10n.refundEmpty,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            )
          else
            for (final refund in _sortedRefunds)
              _RefundRow(
                refund: refund,
                accounts: controller.accounts,
                onTap: () => _edit(context, refund),
              ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _remaining <= 0 ? null : () => _edit(context, null),
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.refundAdd),
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundRow extends StatelessWidget {
  const _RefundRow({
    required this.refund,
    required this.accounts,
    required this.onTap,
  });

  final LedgerEntry refund;
  final List<Account> accounts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settled = refund.settledAt != null;
    final date = refund.settledAt ?? refund.occurredAt;
    final accountName = accountDisplayName(
      accounts,
      refund.accountId,
      l10n.commonNoneShort,
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(veriRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(
              settled ? Icons.check_circle : Icons.schedule,
              size: 20,
              color: settled
                  ? veriSemantic(context, veriIncome)
                  : veriSemantic(context, veriBlue),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '+${formatUserMoney(refund.amount, refund.currencyCode)} · $accountName',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${settled ? l10n.refundStatusSettled : l10n.refundStatusPending}'
                    ' · ${l10n.dateMonthDay(date)}'
                    '${refund.note.isEmpty ? '' : ' · ${refund.note}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

Future<RefundEditResult?> showRefundSheet({
  required BuildContext context,
  required LedgerEntry expense,
  required List<LedgerEntry> refunds,
  LedgerEntry? existing,
}) {
  return showVeriModalSheet<RefundEditResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) =>
        _RefundSheet(expense: expense, refunds: refunds, existing: existing),
  );
}

typedef _RefundSnapshot = ({
  double amount,
  String accountId,
  double? accountAmount,
  double baseAmount,
  DateTime? settledAt,
  DateTime initiatedAt,
  String note,
});

class _RefundSheet extends StatefulWidget {
  const _RefundSheet({
    required this.expense,
    required this.refunds,
    this.existing,
  });

  final LedgerEntry expense;
  final List<LedgerEntry> refunds;
  final LedgerEntry? existing;

  @override
  State<_RefundSheet> createState() => _RefundSheetState();
}

class _RefundSheetState extends State<_RefundSheet> {
  final EditorExitController _exitController = EditorExitController();
  late final String _refundId;
  late double _amount;
  late String _accountId;
  double? _accountAmount;
  late double _baseAmount;
  bool _accountAmountTouched = false;
  bool _baseAmountTouched = false;
  ConversionSource _conversionSource = ConversionSource.identity;
  DateTime? _settledAt;
  late DateTime _initiatedAt;
  late String _note;
  late _RefundSnapshot _initialSnapshot;
  RefundEditResult? _result;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _refundId =
        widget.existing?.id ??
        'entry_refund_${DateTime.now().microsecondsSinceEpoch}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    final existing = widget.existing;
    if (existing != null) {
      _amount = existing.amount;
      _accountId = existing.accountId;
      _accountAmount = existing.accountAmount;
      _baseAmount = existing.baseAmount;
      _conversionSource = existing.conversionSource;
      _settledAt = existing.settledAt;
      _initiatedAt = existing.occurredAt;
      _note = existing.note;
    } else {
      _amount = _maxRefund;
      _accountId = widget.expense.accountId;
      _baseAmount = 0;
      _settledAt = DateTime.now();
      _initiatedAt = _settledAt!;
      _note = '';
      _resolveAmounts(forceAccount: true, forceBase: true);
    }
    _initialSnapshot = _snapshot;
    _noteController.text = _note;
  }

  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  double get _maxRefund => remainingRefundableAmount(
    widget.expense,
    widget.refunds,
    excludeRefundId: widget.existing?.id,
  );

  Account? get _selectedAccount {
    if (_accountId.isEmpty) return null;
    return VeriFinScope.of(
      context,
    ).accounts.where((account) => account.id == _accountId).firstOrNull;
  }

  void _resolveAmounts({bool forceAccount = false, bool forceBase = false}) {
    final controller = VeriFinScope.of(context);
    final expense = widget.expense;
    final baseCode = controller.activeBook.baseCurrencyCode;
    if ((forceBase || !_baseAmountTouched) && expense.amount > 0) {
      _baseAmount = normalizeCurrencyAmount(
        expense.baseAmount * _amount / expense.amount,
        baseCode,
      );
    }
    final account = _selectedAccount;
    if (account == null) {
      _accountAmount = null;
    } else if (forceAccount || !_accountAmountTouched) {
      if (account.id == expense.accountId && expense.accountAmount != null) {
        _accountAmount = normalizeCurrencyAmount(
          expense.accountAmount! * _amount / expense.amount,
          account.currencyCode,
        );
      } else if (account.currencyCode == baseCode) {
        _accountAmount = _baseAmount;
      } else {
        final converted = controller.convertAmount(
          amount: _amount,
          sourceCurrencyCode: expense.currencyCode,
          targetCurrencyCode: account.currencyCode,
          date: _initiatedAt,
        );
        _accountAmount = converted is ConvertedCurrencyAmount
            ? converted.amount
            : null;
      }
    }
    _conversionSource = _accountAmountTouched || _baseAmountTouched
        ? ConversionSource.manual
        : expense.currencyCode == baseCode &&
              (account == null || account.currencyCode == baseCode)
        ? ConversionSource.identity
        : ConversionSource.rateTable;
  }

  _RefundSnapshot get _snapshot => (
    amount: _amount,
    accountId: _accountId,
    accountAmount: _accountAmount,
    baseAmount: _baseAmount,
    settledAt: _settledAt,
    initiatedAt: _initiatedAt,
    note: _note.trim(),
  );

  bool get _isDirty =>
      _initialized &&
      (widget.existing == null || _snapshot != _initialSnapshot);

  Future<void> _editAmount() async {
    final value = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(context).refundAmountShort,
      initialAmount: _amount > 0 ? _amount : null,
      maxAmount: _maxRefund,
      maxFractionDigits: CurrencyCatalog.require(
        widget.expense.currencyCode,
      ).minorUnit,
      currencyCode: widget.expense.currencyCode,
    );
    if (value == null || value <= 0 || !mounted) {
      return;
    }
    setState(() {
      final previousAmount = _amount;
      _amount = normalizeCurrencyAmount(value, widget.expense.currencyCode);
      if (_conversionSource == ConversionSource.manual) {
        final accountCode = _selectedAccount?.currencyCode;
        if (accountCode != null) {
          _accountAmount = scaleDependentCurrencyAmount(
            dependentAmount: _accountAmount,
            previousOriginalAmount: previousAmount,
            nextOriginalAmount: _amount,
            targetCurrencyCode: accountCode,
          );
          _accountAmountTouched = true;
        }
        _baseAmount =
            scaleDependentCurrencyAmount(
              dependentAmount: _baseAmount,
              previousOriginalAmount: previousAmount,
              nextOriginalAmount: _amount,
              targetCurrencyCode: VeriFinScope.of(
                context,
              ).activeBook.baseCurrencyCode,
            ) ??
            0;
        _baseAmountTouched = true;
      } else {
        _resolveAmounts();
      }
    });
  }

  Future<void> _pickAccount() async {
    final l10n = AppLocalizations.of(context);
    final controller = VeriFinScope.of(context);
    final selected = await showAccountPickerSheet(
      context: context,
      title: l10n.refundToAccountLabel,
      accounts: controller.accounts
          .where((account) => !account.hidden)
          .toList(),
      selectedId: _accountId,
      balanceOf: controller.accountBalance,
      noneLabel: l10n.commonNoneShort,
    );
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _accountId = selected.id;
      _accountAmountTouched = false;
      _resolveAmounts(forceAccount: true);
    });
  }

  Future<void> _editAccountAmount(String currencyCode) async {
    final value = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(context).entryAmountInputTitle(
        AppLocalizations.of(context).refundAccountAmountLabel,
        currencyCode,
      ),
      initialAmount: _accountAmount,
      maxFractionDigits: CurrencyCatalog.require(currencyCode).minorUnit,
    );
    if (value == null || value <= 0 || !mounted) return;
    setState(() {
      _accountAmount = normalizeCurrencyAmount(value, currencyCode);
      _accountAmountTouched = true;
      if (currencyCode ==
          VeriFinScope.of(context).activeBook.baseCurrencyCode) {
        _baseAmount = _accountAmount!;
        _baseAmountTouched = true;
      }
      _conversionSource = ConversionSource.manual;
    });
  }

  Future<void> _editBaseAmount(String baseCode) async {
    final value = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(context).entryAmountInputTitle(
        AppLocalizations.of(context).refundBaseAmountLabel,
        baseCode,
      ),
      initialAmount: _baseAmount > 0 ? _baseAmount : null,
      maxFractionDigits: CurrencyCatalog.require(baseCode).minorUnit,
    );
    if (value == null || value <= 0 || !mounted) return;
    setState(() {
      _baseAmount = normalizeCurrencyAmount(value, baseCode);
      _baseAmountTouched = true;
      if (_selectedAccount?.currencyCode == baseCode) {
        _accountAmount = _baseAmount;
        _accountAmountTouched = true;
      }
      _conversionSource = ConversionSource.manual;
    });
  }

  LedgerEntry _buildRefund() => LedgerEntry(
    id: _refundId,
    bookId: widget.expense.bookId,
    type: EntryType.refund,
    amount: normalizeCurrencyAmount(
      _amount.clamp(0.0, _maxRefund).toDouble(),
      widget.expense.currencyCode,
    ),
    currencyCode: widget.expense.currencyCode,
    accountAmount: _accountId.isEmpty ? null : _accountAmount,
    baseAmount: _baseAmount,
    conversionSource: _conversionSource,
    categoryId: widget.expense.categoryId,
    accountId: _accountId,
    note: _note.trim(),
    occurredAt: _initiatedAt,
    refundOf: widget.expense.id,
    settledAt: _settledAt,
  );

  Future<bool> _save() async {
    final amount = normalizeCurrencyAmount(
      _amount,
      widget.expense.currencyCode,
    );
    if (_settledAt == null ||
        amount <= 0 ||
        amount > _maxRefund ||
        _maxRefund <= 0 ||
        _baseAmount <= 0 ||
        (_accountId.isNotEmpty && (_accountAmount ?? 0) <= 0)) {
      return false;
    }
    _result = RefundEditResult.saved(_buildRefund());
    return true;
  }

  Future<void> _saveAndExit() async {
    if (await _save() && mounted) {
      _exitController.exit(result: () => _result);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.refundRecordsTitle,
      message: l10n.refundDeleteConfirm,
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    _result = const RefundEditResult.deleted();
    _exitController.exit(result: () => _result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = VeriFinScope.of(context);
    final theme = Theme.of(context);
    final accountName = accountDisplayName(
      controller.accounts,
      _accountId,
      l10n.commonNoneShort,
    );
    final account = _selectedAccount;
    final baseCode = controller.activeBook.baseCurrencyCode;
    final settledAt = _settledAt;
    final canSave =
        settledAt != null &&
        _amount > 0 &&
        _baseAmount > 0 &&
        (_accountId.isEmpty || (_accountAmount ?? 0) > 0) &&
        (widget.existing == null || _isDirty);

    return UnsavedChangesGuard(
      isDirty: _isDirty,
      onSave: _save,
      popResult: () => _result,
      exitController: _exitController,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          // 内容超过可用高度时可滚动：多币种字段与两个日期行加起来在小屏上会超出一屏。
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? l10n.refundAdd
                            : l10n.refundEditTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.existing != null)
                      IconButton(
                        onPressed: _delete,
                        icon: const Icon(Icons.delete_outline),
                        color: veriSemantic(context, veriExpense),
                        tooltip: l10n.commonDelete,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _editAmount,
                  borderRadius: BorderRadius.circular(veriRadiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '+${formatUserMoney(_amount, widget.expense.currencyCode)}',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: veriSemantic(context, veriIncome),
                          ),
                        ),
                        Text(
                          l10n.refundRemainingLabel(
                            formatUserMoney(
                              _maxRefund,
                              widget.expense.currencyCode,
                            ),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (controller.multiCurrencyEnabled) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    l10n.refundCurrencyLockedHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.55,
                      ),
                    ),
                  ),
                ],
                DetailInfoRow(
                  label: l10n.refundToAccountLabel,
                  value: accountName,
                  onTap: _pickAccount,
                ),
                if (account != null &&
                    (controller.multiCurrencyEnabled ||
                        account.currencyCode != widget.expense.currencyCode))
                  CurrencyAmountField(
                    key: const Key('refund_account_amount'),
                    label: l10n.refundAccountAmountLabel,
                    currencyCode: account.currencyCode,
                    amount: _accountAmount,
                    missingText: l10n.exchangeRateNotSet,
                    // 退款原币锁死为原支出币种，单币种账本下这两端不可能出现第二个币种。
                    forceUnit: false,
                    onTap: () => _editAccountAmount(account.currencyCode),
                  ),
                if (controller.multiCurrencyEnabled ||
                    baseCode != widget.expense.currencyCode)
                  CurrencyAmountField(
                    key: const Key('refund_base_amount'),
                    label: l10n.refundBaseAmountLabel,
                    currencyCode: baseCode,
                    amount: _baseAmount > 0 ? _baseAmount : null,
                    missingText: l10n.exchangeRateNotSet,
                    forceUnit: false,
                    onTap: () => _editBaseAmount(baseCode),
                  ),
                DetailInfoRow(
                  label: l10n.refundDateLabel,
                  value: settledAt == null
                      ? l10n.refundMarkSettled
                      : '${l10n.dateMonthDay(settledAt)}  ${relativeDay(l10n, settledAt)}',
                  onTap: () async {
                    final today = DateUtils.dateOnly(DateTime.now());
                    final date = settledAt ?? today;
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2000),
                      lastDate: date.isAfter(today) ? date : today,
                    );
                    if (picked != null && mounted) {
                      setState(() {
                        _settledAt = picked;
                        // 旧待到账退款已有独立的发起日期。
                        if (widget.existing?.isPendingRefund != true) {
                          _initiatedAt = picked;
                        }
                      });
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 78,
                        child: Text(
                          l10n.commonNote,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.62,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _noteController,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            hintText: l10n.noteHint,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) => setState(() => _note = value),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: canSave ? _saveAndExit : null,
                    child: Text(l10n.commonSave),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
