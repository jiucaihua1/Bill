import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../app/ai/ai_entry_parser.dart';
import '../app/app_theme.dart';
import '../app/attachment_picker.dart';
import '../app/auto_bill_rules.dart';
import '../app/category_suggest.dart';
import '../app/category_tree.dart';
import '../app/common_widgets.dart';
import '../app/currency_catalog.dart';
import '../app/currency_math.dart';
import '../app/entry_currency_draft.dart';
import '../app/entry_save_feedback.dart';
import '../app/entry_sheets.dart';
import '../app/feedback.dart';
import '../app/haptics.dart';
import '../app/model_lookup.dart';
import '../app/ledger_math.dart';
import '../app/models.dart';
import '../app/veri_fin_controller.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'assets_pages.dart';
import 'attachments_editor.dart';
import 'category_management_page.dart';
import 'sheets.dart';

const _diagnoseNoteKeyboard = bool.fromEnvironment('IME_DIAGNOSTICS');

class EntryDetailPage extends StatefulWidget {
  const EntryDetailPage({
    super.key,
    required this.initialAmount,
    this.initialAccountId,
    this.initialDraft,
    this.initialDiscountAmount = 0,
    this.draftReviewHint,
    this.suggestedPlatformTag,
    this.autoCaptureSourcePackage,
  }) : draftEntry = null,
       draftExtraAccounts = null,
       draftExtraCategories = null,
       draftExtraTags = null,
       inlineNumberPad = false;

  const EntryDetailPage.manual({super.key, this.initialAccountId})
    : initialAmount = 0,
      initialDiscountAmount = 0,
      initialDraft = null,
      draftReviewHint = null,
      suggestedPlatformTag = null,
      autoCaptureSourcePackage = null,
      draftEntry = null,
      draftExtraAccounts = null,
      draftExtraCategories = null,
      draftExtraTags = null,
      inlineNumberPad = true;

  /// 草稿编辑模式：编辑一条已有交易（如导入预览里的条目），保存时**不落库**，
  /// 而是通过 `Navigator.pop` 返回修改后的 [LedgerEntry] 供上层处理。
  /// [extraAccounts]/[extraCategories]/[extraTags] 是尚未落库的临时账户/分类/标签
  /// （如导入将新建的），合并进选择器与展示，保证草稿引用到它们时能正确解析、不被回退。
  EntryDetailPage.draft({
    super.key,
    required LedgerEntry entry,
    List<Account> extraAccounts = const <Account>[],
    List<Category> extraCategories = const <Category>[],
    List<Tag> extraTags = const <Tag>[],
  }) : draftEntry = entry,
       draftExtraAccounts = extraAccounts,
       draftExtraCategories = extraCategories,
       draftExtraTags = extraTags,
       initialAmount = entry.amount,
       initialDiscountAmount = entry.discountAmount,
       initialAccountId = null,
       initialDraft = null,
       draftReviewHint = null,
       suggestedPlatformTag = null,
       autoCaptureSourcePackage = null,
       inlineNumberPad = false;

  final double initialAmount;
  final double initialDiscountAmount;
  final String? initialAccountId;
  final bool inlineNumberPad;

  /// 识别出的草稿：非空时预填表单并显示复核提示，供用户确认后落账。
  final AiEntryDraft? initialDraft;
  final String? draftReviewHint;
  final Tag? suggestedPlatformTag;
  final String? autoCaptureSourcePackage;

  /// 草稿编辑模式下要编辑的交易；非空即进入「返回草稿不落库」模式。
  final LedgerEntry? draftEntry;

  /// 草稿模式下额外可选的临时账户 / 分类 / 标签（未落库，如导入待新建项）。
  final List<Account>? draftExtraAccounts;
  final List<Category>? draftExtraCategories;
  final List<Tag>? draftExtraTags;

  @override
  State<EntryDetailPage> createState() => _EntryDetailSessionState();
}

class _EntryDetailSessionState extends State<EntryDetailPage> {
  int _draftNumber = 0;

  @override
  Widget build(BuildContext context) => _EntryDetailForm(
    key: ValueKey(_draftNumber),
    config: widget,
    startNext: () => setState(() => _draftNumber++),
  );
}

class _EntryDetailForm extends StatefulWidget {
  const _EntryDetailForm({
    super.key,
    required this.config,
    required this.startNext,
  });

  final EntryDetailPage config;
  final VoidCallback startNext;

  @override
  State<_EntryDetailForm> createState() => _EntryDetailPageState();
}

enum _EntryConversionTarget { account, toAccount, base }

enum _ManualEntryTab {
  expense(EntryType.expense),
  income(EntryType.income),
  transfer(EntryType.transfer),
  debt(EntryType.transfer);

  const _ManualEntryTab(this.type);

  final EntryType type;
}

enum _DebtDirection {
  borrow(AccountType.payable),
  lend(AccountType.receivable);

  const _DebtDirection(this.accountType);

  final AccountType accountType;
}

class _EntryDetailPageState extends State<_EntryDetailForm> {
  EntryDetailPage get _config => widget.config;

  late double _amount = _config.initialAmount;
  late double _discountAmount = _config.initialDiscountAmount;
  double _inlineGrossAmount = 0;
  double get _grossAmount =>
      _config.inlineNumberPad ? _inlineGrossAmount : _amount + _discountAmount;
  EntryType _type = EntryType.expense;
  _DebtDirection? _debtDirection;
  // 空串 = 尚未选分类；build 时会按当前账本的该类型分类补上首个可用项
  // （分类属于账本，不存在跨账本通用的固定 id）。
  String _categoryId = '';
  String? _collapsedCategoryId;
  late String _accountId = _config.initialAccountId ?? '';
  // 「无账户」：只记金额、不计入任何账户余额（仅收支有效，转账必须选账户）。
  bool _noAccount = false;
  String? _toAccountId;
  DateTime _occurredAt = DateTime.now();
  double _fee = 0;
  String? _currencyCode;
  double? _accountAmount;
  double? _toAccountAmount;
  double? _baseAmount;
  ConversionSource _conversionSource = ConversionSource.identity;
  bool _currencyTouched = false;
  bool _accountAmountTouched = false;
  bool _toAccountAmountTouched = false;
  bool _baseAmountTouched = false;
  bool _rememberRate = false;
  bool _moneyInitialized = false;
  bool _accountFallbackResolved = false;
  Set<String> _missingRateCodes = <String>{};
  ConvertedCurrencyAmount? _accountConversion;
  ConvertedCurrencyAmount? _toAccountConversion;
  ConvertedCurrencyAmount? _baseConversion;
  // 支出可标记「待报销」；新建时不涉及回款冲抵，退款金额建后在编辑页填写。
  bool _reimbursable = false;
  // 支出可标记「不计入预算」（借款、垫付等）：只脱离预算口径，收支统计照旧。
  EntryStatisticsScope _statisticsScope = EntryStatisticsScope.normal;
  List<String> _tagIds = <String>[];
  // 新增交易时先把附件字节落盘（stageNewAttachment），保存时只提交元数据。
  final List<Attachment> _pendingAttachments = <Attachment>[];
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocus = FocusNode();
  _NoteKeyboardTiming? _noteKeyboardTiming;

  // 自动识别：用户未手动改动某字段前，按历史（金额/备注/时段）自动填充类型、分类、
  // 标签、备注；某字段一旦被用户改过就不再覆盖它。AI 草稿模式（initialDraft）下整体
  // 关闭自动识别，尊重草稿。
  bool _typeTouched = false;
  bool _categoryTouched = false;
  bool _tagsTouched = false;
  bool _noteTouched = false;
  // 用户是否手动选过账户：选过就不再被「该分类上次用过的账户」覆盖。
  bool _accountTouched = false;
  bool _creatingDebtAccount = false;
  // 防重复提交：极快双击「保存」可能在 pop 生效前触发两次、落两条交易。
  bool _saving = false;
  bool _saved = false;
  // 保存成功或确认丢弃后置真，让 PopScope 放行程序化返回。
  bool _allowPop = false;
  late final String _entryId =
      _config.draftEntry?.id ??
      DateTime.now().microsecondsSinceEpoch.toString();
  LedgerEntry? _initialEntryDraft;
  List<String>? _initialAttachmentIds;
  LedgerEntry? _savedResult;
  bool _didInitialSuggest = false;
  // 备注逐字重算的防抖句柄：识别要扫一遍历史并整页重建，不能每次按键都同步跑。
  Timer? _suggestDebounce;
  // 草稿编辑模式（导入预览）与 AI 草稿一样关闭自动识别，尊重传入数据。
  late final bool _draftFree =
      _config.initialDraft == null && _config.draftEntry == null;

  /// 自动识别是否生效：非草稿模式，且用户没在设置里关掉总开关
  /// （`controller.autoSuggestEnabled`，全局偏好、进备份）。
  bool get _autoSuggestEnabled =>
      _draftFree &&
      _debtDirection == null &&
      VeriFinScope.of(context).autoSuggestEnabled;

  bool get _isDraft => _config.draftEntry != null;

  @override
  void initState() {
    super.initState();
    final editing = _config.draftEntry;
    if (editing != null) {
      _type = editing.type;
      if (editing.categoryId.isNotEmpty) {
        _categoryId = editing.categoryId;
      }
      if (editing.type != EntryType.transfer && editing.accountId.isEmpty) {
        _noAccount = true;
        _accountId = '';
      } else {
        _accountId = editing.accountId;
      }
      _toAccountId = editing.toAccountId;
      _occurredAt = editing.occurredAt;
      _fee = editing.fee;
      _currencyCode = editing.currencyCode;
      _accountAmount = editing.accountAmount;
      _toAccountAmount = editing.toAccountAmount;
      _baseAmount = editing.baseAmount;
      _conversionSource = editing.conversionSource;
      _reimbursable = editing.reimbursable;
      _statisticsScope = editing.statisticsScope;
      _tagIds = List<String>.of(editing.tagIds);
      _noteController.text = editing.note;
    }
    final draft = _config.initialDraft;
    if (draft != null) {
      _type = draft.type;
      if (draft.categoryId.isNotEmpty) {
        _categoryId = draft.categoryId;
      }
      // 转账必须落到账户；收支允许「无账户」（空 accountId）。AI 没识别到账户时，
      // 若配置了默认付款账户（initialAccountId）就用它，否则记为「无账户」。
      if (draft.type != EntryType.transfer && draft.accountId.isEmpty) {
        final fallback = _config.initialAccountId ?? '';
        if (fallback.isNotEmpty) {
          _accountId = fallback;
        } else {
          _noAccount = true;
          _accountId = '';
        }
      } else {
        _accountId = draft.accountId;
      }
      _toAccountId = draft.toAccountId;
      _occurredAt = draft.occurredAt;
      _currencyCode = draft.currencyCode;
      _noteController.text = draft.note;
      final tag = _config.suggestedPlatformTag;
      if (tag != null) _tagIds = [tag.id];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_moneyInitialized) {
      _initializeCurrencyAmounts();
    } else {
      _resolveNewlyAvailableAccount();
    }
    if (_autoSuggestEnabled && !_didInitialSuggest && _amount > 0) {
      _didInitialSuggest = true;
      _recomputeSuggestion();
    }
  }

