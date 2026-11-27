import 'dart:async';
import 'dart:math' as math;

import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../app/chart_painters.dart';
import '../app/common_widgets.dart';
import '../app/home_metrics.dart';
import '../app/ledger_math.dart';
import '../app/models.dart';
import '../app/root_navigation.dart';
import '../app/series_math.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'budget_pages.dart';
import 'home_metrics_settings_page.dart';
import 'panel_settings_page.dart';
import 'recurring_page.dart';
import 'transactions_pages.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Timer? _midnightTimer;
  DateTime? _lastBuiltDay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDate();
  }

  void _refreshDate() {
    final now = DateTime.now();
    final today = dateOnly(now);
    if (_lastBuiltDay != null && _lastBuiltDay != today) {
      setState(() {});
    }
    _midnightTimer?.cancel();
    _midnightTimer = Timer(
      addCalendarDays(today, 1).difference(now),
      _refreshDate,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _refreshDate();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _midnightTimer?.cancel();
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = VeriFinScope.of(context);
    final entries = controller.entries;
    final now = DateTime.now();
    _lastBuiltDay = dateOnly(now);
    final trendWindow = lastSevenDaysWindowFor(now);
    final trendEntries = entriesInWindow(entries, trendWindow);
    final trendConfig = controller.homeTrendConfig;
    final accountValuation = controller.accountBalancesInBase(date: now);
    final metricContext = HomeMetricContext(
      entries: entries,
      accounts: controller.accounts,
      balanceOf: controller.accountBalance,
      balanceInBaseOf: (account) =>
          accountValuation.amountsByAccountId[account.id],
      now: now,
    );
    final trendChartValues = trendSeriesValues(
      trendConfig.series,
      trendEntries,
      trendWindow,
    );
    // 退款条目在原支出上管理，不单独进时间线（净额已体现在支出行）。
    final recentEntries = entries
        .where((e) => e.type != EntryType.refund)
        .take(5)
        .toList();
    final todayExpenses = entries
        .where(
          (entry) =>
              entry.type == EntryType.expense &&
              !entry.excludedFromStatistics &&
              DateUtils.isSameDay(entry.occurredAt, now),
        )
        .toList();
    final todayExpenseTotal = sumByType(todayExpenses, EntryType.expense);
    // 预算面板按预算周期取数（键月 + 周期窗口）；首页其余统计仍按自然月。
    final budgetKeyMonth = controller.budgetKeyMonthFor(now);
    final budgetWindow = controller.budgetWindow(budgetKeyMonth);
    final budgetEntries = entriesInWindow(entries, budgetWindow);
    // 预算面板按预算口径取数：排除标记「不计入预算」的交易。
    final budgetExpense = budgetExpenseTotal(budgetEntries);
    final monthlyBudget = controller.monthlyBudget(budgetKeyMonth);
    final categoryBudgetSnapshots = computeCategoryBudgetSnapshots(
      controller: controller,
      month: budgetKeyMonth,
      monthEntries: budgetEntries,
    );
    final categoryBudgetRisk = topCategoryBudgetRisk(categoryBudgetSnapshots);
    final panelIds = controller.enabledPanelIds(PanelPageKind.home);
    final recurringMissingByRule = controller.dueRecurringMissingRates(now);
    final recurringMissingCodes =
        recurringMissingByRule.values.expand((codes) => codes).toSet().toList()
          ..sort();

    // 面板 id 对应的卡片,渲染顺序与开关由面板管理页配置。
    Widget panelFor(String id) {
      switch (id) {
        case 'trend':
          return HomeTrendPanel(
            window: trendWindow,
            config: trendConfig,
            metricContext: metricContext,
            chartValues: trendChartValues,
            todayExpenses: todayExpenses,
            todayExpenseTotal: todayExpenseTotal,
            accounts: controller.accounts,
            categories: controller.categories,
            tags: controller.tags,
            baseCurrencyCode: controller.activeBook.baseCurrencyCode,
            onEntryTap: (entry) => openEntryDetail(context, entry),
            onTodayExpenseTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => TransactionsPage(initialDate: now),
                ),
              );
            },
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => IncomeExpenseStatsPage(
                    initialType: trendConfig.series == HomeTrendSeries.income
                        ? EntryType.income
                        : EntryType.expense,
                  ),
                ),
              );
            },
          );
        case 'budget':
          return BudgetPanel(
            month: budgetKeyMonth,
            window: budgetWindow,
            expense: budgetExpense,
            budget: monthlyBudget,
            categoryRisk: categoryBudgetRisk,
            currencyCode: controller.activeBook.baseCurrencyCode,
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) =>
                      BudgetOverviewPage(initialMonth: budgetKeyMonth),
                ),
              );
            },
          );
        case 'calendar':
          return CalendarPreview(
            entries: entries,
            currencyCode: controller.activeBook.baseCurrencyCode,
            accounts: controller.accounts,
            categories: controller.categories,
            tags: controller.tags,
            recentEntries: recentEntries,
            onEntryTap: (entry) => openEntryDetail(context, entry),
            onViewAllTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const TransactionsPage(),
                ),
              );
            },
            onDayTap: (date) {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => TransactionsPage(initialDate: date),
                ),
              );
            },
          );
        default:
          return const SizedBox.shrink();
      }
    }

    return VeriPage(
      child: ListView(
        padding: veriRootPageListPadding(context),
        children: <Widget>[
          PageHeader(
            prominent: true,
            title: AppLocalizations.of(context).tabHome,
            subtitle: currencyUnitSubtitle(
              AppLocalizations.of(context),
              AppLocalizations.of(context).yearMonth(now),
              controller.activeBook.baseCurrencyCode,
            ),
            trailing: HeaderAction(
              icon: Icons.receipt_long_rounded,
              tooltip: AppLocalizations.of(context).allTransactions,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const TransactionsPage(),
                ),
              ),
            ),
          ),
          if (recurringMissingByRule.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            VeriCard(
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const RecurringRulesPage(),
                ),
              ),
              child: Row(
                children: <Widget>[
                  VeriIconBox(
                    icon: Icons.event_repeat_rounded,
                    color: veriSemantic(context, veriWarning),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          AppLocalizations.of(context).homeRecurringRatePending(
                            recurringMissingByRule.length,
                          ),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          AppLocalizations.of(
                            context,
                          ).homeRecurringRatePendingDesc(
                            recurringMissingCodes.join(', '),
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.58),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          ],
          for (final id in panelIds) ...<Widget>[
            const SizedBox(height: 14),
            panelFor(id),
          ],
          const SizedBox(height: 12),
          const PanelSettingsEntry(kind: PanelPageKind.home),
          // 首页右下角有记账按钮（54 + 16 间距），末尾再让出这段高度，
          // 滚到底时最后一条交易/入口不会被按钮压住。
          const SizedBox(height: 70),
        ],
      ),
    );
  }
}

