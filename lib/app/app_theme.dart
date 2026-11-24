import 'package:anchored_menu/anchored_menu.dart';
import 'package:flutter/material.dart';

import 'models.dart';

// 画布与内容基色：一律实体填色，不模拟玻璃折射或模糊。
const Color veriCanvasLight = Color(0xFFF6F2EA);
const Color veriCanvasDark = Color(0xFF14120F);

/// 内容卡片（与资产封面）的深色基色。
const Color veriCardSurfaceDark = Color(0xFF201C18);

/// 默认卡片圆角半径（具体风格由 [VeriStyleTokens.cardRadius] 驱动）。
const double veriCardRadius = 18;

/// 内容卡片与资产封面共用的实体基色。
Color veriContentSurfaceColor(Brightness brightness) =>
    brightness == Brightness.dark ? veriCardSurfaceDark : veriSurfaceLight;

/// 浮动元件（底部导航、快捷按钮、锚点菜单）的实体基色。
Color veriElevatedSurfaceColor(Brightness brightness) =>
    brightness == Brightness.dark ? veriSurfaceRaisedDark : veriSurfaceLight;

/// 深色下高于卡片的浮动表面色。
const Color veriSurfaceRaisedDark = Color(0xFF2E2822);

const Color veriMint = Color(0xFF34DBCB);
const Color veriCyan = Color(0xFF34C2DB);
const Color veriBlue = Color(0xFF3498DB);
const Color veriRoyal = Color(0xFF346EDB);
const Color veriNavigationUnselected = Color(0xFF9C968E);
const Color veriIndigo = Color(0xFF3445DB);
const Color veriInk = Color(0xFF221E1A);
const Color veriLine = Color(0xFFE4DCCE);
const Color veriExpense = Color(0xFFE84D6A);
const Color veriIncome = Color(0xFF12B8A6);
const Color veriWarning = Color(0xFFFFB33E);
// 构成图（分类 / 账户占比）的分类色。
const Color veriChartOrange = Color(0xFFE8894A);
const Color veriChartPink = Color(0xFFE36A9A);
const Color veriChartViolet = Color(0xFF9B7BE8);
const Color veriChartSlate = Color(0xFF8C99A8);
// 浅色底语义色变体（AA 对比度 >= 4.5:1）。
const Color veriExpenseOnLight = Color(0xFFC2334F);
const Color veriIncomeOnLight = Color(0xFF0B7A6C);
const Color veriBlueOnLight = Color(0xFF1F6FC4);
const Color veriWarningOnLight = Color(0xFF8A5A00);

/// 每套视觉风格的完整材质、圆角与语义色令牌。
@immutable
class VeriStyleTokens extends ThemeExtension<VeriStyleTokens> {
  const VeriStyleTokens({
    required this.canvasColor,
    required this.cardColor,
    required this.surfaceAltColor,
    required this.raisedSurfaceColor,
    required this.borderColor,
    required this.inkColor,
    required this.expenseColor,
    required this.incomeColor,
    required this.transferColor,
    required this.warningColor,
    required this.cardRadius,
    required this.innerRadius,
    required this.buttonRadius,
    required this.pillHasBorder,
    required this.cardShadow,
  });

  final Color canvasColor;
  final Color cardColor;
  final Color surfaceAltColor;
  final Color raisedSurfaceColor;
  final Color borderColor;
  final Color inkColor;
  final Color expenseColor;
  final Color incomeColor;
  final Color transferColor;
  final Color warningColor;
  final double cardRadius;
  final double innerRadius;
  final double buttonRadius;
  final bool pillHasBorder;
  final List<BoxShadow> cardShadow;

  static VeriStyleTokens of(BuildContext context) {
    final ext = Theme.of(context).extension<VeriStyleTokens>();
    if (ext != null) return ext;
    return forMode(Theme.of(context).brightness, ThemeColorMode.warmPaper);
  }

  static VeriStyleTokens? maybeOf(BuildContext context) =>
      Theme.of(context).extension<VeriStyleTokens>();

