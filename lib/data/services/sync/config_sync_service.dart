import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:memex/config/app_flavor.dart';
import 'package:memex/data/services/backup_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/sync/config_sync_crypto.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Exports/imports an encrypted *configuration* package — distinct from
/// [BackupService]'s full backup, which also ships the (large) Drift chat/
/// memory database. This package carries only portable user configuration:
///
///   1. Portable SharedPreferences (LLM configs, prefs, tokens) — reusing
///      [BackupService.isPortablePreference] to decide what travels.
///   2. Character personas — `{workspace}/Characters/*.yaml`.
///   3. Custom agent configs — `{workspace}/_UserSettings/agent_configs/*.json`.
///
/// The payload is sealed with [ConfigSyncCrypto] (password-derived
/// AES-256-GCM, gateway-compatible) and written as a `.memexcfg` file. This is
/// the "config sync" first step: export/import closed loop, manual transport.
class ConfigSyncService {
  ConfigSyncService._();

  static final Logger _logger = getLogger('ConfigSyncService');

  static const String fileExtension = '.memexcfg';
  static const int payloadVersion = 1;
  static const String payloadKind = 'here-i-am.config';

  static const String _charactersDir = 'Characters';
  static const List<String> _agentConfigsDirParts = [
    '_UserSettings',
    'agent_configs',
  ];

  static bool isConfigPackageFile(String filePath) =>
      filePath.toLowerCase().endsWith(fileExtension);

