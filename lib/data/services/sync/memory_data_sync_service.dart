import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/data/services/sync/config_sync_crypto.dart';
import 'package:memex/data/services/sync/config_sync_passphrase_store.dart';
import 'package:memex/data/services/sync/config_sync_s3.dart';
import 'package:memex/data/services/sync/config_sync_s3_credentials.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Encrypted snapshot transport for chat, Memory V3/Dreaming and the local
/// files they reference.
///
/// Version 1 deliberately uses full, last-writer-wins snapshots. It reuses the
/// proven `.memex` backup/restore path so SQLite WAL checkpointing, manifest
/// checksums, workspace media and restore safety remain one implementation.
/// Concurrent multi-device merging is intentionally not claimed here.
class MemoryDataSyncService {
  MemoryDataSyncService._();

  static final Logger _logger = getLogger('MemoryDataSyncService');

  static const String fileExtension = '.memexdata';
  static const int payloadVersion = 1;
  static const String payloadKind = 'here-i-am.data-snapshot';

  static bool isDataPackageFile(String filePath) =>
      filePath.toLowerCase().endsWith(fileExtension);

  /// Creates a validated `.memex` snapshot, frames it with authenticated
  /// metadata, then encrypts the whole frame.
  static Future<Map<String, dynamic>> collectEncryptedEnvelope({
    required String passphrase,
    void Function(String status)? onProgress,
  }) async {
    String? backupPath;
    try {
      onProgress?.call('正在生成一致性快照...');
      backupPath = await BackupService.createBackup(
        filePrefix: 'memory_sync_source',
        onProgress: onProgress,
      );
      await BackupService.inspectBackup(backupPath);
      final backupBytes = await File(backupPath).readAsBytes();
      final framed = frameBackupBytes(
        backupBytes,
        createdAt: DateTime.now().toUtc(),
      );
      onProgress?.call('正在加密数据快照...');
      final envelope = await ConfigSyncCrypto.sealBytes(framed, passphrase);
      envelope['package_kind'] = payloadKind;
      envelope['payload_version'] = payloadVersion;
      return envelope;
    } finally {
      if (backupPath != null) {
        final file = File(backupPath);
        if (await file.exists()) await file.delete();
      }
    }
  }

  static Future<String> exportPackage({
    required String passphrase,
    String? outputDirectory,
    void Function(String status)? onProgress,
  }) async {
    final envelope = await collectEncryptedEnvelope(
      passphrase: passphrase,
      onProgress: onProgress,
    );
    final dir = outputDirectory == null
        ? await getTemporaryDirectory()
        : Directory(outputDirectory);
    if (!await dir.exists()) await dir.create(recursive: true);

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .replaceAll('T', '_');
    final fileName = 'here_i_am_data_$stamp$fileExtension';
    final outputPath = path.join(dir.path, fileName);
    final tempPath = path.join(dir.path, '.$fileName.tmp');
    await File(tempPath).writeAsString(jsonEncode(envelope), flush: true);
    final target = File(outputPath);
    if (await target.exists()) await target.delete();
    await File(tempPath).rename(outputPath);
    return outputPath;
  }

