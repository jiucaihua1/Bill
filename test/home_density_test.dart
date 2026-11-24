import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/common_widgets.dart';
import 'package:xiaohe/app/chart_painters.dart';
import 'package:xiaohe/app/models.dart';
import 'package:xiaohe/main.dart';
import 'package:xiaohe/pages/home_page.dart';
import 'package:xiaohe/pages/budget_pages.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();
  testWidgets('概览胶囊靠右对齐，不紧挨主金额', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byKey(const Key('home_primary_metrics')));
    final pill = tester.getRect(find.byKey(const Key('home_summary_pill')));
    expect(pill.right, closeTo(row.right, 0.5));
    expect(tester.takeException(), isNull);
  });
  testWidgets('首页保留指标方块与原预算布局，预算仍可打开详情', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    final controller = await makeController();
    await controller.importTransactionsFromCsv(
      File('docs/fixtures/preview-transactions.csv').readAsStringSync(),
    );
    controller.setMonthlyBudget(DateTime.now(), 5000);
    controller.setThemePreference(ThemePreference.light);
    await controller.waitForPendingWrites();
    await tester.pumpWidget(VeriFinApp(controller: controller));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final overview = tester.getRect(find.byType(HomeTrendPanel));
    for (var i = 1; i <= 3; i++) {
      final metric = find.byKey(Key('home_metric_$i'));
      expect(metric, findsOneWidget);
      expect(overview.contains(tester.getCenter(metric)), isTrue);
    }
    await tester.scrollUntilVisible(
      find.text('最近交易'),
      200,
      scrollable: firstVerticalScrollable(),
    );
    final transactions = find.descendant(
      of: find.byType(CalendarPreview),
      matching: find.byType(TransactionTile),
    );
    expect(transactions, findsNWidgets(5));
    final budget = find.byType(BudgetPanel);
    await tester.scrollUntilVisible(
      budget,
      -200,
      scrollable: firstVerticalScrollable(),
    );
    expect(
      find.descendant(of: budget, matching: find.text('支出')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: budget, matching: find.text('剩余日均')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: budget,
        matching: find.byWidgetPredicate((widget) => widget is VeriBudgetRing),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: budget,
        matching: find.byType(LinearProgressIndicator),
      ),
      findsNothing,
    );
    // 重设计后的预算卡采用左环右数据紧凑排布，保留完整圆环与核心指标。
    expect(tester.getRect(budget).height, greaterThan(115));
    await tester.ensureVisible(budget);
    await tester.pumpAndSettle();
    await tester.tap(budget);
    await tester.pumpAndSettle();
    expect(find.byType(HomeTrendPanel), findsNothing);
    expect(find.byType(BudgetOverviewPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
