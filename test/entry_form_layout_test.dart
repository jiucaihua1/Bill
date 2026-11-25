import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/app_theme.dart';
import 'package:xiaohe/app/attachments/attachment_store.dart';
import 'package:xiaohe/app/common_widgets.dart';
import 'package:xiaohe/app/entry_sheets.dart';
import 'package:xiaohe/app/models.dart';
import 'package:xiaohe/app/veri_fin_scope.dart';
import 'package:xiaohe/pages/attachments_editor.dart';
import 'package:xiaohe/pages/entry_detail_page.dart';

import 'support/test_harness.dart';

void main() {
  useTestDatabases();

  testWidgets('快速记账使用优化类型切换和无分割线底部保存', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.reset);

    final controller = await makeController();
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const EntryDetailPage(initialAmount: 30)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('entry_type_segmented_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('entry_type_selected_expense')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.save_outlined), findsNothing);
    expect(find.byKey(const Key('save_entry_button')), findsOneWidget);
    final saveButton = tester.widget<FilledButton>(
      find.byKey(const Key('save_entry_button')),
    );
    expect(saveButton.style?.backgroundColor, isNotNull);
    expect(saveButton.style?.foregroundColor, isNotNull);
    // 禁用态用淡蓝而非主题灰，且不得因 onPressed 为 null 而丢失。
    expect(
      saveButton.style!.backgroundColor!.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      Theme.of(
        tester.element(find.byKey(const Key('save_entry_button'))),
      ).colorScheme.primary.withValues(alpha: 0.38),
    );
    expect(
      saveButton.style!.foregroundColor!.resolve(<WidgetState>{
        WidgetState.disabled,
      }),
      Theme.of(
        tester.element(find.byKey(const Key('save_entry_button'))),
      ).colorScheme.onPrimary.withValues(alpha: 0.78),
    );
    expect(
      tester
          .widget<Padding>(find.byKey(const Key('entry_bottom_save_padding')))
          .padding,
      const EdgeInsets.fromLTRB(22, 10, 22, 18),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('entry_bottom_save_bar')),
        matching: find.byType(Divider),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<ColoredBox>(find.byKey(const Key('entry_bottom_save_bar')))
          .color,
      Colors.transparent,
    );
    expect(
      tester
          .widget<CategoryGlyph>(
            find.descendant(
              of: find.byKey(const Key('entry_category_dining')),
              matching: find.byType(CategoryGlyph),
            ),
          )
          .color,
      veriSemanticFor(Brightness.light, veriExpense),
    );

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('entry_type_selected_income')), findsOneWidget);
    final selectedIncome = controller.categoriesForType(EntryType.income).first;
    expect(
      tester
          .widget<CategoryGlyph>(
            find.descendant(
              of: find.byKey(Key('entry_category_${selectedIncome.id}')),
              matching: find.byType(CategoryGlyph),
            ),
          )
          .color,
      veriSemanticFor(Brightness.light, veriIncome),
    );

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();
    final selectedTransfer = controller
        .categoriesForType(EntryType.transfer)
        .first;
    expect(
      tester
          .widget<CategoryGlyph>(
            find.descendant(
              of: find.byKey(Key('entry_category_${selectedTransfer.id}')),
              matching: find.byType(CategoryGlyph),
            ),
          )
          .color,
      veriSemanticFor(Brightness.light, veriBlue),
    );
  });

  testWidgets('记账属性使用单行横滑布局且不遮挡键盘', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    final controller = await makeController();
    await controller.setMultiCurrencyEnabled(true);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const EntryDetailPage.manual()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('更多信息'), findsNothing);
    final date = find.byKey(const Key('entry_metadata_datetime'));
    expect(date, findsOneWidget);
    expect(find.byKey(const Key('entry_metadata_tags')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('entry_metadata_discount')),
        matching: find.byIcon(Icons.percent_rounded),
      ),
      findsOneWidget,
    );
    final strip = find.byKey(const Key('quick_entry_metadata_strip'));
    final statistics = find.widgetWithText(EntryTogglePill, '不计入收支');
    final budget = find.widgetWithText(EntryTogglePill, '不计入预算');
    final currency = find.byKey(const Key('entry_currency_button'));
    for (final action in [
      statistics,
      budget,
      find.byKey(const Key('entry_metadata_reimbursable')),
      find.byKey(const Key('entry_metadata_attachments')),
      currency,
    ]) {
      expect(find.descendant(of: strip, matching: action), findsOneWidget);
      expect(
        tester.getCenter(action).dy,
        closeTo(tester.getCenter(date).dy, 1),
      );
    }
    expect(
      tester.getBottomLeft(strip).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('number_key_1'))).dy),
    );
    expect(currency.hitTestable(), findsNothing);
    await tester.drag(strip, const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(currency.hitTestable(), findsOneWidget);

    final tags = find.byKey(const Key('entry_metadata_tags'));
    await tester.ensureVisible(tags);
    await tester.pumpAndSettle();
    await tester.tap(tags);
    await tester.pumpAndSettle();
    expect(find.byType(TagSelectorSheet), findsOneWidget);

    Navigator.of(tester.element(find.byType(TagSelectorSheet))).pop();
    await tester.pumpAndSettle();

    final numberKey = find.byKey(const Key('number_key_1'));
    final keyElement = tester.element(numberKey);
    await tester.tap(find.byKey(const Key('entry_note_field')));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.element(numberKey), same(keyElement));
    expect(numberKey.hitTestable(), findsNothing);
    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.element(numberKey), same(keyElement));
    expect(numberKey.hitTestable(), findsOneWidget);

    final from = find.byKey(const Key('account_dropdown'));
    final to = find.byKey(const Key('to_account_dropdown'));
    for (final tab in ['转账', '债务']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.widget<SelectField>(from).labelOutside, isTrue);
      expect(tester.widget<SelectField>(to).labelOutside, isTrue);
      expect(tester.getTopLeft(from).dx, tester.getTopLeft(to).dx);
      expect(tester.getBottomLeft(from).dy, lessThan(tester.getTopLeft(to).dy));
    }
  });

  testWidgets('紧凑附件条展示多张图片和小型删除按钮', (tester) async {
    const image =
        'data:image/png;base64,'
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final removed = <int>[];
    final bytes = base64Decode(image.substring(image.indexOf(',') + 1));
    final store = InMemoryAttachmentStore();
    final attachments = <Attachment>[];
    for (var index = 0; index < 3; index++) {
      final id = 'att-$index';
      await store.writeBytes(id, bytes);
      attachments.add(
        Attachment(id: id, entryId: 'e1', byteSize: bytes.length),
      );
    }

    await tester.pumpWidget(
      zhMaterialApp(
        home: Scaffold(
          body: AttachmentsEditor(
            attachments: attachments,
            store: store,
            onAddBytes: (_) async {},
            onRemoveIndex: removed.add,
            showHeader: false,
            showAddButton: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('图片附件'), findsNothing);
    expect(find.byKey(const Key('attachment_remove_visual_0')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('attachment_remove_visual_0'))),
      const Size(16, 16),
    );

    await tester.tap(find.byKey(const Key('attachment_remove_visual_1')));
    expect(removed, <int>[1]);
  });

  testWidgets('记账页类型分段条的转账选中色是语义蓝，与下方金额一致', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1000);
    addTearDown(tester.view.reset);

    final controller = await makeController();
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(home: const EntryDetailPage(initialAmount: 30)),
      ),
    );
    await tester.pumpAndSettle();

    // 选中项的文字色由调用点的 accentOf 提供；`entry_type_selected_*` 这个 Key
    // 只挂在当前选中项上，取到的就是分段条里那一份。
    Color? accentOf(String type) => tester
        .widget<Text>(find.byKey(Key('entry_type_selected_$type')))
        .style
        ?.color;

    expect(accentOf('expense'), veriSemanticFor(Brightness.light, veriExpense));

    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(accentOf('income'), veriSemanticFor(Brightness.light, veriIncome));

    await tester.tap(find.text('转账'));
    await tester.pumpAndSettle();

    // 转账用语义蓝，与下方的大金额（veriSemantic(context, veriBlue)）一致。
    expect(
      accentOf('transfer'),
      veriSemanticFor(Brightness.light, veriBlue),
      reason: '转账选中色应与本页下方金额用的是同一支语义蓝',
    );
  });

  testWidgets('快速记账返回静默取消且不落账', (tester) async {
    final controller = await makeController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      VeriFinScope(
        controller: controller,
        child: zhMaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const Key('open_entry'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EntryDetailPage(initialAmount: 30),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open_entry')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open_entry')), findsOneWidget);
    expect(find.text('保存修改？'), findsNothing);
    expect(controller.entries, isEmpty);
  });
}
