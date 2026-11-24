import '../../l10n/app_localizations.dart';

/// 桌面小组件模板词表——**唯一来源**。
///
/// [key] 是发布契约：home_widget 共享存储、原生 Provider 与选择器都按它对齐，
/// 一经发布不得修改。新增模板必须同一批改完：本枚举、Kotlin 渲染分支、
/// `res/xml/<key>_widget_info.xml`、选择器预览布局与 `docs/dev/home-widgets.md`。
///
/// 模板与指标是 1:1 的：一个模板恰好展示一个指标、一种呈现方式，因此本项目
/// **不存在独立的指标词表**——桌面上显示的指标文案由原生 `strings.xml` 提供，
/// 应用内名称由 [name] 提供，两者由 `test/widget_string_parity_test.dart` 强制一致。
enum WidgetTemplate {
  quickEntry('quick_entry', 'QuickEntryWidgetProvider'),
  budget('budget', 'BudgetWidgetProvider'),
  trend('trend', 'TrendWidgetProvider'),
  netWorth('net_worth', 'NetWorthWidgetProvider'),
  dualMetric('dual_metric', 'DualMetricWidgetProvider');

  const WidgetTemplate(this.key, this.providerClassName);

  /// 线上契约键（`home_widget` 与原生共用的字符串标识）。
  final String key;

  /// 该模板的 Glance Provider 类名（`com.xiaohe.ledger` 包内）。
  final String providerClassName;

  /// 完整 Android 组件名，供 `HomeWidget.updateWidget` 使用。
  String get providerComponent => 'com.xiaohe.ledger.$providerClassName';

  static WidgetTemplate? fromKey(String? key) {
    if (key == null) return null;
    for (final template in values) {
      if (template.key == key) return template;
    }
    return null;
  }

  /// 应用内使用的规范名称；必须与 Android `values/strings.xml` 的同名资源一致。
  String name(AppLocalizations l10n) => switch (this) {
    WidgetTemplate.quickEntry => l10n.widgetTemplateQuickEntry,
    WidgetTemplate.budget => l10n.widgetTemplateBudget,
    WidgetTemplate.trend => l10n.widgetTemplateTrend,
    WidgetTemplate.netWorth => l10n.widgetTemplateNetWorth,
    WidgetTemplate.dualMetric => l10n.widgetTemplateDualMetric,
  };
}

/// 点击小部件主体时的跳转行为，每个桌面实例可独立开关。
enum WidgetTapAction {
  quickEntry('entry'),
  home('app'),
  stats('stats');

  const WidgetTapAction(this.key);

  final String key;

  static WidgetTapAction defaultFor(WidgetTemplate template) =>
      template == WidgetTemplate.quickEntry
      ? WidgetTapAction.home
      : WidgetTapAction.stats;

  static WidgetTapAction fromKey(String? key, {WidgetTemplate? template}) {
    for (final action in values) {
      if (action.key == key) return action;
    }
    return template == null
        ? WidgetTapAction.home
        : WidgetTapAction.defaultFor(template);
  }

  String label(AppLocalizations l10n) => switch (this) {
    WidgetTapAction.quickEntry => l10n.widgetTapQuickEntry,
    WidgetTapAction.home => l10n.widgetTapHome,
    WidgetTapAction.stats => l10n.widgetTapStats,
  };
}

/// 双栏（2×1）小部件可选指标：覆盖日/周/月收支、结余与净资产。
enum WidgetDualMetricChoice {
  todayExpense('today_expense'),
  weekExpense('week_expense'),
  monthExpense('month_expense'),
  todayIncome('today_income'),
  weekIncome('week_income'),
  monthIncome('month_income'),
  monthNet('month_net'),
  netAssets('net_assets');

  const WidgetDualMetricChoice(this.key);

  final String key;

  static const WidgetDualMetricChoice defaultLeft = weekExpense;
  static const WidgetDualMetricChoice defaultRight = todayExpense;

