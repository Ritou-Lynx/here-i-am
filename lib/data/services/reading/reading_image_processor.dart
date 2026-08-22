import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/reading/ocr_recognizer.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';

/// OCR result for a single image in a reading_item.
class ImageOcrResult {
  const ImageOcrResult({
    required this.index,
    required this.url,
    required this.localPath,
    required this.recognisedText,
    this.ocrAvailability = OcrAvailability.available,
    this.confidence,
    this.ocrReason,
    this.recognizerVersion,
  });

  /// Position in the original image list (1-based, since this is what
  /// shows up in the agent's prompt — "图 1" reads more naturally).
  final int index;

  /// Original CDN URL.
  final String url;

  /// Relative path under the workspace root where the bytes were saved.
  /// May be null if download failed.
  final String? localPath;

  /// OCR text — empty string when the image had no recognisable text.
  /// Never null: a recognised-but-empty image is "no text in this photo"
  /// which is different from "OCR failed".
  final String recognisedText;

  /// Explicitly distinguishes successful empty OCR from unavailable/failed.
  final OcrAvailability ocrAvailability;
  final double? confidence;
  final String? ocrReason;
  final String? recognizerVersion;
}

/// Downloads a reading_item's images concurrently and runs Chinese OCR
/// on each, returning per-image text the coordinator can append to the
/// article body file.
///
/// Designed for the Reading Companion 小红书 use case: most saved notes
/// are screenshot-heavy "技术分享" 图文 — what matters is the *text* in
/// those screenshots (code, settings, captions). On-device Chinese OCR
/// via ML Kit is free, fast enough, and stays local (no token cost, no
/// data leaves the device).
class ReadingImageProcessor {
  ReadingImageProcessor({Dio? dio, OcrRecognizer? recognizer})
      : _recognizer = recognizer ?? const MlKitChineseOcrRecognizer(),
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                headers: {
                  // XHS image CDN requires a referrer matching the platform
                  // domain. Wechat CDN doesn't check, so this is safe to
                  // send to both.
                  'Referer': 'https://www.xiaohongshu.com/',
                },
                validateStatus: (status) =>
                    status != null && status >= 200 && status < 400,
              ),
            );

  final Dio _dio;
  final OcrRecognizer _recognizer;
  final Logger _logger = getLogger('ReadingImageProcessor');

  /// Concurrency cap — downloading 12 images at once over mobile would
  /// be wasteful and risk CDN rate-limits. 3 is a good compromise.
  static const _maxConcurrentDownloads = 3;

  /// Process every image: download → OCR. Returns one result per image
  /// in the same order, regardless of whether individual ones succeeded.
  ///
  /// [workspaceSubdir] controls where image bytes land on disk. Defaults to
  /// `reading` (persistent entity bodies). Transient fetches that may never
  /// be promoted to an entity should pass `reading_transient` so the files
  /// stay isolated and can be cleaned up when the cache entry expires.
  Future<List<ImageOcrResult>> processAll({
    required String entityId,
    required List<String> imageUrls,
    String workspaceSubdir = 'reading',
  }) async {
    if (imageUrls.isEmpty) return const [];
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      _logger.warning('No userId, skipping image processing');
      return const [];
    }
    final workspaceRoot = FileSystemService.instance.getWorkspacePath(userId);
    final imagesDir = Directory(
      p.join(workspaceRoot, workspaceSubdir, entityId, 'images'),
    );
    await imagesDir.create(recursive: true);

    final results = List<ImageOcrResult?>.filled(imageUrls.length, null);
    final pending = <int>[];
    for (var i = 0; i < imageUrls.length; i++) {
      pending.add(i);
    }

    // Roll N workers through the index queue. Each worker downloads +
    // OCRs one image, then takes the next pending index.
    Future<void> worker() async {
      while (pending.isNotEmpty) {
        final i = pending.removeAt(0);
        results[i] = await _processOne(
          index: i + 1,
          url: imageUrls[i],
          imagesDir: imagesDir,
          workspaceRoot: workspaceRoot,
        );
      }
    }

    final workers = List.generate(
      _maxConcurrentDownloads.clamp(1, imageUrls.length),
      (_) => worker(),
    );
    await Future.wait(workers);

    return results.whereType<ImageOcrResult>().toList(growable: false);
  }

  Future<ImageOcrResult> _processOne({
    required int index,
    required String url,
    required Directory imagesDir,
    required String workspaceRoot,
  }) async {
    final ext = _guessExtension(url);
    final localFile = File(p.join(imagesDir.path, '$index$ext'));
    String? relPath;
    try {
      await _download(url, localFile);
      relPath = p.relative(localFile.path, from: workspaceRoot);
    } catch (e) {
      _logger.warning('Image $index download failed ($url): $e');
      return ImageOcrResult(
        index: index,
        url: url,
        localPath: null,
        recognisedText: '',
        ocrAvailability: OcrAvailability.failed,
        ocrReason: e.toString(),
      );
    }
    final recognition = await _recognizer.recognize(localFile.path);
    return ImageOcrResult(
      index: index,
      url: url,
      localPath: relPath,
      recognisedText: recognition.text,
      ocrAvailability: recognition.availability,
      confidence: recognition.confidence,
      ocrReason: recognition.reason,
      recognizerVersion: recognition.recognizerVersion,
    );
  }

  Future<void> _download(String url, File destination) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Empty image body for $url');
    }
    await destination.writeAsBytes(bytes, flush: true);
  }

  String _guessExtension(String url) {
    final path = Uri.tryParse(url)?.path ?? url;
    final lower = path.toLowerCase();
    for (final ext in const ['.jpg', '.jpeg', '.png', '.webp', '.gif']) {
      if (lower.endsWith(ext)) return ext;
    }
    return '.jpg';
  }
}
