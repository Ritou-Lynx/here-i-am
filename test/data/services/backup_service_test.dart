import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/backup_service.dart';

void main() {
  group('BackupService.inspectBackup', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('memex_backup_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads backup manifest metadata', () async {
      final file = await _writeBackup(
        tempDir,
        'backup.memex',
        manifest: {
          'format': 'memex.backup',
          'backupSchemaVersion': BackupService.currentBackupSchemaVersion,
          'createdAt': '2026-05-15T00:00:00.000Z',
          'appVersion': '1.0.30',
          'buildNumber': '113',
          'flavor': 'globalEarly',
          'platform': 'android',
        },
      );

      final info = await BackupService.inspectBackup(file.path);

      expect(info.isLegacy, isFalse);
      expect(info.manifest?.appVersion, '1.0.30');
      expect(info.manifest?.buildNumber, '113');
      expect(info.manifest?.flavor, 'globalEarly');
    });

    test('accepts legacy backup without manifest', () async {
      final file = await _writeBackup(tempDir, 'legacy.memex');

      final info = await BackupService.inspectBackup(file.path);

      expect(info.isLegacy, isTrue);
      expect(info.manifest, isNull);
    });

    test('rejects newer backup schema', () async {
      final file = await _writeBackup(
        tempDir,
        'newer.memex',
        manifest: {
          'format': 'memex.backup',
          'backupSchemaVersion': BackupService.currentBackupSchemaVersion + 1,
          'createdAt': '2026-05-15T00:00:00.000Z',
        },
      );

      expect(
        () => BackupService.inspectBackup(file.path),
        throwsA(isA<UnsupportedBackupVersionException>()),
      );
    });

    test('rejects non-backup extension', () async {
      final file = await _writeBackup(tempDir, 'backup.txt');

      expect(
        () => BackupService.inspectBackup(file.path),
        throwsA(isA<InvalidBackupFileException>()),
      );
    });

    test('rejects zip without backup markers', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('notes.txt', 5, utf8.encode('hello')));
      final file = File('${tempDir.path}/random.memex');
      await file.writeAsBytes(ZipEncoder().encode(archive));

      expect(
        () => BackupService.inspectBackup(file.path),
        throwsA(isA<InvalidBackupFileException>()),
      );
    });
  });
}

Future<File> _writeBackup(
  Directory tempDir,
  String fileName, {
  Map<String, dynamic>? manifest,
}) async {
  final archive = Archive();
  if (manifest != null) {
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
  }
  final settingsBytes = utf8.encode(jsonEncode({'userId': 'test-user'}));
  archive.addFile(
    ArchiveFile('settings.json', settingsBytes.length, settingsBytes),
  );

  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(ZipEncoder().encode(archive));
  return file;
}
