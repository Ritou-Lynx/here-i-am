import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_config.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_session_resources.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_owned_host.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';
import 'package:memex/p6_r7_candidate_main.dart' as candidate;

const _task = 'd6ea393e-81ae-41b9-89c8-1c7cc7743b5a';
const _dataset = 'b6ea393e-81ae-41b9-89c8-1c7cc7743b5a';
Map<String, dynamic> _fixture() => jsonDecode(
    File('test/data/workbench_ai/candidate/fixtures/witness_snapshot_hash.json')
        .readAsStringSync()) as Map<String, dynamic>;
Map<String, Object?> _closed() {
  final fixture = _fixture();
  return {
    'schema': 'p6_r7_app_lifecycle_running_close_v1',
    'utc': '2026-09-13T00:00:00.000Z',
    'pid': 123,
    'shutdown_reason': 'input_shutdown',
    'result': {
      'status': 'closed',
      'runtime_closed': true,
      'http_server_closed': true,
      'witness_close': {
        'host_closed_sha256': fixture['sha256'],
        'owner_manifest_sha256': 'a' * 64
      }
    },
    'snapshot': fixture['snapshot']
  };
}

P6R7OwnedHostWitnessReceipt _receipt([Map<String, Object?>? value]) =>
    P6R7OwnedHostWitnessReceipt.inspect(
        utf8.encode(jsonEncode(value ?? _closed())),
        expectedPid: 123);
P6R7CandidateSessionResources _resources(List<String> events,
        {bool fail = false}) =>
    P6R7CandidateSessionResources(drainExecution: () async {
      events.add('drain');
    }, closeStore: () async {
      events.add('store');
      if (fail) throw StateError('fixture');
    }, closeClient: () {
      events.add('dio');
    });

