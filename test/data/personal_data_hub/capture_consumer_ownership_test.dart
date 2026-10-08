import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'personal_data_hub_runtime_test.dart' show FakeAlarms;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/utils/result.dart';
import '../memory_v3/notes/claude_web_note_feed_test.dart'
    show item, card, page;
import 'crash_worker.dart' show fixtureBinding;

Matcher failure(String code) =>
    isA<DomainFailure>().having((e) => e.code, 'code', code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late ClaudeWebNoteFeedStorage storage;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = ClaudeWebNoteFeedStorage();
  });
  tearDown(() => db.close());
  ClaudeWebNoteImporter importer(AppDatabase database,
          {ClaudeWebNoteOrganizer? organize}) =>
      ClaudeWebNoteImporter(
          db: database,
          organizer: RecordOrganizerServiceV3(database),
          organize: organize ??
              (source) async =>
                  OrganizedRecord(cards: [card(source.rawInput)]));

  test(
      'configuration and ownership handoff wait for complete import ACK cursor',
      () async {
    final owner = CaptureConsumerOwnership(db);
    final entered = Completer<void>(), release = Completer<void>();
    final feed = ClaudeWebNoteFeedService(
        storage: storage,
        ownership: owner,
        importer: importer(db, organize: (source) async {
          entered.complete();
          await release.future;
          return OrganizedRecord(cards: [card(source.rawInput)]);
        }),
        client: MockClient((r) async => r.method == 'GET'
            ? page([item()])
            : http.Response('{"ok":true}', 200)));
    await feed.configure(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    final syncing = feed.syncOnce();
    await entered.future;
    await expectLater(CaptureConsumerOwnership(db).runLegacy((_) async {}),
        throwsA(failure('capture_consumer_busy')));
    var changed = false;
    final changing = feed
        .configure(baseUrl: 'https://synthetic.ts.net', token: 'iph_rotated')
        .then((r) {
      changed = true;
      return r;
    });
    final takeover = owner.selectCore(const CoreCaptureTakeover(
        gateRef: 'synthetic',
        coreInstanceId: 'core-test',
        bindingFingerprint: 'synthetic-binding',
        adoptionProof: 'synthetic-origin',
        noteToCapture: {}));
    final denied =
        expectLater(takeover, throwsA(failure('capture_core_gate_required')));
    await Future<void>.delayed(Duration.zero);
    expect(changed, false);
    expect((await storage.readConfig())!.cursor, 0);
    release.complete();
    expect((await syncing).valueOrThrow.cursor, 1);
    await denied;
    expect(await changing, isA<Ok<void>>());
    expect((await storage.readConfig())!.cursor, 1);
    expect((await storage.readConfig())!.token, 'iph_rotated');
    expect(await owner.coreSelected(), false);
    await feed.dispose();
  });

  test(
      'expired slow worker on independent SQLite handle cannot write or ACK after reclaim',
      () async {
    await db.close();
    final directory =
        await Directory.systemTemp.createTemp('capture-lease-synthetic-');
    final file = File('${directory.path}/fixture.sqlite');
    db = AppDatabase.forTesting(NativeDatabase(file));
    await db.customSelect('SELECT count(*) FROM kv_store').get();
    await db.customSelect('PRAGMA journal_mode=WAL').get();
    final other = AppDatabase.forTesting(NativeDatabase(file));
    await other.customSelect('SELECT count(*) FROM kv_store').get();
    var now = DateTime(2026, 10, 6);
    CaptureConsumerOwnership owner(AppDatabase database) =>
        CaptureConsumerOwnership(database,
            clock: () => now,
            leaseDuration: const Duration(seconds: 30),
            heartbeatInterval: const Duration(hours: 1));
    final entered = Completer<void>(), release = Completer<void>();
    var oldAcks = 0, newAcks = 0;
    final old = ClaudeWebNoteFeedService(
        storage: storage,
        ownership: owner(db),
        importer: importer(db, organize: (source) async {
          entered.complete();
          await release.future;
          return OrganizedRecord(cards: [card('old worker result')]);
        }),
        client: MockClient((r) async {
          if (r.method == 'GET') return page([item()]);
          oldAcks++;
          return http.Response('{"ok":true}', 200);
        }));
    final replacement = ClaudeWebNoteFeedService(
        storage: storage,
        ownership: owner(other),
        importer: importer(other),
        client: MockClient((r) async {
          if (r.method == 'GET') return page([item()]);
          newAcks++;
          return http.Response('{"ok":true}', 200);
        }));
    try {
      await old.configure(
          baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
      final first = old.syncOnce();
      await entered.future;
      now = now.add(const Duration(seconds: 31));
      expect((await replacement.syncOnce()).valueOrThrow.cursor, 1);
      release.complete();
      final result = await first;
      expect(result, isA<Error<ClaudeWebNoteSyncReport>>());
      expect((result as Error).error, failure('capture_consumer_fenced'));
      expect(oldAcks, 0);
      expect(newAcks, 1);
      expect((await db.select(db.memoryCards).getSingle()).title,
          'synthetic note');
      expect((await storage.readConfig())!.cursor, 1);
      final receipts = await (db.select(db.memoryCardOperations)
            ..where((t) => t.operationType.equals('external_note_import')))
          .get();
      expect(receipts, hasLength(1));
    } finally {
      if (!release.isCompleted) release.complete();
      await old.dispose();
      await replacement.dispose();
      await other.close();
      await db.close();
      expect(directory.absolute.path.toLowerCase(),
          startsWith(Directory.systemTemp.absolute.path.toLowerCase()));
      await directory.delete(recursive: true);
      db = AppDatabase.forTesting(NativeDatabase.memory());
    }
  });

  test(
      'heartbeat renews while model work is outside the SQLite writer transaction',
      () async {
    var now = DateTime(2026, 10, 6);
    final owner = CaptureConsumerOwnership(db,
        clock: () => now,
        leaseDuration: const Duration(seconds: 30),
        heartbeatInterval: const Duration(milliseconds: 10));
    await owner.runLegacy((lease) async {
      now = now.add(const Duration(seconds: 20));
      // Heartbeat uses a short transaction, while unrelated reads/writes remain usable.
      await db.customStatement(
          'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)',
          ['synthetic-other-domain', '{}', 'test', 0]);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      now = now.add(const Duration(seconds: 20));
      await lease.verify();
    });
  });

  test(
      'old B3 receipt identity stays protected; new legacy edits and deletes preserve user edits',
      () async {
    final organizer = RecordOrganizerServiceV3(db);
    final original = await organizer.persist(
        organized: OrganizedRecord(cards: [card('old B3')]),
        source: RecordSource(
            sourceKind: 'claude_web_note',
            rawInput: 'old B3',
            sourceRef: 'old-note'));
    final id = original.cardIds.single;
    await db
        .into(db.memoryCardOperations)
        .insert(MemoryCardOperationsCompanion.insert(
            id: 'claude-note:${base64Url.encode(utf8.encode('old-note'))}:1',
            cardId: id,
            operationType: 'external_note_import',
            sourceKind: 'claude_web_note',
            createdAt: 1,
            payload: jsonEncode({
              'note_id': 'old-note',
              'revision': 1,
              'op': 'upsert',
              'card_ids': [id]
            })));
    final imp = importer(db);
    expect(await imp.apply(ClaudeWebNoteChange.fromJson(item(id: 'old-note'))),
        id);
    expect(
        await imp.apply(ClaudeWebNoteChange.fromJson(
            item(id: 'old-note', revision: 2, seq: 2))),
        id);
    expect((await db.select(db.memoryCards).getSingle()).title, 'old B3');
    expect((await db.select(db.memoryCardSources).getSingle()).sourceRef,
        'old-note');
    expect(await imp.pendingIssues('old-note'), isNotEmpty);
    final fresh = await imp
        .apply(ClaudeWebNoteChange.fromJson(item(id: 'fresh-note', seq: 3)));
    await organizer.updateCard(fresh!,
        title: 'User title', actor: 'user_direct');
    await imp.apply(ClaudeWebNoteChange.fromJson(
        item(id: 'fresh-note', revision: 2, seq: 4)));
    await imp.apply(ClaudeWebNoteChange.fromJson(
        item(id: 'fresh-note', revision: 3, seq: 5, deleted: true)));
    expect((await imp.pendingIssues('fresh-note')).single['reason'],
        'user_modified');
    expect((await db.select(db.memoryCards).get()).map((c) => c.title),
        contains('User title'));
  });

  test('free-form takeover strings cannot select the Core owner', () async {
    await importer(db).apply(ClaudeWebNoteChange.fromJson(item()));
    const proof = CoreCaptureTakeover(
        gateRef: 'verified-synthetic-gate',
        coreInstanceId: 'core-test',
        bindingFingerprint: 'synthetic-binding',
        adoptionProof: 'verified-synthetic-origin',
        noteToCapture: {'note_one': 'note_one'});
    await expectLater(CaptureConsumerOwnership(db).selectCore(proof),
        throwsA(failure('capture_core_gate_required')));
    expect(await CaptureConsumerOwnership(db).coreSelected(), false);
    expect(await db.select(db.memoryCards).get(), hasLength(1));
  });

  test(
      'legacy mode blocks Core web upsert and tomb while phone quick captures still run',
      () async {
    final store = DomainStore(db, binding: fixtureBinding);
    await store.configureRoute('captures', DomainRoute.core);
    Future<void> feed(String id, String source, int rev,
            {bool deleted = false}) =>
        store.applyPage('captures', {
          'next_cursor': '$id-$rev',
          'policy_version': DomainPolicy.version,
          'records': [
            {
              'id': id,
              'domain': 'captures',
              'core_instance_id': 'core-test',
              'revision': rev,
              if (deleted) ...{
                'deleted_at': '2026-10-06T00:00:00Z',
                'body_state': 'purged'
              } else ...{
                'provenance': {'source': source},
                'data': {'text': id, 'source': source},
                'field_meta': {
                  'text': {'rev': rev}
                }
              }
            }
          ]
        });
    final consumer = CaptureConsumer(
        db: db,
        store: store,
        organizer: RecordOrganizerServiceV3(db),
        extract: (text) async => OrganizedRecord(cards: [card(text)]),
        decodeText: (data) => data['text'] as String,
        inputVersion: (r) => r['field_meta']?['text']?['rev'] as int?);
    await feed('web', 'claude_web', 1);
    await feed('phone', 'phone_quick', 1);
    expect(await consumer.consume(allowRemoteWeb: false), 1);
    expect((await db.select(db.memoryCards).getSingle()).title, 'phone');
    await expectLater(consumer.consume(verifyRemoteOwnership: () async {
      throw const DomainFailure('capture_consumer_fenced');
    }), throwsA(failure('capture_consumer_fenced')));
    expect((await db.select(db.memoryCards).getSingle()).title, 'phone');
    // Simulate an already generated Core output, then show that a bodyless web
    // tomb cannot be processed by the legacy-owner runtime.
    expect(await consumer.consume(), 1);
    await feed('web', 'claude_web', 2, deleted: true);
    expect(await consumer.consume(allowRemoteWeb: false), 0);
    expect(await db.select(db.memoryCards).get(), hasLength(2));
    await feed('phone', 'phone_quick', 2, deleted: true);
    expect(await consumer.consume(allowRemoteWeb: false), 1);
    expect((await db.select(db.memoryCards).getSingle()).title, 'web');
  });

  test(
      'runtime connection suspension waits admitted work and rejects new work until resume',
      () async {
    final owner = CaptureConsumerOwnership.forDatabase(db);
    final started = Completer<void>(), release = Completer<void>();
    final work = owner.runLegacy((lease) async {
      started.complete();
      await release.future;
      await lease.verify();
    });
    await started.future;
    var suspended = false;
    final stopping = owner.suspend().then((_) => suspended = true);
    await Future<void>.delayed(Duration.zero);
    expect(suspended, false);
    release.complete();
    await work;
    await stopping;
    await expectLater(owner.runLegacy((_) async {}),
        throwsA(failure('capture_owner_suspended')));
    owner.resume();
    await owner.runLegacy((lease) => lease.verify());
  });
  test(
      'already in-flight ACK remains revision-idempotent but stale lease cannot advance secure cursor',
      () async {
    var now = DateTime(2026, 10, 6);
    CaptureConsumerOwnership owner() => CaptureConsumerOwnership(db,
        clock: () => now,
        leaseDuration: const Duration(seconds: 30),
        heartbeatInterval: const Duration(hours: 1));
    final ackStarted = Completer<void>(), releaseAck = Completer<void>();
    final old = ClaudeWebNoteFeedService(
        storage: storage,
        ownership: owner(),
        importer: importer(db),
        client: MockClient((r) async {
          if (r.method == 'GET') return page([item()]);
          ackStarted.complete();
          await releaseAck.future;
          return http.Response('{"ok":true}', 200);
        }));
    var replayModels = 0;
    final next = ClaudeWebNoteFeedService(
        storage: storage,
        ownership: owner(),
        importer: importer(db, organize: (source) async {
          replayModels++;
          return OrganizedRecord(cards: [card(source.rawInput)]);
        }),
        client: MockClient((r) async => r.method == 'GET'
            ? page([item()])
            : http.Response('{"ok":true}', 200)));
    await old.configure(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    final running = old.syncOnce();
    await ackStarted.future;
    now = now.add(const Duration(seconds: 31));
    expect((await next.syncOnce()).valueOrThrow.cursor, 1);
    expect(replayModels, 0);
    releaseAck.complete();
    final result = await running;
    expect((result as Error).error, failure('capture_consumer_fenced'));
    expect((await storage.readConfig())!.cursor, 1);
    expect(await db.select(db.memoryCards).get(), hasLength(1));
    await old.dispose();
    await next.dispose();
  });

  test(
      'real runtime disposal drains legacy receipt before DB replacement and factory uses new DB',
      () async {
    SharedPreferences.setMockInitialValues(
        {DeviceIdentityService.preferenceKey: 'synthetic-owner-lifetime'});
    DeviceIdentityService.resetForTesting();
    final runtime = await PersonalDataHubRuntime.create(
        db: db,
        alarms: FakeAlarms(),
        enablePlanningReminders: false,
        ownsCaptureConnectionLifetime: true);
    final entered = Completer<void>(), release = Completer<void>();
    var first = true;
    final service = ClaudeWebNoteFeedService(
        storage: storage,
        importerFactory: () => importer(db, organize: (source) async {
              if (first) {
                entered.complete();
                await release.future;
              }
              return OrganizedRecord(cards: [card(source.rawInput)]);
            }),
        client: MockClient((r) async => r.method == 'GET'
            ? page([item(seq: first ? 1 : 2)])
            : http.Response('{"ok":true}', 200)));
    await service.configure(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    final sync = service.syncOnce();
    await entered.future;
    var stopped = false;
    final stop = runtime.dispose().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, false);
    release.complete();
    expect((await sync).valueOrThrow.cursor, 1);
    await stop;
    expect(await db.select(db.memoryCards).get(), hasLength(1));
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    first = false;
    expect((await service.syncOnce()).valueOrThrow.cursor, 2);
    expect(await db.select(db.memoryCards).get(), hasLength(1));
    await service.dispose();
  });
}
