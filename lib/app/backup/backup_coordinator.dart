import '../external_network_guard.dart';
import '../veri_fin_controller.dart';
import 'backup_service.dart';
import 'backup_settings.dart';
import 'webdav_client.dart';
import 'webdav_config.dart';

/// 自动备份协调器：在应用打开与记账后按配置触发自动备份。真正的文件 I/O 在
/// [BackupService]（条件导入存储端口）；控制器只提供配置与数据，不做 I/O。
class BackupCoordinator {
  const BackupCoordinator._();

  static bool _running = false;
  static bool _entryBackupPending = false;

  /// 应用打开（冷启动 / 回前台）时调用。
  static Future<void> maybeBackupOnOpen(VeriFinController controller) {
    return _maybeRun(controller, afterEntry: false);
  }

  /// 新增交易后调用。
  static Future<void> maybeBackupAfterEntry(VeriFinController controller) {
    return _maybeRun(controller, afterEntry: true);
  }

  static Future<void> _maybeRun(
    VeriFinController controller, {
    required bool afterEntry,
  }) async {
    if (_running) {
      if (afterEntry &&
          controller.backupSettings.frequency == BackupFrequency.onEntry) {
        _entryBackupPending = true;
      }
      return;
    }
    _running = true;
    try {
      var triggeredByEntry = afterEntry;
      do {
        _entryBackupPending = false;
        await _runOnce(controller, afterEntry: triggeredByEntry);
        triggeredByEntry = true;
      } while (_entryBackupPending);
    } finally {
      _running = false;
    }
  }

  static Future<void> _runOnce(
    VeriFinController controller, {
    required bool afterEntry,
  }) async {
    final settings = controller.backupSettings;
    final webdav = controller.webdavConfig;
    final now = DateTime.now();
    final toLocal = settings.shouldAutoBackup(now, afterEntry: afterEntry);
    final toWebdav =
        controller.externalNetworkEnabled &&
        webdav.isConfigured &&
        webdav.autoUpload &&
        settings.isFrequencyDue(now, afterEntry: afterEntry, webdav: true);
    if (!toLocal && !toWebdav) return;

    PreparedBackup? prepared;
    try {
      // 只准备一次备份内容（未加密→zip、加密→文本信封），本地与 WebDAV 共用同一份，
      // 避免重复导出/加密（加密时 PBKDF2 迭代很贵）。
      prepared = await BackupService.prepare(
        json: controller.exportDataJson(),
        store: controller.attachmentStore,
        cacheDirectory: await controller.ensureBackupCacheDirectory(),
        passphrase: controller.backupPassphrase,
        now: now,
        auto: true,
      );
      if (toLocal) {
        try {
          await BackupService.writeAutoBackupPrepared(
            settings: settings,
            prepared: prepared,
          );
          controller.recordBackupTime(now, directoryUri: settings.directoryUri);
        } catch (error) {
          // 本地目录失败（授权失效、写坏被回读校验拦下等）不影响 WebDAV 尝试；
          // 记日志便于诊断，但不打断用户。
          controller.logger?.error('本地自动备份失败', source: 'backup', error: error);
        }
      }
      if (toWebdav && controller.externalNetworkEnabled) {
        try {
          // 兜底总超时：即便上传响应被服务器黑洞挂住，也保证 finally 能释放 _running，
          // 不会让此后所有自动备份（含本地目录）被静默跳过。自动备份取较宽的 5 分钟，
          // 手动备份路径不经此处、不受此限。
          await webdavUploadFile(
            webdav,
            prepared.filename,
            prepared.cachePath,
          ).timeout(const Duration(minutes: 5));
          controller.recordWebdavBackupTime(now, webdav);
          // 与本地一致：按保留份数清理远端旧的自动备份，避免无限累积。
          await _pruneWebdav(webdav, settings.retention);
        } on ExternalNetworkDisabled {
          // Permission can change while preparing a local backup.
        } catch (error) {
          // WebDAV 失败不打断，但记日志便于诊断（网络 / 认证 / 服务器错误等）。
          controller.logger?.error(
            'WebDAV 自动备份失败',
            source: 'backup',
            error: error,
          );
        }
      }
    } catch (error) {
      // 兜底：任何未预期错误都不打断用户操作，但必须留下隐私友好的诊断线索。
      controller.logger?.error('自动备份未预期失败', source: 'backup', error: error);
    } finally {
      final pending = prepared;
      if (pending != null) {
        await BackupService.deletePrepared(pending);
      }
    }
  }

  /// 清理 WebDAV 上超出保留份数的旧自动备份。尽力而为，失败不影响备份主流程。
  static Future<void> _pruneWebdav(WebdavConfig webdav, int retention) async {
    try {
      final files = await webdavList(webdav);
      for (final file in webdavAutoBackupsToPrune(files, retention)) {
        await webdavDelete(webdav, file.href);
      }
    } catch (_) {
      // 清理失败静默。
    }
  }
}
