import 'dart:async';

import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/amount_format.dart' as amount_format;
import '../app/app_theme.dart';
import '../app/category_tree.dart';
import '../app/common_widgets.dart';
import '../app/currency_math.dart';
import '../app/model_lookup.dart';
import '../app/entry_sheets.dart';
import '../app/feedback.dart';
import '../app/haptics.dart';
import '../app/ledger_math.dart';
import '../app/models.dart';
import '../app/series_math.dart';
import '../app/recurring.dart' show addCalendarMonths;
import '../app/subscription_notes.dart';
import '../app/veri_fin_controller.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'ai_entry_sheet.dart';
import 'entry_detail_page.dart';
import 'sheets.dart';
import 'transaction_detail_page.dart';

export 'transaction_detail_page.dart';

part 'subscription_analysis.dart';

enum TransactionTimeFilter {
  all,
  year,
  quarter,
  month,
  week,
  last12Months,
  last30Days,
  last6Weeks,
  custom;

  String label(AppLocalizations l10n) {
    switch (this) {
      case TransactionTimeFilter.all:
        return l10n.timeAll;
      case TransactionTimeFilter.year:
        return l10n.timeYear;
      case TransactionTimeFilter.quarter:
        return l10n.timeQuarter;
      case TransactionTimeFilter.month:
        return l10n.thisMonth;
      case TransactionTimeFilter.week:
        return l10n.timeWeek;
      case TransactionTimeFilter.last12Months:
        return l10n.timeLast12Months;
      case TransactionTimeFilter.last30Days:
        return l10n.timeLast30Days;
      case TransactionTimeFilter.last6Weeks:
        return l10n.timeLast6Weeks;
      case TransactionTimeFilter.custom:
        return l10n.customTimeRange;
    }
  }
}

enum TransactionSortOrder {
  dateDesc,
  dateAsc,
  amountDesc,
  amountAsc;

  String label(AppLocalizations l10n) {
    switch (this) {
      case TransactionSortOrder.dateDesc:
        return l10n.sortDateDesc;
      case TransactionSortOrder.dateAsc:
        return l10n.sortDateAsc;
      case TransactionSortOrder.amountDesc:
        return l10n.sortAmountDesc;
      case TransactionSortOrder.amountAsc:
        return l10n.sortAmountAsc;
    }
  }
}

/// 报销状态筛选：全部 / 待报销（已标记且未完全冲抵）/ 已报销（已有回款冲抵）。
enum ReimbursementFilter {
  all,
  notReimbursable,
  pending,
  reimbursed;

  String label(AppLocalizations l10n) {
    switch (this) {
      case ReimbursementFilter.all:
        return l10n.reimbursementStatusAll;
      case ReimbursementFilter.notReimbursable:
        return l10n.reimbursementNotReimbursable;
      case ReimbursementFilter.pending:
        return l10n.badgeReimbursable;
      case ReimbursementFilter.reimbursed:
        return l10n.reimbursementReimbursed;
    }
  }

  bool matches(LedgerEntry entry, String baseCurrencyCode) {
    // 两个筛选互斥：一笔交易只会出现在其中一个结果里。部分到账的支出仍算「待报销」
    // （还有钱没回来），不会同时出现在「已到账」里。
    final awaiting =
        entry.reimbursable &&
        !isZeroCurrencyAmount(entry.netBaseAmount, baseCurrencyCode);
    switch (this) {
      case ReimbursementFilter.all:
        return true;
      case ReimbursementFilter.notReimbursable:
        // 从未标记待报销的交易：把囤券等标了待报销的排除掉，只看真实花销。
        return !entry.reimbursable;
      case ReimbursementFilter.pending:
        // 已标记待报销、且还有钱没回来（含只报回来一部分的）。
        return awaiting;
      case ReimbursementFilter.reimbursed:
        // 钱已经到账：标记后已全部冲抵的，或没标记但已经收到退款的。
        return !awaiting &&
            !isZeroCurrencyAmount(entry.refundedBaseAmount, baseCurrencyCode);
    }
  }
}

enum TransactionScopeFilter {
  all,
  inBudget,
  outOfBudget,
  excludedFromStatistics;

  String label(AppLocalizations l10n) => switch (this) {
    all => l10n.budgetScopeAll,
    inBudget => l10n.budgetScopeIncluded,
    outOfBudget => l10n.excludedFromBudget,
    excludedFromStatistics => l10n.excludedStatisticsFilter,
  };

