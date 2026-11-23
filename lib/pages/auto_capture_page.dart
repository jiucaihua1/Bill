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

const List<({String id, String name, String hint})> _supportedPlatforms =
    <({String id, String name, String hint})>[
      (id: 'wechat', name: '微信支付 / 转账', hint: '支付成功页、微信账单与转账详情'),
      (id: 'alipay', name: '支付宝', hint: '付款成功页与账单详情'),
      (id: 'jd', name: '京东', hint: '订单支付成功与白条/钱包账单'),
      (id: 'pdd', name: '拼多多', hint: '订单支付与多多支付账单详情'),
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

  List<({String id, String name, String hint})> _platforms(
    BuildContext context,
  ) {
    final l10n = AppLocalizations.of(context);
    return [
      ..._supportedPlatforms,
      (id: 'ccb', name: l10n.autoCaptureCcbName, hint: l10n.autoCaptureCcbHint),
    ];
  }

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
      for (final p in _platforms(context)) {
        _enabledPlatforms[p.id] =
            prefs.getBool('verifin.auto_capture.app.${p.id}') ??
            (p.id != 'ccb');
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自动记账'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新权限检测',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshStatus,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: veriPageMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: <Widget>[
              VeriCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '自动记账总开关',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.autoCaptureOverlayFlow,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _status.autoEnabled,
                          onChanged: _loading ? null : _toggleAutoEnabled,
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('通知栏运行状态'),
                      subtitle: const Text('开启自动记账时在通知栏显示运行状态'),
                      value: _status.persistentNotification,
                      onChanged: _loading
                          ? null
                          : _togglePersistentNotification,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('采集通道与权限'),
              VeriCard(
                child: Column(
                  children: <Widget>[
                    _PermissionRow(
                      icon: Icons.layers_outlined,
                      title: l10n.autoCaptureOverlayPermission,
                      subtitle: l10n.autoCaptureOverlayFlow,
                      granted: _status.overlayGranted,
                      onTap: () =>
                          AppCaptureBridge.openAutoCapturePermission('overlay'),
                    ),
                    const Divider(height: 1),
                    _PermissionRow(
                      icon: Icons.accessibility_new_rounded,
                      title: '无障碍服务',
                      subtitle: _status.accessibilityConnected
                          ? l10n.autoCaptureListenerConnected
                          : _status.accessibilityGranted
                          ? l10n.autoCaptureListenerDisconnected
                          : '识别已选平台的付款和转账页面',
                      granted: _status.accessibilityConnected,
                      badgeText:
                          _status.accessibilityGranted &&
                              !_status.accessibilityConnected
                          ? '去设置'
                          : null,
                      onTap: () => AppCaptureBridge.openAutoCapturePermission(
                        'accessibility',
                      ),
                    ),
                    const Divider(height: 1),
                    _PermissionRow(
                      icon: Icons.notifications_active_outlined,
                      title: '通知栏读取权限',
                      subtitle: _status.notificationConnected
                          ? l10n.autoCaptureListenerConnected
                          : _status.notificationGranted
                          ? l10n.autoCaptureListenerDisconnected
                          : '接收已选平台的支付通知',
                      granted: _status.notificationConnected,
                      onTap: () => AppCaptureBridge.openAutoCapturePermission(
                        'notification',
                      ),
                    ),
                    if (_status.notificationGranted &&
                        !_status.notificationConnected)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _reconnectNotificationListener,
                          child: Text(l10n.autoCaptureReconnect),
                        ),
                      ),
                    const Divider(height: 1),
                    _PermissionRow(
                      icon: Icons.receipt_long_outlined,
                      title: l10n.autoCaptureReviewNotifications,
                      subtitle: _status.canPostNotifications
                          ? l10n.autoCaptureNotificationFlow
                          : l10n.autoCaptureNotificationsDisabled,
                      granted: _status.canPostNotifications,
                      onTap: () => AppCaptureBridge.openAutoCapturePermission(
                        'post_notifications',
                      ),
                    ),
                    const Divider(height: 1),
                    _PermissionRow(
                      icon: Icons.battery_saver_outlined,
                      title: '后台保活（忽略电池优化）',
                      subtitle: '防止 HyperOS 后台清理导致监听断开',
                      granted: _status.batteryIgnored,
                      onTap: () =>
                          AppCaptureBridge.openAutoCapturePermission('battery'),
                    ),
                    const Divider(height: 1),
                    _PermissionRow(
                      icon: Icons.terminal_rounded,
                      title: 'Shizuku 授权状态',
                      subtitle: _status.shizukuGranted
                          ? 'Shizuku 已授权，当前识别仍使用系统采集通道'
                          : _status.shizukuInstalled
                          ? '已安装 Shizuku，点击请求授权（需先在 Shizuku 内启动服务）'
                          : '未检测到 Shizuku（当前识别不依赖此授权）',
                      granted: _status.shizukuGranted,
                      optional: !_status.shizukuInstalled,
                      onTap: () async {
                        final res =
                            await AppCaptureBridge.requestShizukuPermission();
                        if (!context.mounted) return;
                        final msg = switch (res) {
                          'granted' => 'Shizuku 已授权',
                          'requested' => '已发起 Shizuku 授权请求，请在弹窗中允许',
                          'not_running' =>
                            '未连接到 Shizuku 服务，请先在 Shizuku 中启动服务后再试',
                          _ => '未检测到 Shizuku 应用',
                        };
                        unawaited(
                          VeriFeedbackHost.of(context).showMessage(
                            message: msg,
                            tone: res == 'granted'
                                ? VeriFeedbackTone.success
                                : VeriFeedbackTone.warning,
                          ),
                        );
                        await Future<void>.delayed(
                          const Duration(milliseconds: 500),
                        );
                        await _refreshStatus();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('已适配与计划适配平台'),
              VeriCard(
                child: Column(
                  children: <Widget>[
                    for (final platform in _platforms(context)) ...<Widget>[
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(platform.name),
                        subtitle: Text(platform.hint),
                        value: _enabledPlatforms[platform.id] ?? true,
                        onChanged: (value) {
                          setState(
                            () => _enabledPlatforms[platform.id] = value,
                          );
                          unawaited(
                            _setBoolPref(
                              'verifin.auto_capture.app.${platform.id}',
                              value,
                            ),
                          );
                        },
                      ),
                      if (platform.id != 'ccb') const Divider(height: 1),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              VeriCard(
                child: FilledButton.icon(
                  icon: const Icon(Icons.bolt_rounded, size: 18),
                  label: Text(l10n.autoCapturePreviewTitle),
                  onPressed: () => showAutoCapturePreview(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 截图记账配置页：
/// 控制中心【截图记账】磁贴指引、本地 OCR + 文本传 AI 省流开关与立即选图测试。
class ScreenshotCapturePage extends StatefulWidget {
  const ScreenshotCapturePage({super.key});

  @override
  State<ScreenshotCapturePage> createState() => _ScreenshotCapturePageState();
}

class _ScreenshotCapturePageState extends State<ScreenshotCapturePage> {
  static const _keyAiTextOnly = 'verifin.auto_capture.ai_text_only';
  bool _aiTextOnly = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _aiTextOnly = prefs.getBool(_keyAiTextOnly) ?? true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = VeriStyleTokens.of(context);
    final controller = VeriFinScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('截图记账')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: veriPageMaxWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: <Widget>[
              VeriCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '识别与成本控制',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('本地 OCR 优先 + 仅传文本给 AI'),
                      subtitle: Text(
                        controller.aiSettings.isConfigured
                            ? '截图不出手机，本地 ML Kit 离线提取文字后仅发送文本给 AI 解析，大幅降低 Token 成本'
                            : '请先在「AI 财务助理」配置模型接口，即可直接解析截图文字',
                      ),
                      value: _aiTextOnly,
                      onChanged: (value) async {
                        setState(() => _aiTextOnly = value);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool(_keyAiTextOnly, value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('控制中心快捷开关'),
              VeriCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: tokens.surfaceAltColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '使用方式：\n1. 下拉小米控制中心 → 点击「编辑」将【截图记账】磁贴拖到快捷面板；\n2. 支付完或看到账单时，也可直接系统「分享截图 → 小禾记账」。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.screenshot_rounded, size: 18),
                      label: const Text('选择账单截图立即识别'),
                      onPressed: () => startScreenshotEntry(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('支持识别的常见账单截图'),
              VeriCard(
                child: Column(
                  children: <Widget>[
                    for (final item in _supportedPlatforms.indexed) ...<Widget>[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: VeriIconBox(
                          icon: Icons.receipt_long_outlined,
                          color: theme.colorScheme.primary,
                          size: 34,
                        ),
                        title: Text(
                          item.$2.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(item.$2.hint),
                      ),
                      if (item.$1 != _supportedPlatforms.length - 1)
                        const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
    this.optional = false,
    this.badgeText,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onTap;
  final bool optional;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = granted
        ? veriSemantic(context, veriIncome)
        : optional
        ? theme.colorScheme.onSurface.withValues(alpha: 0.52)
        : veriSemantic(context, veriWarning);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: VeriIconBox(icon: icon, color: statusColor, size: 34),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          badgeText ?? (granted ? '已就绪' : (optional ? '去查看' : '去开启')),
          style: theme.textTheme.labelSmall?.copyWith(
            color: statusColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}
