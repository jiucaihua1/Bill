import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/app_theme.dart';
import 'package:xiaohe/app/models.dart';

void main() {
  test('主题色偏好可编码、解码并强制使用不透明颜色', () {
    const source = ThemeColorPreference(
      mode: ThemeColorMode.custom,
      customColorValue: 0x00123456,
    );

    final restored = ThemeColorPreference.fromStorage(source.encode());

    expect(restored.mode, ThemeColorMode.custom);
    expect(restored.customColorValue, 0xFF123456);
  });

  test('非法主题色偏好回退到默认主题色', () {
    expect(
      ThemeColorPreference.fromStorage('{"mode":"custom","color":"x"}'),
      ThemeColorPreference.defaultValue,
    );
    expect(
      ThemeColorPreference.fromStorage('not-json'),
      ThemeColorPreference.defaultValue,
    );
  });

  test('默认主题风格为晨间手账，经典蓝保留 Veri Royal，自定义主题色精确使用用户颜色', () {
    final warmTheme = buildVeriFinTheme(Brightness.light);
    final classicTheme = buildVeriFinTheme(
      Brightness.light,
      colorPreference: const ThemeColorPreference(
        mode: ThemeColorMode.defaultColor,
        customColorValue: 0xFF346EDB,
      ),
    );
    final hyperTheme = buildVeriFinTheme(
      Brightness.light,
      colorPreference: const ThemeColorPreference(
        mode: ThemeColorMode.hyperCrisp,
        customColorValue: 0xFF2F5BFF,
      ),
    );
    final obsidianTheme = buildVeriFinTheme(
      Brightness.dark,
      colorPreference: const ThemeColorPreference(
        mode: ThemeColorMode.obsidianBento,
        customColorValue: 0xFFF0A32F,
      ),
    );
    final theme = buildVeriFinTheme(
      Brightness.light,
      colorPreference: const ThemeColorPreference(
        mode: ThemeColorMode.custom,
        customColorValue: 0xFFB3261E,
      ),
    );

    expect(warmTheme.colorScheme.primary, const Color(0xFF2B6B56));
    expect(classicTheme.colorScheme.primary, veriRoyal);
    expect(hyperTheme.colorScheme.primary, const Color(0xFF2F5BFF));
    expect(obsidianTheme.colorScheme.primary, const Color(0xFFF0A32F));
    expect(theme.colorScheme.primary, const Color(0xFFB3261E));
    expect(theme.colorScheme.onPrimary.a, 1);
  });

  test('构成图调色盘统一为深色档并固定白字', () {
    final colors = veriChartPaletteFor(veriRoyal);

    expect(colors.length, 10);
    expect(colors.toSet().length, colors.length);
    expect(colors.every((color) => color.a == 1), isTrue);
    // 所有分类色的相对亮度都压在 0.22 附近：白字可读，且不会出现深浅混排。
    for (final color in colors) {
      expect(color.computeLuminance(), inInclusiveRange(0.18, 0.27));
      expect(
        ThemeData.estimateBrightnessForColor(color),
        Brightness.dark,
        reason: '分类色应为深色档，环内统一使用白字',
      );
    }
  });

  test('自定义主题色的明暗前景保持可读', () {
    const seed = Color(0xFFB3261E);
    final theme = buildVeriFinTheme(
      Brightness.light,
      colorPreference: const ThemeColorPreference(
        mode: ThemeColorMode.custom,
        customColorValue: 0xFFB3261E,
      ),
    );

    expect(theme.colorScheme.primary, seed);
    expect(theme.colorScheme.onPrimary, Colors.white);
  });
}
