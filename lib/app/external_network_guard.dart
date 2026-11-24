/// In-app network requests are denied until the ledger preference is ready.
abstract final class ExternalNetworkGuard {
  static bool Function()? _readEnabled;

  static bool get enabled => _readEnabled?.call() ?? false;

  static void bind(bool Function()? readEnabled) {
    _readEnabled = readEnabled;
  }

  static void check(
    Uri target, {
    WebdavOperation? operation,
    WebdavAuthorization? authorization,
  }) {
    if (enabled) return;
    if (authorization != null &&
        authorization._active &&
        authorization._operation == operation &&
        authorization._origin == target.origin) {
      return;
    }
    throw const ExternalNetworkDisabled();
  }

  static WebdavAuthorization authorizeWebdavOnce(
    Uri target,
    WebdavOperation operation,
  ) => WebdavAuthorization._(target.origin, operation);
}

enum WebdavOperation { upload, restore, testConnection }

final class WebdavAuthorization {
  WebdavAuthorization._(this._origin, this._operation);

  final String _origin;
  final WebdavOperation _operation;
  bool _active = true;

  void revoke() => _active = false;
}

final class ExternalNetworkDisabled implements Exception {
  const ExternalNetworkDisabled();
}

final class WebdavOriginMismatch implements Exception {
  const WebdavOriginMismatch();
}
