import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Progress of an offline model install.
@immutable
class OfflineTtsInstallProgress {
  const OfflineTtsInstallProgress(this.value, this.message);

  final double value;
  final String message;
}

/// Downloads, stream-extracts, and verifies an offline TTS model package.
///
/// Shared by every local reader TTS engine so the resume / retry / checksum
/// behavior stays identical: partial downloads are kept between attempts and
/// the next run resumes from the last received byte instead of restarting the
/// whole archive.
class OfflineTtsModelInstaller {
  OfflineTtsModelInstaller({
    required this.name,
    required this.downloadUrl,
    required this.modelRelativePath,
    required this.modelSha256,
    required this.requiredFiles,
    Directory? baseDirectory,
    Duration retryDelay = const Duration(seconds: 3),
  })  : _baseDirectoryOverride = baseDirectory,
        _retryDelay = retryDelay;

  /// Directory name of the model under the base directory, e.g.
  /// 'vits-melo-tts-zh_en'. Must match the folder name inside the archive.
  final String name;

  final String downloadUrl;

  /// Path of the model file relative to the extracted root, e.g. 'model.onnx'.
  final String modelRelativePath;

  final String modelSha256;

  /// Paths (relative to the extracted root) that must exist for the model to
  /// be considered ready. A path may be a file or a directory.
  final List<String> requiredFiles;

  static const _maxDownloadAttempts = 4;
  static const _idleTimeout = Duration(seconds: 90);

  final Directory? _baseDirectoryOverride;
  final Duration _retryDelay;

