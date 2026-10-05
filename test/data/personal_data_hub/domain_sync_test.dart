import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/domain_sync_engine.dart';
import 'package:memex/data/personal_data_hub/domain_http_transport.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/db/app_database.dart';
import 'crash_worker.dart' show CrashDatabase, fixtureBinding;

/// Keep the first failure visible even when releasing a fixture also fails.
Future<T> withCrashCleanup<T>(
    Future<T> Function() action, Future<void> Function() cleanup) async {
  Object? primary;
  StackTrace? primaryStack;
  try {
    return await action();
  } catch (error, stack) {
    primary = error;
    primaryStack = stack;
    rethrow;
  } finally {
    try {
      await cleanup();
    } catch (error, stack) {
      if (primary != null) {
        Error.throwWithStackTrace(
            StateError(
                '$primary\nAdditional fixture cleanup failure: $error\n$stack'),
            primaryStack!);
      }
      rethrow;
    }
  }
}

/// Identity comes from the launched writer's stdout, independently of ready.
Future<void> runCrashProcess(File file, String point, String mode,
    {Duration readyTimeout = const Duration(seconds: 30),
    void Function(int writerPid, String osReceipt)? onTerminated}) async {
  final process = await Process.start(resolveCrashDart(), [
    '--disable-dart-dev',
    'test/data/personal_data_hub/crash_worker.dart',
    file.path,
    point,
    mode
  ]);
  final output = StringBuffer();
  final writer = Completer<int>();
  int? writerPid;
  var exited = false;
  final exit = process.exitCode.then((code) {
    exited = true;
    return code;
  });
  final stdoutDone = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .forEach((line) {
    output.writeln(line);
    if (line.startsWith('crash-writer:') && !writer.isCompleted) {
      writerPid = int.parse(line.substring('crash-writer:'.length));
      writer.complete(writerPid);
    }
  });
  final stderrDone =
      process.stderr.transform(utf8.decoder).forEach(output.write);
  await withCrashCleanup(() async {
    final actualWriter =
        await writer.future.timeout(const Duration(seconds: 30));
    expect(actualWriter, greaterThan(0));
    final ready = File('${file.path}.ready');
    final elapsed = Stopwatch()..start();
    while (!ready.existsSync() && !exited && elapsed.elapsed < readyTimeout) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    if (!ready.existsSync()) {
      fail('Crash fixture did not reach $point: $output');
    }
    final evidence = ready.readAsStringSync().split(':');
    expect(evidence, hasLength(2), reason: 'Complete atomic ready receipt');
    expect(evidence.first, point);
    expect(int.parse(evidence.last), actualWriter,
        reason: 'Ready identity must match this launched writer');
  }, () async {
    String osReceipt = '';
    int? killCode;
    // Wait and drain even if OS invocation or receipt assertions fail.
    await withCrashCleanup(() async {
      if (Platform.isWindows) {
        final result = await Process.run(
            'taskkill', ['/PID', '${process.pid}', '/T', '/F']);
        killCode = result.exitCode;
        osReceipt = '${result.stdout} ${result.stderr}';
        // A launcher can exit before its VM. Only target this launched writer.
        if (writerPid != null && !osReceipt.contains('$writerPid')) {
          final child =
              await Process.run('taskkill', ['/PID', '$writerPid', '/T', '/F']);
          osReceipt += '\n${child.stdout} ${child.stderr}';
          if (child.exitCode == 0) killCode = 0;
        }
      } else {
        expect(writerPid, process.pid);
        expect(process.kill(ProcessSignal.sigkill), true);
      }
    }, () async {
      await Future.wait([exit.then<void>((_) {}), stdoutDone, stderrDone])
          .timeout(const Duration(seconds: 10));
    });
    if (Platform.isWindows) {
      // Launcher exit alone is not proof of actual VM termination.
      if (writerPid != null) {
        final wait = await Process.run('powershell.exe', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '\$p=Get-Process -Id $writerPid -ErrorAction SilentlyContinue; '
              'if (\$null -ne \$p -and !\$p.WaitForExit(10000)) { exit 1 }; exit 0'
        ]);
        expect(wait.exitCode, 0, reason: 'Actual SQLite writer must exit');
      }
      expect(killCode, 0, reason: osReceipt);
      expect(writerPid, isNotNull, reason: 'Actual writer identity required');
      expect(osReceipt, contains('$writerPid'),
          reason: 'OS receipt must include the actual SQLite writer');
    }
    printOnFailure('Crash fixture $point: launcher=${process.pid}; '
        'writer=$writerPid; exit=${await exit}; output=closed; OS=$osReceipt');
    onTerminated?.call(writerPid!, osReceipt);
  });
}