  static VeriStyleTokens forMode(Brightness brightness, ThemeColorMode mode) {
    final isDark = brightness == Brightness.dark;
    switch (mode) {
      case ThemeColorMode.warmPaper:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF14120F),
                cardColor: const Color(0xFF201C18),
                surfaceAltColor: const Color(0xFF2A241E),
                raisedSurfaceColor: const Color(0xFF2E2822),
                borderColor: Colors.white.withValues(alpha: 0.085),
                inkColor: const Color(0xFFF2ECE3),
                expenseColor: const Color(0xFFEE6C57),
                incomeColor: const Color(0xFF41B996),
                transferColor: const Color(0xFF5B9BD5),
                warningColor: const Color(0xFFFFB33E),
                cardRadius: 20,
                innerRadius: 14,
                buttonRadius: 16,
                pillHasBorder: false,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFF6F2EA),
                cardColor: Color(0xFFFFFCF6),
                surfaceAltColor: Color(0xFFEFE9DC),
                raisedSurfaceColor: Color(0xFFFFFDF9),
                borderColor: Color(0xFFE5DDD0),
                inkColor: Color(0xFF221E1A),
                expenseColor: Color(0xFFC54834),
                incomeColor: Color(0xFF1C8266),
                transferColor: Color(0xFF2E6B9E),
                warningColor: Color(0xFF9E6100),
                cardRadius: 20,
                innerRadius: 14,
                buttonRadius: 16,
                pillHasBorder: false,
                cardShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x0D483824),
                    blurRadius: 14,
                    offset: Offset(0, 4),
                  ),
                ],
              );
      case ThemeColorMode.matchaZen:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF0E1512),
                cardColor: const Color(0xFF16201B),
                surfaceAltColor: const Color(0xFF1E2B24),
                raisedSurfaceColor: const Color(0xFF23322A),
                borderColor: const Color(0xFF2F4439),
                inkColor: const Color(0xFFEAF3EE),
                expenseColor: const Color(0xFFEB7352),
                incomeColor: const Color(0xFF39C698),
                transferColor: const Color(0xFF59A5D8),
                warningColor: const Color(0xFFE8B048),
                cardRadius: 18,
                innerRadius: 12,
                buttonRadius: 14,
                pillHasBorder: true,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFECF3ED),
                cardColor: Color(0xFFFAFCFA),
                surfaceAltColor: Color(0xFFE2ECE4),
                raisedSurfaceColor: Color(0xFFFFFFFF),
                borderColor: Color(0xFFD0DFD3),
                inkColor: Color(0xFF16241C),
                expenseColor: Color(0xFFC94F2E),
                incomeColor: Color(0xFF177D5E),
                transferColor: Color(0xFF266D9E),
                warningColor: Color(0xFF9C6408),
                cardRadius: 18,
                innerRadius: 12,
                buttonRadius: 14,
                pillHasBorder: true,
                cardShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x0916241C),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              );
      case ThemeColorMode.sakuraMist:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF171014),
                cardColor: const Color(0xFF23181E),
                surfaceAltColor: const Color(0xFF2E2027),
                raisedSurfaceColor: const Color(0xFF35252D),
                borderColor: Colors.white.withValues(alpha: 0.085),
                inkColor: const Color(0xFFF7ECEF),
                expenseColor: const Color(0xFFF06779),
                incomeColor: const Color(0xFF3EC4A4),
                transferColor: const Color(0xFF7B9CF0),
                warningColor: const Color(0xFFF5B14C),
                cardRadius: 24,
                innerRadius: 16,
                buttonRadius: 20,
                pillHasBorder: false,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFF8EFF2),
                cardColor: Color(0xFFFFFAFB),
                surfaceAltColor: Color(0xFFF2E3E8),
                raisedSurfaceColor: Color(0xFFFFFCFD),
                borderColor: Color(0xFFE8D5DC),
                inkColor: Color(0xFF281920),
                expenseColor: Color(0xFFC83C52),
                incomeColor: Color(0xFF18826B),
                transferColor: Color(0xFF4768B8),
                warningColor: Color(0xFFA16207),
                cardRadius: 24,
                innerRadius: 16,
                buttonRadius: 20,
                pillHasBorder: false,
                cardShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x0D6B2943),
                    blurRadius: 16,
                    offset: Offset(0, 5),
                  ),
                ],
              );
      case ThemeColorMode.caramelLatte:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF17120E),
                cardColor: const Color(0xFF231B15),
                surfaceAltColor: const Color(0xFF2E241C),
                raisedSurfaceColor: const Color(0xFF362A20),
                borderColor: const Color(0xFF433529),
                inkColor: const Color(0xFFF5ECE3),
                expenseColor: const Color(0xFFEB6B52),
                incomeColor: const Color(0xFF46B88D),
                transferColor: const Color(0xFF6BA0D6),
                warningColor: const Color(0xFFF2AE46),
                cardRadius: 16,
                innerRadius: 12,
                buttonRadius: 14,
                pillHasBorder: true,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFF2EAE1),
                cardColor: Color(0xFFFFFBF7),
                surfaceAltColor: Color(0xFFEADFD2),
                raisedSurfaceColor: Color(0xFFFFFDFB),
                borderColor: Color(0xFFDCCEC0),
                inkColor: Color(0xFF291D14),
                expenseColor: Color(0xFFC4452B),
                incomeColor: Color(0xFF237A5A),
                transferColor: Color(0xFF366C9C),
                warningColor: Color(0xFF9A5B06),
                cardRadius: 16,
                innerRadius: 12,
                buttonRadius: 14,
                pillHasBorder: true,
                cardShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x0C4A2F1B),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              );
      case ThemeColorMode.hyperCrisp:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF090C12),
                cardColor: const Color(0xFF141923),
                surfaceAltColor: const Color(0xFF1A212E),
                raisedSurfaceColor: const Color(0xFF1E2636),
                borderColor: Colors.white.withValues(alpha: 0.075),
                inkColor: const Color(0xFFF2F5FA),
                expenseColor: const Color(0xFFFB5C79),
                incomeColor: const Color(0xFF27C6AA),
                transferColor: const Color(0xFF5D82FF),
                warningColor: const Color(0xFFFFB33E),
                cardRadius: 24,
                innerRadius: 15,
                buttonRadius: 20,
                pillHasBorder: false,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFEDF2FA),
                cardColor: Color(0xFFFFFFFF),
                surfaceAltColor: Color(0xFFE8EFF9),
                raisedSurfaceColor: Color(0xFFFFFFFF),
                borderColor: Color(0xFFDDE6F4),
                inkColor: Color(0xFF101828),
                expenseColor: Color(0xFFD62E4E),
                incomeColor: Color(0xFF0A8570),
                transferColor: Color(0xFF2454FF),
                warningColor: Color(0xFF9A6000),
                cardRadius: 24,
                innerRadius: 15,
                buttonRadius: 20,
                pillHasBorder: false,
                cardShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x0E142850),
                    blurRadius: 20,
                    offset: Offset(0, 5),
                  ),
                ],
              );
      case ThemeColorMode.obsidianBento:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF08090B),
                cardColor: const Color(0xFF121419),
                surfaceAltColor: const Color(0xFF1A1D24),
                raisedSurfaceColor: const Color(0xFF20242D),
                borderColor: Colors.white.withValues(alpha: 0.14),
                inkColor: const Color(0xFFF5F7FA),
                expenseColor: const Color(0xFFF2576E),
                incomeColor: const Color(0xFF29C29D),
                transferColor: const Color(0xFF60A5FA),
                warningColor: const Color(0xFFF0A32F),
                cardRadius: 12,
                innerRadius: 8,
                buttonRadius: 10,
                pillHasBorder: true,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFE9ECF1),
                cardColor: Color(0xFFFFFFFF),
                surfaceAltColor: Color(0xFFF1F3F7),
                raisedSurfaceColor: Color(0xFFFFFFFF),
                borderColor: Color(0xFFCBD2DD),
                inkColor: Color(0xFF111317),
                expenseColor: Color(0xFFC82C44),
                incomeColor: Color(0xFF0B7D66),
                transferColor: Color(0xFF235CB8),
                warningColor: Color(0xFF965D00),
                cardRadius: 12,
                innerRadius: 8,
                buttonRadius: 10,
                pillHasBorder: true,
                cardShadow: <BoxShadow>[],
              );
      case ThemeColorMode.defaultColor:
      case ThemeColorMode.system:
      case ThemeColorMode.custom:
        return isDark
            ? VeriStyleTokens(
                canvasColor: const Color(0xFF101318),
                cardColor: const Color(0xFF1A1F27),
                surfaceAltColor: const Color(0xFF151A22),
                raisedSurfaceColor: const Color(0xFF232A35),
                borderColor: Colors.white.withValues(alpha: 0.08),
                inkColor: const Color(0xFFF0F3F8),
                expenseColor: veriExpense,
                incomeColor: veriIncome,
                transferColor: veriBlue,
                warningColor: veriWarning,
                cardRadius: 18,
                innerRadius: 12,
                buttonRadius: 14,
                pillHasBorder: false,
                cardShadow: const <BoxShadow>[],
              )
            : const VeriStyleTokens(
                canvasColor: Color(0xFFF3F5F8),
                cardColor: Color(0xFFFFFFFF),
                surfaceAltColor: Color(0xFFF5F8FC),
                raisedSurfaceColor: Color(0xFFFFFFFF),
                borderColor: Color(0xFFE1E8F1),
                inkColor: Color(0xFF151922),
                expenseColor: veriExpenseOnLight,
                incomeColor: veriIncomeOnLight,
                transferColor: veriBlueOnLight,
                warningColor: veriWarningOnLight,
                cardRadius: 18,
                innerRadius: 12,
                buttonRadius: 14,
                pillHasBorder: false,
                cardShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x08151922),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              );
    }
  }

  @override
  VeriStyleTokens copyWith({
    Color? canvasColor,
    Color? cardColor,
    Color? surfaceAltColor,
    Color? raisedSurfaceColor,
    Color? borderColor,
    Color? inkColor,
    Color? expenseColor,
    Color? incomeColor,
    Color? transferColor,
    Color? warningColor,
    double? cardRadius,
    double? innerRadius,
    double? buttonRadius,
    bool? pillHasBorder,
    List<BoxShadow>? cardShadow,
  }) => VeriStyleTokens(
    canvasColor: canvasColor ?? this.canvasColor,
    cardColor: cardColor ?? this.cardColor,
    surfaceAltColor: surfaceAltColor ?? this.surfaceAltColor,
    raisedSurfaceColor: raisedSurfaceColor ?? this.raisedSurfaceColor,
    borderColor: borderColor ?? this.borderColor,
    inkColor: inkColor ?? this.inkColor,
    expenseColor: expenseColor ?? this.expenseColor,
    incomeColor: incomeColor ?? this.incomeColor,
    transferColor: transferColor ?? this.transferColor,
    warningColor: warningColor ?? this.warningColor,
    cardRadius: cardRadius ?? this.cardRadius,
    innerRadius: innerRadius ?? this.innerRadius,
    buttonRadius: buttonRadius ?? this.buttonRadius,
    pillHasBorder: pillHasBorder ?? this.pillHasBorder,
    cardShadow: cardShadow ?? this.cardShadow,
  );

  @override
  VeriStyleTokens lerp(ThemeExtension<VeriStyleTokens>? other, double t) {
    if (other is! VeriStyleTokens) return this;
    return VeriStyleTokens(
      canvasColor: Color.lerp(canvasColor, other.canvasColor, t)!,
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      surfaceAltColor: Color.lerp(surfaceAltColor, other.surfaceAltColor, t)!,
      raisedSurfaceColor: Color.lerp(
        raisedSurfaceColor,
        other.raisedSurfaceColor,
        t,
      )!,
      borderColor: Color.lerp(borderColor, other.borderColor, t)!,
      inkColor: Color.lerp(inkColor, other.inkColor, t)!,
      expenseColor: Color.lerp(expenseColor, other.expenseColor, t)!,
      incomeColor: Color.lerp(incomeColor, other.incomeColor, t)!,
      transferColor: Color.lerp(transferColor, other.transferColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      cardRadius: t < 0.5 ? cardRadius : other.cardRadius,
      innerRadius: t < 0.5 ? innerRadius : other.innerRadius,
      buttonRadius: t < 0.5 ? buttonRadius : other.buttonRadius,
      pillHasBorder: t < 0.5 ? pillHasBorder : other.pillHasBorder,
      cardShadow: t < 0.5 ? cardShadow : other.cardShadow,
    );
  }
}

