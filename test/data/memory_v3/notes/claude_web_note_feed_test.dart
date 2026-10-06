import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/result.dart';

Map<String, dynamic> item(
        {String id = 'note_one',
        int revision = 1,
        int seq = 1,
        String? text = 'synthetic note',
        bool deleted = false}) =>
    {
      'note_id': id,
      'revision': revision,
      'feed_seq': seq,
      'op': deleted ? 'delete' : 'upsert',
      'text': deleted ? null : text,
      'source': 'claude_web',
      'created_at_ms': 1700000000000,
      'updated_at_ms': 1700000000000 + seq,
    };
OrganizedCard card(String text, {bool rich = false}) => OrganizedCard(
      type: rich ? 'task' : 'fact',
      title: text,
      dropletLabel: '记录',
      presentationModule: {
        'blocks': [
          {'type': 'text', 'text': text}
        ]
      },
      retrievalText: text,
      valence: 0,
      arousal: 0.2,
      status: rich ? 'active' : null,
      structuredFieldsType: rich ? 'general' : null,
      structuredFields: rich ? {'dueAt': '2026-10-04', 'obsolete': true} : null,
      entityLinks: rich
          ? [
              OrganizedEntityLink(
                  name: 'Synthetic person',
                  category: 'person',
                  relation: 'about')
            ]
          : [],
    );