class SectionHeaderAction extends StatelessWidget {
  const SectionHeaderAction({
    super.key,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(veriRadiusSm),
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (trailing.isNotEmpty) ...<Widget>[
              Text(
                trailing,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.52),
                ),
              ),
              const SizedBox(width: 6),
            ],
            const _CircleArrow(),
          ],
        ),
      ),
    );
  }
}

/// 走势曲线按所选序列取逐日值（结余=逐日收入−支出）。
List<double> trendSeriesValues(
  HomeTrendSeries series,
  List<LedgerEntry> entries,
  DateWindow window,
) {
  switch (series) {
    case HomeTrendSeries.expense:
      return valuesForTypeInWindow(entries, window, EntryType.expense);
    case HomeTrendSeries.income:
      return valuesForTypeInWindow(entries, window, EntryType.income);
    case HomeTrendSeries.net:
      final income = valuesForTypeInWindow(entries, window, EntryType.income);
      final expense = valuesForTypeInWindow(entries, window, EntryType.expense);
      return <double>[
        for (var i = 0; i < income.length; i++) income[i] - expense[i],
      ];
  }
}

Color _trendSeriesColor(HomeTrendSeries series, Brightness brightness) {
  switch (series) {
    case HomeTrendSeries.expense:
      return veriSemanticFor(brightness, veriExpense);
    case HomeTrendSeries.income:
      return veriSemanticFor(brightness, veriIncome);
    case HomeTrendSeries.net:
      return veriSemanticFor(brightness, veriBlue);
  }
}