  /// 账户从「无」变成「有」时补一次金额解析。用户在记账页空状态里新建账户后返回
  /// 就会走到这里：不补这一次，`_accountAmount` 一直是 null，保存按钮会一直禁用。
  void _resolveNewlyAvailableAccount() {
    if (_accountFallbackResolved || _noAccount || _accountAmount != null) {
      return;
    }
    final controller = VeriFinScope.of(context);
    final accounts = _availableAccounts(controller);
    if (accounts.isEmpty) {
      return;
    }
    _accountFallbackResolved = true;
    if (!accounts.any((account) => account.id == _accountId)) {
      _accountId = accounts.first.id;
    }
    _refreshCurrencyAmounts(
      controller,
      accounts,
      forceAccount: true,
      forceBase: true,
    );
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _noteKeyboardTiming?.cancel();
    _noteFocus.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<Account> _availableAccounts(VeriFinController controller) {
    final values = _isDraft
        ? <Account>[...controller.accounts, ..._config.draftExtraAccounts!]
        : controller.accounts;
    return values
        .where(
          (account) =>
              !account.hidden &&
              (!_config.inlineNumberPad ||
                  _type == EntryType.transfer ||
                  !account.type.isDebt),
        )
        .toList();
  }

  Account? _accountFor(List<Account> accounts, String? id) {
    if (id == null || id.isEmpty) return null;
    return accounts.where((account) => account.id == id).firstOrNull;
  }

  void _initializeCurrencyAmounts() {
    final controller = VeriFinScope.of(context);
    final accounts = _availableAccounts(controller);
    if (_config.inlineNumberPad && accounts.isEmpty) {
      _noAccount = true;
    }
    if (!_noAccount &&
        accounts.isNotEmpty &&
        !accounts.any((account) => account.id == _accountId)) {
      _accountId = accounts.first.id;
    }
    _normalizeTransferAccounts(accounts);
    _currencyCode ??=
        _accountFor(accounts, _accountId)?.currencyCode ??
        controller.activeBook.baseCurrencyCode;
    _moneyInitialized = true;
    if (_config.draftEntry == null) {
      _refreshCurrencyAmounts(
        controller,
        accounts,
        forceAccount: true,
        forceToAccount: true,
        forceBase: true,
      );
    } else {
      _refreshMissingRateCodes(controller, accounts);
    }
  }

  double? _convertAmount(
    VeriFinController controller, {
    required double amount,
    required String sourceCode,
    required String targetCode,
    required _EntryConversionTarget target,
  }) {
    final result = controller.convertAmount(
      amount: amount,
      sourceCurrencyCode: sourceCode,
      targetCurrencyCode: targetCode,
      date: _occurredAt,
    );
    if (result is ConvertedCurrencyAmount) {
      switch (target) {
        case _EntryConversionTarget.account:
          _accountConversion = result;
        case _EntryConversionTarget.toAccount:
          _toAccountConversion = result;
        case _EntryConversionTarget.base:
          _baseConversion = result;
      }
      return result.amount;
    }
    switch (target) {
      case _EntryConversionTarget.account:
        _accountConversion = null;
      case _EntryConversionTarget.toAccount:
        _toAccountConversion = null;
      case _EntryConversionTarget.base:
        _baseConversion = null;
    }
    if (result is MissingCurrencyRate) {
      _missingRateCodes.addAll(result.currencyCodes);
    }
    return null;
  }

  void _refreshCurrencyAmounts(
    VeriFinController controller,
    List<Account> accounts, {
    bool forceAccount = false,
    bool forceToAccount = false,
    bool forceBase = false,
  }) {
    _missingRateCodes = <String>{};
    final baseCode = controller.activeBook.baseCurrencyCode;
    final account = _noAccount ? null : _accountFor(accounts, _accountId);
    final toAccount = _accountFor(accounts, _toAccountId);

    if (_type == EntryType.transfer) {
      _accountConversion = null;
      _baseConversion = null;
      if (account != null) {
        _currencyCode = account.currencyCode;
        _amount = normalizeCurrencyAmount(_amount, account.currencyCode);
        _accountAmount = _amount;
      } else {
        _accountAmount = null;
      }
      _baseAmount = 0;
      if (account == null || toAccount == null) {
        _toAccountAmount = null;
        _toAccountConversion = null;
      } else if (toAccount.currencyCode == account.currencyCode) {
        _toAccountAmount = normalizeCurrencyAmount(
          _amount,
          toAccount.currencyCode,
        );
        _toAccountAmountTouched = false;
        _toAccountConversion = null;
      } else if (forceToAccount || !_toAccountAmountTouched) {
        _toAccountAmount = _convertAmount(
          controller,
          amount: _amount,
          sourceCode: _currencyCode!,
          targetCode: toAccount.currencyCode,
          target: _EntryConversionTarget.toAccount,
        );
      }
      _conversionSource = _toAccountAmountTouched
          ? ConversionSource.manual
          : account != null &&
                toAccount != null &&
                account.currencyCode != toAccount.currencyCode
          ? ConversionSource.rateTable
          : ConversionSource.identity;
      _refreshMissingRateCodes(controller, accounts);
      return;
    }

    final code = _currencyCode ?? baseCode;
    if (account == null) {
      _accountAmount = null;
      _accountConversion = null;
    } else if (code == account.currencyCode) {
      _accountAmount = normalizeCurrencyAmount(_amount, account.currencyCode);
      _accountAmountTouched = false;
      _accountConversion = null;
    } else if (forceAccount || !_accountAmountTouched) {
      _accountAmount = _convertAmount(
        controller,
        amount: _amount,
        sourceCode: code,
        targetCode: account.currencyCode,
        target: _EntryConversionTarget.account,
      );
    }

    if (code == baseCode) {
      _baseAmount = normalizeCurrencyAmount(_amount, baseCode);
      _baseAmountTouched = false;
      _baseConversion = null;
    } else if (account?.currencyCode == baseCode && _accountAmount != null) {
      _baseAmount = normalizeCurrencyAmount(_accountAmount!, baseCode);
      _baseAmountTouched = _accountAmountTouched;
      _baseConversion = null;
    } else if (forceBase || !_baseAmountTouched) {
      _baseAmount = _convertAmount(
        controller,
        amount: _amount,
        sourceCode: code,
        targetCode: baseCode,
        target: _EntryConversionTarget.base,
      );
    }
    _conversionSource = _accountAmountTouched || _baseAmountTouched
        ? ConversionSource.manual
        : code == baseCode &&
              (account == null || account.currencyCode == baseCode)
        ? ConversionSource.identity
        : ConversionSource.rateTable;
    _refreshMissingRateCodes(controller, accounts);
  }

  void _refreshMissingRateCodes(
    VeriFinController controller,
    List<Account> accounts,
  ) {
    final missing = <String>{};
    final code = _currencyCode ?? controller.activeBook.baseCurrencyCode;
    final account = _noAccount ? null : _accountFor(accounts, _accountId);
    final toAccount = _accountFor(accounts, _toAccountId);
    if (_type == EntryType.transfer) {
      if (toAccount != null &&
          toAccount.currencyCode != code &&
          _toAccountAmount == null) {
        final result = controller.convertAmount(
          amount: _amount,
          sourceCurrencyCode: code,
          targetCurrencyCode: toAccount.currencyCode,
          date: _occurredAt,
        );
        if (result is MissingCurrencyRate) missing.addAll(result.currencyCodes);
      }
    } else {
      if (account != null &&
          account.currencyCode != code &&
          _accountAmount == null) {
        final result = controller.convertAmount(
          amount: _amount,
          sourceCurrencyCode: code,
          targetCurrencyCode: account.currencyCode,
          date: _occurredAt,
        );
        if (result is MissingCurrencyRate) missing.addAll(result.currencyCodes);
      }
      if (code != controller.activeBook.baseCurrencyCode &&
          _baseAmount == null) {
        final result = controller.convertAmount(
          amount: _amount,
          sourceCurrencyCode: code,
          targetCurrencyCode: controller.activeBook.baseCurrencyCode,
          date: _occurredAt,
        );
        if (result is MissingCurrencyRate) missing.addAll(result.currencyCodes);
      }
    }
    _missingRateCodes = missing;
  }

  List<DateTime> get _usedRateDates {
    final dates = <DateTime>{};
    for (final conversion in <ConvertedCurrencyAmount?>[
      _accountConversion,
      _toAccountConversion,
      _baseConversion,
    ]) {
      if (conversion?.sourceRateDate != null) {
        dates.add(conversion!.sourceRateDate!);
      }
      if (conversion?.targetRateDate != null) {
        dates.add(conversion!.targetRateDate!);
      }
    }
    return dates.toList()..sort();
  }

  void _onNoteChanged(String _) {
    // TextField 仅在用户编辑文本时调用，光标、选区和程序化赋值不触发识别。
    if (!_autoSuggestEnabled) {
      if (_isDraft) setState(() {});
      return;
    }
    // 用户真的在输备注：标记已改（不再回填备注），并安排按新备注重算类型/分类/标签
    // （防抖 300ms，见 [_scheduleSuggestion]）。
    _noteTouched = true;
    _scheduleSuggestion();
  }

  /// 备注和页内金额输入停顿后才重算，避免每次按键都扫描历史。
  void _scheduleSuggestion() {
    _suggestDebounce?.cancel();
    _suggestDebounce = Timer(
      const Duration(milliseconds: 300),
      _recomputeSuggestion,
    );
  }

  /// 清掉挂起的防抖重算。识别只填「用户没改过」的字段，因此手动选择无需取消；
  /// 这里只用于重算开始前作废重复计时器、以及保存前 flush。
  void _cancelPendingSuggestion() {
    _suggestDebounce?.cancel();
    _suggestDebounce = null;
  }

  /// 按当前金额/备注/时段从历史识别，并填充「用户尚未改过」的字段。
  ///
  /// [suggestAccount] 为 false 时不动账户：保存前 flush 挂起的识别时，页面上显示的
  /// 账户已经是用户看到的样子，不能在落账瞬间再换一个。
  void _recomputeSuggestion({bool suggestAccount = true}) {
    _cancelPendingSuggestion();
    if (!mounted || !_autoSuggestEnabled) {
      return;
    }
    final controller = VeriFinScope.of(context);
    final suggestion = suggestEntry(
      history: controller.entries,
      expenseCategoryIds: controller
          .categoriesForType(EntryType.expense)
          .map((c) => c.id)
          .toSet(),
      incomeCategoryIds: controller
          .categoriesForType(EntryType.income)
          .map((c) => c.id)
          .toSet(),
      note: _noteController.text,
      amount: _amount,
      currencyCode: _currencyCode ?? controller.activeBook.baseCurrencyCode,
      hour: _occurredAt.hour,
      // 用户已手动选过类型：不再翻转类型，只在该类型内识别分类/标签/备注。
      forcedType: _typeTouched ? _type : null,
    );
    if (!suggestion.isEmpty) {
      setState(() {
        if (!_typeTouched && suggestion.type != null) {
          _type = suggestion.type!;
        }
        if (!_categoryTouched && suggestion.categoryId != null) {
          _categoryId = suggestion.categoryId!;
        }
        if (!_tagsTouched && _tagIds.isEmpty && suggestion.tagIds != null) {
          _tagIds = List<String>.of(suggestion.tagIds!);
        }
        if (!_noteTouched &&
            !_noteFocus.hasFocus &&
            _noteController.text.isEmpty &&
            suggestion.note != null) {
          _noteController.text = suggestion.note!;
        }
      });
    }
    // 分类定下来之后（无论是识别出来的还是用户选的）再预选账户。
    if (suggestAccount) {
      _applyCategoryAccountSuggestion(controller);
    }
  }

  /// 自动识别开启时，按分类预选「这个分类上次用过的账户」；用户手动改过账户、
  /// 选了「无账户」或当前是转账（两端账户都是显式选择）时都不覆盖。
  /// 关闭自动识别时保持原行为——只用账本默认账户。
  void _applyCategoryAccountSuggestion(VeriFinController controller) {
    if (!_autoSuggestEnabled || _accountTouched || _noAccount) {
      return;
    }
    if (_type == EntryType.transfer) {
      return;
    }
    final suggested = lastUsedAccountIdForCategory(
      history: controller.entries,
      categoryId: _categoryId,
      type: _type,
    );
    if (suggested == null || suggested == _accountId) {
      return;
    }
    final accounts = _availableAccounts(controller);
    final account = accounts.where((item) => item.id == suggested).firstOrNull;
    if (account == null) {
      return;
    }
    setState(() {
      _accountId = suggested;
      if (!_currencyTouched) {
        _currencyCode = account.currencyCode;
      }
      _refreshCurrencyAmounts(
        controller,
        accounts,
        forceAccount: true,
        forceBase: true,
      );
    });
  }

  /// 指定类型的可选分类：草稿模式下把传入的临时分类（未落库，如导入将新建的）
  /// 追加到账本现有分类之后，保证草稿引用到它们时能被解析、不被回退。
  List<Category> _categoriesForType(
    VeriFinController controller,
    EntryType type,
  ) {
    final base = controller.categoriesForType(type);
    if (!_isDraft) {
      return base;
    }
    return <Category>[
      ...base,
      ..._config.draftExtraCategories!.where(
        (category) => category.type == type,
      ),
    ];
  }

  /// 分类快捷区展示的前若干个顶级分类；若当前选中项所属的顶级分类不在前 8 个里，则把它
  /// 置顶插入，保证被选中/推荐分类所在的分支始终可见（可展开选到具体子分类）。
  List<Category> _visibleTopChips(List<Category> roots, String selectedTopId) {
    final shown = roots.take(8).toList();
    if (!shown.any((c) => c.id == selectedTopId)) {
      final idx = roots.indexWhere((c) => c.id == selectedTopId);
      if (idx >= 0) {
        shown.insert(0, roots[idx]);
        if (shown.length > 8) {
          shown.removeLast();
        }
      }
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    // 本页只能表达用户可选的类型：退款不在此选择（只能从「原支出 → 添加退款」创建），
    // 且没有退款分类。任何来路（自动识别、草稿）带进来的非可选类型都归一化回支出，
    // 否则下方分类列表为空、类型选择器也会选不中任何一段。
    if (!EntryType.userSelectable.contains(_type)) {
      _type = EntryType.expense;
    }
    // 草稿模式下把临时账户（未落库，如导入将新建的）并入可选列表。
    final accounts = _availableAccounts(controller);
    final hasAccounts = accounts.isNotEmpty;
    final quick = _config.inlineNumberPad;
    final quickTransfer = quick && _type == EntryType.transfer;
    // 转账必须落到具体账户，不允许「无账户」。
    if (_type == EntryType.transfer) {
      _noAccount = false;
    }
    if (!quickTransfer &&
        hasAccounts &&
        !_noAccount &&
        !accounts.any((account) => account.id == _accountId)) {
      _accountId = accounts.first.id;
    }
    _normalizeTransferAccounts(accounts);
    final categories = _categoriesForType(controller, _type);
    if (_config.draftReviewHint == null &&
        !categories.any((category) => category.id == _categoryId)) {
      // 兜底而非 `categories.first`：某类型一个分类都没有时，宁可先留空（保存前
      // 由用户选，最坏也只是一条无分类交易）也不能让整页 build 抛异常白屏。
      // 上面的类型归一化 + 「不许删光某类型最后一个分类」的保护已让空列表不可达，
      // 这里只是最后一道防线。
      _categoryId = categories.isEmpty ? '' : categories.first.id;
    }
    final selectedTopId = rootIdOf(categories, _categoryId);
    // 大金额颜色跟随类型:支出红、收入青绿、转账保持蓝色。
    final amountColor = switch (_type) {
      EntryType.expense => veriSemantic(context, veriExpense),
      EntryType.income => veriSemantic(context, veriIncome),
      EntryType.transfer => veriSemantic(context, veriBlue),
      // 退款不在此页手动选择，仅作穷尽兜底（正向流入用青绿）。
      EntryType.refund => veriSemantic(context, veriIncome),
    };
    // 用带单位的格式化：单币种账本按偏好隐藏单位，多币种账本必须能看出币种。
    final amountCode = _currencyCode ?? controller.activeBook.baseCurrencyCode;
    final amountNumber = formatUserMoney(_grossAmount, amountCode);
    // 符号与 formatSignedAmount 保持同一套写法（ASCII 正负号、无空格），
    // 否则这里会成为全应用唯一使用 U+2212 加空格的位置。
    final amountText = switch (_type) {
      EntryType.expense => '-$amountNumber',
      EntryType.income => '+$amountNumber',
      EntryType.transfer => amountNumber,
      EntryType.refund => '+$amountNumber',
    };
    _captureInitialSnapshot();
    final canSave = _canSave(accounts);
    final saveReason = canSave ? null : _saveBlockReason(accounts);

    final l10n = AppLocalizations.of(context);
    final typePicker = quick
        ? _buildManualTypePicker()
        : _EntryTypeSelector(
            key: const Key('entry_type_segmented_button'),
            selected: _type,
            onChanged: _changeEntryType,
          );
    final roots = rootCategories(categories, _type);
    final categoryGrid = EntryCategoryGrid(
      categories: quick ? roots : _visibleTopChips(roots, selectedTopId),
      iconGrid: quick,
      allCategories: categories,
      selectedId: _categoryId,
      selectedTopId: selectedTopId,
      accent: amountColor,
      onSelected: _selectCategory,
      // 默认展开当前选中大类的二级分类，避免快速记账页中间留出大片空白。
      collapsedId: _collapsedCategoryId,
      onToggleBranch: quick ? _toggleCategoryBranch : null,
      onOpenAll: () => unawaited(_showAllCategories()),
      allLabel: AppLocalizations.of(context).allLabel,
    );
    final keyboardLogger = _diagnoseNoteKeyboard ? controller.logger : null;
    final noteField = TextField(
      key: const Key('entry_note_field'),
      controller: _noteController,
      focusNode: _noteFocus,
      maxLines: 1,
      textInputAction: TextInputAction.done,
      onChanged: _onNoteChanged,
      onTap: keyboardLogger == null
          ? null
          : () {
              (_noteKeyboardTiming ??= _NoteKeyboardTiming(
                view: View.of(context),
                focus: _noteFocus,
                report: (message) => keyboardLogger.info(
                  message,
                  source: quick ? 'ime.quick_entry_note' : 'ime.entry_note',
                ),
              )).start();
            },
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        labelText: quick ? null : l10n.commonNote,
        hintText: l10n.noteHint,
        prefixIcon: quick ? null : const Icon(Icons.notes),
        filled: !quick,
        border: quick ? InputBorder.none : null,
        enabledBorder: quick ? InputBorder.none : null,
        focusedBorder: quick ? InputBorder.none : null,
        disabledBorder: quick ? InputBorder.none : null,
        isDense: quick,
        contentPadding: quick ? EdgeInsets.zero : null,
      ),
    );
    final dateLabel = quick && DateUtils.isSameDay(_occurredAt, DateTime.now())
        ? l10n.todayLabel
        : l10n.dateMonthDay(_occurredAt);
    final dateTimeChip = EntryMetadataPill(
      key: const Key('entry_metadata_datetime'),
      icon: Icons.calendar_today_outlined,
      label: Text('$dateLabel ${formatTime(_occurredAt)}'),
      compact: quick,
      onTap: _pickDateTime,
    );
    final discountChip = EntryMetadataPill(
      key: const Key('entry_metadata_discount'),
      icon: Icons.percent_rounded,
      label: Text(
        _discountAmount > 0
            ? l10n.entryDiscountValue(
                formatUserMoney(_discountAmount, amountCode),
              )
            : l10n.entryDiscountLabel,
      ),
      selected: _discountAmount > 0,
      compact: quick,
      onTap: _grossAmount > 0 || _discountAmount > 0
          ? () => _editDiscount(amountCode)
          : null,
    );
    final payable = _discountAmount > 0 && _grossAmount > _discountAmount
        ? Text(
            l10n.entryPayableValue(formatUserMoney(_amount, amountCode)),
            style: Theme.of(context).textTheme.bodySmall,
          )
        : null;
    final tagsChip = EntryMetadataPill(
      key: const Key('entry_metadata_tags'),
      icon: Icons.sell_outlined,
      label: Text(
        _tagIds.isEmpty ? l10n.tagLabel : l10n.entryTagCount(_tagIds.length),
      ),
      selected: _tagIds.isNotEmpty,
      compact: quick,
      onTap: _pickTags,
    );
    final statisticsToggles = EntryStatisticsScope.supports(_type)
        ? EntryStatisticsToggles(
            type: _type,
            scope: _statisticsScope,
            onChanged: (scope) => setState(() => _statisticsScope = scope),
          )
        : null;
    final extraMetadata = <Widget>[
      if (quickTransfer && _debtDirection == null && roots.isNotEmpty)
        EntryMetadataPill(
          key: const Key('quick_transfer_category'),
          icon: Icons.category_outlined,
          compact: quick,
          label: Text(l10n.commonCategory),
          onTap: _showAllCategories,
        ),
      if (_type == EntryType.expense)
        Tooltip(
          message: l10n.reimbursableHint,
          child: EntryMetadataPill(
            key: const Key('entry_metadata_reimbursable'),
            toggle: true,
            compact: quick,
            icon: Icons.receipt_long_outlined,
            label: Text(l10n.badgeReimbursable),
            selected: _reimbursable,
            onTap: () => setState(() => _reimbursable = !_reimbursable),
          ),
        ),
      if (!_isDraft)
        AnchoredMenuAnchor(
          entries: <AnchoredMenuEntry>[
            AnchoredMenuItem(
              id: 'entry_attachment_camera',
              icon: Icons.photo_camera_outlined,
              title: AppLocalizations.of(context).attachTakePhoto,
              enabled: attachmentPickingSupported,
              onPressed: () => unawaited(_addAttachment(fromCamera: true)),
            ),
            AnchoredMenuItem(
              id: 'entry_attachment_gallery',
              icon: Icons.photo_library_outlined,
              title: AppLocalizations.of(context).attachFromGallery,
              enabled: attachmentPickingSupported,
              onPressed: () => unawaited(_addAttachment(fromCamera: false)),
            ),
          ],
          semanticLabel: AppLocalizations.of(context).attachTitle,
          builder: (context, openMenu, menuOpen) => EntryMetadataPill(
            key: const Key('entry_metadata_attachments'),
            icon: Icons.add_photo_alternate_outlined,
            compact: quick,
            label: Text(
              _pendingAttachments.isEmpty
                  ? AppLocalizations.of(context).attachTitle
                  : AppLocalizations.of(
                      context,
                    ).entryAttachmentCount(_pendingAttachments.length),
            ),
            selected: _pendingAttachments.isNotEmpty || menuOpen,
            onTap: attachmentPickingSupported ? openMenu : null,
          ),
        ),
      if (controller.multiCurrencyEnabled)
        EntryMetadataPill(
          key: const Key('entry_currency_button'),
          icon: Icons.currency_exchange_rounded,
          compact: quick,
          label: Text(_currencyCode ?? controller.activeBook.baseCurrencyCode),
          selected:
              (_currencyCode ?? controller.activeBook.baseCurrencyCode) !=
              controller.activeBook.baseCurrencyCode,
          onTap: _type == EntryType.transfer ? null : _pickCurrency,
        ),
    ];
    final attachmentsEditor = !_isDraft && _pendingAttachments.isNotEmpty
        ? AttachmentsEditor(
            attachments: _pendingAttachments,
            store: VeriFinScope.of(context).attachmentStore,
            onAddBytes: (bytes) async {
              final attachment = await VeriFinScope.of(
                context,
              ).stageNewAttachment(entryId: _entryId, bytes: bytes);
              if (!mounted) return;
              setState(() => _pendingAttachments.add(attachment));
            },
            onRemoveIndex: (index) =>
                setState(() => _pendingAttachments.removeAt(index)),
            showHeader: false,
            showAddButton: false,
          )
        : null;
    final details = <Widget>[
      if (hasAccounts && _type == EntryType.transfer && !quick) ...<Widget>[
        SelectField(
          key: const Key('account_dropdown'),
          label: AppLocalizations.of(context).transferOutAccount,
          value:
              '${accountById(accounts, _accountId).name} (${formatUserMoney(controller.accountBalance(accountById(accounts, _accountId)), accountById(accounts, _accountId).currencyCode)})',
          leading: AccountIconBox(
            iconCode: effectiveAccountIconCode(
              accountById(accounts, _accountId).iconCode,
              accountById(accounts, _accountId).name,
            ),
            size: 26,
          ),
          onTap: () => _pickAccount(accounts),
        ),
        const SizedBox(height: 10),
        SelectField(
          key: const Key('to_account_dropdown'),
          label: AppLocalizations.of(context).transferInAccount,
          value: _toAccountId == null
              ? AppLocalizations.of(context).pleaseSelect
              : '${accountById(accounts, _toAccountId!).name} (${formatUserMoney(controller.accountBalance(accountById(accounts, _toAccountId!)), accountById(accounts, _toAccountId!).currencyCode)})',
          icon: _toAccountId == null ? Icons.call_received : null,
          leading: _toAccountId == null
              ? null
              : AccountIconBox(
                  iconCode: effectiveAccountIconCode(
                    accountById(accounts, _toAccountId!).iconCode,
                    accountById(accounts, _toAccountId!).name,
                  ),
                  size: 26,
                ),
          onTap: accounts.length < 2 ? null : () => _pickToAccount(accounts),
        ),
        const SizedBox(height: 10),
        SelectField(
          key: const Key('fee_field'),
          label: AppLocalizations.of(context).feeLabel,
          value: _fee > 0
              ? formatUserMoney(
                  _fee,
                  _currencyCode ?? controller.activeBook.baseCurrencyCode,
                )
              : AppLocalizations.of(context).feeNoneTapToFill,
          icon: Icons.paid_outlined,
          onTap: _editFee,
        ),
      ] else if (hasAccounts && !quick)
        SelectField(
          key: const Key('account_dropdown'),
          label: AppLocalizations.of(context).accountLabel,
          value: _noAccount
              ? AppLocalizations.of(context).noAccountLabel
              : '${accountById(accounts, _accountId).name} (${formatUserMoney(controller.accountBalance(accountById(accounts, _accountId)), accountById(accounts, _accountId).currencyCode)})',
          icon: _noAccount ? Icons.money_off_csred_outlined : null,
          leading: _noAccount
              ? null
              : AccountIconBox(
                  iconCode: effectiveAccountIconCode(
                    accountById(accounts, _accountId).iconCode,
                    accountById(accounts, _accountId).name,
                  ),
                  size: 26,
                ),
          onTap: () => _pickAccount(accounts),
        )
      else if (!hasAccounts && !quickTransfer)
        EmptyState(
          icon: Icons.account_balance_wallet_outlined,
          title: AppLocalizations.of(context).noUsableAccountTitle,
          description: AppLocalizations.of(context).noUsableAccountDesc,
          // 空状态只说原因不给出口，用户就会卡在「保存按钮永远灰」的死路上。
          action: FilledButton.tonalIcon(
            key: const Key('entry_add_account_action'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AddAccountPage()),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(AppLocalizations.of(context).accountAdd),
          ),
        ),
      if (!quickTransfer) ..._buildCurrencyAmountFields(controller, accounts),
      if (!quick) ...[
        const SizedBox(height: 14),
        noteField,
        const SizedBox(height: 14),
        Text(
          l10n.entryMoreInfo,
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
      ],
      Wrap(
        key: const Key('entry_metadata_chips'),
        spacing: 7,
        runSpacing: 7,
        children: <Widget>[
          dateTimeChip,
          if (_type == EntryType.expense) discountChip,
          tagsChip,
          ?statisticsToggles,
          ...extraMetadata,
        ],
      ),
      if (attachmentsEditor != null) ...<Widget>[
        const SizedBox(height: 10),
        attachmentsEditor,
      ],
    ];
    return PopScope<Object?>(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_discardAndPop());
      },
      child: Scaffold(
        resizeToAvoidBottomInset: !quick,
        bottomNavigationBar: quick
            ? null
            : _EntryBottomSaveBar(
                enabled: _isDirty && canSave,
                reason: saveReason,
                onPressed: _saveAndExit,
              ),
        body: SafeArea(
          bottom: !quick,
          child: quick
              ? VeriPage(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
                        child: Row(
                          children: [
                            const BackButton(),
                            Expanded(child: typePicker),
                            IconButton(
                              icon: const Icon(Icons.tune_rounded),
                              tooltip: l10n.categoryMgmt,
                              onPressed: () => Navigator.of(context).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => CategoryManagementPage(
                                    initialType: _type,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: ShapeDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.55),
                              shape: const StadiumBorder(),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.menu_book_outlined,
                                  size: 13,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.65),
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    controller.activeBook.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: RepaintBoundary(
                          child: ListView(
                            key: ValueKey(_type),
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                            children: [
                              if (quickTransfer)
                                _buildManualTransfer(controller, accounts)
                              else
                                VeriCard(
                                  padding: const EdgeInsets.all(10),
                                  child: categoryGrid,
                                ),
                              if (attachmentsEditor != null) ...[
                                const SizedBox(height: 10),
                                attachmentsEditor,
                              ],
                            ],
                          ),
                        ),
                      ),
                      NumberPadSheet.inline(
                        initialAmount: _config.initialAmount,
                        currencyCode: amountCode,
                        maxFractionDigits: CurrencyCatalog.require(
                          amountCode,
                        ).minorUnit,
                        layout: controller.numberPadLayout,
                        submitEnabled: canSave,
                        blockReason: saveReason,
                        amountLeading: Row(
                          spacing: 6,
                          children: [
                            Icon(
                              Icons.notes_rounded,
                              size: 16,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            Expanded(child: noteField),
                          ],
                        ),
                        amountColor: amountColor,
                        metadata: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ?payable,
                            EntryMetadataStrip(
                              key: const Key('quick_entry_metadata_strip'),
                              children: [
                                dateTimeChip,
                                if (_type == EntryType.expense) discountChip,
                                if (!quickTransfer)
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 112,
                                    ),
                                    child: EntryMetadataPill(
                                      key: const Key('quick_entry_account'),
                                      icon:
                                          Icons.account_balance_wallet_outlined,
                                      compact: true,
                                      label: Text(
                                        hasAccounts && !_noAccount
                                            ? accountById(
                                                accounts,
                                                _accountId,
                                              ).name
                                            : l10n.noAccountLabel,
                                      ),
                                      onTap: () => _pickAccount(accounts),
                                    ),
                                  ),
                                if (quickTransfer && _debtDirection == null)
                                  EntryMetadataPill(
                                    key: const Key('fee_field'),
                                    icon: Icons.paid_outlined,
                                    compact: true,
                                    label: Text(l10n.feeLabel),
                                    selected: _fee > 0,
                                    onTap: _accountId.isEmpty ? null : _editFee,
                                  ),
                                tagsChip,
                                ?statisticsToggles,
                                ...extraMetadata,
                                if (!hasAccounts && !quickTransfer)
                                  EntryMetadataPill(
                                    key: const Key('entry_add_account_action'),
                                    icon: Icons.add,
                                    compact: true,
                                    label: Text(l10n.accountAdd),
                                    onTap: () =>
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const AddAccountPage(),
                                          ),
                                        ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        onAmountChanged: _onInlineAmountChanged,
                        onCancel: () => unawaited(_discardAndPop()),
                        onContinue: (amount) {
                          _onInlineAmountChanged(amount);
                          unawaited(_saveAndContinue());
                        },
                        onSubmitted: (amount) {
                          _onInlineAmountChanged(amount);
                          unawaited(_saveAndExit());
                        },
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    VeriHeader(
                      title: controller.activeBook.name,
                      subtitle: l10n.entryDetailSubtitle,
                      showBack: true,
                    ),
                    if (_config.initialDraft != null) ...[
                      const SizedBox(height: 12),
                      _AiReviewBanner(
                        draft: _config.initialDraft!,
                        reviewHint: _config.draftReviewHint,
                      ),
                    ],
                    const SizedBox(height: 12),
                    typePicker,
                    const SizedBox(height: 16),
                    InkWell(
                      key: const Key('detail_amount_button'),
                      borderRadius: BorderRadius.circular(veriRadiusMd),
                      onTap: _editAmount,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          amountText,
                          style: Theme.of(context).textTheme.displayLarge
                              ?.copyWith(
                                color: amountColor,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ),
                    ?payable,
                    const SizedBox(height: 12),
                    Text(
                      l10n.commonCategory,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    categoryGrid,
                    const SizedBox(height: 18),
                    ...details,
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildManualTypePicker() {
    final l10n = AppLocalizations.of(context);
    final selected = _debtDirection == null
        ? _ManualEntryTab.values.firstWhere((tab) => tab.type == _type)
        : _ManualEntryTab.debt;
    return VeriSegmentedControl<_ManualEntryTab>(
      key: const Key('entry_type_segmented_button'),
      values: _ManualEntryTab.values,
      selected: selected,
      semanticLabel: l10n.commonType,
      labelOf: (tab) => tab == _ManualEntryTab.debt
          ? l10n.entryTypeDebt
          : tab.type.label(l10n),
      accentOf: (tab) => switch (tab) {
        _ManualEntryTab.expense => veriSemantic(context, veriExpense),
        _ManualEntryTab.income => veriSemantic(context, veriIncome),
        _ManualEntryTab.transfer ||
        _ManualEntryTab.debt => veriSemantic(context, veriBlue),
      },
      keyOf: (tab) =>
          tab == selected ? Key('entry_type_selected_${tab.name}') : null,
      onChanged: (tab) => _changeEntryType(
        tab.type,
        debt: tab == _ManualEntryTab.debt
            ? _debtDirection ?? _DebtDirection.borrow
            : null,
      ),
    );
  }

  void _changeEntryType(EntryType type, {_DebtDirection? debt}) {
    if (type == _type && debt == _debtDirection) return;
    final controller = VeriFinScope.of(context);
    final quick = _config.inlineNumberPad;
    final switchingAccounts =
        quick && (type == EntryType.transfer || _type == EntryType.transfer);
    setState(() {
      if (type != EntryType.expense && _discountAmount > 0) {
        _amount = _grossAmount;
        _discountAmount = 0;
      }
      _type = type;
      _debtDirection = debt;
      _typeTouched = true;
      final accounts = _availableAccounts(controller);
      if (switchingAccounts) {
        _accountId = type == EntryType.transfer
            ? ''
            : (_accountFor(accounts, _config.initialAccountId) ??
                          accounts.firstOrNull)
                      ?.id ??
                  '';
        _toAccountId = null;
        _fee = 0;
        _currencyTouched = false;
        _currencyCode =
            _accountFor(accounts, _accountId)?.currencyCode ??
            controller.activeBook.baseCurrencyCode;
      }
      if (quick && (accounts.isEmpty || switchingAccounts)) {
        _noAccount = type != EntryType.transfer && accounts.isEmpty;
      }
      if (type == EntryType.transfer) _currencyTouched = false;
      final categories = _categoriesForType(controller, type);
      final defaultCategory = _config.draftReviewHint == null
          ? categories.firstOrNull
          : categories
                .where((category) => category.isUncategorized)
                .firstOrNull;
      _categoryId = defaultCategory?.id ?? '';
      _collapsedCategoryId = quick ? _categoryId : null;
      _normalizeTransferAccounts(accounts);
      _refreshCurrencyAmounts(
        controller,
        accounts,
        forceAccount: true,
        forceToAccount: true,
        forceBase: true,
      );
    });
    _recomputeSuggestion();
  }

  Widget _buildManualTransfer(
    VeriFinController controller,
    List<Account> accounts,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final debt = _debtDirection;
    final from = _accountFor(accounts, _accountId);
    final to = _accountFor(accounts, _toAccountId);
    final crossCurrency =
        from != null && to != null && from.currencyCode != to.currencyCode;
    Widget accountRow({required bool outgoing}) {
      final account = outgoing ? from : to;
      final field = SelectField(
        key: Key(outgoing ? 'account_dropdown' : 'to_account_dropdown'),
        label: _manualTransferAccountLabel(l10n, outgoing: outgoing),
        labelOutside: true,
        value: account?.name ?? l10n.pleaseSelect,
        icon: outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
        leading: account == null
            ? null
            : AccountIconBox(
                iconCode: effectiveAccountIconCode(
                  account.iconCode,
                  account.name,
                ),
                size: 28,
              ),
        onTap: _manualTransferCandidates(accounts, outgoing: outgoing).isEmpty
            ? null
            : () => _pickManualTransferAccount(outgoing: outgoing),
      );
      return Row(
        spacing: 10,
        children: [
          Expanded(flex: 3, child: field),
          Expanded(
            flex: 2,
            child: account == null
                ? const SizedBox.shrink()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 3,
                    children: [
                      Text(
                        l10n.currentBalance,
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        formatUserMoney(
                          controller.accountBalance(account),
                          account.currencyCode,
                          forceUnit: crossCurrency,
                        ),
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      );
    }

    return VeriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (debt != null) ...[
            VeriSegmentedControl<_DebtDirection>(
              values: _DebtDirection.values,
              selected: debt,
              compact: true,
              labelOf: (direction) => direction == _DebtDirection.borrow
                  ? l10n.entryDebtBorrow
                  : l10n.entryDebtLend,
              onChanged: (direction) =>
                  _changeEntryType(EntryType.transfer, debt: direction),
            ),
            const SizedBox(height: 12),
          ],
          accountRow(outgoing: true),
          if (debt == null)
            Center(
              child: IconButton(
                tooltip: l10n.entrySwapTransferAccounts,
                icon: const Icon(Icons.swap_vert_rounded),
                onPressed: from == null || to == null
                    ? null
                    : () {
                        VeriHaptics.tap();
                        _setManualTransferAccounts(to.id, from.id);
                      },
              ),
            )
          else
            const SizedBox(height: 10),
          accountRow(outgoing: false),
          if (debt != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _creatingDebtAccount ? null : _addDebtAccount,
                icon: const Icon(Icons.add),
                label: Text(l10n.entryAddDebtAccount),
              ),
            ),
          if (debt == null
              ? accounts.length < 2
              : accounts.every((account) => account.type.isDebt))
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const AddAccountPage(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(l10n.accountAdd),
              ),
            ),
          ..._buildCurrencyAmountFields(controller, accounts),
        ],
      ),
    );
  }

  String _manualTransferAccountLabel(
    AppLocalizations l10n, {
    required bool outgoing,
  }) {
    final direction = _debtDirection;
    if (direction != null && outgoing == (direction == _DebtDirection.borrow)) {
      return direction.accountType.label(l10n);
    }
    return outgoing ? l10n.transferOutAccount : l10n.transferInAccount;
  }

  List<Account> _manualTransferCandidates(
    List<Account> accounts, {
    required bool outgoing,
  }) {
    final direction = _debtDirection;
    final otherId = outgoing ? _toAccountId : _accountId;
    final debtSide = outgoing == (direction == _DebtDirection.borrow);
    return [
      for (final account in accounts)
        if (account.id != otherId &&
            (direction == null ||
                (debtSide
                    ? account.type == direction.accountType
                    : !account.type.isDebt)))
          account,
    ];
  }

  Future<void> _pickManualTransferAccount({required bool outgoing}) async {
    final controller = VeriFinScope.of(context);
    final selected = await showAccountPickerSheet(
      context: context,
      title: _manualTransferAccountLabel(
        AppLocalizations.of(context),
        outgoing: outgoing,
      ),
      accounts: _manualTransferCandidates(
        _availableAccounts(controller),
        outgoing: outgoing,
      ),
      selectedId: outgoing ? _accountId : _toAccountId,
      balanceOf: controller.accountBalance,
    );
    if (!mounted || selected == null) return;
    _setManualTransferAccounts(
      outgoing ? selected.id : _accountId,
      outgoing ? _toAccountId : selected.id,
    );
  }

  void _setManualTransferAccounts(String fromId, String? toId) {
    final controller = VeriFinScope.of(context);
    setState(() {
      _accountId = fromId;
      _toAccountId = toId;
      _toAccountAmountTouched = false;
      _refreshCurrencyAmounts(
        controller,
        _availableAccounts(controller),
        forceToAccount: true,
      );
    });
  }

  Future<void> _addDebtAccount() async {
    final direction = _debtDirection;
    if (direction == null || _creatingDebtAccount) return;
    final controller = VeriFinScope.of(context);
    final l10n = AppLocalizations.of(context);
    final book = controller.activeBook;
    final outgoing = direction == _DebtDirection.borrow;
    setState(() => _creatingDebtAccount = true);
    try {
      final name = await showTextInputDialog(
        context: context,
        title: l10n.entryAddDebtAccount,
        label: l10n.entryDebtAccountName,
      );
      if (!mounted || name == null || controller.activeBook.id != book.id) {
        return;
      }
      final cashSide = _accountFor(
        _availableAccounts(controller),
        outgoing ? _toAccountId : _accountId,
      );
      final account = Account(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        bookId: book.id,
        name: name,
        type: direction.accountType,
        groupId: null,
        initialBalance: 0,
        iconCode: 'wallet',
        note: '',
        includeInAssets: true,
        hidden: false,
        currencyCode: cashSide?.currencyCode ?? book.baseCurrencyCode,
      );
      final added = await controller.addAccountDraft(account);
      if (added &&
          mounted &&
          _debtDirection == direction &&
          controller.activeBook.id == book.id) {
        VeriHaptics.commit();
        _setManualTransferAccounts(
          outgoing ? account.id : _accountId,
          outgoing ? _toAccountId : account.id,
        );
      }
    } finally {
      if (mounted) setState(() => _creatingDebtAccount = false);
    }
  }

  List<Widget> _buildCurrencyAmountFields(
    VeriFinController controller,
    List<Account> accounts,
  ) {
    final l10n = AppLocalizations.of(context);
    final code = _currencyCode ?? controller.activeBook.baseCurrencyCode;
    final baseCode = controller.activeBook.baseCurrencyCode;
    final account = _noAccount ? null : _accountFor(accounts, _accountId);
    final toAccount = _accountFor(accounts, _toAccountId);
    final fields = <Widget>[];
    if (_type == EntryType.transfer) {
      if (account != null &&
          toAccount != null &&
          toAccount.currencyCode != code) {
        fields.addAll(<Widget>[
          const SizedBox(height: 12),
          VeriCard(
            child: Column(
              children: <Widget>[
                CurrencyAmountField(
                  key: const Key('entry_to_account_amount'),
                  label: l10n.entryTransferInAmount,
                  currencyCode: toAccount.currencyCode,
                  amount: _toAccountAmount,
                  missingText: l10n.exchangeRateNotSet,
                  onTap: () => _editToAccountAmount(toAccount.currencyCode),
                ),
                DetailInfoRow(
                  label: l10n.entryRateLabel,
                  value: _toAccountAmount == null || _amount <= 0
                      ? l10n.exchangeRateNotSet
                      : l10n.entryRateEquation(
                          code,
                          formatRateValue(_toAccountAmount! / _amount),
                          toAccount.currencyCode,
                        ),
                  placeholder: _toAccountAmount == null,
                  onTap: () => _editDerivedRate(
                    sourceCode: code,
                    targetCode: toAccount.currencyCode,
                    transfer: true,
                  ),
                ),
              ],
            ),
          ),
        ]);
      }
    } else {
      final needsAccountAmount =
          account != null && account.currencyCode != code;
      final needsBaseAmount = code != baseCode;
      if (needsAccountAmount || needsBaseAmount) {
        fields.addAll(<Widget>[
          const SizedBox(height: 12),
          VeriCard(
            child: Column(
              children: <Widget>[
                if (needsAccountAmount)
                  CurrencyAmountField(
                    key: const Key('entry_account_amount'),
                    label: _type == EntryType.expense
                        ? l10n.entryAccountAmountExpense
                        : l10n.entryAccountAmountIncome,
                    currencyCode: account.currencyCode,
                    amount: _accountAmount,
                    missingText: l10n.exchangeRateNotSet,
                    onTap: () => _editAccountAmount(account.currencyCode),
                  ),
                if (needsBaseAmount)
                  CurrencyAmountField(
                    key: const Key('entry_base_amount'),
                    label: l10n.entryLedgerAmountLabel,
                    currencyCode: baseCode,
                    amount: _baseAmount,
                    missingText: l10n.exchangeRateNotSet,
                    onTap: () => _editBaseAmount(baseCode),
                  ),
                if (needsBaseAmount)
                  DetailInfoRow(
                    label: l10n.entryRateLabel,
                    value: _baseAmount == null || _amount <= 0
                        ? l10n.exchangeRateNotSet
                        : l10n.entryRateEquation(
                            code,
                            formatRateValue(_baseAmount! / _amount),
                            baseCode,
                          ),
                    placeholder: _baseAmount == null,
                    onTap: () => _editDerivedRate(
                      sourceCode: code,
                      targetCode: baseCode,
                      transfer: false,
                    ),
                  ),
                if (needsBaseAmount && _baseAmount != null)
                  CompactSwitchRow(
                    icon: Icons.bookmark_add_outlined,
                    title: Text(l10n.entryRememberRate),
                    subtitle: Text(l10n.entryRememberRateHint),
                    value: _rememberRate,
                    onChanged: (value) => setState(() => _rememberRate = value),
                  ),
              ],
            ),
          ),
        ]);
      }
    }
    if (_missingRateCodes.isNotEmpty) {
      fields.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            l10n.entryMissingRate(
              (_missingRateCodes.toList()..sort()).join(', '),
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: veriSemantic(context, veriWarning),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } else if (fields.isNotEmpty) {
      final rateDates = _usedRateDates;
      final stale = rateDates.any(
        (date) => calendarDaysBetween(date, _occurredAt) > 30,
      );
      fields.add(
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _conversionSource == ConversionSource.manual
                ? l10n.entryConversionSourceManual
                : rateDates.isEmpty
                ? l10n.entryConversionSourceRateTable
                : l10n.entryConversionRateTrace(
                    rateDates.map(currencyDateKey).join(' / '),
                    stale ? ' · ${l10n.exchangeRateStale}' : '',
                  ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
    }
    return fields;
  }

  Future<void> _pickCurrency() async {
    final controller = VeriFinScope.of(context);
    final selected = await showCurrencyPickerSheet(
      context: context,
      title: AppLocalizations.of(context).entryCurrencyPickTitle,
      selectedCode: _currencyCode,
      preferredCodes: <String>[
        controller.activeBook.baseCurrencyCode,
        for (final account in controller.accounts) account.currencyCode,
      ],
    );
    if (!mounted || selected == null || selected.code == _currencyCode) return;
    setState(() {
      _currencyCode = selected.code;
      _currencyTouched = true;
      final gross = normalizeCurrencyAmount(_grossAmount, selected.code);
      _discountAmount = _discountForGross(gross, selected.code);
      _amount = normalizeCurrencyAmount(gross - _discountAmount, selected.code);
      _accountAmountTouched = false;
      _baseAmountTouched = false;
      _rememberRate = false;
      _refreshCurrencyAmounts(
        controller,
        _availableAccounts(controller),
        forceAccount: true,
        forceBase: true,
      );
    });
  }

  Future<void> _editAmount() async {
    final code =
        _currencyCode ?? VeriFinScope.of(context).activeBook.baseCurrencyCode;
    final amount = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(context).entryAmountInputTitle(
        _discountAmount > 0
            ? AppLocalizations.of(context).entryGrossAmountLabel
            : AppLocalizations.of(context).entryOriginalAmountLabel,
        code,
      ),
      initialAmount: _grossAmount,
      maxFractionDigits: CurrencyCatalog.require(code).minorUnit,
    );

    if (!mounted || amount == null || amount <= 0) {
      return;
    }
    final discount = _discountForGross(amount, code);
    _setAmount(amount - discount, code, discountAmount: discount);
  }

  double _discountForGross(double gross, String code) =>
      normalizeCurrencyAmount(
        _discountAmount,
        code,
      ).clamp(0.0, maxEntryDiscount(gross, code));

  Future<void> _editDiscount(String code) async {
    final gross = _grossAmount;
    final discount = await showEntryDiscountSheet(
      context,
      grossAmount: gross,
      discountAmount: _discountAmount,
      currencyCode: code,
    );
    if (!mounted || discount == null) return;
    _setAmount(gross - discount, code, discountAmount: discount);
  }

  void _onInlineAmountChanged(double? amount) {
    final code =
        _currencyCode ?? VeriFinScope.of(context).activeBook.baseCurrencyCode;
    final gross = normalizeCurrencyAmount(amount ?? 0, code);
    if (gross == _inlineGrossAmount) return;
    setState(() => _inlineGrossAmount = gross);
    if (gross > _discountAmount) {
      _setAmount(gross - _discountAmount, code, debounceSuggestion: true);
    }
  }

  void _setAmount(
    double amount,
    String code, {
    double? discountAmount,
    bool debounceSuggestion = false,
  }) {
    setState(() {
      final previousAmount = _amount;
      _amount = normalizeCurrencyAmount(amount, code);
      if (discountAmount != null) _discountAmount = discountAmount;
      final controller = VeriFinScope.of(context);
      final accounts = _availableAccounts(controller);
      if (_conversionSource == ConversionSource.manual ||
          _conversionSource == ConversionSource.imported ||
          _conversionSource == ConversionSource.legacy) {
        final accountCode = _accountFor(accounts, _accountId)?.currencyCode;
        final toAccountCode = _accountFor(accounts, _toAccountId)?.currencyCode;
        if (accountCode != null) {
          _accountAmount = scaleDependentCurrencyAmount(
            dependentAmount: _accountAmount,
            previousOriginalAmount: previousAmount,
            nextOriginalAmount: _amount,
            targetCurrencyCode: accountCode,
          );
          _accountAmountTouched = true;
        }
        if (toAccountCode != null) {
          _toAccountAmount = scaleDependentCurrencyAmount(
            dependentAmount: _toAccountAmount,
            previousOriginalAmount: previousAmount,
            nextOriginalAmount: _amount,
            targetCurrencyCode: toAccountCode,
          );
          _toAccountAmountTouched = true;
        }
        _baseAmount = scaleDependentCurrencyAmount(
          dependentAmount: _baseAmount,
          previousOriginalAmount: previousAmount,
          nextOriginalAmount: _amount,
          targetCurrencyCode: controller.activeBook.baseCurrencyCode,
        );
        _baseAmountTouched = true;
        _refreshMissingRateCodes(controller, accounts);
      } else {
        _refreshCurrencyAmounts(controller, accounts);
      }
    });
    if (debounceSuggestion) {
      if (_autoSuggestEnabled) _scheduleSuggestion();
    } else {
      _recomputeSuggestion();
    }
  }

  Future<void> _editFee() async {
    final code =
        _currencyCode ?? VeriFinScope.of(context).activeBook.baseCurrencyCode;
    final fee = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(context).transferFeeTitle,
      initialAmount: _fee > 0 ? _fee : null,
      allowZero: true,
      maxFractionDigits: CurrencyCatalog.require(code).minorUnit,
    );
    if (!mounted || fee == null || fee < 0) {
      return;
    }
    setState(() => _fee = normalizeCurrencyAmount(fee, code));
  }

  Future<void> _editAccountAmount(String currencyCode) async {
    final l10n = AppLocalizations.of(context);
    final value = await showNumberPadSheet(
      context,
      title: l10n.entryAmountInputTitle(
        _type == EntryType.expense
            ? l10n.entryAccountAmountExpense
            : l10n.entryAccountAmountIncome,
        currencyCode,
      ),
      initialAmount: _accountAmount,
      maxFractionDigits: CurrencyCatalog.require(currencyCode).minorUnit,
    );
    if (!mounted || value == null || value <= 0) return;
    setState(() {
      _accountAmount = normalizeCurrencyAmount(value, currencyCode);
      _accountAmountTouched = true;
      if (currencyCode ==
          VeriFinScope.of(context).activeBook.baseCurrencyCode) {
        _baseAmount = _accountAmount;
        _baseAmountTouched = true;
      }
      _conversionSource = ConversionSource.manual;
      _refreshMissingRateCodes(
        VeriFinScope.of(context),
        _availableAccounts(VeriFinScope.of(context)),
      );
    });
  }

  Future<void> _editToAccountAmount(String currencyCode) async {
    final l10n = AppLocalizations.of(context);
    final value = await showNumberPadSheet(
      context,
      title: l10n.entryAmountInputTitle(
        l10n.entryTransferInAmount,
        currencyCode,
      ),
      initialAmount: _toAccountAmount,
      maxFractionDigits: CurrencyCatalog.require(currencyCode).minorUnit,
    );
    if (!mounted || value == null || value <= 0) return;
    setState(() {
      _toAccountAmount = normalizeCurrencyAmount(value, currencyCode);
      _toAccountAmountTouched = true;
      _conversionSource = ConversionSource.manual;
      _refreshMissingRateCodes(
        VeriFinScope.of(context),
        _availableAccounts(VeriFinScope.of(context)),
      );
    });
  }

  Future<void> _editBaseAmount(String currencyCode) async {
    final l10n = AppLocalizations.of(context);
    final value = await showNumberPadSheet(
      context,
      title: l10n.entryAmountInputTitle(
        l10n.entryLedgerAmountLabel,
        currencyCode,
      ),
      initialAmount: _baseAmount,
      maxFractionDigits: CurrencyCatalog.require(currencyCode).minorUnit,
    );
    if (!mounted || value == null || value <= 0) return;
    setState(() {
      _baseAmount = normalizeCurrencyAmount(value, currencyCode);
      _baseAmountTouched = true;
      final account = _accountFor(
        _availableAccounts(VeriFinScope.of(context)),
        _accountId,
      );
      if (!_noAccount && account?.currencyCode == currencyCode) {
        _accountAmount = _baseAmount;
        _accountAmountTouched = true;
      }
      _conversionSource = ConversionSource.manual;
      _refreshMissingRateCodes(
        VeriFinScope.of(context),
        _availableAccounts(VeriFinScope.of(context)),
      );
    });
  }

  Future<void> _editDerivedRate({
    required String sourceCode,
    required String targetCode,
    required bool transfer,
  }) async {
    final currentTarget = transfer ? _toAccountAmount : _baseAmount;
    final value = await showNumberPadSheet(
      context,
      title: AppLocalizations.of(
        context,
      ).entryRateEditTitle(sourceCode, targetCode),
      initialAmount: currentTarget == null || _amount <= 0
          ? null
          : currentTarget / _amount,
      maxFractionDigits: 10,
    );
    if (!mounted || value == null || value <= 0) return;
    setState(() {
      final targetAmount = normalizeCurrencyAmount(_amount * value, targetCode);
      if (transfer) {
        _toAccountAmount = targetAmount;
        _toAccountAmountTouched = true;
      } else {
        _baseAmount = targetAmount;
        _baseAmountTouched = true;
        final account = _accountFor(
          _availableAccounts(VeriFinScope.of(context)),
          _accountId,
        );
        if (!_noAccount && account?.currencyCode == targetCode) {
          _accountAmount = targetAmount;
          _accountAmountTouched = true;
        }
      }
      _conversionSource = ConversionSource.manual;
      _refreshMissingRateCodes(
        VeriFinScope.of(context),
        _availableAccounts(VeriFinScope.of(context)),
      );
    });
  }

  Future<void> _showAllCategories() async {
    final selected = await showCategoryPickerSheet(
      context,
      categories: _categoriesForType(VeriFinScope.of(context), _type),
      selectedId: _categoryId,
    );

    if (!mounted || selected == null) {
      return;
    }

    _selectCategory(selected);
  }

  void _selectCategory(String id) {
    setState(() {
      _categoryId = id;
      _collapsedCategoryId = null;
      _categoryTouched = true;
      _typeTouched = true;
    });
    _applyCategoryAccountSuggestion(VeriFinScope.of(context));
  }

  void _toggleCategoryBranch(String id, bool expanded) {
    VeriHaptics.tap();
    setState(() {
      _collapsedCategoryId = expanded ? id : null;
      _categoryTouched = true;
      _typeTouched = true;
    });
  }

  Future<void> _pickAccount(List<Account> accounts) async {
    final isTransfer = _type == EntryType.transfer;
    final selected = await showAccountPickerSheet(
      context: context,
      title: isTransfer
          ? AppLocalizations.of(context).pickTransferOutAccount
          : AppLocalizations.of(context).pickAccountTitle,
      accounts: accounts,
      selectedId: _noAccount ? '' : _accountId,
      balanceOf: VeriFinScope.of(context).accountBalance,
      // 转账两端都必须是具体账户，故转出账户不提供「无账户」。
      noneLabel: isTransfer
          ? null
          : AppLocalizations.of(context).noAccountLabel,
      noneHint: isTransfer ? null : AppLocalizations.of(context).noAccountHint,
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() {
      _accountTouched = true;
      if (selected.id.isEmpty) {
        _noAccount = true;
        if (!_currencyTouched) {
          _currencyCode = VeriFinScope.of(context).activeBook.baseCurrencyCode;
        }
      } else {
        _noAccount = false;
        _accountId = selected.id;
        if (!_currencyTouched || isTransfer) {
          _currencyCode = selected.currencyCode;
        }
      }
      _normalizeTransferAccounts(accounts);
      _accountAmountTouched = false;
      _toAccountAmountTouched = false;
      _baseAmountTouched = false;
      _rememberRate = false;
      _refreshCurrencyAmounts(
        VeriFinScope.of(context),
        accounts,
        forceAccount: true,
        forceToAccount: true,
        forceBase: true,
      );
    });
  }

  Future<void> _pickToAccount(List<Account> accounts) async {
    final selectableAccounts = accounts
        .where((account) => account.id != _accountId)
        .toList();
    if (selectableAccounts.isEmpty) {
      return;
    }
    final selected = await showAccountPickerSheet(
      context: context,
      title: AppLocalizations.of(context).pickTransferInAccount,
      accounts: selectableAccounts,
      selectedId: _toAccountId,
      balanceOf: VeriFinScope.of(context).accountBalance,
    );
    if (selected != null && mounted) {
      setState(() {
        _toAccountId = selected.id;
        _toAccountAmountTouched = false;
        _refreshCurrencyAmounts(
          VeriFinScope.of(context),
          accounts,
          forceToAccount: true,
        );
      });
    }
  }

  void _normalizeTransferAccounts(List<Account> accounts) {
    if (_type != EntryType.transfer) {
      _toAccountId = null;
      return;
    }
    if (_config.inlineNumberPad) {
      if (!_manualTransferCandidates(
        accounts,
        outgoing: true,
      ).any((account) => account.id == _accountId)) {
        _accountId = '';
      }
      if (!_manualTransferCandidates(
        accounts,
        outgoing: false,
      ).any((account) => account.id == _toAccountId)) {
        _toAccountId = null;
      }
      return;
    }
    if (accounts.length < 2) {
      _toAccountId = null;
      return;
    }
    if (_toAccountId == null ||
        _toAccountId == _accountId ||
        !accounts.any((account) => account.id == _toAccountId)) {
      _toAccountId = accounts
          .firstWhere((account) => account.id != _accountId)
          .id;
    }
  }

  bool _canSave(List<Account> accounts) {
    if (_grossAmount <= _discountAmount) return false;
    if (_type != EntryType.transfer) {
      // 无账户也可保存（只记金额）；否则需有可选账户。
      final hasAccountAmount =
          _noAccount || (_accountAmount != null && _accountAmount! > 0);
      return (_noAccount || accounts.isNotEmpty) &&
          hasAccountAmount &&
          _baseAmount != null &&
          _baseAmount! > 0;
    }
    return !_creatingDebtAccount &&
        _accountFor(accounts, _accountId) != null &&
        _accountFor(accounts, _toAccountId) != null &&
        _toAccountId != _accountId &&
        _accountAmount != null &&
        _accountAmount! > 0 &&
        _toAccountAmount != null &&
        _toAccountAmount! > 0;
  }

  /// 保存按钮禁用时缺什么。与 [_canSave] 同一判据，避免「按钮灰着却不说原因」。
  /// 返回 null 表示没有可解释的缺失（例如只是还没有任何改动）。
  String? _saveBlockReason(List<Account> accounts) {
    final l10n = AppLocalizations.of(context);
    if (_discountAmount > 0 && _grossAmount <= _discountAmount) {
      return l10n.entrySaveReasonAmount;
    }
    if (_type == EntryType.transfer) {
      if (_accountFor(accounts, _accountId) == null ||
          _accountFor(accounts, _toAccountId) == null ||
          _toAccountId == _accountId) {
        return l10n.entrySaveReasonTransferAccount;
      }
      if (_accountAmount == null ||
          _accountAmount! <= 0 ||
          _toAccountAmount == null ||
          _toAccountAmount! <= 0) {
        return l10n.entrySaveReasonTransferAmount;
      }
      return null;
    }
    if (!_noAccount && accounts.isEmpty) {
      return l10n.entrySaveReasonAccount;
    }
    if (!_noAccount && (_accountAmount == null || _accountAmount! <= 0)) {
      return l10n.entrySaveReasonAmount;
    }
    if (_baseAmount == null || _baseAmount! <= 0) {
      return l10n.entrySaveReasonAmount;
    }
    return null;
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );

    if (!mounted) return;

    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? _occurredAt.hour,
        time?.minute ?? _occurredAt.minute,
      );
      final controller = VeriFinScope.of(context);
      _refreshCurrencyAmounts(controller, _availableAccounts(controller));
    });
    _recomputeSuggestion();
  }

  Future<void> _addAttachment({required bool fromCamera}) async {
    final bytes = await pickAttachmentBytes(fromCamera: fromCamera);
    if (!mounted || bytes == null || bytes.isEmpty) return;
    final attachment = await VeriFinScope.of(
      context,
    ).stageNewAttachment(entryId: _entryId, bytes: bytes);
    if (!mounted) return;
    setState(() => _pendingAttachments.add(attachment));
  }

  Future<void> _pickTags() async {
    final platformTag = _config.suggestedPlatformTag;
    final result = await pickEntryTags(
      context: context,
      selectedIds: _tagIds,
      extraTags: [
        ...?_config.draftExtraTags,
        if (platformTag != null &&
            platformTag.id == AutoBillSuggestions.draftTagId)
          platformTag,
      ],
    );
    if (!mounted || result == null) {
      return;
    }
    setState(() {
      _tagIds = result;
      _tagsTouched = true;
    });
  }

  LedgerEntry _buildDraftEntry() {
    final original = _config.draftEntry;
    final noAccount = _type != EntryType.transfer && _noAccount;
    final controller = VeriFinScope.of(context);
    final accounts = _availableAccounts(controller);
    final code =
        _currencyCode ??
        _accountFor(accounts, _accountId)?.currencyCode ??
        controller.activeBook.baseCurrencyCode;
    final accountCode = _accountFor(accounts, _accountId)?.currencyCode;
    final toAccountCode = _accountFor(accounts, _toAccountId)?.currencyCode;
    return LedgerEntry(
      id: _entryId,
      bookId: original?.bookId ?? VeriFinScope.of(context).activeBook.id,
      type: _type,
      amount: normalizeCurrencyAmount(_amount, code),
      discountAmount: _type == EntryType.expense ? _discountAmount : 0,
      currencyCode: code,
      accountAmount: noAccount || accountCode == null
          ? null
          : normalizeCurrencyAmount(_accountAmount ?? _amount, accountCode),
      toAccountAmount: _type != EntryType.transfer || toAccountCode == null
          ? null
          : normalizeCurrencyAmount(_toAccountAmount ?? _amount, toAccountCode),
      baseAmount: _type == EntryType.transfer
          ? 0
          : normalizeCurrencyAmount(
              _baseAmount ?? _amount,
              controller.activeBook.baseCurrencyCode,
            ),
      conversionSource: _conversionSource,
      categoryId: _categoryId,
      accountId: noAccount ? '' : _accountId,
      toAccountId: _type == EntryType.transfer ? _toAccountId : null,
      note: _noteController.text.trim(),
      occurredAt: _occurredAt,
      tagIds: _tagIds
          .where((id) => id != AutoBillSuggestions.draftTagId)
          .toList(),
      fee: _type == EntryType.transfer && _debtDirection == null
          ? normalizeCurrencyAmount(_fee, code)
          : 0,
      reimbursable: _type == EntryType.expense && _reimbursable,
      excludedFromBudget:
          _statisticsScope.forType(_type) == EntryStatisticsScope.excludeBudget,
      excludedFromStatistics:
          _statisticsScope.forType(_type) ==
          EntryStatisticsScope.excludeStatistics,
      subscriptionMark: _type == EntryType.expense
          ? original?.subscriptionMark ?? SubscriptionMark.automatic
          : SubscriptionMark.automatic,
      refundedBaseAmount: original?.refundedBaseAmount ?? 0,
    );
  }

  void _captureInitialSnapshot() {
    _initialEntryDraft ??= _buildDraftEntry();
    _initialAttachmentIds ??= _pendingAttachments
        .map((attachment) => attachment.id)
        .toList(growable: false);
  }

  bool _sameDraft(LedgerEntry left, LedgerEntry right) =>
      left.type == right.type &&
      left.amount == right.amount &&
      left.discountAmount == right.discountAmount &&
      left.currencyCode == right.currencyCode &&
      left.accountAmount == right.accountAmount &&
      left.toAccountAmount == right.toAccountAmount &&
      left.baseAmount == right.baseAmount &&
      left.conversionSource == right.conversionSource &&
      left.categoryId == right.categoryId &&
      left.accountId == right.accountId &&
      left.toAccountId == right.toAccountId &&
      left.note == right.note &&
      left.occurredAt == right.occurredAt &&
      listEquals(left.tagIds, right.tagIds) &&
      left.fee == right.fee &&
      left.reimbursable == right.reimbursable &&
      left.statisticsScope == right.statisticsScope;

  bool get _isDirty {
    if (_saved) {
      return false;
    }
    // Reaching a new-entry page means the user already entered or supplied a
    // draft amount; the not-yet-created entity itself is pending work.
    if (!_isDraft) {
      return true;
    }
    final initial = _initialEntryDraft;
    final initialAttachments = _initialAttachmentIds;
    if (initial == null || initialAttachments == null) {
      return false;
    }
    return !_sameDraft(initial, _buildDraftEntry()) ||
        !listEquals(
          initialAttachments,
          _pendingAttachments
              .map((attachment) => attachment.id)
              .toList(growable: false),
        );
  }

  Future<void> _saveAndExit() async {
    if (await _save() && mounted) {
      _popWithResult(_savedResult);
    }
  }

  Future<void> _saveAndContinue() async {
    if (await _save() && mounted) {
      widget.startNext();
    }
  }

  /// 快速记账的返回语义是取消：删除本次新暂存的附件，不落任何账目。
  Future<void> _discardAndPop() async {
    if (_saving) return;
    final controller = VeriFinScope.of(context);
    final initialIds = (_initialAttachmentIds ?? const <String>[]).toSet();
    final stagedIds = _pendingAttachments
        .map((attachment) => attachment.id)
        .where((id) => !initialIds.contains(id))
        .toList(growable: false);
    if (stagedIds.isNotEmpty) {
      try {
        await controller.attachmentStore.deleteMany(stagedIds);
      } on Object catch (error, stackTrace) {
        controller.logger?.error(
          '删除未保存记账草稿的附件失败',
          source: 'entry_detail',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (!mounted) {
      return;
    }
    _popWithResult(null);
  }

  void _popWithResult(Object? result) {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  Future<bool> _save() async {
    if (_saving) {
      return false;
    }
    // 备注识别有 300ms 防抖：保存前必须落定，否则输入停顿不足时会把还没识别的
    // 默认类型/分类写进账目。
    if (_suggestDebounce != null) {
      _cancelPendingSuggestion();
      _recomputeSuggestion(suggestAccount: false);
    }
    final controller = VeriFinScope.of(context);
    final accounts = _availableAccounts(controller);
    if (!_canSave(accounts)) {
      VeriHaptics.emphasis();
      return false;
    }
    if (_config.draftReviewHint != null &&
        !_categoriesForType(
          controller,
          _type,
        ).any((c) => c.id == _categoryId)) {
      await _showAllCategories();
      return false;
    }
    final draft = _buildDraftEntry();
    // 草稿编辑模式：不落库，构造修改后的交易并回传给上层（如导入预览页）。
    if (_isDraft) {
      _saving = true;
      _savedResult = draft;
      _saved = true;
      return true;
    }
    if (draft.accountId.isNotEmpty &&
        !controller.accounts
            .where((account) => !account.hidden)
            .any((account) => account.id == draft.accountId)) {
      return false;
    }
    _saving = true;
    // 附件字节已在选择时落盘，这里只提交元数据；entryId 由 stageNewAttachment
    // 与 _buildDraftEntry 共用同一个 _entryId，保证引用一致。
    final attachments = List<Attachment>.of(_pendingAttachments);
    final result = await controller.saveEntryAggregateDraftResult(
      entry: draft,
      isNew: true,
      autoCaptureSourcePackage: _config.autoCaptureSourcePackage,
      suggestedTagLabel: _tagIds.contains(AutoBillSuggestions.draftTagId)
          ? _config.suggestedPlatformTag?.label
          : null,
      attachments: attachments,
      rememberRateCurrencyCode: _rememberRate ? draft.currencyCode : null,
      rememberRateToBase: _rememberRate
          ? draft.baseAmount / draft.amount
          : null,
      rememberRateEffectiveDate: _rememberRate ? draft.occurredAt : null,
    );
    if (!result.isSuccess) {
      _saving = false;
      // 保存失败/校验不通过：这一下是「没成」，用更实的触感区分于成功。
      VeriHaptics.emphasis();
      if (result is EntrySaveValidationFailure && mounted) {
        unawaited(
          VeriFeedbackHost.of(context).showMessage(
            message: entrySaveValidationMessage(
              AppLocalizations.of(context),
              result.code,
            ),
            tone: VeriFeedbackTone.warning,
            duration: VeriFeedbackDuration.long,
          ),
        );
      }
      return false;
    }
    _saved = true;
    VeriHaptics.commit();
    if (mounted) {
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: AppLocalizations.of(context).entrySavedSuccessfully,
          tone: VeriFeedbackTone.success,
          duration: VeriFeedbackDuration.short,
          dedupeKey: 'entry_saved',
        ),
      );
    }
    return true;
  }
}

/// 仅在诊断构建中记录备注单击后 Flutter 收到的焦点与键盘遮挡信号。
class _NoteKeyboardTiming with WidgetsBindingObserver {
  _NoteKeyboardTiming({
    required this.view,
    required this.focus,
    required this.report,
  });

  final FlutterView view;
  final FocusNode focus;
  final ValueChanged<String> report;
  final Stopwatch _clock = Stopwatch();
  Timer? _timer;
  double _bottom = 0;
  int? _focusMs;
  int? _firstInsetMs;
  int? _lastInsetMs;

  void start() {
    if (_clock.isRunning || view.viewInsets.bottom != 0) return;
    _bottom = 0;
    _focusMs = focus.hasFocus ? 0 : null;
    _firstInsetMs = null;
    _lastInsetMs = null;
    _clock
      ..reset()
      ..start();
    focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer(const Duration(seconds: 3), _finish);
  }

  void _onFocusChanged() {
    if (focus.hasFocus) {
      _focusMs ??= _clock.elapsedMilliseconds;
    } else {
      cancel();
    }
  }

  @override
  void didChangeMetrics() {
    final bottom = view.viewInsets.bottom;
    if (bottom == _bottom) return;
    if (bottom == 0) {
      cancel();
      return;
    }
    _bottom = bottom;
    _lastInsetMs = _clock.elapsedMilliseconds;
    _firstInsetMs ??= _lastInsetMs;
    _timer?.cancel();
    // 等遮挡值稳定后再写日志，耗时使用最后实际变化的时间。
    _timer = Timer(const Duration(milliseconds: 250), _finish);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cancel();
  }

  void _finish() {
    cancel();
    report(
      'focusMs=${_focusMs ?? "unobserved"} '
      'firstInsetMs=${_firstInsetMs ?? "unobserved"} '
      'lastInsetChangeMs=${_lastInsetMs ?? "unobserved"}',
    );
  }

  void cancel() {
    if (!_clock.isRunning) return;
    _clock.stop();
    _timer?.cancel();
    focus.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// AI 记账草稿的复核提示条：说明这是 AI 解析结果，并列出降级提示（分类/账户未匹配）。
class _AiReviewBanner extends StatelessWidget {
  const _AiReviewBanner({required this.draft, this.reviewHint});

  final AiEntryDraft draft;
  final String? reviewHint;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(veriRadiusMd),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome, size: 16, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reviewHint ?? l10n.aiEntryReviewHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          for (final warning in draft.warnings) ...<Widget>[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                aiDraftWarningLabel(l10n, warning),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 把解析降级提示码本地化为一句提示文案。
String aiDraftWarningLabel(AppLocalizations l10n, AiDraftWarning warning) {
  switch (warning) {
    case AiDraftWarning.categoryUnmatched:
      return l10n.aiWarningCategoryUnmatched;
    case AiDraftWarning.accountUnmatched:
      return l10n.aiWarningAccountUnmatched;
    case AiDraftWarning.currencyUnmatched:
      return l10n.aiWarningCurrencyUnmatched;
  }
}

class _EntryBottomSaveBar extends StatelessWidget {
  const _EntryBottomSaveBar({
    required this.enabled,
    required this.onPressed,
    this.reason,
  });

  final bool enabled;
  final VoidCallback onPressed;

  /// 保存按钮不可用时缺什么；为 null 表示没有可解释的缺失（例如只是没有改动）。
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: ColoredBox(
        key: const Key('entry_bottom_save_bar'),
        color: Colors.transparent,
        child: Padding(
          key: const Key('entry_bottom_save_padding'),
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (!enabled && reason != null) ...<Widget>[
                Text(
                  reason!,
                  key: const Key('entry_save_block_reason'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton(
                key: const Key('save_entry_button'),
                style: FilledButton.styleFrom(
                  // 保存栏不继承 FilledButton 的暗色禁用填充，保持与应用主色一致；
                  // 不可保存时用淡蓝（禁用态专属属性）表达，而非主题灰色。
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  disabledBackgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.38,
                  ),
                  disabledForegroundColor: theme.colorScheme.onPrimary
                      .withValues(alpha: 0.78),
                  minimumSize: const Size.fromHeight(50),
                  shape: const StadiumBorder(),
                  textStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: enabled ? onPressed : null,
                child: Text(AppLocalizations.of(context).commonSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryTypeSelector extends StatelessWidget {
  const _EntryTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final EntryType selected;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeriSegmentedControl<EntryType>(
      values: EntryType.userSelectable,
      selected: selected,
      semanticLabel: l10n.commonType,
      labelOf: (type) => type.label(l10n),
      // 支出/收入用语义色强调；转账用语义蓝——与本页下方的大金额、分类图标取同一支颜色。
      accentOf: (type) => switch (type) {
        EntryType.expense => veriSemantic(context, veriExpense),
        EntryType.income ||
        EntryType.refund => veriSemantic(context, veriIncome),
        EntryType.transfer => veriSemantic(context, veriBlue),
      },
      keyOf: (type) =>
          type == selected ? Key('entry_type_selected_${type.name}') : null,
      onChanged: onChanged,
    );
  }
}
