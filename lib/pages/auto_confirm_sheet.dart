import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../app/auto_bill_overlay.dart';
import '../app/auto_bill_rules.dart';
import '../app/category_icon_theme.dart';
import '../app/currency_math.dart';
import '../app/entry_sheets.dart';
import '../app/haptics.dart';
import '../app/ledger_math.dart';
import '../app/models.dart';
import '../app/platform_bridge.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'entry_detail_page.dart';
import 'sheets.dart';

/// The overlay isolate renders the sheet. Ledger access stays in the main engine.
Future<void> runAutoBillOverlay() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('verifin/auto_bill_overlay_view');
  final payload = await channel.invokeMapMethod<String, Object?>('load');
  if (payload == null) return;
  final data = AutoBillReviewData(
    Map<String, Object?>.from(payload['ledger']! as Map),
  );
  final draft = Map<String, Object?>.from(payload['draft']! as Map);
  final navigator = GlobalKey<NavigatorState>();
  Future<void> close() => channel.invokeMethod<void>('close');
  channel.setMethodCallHandler((call) async {
    if (call.method != 'back') return;
    final context = navigator.currentContext;
    if (context != null && MediaQuery.viewInsetsOf(context).bottom > 0) {
      FocusManager.instance.primaryFocus?.unfocus();
      return;
    }
    if (await navigator.currentState?.maybePop() != true) await close();
  });
  final colors = ThemeColorPreference.fromStorage(
    data.fields['themeColors'] as String?,
  );
  runApp(
    MaterialApp(
      navigatorKey: navigator,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: LocalePreference.fromStorage(
        data.fields['locale'] as String?,
      ).locale,
      theme: buildVeriFinTheme(Brightness.light, colorPreference: colors),
      darkTheme: buildVeriFinTheme(Brightness.dark, colorPreference: colors),
      themeMode: ThemePreference.fromStorage(
        data.fields['theme'] as String?,
      ).themeMode,
      builder: (context, child) => CategoryIconThemeScope.snapshot(
        preset: data.categoryIconPreset,
        child: child!,
      ),
      home: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AutoConfirmCaptureSheet(
              data: data,
              draft: draft,
              preview: payload['preview'] == true,
              keyboardHandledByWindow: true,
              onSave: (changes) async {
                try {
                  return await channel.invokeMethod<bool>('save', changes) ??
                      false;
                } on PlatformException {
                  return false;
                }
              },
              onClose: (_) => close(),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> showAutoCapturePreview(BuildContext context) async {
  if (await AppCaptureBridge.openAutoBillOverlayPreview()) return;
  if (!context.mounted) return;
  final preview = await AppCaptureBridge.previewWechatTransfer();
  if (!context.mounted || preview == null) return;
  await showAutoConfirmCaptureSheet(
    context,
    draft: {...preview, 'type': 'expense'},
    preview: true,
  );
}

Future<void> showAutoConfirmCaptureSheet(
  BuildContext context, {
  required Map<String, Object?> draft,
  bool preview = false,
}) async {
  final controller = VeriFinScope.of(context);
  final data = AutoBillReviewData.fromController(controller, draft);
  await showVeriModalSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AutoConfirmCaptureSheet(
      data: data,
      draft: draft,
      preview: preview,
      onSave: (changes) =>
          AutoBillOverlayBridge.commit(controller, {...draft, ...changes}),
      onClose: (_) => Navigator.of(sheetContext).pop(),
    ),
  );
}

/// The existing confirmation panel, shared by the app and Android overlay.
class AutoConfirmCaptureSheet extends StatefulWidget {
  const AutoConfirmCaptureSheet({
    super.key,
    required this.data,
    required this.draft,
    required this.onSave,
    required this.onClose,
    this.preview = false,
    this.keyboardHandledByWindow = false,
  });

  final AutoBillReviewData data;
  final Map<String, Object?> draft;
  final Future<bool> Function(Map<String, Object?>) onSave;
  final ValueChanged<bool> onClose;
  final bool preview;
  final bool keyboardHandledByWindow;

  @override
  State<AutoConfirmCaptureSheet> createState() =>
      _AutoConfirmCaptureSheetState();
}

class _AutoConfirmCaptureSheetState extends State<AutoConfirmCaptureSheet> {
  late EntryType _type;
  late double _grossAmount;
  late double _discountAmount;
  double get _amount =>
      normalizeCurrencyAmount(_grossAmount - _discountAmount, 'CNY');
  late String _categoryId;
  String _accountId = '';
  String? _toAccountId;
  late TextEditingController _noteController;
  final List<String> _tagIds = <String>[];
  Tag? _platformTag;
  late final List<Tag> _availableTags;
  bool _reimbursable = false;
  bool _excludedFromBudget = false;
  bool _saving = false;
  String? _error;
  String? _collapsedCategoryId;

  List<Category> _categoriesForType(EntryType type) =>
      widget.data.categories.where((c) => c.type == type).toList();

  @override
  void initState() {
    super.initState();
    _type = EntryType.fromStorage(widget.draft['type'] as String? ?? 'expense');
    _discountAmount = _type == EntryType.expense
        ? (widget.draft['discountAmount'] as num?)?.toDouble() ?? 0
        : 0;
    _grossAmount = (widget.draft['amount'] as num).toDouble() + _discountAmount;
    _noteController = TextEditingController(
      text: widget.draft['note'] as String? ?? '',
    );
    final categories = _categoriesForType(_type);
    final fields = widget.data.fields;
    final categoryId = fields['suggestedCategoryId'];
    final selected =
        categories.where((c) => c.id == categoryId).firstOrNull ??
        categories.where((c) => c.isUncategorized).firstOrNull;
    _categoryId = selected?.id ?? '';
    _collapsedCategoryId = selected?.parentId ?? selected?.id;
    final accountId = fields['suggestedAccountId'];
    if (accountId is String && widget.data.accounts.containsKey(accountId)) {
      _accountId = accountId;
    }
    _platformTag = AutoBillSuggestions(
      platformTag: fields['suggestedPlatformTag'] as String?,
    ).tagFor(widget.data.bookId, widget.data.tags);
    final platformTag = _platformTag;
    if (platformTag != null) _tagIds.add(platformTag.id);
    _availableTags = [
      ...widget.data.tags,
      if (platformTag != null &&
          platformTag.id == AutoBillSuggestions.draftTagId)
        platformTag,
    ];
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _editAmount() async {
    final next = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(context).amountLabel,
      initialAmount: _amount,
      currencyCode: 'CNY',
      layout: widget.data.numberPadLayout,
    );
    if (mounted && next != null && next > 0) {
      setState(() => _grossAmount = next + _discountAmount);
    }
  }

  Future<void> _editDiscount() async {
    final next = await showEntryDiscountSheet(
      context,
      grossAmount: _grossAmount,
      discountAmount: _discountAmount,
      currencyCode: 'CNY',
      layout: widget.data.numberPadLayout,
    );
    if (mounted && next != null) setState(() => _discountAmount = next);
  }

  Future<void> _pickCategory() async {
    final next = await showCategoryPickerSheet(
      context,
      categories: _categoriesForType(_type),
      selectedId: _categoryId,
    );
    if (mounted && next != null) setState(() => _categoryId = next);
  }

  Future<void> _pickAccount({bool destination = false}) async {
    final l10n = AppLocalizations.of(context);
    final accounts = widget.data.accounts;
    final picked = await showOptionSheet<String>(
      context: context,
      title: destination ? l10n.transferInAccount : l10n.accountLabel,
      values: [
        if (!destination && _type != EntryType.transfer) '',
        ...accounts.keys.where(
          (id) => destination ? id != _accountId : id != _toAccountId,
        ),
      ],
      selected: destination ? _toAccountId ?? '' : _accountId,
      labelOf: (id) => accounts[id] ?? l10n.noAccountLabel,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (destination) {
        _toAccountId = picked;
      } else {
        _accountId = picked;
      }
    });
  }

  Future<void> _pickTags() async {
    final selected = await showVeriModalSheet<List<String>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: TagSelectorSheet(tags: _availableTags, selectedIds: _tagIds),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(
        () => _tagIds
          ..clear()
          ..addAll(selected),
      );
    }
  }

  Future<void> _saveAndClose() async {
    if (_saving) return;
    if (widget.preview) {
      widget.onClose(false);
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (_type == EntryType.transfer &&
        (_accountId.isEmpty || _toAccountId == null)) {
      setState(() => _error = l10n.entrySaveReasonTransferAccount);
      return;
    }
    if (_categoryId.isEmpty) {
      await _pickCategory();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.onSave({
      'bookId': widget.data.bookId,
      'amount': _amount,
      'discountAmount': _discountAmount,
      'type': _type.storageValue,
      'categoryId': _categoryId,
      'accountId': _accountId,
      'toAccountId': _toAccountId,
      'note': _noteController.text,
      'tagIds': _tagIds
          .where((id) => id != AutoBillSuggestions.draftTagId)
          .toList(),
      if (_tagIds.contains(AutoBillSuggestions.draftTagId))
        'suggestedTagLabel': _platformTag?.label,
      'reimbursable': _reimbursable,
      'excludedFromBudget': _excludedFromBudget,
    });
    if (!mounted) return;
    if (saved) {
      VeriHaptics.commit();
      widget.onClose(true);
    } else {
      setState(() {
        _saving = false;
        _error = l10n.saveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tokens = VeriStyleTokens.of(context);
    final bottomInset = widget.keyboardHandledByWindow
        ? 0.0
        : MediaQuery.viewInsetsOf(context).bottom;
    final allCategories = _categoriesForType(_type);
    final topCategories = allCategories
        .where((c) => c.parentId == null)
        .toList();
    final selectedCat = allCategories
        .where((c) => c.id == _categoryId)
        .firstOrNull;
    final selectedTopId = selectedCat?.parentId ?? selectedCat?.id ?? '';
    final accountName = widget.data.accounts[_accountId] ?? l10n.noAccountLabel;
    final amountColor = _type == EntryType.income
        ? veriSemantic(context, veriIncome)
        : _type == EntryType.transfer
        ? veriSemantic(context, veriBlue)
        : veriSemantic(context, veriExpense);
    final amountText = _type == EntryType.income
        ? formatIncomeAmount(_amount)
        : _type == EntryType.transfer
        ? formatAmount(_amount)
        : formatExpenseAmount(_amount);

    final sheet = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: tokens.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tokens.borderColor),
          boxShadow: tokens.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.draft['sourceLabel'] as String? ??
                                l10n.autoCapturePreviewTitle,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.preview
                                ? l10n.autoCapturePreviewBody
                                : l10n.autoCaptureManualConfirm,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.56,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.surfaceAltColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.data.bookName,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        for (final candidate in const <EntryType>[
                          EntryType.expense,
                          EntryType.income,
                          EntryType.transfer,
                        ]) ...<Widget>[
                          ChoiceChip(
                            label: Text(candidate.label(l10n)),
                            selected: _type == candidate,
                            onSelected: (_) {
                              if (_type == candidate) return;
                              final list = _categoriesForType(candidate);
                              setState(() {
                                _type = candidate;
                                if (candidate != EntryType.expense) {
                                  _discountAmount = 0;
                                }
                                _categoryId =
                                    list
                                        .where((c) => c.isUncategorized)
                                        .firstOrNull
                                        ?.id ??
                                    '';
                                _collapsedCategoryId = null;
                              });
                            },
                          ),
                          const SizedBox(width: 6),
                        ],
                        const Spacer(),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _editAmount,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              amountText,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: amountColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    EntryCategoryGrid(
                      categories: topCategories,
                      allCategories: allCategories,
                      selectedId: _categoryId,
                      selectedTopId: selectedTopId,
                      collapsedId: _collapsedCategoryId,
                      iconGrid: true,
                      accent: amountColor,
                      allLabel: l10n.allLabel,
                      onToggleBranch: (id, expanded) {
                        setState(() {
                          _collapsedCategoryId = expanded ? id : null;
                        });
                      },
                      onSelected: (id) {
                        setState(() {
                          _categoryId = id;
                          _collapsedCategoryId = null;
                        });
                      },
                      onOpenAll: _pickCategory,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              decoration: BoxDecoration(
                color: tokens.surfaceAltColor,
                borderRadius: BorderRadius.circular(veriRadiusMd),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ChipTheme(
                    data: theme.chipTheme.copyWith(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                      avatarBoxConstraints: const BoxConstraints.tightFor(
                        width: 16,
                        height: 16,
                      ),
                    ),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      children: <Widget>[
                        if (_type == EntryType.transfer)
                          ActionChip(
                            label: Text(
                              widget.data.accounts[_toAccountId] ??
                                  l10n.transferInAccount,
                            ),
                            onPressed: () => _pickAccount(destination: true),
                          ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 14,
                          ),
                          label: Text(accountName),
                          onPressed: () => _pickAccount(),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.sell_outlined, size: 14),
                          label: Text(
                            _tagIds.isEmpty
                                ? l10n.tagLabel
                                : _tagIds.length == 1 &&
                                      _tagIds.contains(_platformTag?.id)
                                ? _platformTag!.label
                                : l10n.entryTagCount(_tagIds.length),
                          ),
                          onPressed: _pickTags,
                        ),
                        if (_type == EntryType.expense) ...<Widget>[
                          ActionChip(
                            avatar: const Icon(
                              Icons.local_offer_outlined,
                              size: 14,
                            ),
                            label: Text(
                              _discountAmount > 0
                                  ? l10n.entryDiscountValue(
                                      formatAmount(_discountAmount),
                                    )
                                  : l10n.entryDiscountLabel,
                            ),
                            onPressed: _editDiscount,
                          ),
                          FilterChip(
                            label: Text(l10n.badgeReimbursable),
                            selected: _reimbursable,
                            onSelected: (v) {
                              setState(() => _reimbursable = v);
                            },
                          ),
                          FilterChip(
                            label: Text(l10n.excludedFromBudget),
                            selected: _excludedFromBudget,
                            onSelected: (v) {
                              setState(() => _excludedFromBudget = v);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Text(
                        '${l10n.commonNote}: ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _noteController,
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
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (_error != null) Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => widget.onClose(false),
                    child: Text(l10n.commonCancel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _saveAndClose,
                    child: Text(
                      widget.preview ? l10n.closeLabel : l10n.commonSave,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: sheet,
    );
  }
}
