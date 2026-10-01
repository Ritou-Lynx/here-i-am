import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'android_activity_normalizer.dart';

abstract interface class ActivityIntegrityStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Dedicated Android Keystore-backed namespace for MDA-2 outbox integrity.
/// resetOnError is disabled so corruption never silently creates new authority.
final class FlutterSecureActivityIntegrityStorage
    implements ActivityIntegrityStorage {
  FlutterSecureActivityIntegrityStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              resetOnError: false,
              migrateOnAlgorithmChange: false,
              storageNamespace: 'mda2_activity_integrity_v1',
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Owns exactly one 32-byte random authority. It is not a Core token, sync
/// passphrase, BLE credential, or transport secret and must never be logged.
final class ActivityIntegrityKeyRepository {
  ActivityIntegrityKeyRepository({
    required ActivityIntegrityStorage storage,
    List<int> Function(int length)? randomBytes,
  }) : _storage = storage,
       _randomBytes = randomBytes ?? _secureRandomBytes;

  static const _storageKey = 'mda2_outbox_integrity_key_v1';
  static const keyLength = 32;
  final ActivityIntegrityStorage _storage;
  final List<int> Function(int length) _randomBytes;

  /// Explicit provisioning operation. Missing authority is never repaired by
  /// [readRequired], while a valid existing authority is returned unchanged.
  Future<List<int>> provision() async {
    final existing = await _readRaw();
    if (existing != null) return _decode(existing);
    final generated = _randomBytes(keyLength);
    if (generated.length != keyLength ||
        generated.any((byte) => byte < 0 || byte > 255)) {
      throw const AndroidActivityException('integrity_key_generation_failed');
    }
    final encoded = base64UrlEncode(generated);
    try {
      await _storage.write(_storageKey, encoded);
    } catch (_) {
      throw const AndroidActivityException('integrity_key_write_failed');
    }
    final persisted = await _readRaw();
    if (persisted == null || persisted != encoded) {
      throw const AndroidActivityException('integrity_key_write_failed');
    }
    return List<int>.unmodifiable(generated);
  }

  Future<List<int>> readRequired() async {
    final encoded = await _readRaw();
    if (encoded == null) {
      throw const AndroidActivityException('integrity_key_missing');
    }
    return _decode(encoded);
  }

  Future<void> clear() async {
    try {
      await _storage.delete(_storageKey);
      if (await _storage.read(_storageKey) != null) {
        throw const AndroidActivityException('integrity_key_clear_failed');
      }
    } on AndroidActivityException {
      rethrow;
    } catch (_) {
      throw const AndroidActivityException('integrity_key_clear_failed');
    }
  }

  Future<String?> _readRaw() async {
    try {
      return await _storage.read(_storageKey);
    } catch (_) {
      throw const AndroidActivityException('integrity_key_unavailable');
    }
  }

  List<int> _decode(String encoded) {
    try {
      final decoded = base64Url.decode(encoded);
      if (decoded.length != keyLength || base64UrlEncode(decoded) != encoded) {
        throw const FormatException();
      }
      return List<int>.unmodifiable(decoded);
    } catch (_) {
      throw const AndroidActivityException('integrity_key_invalid');
    }
  }

  static List<int> _secureRandomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