  /// Collect the portable configuration payload as a plain (unencrypted) map.
  /// Kept separate from sealing so it can be unit-tested directly.
  static Future<Map<String, dynamic>> collectPayload() async {
    final userId = await UserStorage.getUserId();
    if (userId == null) throw StateError('No user logged in');

    final prefs = await SharedPreferences.getInstance();
    final settings = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!BackupService.isPortablePreference(key)) continue;
      final value = prefs.get(key);
      if (value != null) settings[key] = value;
    }

    final fs = FileSystemService.instance;
    final workspace = fs.getWorkspacePath(userId);

    final characters = await _readDirFiles(
      path.join(workspace, _charactersDir),
      extensions: const ['.yaml', '.yml'],
    );
    final agentConfigs = await _readDirFiles(
      path.joinAll([workspace, ..._agentConfigsDirParts]),
      extensions: const ['.json'],
    );

    var appVersion = 'unknown';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {}

    return {
      'payload_version': payloadVersion,
      'kind': payloadKind,
      'created_at': DateTime.now().toIso8601String(),
      'app_version': appVersion,
      'build_number': buildNumber,
      'flavor': AppFlavor.name,
      'platform': Platform.operatingSystem,
      'settings': settings,
      'characters': characters,
      'agent_configs': agentConfigs,
    };
  }

  /// Read every file in [dirPath] with a matching extension into a
  /// {relativeFileName: utf8Content} map. Missing dir → empty map.
  static Future<Map<String, String>> _readDirFiles(
    String dirPath, {
    required List<String> extensions,
  }) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return {};
    final result = <String, String>{};
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      final lower = name.toLowerCase();
      if (!extensions.any(lower.endsWith)) continue;
      result[name] = await entity.readAsString();
    }
    return result;
  }

  /// Export an encrypted config package to [outputDirectory] (temp dir if
  /// null). Returns the written file path. The [passphrase] is the sole key.
  static Future<String> exportPackage({
    required String passphrase,
    String? outputDirectory,
    String filePrefix = 'here_i_am_config',
  }) async {
    final payload = await collectPayload();
    final envelope = await ConfigSyncCrypto.seal(payload, passphrase);

    final dir = outputDirectory == null
        ? await getTemporaryDirectory()
        : Directory(outputDirectory);
    if (!await dir.exists()) await dir.create(recursive: true);

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .replaceAll('T', '_');
    final fileName = '${filePrefix}_$stamp$fileExtension';
    final outputPath = path.join(dir.path, fileName);
    final tempPath = path.join(dir.path, '.$fileName.tmp');

    // temp + rename so a reader never observes a partial file.
    await File(tempPath).writeAsString(jsonEncode(envelope), flush: true);
    final target = File(outputPath);
    if (await target.exists()) await target.delete();
    await File(tempPath).rename(outputPath);

    _logger.info('Config package exported: $outputPath '
        '(${(payload['characters'] as Map).length} characters, '
        '${(payload['settings'] as Map).length} settings)');
    return outputPath;
  }

  /// Result of a successful import, for surfacing counts in the UI.
  static Future<ConfigImportResult> importPackage({
    required String packagePath,
    required String passphrase,
  }) async {
    final raw = await File(packagePath).readAsString();
    final Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      throw const ConfigSyncFormatException('not a valid config package');
    }

    final decoded = await ConfigSyncCrypto.open(envelope, passphrase);
    if (decoded is! Map<String, dynamic>) {
      throw const ConfigSyncFormatException('config payload is malformed');
    }
    if (decoded['kind'] != payloadKind) {
      throw const ConfigSyncFormatException('not a here-i-am config package');
    }

    return importFromPayload(decoded);
  }

  /// Import from an already-decrypted payload map. Used by both file import
  /// and cloud download paths.
  static Future<ConfigImportResult> importFromPayload(
    Map<String, dynamic> decoded,
  ) async {
    final settings = (decoded['settings'] as Map?)?.cast<String, dynamic>() ??
        const {};
    final prefs = await SharedPreferences.getInstance();
    var settingsRestored = 0;
    for (final entry in settings.entries) {
      if (!BackupService.isPortablePreference(entry.key)) continue;
      final value = entry.value;
      if (value is String) {
        await prefs.setString(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is List && value.every((e) => e is String)) {
        await prefs.setStringList(entry.key, value.cast<String>());
      } else {
        continue;
      }
      settingsRestored++;
    }

    // Resolve workspace with the (possibly just-restored) userId.
    final userId = await UserStorage.getUserId();
    if (userId == null) throw StateError('No user after settings restore');
    final fs = FileSystemService.instance;
    final workspace = fs.getWorkspacePath(userId);

    // 2. Character personas
    final characters =
        (decoded['characters'] as Map?)?.cast<String, dynamic>() ?? const {};
    final charsRestored = await _writeDirFiles(
      path.join(workspace, _charactersDir),
      characters,
    );

    // 3. Custom agent configs
    final agentConfigs =
        (decoded['agent_configs'] as Map?)?.cast<String, dynamic>() ??
            const {};
    final agentsRestored = await _writeDirFiles(
      path.joinAll([workspace, ..._agentConfigsDirParts]),
      agentConfigs,
    );

    _logger.info('Config package imported: $settingsRestored settings, '
        '$charsRestored characters, $agentsRestored agent configs');
    return ConfigImportResult(
      settings: settingsRestored,
      characters: charsRestored,
      agentConfigs: agentsRestored,
    );
  }

  /// Write {fileName: content} into [dirPath], creating it if needed.
  /// Returns the number of files written.
  static Future<int> _writeDirFiles(
    String dirPath,
    Map<String, dynamic> files,
  ) async {
    if (files.isEmpty) return 0;
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    var count = 0;
    for (final entry in files.entries) {
      final content = entry.value;
      if (content is! String) continue;
      // Guard against path traversal from a tampered payload.
      final safeName = path.basename(entry.key);
      await File(path.join(dirPath, safeName)).writeAsString(content);
      count++;
    }
    return count;
  }
}

/// Counts from a successful [ConfigSyncService.importPackage].
class ConfigImportResult {
  const ConfigImportResult({
    required this.settings,
    required this.characters,
    required this.agentConfigs,
  });

  final int settings;
  final int characters;
  final int agentConfigs;
}