  static WidgetDualMetricChoice fromKey(
    String? key, {
    required WidgetDualMetricChoice fallback,
  }) {
    for (final choice in values) {
      if (choice.key == key) return choice;
    }
    return fallback;
  }

  String label(AppLocalizations l10n) => switch (this) {
    WidgetDualMetricChoice.todayExpense => l10n.metricTodayExpense,
    WidgetDualMetricChoice.weekExpense => l10n.metricWeekExpense,
    WidgetDualMetricChoice.monthExpense => l10n.metricMonthExpense,
    WidgetDualMetricChoice.todayIncome => l10n.metricTodayIncome,
    WidgetDualMetricChoice.weekIncome => l10n.metricWeekIncome,
    WidgetDualMetricChoice.monthIncome => l10n.metricMonthIncome,
    WidgetDualMetricChoice.monthNet => l10n.metricMonthNet,
    WidgetDualMetricChoice.netAssets => l10n.metricNetAssets,
  };
}

/// 单个桌面实例的外观。默认 [system]（跟随系统深浅色），可在配置页覆盖。
enum WidgetAppearance {
  system('system'),
  light('light'),
  dark('dark');

  const WidgetAppearance(this.key);

  /// 与原生共享存储一致的字符串标识。
  final String key;

  static const WidgetAppearance fallback = WidgetAppearance.system;

  static WidgetAppearance fromKey(String? key) {
    for (final appearance in values) {
      if (appearance.key == key) return appearance;
    }
    return fallback;
  }

  String label(AppLocalizations l10n) => switch (this) {
    WidgetAppearance.system => l10n.themeSystem,
    WidgetAppearance.light => l10n.themeLight,
    WidgetAppearance.dark => l10n.themeDark,
  };
}

enum WidgetTextSize {
  small,
  standard,
  large;

  String label(AppLocalizations l10n) => switch (this) {
    small => l10n.widgetTextSmall,
    standard => l10n.widgetTextStandard,
    large => l10n.widgetTextLarge,
  };
}

enum WidgetTextAlignment {
  start,
  center;

  String label(AppLocalizations l10n) => switch (this) {
    start => l10n.widgetTextStart,
    center => l10n.widgetTextCenter,
  };
}

enum WidgetTextColor {
  automatic,
  white,
  black,
  blue,
  green;

  String label(AppLocalizations l10n) => switch (this) {
    automatic => l10n.widgetTextAutomatic,
    white => l10n.widgetTextWhite,
    black => l10n.widgetTextBlack,
    blue => l10n.widgetTextBlue,
    green => l10n.widgetTextGreen,
  };
}

typedef WidgetTypography = ({
  WidgetTextSize size,
  WidgetTextAlignment alignment,
  WidgetTextColor color,
});

const defaultWidgetTypography = (
  size: WidgetTextSize.standard,
  alignment: WidgetTextAlignment.start,
  color: WidgetTextColor.automatic,
);

WidgetTypography decodeWidgetTypography(Map<Object?, Object?> fields) => (
  size:
      WidgetTextSize.values
          .where((size) => size.name == fields['textSize'])
          .firstOrNull ??
      defaultWidgetTypography.size,
  alignment:
      WidgetTextAlignment.values
          .where((alignment) => alignment.name == fields['textAlignment'])
          .firstOrNull ??
      defaultWidgetTypography.alignment,
  color:
      WidgetTextColor.values
          .where((color) => color.name == fields['textColor'])
          .firstOrNull ??
      defaultWidgetTypography.color,
);

Map<String, String> encodeWidgetTypography(WidgetTypography typography) => {
  'textSize': typography.size.name,
  'textAlignment': typography.alignment.name,
  'textColor': typography.color.name,
};

/// 趋势模板与净资产曲线固定的日历日窗口（以今天收尾）。
const int widgetChartDays = 30;