/// 语义色在当前主题风格与明暗下的实际取值。
Color veriSemantic(BuildContext context, Color semanticColor) {
  final tokens = VeriStyleTokens.maybeOf(context);
  if (tokens != null) {
    return switch (semanticColor) {
      veriExpense => tokens.expenseColor,
      veriIncome => tokens.incomeColor,
      veriBlue => tokens.transferColor,
      veriWarning => tokens.warningColor,
      _ => semanticColor,
    };
  }
  return veriSemanticFor(Theme.of(context).brightness, semanticColor);
}

/// [veriSemantic] 的无 `BuildContext` 版本，供纯取色函数使用。
Color veriSemanticFor(Brightness brightness, Color semanticColor) {
  if (brightness == Brightness.dark) {
    return semanticColor;
  }
  return switch (semanticColor) {
    veriExpense => veriExpenseOnLight,
    veriIncome => veriIncomeOnLight,
    veriBlue => veriBlueOnLight,
    veriWarning => veriWarningOnLight,
    _ => semanticColor,
  };
}

const List<Color> _veriChartPaletteTail = <Color>[
  veriBlue,
  veriCyan,
  veriMint,
  veriWarning,
  veriChartOrange,
  veriChartPink,
  veriChartViolet,
  veriIndigo,
  veriChartSlate,
];

