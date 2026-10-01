import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/product/ordinary_desktop_candidate_storage.dart';
import 'package:memex/db/app_database.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox =
        await Directory.systemTemp.createTemp('ordinary_candidate_storage_');
  });

  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('admits an empty root and persists legacy preferences only inside it',
      () async {
    final root = Directory('${sandbox.path}${Platform.pathSeparator}candidate');
    await root.create();

    final result = await Isolate.run(() => _installAndWrite(root.path, 'p6-a'));

    expect(result['rootPath'], root.absolute.path);
    expect(
        result['databasePath'],
        contains(
            '${Platform.pathSeparator}workspace${Platform.pathSeparator}'));
    expect(
        result['databasePath'], endsWith('memex_local_desktop_local.sqlite'));
    expect(result['preferenceValue'], 'isolated');
    expect(result['configuredDatabasePath'], result['databasePath']);
    expect(result['databaseExists'], 'true');

    final topLevelNames = (await root.list(followLinks: false).toList())
        .map((entry) => _basename(entry.path))
        .toSet();
    expect(topLevelNames, {
      '.ordinary_desktop_candidate.json',
      'workspace',
      'logs',
    });
    expect(
      await File(
              '${root.path}${Platform.pathSeparator}workspace${Platform.pathSeparator}shared_preferences.json')
          .readAsString(),
      contains('flutter.candidate_key'),
    );
    expect(
        await File(
                '${sandbox.path}${Platform.pathSeparator}shared_preferences.json')
            .exists(),
        isFalse);
  });

  test('reopens only the same candidate with an intact marker', () async {
    final root = Directory('${sandbox.path}${Platform.pathSeparator}candidate');
    await root.create();
    await Isolate.run(() => _installAndWrite(root.path, 'p6-a'));

    final result = await Isolate.run(() => _reopenAndRead(root.path, 'p6-a'));

    expect(result, 'isolated');
    expect(await Isolate.run(() => _attemptInstall(root.path, 'p6-other')),
        isTrue);
  });

  test('rejects a missing or tampered marker without widening the root',
      () async {
    final root = Directory('${sandbox.path}${Platform.pathSeparator}candidate');
    await root.create();
    await Isolate.run(() => _installAndWrite(root.path, 'p6-a'));
    final marker = File(
        '${root.path}${Platform.pathSeparator}.ordinary_desktop_candidate.json');

    await marker.writeAsString('not json');
    expect(await Isolate.run(() => _attemptInstall(root.path, 'p6-a')), isTrue);

    await marker.delete();
    expect(await Isolate.run(() => _attemptInstall(root.path, 'p6-a')), isTrue);
    expect(
      (await root.list(followLinks: false).toList())
          .map((entry) => _basename(entry.path))
          .toSet(),
      {'workspace', 'logs'},
    );
  });

  test('rejects a nested reparse point before reopening', () async {
    final root = Directory('${sandbox.path}${Platform.pathSeparator}candidate');
    await root.create();
    await Isolate.run(() => _installAndWrite(root.path, 'p6-a'));
    final redirect = Link(
      '${root.path}${Platform.pathSeparator}workspace${Platform.pathSeparator}redirect',
    );
    await redirect.create(sandbox.path);

    expect(await Isolate.run(() => _attemptInstall(root.path, 'p6-a')), isTrue);
  });

  test('rejects process reconfiguration after installation', () async {
    final first = Directory('${sandbox.path}${Platform.pathSeparator}first');
    final second = Directory('${sandbox.path}${Platform.pathSeparator}second');
    await first.create();
    await second.create();

    expect(
      await Isolate.run(() => _installThenReconfigure(first.path, second.path)),
      isTrue,
    );
  });
}

Future<Map<String, String>> _installAndWrite(
    String rootPath, String candidateId) async {
  await OrdinaryDesktopCandidateStorage.install(
    Directory(rootPath),
    candidateId: candidateId,
  );
  await AppDatabase.init(
    'desktop_local',
    databasePath: OrdinaryDesktopCandidateStorage.databasePath,
  );
  final databaseExists =
      await File(OrdinaryDesktopCandidateStorage.databasePath).exists();
  await AppDatabase.instance.close();
  final store = OrdinaryDesktopCandidatePreferencesStore(
    File(OrdinaryDesktopCandidateStorage.preferencesPath),
  );
  await store.setValue('String', 'flutter.candidate_key', 'isolated');
  final values = await store.getAll();
  return <String, String>{
    'rootPath': OrdinaryDesktopCandidateStorage.rootPath,
    'databasePath': OrdinaryDesktopCandidateStorage.databasePath,
    'configuredDatabasePath': AppDatabase.productionDatabasePath ?? '',
    'databaseExists': '$databaseExists',
    'preferenceValue': values['flutter.candidate_key']! as String,
  };
}

Future<String?> _reopenAndRead(String rootPath, String candidateId) async {
  await OrdinaryDesktopCandidateStorage.install(
    Directory(rootPath),
    candidateId: candidateId,
  );
  final store = OrdinaryDesktopCandidatePreferencesStore(
    File(OrdinaryDesktopCandidateStorage.preferencesPath),
  );
  return (await store.getAll())['flutter.candidate_key'] as String?;
}

Future<bool> _attemptInstall(String rootPath, String candidateId) async {
  try {
    await OrdinaryDesktopCandidateStorage.install(
      Directory(rootPath),
      candidateId: candidateId,
    );
  } on ArgumentError catch (_) {
    return true;
  } on StateError catch (_) {
    return true;
  } on FormatException catch (_) {
    return true;
  }
  return false;
}

Future<bool> _installThenReconfigure(
    String firstPath, String secondPath) async {
  await OrdinaryDesktopCandidateStorage.install(
    Directory(firstPath),
    candidateId: 'p6-a',
  );
  try {
    await OrdinaryDesktopCandidateStorage.install(
      Directory(secondPath),
      candidateId: 'p6-a',
    );
  } on StateError catch (_) {
    return true;
  }
  return false;
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  return normalized.substring(normalized.lastIndexOf('/') + 1);
}
