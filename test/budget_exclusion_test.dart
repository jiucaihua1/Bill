import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/budget_status.dart';
import 'package:xiaohe/app/common_widgets.dart';
import 'package:xiaohe/app/ledger_math.dart';
import 'package:xiaohe/app/models.dart';
import 'package:xiaohe/app/report_analysis.dart';
import 'package:xiaohe/app/veri_fin_scope.dart';
import 'package:xiaohe/local_storage/local_storage.dart';
import 'package:xiaohe/pages/budget_pages.dart';
import 'package:xiaohe/pages/home_page.dart';
import 'package:xiaohe/pages/transactions_pages.dart';

import 'support/test_harness.dart';

/// 「不计入预算」标记：一笔支出脱离**预算**口径，但仍是**实际发生**的支出。
///
/// 本文件成对断言两侧，防止收口做成「整个 App 都不算这笔」：
/// 预算一侧必须排除，账户余额/收支统计/报表一侧必须照常计入。
LedgerEntry _expense({
  required String id,
  required double amount,
  bool excluded = false,
  DateTime? occurredAt,
}) => LedgerEntry(
  id: id,
  bookId: defaultLedgerBookId,
  type: EntryType.expense,
  amount: amount,
  categoryId: 'dining',
  accountId: 'cash',
  note: '',
  occurredAt: occurredAt ?? DateTime(2026, 7, 4),
  excludedFromBudget: excluded,
);

const List<Category> _categories = <Category>[
  Category(
    bookId: defaultLedgerBookId,
    id: 'dining',
    label: '餐饮',
    type: EntryType.expense,
    iconCode: 'dining',
  ),
];

