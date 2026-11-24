import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_theme.dart';
import '../app/auto_bill_overlay.dart';
import '../app/common_widgets.dart';
import '../app/feedback.dart';
import '../app/platform_bridge.dart';
import '../app/veri_fin_scope.dart';
import '../l10n/app_localizations.dart';
import 'auto_confirm_sheet.dart';
import 'capture_entry.dart';

typedef _CapturePlatform = ({
  String id,
  String name,
  String hint,
  IconData icon,
});

List<_CapturePlatform> _platforms(AppLocalizations l10n) => [
  (
    id: 'wechat',
    name: l10n.autoSettingsWeChat,
    hint: l10n.autoSettingsWeChatHint,
    icon: Icons.chat_outlined,
  ),
  (
    id: 'alipay',
    name: l10n.autoSettingsAlipay,
    hint: l10n.autoSettingsAlipayHint,
    icon: Icons.payment_outlined,
  ),
  (
    id: 'jd',
    name: l10n.autoSettingsJd,
    hint: l10n.autoSettingsJdHint,
    icon: Icons.shopping_bag_outlined,
  ),
  (
    id: 'pdd',
    name: l10n.autoSettingsPdd,
    hint: l10n.autoSettingsPddHint,
    icon: Icons.shopping_cart_outlined,
  ),
];

/// 自动记账配置页：
/// 后台总开关、采集通道状态、适配平台开关以及只读识别预览。
class AutoBookkeepingPage extends StatefulWidget {
  const AutoBookkeepingPage({super.key});

  @override
  State<AutoBookkeepingPage> createState() => _AutoBookkeepingPageState();
}