  static Future<MemoryDataImportResult> importPackage({
    required String packagePath,
    required String passphrase,
    void Function(String status)? onProgress,
  }) async {
    final raw = await File(packagePath).readAsString();
    final Map<String, dynamic> envelope;
    try {
      envelope = (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      throw const ConfigSyncFormatException('not a valid data package');
    }
    return importEnvelope(
      envelope: envelope,
      passphrase: passphrase,
      onProgress: onProgress,
    );
  }

  /// Restores a downloaded encrypted snapshot. A local safety snapshot is
  /// always created before the destructive replace begins.
  static Future<MemoryDataImportResult> importEnvelope({
    required Map<String, dynamic> envelope,
    required String passphrase,
    void Function(String status)? onProgress,
  }) async {
    if (envelope['package_kind'] != payloadKind ||
        envelope['payload_version'] != payloadVersion) {
      throw const ConfigSyncFormatException('not a here-i-am data package');
    }

    onProgress?.call('正在解密并校验数据快照...');
    final framed = await ConfigSyncCrypto.openBytes(envelope, passphrase);
    final decoded = decodeFramedBackup(framed);

    final tempDir = await getTemporaryDirectory();
    final tempPath = path.join(
      tempDir.path,
      'memory_sync_restore_${DateTime.now().microsecondsSinceEpoch}.memex',
    );
    final tempFile = File(tempPath);
    try {
      await tempFile.writeAsBytes(decoded.backupBytes, flush: true);
      await BackupService.inspectBackup(tempPath);

      onProgress?.call('正在创建本机安全快照...');
      final safety = await BackupService.createSafetySnapshot(
        reason: 'before_memory_sync_import',
        onProgress: onProgress,
      );

      onProgress?.call('正在恢复数据快照...');
      await BackupService.restoreBackup(tempPath, onProgress: onProgress);
      _logger.info(
        'Memory data snapshot restored (${decoded.backupBytes.length} bytes)',
      );
      return MemoryDataImportResult(
        sourceCreatedAt: decoded.createdAt,
        restoredBytes: decoded.backupBytes.length,
        safetySnapshot: safety,
      );
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  @visibleForTesting
  static Uint8List frameBackupBytes(
    List<int> backupBytes, {
    required DateTime createdAt,
  }) {
    if (backupBytes.length > ConfigSyncCrypto.maxDataPackageBytes) {
      throw const ConfigSyncFormatException(
        'data snapshot is too large for this sync version',
      );
    }
    final header = utf8.encode(jsonEncode({
      'kind': payloadKind,
      'payload_version': payloadVersion,
      'created_at': createdAt.toIso8601String(),
      'backup_size': backupBytes.length,
      'backup_sha256': sha256.convert(backupBytes).toString(),
    }));
    final output = BytesBuilder(copy: false)
      ..add(_uint32(header.length))
      ..add(header)
      ..add(backupBytes);
    return output.takeBytes();
  }

  @visibleForTesting
  static DecodedMemoryDataSnapshot decodeFramedBackup(List<int> framed) {
    if (framed.length < 5) {
      throw const ConfigSyncFormatException('data payload is truncated');
    }
    final headerLength = ByteData.sublistView(Uint8List.fromList(framed))
        .getUint32(0, Endian.big);
    if (headerLength <= 0 || headerLength > framed.length - 4) {
      throw const ConfigSyncFormatException('data payload header is invalid');
    }
    final Map<String, dynamic> header;
    try {
      header =
          (jsonDecode(utf8.decode(framed.sublist(4, 4 + headerLength))) as Map)
              .cast<String, dynamic>();
    } catch (_) {
      throw const ConfigSyncFormatException('data payload header is invalid');
    }
    if (header['kind'] != payloadKind ||
        header['payload_version'] != payloadVersion) {
      throw const ConfigSyncFormatException('data payload kind is invalid');
    }
    final backupBytes = Uint8List.fromList(framed.sublist(4 + headerLength));
    final expectedSize = header['backup_size'];
    final expectedHash = header['backup_sha256'];
    if (expectedSize != backupBytes.length ||
        expectedHash != sha256.convert(backupBytes).toString()) {
      throw const ConfigSyncFormatException('data snapshot checksum mismatch');
    }
    final createdAt = DateTime.tryParse(header['created_at'] as String? ?? '');
    if (createdAt == null) {
      throw const ConfigSyncFormatException('data snapshot time is invalid');
    }
    return DecodedMemoryDataSnapshot(
      createdAt: createdAt,
      backupBytes: backupBytes,
    );
  }

  static Uint8List _uint32(int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }

  static const _autoCloudSyncInterval = Duration(hours: 24);

  /// Upload an encrypted data snapshot to S3 when conditions are met:
  /// cloud sync is enabled, ≥24 h since last upload, passphrase and S3
  /// credentials are present, and the source data fingerprint changed.
  ///
  /// Fire-and-forget safe: exceptions are logged, not rethrown.
  static Future<void> maybeAutoUploadToCloud() async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null || userId.isEmpty) return;

      final enabled = await UserStorage.isAutoCloudSyncEnabled(userId);
      if (!enabled) return;

      final lastUploadAt = await UserStorage.getLastCloudSyncAt(userId);
      final now = DateTime.now();
      if (lastUploadAt != null &&
          now.difference(lastUploadAt) < _autoCloudSyncInterval) {
        return;
      }

      final fingerprint = await _cloudFingerprint(userId);
      final lastFingerprint =
          await UserStorage.getLastCloudSyncFingerprint(userId);
      if (lastFingerprint == fingerprint) return;

      if (!await ConfigSyncS3Credentials.instance.hasCredentials()) return;

      final passphrase = await ConfigSyncPassphraseStore.instance.read();
      if (passphrase == null) return;

      _logger.info('Auto cloud sync: uploading ($userId) ...');
      final envelope = await collectEncryptedEnvelope(
        passphrase: passphrase,
        onProgress: (s) => _logger.info('Auto cloud sync: $s'),
      );
      final s3Config = await ConfigSyncS3Credentials.instance.read();
      if (s3Config == null) return;

      await ConfigSyncS3.upload(
        s3Config,
        envelope,
        targetObjectKey: ConfigSyncS3.dataObjectKey,
      );
      await UserStorage.setLastCloudSyncMetadata(
        userId,
        fingerprint: fingerprint,
        createdAt: now,
      );
      _logger.info(
        'Auto cloud sync: uploaded (${(envelope['ciphertext'] as String? ?? '').length} B ciphertext)',
      );
    } catch (e, stack) {
      _logger.warning('Auto cloud sync failed', e, stack);
      // Fire-and-forget: don't rethrow, don't block the app.
    }
  }

  static Future<String> _cloudFingerprint(String userId) async {
    final dbName = 'memex_local_$userId.sqlite';
    final appDir = await getApplicationDocumentsDirectory();
    final dbFile = File(path.join(appDir.path, dbName));
    if (!await dbFile.exists()) return 'no-db-$userId';
    final stat = await dbFile.stat();
    return '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  }
}

class DecodedMemoryDataSnapshot {
  const DecodedMemoryDataSnapshot({
    required this.createdAt,
    required this.backupBytes,
  });

  final DateTime createdAt;
  final Uint8List backupBytes;
}

class MemoryDataImportResult {
  const MemoryDataImportResult({
    required this.sourceCreatedAt,
    required this.restoredBytes,
    required this.safetySnapshot,
  });

  final DateTime sourceCreatedAt;
  final int restoredBytes;
  final BackupSnapshot safetySnapshot;
}
