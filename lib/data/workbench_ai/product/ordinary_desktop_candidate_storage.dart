import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import '../../../db/app_database.dart';

/// Debug-only storage admission for one ordinary Windows desktop candidate.
///
/// Call [install] before any legacy SharedPreferences, UserStorage, or
/// AppDatabase use. The root is either admitted as an empty first-run root,
/// or reopened only when its marker, top-level layout, and candidate id match.
class OrdinaryDesktopCandidateStorage {
  OrdinaryDesktopCandidateStorage._({
    required String rootPath,
    required this.candidateId,
  }) : _rootPath = rootPath;

  static const String _markerFileName = '.ordinary_desktop_candidate.json';
  static const String _workspaceDirectoryName = 'workspace';
  static const String _logsDirectoryName = 'logs';
  static const String _preferencesFileName = 'shared_preferences.json';
  static const String _databaseFileName = 'memex_local_desktop_local.sqlite';
  static const int _layoutVersion = 1;

  static OrdinaryDesktopCandidateStorage? _active;

  final String _rootPath;
  final String candidateId;

  static bool get isActive => _active != null;

  static OrdinaryDesktopCandidateStorage get active {
    final storage = _active;
    if (storage == null) {
      throw StateError(
          'Ordinary desktop candidate storage has not been installed.');
    }
    return storage;
  }

  static String get rootPath => active._rootPath;
  static String get workspacePath => active._workspacePath;
  static String get logsPath => active._logsPath;
  static String get preferencesPath => active._preferencesPath;
  static String get databasePath => active._databasePath;

  String get _workspacePath =>
      '${_rootPath}${Platform.pathSeparator}$_workspaceDirectoryName';
  String get _logsPath =>
      '${_rootPath}${Platform.pathSeparator}$_logsDirectoryName';
  String get _preferencesPath =>
      '$_workspacePath${Platform.pathSeparator}$_preferencesFileName';
  String get _databasePath =>
      '$_workspacePath${Platform.pathSeparator}$_databaseFileName';

  /// Admits [root] and installs durable legacy preferences plus Drift's real
  /// production path. It is intentionally irreversible for this process.
  static Future<OrdinaryDesktopCandidateStorage> install(
    Directory root, {
    required String candidateId,
  }) async {
    _validateCandidateId(candidateId);
    final canonicalRoot = _validateAbsolutePath(root.path);
    final current = _active;
    if (current != null) {
      if (current._rootPath == canonicalRoot &&
          current.candidateId == candidateId) {
        return current;
      }
      throw StateError(
          'Ordinary desktop candidate storage is already installed.');
    }

    await _admitRoot(Directory(canonicalRoot), candidateId);
    final storage = OrdinaryDesktopCandidateStorage._(
      rootPath: canonicalRoot,
      candidateId: candidateId,
    );

    SharedPreferencesStorePlatform.instance =
        OrdinaryDesktopCandidatePreferencesStore(
            File(storage._preferencesPath));
    AppDatabase.configureProductionDatabasePath(storage._databasePath);
    _active = storage;
    return storage;
  }

  static Future<void> _admitRoot(Directory root, String candidateId) async {
    await _requirePhysicalAncestorChain(root);
    final entries = await root.list(followLinks: false).toList();
    if (entries.isEmpty) {
      await Directory(
              '${root.path}${Platform.pathSeparator}$_workspaceDirectoryName')
          .create();
      await Directory(
              '${root.path}${Platform.pathSeparator}$_logsDirectoryName')
          .create();
      await _writeMarker(root, candidateId);
      return;
    }

    await _validateReopenLayout(root, candidateId, entries);
  }

  static Future<void> _validateReopenLayout(
    Directory root,
    String candidateId,
    List<FileSystemEntity> entries,
  ) async {
    final expectedNames = <String>{
      _markerFileName,
      _workspaceDirectoryName,
      _logsDirectoryName,
    };
    final names = entries.map((entry) => _basename(entry.path)).toSet();
    if (names.length != expectedNames.length ||
        !names.containsAll(expectedNames)) {
      throw StateError(
          'Candidate root contains an unrecognized top-level entry.');
    }

    await _requireRegularFile(
      File('${root.path}${Platform.pathSeparator}$_markerFileName'),
      description: 'candidate marker',
    );
    await _requireDirectory(
      Directory(
          '${root.path}${Platform.pathSeparator}$_workspaceDirectoryName'),
      description: 'candidate workspace',
    );
    await _requireDirectory(
      Directory('${root.path}${Platform.pathSeparator}$_logsDirectoryName'),
      description: 'candidate logs',
    );
    await _requireNoReparseDescendants(root);

    final marker = await _readMarker(root);
    if (marker.length != 2 ||
        marker['layoutVersion'] != _layoutVersion ||
        marker['candidateId'] != candidateId) {
      throw StateError('Candidate root marker does not match this candidate.');
    }
  }

