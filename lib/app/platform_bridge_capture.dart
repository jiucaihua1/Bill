part of 'platform_bridge.dart';

Future<void> Function()? _quickEntryHandler;
Future<void> Function()? _sharedCaptureHandler;
Future<void> Function()? _screenshotCaptureHandler;
Future<void> Function()? _openAutoCaptureHandler;
Future<void> Function()? _autoConfirmDraftHandler;

class AutoCapturePermissionStatus {
  const AutoCapturePermissionStatus({
    this.overlayGranted = false,
    required this.accessibilityGranted,
    required this.accessibilityConnected,
    required this.notificationGranted,
    required this.notificationConnected,
    required this.canPostNotifications,
    required this.batteryIgnored,
    required this.shizukuInstalled,
    required this.shizukuGranted,
    required this.autoEnabled,
    required this.persistentNotification,
  });

  const AutoCapturePermissionStatus.empty()
    : overlayGranted = false,
      accessibilityGranted = false,
      accessibilityConnected = false,
      notificationGranted = false,
      notificationConnected = false,
      canPostNotifications = false,
      batteryIgnored = false,
      shizukuInstalled = false,
      shizukuGranted = false,
      autoEnabled = false,
      persistentNotification = true;

  final bool overlayGranted;
  final bool accessibilityGranted;
  final bool accessibilityConnected;
  final bool notificationGranted;
  final bool notificationConnected;
  final bool canPostNotifications;
  final bool batteryIgnored;
  final bool shizukuInstalled;
  final bool shizukuGranted;
  final bool autoEnabled;
  final bool persistentNotification;

  factory AutoCapturePermissionStatus.fromMap(Map<Object?, Object?> map) {
    bool flag(String key, {bool fallback = false}) =>
        map.containsKey(key) ? map[key] == true : fallback;
    return AutoCapturePermissionStatus(
      overlayGranted: flag('overlayGranted'),
      accessibilityGranted: flag('accessibilityGranted'),
      accessibilityConnected: flag('accessibilityConnected'),
      notificationGranted: flag('notificationGranted'),
      notificationConnected: flag('notificationConnected'),
      canPostNotifications: flag('canPostNotifications'),
      batteryIgnored: flag('batteryIgnored'),
      shizukuInstalled: flag('shizukuInstalled'),
      shizukuGranted: flag('shizukuGranted'),
      autoEnabled: flag('autoEnabled'),
      persistentNotification: flag('persistentNotification', fallback: true),
    );
  }
}

/// 快速记账磁贴与分享/外部采集（`ShareReceiverActivity` 转发）的消费入口。
class AppCaptureBridge {
  AppCaptureBridge._();

  static void setQuickEntryHandler(Future<void> Function() handler) {
    _quickEntryHandler = handler;
    _ensureInboundDispatcher();
  }

  static void clearQuickEntryHandler() {
    _quickEntryHandler = null;
    _ensureInboundDispatcher();
  }

  static void setScreenshotCaptureHandler(Future<void> Function() handler) {
    _screenshotCaptureHandler = handler;
    _ensureInboundDispatcher();
  }

  static void clearScreenshotCaptureHandler() {
    _screenshotCaptureHandler = null;
    _ensureInboundDispatcher();
  }

  static void setOpenAutoCaptureHandler(Future<void> Function() handler) {
    _openAutoCaptureHandler = handler;
    _ensureInboundDispatcher();
  }

  static void clearOpenAutoCaptureHandler() {
    _openAutoCaptureHandler = null;
    _ensureInboundDispatcher();
  }

  static void setAutoConfirmDraftHandler(Future<void> Function() handler) {
    _autoConfirmDraftHandler = handler;
    _ensureInboundDispatcher();
  }

  static void clearAutoConfirmDraftHandler() {
    _autoConfirmDraftHandler = null;
    _ensureInboundDispatcher();
  }

  static Future<bool> reconnectAutoNotificationListener() async {
    try {
      return await _channel.invokeMethod<bool>(
            'reconnectAutoNotificationListener',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<Map<String, Object?>?> consumeAutoConfirmDraft() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'consumeAutoConfirmDraft',
      );
      if (raw == null) return null;
      return Map<String, Object?>.from(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<Map<String, Object?>?> previewWechatTransfer() async {
    try {
      return await _channel.invokeMapMethod<String, Object?>(
        'previewWechatTransfer',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> openAutoBillOverlayPreview() async {
    try {
      return await _channel.invokeMethod<bool>('openAutoBillOverlayPreview') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String> requestShizukuPermission() async {
    try {
      return await _channel.invokeMethod<String>('requestShizukuPermission') ??
          'not_running';
    } on MissingPluginException {
      return 'not_installed';
    } on PlatformException {
      return 'not_running';
    }
  }

  static Future<bool> consumeInitialScreenshotCaptureIntent() async {
    try {
      return await _channel.invokeMethod<bool>(
            'consumeScreenshotCaptureIntent',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> consumeInitialOpenAutoCaptureIntent() async {
    try {
      return await _channel.invokeMethod<bool>(
            'consumeOpenAutoCaptureIntent',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<AutoCapturePermissionStatus> getAutoCaptureStatus() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'getAutoCaptureStatus',
      );
      if (raw == null) return const AutoCapturePermissionStatus.empty();
      return AutoCapturePermissionStatus.fromMap(raw);
    } on MissingPluginException {
      return const AutoCapturePermissionStatus.empty();
    } on PlatformException {
      return const AutoCapturePermissionStatus.empty();
    }
  }

  static Future<void> setAutoBookkeepingEnabled(
    bool enabled, {
    String? summary,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'setAutoBookkeepingEnabled',
        <String, Object>{'enabled': enabled, 'summary': ?summary},
      );
    } on MissingPluginException {
      // 非 Android 平台忽略。
    }
  }

  static Future<void> setPersistentAutoNotification(
    bool enabled, {
    String? summary,
  }) async {
    try {
      await _channel.invokeMethod<void>(
        'setPersistentAutoNotification',
        <String, Object>{'enabled': enabled, 'summary': ?summary},
      );
    } on MissingPluginException {
      // 非 Android 平台忽略。
    }
  }

  static Future<bool> openAutoCapturePermission(String kind) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openAutoCapturePermission',
            <String, Object>{'kind': kind},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 注册分享/外部采集到达时的回调（应用已在运行、原生 onNewIntent 通知）。
  static void setSharedCaptureHandler(Future<void> Function() handler) {
    _sharedCaptureHandler = handler;
    _ensureInboundDispatcher();
  }

  static void clearSharedCaptureHandler() {
    _sharedCaptureHandler = null;
    _ensureInboundDispatcher();
  }

  /// 冷启动时取走「来自磁贴的快速记账」意图（无则 false）。取走即清。
  static Future<bool> consumeInitialQuickEntryIntent() async {
    try {
      return await _channel.invokeMethod<bool>('consumeQuickEntryIntent') ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 取走待识别的分享图片字节（无则 null）。取走即清，重复调用返回 null。
  static Future<Uint8List?> consumeCaptureImage() async {
    try {
      return await _channel.invokeMethod<Uint8List>('consumeCaptureImage');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// 取走待解析的外部采集文本（分享文本 / 自动化意图，无则 null）。取走即清。
  static Future<String?> consumeCaptureText() async {
    try {
      return await _channel.invokeMethod<String>('consumeCaptureText');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
