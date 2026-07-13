import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:memex/data/services/sync/config_sync_crypto.dart';

/// Stores the config-sync passphrase in platform secure storage
/// (iOS Keychain / Android Keystore-backed EncryptedSharedPreferences),
/// so the user sets it once and does not re-type it on every export/import.
///
/// The passphrase is the sole key material for [ConfigSyncCrypto]; it is never
/// written to SharedPreferences, logs, or the backup archive itself.
class ConfigSyncPassphraseStore {
  ConfigSyncPassphraseStore._();

  static final ConfigSyncPassphraseStore instance =
      ConfigSyncPassphraseStore._();

  static const String _key = 'config_sync_passphrase';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Whether a passphrase has already been set on this device.
  Future<bool> hasPassphrase() => _storage.containsKey(key: _key);

  /// Returns the stored passphrase, or null if none is set.
  Future<String?> read() => _storage.read(key: _key);

  /// Persists [passphrase], rejecting values shorter than the minimum length
  /// required by [ConfigSyncCrypto].
  Future<void> save(String passphrase) async {
    if (passphrase.length < ConfigSyncCrypto.minPassphraseLength) {
      throw ArgumentError(
        'passphrase must contain at least '
        '${ConfigSyncCrypto.minPassphraseLength} characters',
      );
    }
    await _storage.write(key: _key, value: passphrase);
  }

  /// Removes the stored passphrase (e.g. on user request or sign-out).
  Future<void> clear() => _storage.delete(key: _key);
}
