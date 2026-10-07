import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/memory_v3/services/task_room_service.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_config.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_store.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_recovery_identity.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_lifecycle_owner.dart';
import 'package:memex/data/workbench_ai/workbench_runtime_client.dart';
import 'package:memex/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

int _fixtureSerial = 0;

void main() {
  test('candidate goal remains the approved public long-running task', () {
    expect(p6R7CandidateGoal, '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。');
  });

  late Directory sandbox;
  late Directory root;
  late _CandidateAttestationServer host;

  setUp(() async {
    _fixtureSerial = 0;
    sandbox = await Directory.systemTemp.createTemp('p6-r7-candidate-test-');
    root = Directory(p.join(sandbox.path, 'p6-r7-app-data'))..createSync();
    host = await _CandidateAttestationServer.start();
  });

  tearDown(() async {
    await host.close();
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  Future<void> expectRestartRejected(void Function(String directory) mutate,
      {bool alterManifest = false}) async {
    final run = _runPath(
      root,
      '4${(++_fixtureSerial).toString().padLeft(7, '0')}-e89b-42d3-a456-426614174000',
    );
    final manifest = _writeAdmission(sandbox, host.uri);
    final fresh = _parse(manifest, run, root);
    await _verify(fresh);
    final store = await P6R7CandidateStore.open(fresh);
    await store.close();
    mutate(run);
    if (alterManifest) {
      final data =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      data['source_closure_sha256'] = 'e' * 64;
      manifest.writeAsStringSync(jsonEncode(data));
      host.sourceClosure = 'e' * 64;
    }
    final restart = _parse(manifest, run, root, restart: true);
    await _verify(restart);
    await expectLater(
        P6R7CandidateStore.open(restart), throwsA(isA<FormatException>()));
    host.sourceClosure = 'a' * 64;
  }

  test('admission rejects unsafe configurations before a candidate DB exists',
      () async {
    final run = _runPath(root, '123e4567-e89b-42d3-a456-426614174000');
    final manifest = _writeAdmission(sandbox, host.uri);
    final hash = _hash(manifest);

    expect(
      () => P6R7CandidateConfiguration.parse(_args(manifest, hash, run),
          enableToken: 'wrong', candidateRoot: root.path),
      throwsA(isA<FormatException>()),
    );
    _replaceAdmissionUri(manifest, 'http://8.8.8.8:44444');
    expect(
      () => _parse(manifest, run, root),
      throwsA(isA<FormatException>()),
    );
    _replaceAdmissionUri(manifest, 'http://127.0.0.1:47831');
    expect(
      () => _parse(manifest, run, root),
      throwsA(isA<FormatException>()),
    );
    _replaceAdmissionUri(manifest, host.uri.toString());
    Directory(run).createSync();
    File(p.join(run, 'unrelated.txt')).writeAsStringSync('x');
    expect(
      () => _parse(manifest, run, root),
      throwsA(isA<FormatException>()),
    );
    expect(File(p.join(run, P6R7CandidateStore.databaseName)).existsSync(),
        isFalse);
  });

  test('store requires challenged live host proof and rejects a mismatched pin',
      () async {
    final run = _runPath(root, '223e4567-e89b-42d3-a456-426614174000');
    final manifest = _writeAdmission(sandbox, host.uri);
    final config = _parse(manifest, run, root);

    await expectLater(
        P6R7CandidateStore.open(config), throwsA(isA<FormatException>()));
    expect(Directory(run).existsSync(), isFalse);

    host.sourceClosure = 'f' * 64;
    await expectLater(_verify(config), throwsA(isA<FormatException>()));
    expect(config.liveHostVerified, isFalse);
    expect(Directory(run).existsSync(), isFalse);
  });

  test(
      'fresh persists the only enqueued task and restart restores it without start',
      () async {
    final run = _runPath(root, '323e4567-e89b-42d3-a456-426614174000');
    final manifest = _writeAdmission(sandbox, host.uri);
    final config = _parse(manifest, run, root);
    await _verify(config);
    expect(AppDatabase.isInitialized, isFalse);
    final store = await P6R7CandidateStore.open(config);
    expect(store.database.schemaVersion, 62);
    expect(AppDatabase.isInitialized, isFalse);

    TaskRoomService.init(store.database);
    final runtimeDio = config.createClient();
    final tool = WorkbenchRuntimeTaskQueueTool.production(
      runtime: WorkbenchTextTaskRuntimeClient(
          bridgeUrl: host.uri.toString(), dio: runtimeDio),
      lifecycleOwner: WorkbenchTaskQueueLifecycleOwner(),
    );
    final authorization = WorkbenchTaskQueueAuthorization(
      profileId: DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
      conversationId: store.conversationId,
      allowedActions: const {WorkbenchTaskQueueAction.enqueue},
    );
    final result = await tool.invoke({
      'request_id': 'candidate-enqueue-1',
      'action': 'enqueue',
      'title': p6R7CandidateTitle,
      'goal': p6R7CandidateGoal,
    }, authorization: authorization);
    expect(result.success, isTrue);
    final taskId = (jsonDecode(result.text) as Map<String, dynamic>)['task']
        ['task_id'] as String;
    await store.persistTaskId(taskId);
    expect(
        (await TaskRoomService.instance.getTaskQueueSnapshot(taskId))!.status,
        TaskStatus.pending);
    await store.close();
    runtimeDio.close(force: true);

    final restart = _parse(manifest, run, root, restart: true);
    await _verify(restart);
    final reopened = await P6R7CandidateStore.open(restart);
    expect(reopened.taskId, taskId);
    final recovered = await TaskRoomService(db: reopened.database)
        .getTaskQueueSnapshot(taskId);
    expect(recovered!.status, TaskStatus.pending,
        reason: 'opening storage never dispatches or starts a pending task');
    await reopened.close();
    expect(AppDatabase.isInitialized, isFalse);

    final trusted = P6R7TrustedOrigin(
        identityHash: store.originIdentityHash,
        sourceClosureSha256: config.sourceClosureSha256,
        nativeSha256: p6R7NativeHash,
        canonicalDirectory: run,
        datasetId: store.datasetId);
    final marker = File(p.join(run, P6R7CandidateStore.markerName));
    final markerHash = _hash(marker);
    final dbFile = File(p.join(run, P6R7CandidateStore.databaseName));
    final beforeInspect = _hash(dbFile);
    final inspected = P6R7CandidateStore.inspectOrigin(trusted);
    expect(inspected.taskId, taskId);
    expect(_hash(dbFile), beforeInspect);
    expect(_hash(marker), markerHash);

    // Synthetic live-host admission changes without rewriting the origin.
    final nextAdmission =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    nextAdmission['admission_token'] = 'c' * 64;
    manifest.writeAsStringSync(jsonEncode(nextAdmission));
    final recoveryArgs = _args(manifest, _hash(manifest), run)..[8] = 'recover';
    expect(
        () => P6R7CandidateConfiguration.parse(recoveryArgs,
            enableToken: p6R7CandidateEnableToken, candidateRoot: root.path),
        throwsA(isA<FormatException>()));
    final changedRestart = _parse(manifest, run, root, restart: true);
    await _verify(changedRestart);
    await expectLater(P6R7CandidateStore.open(changedRestart),
        throwsA(isA<FormatException>()));
    final recovery = P6R7CandidateConfiguration.parse(recoveryArgs,
        enableToken: p6R7CandidateEnableToken,
        candidateRoot: root.path,
        recoveredOrigin: inspected);
    await _verify(recovery);
    final recoveredStore = await P6R7CandidateStore.open(recovery);
    expect(recoveredStore.taskId, taskId);
    expect(recoveredStore.originIdentityHash, store.originIdentityHash);
    expect(
        (await TaskRoomService(db: recoveredStore.database)
                .getTaskQueueSnapshot(taskId))!
            .status,
        TaskStatus.pending);
    await recoveredStore.close();
    expect(_hash(marker), markerHash);

    // Revalidate after the external read-only inspection, before opening Drift.
    final raw = sqlite.sqlite3.open(dbFile.path);
    try {
      raw.execute("UPDATE task_rooms SET permissions_json='{}'");
    } finally {
      raw.dispose();
    }
    await expectLater(
        P6R7CandidateStore.open(recovery), throwsA(isA<FormatException>()));
    expect(_hash(marker), markerHash);
  });

  test('candidate JSON rejects duplicate decoded keys and bounded overflow',
      () {
    expect(() => candidateJson(utf8.encode('{"x":1,"\\u0078":2}'), {'x'}),
        throwsA(isA<FormatException>()));
    expect(() => P6R7StrictJson.decode(utf8.encode('"${'x' * 9000}"')),
        throwsA(isA<FormatException>()));
    expect(
        P6R7StrictJson.decode(utf8.encode('"${'x' * 9000}"'),
            maximumBytes: 16384),
        'x' * 9000);
  });

  test(
      'restart rejects altered manifest, marker, DB schema, extra files, and task identity',
      () async {
    await expectRestartRejected((directory) {
      final marker = File(p.join(directory, P6R7CandidateStore.markerName));
      final data =
          jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
      data['native_sha256'] = '0' * 64;
      marker.writeAsStringSync(jsonEncode(data));
    });
    await expectRestartRejected((directory) {
      File(p.join(directory, 'not-candidate-owned')).writeAsStringSync('x');
    });
    await expectRestartRejected((directory) {
      final db = sqlite.sqlite3
          .open(p.join(directory, P6R7CandidateStore.databaseName));
      try {
        db.execute('PRAGMA user_version = 59');
      } finally {
        db.dispose();
      }
    });
    await expectRestartRejected((directory) {
      final db = sqlite.sqlite3
          .open(p.join(directory, P6R7CandidateStore.databaseName));
      try {
        db.execute(
            "UPDATE p6_r7_candidate_identity SET identity_hash = '${'0' * 64}'");
      } finally {
        db.dispose();
      }
    });
    await expectRestartRejected((directory) {
      final db = sqlite.sqlite3
          .open(p.join(directory, P6R7CandidateStore.databaseName));
      try {
        db.execute(
            'UPDATE p6_r7_candidate_identity SET task_id = "not-a-uuid"');
      } finally {
        db.dispose();
      }
    });
    await expectRestartRejected((directory) {}, alterManifest: true);
  });
}

String _runPath(Directory root, String uuid) => p.join(root.path, 'run-$uuid');

List<String> _args(File admission, String hash, String data) => [
      '--p6-r7-app-candidate',
      '--admission',
      admission.path,
      '--admission-sha256',
      hash,
      '--data-dir',
      data,
      '--mode',
      'fresh',
    ];

P6R7CandidateConfiguration _parse(File admission, String data, Directory root,
        {bool restart = false}) =>
    P6R7CandidateConfiguration.parse([
      '--p6-r7-app-candidate',
      '--admission',
      admission.path,
      '--admission-sha256',
      _hash(admission),
      '--data-dir',
      data,
      '--mode',
      restart ? 'restart' : 'fresh',
    ], enableToken: p6R7CandidateEnableToken, candidateRoot: root.path);

File _writeAdmission(Directory parent, Uri uri) {
  final file = File(p.join(parent.path, 'candidate-admission.json'));
  file.writeAsStringSync(jsonEncode({
    'schema': 'p6_r7_app_candidate_admission_v1',
    'launch_id': '523e4567-e89b-42d3-a456-426614174000',
    'base_uri': uri.toString(),
    'profile': p6R7CandidateProfile,
    'source_closure_sha256': 'a' * 64,
    'native_sha256': p6R7NativeHash,
    'admission_token': 'b' * 64,
  }));
  return file;
}

String _hash(File file) => sha256.convert(file.readAsBytesSync()).toString();

Future<void> _verify(P6R7CandidateConfiguration config) async {
  final dio = config.createClient();
  try {
    await config.verifyLiveHost(dio);
  } finally {
    dio.close(force: true);
  }
}

void _replaceAdmissionUri(File manifest, String value) {
  final data = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
  data['base_uri'] = value;
  manifest.writeAsStringSync(jsonEncode(data));
}

class _CandidateAttestationServer {
  _CandidateAttestationServer(this._server);
  final HttpServer _server;
  String sourceClosure = 'a' * 64;
  Uri get uri => Uri(scheme: 'http', host: '127.0.0.1', port: _server.port);

  static Future<_CandidateAttestationServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = _CandidateAttestationServer(server);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final challenge = (jsonDecode(body) as Map<String, dynamic>)['challenge'];
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'schema': 'p6_r7_app_candidate_attestation_v1',
        'challenge': challenge,
        'launch_id': '523e4567-e89b-42d3-a456-426614174000',
        'port': server.port,
        'profile': p6R7CandidateProfile,
        'source_closure_sha256': fake.sourceClosure,
        'native_sha256': p6R7NativeHash,
        'no_turn_preflight_verified': true,
        'ready': true,
      }));
      await request.response.close();
    });
    return fake;
  }

  Future<void> close() => _server.close(force: true);
}