/// 把分类色统一压到深色档（相对亮度约 0.22）。
Color _veriChartTone(Color color) {
  final hsl = HSLColor.fromColor(color);
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 24; i++) {
    final mid = (low + high) / 2;
    final luminance = hsl.withLightness(mid).toColor().computeLuminance();
    if (luminance < 0.22) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return hsl.withLightness((low + high) / 2).toColor();
}

/// 构成图（分类 / 账户占比）的 10 色分类调色盘。
List<Color> veriChartPaletteFor(Color primary) => <Color>[
  _veriChartTone(primary),
  for (final color in _veriChartPaletteTail) _veriChartTone(color),
];

/// [veriChartPaletteFor] 的主题入口；分类图与资产汇总共用同一套顺序。
List<Color> veriChartPalette(BuildContext context) =>
    veriChartPaletteFor(Theme.of(context).colorScheme.primary);

const Color veriSurfaceLight = Color(0xFFFFFFFF);
const Color veriSurfaceDark = Color(0xFF0E1117);
const Color veriSurfaceAltLight = Color(0xFFF5F8FC);
const Color veriSurfaceAltDark = Color(0xFF151A22);
const double veriRadiusSm = 8;
const double veriRadiusMd = 14;
const double veriRadiusLg = 18;
const double veriRadiusXl = 24;
const double veriHeaderHeight = 56;
const double veriPageMaxWidth = 440;

