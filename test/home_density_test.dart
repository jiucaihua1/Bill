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
    expect(overview.height, lessThanOrEqualTo(280));
    for (var i = 1; i <= 3; i++) {
      expect(find.byKey(Key('home_metric_$i')), findsOneWidget);
    }
    final transactions = find.byType(TransactionTile);
    expect(transactions, findsNWidgets(5));
    final navTop = tester.getRect(find.byKey(const Key('main_bottom_nav'))).top;
    expect(tester.getRect(transactions.last).bottom, lessThan(navTop));
    final budget = find.byType(BudgetPanel);
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
    await tester.drag(firstVerticalScrollable(), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(budget);
    await tester.pumpAndSettle();
    expect(find.byType(HomeTrendPanel), findsNothing);
    expect(find.byType(BudgetOverviewPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
