import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'category_icon_presets.dart';
import 'logging/app_logger.dart';

/// Stores the selected bundled icon preset as a device appearance preference.
class CategoryIconThemes extends ChangeNotifier {
  CategoryIconThemes({required this.logger});

  final AppLogger? logger;
  Future<void>? _restoreFuture;
  CategoryIconPreset _preset = CategoryIconPreset.defaultPreset;
  bool _ready = false;
  bool _writing = false;
  bool _disposed = false;

  CategoryIconPreset get preset => _preset;
  bool get ready => _ready;

  Future<void> restore() => _restoreFuture ??= _restore();

  Future<File> _presetFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'category-icon-preset-v1'));
  }

  Future<void> _restore() async {
    try {
      final file = await _presetFile();
      if (!await file.exists()) return;
      final raw = (await file.readAsString()).trim();
      if (_disposed) return;
      _preset = CategoryIconPreset.fromStorage(raw);
      if (raw == 'builtin') await _writePreset(file, _preset);
    } catch (error, stack) {
      logger?.error(
        'Could not restore category icon theme (${error.runtimeType})',
        source: 'category_icon_theme',
        stackTrace: stack,
      );
    } finally {
      if (!_disposed) {
        _ready = true;
        notifyListeners();
      }
    }
  }

  Future<void> reset() => selectPreset(CategoryIconPreset.defaultPreset);

  Future<void> _writePreset(File file, CategoryIconPreset preset) async {
    final staged = File('${file.path}.tmp');
    await staged.writeAsString(preset.name, flush: true);
    await staged.rename(file.path);
  }

  Future<void> selectPreset(CategoryIconPreset preset) async {
    if (!_ready) await restore();
    if (_preset == preset) return;
    if (_writing || _disposed) {
      throw StateError('Category icon theme is unavailable for writing');
    }
    _writing = true;
    try {
      await _writePreset(await _presetFile(), preset);
      if (_disposed) return;
      _preset = preset;
      notifyListeners();
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class CategoryIconThemeScope extends InheritedNotifier<CategoryIconThemes> {
  const CategoryIconThemeScope({
    super.key,
    required CategoryIconThemes themes,
    required super.child,
  }) : _preset = null,
       super(notifier: themes);

  const CategoryIconThemeScope.snapshot({
    super.key,
    required CategoryIconPreset this._preset,
    required super.child,
  });

  final CategoryIconPreset? _preset;

  static CategoryIconPreset presetOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<CategoryIconThemeScope>();
    return scope?.notifier?.preset ??
        scope?._preset ??
        CategoryIconPreset.defaultPreset;
  }

  @override
  bool updateShouldNotify(CategoryIconThemeScope oldWidget) =>
      _preset != oldWidget._preset || super.updateShouldNotify(oldWidget);
}
