import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'external_network_guard.dart';

Uint8List? bytesFromDataUrl(String source) {
  if (!source.startsWith('data:')) {
    return null;
  }
  final commaIndex = source.indexOf(',');
  if (commaIndex == -1) {
    return null;
  }
  try {
    return base64Decode(source.substring(commaIndex + 1));
  } on FormatException {
    return null;
  }
}

// data URL 每次 build 重新 base64 解码会得到新的字节数组,MemoryImage 按
// 字节对象身份判等,会被当成"新图片"重新解码,期间画面短暂空白造成闪烁。
// 用小容量 LRU 复用 provider,让 Flutter 图片缓存稳定命中(头像 + 资产背景)。
const int _maxCachedDataUrlProviders = 4;
final Map<String, MemoryImage> _dataUrlProviderCache = <String, MemoryImage>{};

ImageProvider? imageProviderForSource(String source) {
  final cached = _dataUrlProviderCache.remove(source);
  if (cached != null) {
    _dataUrlProviderCache[source] = cached;
    return cached;
  }
  final bytes = bytesFromDataUrl(source);
  if (bytes == null) {
    // Legacy backups may contain a remote avatar or cover instead of bytes.
    final uri = Uri.tryParse(source);
    if (!ExternalNetworkGuard.enabled ||
        uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return _RemoteAppearanceImage(uri);
  }
  final provider = MemoryImage(bytes);
  _dataUrlProviderCache[source] = provider;
  if (_dataUrlProviderCache.length > _maxCachedDataUrlProviders) {
    _dataUrlProviderCache.remove(_dataUrlProviderCache.keys.first);
  }
  return provider;
}

Widget imageForSource(
  String source, {
  BoxFit fit = BoxFit.cover,
  AlignmentGeometry alignment = Alignment.center,
}) {
  final provider = imageProviderForSource(source);
  if (provider == null) return const SizedBox.expand();
  return Image(
    image: provider,
    fit: fit,
    alignment: alignment,
    gaplessPlayback: true,
  );
}

class _RemoteAppearanceImage extends ImageProvider<_RemoteAppearanceImage> {
  const _RemoteAppearanceImage(this.uri);

  final Uri uri;

  @override
  Future<_RemoteAppearanceImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _RemoteAppearanceImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: key._load(decode), scale: 1);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    const timeout = Duration(seconds: 15);
    ExternalNetworkGuard.check(uri);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      ExternalNetworkGuard.check(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw NetworkImageLoadException(
          statusCode: response.statusCode,
          uri: uri,
        );
      }
      final bytes = await consolidateHttpClientResponseBytes(
        response,
      ).timeout(timeout);
      return await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } finally {
      client.close(force: true);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _RemoteAppearanceImage && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