  bool matches(LedgerEntry entry) => switch (this) {
    all => true,
    inBudget => entry.type != EntryType.expense || countsTowardBudget(entry),
    outOfBudget =>
      entry.type == EntryType.expense && !countsTowardBudget(entry),
    excludedFromStatistics => entry.excludedFromStatistics,
  };
}

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({
    super.key,
    this.initialDate,
    this.accountId,
    this.initialCategoryId,
    this.subscriptionsOnly = false,
    this.initialTimeFilter = TransactionTimeFilter.year,
    this.initialPeriodAnchor,
    this.title,
  });

  final DateTime? initialDate;
  final String? accountId;
  final String? initialCategoryId;
  final bool subscriptionsOnly;
  final TransactionTimeFilter initialTimeFilter;
  final DateTime? initialPeriodAnchor;
  final String? title;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  static const String _allFilterValue = '__all__';
  // 标签筛选的两个哨兵值（与真实标签 id 区分）：筛出「没有任何标签」/「至少有一个标签」的交易。
  static const String _noTagFilterValue = '__no_tag__';
  static const String _hasTagFilterValue = '__has_tag__';

  late TransactionTimeFilter _timeFilter = widget.initialTimeFilter;
  TransactionSortOrder _sortOrder = TransactionSortOrder.dateDesc;
  late DateTime _periodAnchor = widget.initialPeriodAnchor ?? DateTime.now();
  late DateTime _visibleDate = widget.initialDate ?? DateTime.now();
  late bool _dateMode = widget.initialDate != null;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  // 搜索防抖：每敲一个字符都重跑「过滤 + 排序 + 分组」在几千笔账本上会明显卡顿，
  // 等用户停下来再算一次。
  static const Duration _searchDebounce = Duration(milliseconds: 220);
  Timer? _queryDebounceTimer;
  String? _selectedAccountId;
  String? _selectedCategoryId;
  String? _selectedTagId;
  ReimbursementFilter _reimbursementFilter = ReimbursementFilter.all;
  TransactionScopeFilter _scopeFilter = TransactionScopeFilter.all;
  bool _selectionMode = false;
  bool _subscriptionFiltersOpen = false;
  final Set<String> _selectedIds = <String>{};

  // 分页显示：列表只渲染前 _visibleCount 条交易，快滑到底部前
  // （extentAfter 阈值）预加载下一批，避免一次性构建成百上千个 widget。汇总/
  // 计数/全选仍基于完整派生列表，不受分页影响。
  static const int _pageBatchSize = 30;

  // 快滑到底部前多少像素就预取下一批：给一屏左右的余量，避免用户滑到底再等。
  static const double _prefetchExtent = 800;
  int _visibleCount = _pageBatchSize;

  // 派生管线（过滤→排序→去退款→分组→汇总）缓存：签名不变则复用，避免无关
  // notifyListeners 触发整条 O(n log n) 重算。签名覆盖全部输入——三个模型列表
  // 引用（经派生缓存后变化即换实例）、金额格式开关、locale、以及所有筛选字段。
  List<Object?>? _deriveSignature;
  // 上一轮派生用的筛选条件。只有它变化才把分页打回第一批；后台数据变化（周期
  // 补记、改设置等引发的 notify）只重算，保留用户已经翻到的位置。
  List<Object?>? _deriveFilterSignature;
  List<LedgerEntry> _derivedEntries = const <LedgerEntry>[];
  List<DateEntryGroup> _derivedGroups = const <DateEntryGroup>[];
  double _derivedExpense = 0;
  double _derivedIncome = 0;
  double _dailySubscriptionCost = 0;
  final List<({LedgerEntry entry, SubscriptionMark period, double daily})>
  _activeSubscriptions = [];
  DateTimeRange? _customRange;
  Timer? _midnightTimer;
  int _expenseCount = 0;
  final Map<SubscriptionMark, (int, double)> _subscriptionTotals = {};

  @override
  void initState() {
    super.initState();
    if (widget.subscriptionsOnly) _scheduleDailyRefresh();
    _selectedAccountId = widget.accountId;
    _selectedCategoryId = widget.initialCategoryId;
  }

  void _scheduleDailyRefresh() {
    final now = DateTime.now();
    _midnightTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now),
      () {
        if (!mounted) return;
        setState(() {});
        _scheduleDailyRefresh();
      },
    );
  }

  /// 筛选条件：用户改了「看什么」，就视为重新浏览。
  List<Object?> _filterSignature() => <Object?>[
    widget.accountId,
    widget.subscriptionsOnly,
    _dateMode,
    _visibleDate,
    _timeFilter,
    if (_timeFilter == TransactionTimeFilter.custom) _customRange,
    _periodAnchor,
    _query,
    _selectedAccountId,
    _selectedCategoryId,
    _selectedTagId,
    _reimbursementFilter,
    _scopeFilter,
    _sortOrder,
  ];

  /// 按签名判断派生结果是否失效；失效才重跑过滤/排序/分组/汇总。
  void _ensureDerived(VeriFinController controller, BuildContext context) {
    final today = dateOnly(DateTime.now());
    final filterSignature = _filterSignature();
    final signature = <Object?>[
      controller.entries,
      controller.accounts,
      controller.categories,
      controller.tags,
      amount_format.currencyFractionStyle,
      Localizations.localeOf(context),
      if (widget.subscriptionsOnly) today,
      ...filterSignature,
    ];
    if (_deriveSignature != null && listEquals(_deriveSignature, signature)) {
      return;
    }
    final filterChanged =
        _deriveFilterSignature == null ||
        !listEquals(_deriveFilterSignature, filterSignature);
    _deriveSignature = signature;
    _deriveFilterSignature = filterSignature;
    final entries = _sortedEntries(
      _filteredEntries(controller.entries),
      controller,
    ).where((entry) => entry.type != EntryType.refund).toList();
    _expenseCount = entries
        .where(
          (entry) =>
              entry.type == EntryType.expense && !entry.excludedFromStatistics,
        )
        .length;
    _subscriptionTotals.clear();
    _dailySubscriptionCost = 0;
    _activeSubscriptions.clear();
    if (widget.subscriptionsOnly) {
      for (final entry in entries) {
        final period = subscriptionPeriod(entry)!;
        final daily = subscriptionDailyCost(entry, period, today);
        if (daily > 0) {
          _dailySubscriptionCost += daily;
          _activeSubscriptions.add((
            entry: entry,
            period: period,
            daily: daily,
          ));
        }
        final (count, amount) = _subscriptionTotals[period] ?? (0, 0.0);
        _subscriptionTotals[period] = (count + 1, amount + entry.netBaseAmount);
      }
    }
    _derivedEntries = entries;
    _derivedExpense = sumByType(entries, EntryType.expense);
    _derivedIncome = sumByType(entries, EntryType.income);
    _derivedGroups = groupEntriesByDate(entries);
    // 只有筛选条件变化才回到第一批（输入变化视为「重新浏览」）；账目数据在后台
    // 变化（周期补记、汇率或偏好更新引发的通知）时保留当前深度，不把用户正在
    // 看的位置顶回顶部。
    if (filterChanged) {
      _visibleCount = _pageBatchSize;
    }
  }

  /// 分页精确到交易，同一天导入大量流水时也只构建当前批次。
  List<DateEntryGroup> _visibleGroups() {
    final result = <DateEntryGroup>[];
    var remaining = _visibleCount;
    for (final group in _derivedGroups) {
      if (remaining <= 0) break;
      final rows = group.entries;
      result.add(
        rows.length <= remaining
            ? group
            : DateEntryGroup(
                date: group.date,
                entries: rows.sublist(0, remaining),
              ),
      );
      remaining -= rows.length;
    }
    return result;
  }

  /// 滚动到接近底部（预取余量内）且仍有未展示分组时，追加下一批。数据全在内存，
  /// 追加只是多渲染几组、无异步等待，故「加载」瞬时完成、不会卡在底部。
  bool _onScroll(ScrollNotification notification, bool hasMore) {
    if (hasMore && notification.metrics.extentAfter < _prefetchExtent) {
      setState(() => _visibleCount += _pageBatchSize);
    }
    return false;
  }

  @override
  void dispose() {
    _midnightTimer?.cancel();
    _queryDebounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _queryDebounceTimer?.cancel();
    _queryDebounceTimer = Timer(_searchDebounce, () {
      if (!mounted) {
        return;
      }
      setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    // 派生管线（过滤→排序→去退款→分组→汇总）带签名缓存：输入不变则复用，避免
    // 无关 notify 触发整条重算。退款条目在原支出上管理，不进列表（净额已体现在支出行）。
    _ensureDerived(controller, context);
    final entries = _derivedEntries;
    final expense = _derivedExpense;
    final income = _derivedIncome;
    final l10n = AppLocalizations.of(context);
    final expenseSummary =
        widget.subscriptionsOnly ||
        (_selectedCategoryId != null &&
            controller.categoryById(_selectedCategoryId!).type ==
                EntryType.expense);
    final visibleGroups = _visibleGroups();
    final hasMore = _visibleCount < entries.length;
    // 悬浮记账按钮（56 + 下边距 16）会压住列表末行金额，底部按需额外避让；多选时
    // 按钮让位给底部批量栏，只保留原来的内容留白。
    final double listBottomPadding = _selectionMode || widget.subscriptionsOnly
        ? 28
        : 100;

    return Scaffold(
      // 记账入口沿用首页快捷记账的 fabActionMode 语义；多选时让位给底部批量栏。
      floatingActionButton: _selectionMode || widget.subscriptionsOnly
          ? null
          : FloatingActionButton(
              key: const Key('transactions_quick_entry_fab'),
              tooltip: AppLocalizations.of(context).quickEntry,
              shape: const CircleBorder(),
              onPressed: () => _startQuickEntry(controller),
              child: const Icon(Icons.add_rounded),
            ),
      bottomNavigationBar: _selectionMode
          ? _BatchActionBar(
              count: _selectedIds.length,
              onSelectAll: () => setState(() {
                _selectedIds
                  ..clear()
                  ..addAll(entries.map((e) => e.id));
              }),
              onDelete: _selectedIds.isEmpty ? null : _batchDelete,
              onChangeCategory: _selectedIds.isEmpty
                  ? null
                  : () => _batchChangeCategory(controller),
              onChangeAccount: _selectedIds.isEmpty
                  ? null
                  : () => _batchChangeAccount(controller),
            )
          : null,
      body: SafeArea(
        child: VeriPage(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) => _onScroll(notification, hasMore),
            child: CustomScrollView(
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        VeriHeader(
                          title: _selectionMode
                              ? AppLocalizations.of(
                                  context,
                                ).selectedCount(_selectedIds.length)
                              : (widget.subscriptionsOnly
                                    ? AppLocalizations.of(
                                        context,
                                      ).subscriptionExpenses
                                    : widget.title ??
                                          (_dateMode
                                              ? AppLocalizations.of(
                                                  context,
                                                ).dayEntriesTitle
                                              : AppLocalizations.of(
                                                  context,
                                                ).entriesListTitle)),
                          subtitle: _selectionMode
                              ? null
                              : (_dateMode
                                    ? currencyUnitSubtitle(
                                        AppLocalizations.of(context),
                                        l10n.dateYearMonthDay(_visibleDate),
                                        controller.activeBook.baseCurrencyCode,
                                      )
                                    : currencyUnitSubtitle(
                                        AppLocalizations.of(context),
                                        null,
                                        controller.activeBook.baseCurrencyCode,
                                      )),
                          showBack: true,
                          actions: <Widget>[
                            if (widget.subscriptionsOnly)
                              HeaderTextAction(
                                label: l10n.selectSubscriptionOrders,
                                onPressed: () =>
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute<void>(
                                        builder: (_) => _SubscriptionPicker(
                                          bookId: controller.activeBook.id,
                                        ),
                                      ),
                                    ),
                              )
                            else if (_selectionMode)
                              HeaderAction(
                                icon: Icons.close,
                                tooltip: AppLocalizations.of(
                                  context,
                                ).exitMultiSelect,
                                onPressed: () {
                                  VeriHaptics.tap();
                                  setState(() {
                                    _selectionMode = false;
                                    _selectedIds.clear();
                                  });
                                },
                              )
                            else if (entries.isNotEmpty)
                              HeaderAction(
                                icon: Icons.checklist,
                                tooltip: l10n.multiSelect,
                                onPressed: () {
                                  VeriHaptics.tap();
                                  setState(() => _selectionMode = true);
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_dateMode)
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: _buildTimeFilterAnchor(
                                  builder: (openMenu) => _DateFilterBar(
                                    date: _visibleDate,
                                    onPrevious: () => setState(() {
                                      _visibleDate = addCalendarDays(
                                        _visibleDate,
                                        -1,
                                      );
                                    }),
                                    onNext: () => setState(() {
                                      _visibleDate = addCalendarDays(
                                        _visibleDate,
                                        1,
                                      );
                                    }),
                                    onTap: openMenu,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _buildSortOrderAnchor(),
                            ],
                          )
                        else
                          Row(
                            children: <Widget>[
                              Flexible(
                                child: _buildTimeFilterAnchor(
                                  builder: (openMenu) => _TransactionFilterBar(
                                    label: _periodLabel(),
                                    showNavigation:
                                        _timeFilter !=
                                            TransactionTimeFilter.all &&
                                        _timeFilter !=
                                            TransactionTimeFilter.custom,
                                    onPrevious: () => _movePeriod(-1),
                                    onNext: () => _movePeriod(1),
                                    onTap: openMenu,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              _buildSortOrderAnchor(),
                              if (widget.subscriptionsOnly) ...[
                                const Spacer(),
                                IconButton(
                                  tooltip: l10n.subscriptionFilters,
                                  isSelected: _subscriptionFiltersOpen,
                                  onPressed: () => setState(
                                    () => _subscriptionFiltersOpen =
                                        !_subscriptionFiltersOpen,
                                  ),
                                  icon: const Icon(Icons.tune_rounded),
                                ),
                              ],
                            ],
                          ),
                        if (!widget.subscriptionsOnly ||
                            _subscriptionFiltersOpen) ...[
                          const SizedBox(height: 10),
                          _TransactionSearchFilters(
                            controller: _searchController,
                            accountLabel: _accountFilterLabel(controller),
                            categoryLabel: _categoryFilterLabel(controller),
                            accountLocked: widget.accountId != null,
                            onChanged: _onSearchChanged,
                            onPickAccount: widget.accountId == null
                                ? () => _pickAccountFilter(controller)
                                : null,
                            onPickCategory: () =>
                                _pickCategoryFilter(controller),
                            tagLabel: _tagFilterLabel(controller),
                            tagSelected: _selectedTagId != null,
                            onPickTag: controller.tags.isEmpty
                                ? null
                                : () => _pickTagFilter(controller),
                            onClear: _hasSecondaryFilters
                                ? () {
                                    _queryDebounceTimer?.cancel();
                                    setState(() {
                                      _searchController.clear();
                                      _query = '';
                                      if (widget.accountId == null) {
                                        _selectedAccountId = null;
                                      }
                                      _selectedCategoryId = null;
                                      _selectedTagId = null;
                                      _reimbursementFilter =
                                          ReimbursementFilter.all;
                                      _scopeFilter = TransactionScopeFilter.all;
                                      // 按天视图与时间档同属时间维度，清空必须一起复位。
                                      _dateMode = false;
                                      _timeFilter = widget.initialTimeFilter;
                                      _customRange = null;
                                      _periodAnchor =
                                          widget.initialPeriodAnchor ??
                                          DateTime.now();
                                    });
                                  }
                                : null,
                            reimbursementFilter: _reimbursementFilter,
                            onSelectReimbursement: (value) =>
                                setState(() => _reimbursementFilter = value),
                            scopeFilter: _scopeFilter,
                            onSelectScope: (value) =>
                                setState(() => _scopeFilter = value),
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (!widget.subscriptionsOnly)
                          Text(
                            AppLocalizations.of(
                              context,
                            ).entriesCountFull(entries.length),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.28),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        const SizedBox(height: 12),
                        VeriCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 16,
                          ),
                          child: Row(
                            children: <Widget>[
                              SummaryMetric(
                                label: AppLocalizations.of(
                                  context,
                                ).entryTypeExpense,
                                value: formatExpenseAmount(expense),
                                color: isZeroAmount(expense)
                                    ? Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: 0.48)
                                    : veriSemantic(context, veriExpense),
                              ),
                              if (expenseSummary)
                                SummaryMetric(
                                  onTap: widget.subscriptionsOnly
                                      ? () => _showDailySubscriptions(
                                          context,
                                          controller,
                                          _activeSubscriptions,
                                          _dailySubscriptionCost,
                                        )
                                      : null,
                                  label: widget.subscriptionsOnly
                                      ? l10n.activeDailySubscriptionCost
                                      : l10n.averagePerExpense,
                                  value: formatAmount(
                                    widget.subscriptionsOnly
                                        ? _dailySubscriptionCost
                                        : _expenseCount == 0
                                        ? 0
                                        : expense / _expenseCount,
                                  ),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                )
                              else ...[
                                SummaryMetric(
                                  label: AppLocalizations.of(
                                    context,
                                  ).entryTypeIncome,
                                  value: formatAmount(income),
                                  color: isZeroAmount(income)
                                      ? Theme.of(context).colorScheme.onSurface
                                            .withValues(alpha: 0.48)
                                      : veriSemantic(context, veriIncome),
                                ),
                                SummaryMetric(
                                  label: AppLocalizations.of(context).netLabel,
                                  value: formatSignedAmount(income - expense),
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (widget.subscriptionsOnly && entries.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SubscriptionBreakdown(
                            totals: _subscriptionTotals,
                            currency: controller.activeBook.baseCurrencyCode,
                          ),
                        ],
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, listBottomPadding),
                    sliver: SliverToBoxAdapter(
                      child: VeriCard(
                        child: EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: _hasSecondaryFilters
                              ? AppLocalizations.of(context).noMatchTitle
                              : AppLocalizations.of(context).noEntriesTitle,
                          description: _hasSecondaryFilters
                              ? AppLocalizations.of(context).noMatchDesc
                              : widget.subscriptionsOnly
                              ? AppLocalizations.of(
                                  context,
                                ).subscriptionEmptyHint
                              : AppLocalizations.of(context).emptyEntriesDesc,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(14, 0, 14, listBottomPadding),
                    sliver: SliverList.builder(
                      itemCount: visibleGroups.length,
                      itemBuilder: (context, index) {
                        final group = visibleGroups[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            DateGroupHeader(
                              entries: _derivedGroups[index].entries,
                              date: group.date,
                              baseCurrencyCode:
                                  controller.activeBook.baseCurrencyCode,
                            ),
                            const SizedBox(height: 8),
                            if (widget.subscriptionsOnly)
                              VeriCard(
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: Column(
                                    children: [
                                      for (final entry in group.entries)
                                        _SubscriptionRow(entry: entry),
                                    ],
                                  ),
                                ),
                              )
                            else
                              TransactionListCard(
                                entries: group.entries,
                                accounts: controller.accounts,
                                categories: controller.categories,
                                tags: controller.tags,
                                baseCurrencyCode:
                                    controller.activeBook.baseCurrencyCode,
                                // 逐笔结余是可选显示；关着时连计算都不做。
                                balanceAfterEntry: controller.showRunningBalance
                                    ? controller.balanceAfterEntry
                                    : null,
                                selectionMode: _selectionMode,
                                selectedIds: _selectedIds,
                                onEntryTap: (entry) {
                                  if (_selectionMode) {
                                    _toggleSelected(entry.id);
                                  } else {
                                    openEntryDetail(context, entry);
                                  }
                                },
                                onEntryLongPress: (entry) {
                                  setState(() {
                                    _selectionMode = true;
                                    _selectedIds.add(entry.id);
                                  });
                                },
                              ),
                            const SizedBox(height: 18),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<LedgerEntry> _filteredEntries(List<LedgerEntry> entries) {
    final scopedEntries = widget.accountId == null
        ? entries
        : entries
              .where((entry) => entryTouchesAccount(entry, widget.accountId!))
              .toList();

    List<LedgerEntry> filtered;
    if (_dateMode) {
      filtered = scopedEntries
          .where((entry) => DateUtils.isSameDay(entry.occurredAt, _visibleDate))
          .toList();
    } else {
      final period = _activePeriod();
      if (period == null) {
        filtered = scopedEntries;
      } else {
        final endExclusive = addCalendarDays(period.end, 1);
        filtered = scopedEntries
            .where(
              (entry) =>
                  !entry.occurredAt.isBefore(period.start) &&
                  entry.occurredAt.isBefore(endExclusive),
            )
            .toList();
      }
    }

    final controller = VeriFinScope.of(context);
    final normalizedQuery = _query.toLowerCase();
    // 选中分类时把「分类 + 全部子孙」算一次；放在每条交易的谓词里会把分类树
    // 重算 N 遍。
    final selectedCategoryIds = _selectedCategoryId == null
        ? null
        : <String>{
            _selectedCategoryId!,
            ...descendantIds(controller.categories, _selectedCategoryId!),
          };
    return filtered
        .where(
          (entry) =>
              _matchesSecondaryFilters(entry, controller, selectedCategoryIds),
        )
        .where(
          (entry) => normalizedQuery.isEmpty
              ? true
              : _matchesQuery(entry, controller, normalizedQuery),
        )
        .toList();
  }

  // 默认期间属于页面入口；仅用户切换的档位或期间需要清空。
  bool get _hasSecondaryFilters =>
      _query.isNotEmpty ||
      (widget.accountId == null && _selectedAccountId != null) ||
      _selectedCategoryId != null ||
      _selectedTagId != null ||
      _reimbursementFilter != ReimbursementFilter.all ||
      _scopeFilter != TransactionScopeFilter.all ||
      (!_dateMode &&
          (_timeFilter != widget.initialTimeFilter ||
              (_timeFilter != TransactionTimeFilter.all &&
                  !DateUtils.isSameDay(
                    _periodAnchor,
                    widget.initialPeriodAnchor ?? DateTime.now(),
                  ))));

  bool _matchesSecondaryFilters(
    LedgerEntry entry,
    VeriFinController controller,
    Set<String>? selectedCategoryIds,
  ) {
    if (widget.subscriptionsOnly && subscriptionPeriod(entry) == null) {
      return false;
    }
    if (_selectedAccountId != null &&
        !entryTouchesAccount(entry, _selectedAccountId!)) {
      return false;
    }
    // 选中某分类时，连同它的所有子分类一起筛出（与看板统计「归总到顶级」口径
    // 一致：选大类=大类及其全部子类的交易）。
    if (selectedCategoryIds != null) {
      if (!selectedCategoryIds.contains(entry.categoryId)) {
        return false;
      }
    }
    final tagFilter = _selectedTagId;
    if (tagFilter == _noTagFilterValue) {
      if (entry.tagIds.isNotEmpty) {
        return false;
      }
    } else if (tagFilter == _hasTagFilterValue) {
      if (entry.tagIds.isEmpty) {
        return false;
      }
    } else if (tagFilter != null && !entry.tagIds.contains(tagFilter)) {
      return false;
    }
    // 报销状态：全部 / 待报销（未完全冲抵）/ 已报销（已有回款冲抵）。
    if (!_reimbursementFilter.matches(
      entry,
      controller.activeBook.baseCurrencyCode,
    )) {
      return false;
    }
    return _scopeFilter.matches(entry);
  }

  bool _matchesQuery(
    LedgerEntry entry,
    VeriFinController controller,
    String query,
  ) {
    final category = controller.categoryById(entry.categoryId);
    final noneLabel = AppLocalizations.of(context).noAccountLabel;
    final searchable = <String>[
      entry.note,
      category.label,
      accountDisplayName(controller.accounts, entry.accountId, noneLabel),
      if (entry.toAccountId != null && entry.toAccountId!.isNotEmpty)
        accountById(controller.accounts, entry.toAccountId!).name,
      entry.type.label(AppLocalizations.of(context)),
      formatCurrencyNumber(entry.amount, entry.currencyCode),
      formatSignedAmount(signedAmount(entry)),
      for (final id in entry.tagIds)
        if (controller.tagById(id) case final Tag tag) tag.label,
      // 报销状态也纳入搜索：可用「待报销」「已退」「已报销」关键词检索；
      // 「退款」是这类交易在应用里的叫法，只有确实关联退款的交易才加进去，
      // 否则每条交易都会命中。
      if (entry.refundedAmount > 0) ...<String>[
        AppLocalizations.of(context).badgeRefunded,
        AppLocalizations.of(context).reimbursementReimbursed,
        AppLocalizations.of(context).entryTypeRefund,
      ] else if (entry.reimbursable) ...<String>[
        AppLocalizations.of(context).badgeReimbursable,
        AppLocalizations.of(context).entryTypeRefund,
      ],
      // 预算标记也纳入搜索：可用「不计入预算」关键词快速找回这类交易。
      if (entry.statisticsScope != EntryStatisticsScope.normal)
        entry.statisticsScope.label(AppLocalizations.of(context)),
    ].join(' ').toLowerCase();
    return searchable.contains(query);
  }

  List<LedgerEntry> _sortedEntries(
    List<LedgerEntry> entries,
    VeriFinController controller,
  ) {
    final sorted = entries;
    switch (_sortOrder) {
      case TransactionSortOrder.dateDesc:
        return entries;
      case TransactionSortOrder.dateAsc:
        sorted.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      case TransactionSortOrder.amountDesc:
        sorted.sort(
          (a, b) => _compareBookAmounts(a, b, controller, descending: true),
        );
      case TransactionSortOrder.amountAsc:
        sorted.sort(
          (a, b) => _compareBookAmounts(a, b, controller, descending: false),
        );
    }
    return sorted;
  }

  int _compareBookAmounts(
    LedgerEntry a,
    LedgerEntry b,
    VeriFinController controller, {
    required bool descending,
  }) {
    double? valueOf(LedgerEntry entry) => comparableEntryAmountInBase(
      entry: entry,
      accounts: controller.accounts,
      baseCurrencyCode: controller.activeBook.baseCurrencyCode,
      rates: controller.exchangeRates,
    );

    final aValue = valueOf(a);
    final bValue = valueOf(b);
    if (aValue == null && bValue != null) return 1;
    if (aValue != null && bValue == null) return -1;
    final byAmount = aValue == null || bValue == null
        ? 0
        : (descending ? bValue.compareTo(aValue) : aValue.compareTo(bValue));
    if (byAmount != 0) return byAmount;
    final byDate = b.occurredAt.compareTo(a.occurredAt);
    return byDate != 0 ? byDate : b.id.compareTo(a.id);
  }

  Widget _buildTimeFilterAnchor({
    required Widget Function(VoidCallback openMenu) builder,
  }) {
    final l10n = AppLocalizations.of(context);
    return AnchoredMenuChoice<TransactionTimeFilter>(
      values: _selectedCategoryId == null && widget.initialCategoryId == null
          ? TransactionTimeFilter.values
          : const [
              TransactionTimeFilter.all,
              TransactionTimeFilter.week,
              TransactionTimeFilter.month,
              TransactionTimeFilter.year,
              TransactionTimeFilter.custom,
            ],
      selected: _timeFilter,
      idOf: (value) => 'transaction_time_${value.name}',
      labelOf: (value) => value.label(l10n),
      onSelected: (value) async {
        if (value == TransactionTimeFilter.custom) {
          final now = dateOnly(DateTime.now());
          final selected = await showDateRangePicker(
            context: context,
            firstDate: DateTime(1900),
            lastDate: DateTime(9999, 12, 31),
            initialDateRange:
                _customRange ??
                DateTimeRange(start: DateTime(now.year, now.month), end: now),
            helpText: l10n.customTimeRange,
          );
          if (!mounted || selected == null) return;
          setState(() {
            _dateMode = false;
            _timeFilter = value;
            _customRange = selected;
          });
          return;
        }
        setState(() {
          _dateMode = false;
          _timeFilter = value;
          _periodAnchor = DateTime.now();
        });
      },
      semanticLabel: l10n.filterTimeTitle,
      builder: (context, openMenu, menuOpen) => builder(openMenu),
    );
  }

  Widget _buildSortOrderAnchor() {
    final l10n = AppLocalizations.of(context);
    return AnchoredMenuChoice<TransactionSortOrder>(
      values: TransactionSortOrder.values,
      selected: _sortOrder,
      idOf: (value) => 'transaction_sort_${value.name}',
      labelOf: (value) => value.label(l10n),
      iconOf: (value) => switch (value) {
        TransactionSortOrder.dateDesc => Icons.arrow_downward_rounded,
        TransactionSortOrder.dateAsc => Icons.arrow_upward_rounded,
        TransactionSortOrder.amountDesc => Icons.trending_down_rounded,
        TransactionSortOrder.amountAsc => Icons.trending_up_rounded,
      },
      onSelected: (value) => setState(() => _sortOrder = value),
      semanticLabel: l10n.sortTitle,
      builder: (context, openMenu, menuOpen) =>
          FilterPill(label: _sortOrder.label(l10n), onTap: openMenu),
    );
  }

  Future<void> _pickAccountFilter(VeriFinController controller) async {
    // 与记账 / 编辑用同一个账户选择器（带图标+余额、按资产视图模式分区），顶部加「全部」项。
    final selected = await showAccountPickerSheet(
      context: context,
      title: AppLocalizations.of(context).filterAccountTitle,
      accounts: controller.accounts,
      selectedId: _selectedAccountId ?? accountPickerAllId,
      balanceOf: controller.accountBalance,
      allLabel: AppLocalizations.of(context).allAccounts,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedAccountId = selected.id == accountPickerAllId
            ? null
            : selected.id;
      });
    }
  }

  Future<void> _pickCategoryFilter(VeriFinController controller) async {
    // 与记账 / 编辑交易用同一个分类选择器（带图标、可折叠层级树），顶部加「全部」项。
    final selected = await showCategoryPickerSheet(
      context,
      categories: controller.categories,
      selectedId: _selectedCategoryId ?? categoryPickerAll,
      title: AppLocalizations.of(context).filterCategoryTitle,
      allLabel: AppLocalizations.of(context).categoryAll,
      initiallyCollapseRoots: true,
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedCategoryId = selected == categoryPickerAll ? null : selected;
      });
    }
  }

  String _accountFilterLabel(VeriFinController controller) {
    final accountId = _selectedAccountId;
    if (accountId == null) {
      return AppLocalizations.of(context).allAccounts;
    }
    return accountById(controller.accounts, accountId).name;
  }

  String _categoryFilterLabel(VeriFinController controller) {
    final categoryId = _selectedCategoryId;
    if (categoryId == null) {
      return AppLocalizations.of(context).categoryAll;
    }
    return controller.categoryById(categoryId).label;
  }

  Future<void> _pickTagFilter(VeriFinController controller) async {
    final l10n = AppLocalizations.of(context);
    final values = <String>[
      _allFilterValue,
      _noTagFilterValue,
      _hasTagFilterValue,
      for (final tag in controller.tags) tag.id,
    ];
    final selected = await showOptionSheet<String>(
      context: context,
      title: l10n.filterTagTitle,
      values: values,
      selected: _selectedTagId ?? _allFilterValue,
      sectionOf: (value) =>
          (value == _allFilterValue ||
              value == _noTagFilterValue ||
              value == _hasTagFilterValue)
          ? l10n.tagFilterQuickSection
          : l10n.tagFilterTagSection,
      labelOf: (value) => switch (value) {
        _allFilterValue => l10n.allTags,
        _noTagFilterValue => l10n.noTagFilter,
        _hasTagFilterValue => l10n.hasTagFilter,
        _ => controller.tagById(value)?.label ?? l10n.unknownTag,
      },
    );
    if (selected != null) {
      setState(() {
        _selectedTagId = selected == _allFilterValue ? null : selected;
      });
    }
  }

  String _tagFilterLabel(VeriFinController controller) {
    final l10n = AppLocalizations.of(context);
    final tagId = _selectedTagId;
    switch (tagId) {
      case null:
        return l10n.tagLabel;
      case _noTagFilterValue:
        return l10n.noTagFilter;
      case _hasTagFilterValue:
        return l10n.hasTagFilter;
      default:
        return controller.tagById(tagId)?.label ?? l10n.tagLabel;
    }
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  /// 快捷记账使用与首页相同的编辑页，默认账户来自当前账本。
  Future<void> _startQuickEntry(VeriFinController controller) async {
    if (controller.fabActionMode == FabActionMode.ai) {
      await startAiEntry(context);
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => EntryDetailPage.manual(
          initialAccountId: controller.defaultAccountId,
        ),
      ),
    );
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    final confirmed = await showConfirmDialog(
      context,
      title: AppLocalizations.of(context).deleteEntriesTitle(count),
      message: AppLocalizations.of(context).deleteEntriesMessage,
      confirmLabel: AppLocalizations.of(context).commonDelete,
      destructive: true,
    );
    if (!mounted || !confirmed) {
      return;
    }
    final deleted = await VeriFinScope.of(
      context,
    ).deleteEntries(Set<String>.of(_selectedIds));
    if (deleted) {
      VeriHaptics.emphasis();
    }
    if (mounted && deleted) {
      _exitSelection();
    }
  }

  Future<void> _batchChangeCategory(VeriFinController controller) async {
    // 与记账 / 编辑用同一个多级分类选择器（带图标、按 支出/收入/转账 分区）；批量赋值
    // 传全部分类、不带「全部」项，选中即落到该具体分类。
    final selected = await showCategoryPickerSheet(
      context,
      categories: controller.categories,
      selectedId: '',
      title: AppLocalizations.of(context).changeCategoryTitle,
    );
    if (selected == null || !mounted) {
      return;
    }
    final changed = controller.setEntriesCategory(
      Set<String>.of(_selectedIds),
      selected,
    );
    if (changed > 0) {
      VeriHaptics.commit();
    }
    if (mounted) {
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: AppLocalizations.of(context).changedCategoryCount(changed),
          tone: VeriFeedbackTone.success,
        ),
      );
    }
    _exitSelection();
  }

  Future<void> _batchChangeAccount(VeriFinController controller) async {
    final candidates = controller.batchAccountChangeCandidates(
      Set<String>.of(_selectedIds),
    );
    if (candidates.isEmpty) {
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: AppLocalizations.of(context).batchAccountChangeUnsafe,
          tone: VeriFeedbackTone.warning,
          duration: VeriFeedbackDuration.long,
        ),
      );
      return;
    }
    // 与记账 / 编辑用同一个账户选择器（带图标、余额，按资产视图模式分区）。
    final selected = await showAccountPickerSheet(
      context: context,
      title: AppLocalizations.of(context).changeAccountTitle,
      accounts: candidates,
      selectedId: null,
      balanceOf: controller.accountBalance,
    );
    if (selected == null || !mounted) {
      return;
    }
    final result = await controller.setEntriesAccount(
      Set<String>.of(_selectedIds),
      selected.id,
    );
    if (!mounted) {
      return;
    }
    if (result.status == BatchAccountChangeStatus.unsafeSelection ||
        result.status == BatchAccountChangeStatus.invalidTarget) {
      VeriHaptics.emphasis();
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: AppLocalizations.of(context).batchAccountChangeUnsafe,
          tone: VeriFeedbackTone.warning,
          duration: VeriFeedbackDuration.long,
        ),
      );
      return;
    }
    if (result.isSuccess) {
      VeriHaptics.commit();
      unawaited(
        VeriFeedbackHost.of(context).showMessage(
          message: AppLocalizations.of(
            context,
          ).changedAccountCount(result.changed),
          tone: VeriFeedbackTone.success,
        ),
      );
      _exitSelection();
    }
  }

  DateWindow? _activePeriod() {
    final anchor = dateOnly(_periodAnchor);
    switch (_timeFilter) {
      case TransactionTimeFilter.custom:
        final range = _customRange;
        return range == null
            ? null
            : DateWindow(start: range.start, end: range.end);
      case TransactionTimeFilter.all:
        return null;
      case TransactionTimeFilter.year:
        return DateWindow(
          start: DateTime(anchor.year),
          end: DateTime(anchor.year, 12, 31),
        );
      case TransactionTimeFilter.quarter:
        final quarter = ((anchor.month - 1) ~/ 3) + 1;
        final startMonth = (quarter - 1) * 3 + 1;
        return DateWindow(
          start: DateTime(anchor.year, startMonth),
          end: DateTime(anchor.year, startMonth + 3, 0),
        );
      case TransactionTimeFilter.month:
        return DateWindow(
          start: DateTime(anchor.year, anchor.month),
          end: DateTime(anchor.year, anchor.month + 1, 0),
        );
      case TransactionTimeFilter.week:
        final start = addCalendarDays(anchor, -(anchor.weekday - 1));
        return DateWindow(start: start, end: addCalendarDays(start, 6));
      case TransactionTimeFilter.last12Months:
        return DateWindow(
          start: DateTime(anchor.year, anchor.month - 11),
          end: DateTime(anchor.year, anchor.month + 1, 0),
        );
      case TransactionTimeFilter.last30Days:
        return DateWindow(start: addCalendarDays(anchor, -29), end: anchor);
      case TransactionTimeFilter.last6Weeks:
        final weekEnd = addCalendarDays(anchor, 7 - anchor.weekday);
        return DateWindow(start: addCalendarDays(weekEnd, -41), end: weekEnd);
    }
  }

  String _periodLabel() {
    final now = DateTime.now();
    final period = _activePeriod();
    if (period == null) {
      return _timeFilter.label(AppLocalizations.of(context));
    }
    final anchor = _periodAnchor;
    switch (_timeFilter) {
      case TransactionTimeFilter.custom:
        final localizations = MaterialLocalizations.of(context);
        return '${localizations.formatCompactDate(period.start)} – ${localizations.formatCompactDate(period.end)}';
      case TransactionTimeFilter.all:
        return _timeFilter.label(AppLocalizations.of(context));
      case TransactionTimeFilter.year:
        return anchor.year == now.year
            ? AppLocalizations.of(context).timeYear
            : AppLocalizations.of(context).yearLabel(anchor.year);
      case TransactionTimeFilter.quarter:
        final quarter = ((anchor.month - 1) ~/ 3) + 1;
        return anchor.year == now.year
            ? AppLocalizations.of(context).quarterLabel(quarter)
            : '${twoDigitYear(anchor.year)}.Q$quarter';
      case TransactionTimeFilter.month:
        return anchor.year == now.year
            ? AppLocalizations.of(context).monthNumber(anchor.month)
            : '${twoDigitYear(anchor.year)}.${anchor.month.toString().padLeft(2, '0')}';
      case TransactionTimeFilter.week:
        final week = isoWeekNumber(anchor);
        final year = isoWeekYear(anchor);
        return year == now.year
            ? AppLocalizations.of(context).weekNumber(week)
            : AppLocalizations.of(context).yearWeek(year, week);
      case TransactionTimeFilter.last12Months:
      case TransactionTimeFilter.last30Days:
        return '${AppLocalizations.of(context).dateMonthDay(period.start)}-${AppLocalizations.of(context).dateMonthDay(period.end)}';
      case TransactionTimeFilter.last6Weeks:
        return '${twoDigitYear(isoWeekYear(period.start))}.${isoWeekNumber(period.start).toString().padLeft(2, '0')}-${twoDigitYear(isoWeekYear(period.end))}.${isoWeekNumber(period.end).toString().padLeft(2, '0')}';
    }
  }

  void _movePeriod(int direction) {
    setState(() {
      switch (_timeFilter) {
        case TransactionTimeFilter.all:
        case TransactionTimeFilter.custom:
          break;
        case TransactionTimeFilter.year:
          _periodAnchor = DateTime(
            _periodAnchor.year + direction,
            _periodAnchor.month,
          );
        case TransactionTimeFilter.quarter:
          _periodAnchor = DateTime(
            _periodAnchor.year,
            _periodAnchor.month + direction * 3,
          );
        case TransactionTimeFilter.month:
          _periodAnchor = DateTime(
            _periodAnchor.year,
            _periodAnchor.month + direction,
          );
        case TransactionTimeFilter.week:
          _periodAnchor = addCalendarDays(_periodAnchor, direction * 7);
        case TransactionTimeFilter.last12Months:
          _periodAnchor = DateTime(
            _periodAnchor.year,
            _periodAnchor.month + direction * 12,
          );
        case TransactionTimeFilter.last30Days:
          _periodAnchor = addCalendarDays(_periodAnchor, direction * 30);
        case TransactionTimeFilter.last6Weeks:
          _periodAnchor = addCalendarDays(_periodAnchor, direction * 42);
      }
    });
  }
}

class _TransactionFilterBar extends StatelessWidget {
  const _TransactionFilterBar({
    required this.label,
    required this.showNavigation,
    required this.onPrevious,
    required this.onNext,
    required this.onTap,
  });

  final String label;
  final bool showNavigation;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!showNavigation) {
      return FilterPill(label: label, onTap: onTap, flexibleLabel: true);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: AppLocalizations.of(context).prevRange,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left, size: 18),
        ),
        FilterPill(label: label, onTap: onTap),
        IconButton(
          tooltip: AppLocalizations.of(context).nextRange,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, size: 18),
        ),
      ],
    );
  }
}

class _TransactionSearchFilters extends StatelessWidget {
  const _TransactionSearchFilters({
    required this.controller,
    required this.accountLabel,
    required this.categoryLabel,
    required this.accountLocked,
    required this.onChanged,
    required this.onPickCategory,
    this.onPickAccount,
    this.tagLabel,
    this.tagSelected = false,
    this.onPickTag,
    required this.reimbursementFilter,
    required this.onSelectReimbursement,
    required this.scopeFilter,
    required this.onSelectScope,
    this.onClear,
  });

  final TextEditingController controller;
  final String accountLabel;
  final String categoryLabel;
  final bool accountLocked;
  final ValueChanged<String> onChanged;
  final VoidCallback? onPickAccount;
  final VoidCallback onPickCategory;

  /// 标签筛选：仅当存在标签时由上层传入 [onPickTag]，否则不展示该胶囊。
  final String? tagLabel;
  final bool tagSelected;
  final VoidCallback? onPickTag;
  final ReimbursementFilter reimbursementFilter;
  final ValueChanged<ReimbursementFilter> onSelectReimbursement;
  final TransactionScopeFilter scopeFilter;
  final ValueChanged<TransactionScopeFilter> onSelectScope;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = VeriStyleTokens.of(context);
    final l10n = AppLocalizations.of(context);

    return VeriCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        children: <Widget>[
          TextField(
            key: const Key('transaction_search_field'),
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              hintText: AppLocalizations.of(context).searchHint,
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: onClear == null
                  ? null
                  : IconButton(
                      tooltip: AppLocalizations.of(context).clearFilters,
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 18),
                    ),
              filled: true,
              fillColor: tokens.surfaceAltColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.innerRadius),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.innerRadius),
                borderSide: tokens.pillHasBorder
                    ? BorderSide(color: tokens.borderColor)
                    : BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(tokens.innerRadius),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilterPill(
                  label: accountLabel,
                  icon: accountLocked
                      ? Icons.lock_outline
                      : Icons.account_balance_wallet_outlined,
                  onTap: onPickAccount,
                  showChevron: !accountLocked,
                ),
                FilterPill(
                  label: categoryLabel,
                  icon: Icons.category_outlined,
                  onTap: onPickCategory,
                ),
                if (onPickTag != null)
                  FilterPill(
                    label: tagLabel ?? AppLocalizations.of(context).tagLabel,
                    icon: tagSelected ? Icons.label : Icons.label_outline,
                    onTap: onPickTag,
                  ),
                AnchoredMenuChoice<ReimbursementFilter>(
                  values: ReimbursementFilter.values,
                  selected: reimbursementFilter,
                  idOf: (value) => 'reimbursement_${value.name}',
                  labelOf: (value) => value.label(AppLocalizations.of(context)),
                  onSelected: onSelectReimbursement,
                  semanticLabel: AppLocalizations.of(
                    context,
                  ).reimbursementFilterTitle,
                  builder: (context, openMenu, menuOpen) => FilterPill(
                    label: reimbursementFilter == ReimbursementFilter.all
                        ? AppLocalizations.of(context).reimbursementFilterName
                        : reimbursementFilter.label(
                            AppLocalizations.of(context),
                          ),
                    icon: reimbursementFilter != ReimbursementFilter.all
                        ? Icons.check_circle
                        : Icons.receipt_long_outlined,
                    onTap: openMenu,
                  ),
                ),
                AnchoredMenuChoice<TransactionScopeFilter>(
                  values: TransactionScopeFilter.values,
                  selected: scopeFilter,
                  idOf: (value) => 'transaction_scope_${value.name}',
                  labelOf: (value) => value.label(l10n),
                  onSelected: onSelectScope,
                  semanticLabel: l10n.transactionScopeFilterName,
                  builder: (context, openMenu, menuOpen) => FilterPill(
                    label: scopeFilter == TransactionScopeFilter.all
                        ? l10n.transactionScopeFilterName
                        : scopeFilter.label(l10n),
                    icon: scopeFilter != TransactionScopeFilter.all
                        ? Icons.check_circle
                        : Icons.bar_chart_outlined,
                    onTap: openMenu,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateFilterBar extends StatelessWidget {
  const _DateFilterBar({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onTap,
  });

  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          tooltip: AppLocalizations.of(context).prevDay,
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Flexible(
          child: FilterPill(
            label: AppLocalizations.of(context).dateYearMonthDay(date),
            onTap: onTap,
            flexibleLabel: true,
          ),
        ),
        IconButton(
          tooltip: AppLocalizations.of(context).nextDay,
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.count,
    required this.onSelectAll,
    required this.onDelete,
    required this.onChangeCategory,
    required this.onChangeAccount,
  });

  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback? onDelete;
  final VoidCallback? onChangeCategory;
  final VoidCallback? onChangeAccount;

  @override
  Widget build(BuildContext context) {
    final tokens = VeriStyleTokens.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.raisedSurfaceColor,
          border: Border(top: BorderSide(color: tokens.borderColor)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            _BatchAction(
              icon: Icons.select_all,
              label: AppLocalizations.of(context).selectAll,
              onTap: onSelectAll,
            ),
            _BatchAction(
              icon: Icons.category_outlined,
              label: AppLocalizations.of(context).changeCategoryShort,
              onTap: onChangeCategory,
            ),
            _BatchAction(
              icon: Icons.account_balance_wallet_outlined,
              label: AppLocalizations.of(context).changeAccountShort,
              onTap: onChangeAccount,
            ),
            _BatchAction(
              icon: Icons.delete_outline,
              label: AppLocalizations.of(context).commonDelete,
              destructive: true,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final base = destructive
        ? veriSemantic(context, veriExpense)
        : Theme.of(context).colorScheme.onSurface;
    final color = enabled ? base : base.withValues(alpha: 0.3);
    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              VeriHaptics.tap();
              onTap!();
            },
      borderRadius: BorderRadius.circular(veriRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
