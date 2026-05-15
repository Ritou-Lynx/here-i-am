import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logging/logging.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';

/// Keys to exclude from backup (Flutter internals, not user data).
const _excludePrefKeys = <String>{'flutter.'};

const _backupManifestFileName = 'manifest.json';
const _backupFormat = 'memex.backup';
const _currentBackupSchemaVersion = 1;

class BackupManifest {
  final String format;
  final int backupSchemaVersion;
  final DateTime createdAt;
  final String appVersion;
  final String buildNumber;
  final String flavor;
  final String platform;

  const BackupManifest({
    required this.format,
    required this.backupSchemaVersion,
    required this.createdAt,
    required this.appVersion,
    required this.buildNumber,
    required this.flavor,
    required this.platform,
  });

  factory BackupManifest.fromJson(Map<String, dynamic> json) {
    return BackupManifest(
      format: json['format'] as String? ?? '',
      backupSchemaVersion: (json['backupSchemaVersion'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      appVersion: json['appVersion'] as String? ?? '',
      buildNumber: json['buildNumber']?.toString() ?? '',
      flavor: json['flavor'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'format': format,
        'backupSchemaVersion': backupSchemaVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'appVersion': appVersion,
        'buildNumber': buildNumber,
        'flavor': flavor,
        'platform': platform,
      };
}

class BackupFileInfo {
  final String path;
  final int sizeBytes;
  final BackupManifest? manifest;

  const BackupFileInfo({
    required this.path,
    required this.sizeBytes,
    required this.manifest,
  });

  bool get isLegacy => manifest == null;
}

class InvalidBackupFileException implements Exception {
  final String message;

  const InvalidBackupFileException(this.message);

  @override
  String toString() => message;
}

class UnsupportedBackupVersionException implements Exception {
  final int backupSchemaVersion;
  final int supportedSchemaVersion;

  const UnsupportedBackupVersionException({
    required this.backupSchemaVersion,
    required this.supportedSchemaVersion,
  });

  @override
  String toString() {
    return 'Backup schema $backupSchemaVersion is newer than supported schema '
        '$supportedSchemaVersion. Please update Memex before restoring.';
  }
}

/// Service for creating and restoring full app backups as .memex (zip) files.
class BackupService {
  static final Logger _logger = getLogger('BackupService');
  static const backupMimeType = 'application/x-memex-backup';
  static const currentBackupSchemaVersion = _currentBackupSchemaVersion;

  static bool isSelectableBackupFile(String filePath) {
    final lowerPath = _normalizeFilePath(filePath).toLowerCase();
    return lowerPath.endsWith('.memex') || lowerPath.endsWith('.zip');
  }

  static bool isMemexBackupFile(String filePath) {
    return _normalizeFilePath(filePath).toLowerCase().endsWith('.memex');
  }

  /// Create a backup zip containing:
  /// - workspace/ directory (Facts, Cards, PKM, KnowledgeInsights, etc.)
  /// - Drift SQLite DB file
  /// - settings.json (selected SharedPreferences keys)
  ///
  /// Returns the path to the generated .memex file.
  static Future<String> createBackup({
    void Function(String status)? onProgress,
  }) async {
    final userId = await UserStorage.getUserId();
    if (userId == null) throw Exception('No user logged in');

    final fs = FileSystemService.instance;
    final workspacePath = fs.getWorkspacePath(userId);
    final appDir = await getApplicationDocumentsDirectory();

    // Temp output path
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').substring(0, 19);
    final tempDir = await getTemporaryDirectory();
    final outputPath = path.join(tempDir.path, 'memex_backup_$timestamp.memex');

    final archive = Archive();

    // 0. Add backup manifest for cross-version compatibility checks.
    final manifest = await _createManifest();
    final manifestJson = utf8.encode(jsonEncode(manifest.toJson()));
    archive.addFile(
      ArchiveFile(_backupManifestFileName, manifestJson.length, manifestJson),
    );

    // 1. Add workspace files
    onProgress?.call('Packing workspace...');
    await _addDirectoryToArchive(archive, workspacePath, 'workspace');

    // 2. Add Drift DB file
    onProgress?.call('Packing database...');
    final dbName = 'memex_local_$userId.sqlite';
    // drift_flutter stores DB in app support directory on iOS, app documents on Android
    final possibleDbPaths = [
      path.join(appDir.path, dbName),
      path.join((await getApplicationSupportDirectory()).path, dbName),
    ];
    for (final dbPath in possibleDbPaths) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final bytes = await dbFile.readAsBytes();
        archive.addFile(ArchiveFile('db/$dbName', bytes.length, bytes));
        _logger.info('Added DB file: $dbPath (${bytes.length} bytes)');
        break;
      }
    }

    // 3. Add SharedPreferences settings — backup ALL keys
    onProgress?.call('Packing settings...');
    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      // Skip Flutter internal keys
      if (_excludePrefKeys.any((prefix) => key.startsWith(prefix))) continue;
      final value = prefs.get(key);
      if (value != null) {
        settings[key] = value;
      }
    }
    final settingsJson = utf8.encode(jsonEncode(settings));
    archive.addFile(
      ArchiveFile('settings.json', settingsJson.length, settingsJson),
    );

    // 4. Write zip
    onProgress?.call('Compressing...');
    final zipData = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipData);

    _logger.info('Backup created: $outputPath (${zipData.length} bytes)');
    return outputPath;
  }

