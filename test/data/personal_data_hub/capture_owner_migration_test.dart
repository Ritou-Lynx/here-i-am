import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_service.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';
import 'package:memex/data/personal_data_hub/capture_consumer.dart';
import 'package:memex/data/personal_data_hub/capture_owner_migration.dart';
import 'package:memex/data/personal_data_hub/core_domain_workflow.dart';
import 'package:memex/data/personal_data_hub/domain_access.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/domain_http_transport.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

import '../memory_v3/notes/claude_web_note_feed_test.dart' show card, item;

const _secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
final _now = DateTime.utc(2026, 10, 7, 1);

CoreDomainAccessGrant _grant() => const CoreDomainAccessGrant(
      protocolVersion: 1,
      coreInstanceId: 'core-migration-synthetic',
      principalId: 'capture-owner',
      credentialGeneration: 3,
      installationId: 'phone-install',
      policyVersion: DomainPolicy.version,
      schemaVersion: 1,
      token: 'independent-owner-bearer',
      scopes: [
        'captures:read',
        'captures:ack',
        'captures:adopt',
        'captures:owner',
      ],
      authorization: CoreDomainAuthorizationGrant(
        scheme: 'hmac-sha256-v1',
        keyId: 'synthetic-owner-key',
        secret: _secret,
      ),
    );

DomainBinding _binding(CoreDomainAccessGrant grant) => DomainBinding(
      coreInstanceId: grant.coreInstanceId,
      principalId: grant.principalId,
      generation: grant.credentialGeneration,
      installationId: grant.installationId,
    );

Json _signedProof(CaptureMigrationManifest manifest) {
  final records = manifest.records;
  final entries = [
    for (var index = 0; index < records.length; index++)
      {
        'source_id': records[index]['source_id'],
        'source_revision': records[index]['source_revision'],
        'source_digest': records[index]['source_digest'],
        'target_id': records[index]['source_id'],
        'target_revision': records[index]['source_revision'],
        'is_tombstone': records[index]['op'] == 'delete',
        'adopted_op_id': 'adopt-op-${index + 1}',
        'receipt_id': 'receipt-${index + 1}',
        'receipt_auth': '6' * 64,
        'adoption_binding_digest': '5' * 64,
        'output_ids': records[index]['output_ids'],
        'output_digest': records[index]['output_digest'],
      }
  ];
  final proof = <String, dynamic>{
    'protocol': 'i-domain-migration-v1',
    'phase': 'adopt',
    'migration_id': manifest.migrationId,
    'domain': 'captures',
    'binding': manifest.binding,
    'source': manifest.source,
    'prior_proof_digest': null,
    'details': {
      'batch_id': 'batch-synthetic',
      'mapping_version': 'mapping-v1',
      'entries': entries,
      'entries_digest': domainDigest(entries),
      'pending_ops': 0,
      'conflict_count': 0,
    },
    'issued_at': '2026-10-07T00:59:00.000Z',
    'expires_at': '2026-10-07T01:59:00.000Z',
  };
  final secret = base64Url.decode('$_secret=');
  final mac = base64UrlEncode(
          Hmac(sha256, secret).convert(utf8.encode(canonicalJson(proof))).bytes)
      .replaceAll('=', '');
  proof['proof_ref'] = 'mig1.synthetic-owner-key.$mac';
  return proof;
}

class _FakeAdoptionTransport extends DomainHttpTransport {
  _FakeAdoptionTransport(this.entry, DomainBinding binding,
      {this.currentRevision})
      : super(
          baseUrl: 'http://127.0.0.1:47862',
          token: 'synthetic-owner-token',
          binding: binding,
        );
  final Json entry;
  final int? currentRevision;

  @override
  Future<Json> operation(String domain, String opId) async => {
        'found': true,
        'target_state': entry['is_tombstone'] == true ? 'deleted' : 'present',
        'result': {
          'domain_protocol_version': 1,
          'domain': 'captures',
          'op_id': opId,
          'outcome': 'accepted',
          'receipt': {
            'receipt_id': entry['receipt_id'],
            'core_instance_id': binding.coreInstanceId,
            'authority_mode': 'single_host',
            'epoch': null,
            'domain': 'captures',
            'accepted_op_id': opId,
            'principal_id': binding.principalId,
            'accepted_at': '2026-10-07T00:59:00.000Z',
            'policy_version': binding.policyVersion,
            'targets': [
              {'id': entry['target_id'], 'revision': entry['target_revision']}
            ],
            'change_sequences': [1],
            'adoption_binding_digest': entry['adoption_binding_digest'],
            'receipt_auth': entry['receipt_auth'],
          }
        }
      };

