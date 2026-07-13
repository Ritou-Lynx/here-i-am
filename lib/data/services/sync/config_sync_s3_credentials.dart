import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists S3-compatible object storage credentials in platform secure storage
/// (iOS Keychain / Android EncryptedSharedPreferences).
class ConfigSyncS3Credentials {
  ConfigSyncS3Credentials._();
  static final ConfigSyncS3Credentials instance = ConfigSyncS3Credentials._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyEndpoint = 'config_sync_s3_endpoint';
  static const _keyBucket = 'config_sync_s3_bucket';
  static const _keyAccessKey = 'config_sync_s3_access_key';
  static const _keySecretKey = 'config_sync_s3_secret_key';
  static const _keyRegion = 'config_sync_s3_region';
  static const _keyUseSSL = 'config_sync_s3_use_ssl';

  Future<bool> hasCredentials() async {
    final ep = await _storage.read(key: _keyEndpoint);
    final ak = await _storage.read(key: _keyAccessKey);
    return ep != null && ep.isNotEmpty && ak != null && ak.isNotEmpty;
  }

  Future<S3Config?> read() async {
    final endpoint = await _storage.read(key: _keyEndpoint);
    final bucket = await _storage.read(key: _keyBucket);
    final accessKey = await _storage.read(key: _keyAccessKey);
    final secretKey = await _storage.read(key: _keySecretKey);
    if (endpoint == null || bucket == null || accessKey == null || secretKey == null) {
      return null;
    }
    return S3Config(
      endpoint: endpoint,
      bucket: bucket,
      accessKey: accessKey,
      secretKey: secretKey,
      region: await _storage.read(key: _keyRegion),
      useSSL: (await _storage.read(key: _keyUseSSL)) != 'false',
    );
  }

  Future<void> save(S3Config config) async {
    await _storage.write(key: _keyEndpoint, value: config.endpoint);
    await _storage.write(key: _keyBucket, value: config.bucket);
    await _storage.write(key: _keyAccessKey, value: config.accessKey);
    await _storage.write(key: _keySecretKey, value: config.secretKey);
    await _storage.write(key: _keyRegion, value: config.region ?? '');
    await _storage.write(key: _keyUseSSL, value: config.useSSL.toString());
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyEndpoint);
    await _storage.delete(key: _keyBucket);
    await _storage.delete(key: _keyAccessKey);
    await _storage.delete(key: _keySecretKey);
    await _storage.delete(key: _keyRegion);
    await _storage.delete(key: _keyUseSSL);
  }
}

class S3Config {
  const S3Config({
    required this.endpoint,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    this.region,
    this.useSSL = true,
  });

  final String endpoint;
  final String bucket;
  final String accessKey;
  final String secretKey;
  final String? region;
  final bool useSSL;
}