  /// Restore from a .memex backup file.
  /// Overwrites workspace, DB, and settings.
  /// Returns true on success.
  static Future<bool> restoreBackup(
    String backupFilePath, {
    void Function(String status)? onProgress,
  }) async {
    final currentUserId = await UserStorage.getUserId();
    if (currentUserId == null) throw Exception('No user logged in');

    try {
      await inspectBackup(backupFilePath);

      onProgress?.call('Reading backup...');
      final bytes = await File(
        _normalizeFilePath(backupFilePath),
      ).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // 1. Restore settings FIRST to get the correct userId from backup
      onProgress?.call('Restoring settings...');
      for (final file in archive) {
        if (file.name == 'settings.json' && file.isFile) {
          final jsonStr = utf8.decode(file.content as List<int>);
          final settings = jsonDecode(jsonStr) as Map<String, dynamic>;
          final prefs = await SharedPreferences.getInstance();
          for (final entry in settings.entries) {
            final value = entry.value;
            if (value is String) {
              await prefs.setString(entry.key, value);
            } else if (value is int) {
              await prefs.setInt(entry.key, value);
            } else if (value is double) {
              await prefs.setDouble(entry.key, value);
            } else if (value is bool) {
              await prefs.setBool(entry.key, value);
            }
          }
          _logger.info('Restored ${settings.length} settings');
        }
      }

      // Use the restored userId (from backup settings) for workspace and DB paths
      final restoredUserId = await UserStorage.getUserId() ?? currentUserId;
      final fs = FileSystemService.instance;
      final workspacePath = fs.getWorkspacePath(restoredUserId);
      final appDir = await getApplicationDocumentsDirectory();

      // 2. Restore workspace files
      onProgress?.call('Restoring workspace...');
      for (final file in archive) {
        if (file.name.startsWith('workspace/') && !file.isFile) continue;
        if (!file.name.startsWith('workspace/')) continue;

        final relativePath = file.name.substring('workspace/'.length);
        if (relativePath.isEmpty) continue;

        final targetPath = path.join(workspacePath, relativePath);
        final targetDir = Directory(path.dirname(targetPath));
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        await File(targetPath).writeAsBytes(file.content as List<int>);
      }

      // 3. Restore DB
      onProgress?.call('Restoring database...');
      // Close current DB first
      if (AppDatabase.isInitialized) {
        await AppDatabase.instance.close();
      }

      for (final file in archive) {
        if (file.name.startsWith('db/') && file.isFile) {
          final dbFileName = path.basename(file.name);
          // Try both possible locations
          final supportDir = await getApplicationSupportDirectory();
          final possibleTargets = [
            path.join(appDir.path, dbFileName),
            path.join(supportDir.path, dbFileName),
          ];
          // Write to whichever location already has the file, or support dir
          String targetPath = possibleTargets.last;
          for (final p in possibleTargets) {
            if (await File(p).exists()) {
              targetPath = p;
              break;
            }
          }
          await File(targetPath).writeAsBytes(file.content as List<int>);
          _logger.info('Restored DB to: $targetPath');
        }
      }

      // Re-init DB
      await AppDatabase.init(restoredUserId);

      // 4. Rebuild card cache
      onProgress?.call('Rebuilding cache...');
      await fs.rebuildCardCache(restoredUserId);

      _logger.info('Backup restored successfully');
      return true;
    } catch (e, stack) {
      _logger.severe('Restore failed: $e', e, stack);
      // Try to re-init DB even on failure
      try {
        final userId = await UserStorage.getUserId();
        if (userId != null) await AppDatabase.init(userId);
      } catch (_) {}
      rethrow;
    }
  }