/// 走势气泡里单日数值的文案：支出显示为负（`-x`）、收入为正（`+x`）、结余带正负号。
String _trendSeriesValueText(HomeTrendSeries series, double value) {
  switch (series) {
    case HomeTrendSeries.expense:
      return formatExpenseAmount(value);
    case HomeTrendSeries.income:
      return formatSignedAmount(value);
    case HomeTrendSeries.net:
      return formatSignedAmount(value);
  }
}

class HomeTrendPanel extends StatelessWidget {
  const HomeTrendPanel({
    super.key,
    required this.window,
    required this.config,
    required this.metricContext,
    required this.chartValues,
    required this.onTap,
    this.todayExpenses = const <LedgerEntry>[],
    this.todayExpenseTotal = 0,
    this.accounts = const <Account>[],
    this.categories = const <Category>[],
    this.tags = const <Tag>[],
    this.baseCurrencyCode = 'CNY',
    this.onEntryTap,
    this.onTodayExpenseTap,
  });

  final DateWindow window;
  final HomeTrendConfig config;
  final HomeMetricContext metricContext;
  final List<double> chartValues;
  final VoidCallback onTap;
  final List<LedgerEntry> todayExpenses;
  final double todayExpenseTotal;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Tag> tags;
  final String baseCurrencyCode;
  final ValueChanged<LedgerEntry>? onEntryTap;
  final VoidCallback? onTodayExpenseTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = textColor.withValues(alpha: 0.68);

    final showBig = config.isSlotVisible(0);
    final showPill = config.isSlotVisible(1);
    final cardSlots = [
      for (var slot = 2; slot <= 4; slot++)
        if (config.isSlotVisible(slot)) slot,
    ];
    final bigValue = showBig
        ? computeHomeMetric(config.big, metricContext)
        : 0.0;
    final bigColor = homeMetricColor(
      config.big,
      bigValue,
      mutedColor,
      Theme.of(context).brightness,
      inkColor: textColor,
    );
    final pillValue = showPill
        ? computeHomeMetric(config.pill, metricContext)
        : 0.0;
    final pillColor = homeMetricColor(
      config.pill,
      pillValue,
      mutedColor,
      Theme.of(context).brightness,
    );

    final title = config.title.isEmpty ? l10n.trendDefaultTitle : config.title;
    final seriesColor = isZeroAmount(chartValues.fold<double>(0, math.max))
        ? mutedColor
        : _trendSeriesColor(config.series, Theme.of(context).brightness);
    final seriesLabel = homeTrendSeriesLabel(l10n, config.series);

