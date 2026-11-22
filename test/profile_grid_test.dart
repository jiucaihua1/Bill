import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/app/common_widgets.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('我的页宫格展示功能入口', (WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    final controller = await pumpApp(tester);
    final category = controller.categoriesForType(EntryType.expense).first;
    final now = DateTime.now();
    for (final (id, note) in [
      ('auto', '视频会员月付'),
      ('manual', '云存储服务'),
      ('expired', '京东 PLUS 年付'),
      ('biennial', '云盘会员两年付'),
    ]) {
      controller.addEntry(
        LedgerEntry(
          id: id,
          bookId: controller.activeBook.id,
          type: EntryType.expense,
          amount: id == 'biennial'
              ? DateTime.utc(now.year + 2, now.month, now.day)
                    .difference(DateTime.utc(now.year, now.month, now.day))
                    .inDays
                    .toDouble()
              : 24,
          categoryId: category.id,
          accountId: '',
          note: note,
          occurredAt: id == 'biennial'
              ? now
              : DateTime(now.year - 3, now.month, now.day),
        ),
      );
    }
    await tapBottomTab(tester, 3);

    expect(find.text('小禾'), findsOneWidget);
    expect(find.text('记账年数'), findsOneWidget);
    expect(find.text('交易笔数'), findsOneWidget);
    expect(find.text('净资产'), findsNothing);
    // 宫格分组标题与主要入口。
    expect(find.text('记账管理'), findsOneWidget);
    expect(find.text('数据与工具'), findsOneWidget);
    expect(find.text('分类管理'), findsOneWidget);
    expect(find.text('周期记账'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('profile_feature_grid_bookkeeping')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('profile_feature_grid_tools')),
      findsOneWidget,
    );
    expect(find.textContaining('Web 开发预览'), findsNothing);

    // 「统计分析」已并入看板，入口不再出现在宫格里。
    final scrollable = firstVerticalScrollable();
    await tester.scrollUntilVisible(
      find.text('记账提醒'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('统计分析'), findsNothing);
    expect(find.text('记账提醒'), findsOneWidget);

    final subscriptions = find.text('订阅支出');
    await tester.scrollUntilVisible(subscriptions, 200, scrollable: scrollable);
    await tester.tap(subscriptions);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transactions_quick_entry_fab')), findsNothing);
    expect(find.text('月付'), findsWidgets);
    final daily = tester
        .widgetList<SummaryMetric>(find.byType(SummaryMetric))
        .singleWhere((m) => m.label == '今日日均花费');
    expect(double.parse(daily.value), 1);
    await tester.ensureVisible(find.text('今日日均花费'));
    await tester.tap(find.text('今日日均花费'));
    await tester.pumpAndSettle();
    final breakdown = find.byType(BottomSheet);
    expect(
      find.descendant(of: breakdown, matching: find.text('云盘会员两年付')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: breakdown, matching: find.text('京东 PLUS 年付')),
      findsNothing,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('两年付'), findsWidgets);
    expect(find.text('云存储服务'), findsNothing);
    await tester.drag(firstVerticalScrollable(), const Offset(0, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择已有账单'));
    await tester.pumpAndSettle();
    expect(find.text('视频会员月付'), findsNothing);
    await tester.tap(find.text('云存储服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('付款周期'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '3');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('保存'));
    await tester.pumpAndSettle();
    expect(find.text('季付'), findsWidgets);
    expect(
      controller.entries.singleWhere((e) => e.id == 'manual').subscriptionMark,
      SubscriptionMark.forMonths(3),
    );
    await tester.ensureVisible(find.text('云存储服务'));
    await tester.tap(find.text('云存储服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出订阅分析'));
    await tester.pumpAndSettle();
    expect(find.text('云存储服务'), findsNothing);
    expect(controller.entries.length, 4);
  });
}