  /// Recursively add a directory to the archive.
  static Future<void> _addDirectoryToArchive(
    Archive archive,
    String dirPath,
    String archivePrefix,
  ) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = path.relative(entity.path, from: dirPath);
        final archivePath = '$archivePrefix/$relativePath';
        try {
          final bytes = await entity.readAsBytes();
          archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
        } catch (e) {
          _logger.warning('Skipping file ${entity.path}: $e');
        }
      }
    }
  }

  /// Get estimated backup size (workspace + DB).
  static Future<int> estimateBackupSize() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) return 0;

    final fs = FileSystemService.instance;
    final workspacePath = fs.getWorkspacePath(userId);
    int totalSize = 0;

    final dir = Directory(workspacePath);
    if (await dir.exists()) {
      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {}
        }
      }
    }

    return totalSize;
  }

  static Future<BackupFileInfo> inspectBackup(String backupFilePath) async {
    final normalizedPath = _normalizeFilePath(backupFilePath);
    if (!isSelectableBackupFile(normalizedPath)) {
      throw const InvalidBackupFileException(
        'Invalid backup file. Please select a .memex file.',
      );
    }

    final file = File(normalizedPath);
    if (!await file.exists()) {
      throw InvalidBackupFileException(
        'Backup file does not exist: $normalizedPath',
      );
    }

    final bytes = await file.readAsBytes();
    final archive = _decodeBackup(bytes);
    ArchiveFile? manifestFile;
    for (final file in archive.files) {
      if (file.isFile && file.name == _backupManifestFileName) {
        manifestFile = file;
        break;
      }
    }

    if (manifestFile == null) {
      if (!_looksLikeLegacyBackup(archive)) {
        throw const InvalidBackupFileException(
          'Invalid backup file. Please select a .memex file.',
        );
      }
      return BackupFileInfo(
        path: normalizedPath,
        sizeBytes: bytes.length,
        manifest: null,
      );
    }

    final manifest = _readManifest(manifestFile);
    if (manifest.format != _backupFormat) {
      throw InvalidBackupFileException(
        'Unsupported backup format: ${manifest.format}',
      );
    }
    if (manifest.backupSchemaVersion > _currentBackupSchemaVersion) {
      throw UnsupportedBackupVersionException(
        backupSchemaVersion: manifest.backupSchemaVersion,
        supportedSchemaVersion: _currentBackupSchemaVersion,
      );
    }

    return BackupFileInfo(
      path: normalizedPath,
      sizeBytes: bytes.length,
      manifest: manifest,
    );
  }

  static bool _looksLikeLegacyBackup(Archive archive) {
    return archive.files.any(
      (file) =>
          file.name == 'settings.json' ||
          file.name.startsWith('workspace/') ||
          file.name.startsWith('db/'),
    );
  }

  static Future<BackupManifest> _createManifest() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return BackupManifest(
      format: _backupFormat,
      backupSchemaVersion: _currentBackupSchemaVersion,
      createdAt: DateTime.now().toUtc(),
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      flavor: AppFlavor.name,
      platform: Platform.operatingSystem,
    );
  }

  static Archive _decodeBackup(List<int> bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const InvalidBackupFileException(
        'Invalid backup file. Please select a .memex file.',
      );
    }
  }

  static BackupManifest _readManifest(ArchiveFile manifestFile) {
    try {
      final jsonStr = utf8.decode(manifestFile.content as List<int>);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return BackupManifest.fromJson(json);
    } catch (_) {
      throw const InvalidBackupFileException('Invalid backup manifest.');
    }
  }

  static String _normalizeFilePath(String filePath) {
    if (filePath.startsWith('file://')) {
      try {
        return Uri.parse(filePath).toFilePath();
      } catch (_) {
        return filePath.replaceFirst('file://', '');
      }
    }
    return filePath;
  }
}
