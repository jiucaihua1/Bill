import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaohe/app/app_theme.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('主题将设计令牌桥接给 anchored_menu：$brightness', () {
      final theme = buildVeriFinTheme(brightness);
      final menuTheme = theme.extension<AnchoredMenuThemeData>();
      final tokens = theme.extension<VeriStyleTokens>()!;

      expect(menuTheme, isNotNull);
      expect(menuTheme!.surfaceColor, tokens.raisedSurfaceColor);
      expect(menuTheme.borderColor, tokens.borderColor);
      expect(menuTheme.foregroundColor, tokens.inkColor);
      expect(menuTheme.selectedColor, theme.colorScheme.primary);
      expect(menuTheme.panelBorderRadius, BorderRadius.circular(veriRadiusXl));
      expect(
        menuTheme.itemBorderRadius,
        BorderRadius.circular(tokens.innerRadius),
      );
      expect(menuTheme.minWidth, 168);
    });
  }
}