Future<void> deleteCrashFixture(Directory directory) async {
  final root =
      Directory.systemTemp.absolute.path.toLowerCase() + Platform.pathSeparator;
  if (!directory.absolute.path.toLowerCase().startsWith(root)) {
    throw StateError('Unsafe synthetic cleanup path');
  }
  for (var attempt = 0;; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on PathAccessException catch (error) {
      if (!Platform.isWindows ||
          error.osError?.errorCode != 32 ||
          attempt >= 29) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

String resolveCrashDart({
  Map<String, String>? environment,
  String? resolvedExecutable,
  bool? windows,
  bool Function(String)? fileExists,
}) {
  final env = environment ?? Platform.environment;
  final win = windows ?? Platform.isWindows;
  final paths =
      path.Context(style: win ? path.Style.windows : path.Style.posix);
  final exists = fileExists ?? (candidate) => File(candidate).existsSync();
  final override = env['W7_DART_EXECUTABLE'];
  if (override != null && override.isNotEmpty) {
    if (exists(override)) return override;
    throw StateError('W7_DART_EXECUTABLE does not name an existing executable');
  }
  final binary = win ? 'dart.exe' : 'dart';
  final candidates = <String>[];
  final flutterRoot = env['FLUTTER_ROOT'];
  if (flutterRoot != null && flutterRoot.isNotEmpty) {
    candidates.add(
        paths.join(flutterRoot, 'bin', 'cache', 'dart-sdk', 'bin', binary));
  }
  var ancestor =
      paths.dirname(resolvedExecutable ?? Platform.resolvedExecutable);
  while (true) {
    candidates
        .add(paths.join(ancestor, 'bin', 'cache', 'dart-sdk', 'bin', binary));
    candidates.add(paths.join(ancestor, 'dart-sdk', 'bin', binary));
    candidates.add(paths.join(ancestor, 'bin', binary));
    final parent = paths.dirname(ancestor);
    if (parent == ancestor) break;
    ancestor = parent;
  }
  for (final candidate in candidates) {
    if (exists(candidate)) return candidate;
  }
  throw StateError(
      'Cannot locate SDK dart for OS crash verification; set W7_DART_EXECUTABLE or FLUTTER_ROOT');
}

Json fields(String title) => {
      'data': {'title': title},
      'provenance': {
        'source': 'fixture',
        'source_refs': [],
        'import_batch_id': null
      }
    };
Json record(String id, int rev, {bool deleted = false}) => {
      'domain': 'example',
      'id': id,
      'revision': rev,
      'core_instance_id': 'core-test',
      'policy_version': DomainPolicy.version,
      if (!deleted) 'data': {'title': id},
      if (deleted) 'deleted_at': '2026-10-05T00:00:00.000Z',
      if (deleted) 'body_state': 'purged',
    };
Json accepted(String op, {String id = 'a', int revision = 1}) => {
      'domain': 'example',
      'op_id': op,
      'outcome': 'accepted',
      'receipt': {
        'receipt_id': 'receipt-$op',
        'accepted_op_id': op,
        'principal_id': 'phone-test',
        'accepted_at': '2026-10-05T00:00:00.000Z',
        'policy_version': DomainPolicy.version,
        'core_instance_id': 'core-test',
        'domain': 'example',
        'authority_mode': 'single_host',
        'epoch': null,
        'targets': [
          {'id': id, 'revision': revision}
        ],
        'change_sequences': [revision],
        'receipt_auth': '0' * 64
      },
      'record': record(id, revision),
    };

class Remote implements DomainTransport {
  final results = <String, Json>{};
  final submitted = <Json>[];
  final lookedUp = <String>[];
  final acks = <String>[];
  List<Json> snapshots = [];
  bool loseResponse = false;
  Json Function(Json request)? makeResult;
  DomainFailure? submitError;
  DomainFailure? ackError;
  DomainFailure? changesError, snapshotError;
  String? operationTargetState;
  Json page = {
    'records': <dynamic>[],
    'next_cursor': 'feed-cursor',
    'policy_version': DomainPolicy.version,
    'has_more': false
  };
  @override
  Future<Json> submit(String d, Json request) async {
    if (submitError != null) throw submitError!;
    submitted.add(copyJson(request));
    final result = makeResult?.call(request) ??
        accepted(request['op_id'],
            id: request['id'], revision: (request['base_revision'] as int) + 1);
    results[request['op_id']] = result;
    if (loseResponse) {
      loseResponse = false;
      throw const DomainFailure('transport_error', retryable: true);
    }
    return result;
  }

  @override
  Future<Json> operation(String d, String op) async {
    lookedUp.add(op);
    if (!results.containsKey(op)) throw const DomainFailure('op_not_found');
    return {
      'found': true,
      'result': results[op],
      if (operationTargetState != null) 'target_state': operationTargetState
    };
  }

  @override
  Future<Json> changes(String d, String? cursor) async {
    if (changesError != null) throw changesError!;
    return page;
  }

  @override
  Future<Json> snapshot(String d,
      {String? snapshotToken, String? pageToken}) async {
    if (snapshotError != null) throw snapshotError!;
    return snapshots.removeAt(0);
  }

  @override
  Future<void> acknowledge(String d, String c, {String? snapshotId}) async {
    final error = ackError;
    ackError = null;
    if (error != null) throw error;
    acks.add(c);
  }
}

List<Json> snapshotPages(List<Json> records, {int pageSize = 1}) {
  final count = (records.length / pageSize).ceil().clamp(1, 999);
  return List.generate(count, (i) {
    final more = i < count - 1;
    final part = records.skip(i * pageSize).take(pageSize).toList();
    final manifest = {
      ...fixtureBinding.forDomain('example'),
      'snapshot_id': 'snapshot-a',
      'schema_version': 1,
      'policy_version': DomainPolicy.version,
      'created_at': '2026-10-05T00:00:00.000Z',
      'expires_at': '2026-10-05T00:15:00.000Z',
      'collection_digest': domainDigest(records),
      'cut_sequence': 4,
      'base_watermark': 0,
      'base_cursor': more ? null : 'snapshot-cursor',
      'manifest_auth': 'opaque-auth-$i'
    };
    return {
      'snapshot_id': 'snapshot-a',
      'snapshot_token': 'opaque-snapshot',
      'records': part,
      'page_digest': domainDigest(part),
      'has_more': more,
      'next_page_token': more ? 'page-${i + 1}' : null,
      'manifest': manifest
    };
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // This suite exercises a real loopback server.
  late AppDatabase db;
  late DomainStore store;
  late DateTime now;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 5);
    store = DomainStore(db, binding: fixtureBinding, clock: () => now);
  });
  tearDown(() async {
    await db.close();
  });

  test(
      'default phone is inert; phone write and local view share AppDatabase transaction',
      () async {
    final remote = Remote();
    await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('phone'), phoneWrite: () async {
      await db.customStatement(
          "INSERT INTO kv_store(key,value) VALUES('legacy','kept')");
    });
    await DomainSyncEngine(store, remote).syncOnce('example');
    expect(remote.submitted, isEmpty);
    expect((await store.read())['outbox'], isEmpty);
    expect((await store.visible('example')).single['data']['title'], 'phone');
    final failing = DomainStore(db, binding: fixtureBinding, testFault: (p) {
      if (p == 'enqueue_before_commit') {
        throw StateError('synthetic interruption');
      }
    });
    await expectLater(
        failing.enqueue('example',
            id: 'b',
            kind: 'create',
            actor: 'agent_inferred',
            fields: fields('rollback'), phoneWrite: () async {
          await db.customStatement(
              "UPDATE kv_store SET value='changed' WHERE key='legacy'");
        }),
        throwsStateError);
    expect(
        (await db
                .customSelect("SELECT value FROM kv_store WHERE key='legacy'")
                .getSingle())
            .read<String>('value'),
        'kept');
    expect((await store.visible('example')).map((r) => r['id']), ['a']);
  });

  test(
      'offline optimistic write survives reopen; reply loss queries original op before resubmit',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('offline'));
    expect((await store.visible('example')).single['sync_label'], '未同步');
    final remote = Remote()..loseResponse = true;
    await DomainSyncEngine(store, remote).syncOnce('example');
    expect((await store.read())['outbox'][0]['state'], 'pending');
    now = now.add(const Duration(minutes: 6));
    store = DomainStore(db, binding: fixtureBinding, clock: () => now);
    await DomainSyncEngine(store, remote).syncOnce('example');
    expect(remote.lookedUp, [op]);
    expect(remote.submitted, hasLength(1));
    expect((await store.read())['outbox'][0]['state'], 'accepted');
    final saved = await store.read();
    await store.complete(op, accepted(op));
    expect(await store.read(), saved);
  });

  test(
      'dependent edit seals predecessor receipt revision; uncertain delete blocks following edit',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'a', kind: 'create', actor: 'agent_inferred', fields: fields('a'));
    await store.enqueue('example',
        id: 'a',
        kind: 'patch',
        actor: 'agent_inferred',
        fields: {
          'patch': {'title': 'b'}
        });
    final remote = Remote();
    await DomainSyncEngine(store, remote).syncOnce('example');
    expect(remote.submitted.map((r) => r['base_revision']), [0, 1]);
    final deletion = await store.enqueue('example',
        id: 'a',
        kind: 'delete',
        actor: 'user_direct',
        authorizationRef: 'trusted-local-action',
        fields: {'permanent': false});
    await store.prepare('example');
    await store.enqueue('example',
        id: 'a',
        kind: 'patch',
        actor: 'agent_inferred',
        fields: {
          'patch': {'title': 'after'}
        });
    final next = await store.prepare('example');
    expect(next!['op_id'], deletion);
    expect(next['query_first'], true);
  });

  test(
      'strict header/actor guard and capacity rejection retain existing pending',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await expectLater(
        store.enqueue('example',
            id: 'a', kind: 'create', actor: 'user_direct', fields: fields('x')),
        throwsA(isA<DomainFailure>()));
    await expectLater(
        store.enqueue('example',
            id: 'a',
            kind: 'create',
            actor: 'agent_inferred',
            fields: {...fields('x'), 'op_id': 'overwrite'}),
        throwsA(isA<DomainFailure>()));
    final bounded =
        DomainStore(db, binding: fixtureBinding, maxItems: 1, clock: () => now);
    await bounded.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('first'));
    final before = await store.read();
    await expectLater(
        bounded.enqueue('example',
            id: 'b',
            kind: 'create',
            actor: 'agent_inferred',
            fields: fields('second')),
        throwsA(isA<DomainFailure>()));
    expect(await store.read(), before);
    now = now.add(const Duration(days: 7));
    expect(await store.reminders(), hasLength(1));
  });

  test(
      'frozen/capacity retain pending, auth rejection exposes needs_resolution, no token escalation',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'a', kind: 'create', actor: 'agent_inferred', fields: fields('a'));
    final remote = Remote()..submitError = const DomainFailure('domain_frozen');
    await DomainSyncEngine(store, remote).syncOnce('example');
    expect((await store.read())['outbox'][0]['state'], 'pending');
    now = now.add(const Duration(minutes: 6));
    remote.submitError = const DomainFailure('scope_forbidden');
    await DomainSyncEngine(store, remote).syncOnce('example');
    expect((await store.problems()).single['reason'], 'scope_forbidden');
  });

  test('shadow staging never creates accepted or production visible state',
      () async {
    await store.configureRoute('example', DomainRoute.shadow);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('shadow'));
    await store.complete(
        op, {'transport_state': 'shadow_staged', 'shadow_result_id': 's1'});
    expect((await store.read())['outbox'][0]['state'], 'pending');
    expect((await store.read())['domains']['example']['records'], isEmpty);
    expect((await store.visible('example')).single['data']['title'], 'shadow');
    await expectLater(store.configureRoute('example', DomainRoute.core),
        throwsA(isA<DomainFailure>()));
  });

  test(
      'feed revisions resist stale resurrection and receipt sequences never advance cursor',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a', kind: 'create', actor: 'agent_inferred', fields: fields('a'));
    await store.complete(op, accepted(op));
    expect((await store.read())['domains']['example']['cursor'], isNull);
    await store.enqueue('example',
        id: 'a',
        kind: 'patch',
        actor: 'agent_inferred',
        fields: {
          'patch': {'title': 'pending'}
        });
    await store.applyPage('example', {
      'records': [record('a', 3, deleted: true), record('a', 2)],
      'next_cursor': 'c3',
      'policy_version': DomainPolicy.version
    });
    expect(await store.visible('example'), isEmpty);
    expect((await store.problems()).single['reason'], 'deleted_target');
    expect((await store.read())['outbox'][0]['result'].containsKey('record'),
        false);
  });

  test(
      'complete multi-page snapshot atomically replaces canonical and preserves overlay/outbox',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'pending',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('unsynced'));
    final remote = Remote()
      ..snapshots = snapshotPages([record('a', 1), record('b', 2)]);
    await DomainSyncEngine(store, remote).rebuild('example');
    expect((await store.visible('example')).map((r) => r['id']),
        containsAll(['a', 'b', 'pending']));
    expect((await store.read())['outbox'], hasLength(1));
    expect(remote.acks, ['snapshot-cursor']);
  });

  for (final failure in [
    'page_digest',
    'collection_digest',
    'missing_page',
    'expired',
    'binding',
    'transaction'
  ]) {
    test('A18 snapshot $failure leaves complete old state and sends no ack',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      await store.applyPage('example', {
        'records': [record('old', 1)],
        'next_cursor': 'old-cursor',
        'policy_version': DomainPolicy.version
      });
      await store.enqueue('example',
          id: 'pending',
          kind: 'create',
          actor: 'agent_inferred',
          fields: fields('retained'));
      final old = await store.read();
      final remote = Remote()
        ..snapshots = snapshotPages([record('new', 2), record('other', 1)]);
      switch (failure) {
        case 'page_digest':
          remote.snapshots[1]['page_digest'] = 'corrupt';
        case 'collection_digest':
          for (final p in remote.snapshots) {
            p['manifest']['collection_digest'] = 'corrupt';
          }
        case 'missing_page':
          remote.snapshots[0]['next_page_token'] = null;
        case 'expired':
          now = now.add(const Duration(minutes: 15));
        case 'binding':
          remote.snapshots[0]['manifest']['credential_generation'] = 2;
        case 'transaction':
          store = DomainStore(db,
              binding: fixtureBinding,
              clock: () => now,
              testFault: (p) {
                if (p == 'snapshot_before_commit') throw StateError('crash');
              });
      }
      await expectLater(DomainSyncEngine(store, remote).rebuild('example'),
          throwsA(anything));
      expect(await store.read(), old);
      expect(remote.acks, isEmpty);
    });
  }

  test(
      'credential generation change blocks old view and quarantines pending without retarget',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('secret'));
    final changed = DomainStore(db,
        binding: const DomainBinding(
            coreInstanceId: 'core-test',
            principalId: 'phone-test',
            generation: 2,
            installationId: 'installation-test'));
    await expectLater(
        changed.visible('example'), throwsA(isA<DomainFailure>()));
    await changed.resetCredentialView('example');
    expect(await changed.visible('example'), isEmpty);
    expect((await changed.problems()).single['reason'], 'binding_changed');
  });

  test(
      'actual recall adapter labels only explicitly attached allowed pending records',
      () async {
    final hub = PersonalDataHub.forDatabase(db);
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('synthetic dinner'));
    expect(await hub.recallPending('dinner'), '');
    hub.attach('example', store, Remote(), allowLocalRecall: true);
    expect(await hub.recallPending('dinner'), contains('未同步的记录'));
    hub.attach('example', store, Remote(), allowLocalRecall: false);
    expect(await hub.recallPending('dinner'), '');
  });

  test(
      'HTTP adapter binds independent bearer and protocol; does not leak token through error',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final observed = <String>[];
    server.listen((request) async {
      observed.add(request.headers.value(HttpHeaders.authorizationHeader)!);
      expect(request.headers.value('X-I-Core-Domain-Protocol'), '1');
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = 403;
      request.response.write(jsonEncode({
        'error': {'code': 'scope_forbidden', 'retryable': false}
      }));
      await request.response.close();
    });
    try {
      final a = DomainHttpTransport(
          baseUrl: 'http://127.0.0.1:${server.port}',
          token: 'captures-only',
          binding: fixtureBinding);
      final b = DomainHttpTransport(
          baseUrl: 'http://127.0.0.1:${server.port}',
          token: 'planning-only',
          binding: fixtureBinding);
      await expectLater(
          a.changes('captures', null), throwsA(isA<DomainFailure>()));
      await expectLater(
          b.changes('plan_items', null), throwsA(isA<DomainFailure>()));
      expect(observed, ['Bearer captures-only', 'Bearer planning-only']);
      a.dio.close();
      b.dio.close();
    } finally {
      await server.close(force: true);
    }
  });

  test('concurrent old feed/snapshot response cannot regress local cursor',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.applyPage('example', {
      'records': [record('newer', 3)],
      'next_cursor': 'newer-cursor',
      'policy_version': DomainPolicy.version
    });
    final before = await store.read();
    await expectLater(
        store.applyPage(
            'example',
            {
              'records': [record('old', 1)],
              'next_cursor': 'older',
              'policy_version': DomainPolicy.version
            },
            expectedCursor: 'old-cursor',
            compareCursor: true),
        throwsA(isA<DomainFailure>()));
    await expectLater(
        store.replaceSnapshot('example', [record('old', 1)],
            {'base_cursor': 'older', 'snapshot_id': 'old'},
            expectedCursor: 'old-cursor', compareCursor: true),
        throwsA(isA<DomainFailure>()));
    expect(await store.read(), before);
  });

  test(
      'server-invalidated final snapshot ack clears stale canonical but keeps pending',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'pending',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('draft'));
    final remote = Remote()
      ..snapshots = snapshotPages([record('a', 1)])
      ..ackError = const DomainFailure('resync_required');
    await expectLater(DomainSyncEngine(store, remote).rebuild('example'),
        throwsA(isA<DomainFailure>()));
    final state = await store.read();
    expect(state['domains']['example']['records'], isEmpty);
    expect(state['domains']['example']['cursor'], null);
    expect(state['outbox'], hasLength(1));
  });

  test(
      'merge blocks target edits until complete multi-target receipt then uses target revision',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final merge = await store.enqueue('example',
        id: 'source',
        kind: 'merge',
        baseRevision: 1,
        actor: 'user_direct',
        authorizationRef: 'trusted-action',
        fields: {
          'target_id': 'target',
          'target_base_revision': 2,
          'target_data': {'title': 'merged'},
          'reference_updates': []
        });
    final edit = await store.enqueue('example',
        id: 'target',
        kind: 'patch',
        actor: 'agent_inferred',
        fields: {
          'patch': {'other': 'value'}
        });
    expect((await store.prepare('example'))!['op_id'], merge);
    final result = accepted(merge, id: 'source', revision: 2);
    result['receipt']['targets'].add({'id': 'target', 'revision': 3});
    result['receipt']['change_sequences'].add(3);
    await store.complete(merge, result);
    final next = await store.prepare('example');
    expect(next!['op_id'], edit);
    expect(next['intent']['base_revision'], 3);
  });

  test(
      'terminal payload expires at original TTL plus 30 days without rekey or renewal',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('sensitive-fixture'));
    final expires = (await store.read())['outbox'][0]['intent']['expires_at'];
    await store.complete(op, {
      'domain': 'example',
      'op_id': op,
      'outcome': 'rejected',
      'reason': 'synthetic'
    });
    now = now.add(const Duration(days: 90));
    await store.runRetention();
    final item = (await store.read())['outbox'][0];
    expect(item['op_id'], op);
    expect(item['intent']['expires_at'], expires);
    expect(item['intent'].containsKey('data'), false);
    expect(item['payload_expired'], true);
  });

  test(
      'wire timestamps truncate microseconds to exact immutable UTC milliseconds',
      () async {
    now = DateTime.utc(2026, 10, 5, 0, 0, 0, 123, 456);
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('microsecond'));
    final prepared = await store.prepare('example');
    expect(prepared!['intent']['created_at'], '2026-10-05T00:00:00.123Z');
    expect(prepared['intent']['expires_at'], '2026-12-04T00:00:00.123Z');
    now = now.add(const Duration(days: 1));
    expect((await store.prepare('example'))!['intent'], prepared['intent']);
  });

  for (final mismatch in [
    'op',
    'principal',
    'policy',
    'revision',
    'target',
    'duplicate_target',
    'sequence'
  ]) {
    test('invalid receipt $mismatch cannot accept or clear the durable request',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      final op = await store.enqueue('example',
          id: 'a',
          kind: 'create',
          actor: 'agent_inferred',
          fields: fields('protected'));
      final result = accepted(op);
      switch (mismatch) {
        case 'op':
          result['receipt']['accepted_op_id'] = 'foreign-op';
        case 'principal':
          result['receipt']['principal_id'] = 'foreign-principal';
        case 'policy':
          result['receipt']['policy_version'] = 'untrusted-policy';
        case 'revision':
          result['receipt']['targets'][0]['revision'] = 9007199254740992;
        case 'target':
          result['receipt']['targets'][0]['id'] = 'foreign-id';
        case 'duplicate_target':
          result['receipt']['targets'].add({'id': 'a', 'revision': 2});
          result['receipt']['change_sequences'].add(2);
        case 'sequence':
          result['receipt']['change_sequences'][0] = 0;
      }
      final before = await store.read();
      await expectLater(
          store.complete(op, result), throwsA(isA<DomainFailure>()));
      expect(await store.read(), before);
    });
  }

  test(
      'semantic duplicate may use another authorized acceptance receipt without claiming a new acceptance',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'new-id',
        kind: 'create',
        actor: 'agent_inferred',
        fields: fields('same'));
    final result = accepted('old-op', id: 'existing-id');
    result['op_id'] = op;
    result['outcome'] = 'duplicate';
    result['reason'] = 'semantic_duplicate';
    result['duplicate_of'] = 'existing-id';
    result['receipt']['principal_id'] = 'other-authorized-principal';
    await store.complete(op, result);
    final saved = (await store.read())['outbox'][0];
    expect(saved['state'], 'duplicate');
    expect(saved['result']['receipt']['accepted_op_id'], 'old-op');
  });

  test(
      'accepted deletion removes stale phone/shadow body, corrections, prior result and pending payload',
      () async {
    await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'user_direct',
        authorizationRef: 'ui-action',
        fields: {
          ...fields('private-marker'),
          'provenance': {
            'source': 'fixture',
            'source_refs': ['private-source-ref'],
            'import_batch_id': null
          }
        });
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: {
          ...fields('private-marker'),
          'provenance': {
            'source': 'fixture',
            'source_refs': ['private-source-ref'],
            'import_batch_id': null
          }
        });
    final initial = accepted(op);
    initial['record']['data']['title'] = 'private-marker';
    initial['record']['provenance'] = {
      'source_refs': ['private-source-ref']
    };
    await store.complete(op, initial);
    await store.enqueue('example',
        id: 'a',
        kind: 'patch',
        actor: 'user_direct',
        authorizationRef: 'ui-edit',
        fields: {
          'patch': {'title': 'private-marker'}
        });
    await store.applyPage('example', {
      'records': [record('a', 4, deleted: true)],
      'next_cursor': 'deleted',
      'policy_version': DomainPolicy.version
    });
    expect(jsonEncode(await store.read()).contains('private-marker'), false);
    expect(
        jsonEncode(await store.read()).contains('private-source-ref'), false);
    expect((await store.problems()).single['reason'], 'deleted_target');
  });

  test(
      'unchanged merge target is omitted from receipt and successor keeps checked base',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'source',
        kind: 'merge',
        baseRevision: 1,
        actor: 'user_direct',
        authorizationRef: 'local-merge',
        fields: {
          'target_id': 'target',
          'target_base_revision': 7,
          'target_data': {'title': 'unchanged'},
          'reference_updates': [
            {
              'id': 'reference',
              'base_revision': 4,
              'patch': {'link': 'target'}
            }
          ]
        });
    final next = await store.enqueue('example',
        id: 'target',
        kind: 'patch',
        actor: 'agent_inferred',
        fields: {
          'patch': {'other': 'later'}
        });
    await store.prepare('example');
    final result = accepted(op, id: 'source', revision: 2)..remove('record');
    result['receipt']['targets'].add({'id': 'reference', 'revision': 5});
    result['receipt']['change_sequences'].add(3);
    await store.complete(op, result);
    final prepared = await store.prepare('example');
    expect(prepared!['op_id'], next);
    expect(prepared['intent']['base_revision'], 7);
    expect((await store.read())['outbox'][0]['state'], 'accepted');
  });

  test(
      'sparse merge receipt rejects unrelated targets and omitted required changes atomically',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'source',
        kind: 'merge',
        baseRevision: 1,
        actor: 'user_direct',
        authorizationRef: 'local-merge',
        fields: {
          'target_id': 'target',
          'target_base_revision': 7,
          'target_data': {'title': 'unchanged'},
          'reference_updates': [
            {
              'id': 'reference',
              'base_revision': 4,
              'patch': {'link': 'target'}
            }
          ]
        });
    final before = await store.read();
    for (final ids in [
      ['source', 'reference', 'foreign'],
      ['target'],
      ['source'],
      ['reference']
    ]) {
      final result = accepted(op, id: 'source', revision: 2)..remove('record');
      result['receipt']['targets'] = [
        for (final id in ids) {'id': id, 'revision': 2}
      ];
      result['receipt']['change_sequences'] =
          List.generate(ids.length, (i) => i + 1);
      await expectLater(
          store.complete(op, result), throwsA(isA<DomainFailure>()));
      expect(await store.read(), before);
    }
  });

  test('accepted request drops provenance source_refs with other request body',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: {
          ...fields('body-secret'),
          'provenance': {
            'source': 'fixture',
            'source_refs': ['accepted-ref-secret'],
            'import_batch_id': 'batch-secret'
          }
        });
    await store.complete(op, accepted(op)..remove('record'));
    final state = jsonEncode(await store.read());
    for (final marker in [
      'body-secret',
      'accepted-ref-secret',
      'batch-secret'
    ]) {
      expect(state.contains(marker), false);
    }
  });

  for (final terminal in ['rejected', 'expired', 'needs_resolution']) {
    test('$terminal TTL clears provenance and body from actual persisted state',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      final op = await store.enqueue('example',
          id: 'a',
          kind: 'create',
          actor: 'agent_inferred',
          fields: {
            ...fields('ttl-body-secret'),
            'provenance': {
              'source': 'fixture',
              'source_refs': ['ttl-ref-secret'],
              'import_batch_id': 'ttl-batch-secret'
            }
          });
      await store.complete(
          op, {'domain': 'example', 'op_id': op, 'outcome': terminal});
      now = now.add(const Duration(days: 89));
      await store.runRetention();
      expect(jsonEncode(await store.read()).contains('ttl-ref-secret'), true);
      now = now.add(const Duration(days: 1));
      await store.runRetention();
      for (final marker in [
        'ttl-body-secret',
        'ttl-ref-secret',
        'ttl-batch-secret'
      ]) {
        expect(jsonEncode(await store.read()).contains(marker), false);
      }
    });
  }

  test('pending create provenance is purged immediately by target tombstone',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: {
          ...fields('pending-body-secret'),
          'provenance': {
            'source': 'fixture',
            'source_refs': ['pending-ref-secret'],
            'import_batch_id': null
          }
        });
    await store.applyPage('example', {
      'records': [record('a', 2, deleted: true)],
      'next_cursor': 'deleted',
      'policy_version': DomainPolicy.version
    });
    final state = await store.read();
    expect(state['outbox'][0]['reason'], 'deleted_target');
    expect(jsonEncode(state).contains('pending-body-secret'), false);
    expect(jsonEncode(state).contains('pending-ref-secret'), false);
  });

  for (final ambiguous in [false, true]) {
    test(
        'lost duplicate response deleted target clears caches before unavailable snapshot (ambiguous=$ambiguous)',
        () async {
      await store.enqueue('example',
          id: 'existing-id',
          kind: 'create',
          actor: 'user_direct',
          authorizationRef: 'local-action',
          fields: fields('cached-private-marker'));
      await store.configureRoute('example', DomainRoute.core);
      final old = await store.enqueue('example',
          id: 'existing-id',
          kind: 'create',
          actor: 'agent_inferred',
          fields: fields('cached-private-marker'));
      final initial = accepted(old, id: 'existing-id');
      initial['record']['data']['title'] = 'cached-private-marker';
      await store.complete(old, initial);
      final op = await store.enqueue('example',
          id: 'new-id',
          kind: 'create',
          actor: 'user_via_agent',
          authorizationRef: 'trusted-evidence',
          fields: fields('retry-private-marker'));
      // Durable submitting state survives the original POST response loss.
      expect((await store.prepare('example'))!['op_id'], op);
      final result = accepted('original-op', id: 'existing-id')
        ..remove('record');
      result['op_id'] = op;
      result['outcome'] = 'duplicate';
      result['reason'] = 'semantic_duplicate';
      result['receipt']['principal_id'] = 'original-authorized-principal';
      if (ambiguous) {
        result['receipt']['targets']
            .add({'id': 'original-merge-source', 'revision': 2});
        result['receipt']['change_sequences'].add(2);
      }
      // The sanitized GET deliberately has no duplicate_of.
      final remote = Remote()
        ..operationTargetState = 'deleted'
        ..changesError = const DomainFailure('resync_required')
        ..snapshotError =
            const DomainFailure('transport_error', retryable: true);
      remote.results[op] = result;
      await expectLater(DomainSyncEngine(store, remote).syncOnce('example'),
          throwsA(isA<DomainFailure>()));
      expect(remote.lookedUp, [op]);
      expect(remote.submitted, isEmpty);
      expect(await store.visible('example'), isEmpty);
      final state = await store.read();
      expect(state['outbox'].last['state'], 'duplicate');
      expect(state['domains']['example']['cursor'], null);
      expect(state['domains']['example']['replica_requires_resync'], true);
      expect(jsonEncode(state).contains('cached-private-marker'), false);
      expect(jsonEncode(state).contains('retry-private-marker'), false);
      if (!ambiguous) {
        expect(
            state['domains']['example']['hidden_ids']
                .containsKey('existing-id'),
            true);
        expect(state['domains']['example']['hidden_ids'].containsKey('new-id'),
            false);
      }
    });
  }

  test(
      'accepted delete hidden marker blocks create and patch until explicit restored record',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final op = await store.enqueue('example',
        id: 'a',
        kind: 'delete',
        baseRevision: 1,
        actor: 'user_direct',
        authorizationRef: 'local-delete',
        fields: {'permanent': false});
    await store.complete(op, accepted(op, revision: 2)..remove('record'));
    for (final kind in ['create', 'patch']) {
      await expectLater(
          store.enqueue('example',
              id: 'a',
              kind: kind,
              actor: 'agent_inferred',
              fields: kind == 'create'
                  ? fields('resurrect')
                  : {
                      'patch': {'title': 'resurrect'}
                    }),
          throwsA(isA<DomainFailure>()
              .having((e) => e.code, 'code', 'deleted_target')));
    }
    expect(await store.visible('example'), isEmpty);
    final restore = await store.enqueue('example',
        id: 'a',
        kind: 'restore',
        baseRevision: 2,
        actor: 'user_direct',
        authorizationRef: 'local-restore',
        fields: {});
    expect(await store.visible('example'), isEmpty);
    expect((await store.prepare('example'))!['op_id'], restore);
    await store.complete(restore, accepted(restore, revision: 3));
    expect((await store.visible('example')).single['id'], 'a');
    expect(
        (await store.read())['domains']['example']['hidden_ids']
            .containsKey('a'),
        false);
  });

  test(
      'accepted patches retain only current canonical body, never outbox body history',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    for (var revision = 1; revision <= 3; revision++) {
      final op = await store.enqueue('example',
          id: 'a',
          kind: revision == 1 ? 'create' : 'patch',
          actor: 'agent_inferred',
          fields: revision == 1
              ? fields('body-version-$revision')
              : {
                  'patch': {'title': 'body-version-$revision'}
                });
      final result = accepted(op, revision: revision);
      result['record']['data']['title'] = 'body-version-$revision';
      result['record']['provenance'] = {
        'source_refs': ['ref-version-$revision']
      };
      await store.complete(op, result);
      final before = await store.read();
      expect(before['outbox'].every((o) => !o['result'].containsKey('record')),
          true);
      final encoded = jsonEncode(before);
      for (var old = 1; old < revision; old++) {
        expect(encoded.contains('body-version-$old'), false);
        expect(encoded.contains('ref-version-$old'), false);
      }
      expect(encoded.contains('body-version-$revision'), true);
      await store.complete(op, result);
      expect(await store.read(), before);
    }
    expect((await store.visible('example')).single['revision'], 3);
  });

  test(
      'crash Dart locator supports platform SDK ancestry, root and explicit override without skips',
      () {
    final windows = path.Context(style: path.Style.windows);
    final root = windows.join('Q:\\', 'synthetic-sdk');
    final winDart =
        windows.join(root, 'bin', 'cache', 'dart-sdk', 'bin', 'dart.exe');
    expect(
        resolveCrashDart(
            environment: {'FLUTTER_ROOT': root},
            resolvedExecutable:
                windows.join('Q:\\', 'runner', 'flutter_tester.exe'),
            windows: true,
            fileExists: (p) => p == winDart),
        winDart);
    const linuxDart = '/synthetic-sdk/bin/cache/dart-sdk/bin/dart';
    expect(
        resolveCrashDart(
            environment: {},
            windows: false,
            resolvedExecutable:
                '/synthetic-sdk/bin/cache/artifacts/engine/linux-x64/flutter_tester',
            fileExists: (p) => p == linuxDart),
        linuxDart);
    expect(
        resolveCrashDart(
            environment: {'W7_DART_EXECUTABLE': '/explicit/dart'},
            windows: false,
            fileExists: (p) => p == '/explicit/dart'),
        '/explicit/dart');
    expect(
        () => resolveCrashDart(
            environment: {'W7_DART_EXECUTABLE': '/missing/dart'},
            windows: false,
            fileExists: (_) => false),
        throwsStateError);
    expect(
        () => resolveCrashDart(
            environment: {},
            windows: false,
            resolvedExecutable: '/standalone/flutter_tester',
            fileExists: (_) => false),
        throwsStateError);
    expect(File(resolveCrashDart()).existsSync(), true);
  });

  for (final kind in ['delete', 'merge']) {
    test(
        'lost $kind response followed by feed tombstone recovers same op by lookup only',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      final initialRecords = [
        record('source', 1),
        record('target', 5),
        record('reference', 9)
      ];
      await store.applyPage('example', {
        'records': initialRecords,
        'next_cursor': 'initial',
        'policy_version': DomainPolicy.version
      });
      final op = await store.enqueue('example',
          id: 'source',
          kind: kind,
          baseRevision: 1,
          actor: 'user_direct',
          authorizationRef: 'local-authorized',
          fields: kind == 'delete'
              ? {'permanent': false}
              : {
                  'target_id': 'target',
                  'target_base_revision': 5,
                  'target_data': {'title': 'unchanged-target'},
                  'reference_updates': [
                    {
                      'id': 'reference',
                      'base_revision': 9,
                      'patch': {'link': 'target'}
                    }
                  ]
                });
      final postRecords = [
        record('source', 2, deleted: true),
        record('target', 5),
        record('reference', kind == 'merge' ? 10 : 9)
      ];
      final remote = Remote()
        ..loseResponse = true
        ..operationTargetState = 'deleted'
        ..makeResult = (request) {
          final result = accepted(request['op_id'], id: 'source', revision: 2)
            ..remove('record');
          if (kind == 'merge') {
            result['receipt']['targets']
                .add({'id': 'reference', 'revision': 10});
            result['receipt']['change_sequences'].add(3);
          }
          return result;
        }
        ..page = {
          'records': postRecords,
          'next_cursor': 'after-tombstone',
          'policy_version': DomainPolicy.version
        };
      await DomainSyncEngine(store, remote).syncOnce('example');
      var state = await store.read();
      expect(state['outbox'].single['state'], 'pending');
      expect(state['outbox'].single['lookup_only'], true);
      expect(state['outbox'].single['payload_purged'], true);
      expect(state['outbox'].single['intent'].containsKey('authorization_ref'),
          false);
      expect(
          state['outbox'].single['intent'].containsKey('target_data'), false);
      expect(remote.submitted, hasLength(1));
      now = now.add(const Duration(minutes: 6));
      // Reopen the durable store. A matching receipt, not the tombstone itself,
      // is the only evidence allowed to conclude this operation was accepted.
      store = DomainStore(db, binding: fixtureBinding, clock: () => now);
      remote.changesError = const DomainFailure('resync_required');
      remote.snapshots = snapshotPages(postRecords, pageSize: 2);
      await DomainSyncEngine(store, remote).syncOnce('example');
      state = await store.read();
      expect(remote.lookedUp, [op]);
      expect(remote.submitted, hasLength(1));
      expect(state['outbox'].single['state'], 'accepted');
      expect(state['outbox'].single.containsKey('lookup_only'), false);
      expect((state['domains']['example']['hidden_ids'] as Map).keys,
          everyElement('source'));
      final visible = await store.visible('example');
      expect(visible.map((r) => r['id']), containsAll(['target', 'reference']));
      expect(visible.map((r) => r['id']), isNot(contains('source')));
      expect(visible.singleWhere((r) => r['id'] == 'target')['revision'], 5);
      expect(visible.singleWhere((r) => r['id'] == 'reference')['revision'],
          kind == 'merge' ? 10 : 9);
    });
  }

  for (final outcome in ['not_found', 'rejected', 'needs_resolution']) {
    test(
        'another writer tombstone plus lookup $outcome cannot accept or resubmit scrubbed intent',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      final op = await store.enqueue('example',
          id: 'source',
          kind: 'merge',
          baseRevision: 1,
          actor: 'user_direct',
          authorizationRef: 'local-authorized',
          fields: {
            'target_id': 'target',
            'target_base_revision': 1,
            'target_data': {'title': 'cleared-sensitive-marker'},
            'reference_updates': []
          });
      await store.prepare('example');
      await store.applyPage('example', {
        'records': [record('source', 2, deleted: true)],
        'next_cursor': 'other-writer-delete',
        'policy_version': DomainPolicy.version
      });
      expect(
          jsonEncode(await store.read()).contains('cleared-sensitive-marker'),
          false);
      final remote = Remote()..operationTargetState = 'deleted';
      if (outcome != 'not_found') {
        remote.results[op] = {
          'domain': 'example',
          'op_id': op,
          'outcome': outcome,
          'reason': 'deleted_target'
        };
      }
      await DomainSyncEngine(store, remote).syncOnce('example');
      final row = (await store.read())['outbox'].single;
      expect(
          row['state'], outcome == 'not_found' ? 'needs_resolution' : outcome);
      expect(row['result']?['receipt'], null);
      expect(remote.submitted, isEmpty);
      expect(remote.lookedUp, [op]);
      now = now.add(const Duration(minutes: 6));
      await DomainSyncEngine(store, remote).syncOnce('example');
      expect(remote.submitted, isEmpty);
      expect(remote.lookedUp, [op]);
      expect(await store.visible('example'), isEmpty);
    });
  }

  for (final variation in [
    'explicit_patch',
    'implicit_patch',
    'explicit_delete'
  ]) {
    test(
        'historical accepted rev2 never regresses observed rev5 for $variation',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      final old = await store.enqueue('example',
          id: 'a',
          kind: 'patch',
          baseRevision: 1,
          actor: 'agent_inferred',
          fields: {
            'patch': {'title': 'old-local'}
          });
      await store.complete(old, accepted(old, revision: 2));
      await store.applyPage('example', {
        'records': [record('a', 5)],
        'next_cursor': 'other-device-five',
        'policy_version': DomainPolicy.version
      });
      final deletion = variation.endsWith('delete');
      final next = await store.enqueue('example',
          id: 'a',
          kind: deletion ? 'delete' : 'patch',
          baseRevision: variation.startsWith('explicit') ? 5 : null,
          actor: deletion ? 'user_direct' : 'agent_inferred',
          authorizationRef: deletion ? 'confirmed-action' : null,
          fields: deletion
              ? {'permanent': false}
              : {
                  'patch': {'title': 'observed-five'}
                });
      final prepared = await store.prepare('example');
      expect(prepared!['op_id'], next);
      expect(prepared['predecessors'], isEmpty);
      expect(prepared['intent']['base_revision'], 5);
    });
  }

  test(
      'unfinished predecessors cannot regress explicit source target or reference merge bases',
      () async {
    await store.configureRoute('example', DomainRoute.core);
    final prior = <String, String>{};
    for (final id in ['source', 'target', 'reference']) {
      prior[id] = await store.enqueue('example',
          id: id,
          kind: 'patch',
          baseRevision: 1,
          actor: 'agent_inferred',
          fields: {
            'patch': {'title': 'earlier'}
          });
    }
    final op = await store.enqueue('example',
        id: 'source',
        kind: 'merge',
        baseRevision: 5,
        actor: 'user_direct',
        authorizationRef: 'known-bases',
        fields: {
          'target_id': 'target',
          'target_base_revision': 6,
          'target_data': {'title': 'target'},
          'reference_updates': [
            {
              'id': 'reference',
              'base_revision': 7,
              'patch': {'link': 'target'}
            }
          ]
        });
    for (final entry in prior.entries) {
      await store.complete(
          entry.value, accepted(entry.value, id: entry.key, revision: 2));
    }
    final prepared = await store.prepare('example');
    expect(prepared!['op_id'], op);
    expect(prepared['intent']['base_revision'], 5);
    expect(prepared['intent']['target_base_revision'], 6);
    expect(prepared['intent']['reference_updates'].single['base_revision'], 7);
  });

  for (final scenario in [
    'no_cache',
    'older_cache',
    'higher_cache',
    'explicit_base',
    'idempotent_replay'
  ]) {
    test(
        'completed sparse merge supplies proven target floor to later enqueue: $scenario',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      final cached = scenario == 'higher_cache' ? 9 : 5;
      if (scenario != 'no_cache') {
        await store.applyPage('example', {
          'records': [record('target', cached)],
          'next_cursor': 'before-merge',
          'policy_version': DomainPolicy.version
        });
      }
      final merge = await store.enqueue('example',
          id: 'source',
          kind: 'merge',
          baseRevision: 1,
          actor: 'user_direct',
          authorizationRef: 'local-authorized',
          fields: {
            'target_id': 'target',
            'target_base_revision': 7,
            'target_data': {'title': 'unchanged'},
            'reference_updates': []
          });
      final result = accepted(merge, id: 'source', revision: 2)
        ..remove('record');
      if (scenario == 'idempotent_replay') {
        result['outcome'] = 'duplicate';
        result['reason'] = 'idempotent_replay';
      }
      await store.complete(merge, result);
      // This ordering is distinct from queued-before-merge predecessors.
      final next = await store.enqueue('example',
          id: 'target',
          kind: 'patch',
          actor: 'agent_inferred',
          baseRevision: scenario == 'explicit_base' ? 11 : null,
          fields: {
            'patch': {'other': 'later'}
          });
      final prepared = await store.prepare('example');
      expect(prepared!['op_id'], next);
      expect(prepared['predecessors'], isEmpty);
      expect(
          prepared['intent']['base_revision'],
          scenario == 'explicit_base'
              ? 11
              : scenario == 'higher_cache'
                  ? 9
                  : 7);
    });
  }

  for (final scenario in ['pending', 'rejected', 'unbound_receipt']) {
    test('unproven sparse merge target base is not version evidence: $scenario',
        () async {
      await store.configureRoute('example', DomainRoute.core);
      await store.applyPage('example', {
        'records': [record('target', 5)],
        'next_cursor': 'known-five',
        'policy_version': DomainPolicy.version
      });
      final merge = await store.enqueue('example',
          id: 'source',
          kind: 'merge',
          baseRevision: 1,
          actor: 'user_direct',
          authorizationRef: 'local-authorized',
          fields: {
            'target_id': 'target',
            'target_base_revision': 7,
            'target_data': {'title': 'unproven'},
            'reference_updates': []
          });
      if (scenario == 'rejected') {
        await store.complete(merge, {
          'domain': 'example',
          'op_id': merge,
          'outcome': 'rejected',
          'reason': 'stale_base'
        });
      } else if (scenario == 'unbound_receipt') {
        await store.complete(merge,
            accepted(merge, id: 'source', revision: 2)..remove('record'));
        // Malformed persisted evidence cannot promote a base even when its row
        // still has the accepted label (for example a damaged local restore).
        await store.transaction((state) async {
          state['outbox'].single['result']['receipt']['accepted_op_id'] =
              'foreign-op';
        });
      }
      final next = await store.enqueue('example',
          id: 'target',
          kind: 'patch',
          actor: 'agent_inferred',
          fields: {
            'patch': {'other': 'later'}
          });
      final row = (await store.read())['outbox'].last;
      expect(row['op_id'], next);
      expect(row['intent']['base_revision'], 5);
    });
  }

  test('crash fixture retains primary error when cleanup also fails', () async {
    await expectLater(
        withCrashCleanup(() async => throw StateError('primary-ready-failure'),
            () async => throw StateError('secondary-cleanup-failure')),
        throwsA(isA<StateError>().having(
            (e) => e.message,
            'first error followed by cleanup evidence',
            allOf(
                contains('primary-ready-failure'),
                contains('Additional fixture cleanup failure'),
                contains('secondary-cleanup-failure')))));
  });

  for (final mode in ['fixture_no_ready', 'fixture_bad_ready']) {
    test('crash fixture $mode preserves first failure and terminates writer',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('w7-crash-failure-');
      await withCrashCleanup(() async {
        final file = File('${directory.path}/failure.sqlite');
        int? stoppedWriter;
        String? receipt;
        await expectLater(
            runCrashProcess(file, 'failure-point', mode,
                readyTimeout: const Duration(milliseconds: 300),
                onTerminated: (writer, evidence) {
              stoppedWriter = writer;
              receipt = evidence;
            }),
            throwsA(isA<TestFailure>().having(
                (e) => e.message,
                'first failure',
                contains(mode == 'fixture_no_ready'
                    ? 'Crash fixture did not reach'
                    : 'Complete atomic ready receipt'))));
        expect(stoppedWriter, greaterThan(0));
        if (Platform.isWindows) expect(receipt, contains('$stoppedWriter'));
        // SQLite was opened before the failure-mode handshake.
        final reopened = CrashDatabase(file);
        await withCrashCleanup(() async {
          expect(await reopened.customSelect('SELECT 1 AS alive').getSingle(),
              isNotNull);
        }, reopened.close);
      }, () => deleteCrashFixture(directory));
      expect(directory.existsSync(), false);
    });
  }

  test('A20 OS-killed SQLite processes preserve only full before/after states',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('w7-crash-synthetic-');
    await withCrashCleanup(() async {
      for (final point in [
        'enqueue_before_commit',
        'enqueue_after_commit',
        'submit_before_commit',
        'submit_after_local_commit',
        'response_before_save',
        'receipt_before_commit',
        'receipt_after_commit',
        'snapshot_before_commit',
        'snapshot_after_commit'
      ]) {
        final file = File('${directory.path}/$point.sqlite');
        var local = CrashDatabase(file);
        var durable = DomainStore(local, binding: fixtureBinding);
        await durable.configureRoute('example', DomainRoute.core);
        if (!point.startsWith('enqueue')) {
          await durable.enqueue('example',
              id: 'record-a',
              kind: 'create',
              actor: 'agent_inferred',
              fields: fields('pending'));
        }
        if (point.startsWith('receipt') || point.startsWith('response')) {
          await durable.prepare('example');
        }
        final before = await durable.read();
        await local.close();
        final mode = point.startsWith('submit')
            ? 'submit'
            : (point.startsWith('receipt') || point.startsWith('response'))
                ? 'receipt'
                : point.startsWith('snapshot')
                    ? 'snapshot'
                    : 'enqueue';
        await runCrashProcess(file, point, mode);
        local = CrashDatabase(file);
        durable = DomainStore(local, binding: fixtureBinding);
        late Json after;
        try {
          after = await durable.read();
        } finally {
          // Release the reopened handle before assertions: a failed assertion
          // must not be hidden by Windows refusing fixture cleanup.
          await local.close();
        }
        if (point == 'enqueue_after_commit') {
          expect(after['outbox'], hasLength(1));
          expect(after['outbox'][0]['state'], 'pending');
        } else if (point == 'submit_after_local_commit') {
          expect(after['outbox'][0]['state'], 'submitting');
          expect(after['outbox'][0]['op_id'], before['outbox'][0]['op_id']);
        } else if (point == 'receipt_after_commit') {
          expect(after['outbox'][0]['state'], 'accepted');
          expect(after['outbox'][0]['op_id'], before['outbox'][0]['op_id']);
        } else if (point == 'snapshot_after_commit') {
          expect(after['domains']['example']['cursor'], 'cursor-new');
          expect(after['outbox'], before['outbox']);
        } else {
          expect(after, before, reason: point);
        }
      }
    }, () => deleteCrashFixture(directory));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
