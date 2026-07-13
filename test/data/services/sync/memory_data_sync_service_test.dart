import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/config_sync_crypto.dart';
import 'package:memex/data/services/sync/memory_data_sync_service.dart';

void main() {
  group('MemoryDataSyncService framing', () {
    final createdAt = DateTime.utc(2026, 7, 13, 16, 30);
    final backup = Uint8List.fromList(
      List<int>.generate(4096, (index) => index % 239),
    );

    test('round-trips backup bytes and authenticated metadata', () {
      final framed = MemoryDataSyncService.frameBackupBytes(
        backup,
        createdAt: createdAt,
      );

      final decoded = MemoryDataSyncService.decodeFramedBackup(framed);

      expect(decoded.createdAt, createdAt);
      expect(decoded.backupBytes, backup);
    });

    test('rejects a changed backup body', () {
      final framed = MemoryDataSyncService.frameBackupBytes(
        backup,
        createdAt: createdAt,
      );
      framed[framed.length - 1] ^= 1;

      expect(
        () => MemoryDataSyncService.decodeFramedBackup(framed),
        throwsA(isA<ConfigSyncFormatException>()),
      );
    });

    test('rejects a truncated payload', () {
      expect(
        () => MemoryDataSyncService.decodeFramedBackup([0, 0, 0, 12, 1]),
        throwsA(isA<ConfigSyncFormatException>()),
      );
    });
  });
}