    return VeriCard(
      onTap: onTap,
      quietTap: true,
      child: RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const _CircleArrow(),
              ],
            ),
            if (showBig || showPill) ...[
              const SizedBox(height: 10),
              Row(
                key: const Key('home_primary_metrics'),
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (showBig)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            homeMetricLabel(l10n, config.big),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: mutedColor,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatHomeMetric(config.big, bigValue),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.displayMedium
                                ?.copyWith(
                                  color: bigColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                    ),
                  if (showBig && showPill) const SizedBox(width: 8),
                  // 摘要胶囊可收缩：大字号下英文标签可能比整行还宽，不能让整行溢出；
                  // 收缩后仍靠右对齐。
                  if (showPill)
                    Flexible(
                      child: Align(
                        alignment: showBig
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          key: const Key('home_summary_pill'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: pillColor.withValues(
                              alpha: isDark ? 0.16 : 0.10,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${homeMetricLabel(l10n, config.pill)} '
                            '${formatHomeMetric(config.pill, pillValue)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: pillColor,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (cardSlots.isNotEmpty) ...[
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final (index, slot) in cardSlots.indexed) ...[
                      if (index > 0) const SizedBox(width: 8),
                      Expanded(
                        key: ValueKey(slot),
                        child: _MetricTile(
                          key: Key('home_metric_${slot - 1}'),
                          metric: config.slotMetric(slot),
                          metricContext: metricContext,
                          dark: isDark,
                          mutedColor: mutedColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.lastSevenDaysSeries(seriesLabel),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            SizedBox(
              height: 96,
              child: Padding(
                // 左右不留空隙，保证纵轴标签左缘与卡片标题严格对齐。
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                // 图表区域自行响应点击展示数据,不触发卡片跳转。
                child: InteractiveTrendChart(
                  color: seriesColor,
                  values: chartValues,
                  xLabels: labelsForWindow(window),
                  yLabels: reportAxisLabels(
                    chartValues.map((v) => v.abs()).fold(0, math.max),
                  ),
                  labelColor: mutedColor,
                  glow: false,
                  highlightLatest: true,
                  tooltipOf: (index) {
                    final day = window.days[index];
                    return ChartTooltip(
                      title: l10n.dateMonthDay(day),
                      lines: <ChartTooltipLine>[
                        ChartTooltipLine(
                          text:
                              '$seriesLabel ${_trendSeriesValueText(config.series, chartValues[index])}',
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            SectionHeaderAction(
              title: l10n.metricTodayExpense,
              trailing: todayExpenses.isEmpty
                  ? l10n.commonNone
                  : formatExpenseAmount(todayExpenseTotal),
              onTap: onTodayExpenseTap,
            ),
            const SizedBox(height: 6),
            if (todayExpenses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  l10n.homeNoEntriesTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: mutedColor),
                ),
              )
            else
              for (final item in todayExpenses.indexed) ...<Widget>[
                TransactionTile(
                  item.$2,
                  accounts: accounts,
                  categories: categories,
                  tags: tags,
                  showDate: false,
                  baseCurrencyCode: baseCurrencyCode,
                  onTap: onEntryTap == null ? null : () => onEntryTap!(item.$2),
                ),
                if (item.$1 != todayExpenses.length - 1)
                  const SizedBox(height: 4),
              ],
          ],
        ),
      ),
    );
  }
}

/// 走势卡片里的一个可自定义小卡片：展示某个指标的名称与数值。
class _MetricTile extends StatelessWidget {
  const _MetricTile({
    super.key,
    required this.metric,
    required this.metricContext,
    required this.dark,
    required this.mutedColor,
  });

  final HomeMetric metric;
  final HomeMetricContext metricContext;
  final bool dark;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    final value = computeHomeMetric(metric, metricContext);
    final color = homeMetricColor(
      metric,
      value,
      mutedColor,
      Theme.of(context).brightness,
      inkColor: Theme.of(context).colorScheme.onSurface,
    );
    final tone = metric.name.contains('Avg')
        ? VeriMetricTone.neutral
        : color == veriSemantic(context, veriIncome)
        ? VeriMetricTone.income
        : color == veriSemantic(context, veriExpense)
        ? VeriMetricTone.expense
        : VeriMetricTone.neutral;
    return _TrendMetric(
      label: homeMetricLabel(AppLocalizations.of(context), metric),
      value: formatHomeMetric(metric, value),
      color: color,
      tone: tone,
      dark: dark,
    );
  }
}

class _TrendMetric extends StatelessWidget {
  const _TrendMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.tone,
    required this.dark,
  });

  final String label;
  final String value;
  final Color color;
  final VeriMetricTone tone;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: veriMetricTileColor(context, tone, onCover: dark),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: dark
                  ? Colors.white.withValues(alpha: 0.72)
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.58),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: dark ? Colors.white.withValues(alpha: 0.94) : color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetPanel extends StatelessWidget {
  const BudgetPanel({
    super.key,
    required this.month,
    required this.window,
    required this.expense,
    required this.budget,
    required this.categoryRisk,
    required this.currencyCode,
    required this.onTap,
  });

  /// 预算周期的键月（预算存储键）。
  final DateTime month;

  /// 当期预算周期窗口（自然月时即该月），决定剩余天数与标题日期范围。
  final DateWindow window;

  final double expense;
  final double budget;
  final CategoryBudgetSnapshot? categoryRisk;
  final String currencyCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 未设预算（budget<=0）显示 0；设了预算则超支时显示负数（与预算页口径一致）。
    final remaining = budget <= 0 ? 0.0 : budget - expense;
    final overspent = remaining < 0;
    final today = dateOnly(DateTime.now());
    final daysInCycle = window.days.length;
    final remainingDays = window.days
        .where((day) => !day.isBefore(today))
        .length
        .clamp(1, daysInCycle);
    final ratio = budget <= 0 ? 0.0 : (expense / budget).clamp(0, 1).toDouble();
    // 中心文案用真实比例（超支时 >100%），环本身仍封顶为满圈。
    final realPercent = budget <= 0 ? 0.0 : expense / budget * 100;
    final expenseColor = veriSemantic(context, veriExpense);
    // 自定义预算周期时标题展示日期范围，避免「N月预算」误导。
    final cyclic = VeriFinScope.of(context).budgetCycleIsCustom;
    final title = cyclic
        ? AppLocalizations.of(
            context,
          ).budgetCycleRange(window.start, window.end)
        : AppLocalizations.of(context).monthBudgetTitle(month);

    return VeriCard(
      onTap: onTap,
      quietTap: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              MoneyUnitLabel(currencyCode: currencyCode),
              const SizedBox(width: 8),
              const _CircleArrow(),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox(
                      width: 88,
                      height: 88,
                      child: VeriBudgetRing(
                        value: ratio,
                        strokeWidth: 9,
                        trackColor: VeriStyleTokens.of(context).surfaceAltColor,
                        progressColor: budgetProgressColor(
                          budget,
                          budget - expense,
                          ratio,
                          Theme.of(context).brightness,
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          '${realPercent.toStringAsFixed(0)}%',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: overspent
                                    ? expenseColor
                                    : Theme.of(context).colorScheme.onSurface
                                          .withValues(alpha: 0.82),
                              ),
                        ),
                        if (overspent)
                          Text(
                            AppLocalizations.of(context).aiOverBudget,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: expenseColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _BudgetMetricCell(
                            // 超支时不再显示「剩余 -324」，直接说「本月已超支 324」。
                            label: overspent
                                ? (cyclic
                                      ? AppLocalizations.of(
                                          context,
                                        ).budgetOverspentThisPeriod
                                      : AppLocalizations.of(
                                          context,
                                        ).budgetOverspentThisMonth)
                                : AppLocalizations.of(context).budgetRemaining,
                            value: formatAmount(remaining.abs()),
                            color: overspent
                                ? expenseColor
                                : veriSemantic(context, veriIncome),
                            tone: overspent
                                ? VeriMetricTone.expense
                                : VeriMetricTone.income,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BudgetMetricCell(
                            label: AppLocalizations.of(
                              context,
                            ).budgetDailyRemaining,
                            // 超支时可分配日均为 0（负的日均无实际意义）。
                            value: formatAmount(
                              (remaining < 0 ? 0.0 : remaining) / remainingDays,
                            ),
                            color: Theme.of(context).colorScheme.onSurface,
                            tone: remaining > 0
                                ? VeriMetricTone.primary
                                : VeriMetricTone.neutral,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _BudgetMetricCell(
                            label: AppLocalizations.of(
                              context,
                            ).entryTypeExpense,
                            value: formatExpenseAmount(expense),
                            color: Theme.of(context).colorScheme.onSurface,
                            tone: VeriMetricTone.expense,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _BudgetMetricCell(
                            label: AppLocalizations.of(context).budgetLegend,
                            value: formatAmount(budget),
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.72),
                            tone: VeriMetricTone.neutral,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (categoryRisk != null) ...<Widget>[
            const SizedBox(height: 12),
            _HomeBudgetRiskBanner(snapshot: categoryRisk!),
          ],
        ],
      ),
    );
  }
}

class _BudgetMetricCell extends StatelessWidget {
  const _BudgetMetricCell({
    required this.label,
    required this.value,
    required this.color,
    required this.tone,
  });

  final String label;
  final String value;
  final Color color;
  final VeriMetricTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: veriMetricTileColor(context, tone),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.58),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleArrow extends StatelessWidget {
  const _CircleArrow();

  @override
  Widget build(BuildContext context) {
    // 轻量化：去掉圆形底色，只保留浅色箭头；整张卡片本身可点。
    return Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
    );
  }
}

class IncomeExpenseStatsPage extends StatefulWidget {
  const IncomeExpenseStatsPage({
    super.key,
    this.initialType = EntryType.expense,
  });
  final EntryType initialType;

  @override
  State<IncomeExpenseStatsPage> createState() => _IncomeExpenseStatsPageState();
}

/// 收支统计的视图档位：周 / 月 / 季按天描点，年按 12 个月描点。
enum _StatPeriod { lastSeven, week, month, quarter, year }

class _IncomeExpenseStatsPageState extends State<IncomeExpenseStatsPage> {
  DateTime _focusDate = DateTime.now();
  late EntryType _type = widget.initialType;
  _StatPeriod _period = _StatPeriod.lastSeven;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = VeriFinScope.of(context);
    final isYear = _period == _StatPeriod.year;
    // 年视图无「按天」窗口，用 12 个月聚合；其余按天窗口。
    final window = isYear ? null : _windowForPeriod();
    final scopedByType = controller.entries
        .where((entry) => entry.type == _type && !entry.excludedFromStatistics)
        .toList();

    final List<LedgerEntry> rangeEntries;
    final List<double> chartValues;
    final List<String> chartXLabels;
    if (isYear) {
      rangeEntries = scopedByType
          .where((entry) => entry.occurredAt.year == _focusDate.year)
          .toList();
      chartValues = monthlyNetValuesForType(
        scopedByType,
        _focusDate.year,
        _type,
      );
      chartXLabels = List<String>.generate(12, (i) => '${i + 1}');
    } else {
      rangeEntries = entriesInWindow(scopedByType, window!);
      chartValues = valuesForTypeInWindow(rangeEntries, window, _type);
      chartXLabels =
          _period == _StatPeriod.week || _period == _StatPeriod.lastSeven
          ? labelsForWindow(window)
          : sparseLabelsForWindow(
              window,
              interval: _period == _StatPeriod.quarter ? 15 : 5,
              anchorToWindowStart: _period == _StatPeriod.quarter,
            );
    }

    final total = sumByType(rangeEntries, _type);
    final statRows = isYear
        ? _monthlyStatRows(rangeEntries, _focusDate.year, total)
        : _periodDayRows(rangeEntries, window!, total);
    final mutedColor = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.52);
    final totalColor = isZeroAmount(total)
        ? mutedColor
        : colorForType(context, _type);
    final totalText = switch (_type) {
      EntryType.expense => formatExpenseAmount(total),
      EntryType.income => formatIncomeAmount(total),
      EntryType.transfer => formatAmount(total),
      EntryType.refund => formatIncomeAmount(total),
    };

    String amountTextOf(double value) => switch (_type) {
      EntryType.expense => formatExpenseAmount(value),
      EntryType.income => formatSignedAmount(value),
      EntryType.transfer => formatAmount(value),
      EntryType.refund => formatSignedAmount(value),
    };

    return Scaffold(
      body: SafeArea(
        child: VeriPage(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
            children: <Widget>[
              VeriHeader(
                title: l10n.incomeExpenseTitle,
                subtitle: currencyUnitSubtitle(
                  l10n,
                  null,
                  controller.activeBook.baseCurrencyCode,
                ),
                showBack: true,
                actions: <Widget>[
                  HeaderAction(
                    key: const Key('trend_customize'),
                    icon: Icons.edit_outlined,
                    tooltip: l10n.trendCustomizeEntry,
                    onPressed: () {
                      Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (context) => const HomeMetricsSettingsPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              VeriSegmentedControl<_StatPeriod>(
                values: _StatPeriod.values,
                selected: _period,
                labelOf: (period) => switch (period) {
                  _StatPeriod.lastSeven => l10n.statLastSevenDays,
                  _StatPeriod.week => l10n.statPeriodWeek,
                  _StatPeriod.month => l10n.statPeriodMonth,
                  _StatPeriod.quarter => l10n.statPeriodQuarter,
                  _StatPeriod.year => l10n.statPeriodYear,
                },
                onChanged: (period) => setState(() {
                  _period = period;
                  if (period == _StatPeriod.lastSeven) {
                    _focusDate = DateTime.now();
                  }
                }),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: MonthSwitcher(
                        label: _rangeLabel(l10n, window),
                        previousTooltip: _period == _StatPeriod.lastSeven
                            ? l10n.previousSevenDays
                            : null,
                        nextTooltip: _period == _StatPeriod.lastSeven
                            ? l10n.nextSevenDays
                            : null,
                        onPrevious: () => _shiftFocus(-1),
                        onNext:
                            _period == _StatPeriod.lastSeven &&
                                !dateOnly(
                                  _focusDate,
                                ).isBefore(dateOnly(DateTime.now()))
                            ? null
                            : () => _shiftFocus(1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  AnchoredMenuChoice<EntryType>(
                    // 收支统计只展示收支口径；转账不是收入也不是支出，留在
                    // 交易列表和转账详情里查看，不在这里与收支并列。
                    values: const <EntryType>[
                      EntryType.expense,
                      EntryType.income,
                    ],
                    selected: _type,
                    idOf: (value) => 'stats_type_${value.name}',
                    labelOf: (value) => value.label(l10n),
                    iconOf: (value) => switch (value) {
                      EntryType.expense => Icons.arrow_upward_rounded,
                      EntryType.income => Icons.arrow_downward_rounded,
                      EntryType.transfer => Icons.swap_horiz_rounded,
                      EntryType.refund => Icons.undo_rounded,
                    },
                    onSelected: (value) => setState(() => _type = value),
                    semanticLabel: l10n.statTypeTitle,
                    builder: (context, openMenu, menuOpen) =>
                        FilterPill(label: _type.label(l10n), onTap: openMenu),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              VeriCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${_rangeLabel(l10n, window)} ${_type.label(l10n)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      totalText,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: totalColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: InteractiveTrendChart(
                        color: totalColor,
                        values: chartValues,
                        xLabels: chartXLabels,
                        yLabels: reportAxisLabels(
                          chartValues.fold(0, math.max),
                        ),
                        labelColor: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.50),
                        tooltipOf: (index) {
                          final value = chartValues[index];
                          final title = isYear
                              ? l10n.monthNumber(index + 1)
                              : l10n.dateMonthDay(window!.days[index]);
                          return ChartTooltip(
                            title: title,
                            lines: <ChartTooltipLine>[
                              ChartTooltipLine(
                                text:
                                    '${_type.label(l10n)} ${amountTextOf(value)}',
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              VeriCard(
                child: Column(
                  children: <Widget>[
                    if (statRows.isEmpty)
                      EmptyState(
                        icon: Icons.bar_chart_outlined,
                        title: l10n.homeNoStatsTitle,
                        description: l10n.homeNoStatsDesc,
                      )
                    else
                      for (final row in statRows.indexed) ...<Widget>[
                        _DailyStatTile(
                          row: row.$2,
                          type: _type,
                          onTap: () => _openStatRow(row.$2),
                        ),
                        if (row.$1 != statRows.length - 1) const Divider(),
                      ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateWindow _windowForPeriod() => switch (_period) {
    _StatPeriod.lastSeven => lastSevenDaysWindowFor(_focusDate),
    _StatPeriod.week => weekWindowFor(_focusDate),
    _StatPeriod.quarter => quarterWindowFor(_focusDate),
    _StatPeriod.year => monthWindowFor(_focusDate), // 年视图不用此窗口
    _StatPeriod.month => monthWindowFor(_focusDate),
  };

  /// 顶部前后翻页：按当前档位步进（周±7 天、月±1 月、季±3 月、年±1 年）。
  void _shiftFocus(int direction) {
    setState(() {
      _focusDate = switch (_period) {
        _StatPeriod.lastSeven => addCalendarDays(_focusDate, direction * 7),
        _StatPeriod.week => DateTime(
          _focusDate.year,
          _focusDate.month,
          _focusDate.day + direction * 7,
        ),
        _StatPeriod.month => DateTime(
          _focusDate.year,
          _focusDate.month + direction,
        ),
        _StatPeriod.quarter => DateTime(
          _focusDate.year,
          _focusDate.month + direction * 3,
        ),
        _StatPeriod.year => DateTime(
          _focusDate.year + direction,
          _focusDate.month,
        ),
      };
    });
  }

  String _rangeLabel(AppLocalizations l10n, DateWindow? window) =>
      switch (_period) {
        _StatPeriod.lastSeven || _StatPeriod.week => window!.label,
        _StatPeriod.month => l10n.yearMonth(_focusDate),
        _StatPeriod.quarter => l10n.statQuarterRange(
          _focusDate.year,
          quarterOfMonth(_focusDate.month),
        ),
        _StatPeriod.year => l10n.yearLabel(_focusDate.year),
      };

  /// 点统计行：按天视图点某天进当天交易明细；按月（年视图）点某月下钻到该月视图。
  void _openStatRow(_DailyStatRow row) {
    if (row.monthly) {
      setState(() {
        _period = _StatPeriod.month;
        _focusDate = DateTime(row.date.year, row.date.month);
      });
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => TransactionsPage(initialDate: row.date),
      ),
    );
  }
}

class _HomeBudgetRiskBanner extends StatelessWidget {
  const _HomeBudgetRiskBanner({required this.snapshot});

  final CategoryBudgetSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final color = snapshot.overBudget
        ? veriSemantic(context, veriExpense)
        : veriSemantic(context, veriWarning);
    final l10n = AppLocalizations.of(context);
    final text = snapshot.overBudget
        ? l10n.budgetCatOver(
            snapshot.category.label,
            formatAmount(snapshot.spent - snapshot.budget),
          )
        : l10n.budgetCatUsed(
            snapshot.category.label,
            (snapshot.ratio * 100).toStringAsFixed(0),
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(veriRadiusSm),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            snapshot.overBudget
                ? Icons.warning_amber_rounded
                : Icons.error_outline,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyStatRow {
  const _DailyStatRow({
    required this.date,
    required this.amount,
    required this.percent,
    required this.count,
    this.monthly = false,
  });

  final DateTime date;
  final double amount;
  final double percent;
  final int count;

  /// true 为「按月」行（年视图），标题显示月份、点击下钻到该月；false 为「按天」行。
  final bool monthly;
}

class _DailyStatTile extends StatelessWidget {
  const _DailyStatTile({required this.row, required this.type, this.onTap});

  final _DailyStatRow row;
  final EntryType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final amountColor = colorForType(context, type);
    final amountText = switch (type) {
      EntryType.expense => formatExpenseAmount(row.amount),
      EntryType.income => formatSignedAmount(row.amount),
      EntryType.transfer => formatAmount(row.amount),
      EntryType.refund => formatSignedAmount(row.amount),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(veriRadiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: <Widget>[
            VeriIconBox(
              icon: Icons.calendar_today_outlined,
              color: amountColor,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row.monthly
                        ? AppLocalizations.of(
                            context,
                          ).monthNumber(row.date.month)
                        : AppLocalizations.of(context).dateMonthDay(row.date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${(row.percent * 100).toStringAsFixed(0)}%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.48),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  amountText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppLocalizations.of(context).entriesCount(row.count),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.48),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 按天统计行（周/月/季视图）：遍历窗口内每一天，聚合当天该类型的交易。
List<_DailyStatRow> _periodDayRows(
  List<LedgerEntry> entries,
  DateWindow window,
  double total,
) {
  final rows = <_DailyStatRow>[];
  for (final day in window.days) {
    final dayEntries = entries
        .where((entry) => DateUtils.isSameDay(entry.occurredAt, day))
        .toList();
    if (dayEntries.isEmpty) {
      continue;
    }
    final amount = dayEntries.fold<double>(
      0,
      (sum, entry) => sum + statAmountForEntry(entry),
    );
    rows.add(
      _DailyStatRow(
        date: day,
        amount: amount,
        percent: total <= 0 ? 0 : amount / total,
        count: dayEntries.length,
      ),
    );
  }
  return rows..sort((a, b) => b.date.compareTo(a.date));
}

/// 按月统计行（年视图）：聚合某年 12 个月里有记录的月份。
List<_DailyStatRow> _monthlyStatRows(
  List<LedgerEntry> entries,
  int year,
  double total,
) {
  final rows = <_DailyStatRow>[];
  for (var month = 1; month <= 12; month += 1) {
    final monthEntries = entries
        .where((entry) => entry.occurredAt.month == month)
        .toList();
    if (monthEntries.isEmpty) {
      continue;
    }
    final amount = monthEntries.fold<double>(
      0,
      (sum, entry) => sum + statAmountForEntry(entry),
    );
    rows.add(
      _DailyStatRow(
        date: DateTime(year, month, 1),
        amount: amount,
        percent: total <= 0 ? 0 : amount / total,
        count: monthEntries.length,
        monthly: true,
      ),
    );
  }
  return rows..sort((a, b) => b.date.compareTo(a.date));
}