void main() {
  test('complete three-owner receipt uses bounded 4096-node projection', () {
    final bytes = File(
            'test/data/workbench_ai/candidate/fixtures/witness_three_owner_close.json')
        .readAsBytesSync();
    final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect((value['snapshot']['owners'] as List).length, 3);
    final receipt = P6R7OwnedHostWitnessReceipt.inspect(bytes,
        expectedPid: value['pid'] as int);
    expect(receipt.hostClosedSha256,
        sha256.convert(utf8.encode(jsonEncode(value['snapshot']))).toString());
  });
  test('receipt still rejects a snapshot exceeding 4096 nodes', () {
    final value = _closed();
    final snapshot = value['snapshot'] as Map<String, dynamic>;
    snapshot['owners'] = List<Object?>.filled(4096, null);
    final hashes = (value['result'] as Map<String, Object?>)['witness_close']
        as Map<String, Object?>;
    hashes['host_closed_sha256'] =
        sha256.convert(utf8.encode(jsonEncode(snapshot))).toString();
    expect(() => _receipt(value), throwsFormatException);
  });
  test('shared JavaScript snapshot bytes and SHA agree exactly with Dart', () {
    final fixture = _fixture();
    final encoded = jsonEncode(fixture['snapshot']);
    expect(encoded, fixture['compact_json']);
    expect(sha256.convert(utf8.encode(encoded)).toString(),
        '1418f896f19a3110a6e7d1ea9f3eea3d8183bef5bfcdf4a8973816e11069e204');
    expect(_receipt().hostClosedSha256, fixture['sha256']);
  });
  test('scope hash uses the single fixed ordered five-field contract', () {
    final ordered = {
      'profile_id': DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
      'scope_type': 'conversation',
      'scope_id': 'p6-r7-candidate-$_dataset',
      'title': p6R7CandidateTitle,
      'goal': p6R7CandidateGoal
    };
    expect(p6R7CandidateScopeHash(_dataset),
        sha256.convert(utf8.encode(jsonEncode(ordered))).toString());
  });
  test('successor erases every case variant of inherited witness discovery',
      () {
    final result = p6R7NodeEnvironment({
      'PATH': 'fixture',
      'P6_R7_WITNESS_PIPE': 'old',
      'p6_r7_witness_sha256': 'old',
      'P6_R7_WITNESS_UNKNOWN': 'old'
    }, null);
    expect(result, {'PATH': 'fixture'});
    expect(() => p6R7NodeEnvironment({'node_options': 'fixture'}, null),
        throwsFormatException);
  });
  test('fresh Node inherits only the newly authenticated witness fields', () {
    expect(
        p6R7NodeEnvironment({'PATH': 'fixture', 'P6_R7_WITNESS_PIPE': 'old'},
            {'P6_R7_WITNESS_PIPE': 'bound', 'P6_R7_WITNESS_PARENT_PID': '123'}),
        {
          'PATH': 'fixture',
          'P6_R7_WITNESS_PIPE': 'bound',
          'P6_R7_WITNESS_PARENT_PID': '123'
        });
  });
  test('durable task persistence completes before unique concurrent bind',
      () async {
    final events = <String>[];
    final persisted = Completer<void>(), bound = Completer<void>();
    final binding = candidate.P6R7CandidateTaskBinding(persist: (_) async {
      events.add('persist');
      await persisted.future;
    }, bind: (_) async {
      events.add('bind');
      await bound.future;
    });
    final a = binding.persist(_task), b = binding.persist(_task);
    expect(identical(a, b), isTrue);
    expect(events, ['persist']);
    persisted.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, ['persist', 'bind']);
    bound.complete();
    await a;
    await binding.persist(_task);
    expect(events, ['persist', 'bind']);
    expect(() => binding.persist(_dataset), throwsFormatException);
  });
  for (final failAt in ['persist', 'bind']) {
    test('task $failAt failure cannot manufacture a second bind', () async {
      final events = <String>[];
      final binding = candidate.P6R7CandidateTaskBinding(persist: (_) async {
        events.add('persist');
        if (failAt == 'persist') throw StateError('fixture');
      }, bind: (_) async {
        events.add('bind');
        throw StateError('fixture');
      });
      await expectLater(binding.persist(_task), throwsStateError);
      await expectLater(binding.persist(_task), throwsStateError);
      expect(events, failAt == 'persist' ? ['persist'] : ['persist', 'bind']);
    });
  }
  test('session resources and snapshot precede the awaited app_closed ACK',
      () async {
    final events = <String>[];
    final resources = _resources(events);
    final ack = Completer<void>();
    final finalizer = candidate.P6R7CandidateWitnessFinalizer(
        closeResources: resources.close,
        readReceipt: () {
          events.add('receipt');
          return _receipt();
        },
        recordClosed: (_) async {
          events.add('app_closed');
          await ack.future;
        });
    final closing = finalizer.close();
    var done = false;
    unawaited(closing.then((_) => done = true));
    await Future<void>.delayed(Duration.zero);
    expect(events, ['drain', 'store', 'dio', 'receipt', 'app_closed']);
    expect(done, isFalse);
    ack.complete();
    expect((await closing).closed, isTrue);
    expect((await finalizer.close()).closed, isTrue);
    expect(events.length, 5);
  });
  for (final failAt in ['store', 'receipt', 'ack']) {
    test('close $failAt unknown remains sticky with no repeated app_closed',
        () async {
      final events = <String>[];
      final resources = _resources(events, fail: failAt == 'store');
      final finalizer = candidate.P6R7CandidateWitnessFinalizer(
          closeResources: resources.close,
          readReceipt: () {
            events.add('receipt');
            if (failAt == 'receipt') throw StateError('fixture');
            return _receipt();
          },
          recordClosed: (_) async {
            events.add('app_closed');
            throw StateError('fixture');
          });
      expect((await finalizer.close()).closed, isFalse);
      final first = List<String>.of(events);
      expect((await finalizer.close()).closed, isFalse);
      expect(events, first);
      expect(events.contains('app_closed'), failAt == 'ack');
    });
  }
  for (final drift in [
    'pid',
    'reason',
    'snapshot',
    'digest',
    'missing',
    'runtime',
    'schema'
  ]) {
    test('closed receipt rejects $drift drift', () {
      final value = _closed();
      final result = value['result'] as Map<String, Object?>;
      switch (drift) {
        case 'pid':
          value['pid'] = 124;
        case 'reason':
          value['shutdown_reason'] = 'stdin_end';
        case 'snapshot':
          (value['snapshot'] as Map<String, dynamic>)['ready'] = true;
        case 'digest':
          (result['witness_close']
              as Map<String, Object?>)['host_closed_sha256'] = 'b' * 64;
        case 'missing':
          result.remove('witness_close');
        case 'runtime':
          result['runtime_closed'] = false;
        case 'schema':
          value['schema'] = 'other';
      }
      expect(() => _receipt(value), throwsFormatException);
    });
  }
}
