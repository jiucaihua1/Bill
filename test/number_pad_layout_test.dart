import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/entry_sheets.dart';
import 'package:xiaohe/app/models.dart';
import 'package:xiaohe/local_storage/local_storage.dart';
import 'package:xiaohe/pages/settings_page.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('电话布局将数字顺序改为 1-2-3 / 4-5-6 / 7-8-9', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      zhMaterialApp(
        home: const Scaffold(
          body: NumberPadSheet(title: '金额', layout: NumberPadLayout.phone),
        ),
      ),
    );

    expect(
      tester.getTopLeft(find.byKey(const Key('number_key_1'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('number_key_7'))).dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('number_key_4'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('number_key_7'))).dy),
    );
  });

  testWidgets('设置中的数字键盘布局选择后可在重启时恢复', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = LocalKeyValueStore();
    final controller = await pumpApp(tester, store);

    await tapBottomTab(tester, 3);
    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('数字键盘布局'),
      200,
      scrollable: firstVerticalScrollable(),
    );
    await tester.tap(find.text('数字键盘布局'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>(
          'anchored_menu_item_settings_number_pad_layout_standard',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 菜单选择后立即自动保存，不再需要右上角保存。
    expect(controller.numberPadLayout, NumberPadLayout.standard);

    // 自动保存不会关闭设置页；滚回顶部返回，再去验证记账键盘。
    await tester.fling(firstVerticalScrollable(), const Offset(0, 1200), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    await tapBottomTab(tester, 0);
    await tester.tap(find.byKey(const Key('quick_entry_fab')));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('number_key_7'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('number_key_1'))).dy),
    );

    final restarted = await makeController(store);
    expect(restarted.numberPadLayout, NumberPadLayout.standard);
    restarted.dispose();
  });

  test('未知或缺失的布局偏好回退为电话布局', () {
    expect(NumberPadLayout.fromStorage(null), NumberPadLayout.phone);
    expect(NumberPadLayout.fromStorage('unknown'), NumberPadLayout.phone);
  });
}