  Future<Directory> _baseDirectory() async {
    final support =
        _baseDirectoryOverride ?? await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'book_tts'));
  }

  /// The shared base directory that holds all reader TTS model packages.
  Future<Directory> get baseDirectory => _baseDirectory();

  /// The published model directory. Files live here only after a successful,
  /// verified install.
  Future<Directory> get modelDirectory async =>
      Directory(path.join((await _baseDirectory()).path, name));

  Future<bool> isReady() async {
    final root = await modelDirectory;
    final marker = File(path.join(root.path, '.verified'));
    if (!await marker.exists()) return false;
    return _hasRequiredFiles(root);
  }

  Future<int> installedBytes() async {
    final root = await modelDirectory;
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Downloads, stream-extracts, and verifies the model before publishing it.
  Future<void> downloadAndPrepare({
    required ValueChanged<OfflineTtsInstallProgress> onProgress,
  }) async {
    final base = await _baseDirectory();
    await base.create(recursive: true);
    // Keep the compression suffix last: the streaming extractor selects its
    // decoder from the filename extension.
    final archiveFile = File(path.join(base.path, '$name.part.tar.bz2'));
    final staging = Directory(path.join(base.path, '.extracting-$name'));
    final destination = await modelDirectory;

    // Resume support: a partial archive from an interrupted attempt is kept
    // intentionally; only the staging dir is always reset.
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);

    var fullyDownloaded = false;
    try {
      onProgress(const OfflineTtsInstallProgress(0, '正在下载本地模型'));
      await _downloadFile(
        Uri.parse(downloadUrl),
        archiveFile,
        onProgress: (value) => onProgress(
          OfflineTtsInstallProgress(value * 0.82, '正在下载本地模型'),
        ),
      );
      fullyDownloaded = true;

      onProgress(const OfflineTtsInstallProgress(0.84, '正在解压模型'));
      await extractFileToDisk(
        archiveFile.path,
        staging.path,
        bufferSize: 1024 * 1024,
      );

      onProgress(const OfflineTtsInstallProgress(0.92, '正在校验模型完整性'));
      final extractedRoot = await _findExtractedRoot(staging);
      if (extractedRoot == null || !_hasRequiredFiles(extractedRoot)) {
        throw const FormatException('模型包缺少必要文件');
      }
      final digest = await sha256
          .bind(
              File(path.join(extractedRoot.path, modelRelativePath)).openRead())
          .first;
      if (digest.toString() != modelSha256) {
        throw const FormatException('模型校验失败，请重新下载');
      }

      if (await destination.exists()) await destination.delete(recursive: true);
      if (path.equals(extractedRoot.path, staging.path)) {
        await staging.rename(destination.path);
      } else {
        await extractedRoot.rename(destination.path);
        if (await staging.exists()) await staging.delete(recursive: true);
      }
      await File(path.join(destination.path, '.verified'))
          .writeAsString(modelSha256, flush: true);
      onProgress(const OfflineTtsInstallProgress(1, '模型已就绪'));
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      // A fully downloaded archive is verified/consumed and never kept. An
      // interrupted one stays as a partial so the next attempt can resume.
      if (fullyDownloaded && await archiveFile.exists()) {
        await archiveFile.delete();
      }
    }
  }

  /// Removes the installed model directory (not shared data like samples).
  Future<void> deleteModel() async {
    final root = await modelDirectory;
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Downloads [uri] into [target] with the same resume/retry logic used for
  /// the model archive.
  Future<void> downloadTo(
    Uri uri,
    File target, {
    required ValueChanged<double> onProgress,
  }) =>
      _downloadFile(uri, target, onProgress: onProgress);

  /// Streams [uri] into [target], resuming from any existing partial bytes and
  /// retrying transient failures with a short backoff. On persistent failure the
  /// partial file is left in place so a later call can continue from the last
  /// received byte instead of restarting the whole archive.
  Future<void> _downloadFile(
    Uri uri,
    File target, {
    required ValueChanged<double> onProgress,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxDownloadAttempts; attempt++) {
      try {
        await _downloadOnce(uri, target, onProgress: onProgress);
        return;
      } on SocketException catch (e) {
        lastError = e;
      } on HttpException catch (e) {
        lastError = e;
      } on TimeoutException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt < _maxDownloadAttempts) {
        await Future<void>.delayed(_retryDelay * attempt);
      }
    }
    throw lastError!;
  }

  Future<void> _downloadOnce(
    Uri uri,
    File target, {
    required ValueChanged<double> onProgress,
  }) async {
    final client = http.Client();
    IOSink? sink;
    try {
      var start = 0;
      if (await target.exists()) start = await target.length();

      var request = http.Request('GET', uri);
      if (start > 0) request.headers['Range'] = 'bytes=$start-';
      var response = await client.send(request);

      if (response.statusCode == 416) {
        // The partial file is already complete or un-resumable: start over.
        await target.delete();
        start = 0;
        request = http.Request('GET', uri);
        response = await client.send(request);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('下载失败（${response.statusCode}）', uri: uri);
      }

      final isPartial = response.statusCode == 206 && start > 0;
      final total = response.contentLength == null
          ? 0
          : response.contentLength! + (isPartial ? start : 0);
      var received = isPartial ? start : 0;
      sink = target.openWrite(mode: isPartial ? FileMode.append : FileMode.write);
      await for (final chunk in response.stream.timeout(_idleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress(received / total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (total > 0 && received < total) {
        throw HttpException('下载不完整（$received/$total）', uri: uri);
      }
    } finally {
      await sink?.close();
      client.close();
    }
  }

  Future<Directory?> _findExtractedRoot(Directory staging) async {
    if (_hasRequiredFiles(staging)) return staging;
    final modelFileName = path.basename(modelRelativePath);
    await for (final entity
        in staging.list(recursive: true, followLinks: false)) {
      if (entity is File && path.basename(entity.path) == modelFileName) {
        final root = entity.parent;
        if (_hasRequiredFiles(root)) return root;
      }
    }
    return null;
  }

  bool _hasRequiredFiles(Directory root) {
    return requiredFiles.every((relative) {
      final entityPath = path.join(root.path, relative);
      return File(entityPath).existsSync() || Directory(entityPath).existsSync();
    });
  }
}
