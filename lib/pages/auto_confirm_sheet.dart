import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_theme.dart';
import '../app/auto_bill_overlay.dart';
import '../app/auto_bill_rules.dart';
import '../app/category_icon_theme.dart';
import '../app/category_tree.dart';
import '../app/common_widgets.dart';
import '../app/currency_math.dart';
import '../app/entry_sheets.dart';
import '../app/haptics.dart';
import '../app/ledger_math.dart';
import '../app/models.dart';
import '../app/platform_bridge.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'sheets.dart';

/// The overlay isolate renders the prepared suggestions without opening SQLite
/// or loading classification rules again.
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
  EntryStatisticsScope _statisticsScope = EntryStatisticsScope.normal;
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
    _collapsedCategoryId = selected?.id;
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
    if (mounted && next != null) {
      setState(() {
        _categoryId = next;
        _collapsedCategoryId = null;
      });
    }
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
      _error = null;
    });
  }

  Future<void> _pickTags() async {
    final selected = await showTagSelectorSheet(
      context,
      tags: _availableTags,
      selectedIds: _tagIds,
    );
    if (selected != null && mounted) {
      setState(
        () => _tagIds
          ..clear()
          ..addAll(selected),
      );
    }
  }

  void _changeType(EntryType type) {
    if (_type == type) return;
    final categories = _categoriesForType(type);
    setState(() {
      _type = type;
      if (type != EntryType.expense) _discountAmount = 0;
      _categoryId =
          categories.where((c) => c.isUncategorized).firstOrNull?.id ?? '';
      _collapsedCategoryId = null;
      _error = null;
    });
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
      'excludedFromBudget':
          _statisticsScope.forType(_type) == EntryStatisticsScope.excludeBudget,
      'excludedFromStatistics':
          _statisticsScope.forType(_type) ==
          EntryStatisticsScope.excludeStatistics,
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
    final frequentNotes = widget.data.notesFor(_categoryId, _type);
    final allCategories = _categoriesForType(_type);
    final topCategories = allCategories
        .where((c) => c.parentId == null)
        .toList();
    final selectedCat = allCategories
        .where((c) => c.id == _categoryId)
        .firstOrNull;
    final selectedTopId = selectedCat == null
        ? ''
        : rootIdOf(allCategories, selectedCat.id);
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        child: VeriCard(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
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
                        spacing: 8,
                        children: <Widget>[
                          Flexible(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: ShapeDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: const StadiumBorder(),
                              ),
                              child: Text(
                                widget.draft['sourceLabel'] as String? ??
                                    l10n.autoCapturePreviewTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
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
                          Flexible(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: ShapeDecoration(
                                  color: tokens.surfaceAltColor,
                                  shape: const StadiumBorder(),
                                ),
                                child: Text(
                                  widget.data.bookName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        spacing: 8,
                        children: <Widget>[
                          Expanded(
                            flex: 3,
                            child: VeriSegmentedControl<EntryType>(
                              values: const [
                                EntryType.expense,
                                EntryType.income,
                                EntryType.transfer,
                              ],
                              selected: _type,
                              labelOf: (type) => type.label(l10n),
                              accentOf: (_) => amountColor,
                              onChanged: _changeType,
                              compact: true,
                            ),
                          ),
                          Flexible(
                            flex: 2,
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(
                                  tokens.innerRadius,
                                ),
                                onTap: _editAmount,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      amountText,
                                      style: theme.textTheme.headlineSmall
                                          ?.copyWith(
                                            color: amountColor,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
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
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: tokens.surfaceAltColor,
                  borderRadius: BorderRadius.circular(tokens.innerRadius),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if (_type == EntryType.transfer)
                          EntryMetadataPill(
                            compact: true,
                            icon: Icons.move_to_inbox_outlined,
                            label: Text(
                              widget.data.accounts[_toAccountId] ??
                                  l10n.transferInAccount,
                            ),
                            onTap: () => _pickAccount(destination: true),
                          ),
                        EntryMetadataPill(
                          compact: true,
                          icon: Icons.account_balance_wallet_outlined,
                          label: Text(accountName),
                          onTap: _pickAccount,
                        ),
                        EntryMetadataPill(
                          compact: true,
                          icon: Icons.sell_outlined,
                          selected: _tagIds.isNotEmpty,
                          label: Text(
                            _tagIds.isEmpty
                                ? l10n.tagLabel
                                : _tagIds.length == 1 &&
                                      _tagIds.contains(_platformTag?.id)
                                ? _platformTag!.label
                                : l10n.entryTagCount(_tagIds.length),
                          ),
                          onTap: _pickTags,
                        ),
                        if (_type == EntryType.expense) ...[
                          EntryMetadataPill(
                            compact: true,
                            icon: Icons.percent_rounded,
                            selected: _discountAmount > 0,
                            label: Text(
                              _discountAmount > 0
                                  ? l10n.entryDiscountValue(
                                      formatAmount(_discountAmount),
                                    )
                                  : l10n.entryDiscountLabel,
                            ),
                            onTap: _editDiscount,
                          ),
                          EntryMetadataPill(
                            compact: true,
                            icon: Icons.receipt_long_outlined,
                            label: Text(l10n.badgeReimbursable),
                            selected: _reimbursable,
                            toggle: true,
                            onTap: () =>
                                setState(() => _reimbursable = !_reimbursable),
                          ),
                        ],
                        if (EntryStatisticsScope.supports(_type))
                          EntryStatisticsToggles(
                            type: _type,
                            scope: _statisticsScope,
                            onChanged: (scope) =>
                                setState(() => _statisticsScope = scope),
                          ),
                      ],
                    ),
                    Divider(height: 16, color: tokens.borderColor),
                    if (frequentNotes.isNotEmpty) ...[
                      TextFieldTapRegion(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _noteController,
                          builder: (context, editing, _) => EntryMetadataStrip(
                            children: [
                              for (final note in frequentNotes)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 152,
                                  ),
                                  child: EntryMetadataPill(
                                    compact: true,
                                    minHeight: 30,
                                    label: Text(note),
                                    selected: editing.text == note,
                                    onTap: () {
                                      _noteController.value = TextEditingValue(
                                        text: note,
                                        selection: TextSelection.collapsed(
                                          offset: note.length,
                                        ),
                                      );
                                      VeriHaptics.tick();
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: <Widget>[
                        Text(
                          l10n.commonNote,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
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
              if (_error case final error?) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(tokens.innerRadius),
                    ),
                    child: Row(
                      spacing: 8,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 16,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        Expanded(
                          child: Text(
                            error,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: sheet,
    );
  }
}
