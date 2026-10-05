import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';

/// A real SQLite connection, minimal owned synthetic schema, no App singleton.
class CrashDatabase extends GeneratedDatabase {
  CrashDatabase(File file) : super(NativeDatabase(file));
  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(onCreate: (m) async {
        await customStatement(
            'CREATE TABLE kv_store(key TEXT PRIMARY KEY,value TEXT,bucket TEXT,updated_at INTEGER)');
      });
}

const fixtureBinding = DomainBinding(
    coreInstanceId: 'core-test',
    principalId: 'phone-test',
    generation: 1,
    installationId: 'installation-test');
Future<void> main(List<String> args) async {
  final db = CrashDatabase(File(args[0]));
  final store = DomainStore(db, binding: fixtureBinding, testFault: (point) {
    if (point == args[1]) {
      // The parent kills this process while SQLite is open (with/without txn).
      File('${args[0]}.ready').writeAsStringSync(point, flush: true);
      sleep(const Duration(seconds: 45));
    }
  });
  if (args[2] == 'enqueue') {
    await store.configureRoute('example', DomainRoute.core);
    await store.enqueue('example',
        id: 'record-a',
        kind: 'create',
        actor: 'agent_inferred',
        fields: {
          'data': {'title': 'synthetic durable'},
          'provenance': {
            'source': 'fixture',
            'source_refs': [],
            'import_batch_id': null
          }
        });
  } else if (args[2] == 'submit') {
    await store.prepare('example');
    await store.fault('submit_after_local_commit');
  } else if (args[2] == 'receipt') {
    await store.fault('response_before_save');
    final state = await store.read();
    final op = (state['outbox'] as List).first['op_id'];
    await store.complete(op, {
      'domain': 'example',
      'op_id': op,
      'outcome': 'accepted',
      'receipt': {
        'receipt_id': 'receipt-a',
        'accepted_op_id': op,
        'principal_id': 'phone-test',
        'accepted_at': '2026-10-05T00:00:00.000Z',
        'policy_version': DomainPolicy.version,
        'core_instance_id': 'core-test',
        'domain': 'example',
        'authority_mode': 'single_host',
        'epoch': null,
        'receipt_auth': '0' * 64,
        'targets': [
          {'id': 'record-a', 'revision': 1}
        ],
        'change_sequences': [1]
      }
    });
    await store.fault('receipt_after_commit');
  } else if (args[2] == 'snapshot') {
    await store.replaceSnapshot('example', [
      {
        'id': 'canonical-new',
        'domain': 'example',
        'revision': 2,
        'core_instance_id': 'core-test',
        'data': {'title': 'new'}
      }
    ], {
      'base_cursor': 'cursor-new',
      'snapshot_id': 'snapshot-new'
    });
  }
  if (args[2] == 'snapshot') await store.fault('snapshot_after_commit');
  await db.close();
}