class _AutoBookkeepingPageState extends State<AutoBookkeepingPage>
    with WidgetsBindingObserver {
  AutoCapturePermissionStatus _status =
      const AutoCapturePermissionStatus.empty();
  bool _loading = true;
  final Map<String, bool> _enabledPlatforms = <String, bool>{
    'wechat': true,
    'alipay': true,
    'ccb': false,
    'jd': true,
    'pdd': true,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadAll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshStatus());
    }
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final status = await AppCaptureBridge.getAutoCaptureStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      for (final id in _enabledPlatforms.keys) {
        _enabledPlatforms[id] =
            prefs.getBool('verifin.auto_capture.app.$id') ?? (id != 'ccb');
      }
      _loading = false;
    });
  }

  Future<void> _refreshStatus() async {
    final status = await AppCaptureBridge.getAutoCaptureStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _reconnectNotificationListener() async {
    final requested =
        await AppCaptureBridge.reconnectAutoNotificationListener();
    if (requested) {
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    if (!mounted) return;
    await _refreshStatus();
    if (!mounted || _status.notificationConnected) return;
    unawaited(
      VeriFeedbackHost.of(context).showMessage(
        message: AppLocalizations.of(context).autoCaptureReconnectPending,
        tone: VeriFeedbackTone.warning,
      ),
    );
  }

  Future<void> _toggleAutoEnabled(bool value) async {
    await AppCaptureBridge.setAutoBookkeepingEnabled(
      value,
      summary: autoBookkeepingNotificationSummary(VeriFinScope.of(context)),
    );
    await _refreshStatus();
  }

  Future<void> _togglePersistentNotification(bool value) async {
    await AppCaptureBridge.setPersistentAutoNotification(
      value,
      summary: autoBookkeepingNotificationSummary(VeriFinScope.of(context)),
    );
    await _refreshStatus();
  }

  Future<void> _setBoolPref(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _requestShizuku() async {
    final result = await AppCaptureBridge.requestShizukuPermission();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = switch (result) {
      'granted' => l10n.autoSettingsShizukuSuccess,
      'requested' => l10n.autoSettingsShizukuRequest,
      'not_running' => l10n.autoSettingsShizukuStart,
      _ => l10n.autoSettingsShizukuUnavailable,
    };
    unawaited(
      VeriFeedbackHost.of(context).showMessage(
        message: message,
        tone: result == 'granted'
            ? VeriFeedbackTone.success
            : VeriFeedbackTone.warning,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (mounted) await _refreshStatus();
  }

  Widget _permission({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool ready,
    required String target,
  }) {
    final l10n = AppLocalizations.of(context);
    return SettingsRow(
      leading: VeriIconBox(
        icon: icon,
        color: veriSemantic(context, ready ? veriIncome : veriWarning),
        size: 28,
      ),
      title: title,
      subtitle: subtitle,
      trailing: ready ? l10n.autoSettingsReady : l10n.autoSettingsOpen,
      trailingIcon: Icons.chevron_right,
      onTap: () => AppCaptureBridge.openAutoCapturePermission(target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final platforms = [
      ..._platforms(l10n),
      (
        id: 'ccb',
        name: l10n.autoCaptureCcbName,
        hint: l10n.autoCaptureCcbHint,
        icon: Icons.account_balance_outlined,
      ),
    ];
    String listenerHint(bool connected, bool granted, String capability) =>
        connected
        ? l10n.autoCaptureListenerConnected
        : granted
        ? l10n.autoCaptureListenerDisconnected
        : capability;
    return _CaptureSettingsPage(
      title: l10n.autoSettingsTitle,
      actions: [
        IconButton(
          tooltip: l10n.autoSettingsRefresh,
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _refreshStatus,
        ),
      ],
      children: [
        _CaptureSettingsGroup(
          rows: [
            CompactSwitchRow(
              icon: Icons.receipt_long_outlined,
              title: Text(l10n.autoSettingsEnabled),
              subtitle: Text(l10n.autoSettingsEnabledHint),
              value: _status.autoEnabled,
              onChanged: _loading ? null : _toggleAutoEnabled,
            ),
            CompactSwitchRow(
              icon: Icons.notifications_outlined,
              title: Text(l10n.autoSettingsPersistent),
              subtitle: Text(l10n.autoSettingsPersistentHint),
              value: _status.persistentNotification,
              onChanged: _loading ? null : _togglePersistentNotification,
            ),
          ],
        ),
        _CaptureSettingsGroup(
          title: l10n.autoSettingsCore,
          rows: [
            _permission(
              icon: Icons.accessibility_new_rounded,
              title: l10n.autoSettingsAccessibility,
              subtitle: listenerHint(
                _status.accessibilityConnected,
                _status.accessibilityGranted,
                l10n.autoSettingsAccessibilityHint,
              ),
              ready: _status.accessibilityConnected,
              target: 'accessibility',
            ),
            _permission(
              icon: Icons.notifications_active_outlined,
              title: l10n.autoSettingsNotificationAccess,
              subtitle: listenerHint(
                _status.notificationConnected,
                _status.notificationGranted,
                l10n.autoSettingsNotificationHint,
              ),
              ready: _status.notificationConnected,
              target: 'notification',
            ),
            if (_status.notificationGranted && !_status.notificationConnected)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: _reconnectNotificationListener,
                  child: Text(l10n.autoCaptureReconnect),
                ),
              ),
          ],
        ),
        _CaptureSettingsGroup(
          title: l10n.autoSettingsEnhancements,
          rows: [
            _permission(
              icon: Icons.layers_outlined,
              title: l10n.autoCaptureOverlayPermission,
              subtitle: l10n.autoCaptureOverlayFlow,
              ready: _status.overlayGranted,
              target: 'overlay',
            ),
            _permission(
              icon: Icons.receipt_long_outlined,
              title: l10n.autoCaptureReviewNotifications,
              subtitle: _status.canPostNotifications
                  ? l10n.autoCaptureNotificationFlow
                  : l10n.autoCaptureNotificationsDisabled,
              ready: _status.canPostNotifications,
              target: 'post_notifications',
            ),
            _permission(
              icon: Icons.battery_saver_outlined,
              title: l10n.autoSettingsBattery,
              subtitle: l10n.autoSettingsBatteryHint,
              ready: _status.batteryIgnored,
              target: 'battery',
            ),
          ],
        ),
        _CaptureSettingsGroup(
          title: l10n.autoSettingsPlatforms,
          rows: [
            for (final platform in platforms)
              CompactSwitchRow(
                icon: platform.icon,
                title: Text(platform.name),
                subtitle: Text(platform.hint),
                value: _enabledPlatforms[platform.id] ?? true,
                onChanged: _loading
                    ? null
                    : (value) {
                        setState(() => _enabledPlatforms[platform.id] = value);
                        unawaited(
                          _setBoolPref(
                            'verifin.auto_capture.app.${platform.id}',
                            value,
                          ),
                        );
                      },
              ),
          ],
        ),
        FilledButton.icon(
          icon: const Icon(Icons.bolt_rounded, size: 18),
          label: Text(l10n.autoCapturePreviewTitle),
          onPressed: _loading ? null : () => showAutoCapturePreview(context),
        ),
        _CaptureSettingsGroup(
          title: l10n.autoSettingsAdvanced,
          rows: [
            SettingsRow(
              icon: Icons.terminal_rounded,
              contentColor: Theme.of(context).colorScheme.onSurfaceVariant,
              title: l10n.autoSettingsShizuku,
              subtitle: _status.shizukuGranted
                  ? l10n.autoSettingsShizukuGranted
                  : _status.shizukuInstalled
                  ? l10n.autoSettingsShizukuInstalled
                  : l10n.autoSettingsShizukuUnavailable,
              trailing: '',
              trailingIcon: _status.shizukuInstalled && !_status.shizukuGranted
                  ? Icons.chevron_right
                  : null,
              onTap: _status.shizukuInstalled && !_status.shizukuGranted
                  ? _requestShizuku
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// 截图记账配置页。
class ScreenshotCapturePage extends StatelessWidget {
  const ScreenshotCapturePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final configured = VeriFinScope.of(context).aiSettings.isConfigured;

    return _CaptureSettingsPage(
      title: l10n.screenshotSettingsTitle,
      children: [
        _CaptureSettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.document_scanner_outlined,
              title: l10n.screenshotSettingsRecognition,
              subtitle: configured
                  ? l10n.screenshotSettingsRecognitionHint
                  : l10n.screenshotSettingsConfigureAi,
              trailing: '',
            ),
            SettingsRow(
              icon: Icons.screenshot_rounded,
              title: l10n.screenshotSettingsShortcut,
              subtitle: l10n.screenshotSettingsShortcutHint,
              trailing: '',
            ),
          ],
        ),
        FilledButton.icon(
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: Text(l10n.screenshotEntryButton),
          onPressed: () => startScreenshotEntry(context),
        ),
        _CaptureSettingsGroup(
          title: l10n.screenshotSettingsSupported,
          rows: [
            for (final platform in _platforms(l10n))
              SettingsRow(
                icon: platform.icon,
                title: platform.name,
                subtitle: platform.hint,
                trailing: '',
              ),
          ],
        ),
      ],
    );
  }
}

class _CaptureSettingsPage extends StatelessWidget {
  const _CaptureSettingsPage({
    required this.title,
    required this.children,
    this.actions,
  });

  final String title;
  final List<Widget> children;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: VeriPage(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
          children: [
            VeriHeader(title: title, showBack: true, actions: actions),
            for (final child in children) ...[
              const SizedBox(height: 12),
              child,
            ],
          ],
        ),
      ),
    ),
  );
}

class _CaptureSettingsGroup extends StatelessWidget {
  const _CaptureSettingsGroup({required this.rows, this.title});

  final String? title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (title case final heading?) SectionLabel(heading),
      VeriCard(
        child: Column(
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index != 0) const Divider(),
              row,
            ],
          ],
        ),
      ),
    ],
  );
}
