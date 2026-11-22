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
  CategoryIconPreset _preset = CategoryIconPreset.builtin;
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
      for (final candidate in CategoryIconPreset.values) {
        if (candidate.name == raw && !_disposed) {
          _preset = candidate;
          break;
        }
      }
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

  Future<void> reset() => selectPreset(CategoryIconPreset.builtin);

  Future<void> selectPreset(CategoryIconPreset preset) async {
    await restore();
    if (_preset == preset) return;
    if (_writing || _disposed) {
      throw StateError('Category icon theme is unavailable for writing');
    }
    _writing = true;
    try {
      final file = await _presetFile();
      if (preset == CategoryIconPreset.builtin) {
        if (await file.exists()) await file.delete();
      } else {
        final staged = File('${file.path}.tmp');
        await staged.writeAsString(preset.name, flush: true);
        await staged.rename(file.path);
      }
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
  }) : super(notifier: themes);

  static CategoryIconThemes? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CategoryIconThemeScope>()
      ?.notifier;
}
