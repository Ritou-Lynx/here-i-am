import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Password-derived AES-256-GCM envelope for encrypted config sync packages.
///
/// Byte-for-byte compatible with the i continuity gateway's device-sync
/// envelope (`tools/i_continuity_gateway/i_device_sync.mjs`), so a package
/// sealed on-device can be opened by the desktop gateway and vice versa:
///   - KDF: PBKDF2-HMAC-SHA256, 600_000 iterations, 32-byte key
///   - Cipher: AES-256-GCM, 16-byte salt, 12-byte iv/nonce, 16-byte tag
///   - Fields base64url-encoded (no padding), wrapped in a JSON envelope with
///     `schema_version` / `type` / `kdf` / `cipher` / `ciphertext`.
class ConfigSyncCrypto {
  ConfigSyncCrypto._();

  static const int iterations = 600000;
  static const int _saltBytes = 16;
  static const int _ivBytes = 12;
  static const int _tagBytes = 16;
  static const int _keyBytes = 32;
  static const int maxPackageBytes = 16 * 1024 * 1024;

  static const int schemaVersion = 1;
  static const String envelopeType = 'i.device-sync.encrypted';
  static const String _kdfName = 'pbkdf2-sha256';
  static const String _cipherName = 'aes-256-gcm';

  static const int minPassphraseLength = 16;

  /// Encrypt [value] (a JSON-encodable object) into the shared envelope.
  static Future<Map<String, dynamic>> seal(
    Object? value,
    String passphrase,
  ) async {
    _requirePassphrase(passphrase);
    final salt = _randomBytes(_saltBytes);
    final iv = _randomBytes(_ivBytes);
    final key = await _deriveKey(passphrase, salt);

    final plaintext = utf8.encode(jsonEncode(value));
    final algorithm = AesGcm.with256bits(nonceLength: _ivBytes);
    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: iv,
    );

    return {
      'schema_version': schemaVersion,
      'type': envelopeType,
      'kdf': {
        'name': _kdfName,
        'iterations': iterations,
        'salt': _b64UrlEncode(salt),
      },
      'cipher': {
        'name': _cipherName,
        'iv': _b64UrlEncode(iv),
        'tag': _b64UrlEncode(secretBox.mac.bytes),
      },
      'ciphertext': _b64UrlEncode(secretBox.cipherText),
    };
  }

  /// Decrypt an envelope produced by [seal] (or the gateway) back to its
  /// original JSON-decoded value. Throws [ConfigSyncFormatException] on a
  /// malformed envelope and [ConfigSyncDecryptException] on a wrong passphrase
  /// or tampered ciphertext.
  static Future<Object?> open(
    Map<String, dynamic> envelope,
    String passphrase,
  ) async {
    _requirePassphrase(passphrase);
    _validateEnvelope(envelope);

    final kdf = envelope['kdf'] as Map<String, dynamic>;
    final cipher = envelope['cipher'] as Map<String, dynamic>;
    final salt = _b64UrlDecode(kdf['salt'] as String);
    final iv = _b64UrlDecode(cipher['iv'] as String);
    final tag = _b64UrlDecode(cipher['tag'] as String);
    final ciphertext = _b64UrlDecode(envelope['ciphertext'] as String);

    if (salt.length != _saltBytes ||
        iv.length != _ivBytes ||
        tag.length != _tagBytes ||
        ciphertext.length > maxPackageBytes) {
      throw const ConfigSyncFormatException(
        'sync package cryptographic fields are invalid',
      );
    }

    final key = await _deriveKey(passphrase, salt);
    final algorithm = AesGcm.with256bits(nonceLength: _ivBytes);
    final secretBox = SecretBox(ciphertext, nonce: iv, mac: Mac(tag));

    final List<int> plaintext;
    try {
      plaintext = await algorithm.decrypt(secretBox, secretKey: SecretKey(key));
    } on SecretBoxAuthenticationError {
      throw const ConfigSyncDecryptException(
        'wrong passphrase or corrupted sync package',
      );
    }
    return jsonDecode(utf8.decode(plaintext));
  }

  static void _validateEnvelope(Map<String, dynamic> envelope) {
    final kdf = envelope['kdf'];
    final cipher = envelope['cipher'];
    if (envelope['schema_version'] != schemaVersion ||
        envelope['type'] != envelopeType ||
        kdf is! Map ||
        kdf['name'] != _kdfName ||
        kdf['iterations'] != iterations ||
        cipher is! Map ||
        cipher['name'] != _cipherName) {
      throw const ConfigSyncFormatException('sync package format is invalid');
    }
  }

  static Future<List<int>> _deriveKey(String passphrase, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _keyBytes * 8,
    );
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    return secretKey.extractBytes();
  }

  static void _requirePassphrase(String passphrase) {
    if (passphrase.length < minPassphraseLength) {
      throw const ConfigSyncFormatException(
        'passphrase must contain at least $minPassphraseLength characters',
      );
    }
  }

  static Uint8List _randomBytes(int length) {
    // SecretKeyData.random uses a cryptographically secure RNG.
    return Uint8List.fromList(
      SecretKeyData.random(length: length).bytes,
    );
  }

  /// base64url without padding, matching Node's `Buffer.toString('base64url')`.
  static String _b64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Decodes base64url with or without padding (gateway packages omit it).
  static Uint8List _b64UrlDecode(String value) {
    final padded = value.padRight((value.length + 3) & ~3, '=');
    return base64Url.decode(padded);
  }
}

/// Thrown when an envelope is structurally invalid (wrong version/type/fields).
class ConfigSyncFormatException implements Exception {
  const ConfigSyncFormatException(this.message);
  final String message;
  @override
  String toString() => 'ConfigSyncFormatException: $message';
}

/// Thrown when decryption fails: wrong passphrase or tampered ciphertext.
class ConfigSyncDecryptException implements Exception {
  const ConfigSyncDecryptException(this.message);
  final String message;
  @override
  String toString() => 'ConfigSyncDecryptException: $message';
}
