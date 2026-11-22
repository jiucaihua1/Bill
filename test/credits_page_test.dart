import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verifin/app/credits.dart';
import 'package:verifin/app/credits_avatar.dart';
import 'package:verifin/app/models.dart';
import 'package:verifin/pages/credits_page.dart';

import 'support/test_harness.dart';

const List<CreditsSupporter> _testSupporters = <CreditsSupporter>[
  CreditsSupporter('fixture-a'),
  CreditsSupporter('fixture-b', group: '特别鸣谢'),
];

const List<CreditsSupporter> _longNameSupporters = <CreditsSupporter>[
  CreditsSupporter('fixture-a'),
  CreditsSupporter('一位名字特别特别长的支持者朋友'),
  CreditsSupporter('fixture-b', handle: '@fixture-b'),
];

/// 从「我的」进设置页。
Future<void> _openSettings(WidgetTester tester) async {
  await tapBottomTab(tester, 3);
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

/// 把页面压进当前导航栈：这些用例只需要「页面处在真实 App 里」（有 scope 与
/// Feedback Host），不必每次都从设置页点进去。
Future<void> _pushPage(WidgetTester tester, Widget page) async {
  // 用根 Navigator：首屏是首页，`ProfilePage` 要切到「我的」才建出来。
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => page)));
  await tester.pumpAndSettle();
}

void main() {
  useTestDatabases();

  testWidgets('设置页「关于」组提供鸣谢入口并可进入名单页', (tester) async {
    await pumpApp(tester);
    await _openSettings(tester);
    await tester.scrollUntilVisible(find.text('鸣谢'), 200);
    await tester.ensureVisible(find.text('鸣谢'));
    await tester.pumpAndSettle();
    expect(find.text('鸣谢'), findsOneWidget);

    await tester.tap(find.text('鸣谢'));
    await tester.pumpAndSettle();

    expect(find.byType(CreditsPage), findsOneWidget);
  });

  testWidgets('分组为空时不渲染组标题，有分组时按标题分组', (tester) async {
    await pumpApp(tester);
    await _pushPage(
      tester,
      const CreditsPage(
        supporters: <CreditsSupporter>[
          CreditsSupporter('fixture-a'),
          CreditsSupporter('fixture-b'),
        ],
      ),
    );
    expect(find.text('特别鸣谢'), findsNothing);

    await _pushPage(tester, const CreditsPage(supporters: _testSupporters));
    expect(find.text('特别鸣谢'), findsOneWidget);
  });

  testWidgets('360dp 窄屏与长昵称下不溢出', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 852);
    addTearDown(tester.view.reset);
    await pumpApp(tester);
    await _pushPage(tester, const CreditsPage(supporters: _longNameSupporters));
    expect(tester.takeException(), isNull);
    expect(
      find.byType(CreditsAvatar),
      findsNWidgets(_longNameSupporters.length),
    );
  });

  testWidgets('英文界面与深色主题下文案与渲染正常', (tester) async {
    final controller = await pumpApp(tester);
    controller.setThemePreference(ThemePreference.dark);
    controller.setLocalePreference(LocalePreference.en);
    await tester.pumpAndSettle();

    await _pushPage(tester, const CreditsPage(supporters: _testSupporters));

    expect(find.text('Credits'), findsOneWidget);
    expect(find.textContaining('Veri Fin by LumiDesk'), findsOneWidget);
    expect(find.byType(CreditsAvatar), findsNWidgets(_testSupporters.length));
    expect(tester.takeException(), isNull);
  });
}