Color _onCustomPrimary(Color color) =>
    ThemeData.estimateBrightnessForColor(color) == Brightness.light
    ? Colors.black
    : Colors.white;

Color _primaryForMode(Brightness brightness, ThemeColorPreference pref) {
  final isDark = brightness == Brightness.dark;
  return switch (pref.mode) {
    ThemeColorMode.warmPaper =>
      isDark ? const Color(0xFF4DA889) : const Color(0xFF2B6B56),
    ThemeColorMode.matchaZen =>
      isDark ? const Color(0xFF47C496) : const Color(0xFF1F6E58),
    ThemeColorMode.sakuraMist =>
      isDark ? const Color(0xFFE87A9E) : const Color(0xFFA83B5E),
    ThemeColorMode.caramelLatte =>
      isDark ? const Color(0xFFD68D5E) : const Color(0xFF8C4A27),
    ThemeColorMode.hyperCrisp =>
      isDark ? const Color(0xFF5D82FF) : const Color(0xFF2454FF),
    ThemeColorMode.obsidianBento =>
      isDark ? const Color(0xFFF0A32F) : const Color(0xFF181B22),
    ThemeColorMode.defaultColor => veriRoyal,
    ThemeColorMode.system => veriRoyal,
    ThemeColorMode.custom => Color(pref.customColorValue),
  };
}

