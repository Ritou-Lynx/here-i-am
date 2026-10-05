// Run explicitly with I_CORE_TEST_REPOSITORY and I_CORE_TEST_NODE configured.
// This harness is outside the default Flutter unit suite because it requires Node 24.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/domain_sync_engine.dart';
import 'package:memex/data/personal_data_hub/domain_http_transport.dart';
import 'package:memex/db/app_database.dart';
import 'package:uuid/uuid.dart';

class CoreFixture {
  CoreFixture(this.process, this.url);
  final Process process;
  final String url;
  static Future<CoreFixture> start(
      {bool dropFirst = false, bool dropMerge = false}) async {
    final repo = Platform.environment['I_CORE_TEST_REPOSITORY'];
    final node = Platform.environment['I_CORE_TEST_NODE'];
    if (repo == null || node == null) {
      throw StateError('explicit_synthetic_harness_configuration_required');
    }
    final process = await Process.start(node, [
      'tools/personal_data_hub/node_core_domain_fixture.mjs',
      repo,
      if (dropFirst) 'drop-first' else if (dropMerge) 'drop-merge'
    ]);
    process.stderr.listen((_) {});
    final line = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 20));
    final ready = jsonDecode(line) as Map;
    return CoreFixture(process, ready['url'] as String);
  }

  Future<void> close() async {
    process.stdin.writeln('close');
    await process.stdin.flush();
    await process.stdin.close();
    try {
      await process.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      process.kill();
      await process.exitCode;
    }
  }
}

const binding = DomainBinding(
    coreInstanceId: 'core-client-interop',
    principalId: 'interop-phone',
    generation: 1,
    installationId: 'interop-install');
DomainHttpTransport transport(CoreFixture f) => DomainHttpTransport(
    baseUrl: f.url,
    token: 'synthetic-interop-token-never-valid-on-live-core',
    binding: binding);
Json fields(String text) => {
      'data': {
        'title': text,
        'amount': 0.125,
        'nested': {
          'z': [null, true, '🌧️'],
          'a': {'value': 1}
        }
      },
      'provenance': {
        'source': 'fixture',
        'source_refs': [],
        'import_batch_id': null
      }
    };
