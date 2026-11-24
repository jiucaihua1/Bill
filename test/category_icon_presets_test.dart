import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/auto_bill_overlay.dart';
import 'package:xiaohe/app/category_icon_presets.dart';
import 'package:xiaohe/app/category_icon_theme.dart';
import 'package:xiaohe/app/common_widgets.dart';
import 'package:xiaohe/app/icon_catalog.dart';

void main() {
  test('分类图标预设 SVG 资源与映射完整且安全', () {
    expect(presetKeyToEmoji, hasLength(68));

    final lineOnDisk = Directory('assets/category_icons/line')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.svg'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();
    final coloredOnDisk = Directory('assets/category_icons/colored')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.svg'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .toSet();

    expect(lineOnDisk, hasLength(68));
    expect(coloredOnDisk, hasLength(68));

    for (final key in presetKeyToEmoji.keys) {
      final linePath = categoryPresetSvgAsset(CategoryIconPreset.line, key)!;
      final coloredPath = categoryPresetSvgAsset(
        CategoryIconPreset.colored,
        key,
      )!;
      expect(lineOnDisk, contains(linePath), reason: linePath);
      expect(coloredOnDisk, contains(coloredPath), reason: coloredPath);

      for (final path in <String>[linePath, coloredPath]) {
        final svg = File(path).readAsStringSync();
        expect(svg, contains('viewBox='), reason: path);
        expect(svg, isNot(contains('<script')), reason: path);
        expect(svg, isNot(contains('<image')), reason: path);
        expect(svg, isNot(contains('<text')), reason: path);
      }
      expect(categoryPresetEmoji(key).trim(), isNotEmpty, reason: key);
    }

    for (final code in categoryIconCodes) {
      final resolved = resolveCategoryPresetKey(iconCode: code);
      expect(presetKeyToEmoji.containsKey(resolved), isTrue, reason: code);
    }

    for (final entry in categoryNameToPresetKey.entries) {
      expect(
        presetKeyToEmoji.containsKey(entry.value),
        isTrue,
        reason: entry.key,
      );
      expect(
        resolveCategoryPresetKey(iconCode: 'category', categoryName: entry.key),
        entry.value,
      );
    }

    expect(
      resolveCategoryPresetKey(iconCode: 'dining', categoryName: '早餐'),
      'breakfast',
    );
    expect(
      resolveCategoryPresetKey(iconCode: 'redpacket', categoryName: '收红包'),
      'redpacket_in',
    );
  });

  testWidgets('旧内置预设迁移为彩色，分类图标可切换为线性和 Emoji', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('verifin_preset_test_');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => tempDir.path,
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    final themes = CategoryIconThemes(logger: null);
    final presetFile = File('${tempDir.path}/category-icon-preset-v1')
      ..writeAsStringSync('builtin');

    Future<void> pumpBox({
      String iconCode = 'dining',
      String? categoryName = '早餐',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: CategoryIconThemeScope(
            themes: themes,
            child: Scaffold(
              body: Center(
                child: CategoryIconBox(
                  iconCode: iconCode,
                  categoryName: categoryName,
                  color: Colors.teal,
                  size: 36,
                ),
              ),
            ),
          ),
        ),
      );
    }

    await tester.runAsync(themes.restore);
    await pumpBox();
    expect(presetFile.readAsStringSync(), 'colored');
    expect(themes.preset, CategoryIconPreset.colored);
    expect(
      AutoBillReviewData({'categoryIconPreset': 'builtin'}).categoryIconPreset,
      CategoryIconPreset.colored,
    );
    expect(find.byType(SvgPicture), findsOneWidget);

    await tester.runAsync(() => themes.selectPreset(CategoryIconPreset.line));
    await pumpBox();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byType(Icon), findsNothing);

    await tester.runAsync(
      () => themes.selectPreset(CategoryIconPreset.colored),
    );
    await pumpBox();
    expect(find.byType(SvgPicture), findsOneWidget);

    await tester.runAsync(() => themes.selectPreset(CategoryIconPreset.emoji));
    expect(
      AutoBillReviewData({
        'categoryIconPreset': themes.preset.name,
      }).categoryIconPreset,
      CategoryIconPreset.emoji,
    );
    await pumpBox();
    expect(find.text('🍳'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);

    themes.dispose();
  });
}
