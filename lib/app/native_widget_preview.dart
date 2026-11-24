import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform_bridge.dart';
import 'widgets/widget_catalog.dart';
import '../l10n/app_localizations.dart';

/// Displays the actual Glance composition. Draft changes only render pixels;
/// they never write the home_widget instance preferences.
class NativeWidgetPreview extends StatefulWidget {
  const NativeWidgetPreview({
    super.key,
    required this.template,
    required this.width,
    required this.height,
    this.bookId = '',
    this.appearance = WidgetAppearance.system,
    this.backgroundOpacity = 1,
    this.typography = defaultWidgetTypography,
    this.leftMetric,
    this.rightMetric,
    this.sample = false,
    required this.semanticLabel,
  });
  final String template;
  final int width;
  final int height;
  final String bookId;
  final WidgetAppearance appearance;
  final double backgroundOpacity;
  final WidgetTypography typography;
  final WidgetDualMetricChoice? leftMetric;
  final WidgetDualMetricChoice? rightMetric;
  final bool sample;
  final String semanticLabel;
  @override
  State<NativeWidgetPreview> createState() => _NativeWidgetPreviewState();
}

class _NativeWidgetPreviewState extends State<NativeWidgetPreview> {
  Uint8List? _image;
  bool _rendering = false;
  bool _renderAgain = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(NativeWidgetPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height ||
        oldWidget.bookId != widget.bookId ||
        oldWidget.appearance != widget.appearance ||
        oldWidget.backgroundOpacity != widget.backgroundOpacity ||
        oldWidget.typography != widget.typography ||
        oldWidget.leftMetric != widget.leftMetric ||
        oldWidget.rightMetric != widget.rightMetric ||
        oldWidget.sample != widget.sample) {
      _load();
    }
  }

  void _load() {
    if (_rendering) {
      _renderAgain = true;
      return;
    }
    _rendering = true;
    unawaited(_render());
  }

  Future<void> _render() async {
    Uint8List? image;
    try {
      image = await AppWidgetBridge.renderPreview(
        template: widget.template,
        widthDp: widget.width,
        heightDp: widget.height,
        bookId: widget.bookId,
        appearance: widget.appearance.key,
        backgroundOpacity: widget.backgroundOpacity,
        typography: widget.typography,
        leftMetric: widget.leftMetric?.key,
        rightMetric: widget.rightMetric?.key,
        sample: widget.sample,
      );
    } on PlatformException {
      // The native activity may be unavailable or closing.
    }
    if (!mounted) return;
    setState(() {
      _image = image ?? (_renderAgain ? _image : null);
      _rendering = false;
    });
    // Keep the last frame visible and render only the latest queued slider value.
    if (_renderAgain) {
      _renderAgain = false;
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _image;
    return SizedBox(
      width: widget.width.toDouble(),
      height: widget.height.toDouble(),
      child: Semantics(
        label: widget.semanticLabel,
        image: true,
        child: bytes != null
            ? Image.memory(
                bytes,
                key: ValueKey('native_widget_preview_${widget.template}'),
                width: widget.width.toDouble(),
                height: widget.height.toDouble(),
                gaplessPlayback: true,
                excludeFromSemantics: true,
              )
            : _rendering
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: Text(AppLocalizations.of(context).widgetPreviewFailed),
              ),
      ),
    );
  }
}