http.Response page(List<Map<String, dynamic>> notes,
        {int? next, bool more = false}) =>
    http.Response(
        jsonEncode({
          'notes': notes,
          'next_after': next ?? notes.last['feed_seq'],
          'has_more': more
        }),
        200);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late RecordOrganizerServiceV3 organizer;
  late ClaudeWebNoteFeedStorage storage;
  late ClaudeWebNoteImporter importer;
  var organizedCalls = 0;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    organizer = RecordOrganizerServiceV3(db);
    storage = ClaudeWebNoteFeedStorage();
    organizedCalls = 0;
    importer = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (source) async {
          organizedCalls++;
          return OrganizedRecord(cards: [card(source.rawInput)]);
        });
  });
  tearDown(() async {
    await db.close();
  });

  test('secure connection survives a new store and URL changes reset cursor',
      () async {
    await storage.saveConfig(
        baseUrl: 'https://synthetic.ts.net/', token: 'iph_synthetic');
    await storage.saveCursor(baseUrl: 'https://synthetic.ts.net', cursor: 9);
    final reopened = ClaudeWebNoteFeedStorage();
    expect((await reopened.readConfig())!.cursor, 9);
    await reopened.saveConfig(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_rotated');
    expect((await reopened.readConfig())!.cursor, 9);
    await reopened.saveConfig(
        baseUrl: 'https://other.ts.net', token: 'iph_other');
    expect((await reopened.readConfig())!.cursor, 0);
    await reopened.clearConfig();
    expect(await reopened.readConfig(), isNull);
  });

  test('rejects insecure remote URL and URL credentials', () async {
    for (final url in [
      'http://synthetic.ts.net',
      'https://user:pass@synthetic.ts.net',
      'https://synthetic.ts.net/path',
      'https://synthetic.ts.net/?secret=x'
    ]) {
      await expectLater(storage.saveConfig(baseUrl: url, token: 'iph_test'),
          throwsFormatException);
    }
  });

  test('create replay and new importer preserve one card and source identity',
      () async {
    final change = ClaudeWebNoteChange.fromJson(item());
    final id = await importer.apply(change);
    final fresh = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (_) async {
          fail('replay must not call the model');
        });
    expect(await fresh.apply(change), id);
    expect((await db.select(db.memoryCards).get()).length, 1);
    final source = await db.select(db.memoryCardSources).getSingle();
    expect(source.sourceKind, 'import');
    expect(source.sourceRef,
        ClaudeWebNoteImporter.projectionSourceRef('note_one'));
    expect(organizedCalls, 1);
  });

  test(
      'revision replaces structured fields entities raw input and presentation with correction',
      () async {
    var rich = true;
    final revised = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (source) async =>
            OrganizedRecord(cards: [card(source.rawInput, rich: rich)]));
    final first = await revised.apply(ClaudeWebNoteChange.fromJson(item()));
    expect((await db.select(db.memoryCardStructuredFields).get()).length, 1);
    expect((await db.select(db.memoryEntityLinks).get()).length, 1);
    rich = false;
    expect(
        await revised.apply(ClaudeWebNoteChange.fromJson(
            item(revision: 2, seq: 2, text: 'corrected'))),
        first);
    final row = await db.select(db.memoryCards).getSingle();
    expect(row.retrievalText, 'corrected');
    expect(row.presentationModule, contains('corrected'));
    expect(row.status, isNull);
    expect((await db.select(db.memoryCardStructuredFields).get()), isEmpty);
    expect((await db.select(db.memoryEntityLinks).get()), isEmpty);
    expect((await db.select(db.memoryCardSources).getSingle()).rawInput,
        'corrected');
    expect(await db.select(db.userCorrections).get(), isEmpty);
  });

  test(
      'multiple cards grow shrink and delete only the matching note projections',
      () async {
    var count = 2;
    final multi = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (source) async => OrganizedRecord(
            cards: List.generate(count, (i) => card('${source.rawInput} $i'))));
    final first = await multi.apply(ClaudeWebNoteChange.fromJson(item()));
    await importer
        .apply(ClaudeWebNoteChange.fromJson(item(id: 'other_note', seq: 2)));
    count = 3;
    expect(
        await multi
            .apply(ClaudeWebNoteChange.fromJson(item(revision: 2, seq: 3))),
        first);
    expect((await db.select(db.memoryCards).get()).length, 4);
    count = 1;
    expect(
        await multi
            .apply(ClaudeWebNoteChange.fromJson(item(revision: 3, seq: 4))),
        first);
    expect((await db.select(db.memoryCards).get()).length, 2);
    final deletion =
        ClaudeWebNoteChange.fromJson(item(revision: 4, seq: 5, deleted: true));
    expect(await multi.apply(deletion), first);
    expect(await multi.apply(deletion), first);
    // Old upsert replay cannot resurrect a tombstoned note.
    await multi.apply(ClaudeWebNoteChange.fromJson(item()));
    expect((await db.select(db.memoryCards).get()).length, 1);
    expect((await db.select(db.memoryCardSources).getSingle()).sourceRef,
        ClaudeWebNoteImporter.projectionSourceRef('other_note'));
  });

  test('receipt failure rolls back the entire card and source transaction',
      () async {
    await db.customStatement(
        "CREATE TRIGGER fail_receipt BEFORE INSERT ON memory_card_operations WHEN NEW.operation_type = 'external_note_import' BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END");
    await expectLater(importer.apply(ClaudeWebNoteChange.fromJson(item())),
        throwsA(anything));
    expect(await db.select(db.memoryCards).get(), isEmpty);
    expect(await db.select(db.memoryCardSources).get(), isEmpty);
    await db.customStatement('DROP TRIGGER fail_receipt');
    await importer.apply(ClaudeWebNoteChange.fromJson(item()));
    expect((await db.select(db.memoryCards).get()).length, 1);
  });

  test('missing connection and 401 return recoverable statuses without import',
      () async {
    var requests = 0;
    final service = ClaudeWebNoteFeedService(
        storage: storage,
        importer: importer,
        client: MockClient((_) async {
          requests++;
          return http.Response('', 401);
        }));
    expect((await service.syncOnce()).valueOrThrow.status,
        ClaudeWebNoteSyncStatus.notConfigured);
    expect(requests, 0);
    await service.configure(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    expect((await service.syncOnce()).valueOrThrow.status,
        ClaudeWebNoteSyncStatus.unauthorized);
    expect(organizedCalls, 0);
    expect((await storage.readConfig())!.cursor, 0);
    await service.dispose();
  });

  test(
      'ack failure and restart retry are idempotent and preserve cursor until ack',
      () async {
    await storage.saveConfig(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    var failAck = true;
    final acks = <Map<String, dynamic>>[];
    http.Client client() => MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer iph_synthetic');
          expect(request.followRedirects, false);
          if (request.method == 'GET') {
            expect(request.url.queryParameters['after'], '0');
            return page([item()]);
          }
          acks.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
              failAck ? '{}' : '{"ok":true}', failAck ? 503 : 200);
        });
    final first = ClaudeWebNoteFeedService(
        storage: storage, importer: importer, client: client());
    expect(await first.syncOnce(), isA<Error<ClaudeWebNoteSyncReport>>());
    expect((await storage.readConfig())!.cursor, 0);
    await first.dispose();
    failAck = false;
    final second = ClaudeWebNoteFeedService(
        storage: ClaudeWebNoteFeedStorage(),
        importer: importer,
        client: client());
    expect((await second.syncOnce()).valueOrThrow.cursor, 1);
    expect(organizedCalls, 1);
    expect(acks.first, acks.last);
    expect(acks.last['card_id'], isNotEmpty);
    await second.dispose();
  });

  test(
      'second item failure keeps first ack cursor and never imports a later item',
      () async {
    await storage.saveConfig(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    final seen = <String>[];
    final failing = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (source) async {
          seen.add(source.sourceRef!);
          if (source.sourceRef == 'two') {
            throw StateError('synthetic model failure');
          }
          return OrganizedRecord(cards: [card(source.rawInput)]);
        });
    final service = ClaudeWebNoteFeedService(
        storage: storage,
        importer: failing,
        client: MockClient((request) async => request.method == 'POST'
            ? http.Response('{"ok":true}', 200)
            : page(
                [item(), item(id: 'two', seq: 2), item(id: 'three', seq: 3)])));
    expect(await service.syncOnce(), isA<Error<ClaudeWebNoteSyncReport>>());
    expect((await storage.readConfig())!.cursor, 1);
    expect(seen, ['note_one', 'two']);
    await service.dispose();
  });

  test(
      'invalid feed cursor fails before processing and overlapping sync coalesces',
      () async {
    await storage.saveConfig(
        baseUrl: 'https://synthetic.ts.net', token: 'iph_synthetic');
    var requests = 0;
    final service = ClaudeWebNoteFeedService(
        storage: storage,
        importer: importer,
        client: MockClient((_) async {
          requests++;
          return page([item()], next: 50);
        }));
    final first = service.syncOnce();
    expect(identical(first, service.syncOnce()), true);
    expect(await first, isA<Error<ClaudeWebNoteSyncReport>>());
    expect(requests, 1);
    expect(organizedCalls, 0);
    expect((await storage.readConfig())!.cursor, 0);
    await service.dispose();
  });

  test('import does not steal a matching task from another record source',
      () async {
    final original = await organizer.persist(
        organized: OrganizedRecord(cards: [card('same task', rich: true)]),
        source:
            RecordSource(sourceKind: 'record_button', rawInput: 'same task'));
    final external = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (_) async =>
            OrganizedRecord(cards: [card('same task', rich: true)]));
    final imported = await external.apply(ClaudeWebNoteChange.fromJson(item()));
    expect(imported, isNot(original.cardIds.single));
    expect((await db.select(db.memoryCards).get()).length, 2);
    await external.apply(
        ClaudeWebNoteChange.fromJson(item(revision: 2, seq: 2, deleted: true)));
    expect((await db.select(db.memoryCards).getSingle()).id,
        original.cardIds.single);
    expect((await db.select(db.memoryCardSources).getSingle()).sourceKind,
        'record_button');
  });
  test('empty organizer output remains retryable without receipt', () async {
    final empty = ClaudeWebNoteImporter(
        db: db,
        organizer: organizer,
        organize: (_) async => OrganizedRecord(cards: []));
    await expectLater(
        empty.apply(ClaudeWebNoteChange.fromJson(item())), throwsStateError);
    expect(await db.select(db.memoryCardOperations).get(), isEmpty);
  });
}