  static Future<void> _writeMarker(Directory root, String candidateId) async {
    final marker =
        File('${root.path}${Platform.pathSeparator}$_markerFileName');
    await marker.writeAsString(
      jsonEncode(<String, Object>{
        'layoutVersion': _layoutVersion,
        'candidateId': candidateId,
      }),
      flush: true,
    );
  }

  static Future<Map<String, Object?>> _readMarker(Directory root) async {
    try {
      final decoded = jsonDecode(
        await File('${root.path}${Platform.pathSeparator}$_markerFileName')
            .readAsString(),
      );
      if (decoded is! Map)
        throw const FormatException('marker is not an object');
      return decoded.map((key, value) => MapEntry('$key', value));
    } on FormatException catch (error) {
      throw StateError('Candidate root marker is invalid: $error');
    }
  }

  static Future<void> _requireDirectory(
    Directory directory, {
    required String description,
  }) async {
    final type =
        await FileSystemEntity.type(directory.path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw StateError(
          '$description must be a real directory, not a reparse point.');
    }
  }

  /// Dart reports Windows junctions and symbolic links as `link` when
  /// `followLinks` is false. Inspect every existing parent and admitted
  /// descendant before reopening, so an attacker cannot redirect a later
  /// preferences, sqlite, or logs write out of the candidate root.
  static Future<void> _requirePhysicalAncestorChain(Directory root) async {
    var current = root;
    while (true) {
      await _requireDirectory(current, description: 'candidate root ancestor');
      final parent = current.parent;
      if (parent.path == current.path) return;
      current = parent;
    }
  }

  static Future<void> _requireNoReparseDescendants(Directory root) async {
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      final type = await FileSystemEntity.type(entry.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw StateError(
            'Candidate root contains a reparse point: ${entry.path}');
      }
    }
  }

  static Future<void> _requireRegularFile(
    File file, {
    required String description,
  }) async {
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.file) {
      throw StateError(
          '$description must be a real file, not a reparse point.');
    }
  }

  static String _validateAbsolutePath(String rootPath) {
    final root = Directory(rootPath);
    if (!root.isAbsolute) {
      throw ArgumentError.value(rootPath, 'root', 'must be an absolute path');
    }
    return root.absolute.path;
  }

  static void _validateCandidateId(String candidateId) {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(candidateId)) {
      throw ArgumentError.value(
        candidateId,
        'candidateId',
        'must contain only letters, numbers, dot, underscore, or hyphen',
      );
    }
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }
}

/// File-backed implementation for the legacy SharedPreferences API.
///
/// This bypasses the Windows plugin's PathProviderWindows lookup so all legacy
/// preference writes stay inside the admitted candidate workspace.
class OrdinaryDesktopCandidatePreferencesStore
    extends SharedPreferencesStorePlatform {
  OrdinaryDesktopCandidatePreferencesStore(this.file);

  final File file;
  Future<void> _tail = Future<void>.value();

  @override
  Future<bool> clear() => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<bool> clearWithPrefix(String prefix) => clearWithParameters(
        ClearParameters(filter: PreferencesFilter(prefix: prefix)),
      );

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _locked(() async {
        final data = await _read();
        final filter = parameters.filter;
        data.removeWhere(
          (key, _) =>
              key.startsWith(filter.prefix) &&
              (filter.allowList == null || filter.allowList!.contains(key)),
        );
        await _write(data);
        return true;
      });

  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')),
      );

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) =>
      getAllWithParameters(
          GetAllParameters(filter: PreferencesFilter(prefix: prefix)));

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) =>
      _locked(() async {
        final data = await _read();
        final filter = parameters.filter;
        return Map<String, Object>.fromEntries(
          data.entries.where(
            (entry) =>
                entry.key.startsWith(filter.prefix) &&
                (filter.allowList == null ||
                    filter.allowList!.contains(entry.key)),
          ),
        );
      });

  @override
  Future<bool> remove(String key) => _locked(() async {
        final data = await _read();
        data.remove(key);
        await _write(data);
        return true;
      });

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _locked(() async {
        if (!_isSupportedValue(value)) {
          throw ArgumentError.value(
              value, 'value', 'is not a preferences value');
        }
        final data = await _read();
        data[key] = value;
        await _write(data);
        return true;
      });

  Future<T> _locked<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<Map<String, Object>> _read() async {
    if (!await file.exists()) return <String, Object>{};
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map)
      throw const FormatException('preferences are not an object');
    return decoded.map<String, Object>((key, value) {
      if (!_isSupportedValue(value)) {
        throw FormatException('unsupported preferences value for $key');
      }
      return MapEntry('$key', value as Object);
    });
  }

  Future<void> _write(Map<String, Object> values) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values), flush: true);
  }

  static bool _isSupportedValue(Object? value) =>
      value is bool ||
      value is double ||
      value is int ||
      value is String ||
      (value is List && value.every((entry) => entry is String));
}
