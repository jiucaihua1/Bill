import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/entry_sheets.dart';
import 'package:xiaohe/app/models.dart';
import 'package:xiaohe/app/veri_fin_controller.dart';
import 'package:xiaohe/app/veri_fin_scope.dart';
import 'package:xiaohe/pages/entry_detail_page.dart';

import 'support/test_harness.dart';

/// 覆盖记账页当前分类分支的就地展开交互。
void main() {
  useTestDatabases();

  String idOfLabel(VeriFinController controller, String label) {
    return controller.categories.firstWhere((c) => c.label == label).id;
  }

  /// 造一个带「餐饮 → 午餐 → 工作午餐」层级的控制器。
  Future<VeriFinController> controllerWithSubcategories() async {
    final controller = await makeController();
    final lunchId = idOfLabel(controller, '午餐');
    controller.addCategory(
      type: EntryType.expense,
      label: '工作午餐',
      iconCode: 'dining',
      parentId: lunchId,
    );
    return controller;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    VeriFinController controller,
    Widget page,
  ) async {
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('一级分类下方展示已打开分支的子分类', (tester) async {
    final controller = await controllerWithSubcategories();
    await pumpPage(tester, controller, const EntryDetailPage.manual());

    final dining = find.text('食品餐饮');
    expect(find.text('午餐'), findsOneWidget);
    await tester.tap(dining);
    await tester.pumpAndSettle();
    expect(find.text('午餐'), findsNothing);
    await tester.tap(dining);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('entry_category_grid')), findsOneWidget);
    expect(find.byKey(const Key('number_pad_display')), findsOneWidget);
    expect(find.byKey(const Key('number_key_CANCEL')), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('早餐'), findsOneWidget);
    expect(find.byType(CategoryPickerSheet), findsNothing);
    expect(
      tester.getTopLeft(find.text('午餐')).dy,
      greaterThan(tester.getBottomLeft(dining).dy),
    );
  });

  testWidgets('切换一级分类后展开新分支并可点选三级分类', (tester) async {
    final controller = await controllerWithSubcategories();
    await pumpPage(
      tester,
      controller,
      const EntryDetailPage(initialAmount: 30),
    );

    final transport = find.text('出行交通');
    await tester.ensureVisible(transport);
    await tester.tap(transport);
    await tester.pumpAndSettle();
    expect(find.text('地铁'), findsOneWidget);
    expect(find.text('早餐'), findsNothing);

    final dining = find.text('食品餐饮');
    await tester.ensureVisible(dining);
    await tester.tap(dining);
    await tester.pumpAndSettle();
    await tester.tap(find.text('午餐'));
    await tester.pumpAndSettle();
    expect(find.text('地铁'), findsNothing);

    final workLunch = find.text('工作午餐');
    await tester.ensureVisible(workLunch);
    await tester.pumpAndSettle();
    await tester.tap(workLunch);
    await tester.pumpAndSettle();

    expect(find.byType(CategoryPickerSheet), findsNothing);
    expect(find.text('工作午餐'), findsOneWidget);
    final workLunchId = idOfLabel(controller, '工作午餐');
    expect(
      find.byKey(Key('entry_category_selected_$workLunchId')),
      findsOneWidget,
    );
  });

  testWidgets('编辑子分类交易时自动打开原分类路径', (tester) async {
    final controller = await controllerWithSubcategories();
    final lunchId = idOfLabel(controller, '午餐');
    final entry = LedgerEntry(
      id: 'e1',
      bookId: controller.activeBook.id,
      type: EntryType.expense,
      amount: 30,
      categoryId: lunchId,
      accountId: '',
      note: '',
      occurredAt: DateTime(2026, 7, 12, 12, 0),
    );

    await pumpPage(tester, controller, EntryDetailPage.draft(entry: entry));

    expect(find.byType(CategoryPickerSheet), findsNothing);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('食品餐饮'), findsOneWidget);
    expect(find.byKey(Key('entry_category_selected_$lunchId')), findsOneWidget);
  });
}
