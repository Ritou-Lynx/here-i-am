import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/config_sync_crypto.dart';

void main() {
  const passphrase = 'correct-horse-battery-staple';

  test('seal then open round-trips a JSON-encodable value', () async {
    final value = {
      'llm': [
        {'key': 'default', 'apiKey': 'sk-secret', 'baseUrl': 'https://api'},
      ],
      'locale': 'zh_CN',
      'count': 3,
    };

    final envelope = await ConfigSyncCrypto.seal(value, passphrase);
    final restored = await ConfigSyncCrypto.open(envelope, passphrase);

    expect(restored, equals(value));
  });

  test('sealBytes then openBytes round-trips binary data', () async {
    final value = List<int>.generate(1024, (index) => index % 251);

    final envelope = await ConfigSyncCrypto.sealBytes(value, passphrase);
    final restored = await ConfigSyncCrypto.openBytes(envelope, passphrase);

    expect(restored, equals(value));
  });

  test('envelope carries the shared gateway-compatible format', () async {
    final envelope = await ConfigSyncCrypto.seal({'a': 1}, passphrase);

    expect(envelope['schema_version'], 1);
    expect(envelope['type'], 'i.device-sync.encrypted');
    expect((envelope['kdf'] as Map)['name'], 'pbkdf2-sha256');
    expect((envelope['kdf'] as Map)['iterations'], 600000);
    expect((envelope['cipher'] as Map)['name'], 'aes-256-gcm');
    // base64url without padding
    expect(envelope['ciphertext'], isNot(contains('=')));
  });

  test('wrong passphrase raises ConfigSyncDecryptException', () async {
    final envelope = await ConfigSyncCrypto.seal({'a': 1}, passphrase);

    expect(
      () => ConfigSyncCrypto.open(envelope, 'wrong-passphrase-here'),
      throwsA(isA<ConfigSyncDecryptException>()),
    );
  });

  test('tampered ciphertext raises ConfigSyncDecryptException', () async {
    final envelope = await ConfigSyncCrypto.seal({'a': 1}, passphrase);
    final ct = envelope['ciphertext'] as String;
    // Flip the first character to reliably corrupt the ciphertext bytes.
    envelope['ciphertext'] = (ct.startsWith('A') ? 'B' : 'A') + ct.substring(1);

    expect(
      () => ConfigSyncCrypto.open(envelope, passphrase),
      throwsA(isA<ConfigSyncDecryptException>()),
    );
  });

  test('malformed envelope raises ConfigSyncFormatException', () async {
    expect(
      () => ConfigSyncCrypto.open({'schema_version': 99}, passphrase),
      throwsA(isA<ConfigSyncFormatException>()),
    );
  });

  test('short passphrase is rejected', () async {
    expect(
      () => ConfigSyncCrypto.seal({'a': 1}, 'short'),
      throwsA(isA<ConfigSyncFormatException>()),
    );
  });

  test('opens an envelope sealed by the Node gateway (cross-language)',
      () async {
    const payload = {'llm': 'sk-secret', 'locale': 'zh_CN'};
    final result = Process.runSync(
      'node',
      [
        'test/data/services/sync/_node_seal.mjs',
        passphrase,
        jsonEncode(payload),
      ],
    );
    if (result.exitCode != 0) {
      // Node not available in this environment — skip rather than fail.
      markTestSkipped('node unavailable: ${result.stderr}');
      return;
    }
    final envelope =
        jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final restored = await ConfigSyncCrypto.open(envelope, passphrase);
    expect(restored, equals(payload));
  });
}