  @override
  Future<Json> currentRecord(String domain, String id) async => {
        'deleted': entry['is_tombstone'],
        'policy_version': binding.policyVersion,
        'record': {
          'id': id,
          'domain': 'captures',
          'core_instance_id': binding.coreInstanceId,
          'revision': currentRevision ?? entry['target_revision'],
          if (entry['is_tombstone'] != true)
            'provenance': {'source': 'i_remember'},
        }
      };
}

CaptureAdoptionReceiptRefetch _refetch(Json proof, CoreDomainAccessGrant grant,
    {int? currentRevision}) {
  final entry =
      jsonObject((jsonObject(proof['details'])['entries'] as List).single);
  return createCaptureAdoptionReceiptRefetch(
      _FakeAdoptionTransport(entry, _binding(grant),
          currentRevision: currentRevision),
      grant);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CoreDomainAccessGrant grant;
  late CaptureAdoptionProofVerifier verifier;
  late CaptureConsumerOwnership ownership;
  late DomainStore store;
  late RecordOrganizerServiceV3 organizer;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    grant = _grant();
    verifier = CaptureAdoptionProofVerifier(grant, clock: () => _now);
    ownership = CaptureConsumerOwnership(db, adoptionVerifier: verifier);
    store = DomainStore(db, binding: _binding(grant), clock: () => _now);
    organizer = RecordOrganizerServiceV3(db);
  });
  tearDown(() => db.close());

  test('Core migration proof canonical HMAC fixed vector', () {
    final unsigned = jsonObject(jsonDecode(
        r'''{"protocol":"i-domain-migration-v1","phase":"adopt","migration_id":"migration-fixed","domain":"captures","binding":{"core_instance_id":"core-fixed","principal_id":"owner-fixed","credential_generation":4,"installation_id":"install-fixed"},"source":{"source_kind":"i_remember","source_instance_id":"legacy-fixed","source_cursor":"cursor-fixed","record_count":1,"records_digest":"3333333333333333333333333333333333333333333333333333333333333333","outputs_digest":"4444444444444444444444444444444444444444444444444444444444444444"},"prior_proof_digest":null,"details":{"batch_id":"batch-fixed","mapping_version":"mapping-fixed","entries":[{"source_id":"legacy-1","source_revision":2,"source_digest":"1111111111111111111111111111111111111111111111111111111111111111","target_id":"legacy-1","target_revision":2,"is_tombstone":false,"adopted_op_id":"00000000-0000-4000-8000-000000000001","receipt_id":"receipt-1","receipt_auth":"receipt-auth-synthetic","adoption_binding_digest":"5555555555555555555555555555555555555555555555555555555555555555","output_ids":[],"output_digest":"2222222222222222222222222222222222222222222222222222222222222222"}],"entries_digest":"14e83f3c1728e1280bc917b0b92775db78636394499d6bf165d59a6f7c83b766","pending_ops":0,"conflict_count":0},"issued_at":"2026-10-07T08:00:00.000Z","expires_at":"2026-10-07T20:00:00.000Z"}'''));
    final mac = base64UrlEncode(Hmac(sha256, base64Url.decode('$_secret='))
            .convert(utf8.encode(canonicalJson(unsigned)))
            .bytes)
        .replaceAll('=', '');
    expect('mig1.migration-key.$mac',
        'mig1.migration-key.YhV99dnM_8fcB6CvjdGqX2cY0Dy8hlg_i9vV1zXUy_M');
  });

  Future<void> importActualReceipt() async {
    final importer = ClaudeWebNoteImporter(
      db: db,
      organizer: organizer,
      organize: (source) async =>
          OrganizedRecord(cards: [card(source.rawInput)]),
    );
    await importer.apply(ClaudeWebNoteChange.fromJson(item()));
  }

  test(
      'actual reconciler receipt freezes and commits owner plus route atomically',
      () async {
    await importActualReceipt();
    final manifest = await ownership.freezeCaptureMigration(
      store: store,
      migrationId: 'migration-1',
      sourceInstanceId: 'legacy-bridge-47862',
      sourceCursor: 1,
    );
    expect(manifest.source['source_cursor'], '1');
    await expectLater(
        ownership.runLegacy((_) async {}),
        throwsA(isA<DomainFailure>()
            .having((e) => e.code, 'code', 'capture_migration_frozen')));
    final proof = _signedProof(manifest);
    await ownership.commitCaptureMigration(
      store: store,
      adoptionProof: proof,
      refetchCurrentReceipt: _refetch(proof, grant),
    );
    expect(await ownership.coreSelected(), true);
    await ownership.runCore((lease) => lease.verify(),
        bindingFingerprint:
            canonicalJson(_binding(grant).forDomain('captures')));
    ownership.configureAdoptionVerifier(CaptureAdoptionProofVerifier(grant,
        clock: () => _now.add(const Duration(days: 2))));
    await ownership.runCore((lease) => lease.verify(),
        bindingFingerprint:
            canonicalJson(_binding(grant).forDomain('captures')));
    final state = await store.read();
    expect(store.domain(state, 'captures')['route'], 'core');
    expect(
        (jsonDecode((await db.customSelect(
                'SELECT value FROM kv_store WHERE key=?',
                variables: [
              const Variable('capture_consumer_ownership.v1')
            ]).getSingle())
            .read<String>('value')) as Map)['migration'],
        null);

    var extracts = 0;
    final consumer = CaptureConsumer(
      db: db,
      store: store,
      organizer: organizer,
      extract: (text) async {
        extracts++;
        return OrganizedRecord(cards: [card(text)]);
      },
      decodeText: (data) => data['text'] as String,
      inputVersion: (record) => record['field_meta']?['text']?['rev'] as int?,
    );
    Future<void> coreRecord(int version, {bool deleted = false}) =>
        store.applyPage('captures', {
          'next_cursor': 'core-$version',
          'policy_version': DomainPolicy.version,
          'records': [
            {
              'id': 'note_one',
              'domain': 'captures',
              'core_instance_id': grant.coreInstanceId,
              'revision': version,
              if (deleted) ...{
                'deleted_at': '2026-10-07T02:00:00.000Z',
                'body_state': 'purged',
              } else ...{
                'data': {'text': 'core revision $version'},
                'provenance': {'source': 'i_remember'},
                'field_meta': {
                  'text': {'rev': version}
                },
              }
            }
          ]
        });
    await coreRecord(1);
    expect(await consumer.consume(), 0);
    expect(extracts, 0);
    expect(await db.select(db.memoryCards).get(), hasLength(1));
    final adoptedCardId = (await db.select(db.memoryCards).getSingle()).id;
    await coreRecord(2);
    expect(await consumer.consume(), 1);
    expect(extracts, 1);
    expect((await db.select(db.memoryCards).getSingle()).id, adoptedCardId);
    await organizer.updateCard(adoptedCardId,
        title: 'user preserved after adoption', actor: 'user_direct');
    await coreRecord(3, deleted: true);
    expect(await consumer.consume(), 1);
    expect((await db.select(db.memoryCards).getSingle()).title,
        'user preserved after adoption');
  });

  test('product workflow exports manifest and accepts only proof envelope',
      () async {
    await importActualReceipt();
    var reloads = 0;
    final connection = CoreSyncConnection(
      baseUrl: 'https://core.example.invalid',
      deviceToken: 'chat-only-token',
      initialCursor: 'chat-cursor',
      coreNodeId: grant.coreInstanceId,
      domainAccess: grant,
    );
    late Json proof;
    final workflow = CoreDomainWorkflowService(
      db: db,
      hub: PersonalDataHub.forDatabase(db),
      ownership: ownership,
      readConnection: () async => connection,
      replaceDomainAccess: (_, __) async {},
      readInstallationId: () async => grant.installationId,
      reloadRuntime: () async => reloads++,
      readLegacyFeedConfig: () async => const ClaudeWebNoteFeedConfig(
        baseUrl: 'https://legacy.example.invalid',
        token: 'not-exported',
        cursor: 1,
      ),
      createMigrationId: () => 'migration-product-entry',
      loadAccess: () async => ConfiguredDomainAccess(
        stores: {'captures': store},
        authorizeCapture: null,
        authorizePlanning: null,
        captureAdoptionVerifier: verifier,
        captureAdoptionReceiptRefetch: (entry) => _refetch(proof, grant)(entry),
      ),
    );

    final exported =
        jsonObject(jsonDecode(await workflow.freezeCaptureMigration()));
    expect(exported.keys.toSet(), {'format', 'manifest'});
    expect(exported['format'], 'i-core-capture-migration-manifest-export-v1');
    final manifest = CaptureMigrationManifest(jsonObject(exported['manifest']));
    expect(manifest.migrationId, 'migration-product-entry');
    expect(manifest.source['source_instance_id'], startsWith('claude-web-'));
    expect(
        canonicalJson(jsonDecode(await workflow.exportFrozenCaptureManifest())),
        canonicalJson(exported));

    proof = _signedProof(manifest);
    await expectLater(
      workflow.commitCaptureMigration(jsonEncode(proof)),
      throwsA(isA<CoreDomainWorkflowFailure>()
          .having((e) => e.code, 'code', 'proof_file_invalid')),
    );
    expect((await ownership.workflowState()).frozenManifest,
        isA<CaptureMigrationManifest>());

    await workflow.commitCaptureMigration(jsonEncode({
      'format': 'i-core-capture-migration-proof-v1',
      'proof': proof,
    }));
    expect(await ownership.coreSelected(), isTrue);
    expect(reloads, 1);
    expect(store.domain(await store.read(), 'captures')['route'], 'core');
  });

  test('post-freeze user mutation leaves migration frozen and phone-owned',
      () async {
    await importActualReceipt();
    final manifest = await ownership.freezeCaptureMigration(
      store: store,
      migrationId: 'migration-2',
      sourceInstanceId: 'legacy-bridge-47862',
      sourceCursor: 1,
    );
    final cardId = (await db.select(db.memoryCards).getSingle()).id;
    await organizer.updateCard(cardId,
        title: 'user preserved title', actor: 'user_direct');
    final proof = _signedProof(manifest);
    await expectLater(
      ownership.commitCaptureMigration(
        store: store,
        adoptionProof: proof,
        refetchCurrentReceipt: _refetch(proof, grant),
      ),
      throwsA(isA<DomainFailure>()),
    );
    expect(await ownership.coreSelected(), false);
    expect(store.domain(await store.read(), 'captures')['route'], 'phone');
    expect((await db.select(db.memoryCards).getSingle()).title,
        'user preserved title');
  });

  test('fresh receipt cannot commit after the Core record changes', () async {
    await importActualReceipt();
    final manifest = await ownership.freezeCaptureMigration(
      store: store,
      migrationId: 'migration-core-race',
      sourceInstanceId: 'legacy-bridge-47862',
      sourceCursor: 1,
    );
    final proof = _signedProof(manifest);
    await expectLater(
      ownership.commitCaptureMigration(
        store: store,
        adoptionProof: proof,
        refetchCurrentReceipt: _refetch(proof, grant, currentRevision: 2),
      ),
      throwsA(isA<DomainFailure>()
          .having((e) => e.code, 'code', 'capture_adoption_record_changed')),
    );
    expect(await ownership.coreSelected(), false);
    expect(store.domain(await store.read(), 'captures')['route'], 'phone');
  });

  test('finance card without immutable creation witness is blocked', () async {
    final importer = ClaudeWebNoteImporter(
      db: db,
      organizer: organizer,
      organize: (source) async => OrganizedRecord(cards: [
        OrganizedCard(
          type: 'event',
          title: 'synthetic expense',
          dropletLabel: '记录',
          presentationModule: const {'blocks': []},
          retrievalText: 'synthetic expense',
          valence: 0,
          arousal: 0,
          structuredFieldsType: 'expense_entry',
          structuredFields: const {
            'amount_cny': 10,
            'purpose': 'synthetic',
            'paidAt': '2026-10-07T00:00:00.000Z'
          },
        )
      ]),
    );
    await importer.apply(ClaudeWebNoteChange.fromJson(item()));
    await expectLater(
      ownership.freezeCaptureMigration(
        store: store,
        migrationId: 'migration-finance',
        sourceInstanceId: 'legacy-bridge-47862',
        sourceCursor: 1,
      ),
      throwsA(isA<DomainFailure>()
          .having((e) => e.code, 'code', 'finance_origin_unverified')),
    );
    expect(await ownership.coreSelected(), false);
  });

  test('empty and oversized receipt sets are rejected before freeze', () async {
    await expectLater(
      ownership.freezeCaptureMigration(
        store: store,
        migrationId: 'migration-empty',
        sourceInstanceId: 'legacy-bridge-47862',
        sourceCursor: 0,
      ),
      throwsA(isA<DomainFailure>()
          .having((e) => e.code, 'code', 'capture_migration_unresolved')),
    );
    await db.batch((batch) {
      for (var index = 0; index < 5001; index++) {
        batch.insert(
          db.memoryCardOperations,
          MemoryCardOperationsCompanion.insert(
            id: 'receipt-$index',
            cardId: 'card-$index',
            operationType: 'external_note_import',
            sourceKind: 'claude_web_note',
            payload: jsonEncode({
              'note_id': 'note-$index',
              'revision': 1,
            }),
            createdAt: index,
          ),
        );
      }
    });
    await expectLater(
      ownership.freezeCaptureMigration(
        store: store,
        migrationId: 'migration-oversized',
        sourceInstanceId: 'legacy-bridge-47862',
        sourceCursor: 5001,
      ),
      throwsA(isA<DomainFailure>()
          .having((e) => e.code, 'code', 'capture_migration_unresolved')),
    );
    expect(await ownership.coreSelected(), false);
  });

  test(
      'commit fault rolls back lifecycle owner and route then same proof retries',
      () async {
    await importActualReceipt();
    final manifest = await ownership.freezeCaptureMigration(
      store: store,
      migrationId: 'migration-rollback',
      sourceInstanceId: 'legacy-bridge-47862',
      sourceCursor: 1,
    );
    final proof = _signedProof(manifest);
    final failingStore = DomainStore(
      db,
      binding: _binding(grant),
      clock: () => _now,
      testFault: (point) {
        if (point == 'before_local_commit') throw StateError('fault');
      },
    );
    await expectLater(
      ownership.commitCaptureMigration(
        store: failingStore,
        adoptionProof: proof,
        refetchCurrentReceipt: _refetch(proof, grant),
      ),
      throwsStateError,
    );
    expect(await ownership.coreSelected(), false);
    expect(store.domain(await store.read(), 'captures')['route'], 'phone');
    expect(
      await db
          .customSelect(
            "SELECT key FROM kv_store WHERE key LIKE 'capture_lifecycle.%'",
          )
          .get(),
      isEmpty,
    );
    await ownership.commitCaptureMigration(
      store: store,
      adoptionProof: proof,
      refetchCurrentReceipt: _refetch(proof, grant),
    );
    expect(await ownership.coreSelected(), true);
    expect(store.domain(await store.read(), 'captures')['route'], 'core');
    expect(
      await db
          .customSelect(
            "SELECT key FROM kv_store WHERE key LIKE 'capture_lifecycle.%'",
          )
          .get(),
      hasLength(1),
    );
  });

  test('proof expiring during refetch cannot write owner route or lifecycle',
      () async {
    var now = _now;
    final expiringOwnership = CaptureConsumerOwnership(
      db,
      adoptionVerifier: CaptureAdoptionProofVerifier(grant, clock: () => now),
    );
    await importActualReceipt();
    final manifest = await expiringOwnership.freezeCaptureMigration(
      store: store,
      migrationId: 'migration-expiring',
      sourceInstanceId: 'legacy-bridge-47862',
      sourceCursor: 1,
    );
    final proof = _signedProof(manifest);
    final refetch = _refetch(proof, grant);
    await expectLater(
      expiringOwnership.commitCaptureMigration(
        store: store,
        adoptionProof: proof,
        refetchCurrentReceipt: (entry) async {
          final receipt = await refetch(entry);
          now = DateTime.utc(2026, 10, 7, 1, 59);
          return receipt;
        },
      ),
      throwsA(isA<DomainFailure>()
          .having((e) => e.code, 'code', 'capture_adoption_proof_expired')),
    );
    expect(await expiringOwnership.coreSelected(), false);
    expect(store.domain(await store.read(), 'captures')['route'], 'phone');
    expect(
      await db
          .customSelect(
            "SELECT key FROM kv_store WHERE key LIKE 'capture_lifecycle.%'",
          )
          .get(),
      isEmpty,
    );
  });
}
