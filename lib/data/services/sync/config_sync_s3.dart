import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:minio/minio.dart';

import 'package:memex/data/services/sync/config_sync_s3_credentials.dart';
import 'package:memex/utils/logger.dart';

/// S3 transport layer for encrypted config packages.
///
/// Uploads/downloads the sealed `.memexcfg` JSON envelope to a fixed object
/// key in the user's configured bucket. The file is already encrypted by
/// [ConfigSyncCrypto] before reaching this layer — S3 sees only ciphertext.
class ConfigSyncS3 {
  ConfigSyncS3._();

  static final Logger _logger = getLogger('ConfigSyncS3');

  static const String objectKey = 'here-i-am/config_latest.memexcfg';
  static const String dataObjectKey = 'here-i-am/data_latest.memexdata';

  static Minio _client(S3Config config) {
    return Minio(
      endPoint: config.endpoint,
      accessKey: config.accessKey,
      secretKey: config.secretKey,
      useSSL: config.useSSL,
      region: config.region,
      // Aliyun OSS (and most S3-compatible services) require virtual-hosted
      // style: <bucket>.<endpoint>. Path-style is rejected with 403
      // SecondLevelDomainForbidden.
      pathStyle: false,
    );
  }

  /// Upload an encrypted config envelope (JSON map) to S3.
  /// Returns the ETag on success.
  static Future<String> upload(
    S3Config config,
    Map<String, dynamic> envelope, {
    String targetObjectKey = objectKey,
  }) async {
    final minio = _client(config);

    final exists = await minio.bucketExists(config.bucket);
    if (!exists) {
      throw ConfigSyncS3Exception(
        'Bucket "${config.bucket}" does not exist or is not accessible.',
      );
    }

    final bytes = utf8.encode(jsonEncode(envelope));
    final stream = Stream<Uint8List>.value(Uint8List.fromList(bytes));

    final etag = await minio.putObject(
      config.bucket,
      targetObjectKey,
      stream,
      size: bytes.length,
      metadata: {'Content-Type': 'application/json'},
    );

    _logger.info('Encrypted package uploaded to '
        's3://${config.bucket}/$targetObjectKey '
        '(${bytes.length} bytes, etag: $etag)');
    return etag;
  }

  /// Download the encrypted config envelope from S3.
  /// Returns the parsed JSON map (still encrypted — caller decrypts).
  static Future<Map<String, dynamic>> download(
    S3Config config, {
    String targetObjectKey = objectKey,
  }) async {
    final minio = _client(config);

    final exists = await minio.bucketExists(config.bucket);
    if (!exists) {
      throw ConfigSyncS3Exception(
        'Bucket "${config.bucket}" does not exist or is not accessible.',
      );
    }

    final MinioByteStream response;
    try {
      response = await minio.getObject(config.bucket, targetObjectKey);
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey') {
        throw const ConfigSyncS3Exception(
          'No encrypted package found in cloud. Upload one first.',
        );
      }
      rethrow;
    }

    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    final allBytes = chunks.expand((c) => c).toList();
    final json = utf8.decode(allBytes);

    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(json) as Map<String, dynamic>;
    } on FormatException {
      throw const ConfigSyncS3Exception(
        'Downloaded file is not a valid encrypted package.',
      );
    }

    _logger.info('Encrypted package downloaded from '
        's3://${config.bucket}/$targetObjectKey '
        '(${allBytes.length} bytes)');
    return envelope;
  }

  /// Check if a config package exists in the bucket.
  static Future<ConfigSyncS3Status> status(
    S3Config config, {
    String targetObjectKey = objectKey,
  }) async {
    final minio = _client(config);

    final bucketOk = await minio.bucketExists(config.bucket);
    if (!bucketOk) {
      return const ConfigSyncS3Status(
        exists: false,
        message: 'Bucket not accessible',
      );
    }

    try {
      final stat = await minio.statObject(config.bucket, targetObjectKey);
      return ConfigSyncS3Status(
        exists: true,
        lastModified: stat.lastModified,
        size: stat.size,
      );
    } on MinioS3Error catch (e) {
      if (e.error?.code == 'NoSuchKey' || e.response?.statusCode == 404) {
        return const ConfigSyncS3Status(
          exists: false,
          message: 'No config in cloud yet',
        );
      }
      rethrow;
    }
  }
}

class ConfigSyncS3Status {
  const ConfigSyncS3Status({
    required this.exists,
    this.lastModified,
    this.size,
    this.message,
  });

  final bool exists;
  final DateTime? lastModified;
  final int? size;
  final String? message;
}

class ConfigSyncS3Exception implements Exception {
  const ConfigSyncS3Exception(this.message);
  final String message;

  @override
  String toString() => 'ConfigSyncS3Exception: $message';
}
