import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await UserStorage.initL10n();
    await UserStorage.saveUser('backup-service-user');

    tempDir = await Directory.systemTemp.createTemp('memex_backup_service_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = FakePathProviderPlatform(tempDir.path);
    _mockPathProviderChannel(tempDir.path);
    await FileSystemService.init(tempDir.path);

    final workspace = Directory(
      FileSystemService.instance.getWorkspacePath('backup-service-user'),
    );
    await workspace.create(recursive: true);
    await File(
      p.join(workspace.path, 'Cards', 'card.md'),
    ).create(recursive: true);
    await File(
      p.join(workspace.path, 'Cards', 'card.md'),
    ).writeAsString('hello backup');
  });

  tearDown(() async {
    _clearPathProviderChannelMock();
    PathProviderPlatform.instance = originalPathProvider;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('createBackup writes manifest and workspace content', () async {
    final outputDir = Directory(p.join(tempDir.path, 'Backups'));
    final backupPath = await BackupService.createBackup(
      outputDirectory: outputDir.path,
    );

    final archive = ZipDecoder().decodeBytes(
      await File(backupPath).readAsBytes(),
    );

    expect(
      archive.files.map((file) => file.name),
      containsAll([
        'manifest.json',
        'settings.json',
        'workspace/Cards/card.md',
      ]),
    );

    final manifest = archive.files.firstWhere(
      (file) => file.name == 'manifest.json',
    );
    final manifestJson = jsonDecode(utf8.decode(manifest.content));

    expect(manifestJson['formatVersion'], 1);
    expect(manifestJson['entries'], isNotEmpty);
  });

  test('createBackup includes legacy absolute character media', () async {
    final workspace =
        FileSystemService.instance.getWorkspacePath('backup-service-user');
    final charactersDir = Directory(p.join(workspace, 'Characters'));
    await charactersDir.create(recursive: true);

    final legacyAvatar = File(p.join(tempDir.path, 'legacy_avatar.png'));
    final legacyBackground = File(p.join(tempDir.path, 'legacy_bg.jpg'));
    await legacyAvatar.writeAsBytes([1, 2, 3]);
    await legacyBackground.writeAsBytes([4, 5, 6]);
    await File(p.join(charactersDir.path, '7.yaml')).writeAsString(
      jsonEncode({
        'name': 'Legacy companion',
        'tags': <String>[],
        'persona': '',
        'enabled': true,
        'avatar': legacyAvatar.path,
        'chat_background': legacyBackground.path,
      }),
    );

    final backupPath = await BackupService.createBackup(
      outputDirectory: p.join(tempDir.path, 'Backups'),
    );
    final archive = ZipDecoder().decodeBytes(
      await File(backupPath).readAsBytes(),
    );
    final names = archive.files.map((file) => file.name).toList();
    final characterFile = archive.files.firstWhere(
      (file) => file.name == 'workspace/Characters/7.yaml',
    );
    final characterData = jsonDecode(utf8.decode(characterFile.content));

    expect(characterData['avatar'], isNot(legacyAvatar.path));
    expect(characterData['chat_background'], isNot(legacyBackground.path));
    expect(
      names.where(
        (name) => name.startsWith(
          'workspace/_System/media/character_media/7_avatar_',
        ),
      ),
      hasLength(1),
    );
    expect(
      names.where(
        (name) => name.startsWith(
          'workspace/_System/media/character_media/7_chat_background_',
        ),
      ),
      hasLength(1),
    );
  });

  test('restore path normalization repairs legacy character media paths',
      () async {
    final fs = FileSystemService.instance;
    const userId = 'backup-service-user';
    final workspace = fs.getWorkspacePath(userId);
    final charactersDir = Directory(p.join(workspace, 'Characters'));
    final mediaDir = Directory(p.join(workspace, '_System', 'media'));
    await charactersDir.create(recursive: true);
    await mediaDir.create(recursive: true);

    final avatar = File(p.join(mediaDir.path, 'avatar.png'));
    final background = File(p.join(mediaDir.path, 'background.jpg'));
    await avatar.writeAsBytes([1]);
    await background.writeAsBytes([2]);

    final legacyRoot = p.join(tempDir.path, 'old-package-data');
    await File(p.join(charactersDir.path, '8.yaml')).writeAsString(
      jsonEncode({
        'name': 'Restored companion',
        'tags': <String>[],
        'persona': '',
        'enabled': true,
        'avatar': p.join(
          legacyRoot,
          'workspace',
          '_$userId',
          '_System',
          'media',
          'avatar.png',
        ),
        'chat_background': p.join(
          legacyRoot,
          'workspace',
          '_$userId',
          '_System',
          'media',
          'background.jpg',
        ),
      }),
    );

    await BackupService.normalizeRestoredCharacterMediaPaths(fs, userId);

    final yaml = loadYaml(
      await File(p.join(charactersDir.path, '8.yaml')).readAsString(),
    );
    final data = jsonDecode(jsonEncode(yaml));
    expect(data['avatar'], fs.toRelativePath(avatar.path));
    expect(data['chat_background'], fs.toRelativePath(background.path));
  });

  test(
    'restore rejects a backup with a mismatched manifest checksum',
    () async {
      final outputDir = Directory(p.join(tempDir.path, 'Backups'));
      final backupPath = await BackupService.createBackup(
        outputDirectory: outputDir.path,
      );
      final archive = ZipDecoder().decodeBytes(
        await File(backupPath).readAsBytes(),
      );
      final corrupted = Archive();

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final bytes = file.name == 'workspace/Cards/card.md'
            ? utf8.encode('tampered workspace note')
            : List<int>.from(file.content);
        corrupted.addFile(ArchiveFile(file.name, bytes.length, bytes));
      }

      final corruptedPath = p.join(outputDir.path, 'tampered.memex');
      await File(corruptedPath).writeAsBytes(ZipEncoder().encode(corrupted));

      await expectLater(
        BackupService.restoreBackup(corruptedPath),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Backup checksum mismatch'),
          ),
        ),
      );
    },
  );

  test(
    'automatic backup skips a second run within twenty-four hours',
    () async {
      await UserStorage.setAutoBackupEnabled('backup-service-user', true);

      final first = await BackupService.maybeCreateAutoBackup(
        trigger: 'test-first',
      );
      final second = await BackupService.maybeCreateAutoBackup(
        trigger: 'test-second',
      );

      expect(first, isNotNull);
      expect(second, isNull);
    },
  );

  test(
    'automatic backup retention keeps the newest seven daily snapshots',
    () async {
      final backupDir = await BackupService.resolveDefaultBackupDirectory();
      final now = DateTime(2026, 5, 15, 12);

      for (var i = 0; i < 9; i += 1) {
        final file = File(
          p.join(
            backupDir.path,
            'memex_auto_2026-05-${(i + 1).toString().padLeft(2, '0')}T00-00-00.memex',
          ),
        );
        await file.writeAsBytes([i]);
        await file.setLastModified(now.subtract(Duration(days: 9 - i)));
      }

      await BackupService.createStoredBackup();

      final files = await backupDir
          .list()
          .where(
            (entity) =>
                entity is File &&
                p.basename(entity.path).startsWith('memex_auto'),
          )
          .toList();

      expect(files.length, lessThanOrEqualTo(7));
    },
  );

  test('safety snapshots are kept outside automatic retention', () async {
    final backupDir = await BackupService.resolveDefaultBackupDirectory();

    for (var i = 0; i < 9; i += 1) {
      final file = File(
        p.join(
          backupDir.path,
          'memex_auto_2026-05-${(i + 1).toString().padLeft(2, '0')}T00-00-00.memex',
        ),
      );
      await file.writeAsBytes([i]);
    }

    final safety = await BackupService.createSafetySnapshot(
      reason: 'before_storage_switch',
    );
    await BackupService.createStoredBackup();

    expect(await File(safety.filePath!).exists(), isTrue);
    final safetyFiles = await backupDir
        .list()
        .where(
          (entity) =>
              entity is File &&
              p
                  .basename(entity.path)
                  .startsWith('memex_safety_before_storage_switch'),
        )
        .toList();

    expect(safetyFiles, isNotEmpty);
  });

  group('inspectBackup', () {
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

void _mockPathProviderChannel(String rootPath) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      switch (call.method) {
        case 'getTemporaryDirectory':
        case 'getApplicationDocumentsDirectory':
        case 'getApplicationSupportDirectory':
        case 'getExternalStorageDirectory':
          return rootPath;
        case 'getExternalStorageDirectories':
          return <String>[rootPath];
      }
      return null;
    },
  );
}

void _clearPathProviderChannelMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    null,
  );
}

class FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String rootPath;

  FakePathProviderPlatform(this.rootPath);

  @override
  Future<String?> getTemporaryPath() async => rootPath;

  @override
  Future<String?> getApplicationSupportPath() async => rootPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootPath;

  @override
  Future<String?> getExternalStoragePath() async => rootPath;
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