void main() {
  test(
      'real Node HTTP accepts Dart millisecond intent; lost response recovers the same op and fixed paged snapshot',
      () async {
    final f = await CoreFixture.start(dropFirst: true);
    addTearDown(f.close);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime.now().toUtc().add(const Duration(microseconds: 123));
    final store = DomainStore(db, binding: binding, clock: () => now);
    await store.configureRoute('example', DomainRoute.core);
    final id = const Uuid().v4();
    final op = await store.enqueue('example',
        id: id,
        kind: 'create',
        fields: fields('合成跨语言 🌧️'),
        actor: 'agent_inferred');
    final engine = DomainSyncEngine(store, transport(f));
    await engine.syncOnce('example');
    final afterDrop = (await store.read())['outbox'] as List;
    expect(afterDrop.single['state'], 'pending');
    final immutable = jsonEncode(afterDrop.single['intent']);
    now = now.add(const Duration(seconds: 10));
    await engine.syncOnce('example');
    final after = (await store.read())['outbox'] as List;
    expect(after.single['op_id'], op);
    expect(after.single['state'], 'accepted');
    expect(after.single['result']['receipt']['accepted_op_id'], op);
    expect(jsonDecode(immutable)['op_id'], op);
    await engine.rebuild('example');
    final visible = await store.visible('example');
    expect(visible.length, 104);
    expect(visible.singleWhere((r) => r['id'] == id)['data']['title'],
        '合成跨语言 🌧️');
    expect((await store.read())['domains']['example']['cursor'], isA<String>());
  });
  for (final dropMerge in [false, true]) {
    test(
        'actual unchanged merge target keeps its revision for a queued successor (lost response: $dropMerge)',
        () async {
      final f = await CoreFixture.start(dropMerge: dropMerge);
      addTearDown(f.close);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var clock = DateTime.now().toUtc();
      final store = DomainStore(db, binding: binding, clock: () => clock);
      await store.configureRoute('example', DomainRoute.core);
      final source = const Uuid().v4(), target = const Uuid().v4();
      for (final entry in {source: '合成合并源', target: '合成未改目标'}.entries) {
        await store.enqueue('example',
            id: entry.key,
            kind: 'create',
            fields: fields(entry.value),
            actor: 'agent_inferred');
      }
      final engine = DomainSyncEngine(store, transport(f));
      await engine.syncOnce('example');
      await engine.rebuild('example');
      final merge = await store.enqueue('example',
          id: source,
          kind: 'merge',
          fields: {
            'target_id': target,
            'target_base_revision': 1,
            'target_data': fields('合成未改目标')['data'],
            'reference_updates': <Json>[]
          },
          actor: 'user_direct',
          authorizationRef: 'synthetic-owner-merge');
      final patch = await store.enqueue('example',
          id: target,
          kind: 'patch',
          fields: {
            'patch': {'title': '合成后继修订'}
          },
          actor: 'user_direct',
          authorizationRef: 'synthetic-owner-patch');
      await engine.syncOnce('example');
      if (dropMerge) {
        clock = clock.add(const Duration(seconds: 10));
        await engine.syncOnce('example');
      }
      await engine.rebuild('example');
      final outbox = (await store.read())['outbox'] as List;
      final merged = outbox.singleWhere((o) => o['op_id'] == merge);
      final successor = outbox.singleWhere((o) => o['op_id'] == patch);
      expect(merged['state'], 'accepted');
      expect(merged['result']['receipt']['targets'], [
        {'id': source, 'revision': 2}
      ]);
      expect(successor['state'], 'accepted');
      expect(successor['intent']['base_revision'], 1);
      final record = (await store.visible('example'))
          .singleWhere((r) => r['id'] == target);
      expect(record['revision'], 2);
      expect(record['data']['title'], '合成后继修订');
      expect((await store.visible('example')).any((r) => r['id'] == source),
          false);
    });
  }
  test(
      'accepted sparse merge provides a known target base to a later enqueue without target cache',
      () async {
    final f = await CoreFixture.start();
    addTearDown(f.close);
    final localDb = AppDatabase.forTesting(NativeDatabase.memory());
    final peerDb = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(localDb.close);
    addTearDown(peerDb.close);
    final local = DomainStore(localDb, binding: binding);
    final peer = DomainStore(peerDb, binding: binding);
    await local.configureRoute('example', DomainRoute.core);
    await peer.configureRoute('example', DomainRoute.core);
    final http = transport(f);
    Future<void> sendWithoutFeed(DomainStore store) async {
      final operation = await store.prepare('example');
      expect(operation, isNotNull);
      final result =
          await http.submit('example', jsonObject(operation!['intent']));
      expect(result['outcome'], 'accepted');
      await store.complete(operation['op_id'] as String, result);
    }

    final source = const Uuid().v4(), target = const Uuid().v4();
    await peer.enqueue('example',
        id: target,
        kind: 'create',
        fields: fields('远端目标 1'),
        actor: 'agent_inferred');
    await sendWithoutFeed(peer);
    for (var revision = 2; revision <= 7; revision++) {
      await peer.enqueue('example',
          id: target,
          kind: 'patch',
          fields: {
            'patch': {'title': '远端目标 $revision'}
          },
          actor: 'user_direct',
          authorizationRef: 'synthetic-peer-patch');
      await sendWithoutFeed(peer);
    }
    await local.enqueue('example',
        id: source,
        kind: 'create',
        fields: fields('本地合并源'),
        actor: 'agent_inferred');
    await sendWithoutFeed(local);
    expect(
        (await local.read())['domains']['example']['records'][target], isNull);
    final merge = await local.enqueue('example',
        id: source,
        kind: 'merge',
        fields: {
          'target_id': target,
          'target_base_revision': 7,
          'target_data': fields('远端目标 7')['data'],
          'reference_updates': <Json>[]
        },
        actor: 'user_direct',
        authorizationRef: 'synthetic-explicit-merge');
    await sendWithoutFeed(local);
    final merged = ((await local.read())['outbox'] as List)
        .singleWhere((o) => o['op_id'] == merge);
    expect(merged['result']['receipt']['targets'], [
      {'id': source, 'revision': 2}
    ]);
    expect(
        (await local.read())['domains']['example']['records'][target], isNull);
    final successor = await local.enqueue('example',
        id: target,
        kind: 'patch',
        fields: {
          'patch': {'title': '后入队目标 8'}
        },
        actor: 'user_direct',
        authorizationRef: 'synthetic-later-patch');
    await sendWithoutFeed(local);
    final patched = ((await local.read())['outbox'] as List)
        .singleWhere((o) => o['op_id'] == successor);
    expect(patched['intent']['base_revision'], 7);
    expect(patched['state'], 'accepted');
    await DomainSyncEngine(local, http).rebuild('example');
    final record =
        (await local.visible('example')).singleWhere((r) => r['id'] == target);
    expect(record['revision'], 8);
    expect(record['data']['title'], '后入队目标 8');
  });
  test(
      'actual permanent tombstone replaces Dart canonical state and clears readable body',
      () async {
    final f = await CoreFixture.start();
    addTearDown(f.close);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final store = DomainStore(db, binding: binding);
    await store.configureRoute('example', DomainRoute.core);
    final id = const Uuid().v4();
    await store.enqueue('example',
        id: id,
        kind: 'create',
        fields: fields('合成删除原话'),
        actor: 'agent_inferred');
    final engine = DomainSyncEngine(store, transport(f));
    await engine.syncOnce('example');
    await engine.rebuild('example');
    await store.enqueue('example',
        id: id,
        kind: 'delete',
        fields: {'permanent': true},
        actor: 'user_direct',
        authorizationRef: 'synthetic-owner-gesture');
    await engine.syncOnce('example');
    final rows = (await store.read())['outbox'] as List;
    expect(rows.last['state'], 'accepted');
    await engine.rebuild('example');
    final state = await store.read();
    final tomb = state['domains']['example']['records'][id] as Map;
    expect(tomb['body_state'], 'purged');
    expect(tomb.containsKey('data'), false);
    expect((await store.visible('example')).any((r) => r['id'] == id), false);
  });
}