void main() {
  useTestDatabases();

  group('纯函数口径', () {
    test('预算与收支分别按交易的统计口径取数', () {
      final passThrough = _expense(
        id: 'c',
        amount: 80,
      ).copyWith(excludedFromStatistics: true);
      final returned = passThrough.copyWith(id: 'd', type: EntryType.income);
      final entries = <LedgerEntry>[
        _expense(id: 'a', amount: 100),
        _expense(id: 'b', amount: 50, excluded: true),
        passThrough,
        returned,
      ];

      expect(budgetExpenseTotal(entries), 100);
      expect(sumByType(entries, EntryType.expense), 150);
      expect(sumByType(entries, EntryType.income), 0);
      final report = reportSummary(entries);
      expect(report.expenseCount, 2);
      expect(report.incomeCount, 0);
      expect(accountDeltaForEntry(passThrough, 'cash'), -80);
      expect(accountDeltaForEntry(returned, 'cash'), 80);
    });

    test('countsTowardBudget 只认支出且未被标记', () {
      expect(countsTowardBudget(_expense(id: 'a', amount: 1)), isTrue);
      expect(
        countsTowardBudget(_expense(id: 'b', amount: 1, excluded: true)),
        isFalse,
      );
      // 非支出天然不进预算，标记与否都不改变这一点。
      final income = LedgerEntry(
        id: 'c',
        bookId: defaultLedgerBookId,
        type: EntryType.income,
        amount: 10,
        categoryId: 'salary',
        accountId: 'cash',
        note: '',
        occurredAt: DateTime(2026, 7, 4),
      );
      expect(countsTowardBudget(income), isFalse);
    });

    test('标记不影响账户余额与净额（钱确实动了）', () {
      final entry = _expense(id: 'a', amount: 100, excluded: true);
      expect(entry.netBaseAmount, 100);
      expect(signedAmount(entry), -100);
      expect(accountDeltaForEntry(entry, 'cash'), -100);
    });

    test('按日预算与桌面小组件「今日支出」使用各自的统计口径', () {
      final day = DateTime(2026, 7, 4);
      final entries = <LedgerEntry>[
        _expense(id: 'a', amount: 30, occurredAt: day),
        _expense(id: 'b', amount: 20, excluded: true, occurredAt: day),
        _expense(
          id: 'c',
          amount: 80,
          occurredAt: day,
        ).copyWith(excludedFromStatistics: true),
      ];

      expect(dayBudgetExpenseTotal(entries, day), 30);
      expect(dayExpenseTotal(entries, day), 50);
    });
  });

  group('交易筛选选项', () {
    test('全部 / 计入预算 / 不计入预算 / 不计入收支', () {
      final plain = _expense(id: 'a', amount: 1);
      final excluded = _expense(id: 'b', amount: 1, excluded: true);

      expect(TransactionScopeFilter.all.matches(plain), isTrue);
      expect(TransactionScopeFilter.all.matches(excluded), isTrue);
      expect(TransactionScopeFilter.inBudget.matches(plain), isTrue);
      expect(TransactionScopeFilter.inBudget.matches(excluded), isFalse);
      expect(TransactionScopeFilter.outOfBudget.matches(plain), isFalse);
      expect(TransactionScopeFilter.outOfBudget.matches(excluded), isTrue);
      final passThrough = plain.copyWith(excludedFromStatistics: true);
      expect(TransactionScopeFilter.inBudget.matches(passThrough), isFalse);
      expect(TransactionScopeFilter.outOfBudget.matches(passThrough), isTrue);
      expect(
        TransactionScopeFilter.excludedFromStatistics.matches(passThrough),
        isTrue,
      );
      expect(
        TransactionScopeFilter.excludedFromStatistics.matches(excluded),
        isFalse,
      );
    });
  });

  group('预算聚合', () {
    test('computeBudgetStatus 的总额与分类上滚都排除标记的支出', () {
      final status = computeBudgetStatus(
        windowEntries: <LedgerEntry>[
          _expense(id: 'a', amount: 100),
          _expense(id: 'b', amount: 50, excluded: true),
        ],
        previousWindowEntries: <LedgerEntry>[
          _expense(id: 'p', amount: 80, excluded: true),
        ],
        categories: _categories,
        budget: 500,
        budgetOf: (Category category) => 0,
        remainingDays: 10,
      );

      expect(status.expense, 100);
      expect(status.remaining, 400);
      expect(status.ratio, closeTo(0.2, 1e-9));
      expect(status.categories.single.spent, 100);
      expect(status.previousExpense, 0);
    });

    test('computeCategoryBudgetSnapshots 的分类已花排除标记的支出', () async {
      final controller = await makeController();
      controller
        ..addEntry(_expense(id: 'a', amount: 100))
        ..addEntry(_expense(id: 'b', amount: 50, excluded: true));

      final snapshots = computeCategoryBudgetSnapshots(
        controller: controller,
        month: DateTime(2026, 7),
        monthEntries: controller.entries.toList(),
      );

      final dining = snapshots.singleWhere(
        (snapshot) => snapshot.category.id == 'dining',
      );
      expect(dining.spent, 100);
      controller.dispose();
    });
  });

  group('控制器与持久化', () {
    test('setEntryExcludedFromBudget 只作用于支出，且标记会落库', () async {
      final store = LocalKeyValueStore();
      final controller = await makeController(store);
      controller
        ..addEntry(_expense(id: 'e1', amount: 100))
        ..addEntry(
          LedgerEntry(
            id: 'i1',
            bookId: controller.activeBook.id,
            type: EntryType.income,
            amount: 10,
            categoryId: 'salary',
            accountId: 'cash',
            note: '',
            occurredAt: DateTime(2026, 7, 4),
          ),
        );

      controller.setEntryExcludedFromBudget('e1', true);
      expect(
        controller.entries
            .singleWhere((entry) => entry.id == 'e1')
            .excludedFromBudget,
        isTrue,
      );

      // 收入不是预算对象，标记对它无效。
      controller.setEntryExcludedFromBudget('i1', true);
      expect(
        controller.entries
            .singleWhere((entry) => entry.id == 'i1')
            .excludedFromBudget,
        isFalse,
      );

      controller.dispose();

      // 同一 store 复用同一仓储，等效于进程重启后重新载入。
      final reloaded = await makeController(store);
      expect(
        reloaded.entries
            .singleWhere((entry) => entry.id == 'e1')
            .excludedFromBudget,
        isTrue,
      );
      reloaded.dispose();
    });

    test('备份往返保留标记，旧备份缺字段按「计入预算」读入', () async {
      final controller = await makeController();
      controller.addEntry(_expense(id: 'e1', amount: 100, excluded: true));

      final restored = await makeController();
      await restored.importDataJson(controller.exportDataJson());
      expect(restored.entries.single.excludedFromBudget, isTrue);
      restored.dispose();

      // 旧备份（v3 但没有该字段）不能凭空变成「不计入预算」。
      final legacy =
          jsonDecode(controller.exportDataJson()) as Map<String, dynamic>;
      final data = legacy['data'] as Map<String, dynamic>;
      final entryJson =
          (data['entries'] as List<dynamic>).single as Map<String, dynamic>;
      expect(entryJson.remove('excludedFromBudget'), isTrue);

      final legacyController = await makeController();
      await legacyController.importDataJson(jsonEncode(legacy));
      expect(legacyController.entries.single.excludedFromBudget, isFalse);
      legacyController.dispose();
      controller.dispose();
    });
  });

  group('界面', () {
    testWidgets('看板预算卡排除标记支出，顶部「本月支出」照常计入', (tester) async {
      final controller = await pumpApp(tester);
      controller.setDefaultMonthlyBudget(1000);
      final now = DateTime.now();
      controller
        ..addEntry(_expense(id: 'a', amount: 100, occurredAt: now))
        ..addEntry(
          _expense(id: 'b', amount: 50, excluded: true, occurredAt: now),
        );
      await tester.pumpAndSettle();

      await openReportsMonthlyTab(tester);

      // 预算执行卡：预算口径只算 100，剩余 1000 - 100 = 900。
      expect(find.text('900'), findsOneWidget);
      // 顶部收支摘要等处：实际发生 150，标记不改变它（同一页同时看得到两个口径）。
      expect(find.text('150'), findsAtLeastNWidgets(1));
    });

    testWidgets('首页预算卡排除标记支出', (tester) async {
      final controller = await pumpApp(tester);
      controller.setDefaultMonthlyBudget(1000);
      final now = DateTime.now();
      controller
        ..addEntry(_expense(id: 'a', amount: 100, occurredAt: now))
        ..addEntry(
          _expense(id: 'b', amount: 50, excluded: true, occurredAt: now),
        );
      await tester.pumpAndSettle();

      // 首页预算卡中心的「剩余」按预算口径：1000 - 100 = 900（不是 850）。
      await tester.scrollUntilVisible(
        find.byType(BudgetPanel),
        300,
        scrollable: firstVerticalScrollable(),
      );
      expect(
        find.descendant(
          of: find.byType(BudgetPanel),
          matching: find.text('900'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('交易列表徽标与预算、收支筛选', (tester) async {
      final controller = await makeController();
      final now = DateTime.now();
      controller
        ..addEntry(_expense(id: 'a', amount: 100, occurredAt: now))
        ..addEntry(
          _expense(id: 'b', amount: 50, excluded: true, occurredAt: now),
        );

      await tester.pumpWidget(
        VeriFinScope(
          controller: controller,
          child: zhMaterialApp(home: const TransactionsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 两笔都照常出现在列表里，只有标记的那笔带徽标。
      expect(find.byType(TransactionTile), findsNWidgets(2));
      expect(find.text('不计入预算'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterPill, '收支'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('计入预算'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionTile), findsOneWidget);

      controller
        ..addEntry(
          _expense(
            id: 'c',
            amount: 25,
            occurredAt: now,
          ).copyWith(excludedFromStatistics: true),
        )
        ..addEntry(
          _expense(id: 'd', amount: 10, occurredAt: now).copyWith(
            type: EntryType.income,
            categoryId: controller.categoriesForType(EntryType.income).first.id,
            excludedFromStatistics: true,
          ),
        );
      await tester.pumpAndSettle();
      // 同一菜单切换口径时，新的选项取代此前的预算筛选。
      await tester.tap(find.widgetWithText(FilterPill, '计入预算'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('不计入收支'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TransactionTile>(find.byType(TransactionTile))
            .map((tile) => tile.entry.id),
        unorderedEquals(['c', 'd']),
      );
      await tester.tap(find.byTooltip('清空筛选'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionTile), findsNWidgets(4));
      expect(find.widgetWithText(FilterPill, '收支'), findsOneWidget);
    });
  });
}
