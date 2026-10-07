import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/ai_finance_service.dart';

const binding = DomainBinding(
    coreInstanceId: 'synthetic-shared-core',
    principalId: 'synthetic-shared-principal',
    generation: 1,
    installationId: 'synthetic-shared-installation');
const captureId = 'synthetic-shared-capture';

class Attempt {
  const Attempt.success(this.count) : busyError = null;
  const Attempt.busy(this.busyError) : count = null;
  final int? count;
  final SqliteException? busyError;
  int? get busyCode => busyError?.extendedResultCode;
}

/// Only SQLITE_BUSY (including BUSY_SNAPSHOT) is an observed retry outcome.
/// Schema, constraints, bindings, extraction, and unknown exceptions must fail.
Future<Attempt> attempt(CaptureConsumer consumer) async {
  try {
    return Attempt.success(await consumer.consume());
  } on SqliteException catch (error) {
    if (error.resultCode != 5) rethrow;
    return Attempt.busy(error);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late List<AppDatabase> databases;
  late List<DomainStore> stores;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('capture-connections-synthetic-');
    final file = File('${directory.path}/app.sqlite');
    final first = AppDatabase.forTesting(NativeDatabase(file));
    databases = [first];
    // Fully migrate the fixture before opening the independent second handle.
    await first.customSelect('SELECT count(*) FROM kv_store').get();
    await first.customSelect('PRAGMA journal_mode=WAL').get();
    final second = AppDatabase.forTesting(NativeDatabase(file));
    databases.add(second);
    await second.customSelect('SELECT count(*) FROM kv_store').get();
    for (final db in databases) {
      // Never block the Dart event loop waiting for a lock held by its peer.
      // Busy is captured explicitly and retried only after both attempts settle.
      await db.customSelect('PRAGMA busy_timeout=0').get();
    }
    expect(identical(first.executor, second.executor), false);
    final files = await Future.wait(databases.map((db) async =>
        (await db.customSelect('PRAGMA database_list').get())
            .singleWhere((row) => row.read<String>('name') == 'main')
            .read<String>('file')));
    expect(files[0], isNotEmpty);
    expect(files[0], files[1]);
    stores = [for (final db in databases) DomainStore(db, binding: binding)];
  });
  tearDown(() async {
    for (final db in databases.reversed) {
      await db.close();
    }
    final tempPrefix =
        '${Directory.systemTemp.absolute.path.toLowerCase()}${Platform.pathSeparator}';
    if (!directory.absolute.path.toLowerCase().startsWith(tempPrefix)) {
      throw StateError('Unsafe synthetic fixture cleanup');
    }
    await directory.delete(recursive: true);
  });

  Future<Json> ledger(AppDatabase db) async {
    final rows = await db
        .customSelect(
            "SELECT key,value FROM kv_store WHERE bucket='capture_consumer'")
        .get();
    expect(rows, hasLength(1),
        reason: 'one durable lifecycle ledger for the shared capture');
    expect(rows.single.read<String>('key'),
        'capture_lifecycle.${binding.coreInstanceId}.$captureId');
    return jsonObject(jsonDecode(rows.single.read<String>('value')));
  }

  for (final route in [DomainRoute.phone, DomainRoute.core]) {
    test(
        'two independent SQLite connections converge for ${route.name} capture versions',
        () async {
      if (route == DomainRoute.core) {
        await stores.first.configureRoute('captures', route);
      }
      Set<String>? originalIds;
      Set<String>? originalFinanceIds;
      var totalBusy = 0;
      for (var version = 1; version <= 2; version++) {
        final text = 'synthetic input version $version';
        if (route == DomainRoute.phone) {
          await stores.first.enqueue('captures',
              id: captureId,
              kind: version == 1 ? 'create' : 'patch',
              actor: 'user_direct',
              authorizationRef: 'synthetic-action-$version',
              fields: version == 1
                  ? {
                      'data': {'text': text, 'source': 'phone_quick'},
                      'provenance': {
                        'source': 'phone_quick',
                        'source_refs': [],
                        'import_batch_id': null
                      },
                    }
                  : {
                      'patch': {'text': text}
                    });
        } else {
          await stores.first.applyPage('captures', {
            'next_cursor': 'cursor-$version',
            'policy_version': DomainPolicy.version,
            'records': [
              {
                'id': captureId,
                'domain': 'captures',
                'core_instance_id': binding.coreInstanceId,
                'revision': version,
                'data': {'text': text, 'source': 'phone_quick'},
                'provenance': {'source': 'phone_quick'},
                'field_meta': {
                  'text': {'rev': version}
                },
              }
            ],
          });
        }
        final bothExtracted = Completer<void>(), release = Completer<void>();
        final extractionCalls = [0, 0];
        var arrivals = 0;
        final consumers = [
          for (var engine = 0; engine < 2; engine++)
            CaptureConsumer(
                db: databases[engine],
                store: stores[engine],
                organizer: RecordOrganizerServiceV3(databases[engine]),
                decodeText: (data) => data['text'] as String,
                inputVersion: (record) =>
                    record['field_meta']?['text']?['rev'] as int?,
                extract: (input) async {
                  expect(input, text);
                  extractionCalls[engine]++;
                  final result = OrganizedRecord(cards: [
                    for (var slot = 0; slot < 2; slot++)
                      OrganizedCard(
                          type: 'fact',
                          structuredFieldsType: 'expense_entry',
                          structuredFields: {
                            'amount_cny': 10 * version,
                            'paidAt': '2026-10-06T12:00:00'
                          },
                          title: 'stable slot-$slot',
                          dropletLabel: 'synthetic',
                          presentationModule: {'blocks': []},
                          retrievalText: 'engine-$engine $text slot-$slot',
                          valence: 0,
                          arousal: 0),
                  ]);
                  arrivals++;
                  if (arrivals == 2) bothExtracted.complete();
                  // Both real consumers finish extraction before either returns
                  // to its independent SQLite projection/ledger transaction.
                  await release.future;
                  return result;
                }),
        ];
        final beforeExtractionBusy = <int>[];
        void checkFence(Attempt result) {
          if (result.busyError == null) return;
          expect(result.busyError!.causingStatement,
              'UPDATE kv_store SET updated_at=updated_at WHERE 0');
          expect(result.busyError!.parametersToStatement, isEmpty);
        }

        Future<Attempt> race(int engine) async {
          // Initial reads/legacy checks now also acquire the writer slot.
          // Retry only known busy before extraction so both engines reach the
          // actual projection race; no failed extraction is silently retried.
          for (var retry = 0; retry < 50; retry++) {
            final result = await attempt(consumers[engine]);
            checkFence(result);
            if (result.busyCode == null || extractionCalls[engine] > 0) {
              return result;
            }
            beforeExtractionBusy.add(result.busyCode!);
            await Future<void>.delayed(Duration.zero);
          }
          throw StateError('pre-extraction writer lock did not converge');
        }

        final racing = Future.wait([race(0), race(1)]);
        final coordination = () async {
          try {
            await bothExtracted.future.timeout(const Duration(seconds: 10));
            expect(extractionCalls, [1, 1]);
          } finally {
            if (!release.isCompleted) release.complete();
          }
        }();
        // Attach error handlers to both futures immediately. Unknown errors
        // propagate; coordination only releases the test's extraction barrier.
        final settled = await Future.wait<Object?>([racing, coordination]);
        final outcomes = settled.first as List<Attempt>;
        final busyCodes =
            outcomes.map((r) => r.busyCode).whereType<int>().toList();
        totalBusy += busyCodes.length + beforeExtractionBusy.length;
        stdout.writeln(
            '${route.name} version=$version pre_extraction_busy=$beforeExtractionBusy');
        final busyDescription = outcomes
            .where((r) => r.busyError != null)
            .map((r) =>
                '${r.busyCode}:${r.busyError!.causingStatement?.split(' ').take(4).join(' ')}')
            .join(',');
        stdout.writeln('${route.name} version=$version busy=$busyDescription');
        for (var engine = 0; engine < databases.length; engine++) {
          final db = databases[engine];
          final cards = await db.select(db.memoryCards).get();
          stdout.writeln(
              '${route.name} engine=$engine initial_count=${outcomes[engine].count} visible_cards=${cards.length}');
          if (outcomes[engine].count == 1) {
            expect(cards, hasLength(2));
            expect((await ledger(db))['slots'], hasLength(2));
          }
        }
        expect(outcomes.where((r) => r.count == 1), hasLength(1));
        expect(
            outcomes
                .where((r) => r.count != null)
                .every((r) => r.count == 0 || r.count == 1),
            true);
        // With the competing transaction finished, a busy loser must converge
        // by re-reading the durable ledger, without extracting or inserting.
        for (var engine = 0; engine < outcomes.length; engine++) {
          if (outcomes[engine].busyCode != null) {
            final retries = <Attempt>[];
            for (var retry = 0; retry < 3; retry++) {
              final result = await attempt(consumers[engine]);
              checkFence(result);
              retries.add(result);
              if (result.busyCode == null) break;
            }
            stdout.writeln(
                '${route.name} engine=$engine retry_codes=${retries.map((r) => r.busyCode).toList()}');
            expect(retries.last.count, 0,
                reason:
                    'settled peer must not leave this connection permanently busy: '
                    '${retries.last.busyError?.message}');
          }
        }
        final left = await ledger(databases[0]),
            right = await ledger(databases[1]);
        expect(left, right);
        expect(left['capture_id'], captureId);
        expect(left['input_version'], version);
        expect(left['issues'], isEmpty);
        expect(left['slots'], hasLength(2));
        final slots =
            (left['slots'] as List).map((r) => r['id'] as String).toSet();
        for (final db in databases) {
          final cards = await db.select(db.memoryCards).get();
          expect(cards, hasLength(2),
              reason: 'losing transaction cannot leave orphan output cards');
          expect(cards.map((card) => card.id).toSet(), slots);
          expect(
              cards.map((card) => card.retrievalText.split(' ').first).toSet(),
              hasLength(1));
          expect(
              cards.every(
                  (card) => card.retrievalText.contains('version $version')),
              true);
        }
        for (final db in databases) {
          final panel =
              await AiFinanceService(db: db).getRecentEntries(month: '2026-10');
          expect(panel, hasLength(2));
          expect(panel.map((row) => row['linked_fact_id']).toSet(), slots);
          expect(
              panel.every((row) => row['total_amount'] == 10 * version), true);
          final financeIds = panel.map((row) => row['id'] as String).toSet();
          if (originalFinanceIds != null) {
            expect(financeIds, originalFinanceIds);
          }
          originalFinanceIds = financeIds;
          expect(await db.select(db.aiFinanceLedger).get(), hasLength(2));
        }
        if (originalIds != null) expect(slots, originalIds);
        originalIds = slots;
        for (final consumer in consumers) {
          expect(await consumer.consume(), 0);
          expect(await consumer.consume(), 0);
        }
        expect(extractionCalls, [1, 1],
            reason:
                'retries and subsequent passes use the committed input version');
        final outbox = (await stores.first.read())['outbox'] as List;
        if (route == DomainRoute.core) {
          expect(outbox.where((op) => op['intent']['kind'] == 'ack_capture'),
              hasLength(version));
        } else {
          expect(outbox, isEmpty);
        }
        // Synthetic diagnostic exposes contention rather than masking it.
        stdout.writeln(
            '${route.name} version=$version sqlite_busy_extended_codes=$busyCodes');
      }
      stdout.writeln('${route.name} total_observed_busy=$totalBusy');
    });
  }
}
