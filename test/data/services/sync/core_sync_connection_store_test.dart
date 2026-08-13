import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';

void main() {
  test('normalizes HTTPS core URLs and trims one trailing slash', () {
    expect(
      CoreSyncConnection.normalizeBaseUrl(' https://host.example.invalid/ '),
      'https://host.example.invalid',
    );
  });

  test('allows loopback HTTP for local and USB development', () {
    expect(
      CoreSyncConnection.normalizeBaseUrl('http://127.0.0.1:47841/'),
      'http://127.0.0.1:47841',
    );
    expect(
      CoreSyncConnection.normalizeBaseUrl('http://localhost:47841'),
      'http://localhost:47841',
    );
  });

  test('rejects insecure remote and ambiguous URLs', () {
    expect(
      () => CoreSyncConnection.normalizeBaseUrl('http://192.168.1.8:47841'),
      throwsFormatException,
    );
    expect(
      () => CoreSyncConnection.normalizeBaseUrl('host.example.invalid'),
      throwsFormatException,
    );
    expect(
      () => CoreSyncConnection.normalizeBaseUrl(
        'https://host.example.invalid?token=secret',
      ),
      throwsFormatException,
    );
    expect(
      () => CoreSyncConnection.normalizeBaseUrl(
        'https://host.example.invalid/v1/core',
      ),
      throwsFormatException,
    );
    expect(
      () => CoreSyncConnection.normalizeBaseUrl(
        'https://user:secret@host.example.invalid',
      ),
      throwsFormatException,
    );
  });
}