class _AndroidPageTransitionsBuilder
    extends FadeForwardsPageTransitionsBuilder {
  const _AndroidPageTransitionsBuilder();

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

ThemeData buildVeriFinTheme(
  Brightness brightness, {
  ThemeColorPreference colorPreference = ThemeColorPreference.defaultValue,
}) {
  final isDark = brightness == Brightness.dark;
  final tokens = VeriStyleTokens.forMode(brightness, colorPreference.mode);
  final useSystemColors = colorPreference.mode == ThemeColorMode.system;
  final useExactPrimary = !useSystemColors;
  final seedColor = _primaryForMode(brightness, colorPreference);
  final seedScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    primary: useExactPrimary ? seedColor : null,
    onPrimary: useExactPrimary
        ? (colorPreference.mode == ThemeColorMode.obsidianBento && isDark
              ? const Color(0xFF111317)
              : colorPreference.mode == ThemeColorMode.warmPaper && isDark
              ? const Color(0xFF091712)
              : _onCustomPrimary(seedColor))
        : null,
  );
  final canvas = tokens.canvasColor;
  final colorScheme = seedScheme.copyWith(
    surface: canvas,
    surfaceContainerLow: tokens.surfaceAltColor,
    surfaceContainerHighest: tokens.surfaceAltColor,
    onSurface: tokens.inkColor,
    outlineVariant: tokens.borderColor,
  );

  final baseTheme = ThemeData(
    useMaterial3: true,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...const PageTransitionsTheme().builders,
        TargetPlatform.android: const _AndroidPageTransitionsBuilder(),
      },
    ),
    brightness: brightness,
    colorScheme: colorScheme,
    useSystemColors: useSystemColors,
    scaffoldBackgroundColor: canvas,
    fontFamily: 'Roboto',
    visualDensity: VisualDensity.compact,
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.cardColor,
      surfaceTintColor: Colors.transparent,
      shadowColor: colorScheme.shadow,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.cardRadius),
        side: BorderSide(color: tokens.borderColor),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.borderColor,
      thickness: 0.8,
      space: 1,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: seedScheme.primary,
        foregroundColor: seedScheme.onPrimary,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.buttonRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(48, 44),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: seedScheme.primary,
      foregroundColor: seedScheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(tokens.buttonRadius)),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tokens.surfaceAltColor,
      selectedColor: seedScheme.primary.withValues(alpha: 0.14),
      secondarySelectedColor: seedScheme.primary.withValues(alpha: 0.14),
      labelStyle: TextStyle(color: tokens.inkColor, fontSize: 12),
      secondaryLabelStyle: TextStyle(color: tokens.inkColor, fontSize: 12),
      side: BorderSide(color: tokens.borderColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.innerRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surfaceAltColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.innerRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.innerRadius),
        borderSide: BorderSide(color: seedScheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.innerRadius),
        borderSide: BorderSide(color: tokens.expenseColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.innerRadius),
        borderSide: BorderSide(color: tokens.expenseColor, width: 1.4),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.innerRadius),
        borderSide: BorderSide.none,
      ),
    ),
  );

  return baseTheme.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      tokens,
      AnchoredMenuThemeData(
        surfaceColor: tokens.raisedSurfaceColor,
        borderColor: tokens.borderColor,
        foregroundColor: tokens.inkColor,
        selectedColor: colorScheme.primary,
        panelBorderRadius: BorderRadius.circular(veriRadiusXl),
        itemBorderRadius: BorderRadius.circular(tokens.innerRadius),
        minWidth: 168,
      ),
    ],
    textTheme: baseTheme.textTheme.copyWith(
      displayLarge: baseTheme.textTheme.displayLarge?.copyWith(
        fontSize: 38,
        height: 1.05,
        letterSpacing: 0,
      ),
      displayMedium: baseTheme.textTheme.displayMedium?.copyWith(
        fontSize: 32,
        height: 1.08,
        letterSpacing: 0,
      ),
      displaySmall: baseTheme.textTheme.displaySmall?.copyWith(
        fontSize: 26,
        height: 1.12,
        letterSpacing: 0,
      ),
      headlineMedium: baseTheme.textTheme.headlineMedium?.copyWith(
        fontSize: 21,
        height: 1.18,
        letterSpacing: 0,
      ),
      headlineSmall: baseTheme.textTheme.headlineSmall?.copyWith(
        fontSize: 19,
        height: 1.2,
        letterSpacing: 0,
      ),
      titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
        fontSize: 17,
        height: 1.25,
        letterSpacing: 0,
      ),
      titleMedium: baseTheme.textTheme.titleMedium?.copyWith(
        fontSize: 14,
        height: 1.25,
        letterSpacing: 0,
      ),
      titleSmall: baseTheme.textTheme.titleSmall?.copyWith(
        fontSize: 13,
        height: 1.25,
        letterSpacing: 0,
      ),
      bodyLarge: baseTheme.textTheme.bodyLarge?.copyWith(
        fontSize: 14,
        height: 1.35,
        letterSpacing: 0,
      ),
      bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(
        fontSize: 13,
        height: 1.35,
        letterSpacing: 0,
      ),
      bodySmall: baseTheme.textTheme.bodySmall?.copyWith(
        fontSize: 12,
        height: 1.35,
        letterSpacing: 0,
      ),
      labelLarge: baseTheme.textTheme.labelLarge?.copyWith(
        fontSize: 12,
        height: 1.25,
        letterSpacing: 0,
      ),
      labelMedium: baseTheme.textTheme.labelMedium?.copyWith(
        fontSize: 11,
        height: 1.25,
        letterSpacing: 0,
      ),
      labelSmall: baseTheme.textTheme.labelSmall?.copyWith(
        fontSize: 10,
        height: 1.2,
        letterSpacing: 0,
      ),
    ),
  );
}
