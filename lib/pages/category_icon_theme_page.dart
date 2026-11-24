import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app/category_icon_presets.dart';
import '../app/category_icon_theme.dart';
import '../app/common_widgets.dart';
import '../app/feedback.dart';
import '../l10n/app_localizations.dart';

class CategoryIconThemePage extends StatefulWidget {
  const CategoryIconThemePage({super.key, required this.themes});

  final CategoryIconThemes themes;

  @override
  State<CategoryIconThemePage> createState() => _CategoryIconThemePageState();
}

class _CategoryIconThemePageState extends State<CategoryIconThemePage> {
  bool _busy = false;

  CategoryIconThemes get _themes => widget.themes;

  @override
  void initState() {
    super.initState();
    unawaited(_themes.restore());
  }

  Future<void> _run(Future<void> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error, stack) {
      _themes.logger?.error(
        'Category icon theme action failed (${error.runtimeType})',
        source: 'category_icon_theme',
        stackTrace: stack,
      );
      if (mounted) _message(failure, VeriFeedbackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String message, VeriFeedbackTone tone) {
    unawaited(
      VeriFeedbackHost.of(context).showMessage(message: message, tone: tone),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: VeriPage(
          child: ListenableBuilder(
            listenable: _themes,
            builder: (context, _) {
              final canAct = _themes.ready && !_busy;
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
                children: [
                  VeriHeader(
                    title: l10n.categoryIconThemeTitle,
                    showBack: true,
                  ),
                  const SizedBox(height: 12),
                  if (!_themes.ready || _busy) const LinearProgressIndicator(),
                  VeriCard(
                    child: Column(
                      children: [
                        _PresetOptionRow(
                          icon: Icons.draw_outlined,
                          title: l10n.categoryIconThemeLine,
                          presetPreview: CategoryIconPreset.line,
                          active:
                              _themes.ready &&
                              _themes.preset == CategoryIconPreset.line,
                          activeLabel: l10n.categoryIconThemeActive,
                          onTap: canAct
                              ? () => _run(
                                  () => _themes.selectPreset(
                                    CategoryIconPreset.line,
                                  ),
                                  l10n.saveFailed,
                                )
                              : null,
                        ),
                        const Divider(height: 1),
                        _PresetOptionRow(
                          icon: Icons.palette_outlined,
                          title: l10n.categoryIconThemeColored,
                          presetPreview: CategoryIconPreset.colored,
                          active:
                              _themes.ready &&
                              _themes.preset == CategoryIconPreset.colored,
                          activeLabel: l10n.categoryIconThemeActive,
                          onTap: canAct
                              ? () => _run(
                                  () => _themes.selectPreset(
                                    CategoryIconPreset.colored,
                                  ),
                                  l10n.saveFailed,
                                )
                              : null,
                        ),
                        const Divider(height: 1),
                        _PresetOptionRow(
                          icon: Icons.emoji_emotions_outlined,
                          title: l10n.categoryIconThemeEmoji,
                          presetPreview: CategoryIconPreset.emoji,
                          active:
                              _themes.ready &&
                              _themes.preset == CategoryIconPreset.emoji,
                          activeLabel: l10n.categoryIconThemeActive,
                          onTap: canAct
                              ? () => _run(
                                  () => _themes.selectPreset(
                                    CategoryIconPreset.emoji,
                                  ),
                                  l10n.saveFailed,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PresetOptionRow extends StatelessWidget {
  const _PresetOptionRow({
    required this.icon,
    required this.title,
    required this.active,
    required this.activeLabel,
    this.presetPreview,
    this.onTap,
  });

  static const _sampleKeys = <String>[
    'dining',
    'breakfast',
    'drink',
    'metro',
    'redpacket',
  ];

  final IconData icon;
  final String title;
  final bool active;
  final String activeLabel;
  final CategoryIconPreset? presetPreview;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = presetPreview;
    return InkWell(
      onTap: active ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final key in _sampleKeys) ...[
                          _PresetSampleGlyph(
                            preset: preview,
                            presetKey: key,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (active) ...[
              Text(
                activeLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.check, size: 18, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _PresetSampleGlyph extends StatelessWidget {
  const _PresetSampleGlyph({
    required this.preset,
    required this.presetKey,
    required this.color,
  });

  final CategoryIconPreset preset;
  final String presetKey;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (preset == CategoryIconPreset.emoji) {
      return Text(
        categoryPresetEmoji(presetKey),
        style: const TextStyle(fontSize: 16, height: 1),
      );
    }
    final asset = categoryPresetSvgAsset(preset, presetKey);
    if (asset == null) return const SizedBox.shrink();
    return SvgPicture.asset(
      asset,
      width: 17,
      height: 17,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      colorFilter: preset == CategoryIconPreset.line
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }
}
