import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:memex/data/services/file_system_service.dart';

/// Local disk cache for generated images, keyed by prompt + parameters.
/// Mirrors the caching pattern used by [MiniMaxTtsService].
class ImageGenCache {
  ImageGenCache._();

  static Future<String> _cacheDir() async {
    final appSupport = await FileSystemService.getAppSupportDir();
    final dir = Directory('$appSupport${Platform.pathSeparator}image_gen_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir.path;
  }

  /// SHA-256 of the concatenated generation parameters.
  static String cacheKey({
    required String prompt,
    required String provider,
    required String model,
    required String size,
    String? negativePrompt,
    String? style,
  }) {
    final raw = '${provider}|$model|$size|${negativePrompt ?? ''}|${style ?? ''}|$prompt';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// Returns the absolute file path if cached, or null.
  static Future<String?> lookup(String key) async {
    try {
      final cacheDir = await _cacheDir();
      final file = File('$cacheDir${Platform.pathSeparator}$key.png');
      if (file.existsSync()) return file.path;
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Writes raw bytes to the cache and returns the absolute file path.
  static Future<String> store(String key, Uint8List bytes) async {
    final cacheDir = await _cacheDir();
    final file = File('$cacheDir${Platform.pathSeparator}$key.png');
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
