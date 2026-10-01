import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_recovery_identity.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_recovery_witness_client.dart';
import 'package:memex/p6_r7_candidate_main.dart' as candidate;

final _hash = 'a' * 64;
final _epoch = 'b' * 64;
const _dataset = 'b6ea393e-81ae-41b9-89c8-1c7cc7743b5a';
const _recovery = 'c6ea393e-81ae-41b9-89c8-1c7cc7743b5a';
const _task = 'd6ea393e-81ae-41b9-89c8-1c7cc7743b5a';
const _image =
    r'D:\memex\tmp\p6-r7-review\owned-recovery-witness-02\OwnedRecoveryWitness.exe';
final _rejected = throwsA(isA<FormatException>()
    .having((e) => e.message, 'fixed error', 'candidate_witness_rejected'));
Map<String, String> _environment(P6R7WitnessRole role) => {
      'P6_R7_WITNESS_PIPE': 'p6-r7-recovery-$_epoch-${role.name}',
      'P6_R7_WITNESS_EPOCH': _epoch,
      'P6_R7_WITNESS_PID': '4567',
      'P6_R7_WITNESS_CREATION': '134337725620243534',
      'P6_R7_WITNESS_IMAGE': _image,
      'P6_R7_WITNESS_SHA256': _hash,
      'P6_R7_WITNESS_ROLE': role.name,
      'P6_R7_WITNESS_PARENT_PID': '3456',
    };
P6R7RecoveryWitnessConfiguration _config(
        [P6R7WitnessRole role = P6R7WitnessRole.successor]) =>
    P6R7RecoveryWitnessConfiguration.fromEnvironment(_environment(role),
        trustedImage: _image, trustedSha256: _hash, expectedRole: role);
Future<P6R7RecoveryPermit> _claim(P6R7RecoveryWitnessClient client) =>
    client.claim(
        datasetId: _dataset,
        datasetIdentityHash: _hash,
        recoveryId: _recovery,
        successorBootSha256: _hash,
        challenge: _hash);

void main() {
  test(
      'Node discovery preserves server parent and never grants successor node role',
      () async {
    final io = _FakeIo();
    final app = await P6R7RecoveryWitnessClient.connectForTesting(
        _config(P6R7WitnessRole.app), io);
    final env = await app.nodeEnvironment();
    expect(env['P6_R7_WITNESS_PIPE'], 'p6-r7-recovery-$_epoch-node');
    expect(env['P6_R7_WITNESS_ROLE'], 'node');
    expect(env['P6_R7_WITNESS_PARENT_PID'], '3456');
    await app.close();
    final successor =
        await P6R7RecoveryWitnessClient.connectForTesting(_config(), _FakeIo());
    await expectLater(successor.nodeEnvironment(), _rejected);
    await successor.close();
  });
  for (final behavior in [
    'success',
    'mismatch',
    'eof',
    'already_consumed',
    'timeout',
    'spawn_failed',
    'open_failed'
  ]) {
    test(
        'recovery wiring $behavior preserves zero pre-consume writes and one attempt',
        () async {
      final marker = <String, Object>{
        'schema': 'p6_r7_candidate_dataset_v1',
        'dataset_id': _dataset,
        'directory': r'D:\fixture\run-candidate',
        'database': 'candidate.sqlite',
        'admission_sha256': _hash,
        'source_closure_sha256': _hash,
        'native_sha256': _hash
      };
      final identityHash =
          sha256.convert(utf8.encode(jsonEncode(marker))).toString();
      final inspection = P6R7RecoveryInspection.inspect(
          markerBytes: utf8.encode(jsonEncode(marker)),
          trustedOrigin: P6R7TrustedOrigin(
              identityHash: identityHash,
              sourceClosureSha256: _hash,
              nativeSha256: _hash,
              canonicalDirectory: r'D:\fixture\run-candidate',
              datasetId: _dataset),
          projection: P6R7ReadOnlyProjection(userVersion: 60, identityRows: [
            {'identity_hash': identityHash, 'task_id': null}
          ], taskRows: []));
      final io = _FakeIo()..consumeBehavior = behavior;
      io.alterReply = (reply) {
        if (reply['type'] == 'permit') {
          reply['dataset_identity_hash'] =
              behavior == 'mismatch' ? _hash : identityHash;
        }
        return jsonEncode(reply);
      };
      final client = await P6R7RecoveryWitnessClient.connectForTesting(
          _config(), io,
          timeout: const Duration(milliseconds: 20));
      final events = <String>[];
      final gate = candidate.P6R7CandidateRecoveryStart<String>(
          witness: client,
          inspection: inspection,
          recoveryId: _recovery,
          bootSha256: _hash,
          challenge: _hash,
          spawn: () async {
            expect(io.commands.last['type'], 'consume');
            events.add('spawn');
            if (behavior == 'spawn_failed') throw StateError('fixture');
          },
          openAfterSpawn: (origin) async {
            expect(identical(origin, inspection), isTrue);
            events.add('open');
            if (behavior == 'open_failed') throw StateError('fixture');
            return 'ready';
          });
      final first = gate.run(), second = gate.run();
      expect(identical(first, second), isTrue);
      if (behavior == 'success') {
        expect(await first, 'ready');
      } else {
        await expectLater(first, throwsA(isA<Object>()));
      }
      expect(
          events,
          behavior == 'success' || behavior == 'open_failed'
              ? ['spawn', 'open']
              : behavior == 'spawn_failed'
                  ? ['spawn']
                  : <String>[]);
      expect(io.commands.where((frame) => frame['type'] == 'claim').length, 1);
      expect(io.commands.where((frame) => frame['type'] == 'consume').length,
          behavior == 'mismatch' ? 0 : 1);
      await client.close();
    });
  }
  test('production witness pins cannot be replaced by discovery environment',
      () {
    expect(
        () => P6R7RecoveryWitnessConfiguration.fromEnvironment(
            _environment(P6R7WitnessRole.app),
            expectedRole: P6R7WitnessRole.app),
        _rejected);
    expect(
        () => P6R7RecoveryWitnessClient.connectWindows(_config()), _rejected);
  });
  test('live child captures creation and retains the same handle through ACK',
      () async {
    final io = _ChildIo();
    final identity = await P6R7LiveChildIdentity.captureForTesting(
        io, 700, 600, Completer<int>().future);
    expect(identity.pid, 700);
    expect(identity.parentPid, 600);
    expect(identity.creation, '134337725620243534');
    await identity.verifyLive();
    expect(io.captures, 1);
    await identity.close();
    await identity.close();
    expect(io.closes, 1);
    await expectLater(identity.verifyLive(), _rejected);
  });
  for (final mismatch in [
    'pid',
    'parent',
    'creation',
    'older',
    'image',
    'hash',
    'dead',
    'handle'
  ]) {
    test('live child rejects $mismatch without process control', () async {
      final io = _ChildIo()..mismatch = mismatch;
      await expectLater(
          P6R7LiveChildIdentity.captureForTesting(
              io, 700, 600, Completer<int>().future),
          _rejected);
      expect(io.captures, 1);
      expect(io.closes, 1);
    });
  }
  test('child creation drift stays failed even if next observation recovers',
      () async {
    final io = _ChildIo();
    final identity = await P6R7LiveChildIdentity.captureForTesting(
        io, 700, 600, Completer<int>().future);
    io.mismatch = 'drift';
    await expectLater(identity.verifyLive(), _rejected);
    io.mismatch = '';
    await expectLater(identity.verifyLive(), _rejected);
    await identity.close();
  });
  test('original Process exit defeats a still-live replacement PID', () async {
    final io = _ChildIo();
    final exit = Completer<int>();
    final identity = await P6R7LiveChildIdentity.captureForTesting(
        io, 700, 600, exit.future);
    exit.complete(0);
    await Future<void>.delayed(Duration.zero);
    await expectLater(identity.verifyLive(), _rejected);
    await identity.close();
  });
  test('exit observed during capture rejects even matching kernel fields',
      () async {
    final io = _ChildIo();
    await expectLater(
        P6R7LiveChildIdentity.captureForTesting(
            io, 700, 600, Future<int>.value(0)),
        _rejected);
    expect(io.closes, 1);
  });
  test('unknown original Process exit also rejects live capture', () async {
    final io = _ChildIo();
    await expectLater(
        P6R7LiveChildIdentity.captureForTesting(
            io, 700, 600, Future<int>.error(StateError('fixture'))),
        _rejected);
    expect(io.closes, 1);
  });
  testWidgets('business command queues behind an already active keepalive',
      (tester) async {
    final gate = Completer<void>();
    final io = _FakeIo()..readGate = gate;
    final client =
        await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
    client.startKeepAlive();
    await tester.pump(const Duration(seconds: 31));
    final claim = _claim(client);
    await tester.pump();
    expect(io.commands.map((c) => c['type']), ['ping']);
    gate.complete();
    await tester.pump();
    await claim;
    expect(io.commands.map((c) => c['type']), ['ping', 'claim']);
    expect(io.commands.map((c) => c['sequence']), [1, 2]);
    expect(client.frozen, isFalse);
    await client.close();
  });
  test('hash and epoch pins reject a trailing newline', () {
    final env = _environment(P6R7WitnessRole.successor);
    env['P6_R7_WITNESS_EPOCH'] = '$_epoch\n';
    env['P6_R7_WITNESS_PIPE'] = 'p6-r7-recovery-$_epoch\n-successor';
    expect(
        () => P6R7RecoveryWitnessConfiguration.fromEnvironment(env,
            trustedImage: _image,
            trustedSha256: _hash,
            expectedRole: P6R7WitnessRole.successor),
        _rejected);
  });

  testWidgets(
      'optional keepalive stops before terminal consume and needs no live pipe after ACK',
      (tester) async {
    final io = _FakeIo();
    final client =
        await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
    client.startKeepAlive();
    await tester.pump(const Duration(seconds: 31));
    expect(io.commands.single['type'], 'ping');
    final permit = await _claim(client);
    var spawns = 0;
    await client.spawnSuccessorOnce(permit, () async {
      spawns++;
    });
    await tester.pump(const Duration(seconds: 90));
    expect(spawns, 1);
    expect(io.commands.map((c) => c['type']), ['ping', 'claim', 'consume']);
    await client.close();
  });
  test(
      'discovery cannot replace trusted image or hash; role and pipe bind epoch',
      () {
    for (final key in [
      'IMAGE',
      'SHA256',
      'ROLE',
      'PIPE',
      'PID',
      'CREATION',
      'EPOCH'
    ]) {
      final env = _environment(P6R7WitnessRole.successor);
      env['P6_R7_WITNESS_$key'] = key == 'PID' ? '04567' : 'untrusted';
      expect(
          () => P6R7RecoveryWitnessConfiguration.fromEnvironment(env,
              trustedImage: _image,
              trustedSha256: _hash,
              expectedRole: P6R7WitnessRole.successor),
          _rejected);
    }
  });

  test('fresh App connection does not invent a register_app command', () async {
    final io = _FakeIo();
    final client = await P6R7RecoveryWitnessClient.connectForTesting(
        _config(P6R7WitnessRole.app), io);
    expect(io.commands, isEmpty);
    await client.registerNode(
        nodePid: 7654, nodeCreation: '134337725620243535');
    await client.bindOrigin(
        datasetId: _dataset,
        dataDirectory: 'D:\\memex\\tmp\\p6-r7-app-data\\run-$_dataset',
        datasetIdentityHash: _hash,
        launchId: _recovery,
        admissionSha256: _hash,
        scopeHash: _hash);
    await client.bindTask(taskId: _task, scopeHash: _hash);
    await client.appClosed(
        nodeExitCode: 0,
        stdoutEof: true,
        stderrEof: true,
        stdinClosed: true,
        storeClosed: true,
        clientClosed: true,
        taskId: _task,
        scopeHash: _hash,
        hostClosedSha256: _hash,
        ownerManifestSha256: _hash);
    expect(io.commands.map((e) => e['type']),
        ['register_node', 'bind_origin', 'bind_task', 'app_closed']);
    expect(io.commands.map((e) => e['sequence']), [1, 2, 3, 4]);
    expect(
        io.commands.every((e) =>
            e['schema'] == 'p6_r7_owned_recovery_command_v1' &&
            e['epoch'] == _epoch),
        isTrue);
    expect(io.commands.first['node_creation'], '134337725620243535');
    await client.close();
  });

  test('unknown app close proof never sends a close frame', () async {
    final io = _FakeIo();
    final client = await P6R7RecoveryWitnessClient.connectForTesting(
        _config(P6R7WitnessRole.app), io);
    await expectLater(
        client.appClosed(
            nodeExitCode: 0,
            stdoutEof: true,
            stderrEof: false,
            stdinClosed: true,
            storeClosed: true,
            clientClosed: true,
            taskId: null,
            scopeHash: _hash,
            hostClosedSha256: _hash,
            ownerManifestSha256: _hash),
        _rejected);
    expect(io.commands, isEmpty);
    await client.close();
  });

  for (final mismatch in [
    'pipe_pid',
    'process_pid',
    'creation',
    'image',
    'hash',
    'dead',
    'handle'
  ]) {
    test('rejects initial server identity $mismatch before any bytes are sent',
        () async {
      final io = _FakeIo()..mismatch = mismatch;
      await expectLater(
          P6R7RecoveryWitnessClient.connectForTesting(_config(), io),
          _rejected);
      expect(io.commands, isEmpty);
      expect(io.closed, isTrue);
    });
  }

  test(
      'fragmented 4LE frames consume once and concurrent calls execute one callback',
      () async {
    final io = _FakeIo()..chunk = 3;
    final client =
        await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
    final permit = await _claim(client);
    expect(permit.datasetId, _dataset);
    final done = Completer<void>();
    var spawns = 0;
    final first = client.spawnSuccessorOnce(permit, () {
      spawns++;
      return done.future;
    });
    final second = client.spawnSuccessorOnce(permit, () async {
      spawns += 100;
    });
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(spawns, 1);
    done.complete();
    await first;
    await second;
    await client.spawnSuccessorOnce(permit, () async {
      spawns++;
    });
    expect(spawns, 1);
    expect(io.commands.map((e) => e['type']), ['claim', 'consume']);
    expect(io.commands.map((e) => e['sequence']), [1, 2]);
    await client.close();
  });

  test('spawn callback failure cannot retry consume or a second spawn',
      () async {
    final io = _FakeIo();
    final client =
        await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
    final permit = await _claim(client);
    var spawns = 0;
    await expectLater(
        client.spawnSuccessorOnce(permit, () async {
          spawns++;
          throw StateError('private fixture');
        }),
        _rejected);
    await expectLater(
        client.spawnSuccessorOnce(permit, () async {
          spawns++;
        }),
        _rejected);
    expect(spawns, 1);
    expect(io.commands.length, 2);
    expect(client.frozen, isTrue);
  });

  for (final behavior in ['already_consumed', 'eof', 'timeout']) {
    test('consume $behavior cannot grant or retry a spawn', () async {
      final io = _FakeIo()..consumeBehavior = behavior;
      final client = await P6R7RecoveryWitnessClient.connectForTesting(
          _config(), io,
          timeout: const Duration(milliseconds: 100));
      final permit = await _claim(client);
      var spawns = 0;
      await expectLater(
          client.spawnSuccessorOnce(permit, () async {
            spawns++;
          }),
          _rejected);
      await expectLater(
          client.spawnSuccessorOnce(permit, () async {
            spawns++;
          }),
          _rejected);
      expect(spawns, 0);
      expect(io.commands.length, 2);
      expect(io.closed, isTrue);
    });
  }

  test('original server death after consume ACK prevents callback', () async {
    final io = _FakeIo()..dieAtObservation = 6;
    final client =
        await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
    final permit = await _claim(client);
    var spawns = 0;
    await expectLater(
        client.spawnSuccessorOnce(permit, () async {
          spawns++;
        }),
        _rejected);
    expect(spawns, 0);
    expect(io.commands.length, 2);
  });

  for (final field in [
    'dataset_id',
    'dataset_identity_hash',
    'generation',
    'next_generation',
    'recovery_id',
    'successor_boot_sha256',
    'challenge',
    'permit_id',
    'sequence',
    'epoch',
    'state',
    'extra'
  ]) {
    test('permit rejects wrong binding or response shape: $field', () async {
      final io = _FakeIo()
        ..alterReply = (reply) {
          reply[field] = field == 'sequence' ? 1.0 : 'incorrect';
          return jsonEncode(reply);
        };
      final client =
          await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
      await expectLater(_claim(client), _rejected);
      await expectLater(_claim(client), _rejected);
      expect(io.commands.length, 1);
      expect(client.frozen, isTrue);
    });
  }

  for (final malformed in [
    'duplicate',
    'escaped_duplicate',
    'trailing',
    'deep',
    'utf8',
    'bom',
    'oversize',
    'zero',
    'reject'
  ]) {
    test('strict frame/parser rejects $malformed and freezes', () async {
      final io = _FakeIo()..malformed = malformed;
      final client =
          await P6R7RecoveryWitnessClient.connectForTesting(_config(), io);
      await expectLater(_claim(client), _rejected);
      expect(client.frozen, isTrue);
      expect(io.closed, isTrue);
    });
  }
}

class _ChildIo implements P6R7WitnessChildIo {
  int captures = 0, closes = 0;
  String mismatch = '';
  @override
  Future<void> capture(int pid, int parentPid, Duration timeout) async {
    captures++;
  }

  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<P6R7WitnessChildObservation> observe(Duration timeout) async =>
      P6R7WitnessChildObservation(
          pid: mismatch == 'pid' ? 701 : 700,
          parentPid: mismatch == 'parent' ? 601 : 600,
          creation: mismatch == 'creation'
              ? '0001'
              : mismatch == 'drift'
                  ? '134337725620243535'
                  : '134337725620243534',
          parentCreation:
              mismatch == 'older' ? '134337725620243536' : '134337725620243000',
          image: mismatch == 'image'
              ? r'D:\elsewhere\node.exe'
              : p6R7WitnessNodeImage,
          imageSha256: mismatch == 'hash' ? _hash : p6R7WitnessNodeSha256,
          alive: mismatch != 'dead',
          originalHandleHeld: mismatch != 'handle');
}

class _FakeIo implements P6R7WitnessIo {
  late P6R7RecoveryWitnessConfiguration config;
  final commands = <Map<String, dynamic>>[];
  final sent = <int>[], incoming = <int>[];
  int chunk = 100000, observations = 0, dieAtObservation = 0;
  String? mismatch, consumeBehavior, malformed;
  String Function(Map<String, dynamic>)? alterReply;
  bool closed = false, timedRead = false;
  Completer<void>? readGate;
  @override
  Future<void> connect(
      P6R7RecoveryWitnessConfiguration config, Duration timeout) async {
    this.config = config;
  }

  @override
  Future<P6R7WitnessServerObservation> observe(Duration timeout,
      {bool requireConnectedPipe = true}) async {
    observations++;
    return P6R7WitnessServerObservation(
        pipePid: !requireConnectedPipe
            ? null
            : mismatch == 'pipe_pid'
                ? 1
                : config.serverPid,
        processPid: mismatch == 'process_pid' ? 1 : config.serverPid,
        creation: mismatch == 'creation' ? '1' : config.serverCreation,
        image: mismatch == 'image' ? r'D:\wrong.exe' : config.image,
        imageSha256: mismatch == 'hash' ? 'c' * 64 : config.imageSha256,
        alive: mismatch != 'dead' && observations != dieAtObservation,
        originalHandleHeld: mismatch != 'handle');
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    final count = bytes.length < chunk ? bytes.length : chunk;
    sent.addAll(bytes.take(count));
    if (sent.length >= 4) {
      final length =
          ByteData.sublistView(Uint8List.fromList(sent.take(4).toList()))
              .getUint32(0, Endian.little);
      if (sent.length == length + 4) {
        final command =
            jsonDecode(utf8.decode(sent.sublist(4))) as Map<String, dynamic>;
        sent.clear();
        commands.add(command);
        _reply(command);
      }
    }
    return count;
  }

  void _reply(Map<String, dynamic> command) {
    final type = command['type'];
    if (type == 'consume' && ['eof', 'timeout'].contains(consumeBehavior)) {
      timedRead = consumeBehavior == 'timeout';
      return;
    }
    final (replyType, state) = switch (type) {
      'ping' => ('alive', 'closed_unclaimed'),
      'register_node' => ('node_registration_pending', 'awaiting_node'),
      'bind_origin' => ('origin_bound', 'live'),
      'bind_task' => ('task_bound', 'live'),
      'app_closed' => ('app_close_recorded', 'awaiting_actual_exits'),
      'claim' => ('permit', 'claimed'),
      'consume' => (
          consumeBehavior == 'already_consumed'
              ? 'already_consumed'
              : 'spawn_once',
          'consumed'
        ),
      _ => throw StateError('unknown fixture command'),
    };
    final reply = <String, dynamic>{
      'schema': 'p6_r7_owned_recovery_reply_v1',
      'epoch': config.epoch,
      'sequence': command['sequence'],
      'type': replyType,
      'state': state,
      if (type == 'claim') ...{
        'dataset_id': _dataset,
        'dataset_identity_hash': _hash,
        'generation': 1,
        'next_generation': 2,
        'recovery_id': _recovery,
        'successor_boot_sha256': _hash,
        'challenge': _hash,
        'permit_id': 'c' * 64
      }
    };
    var text = alterReply?.call(reply) ?? jsonEncode(reply);
    if (malformed == 'duplicate') {
      text = text.replaceFirst('{', '{"epoch":"$_epoch",');
    }
    if (malformed == 'escaped_duplicate') {
      text = text.replaceFirst('{', '{"\\u0065poch":"$_epoch",');
    }
    if (malformed == 'trailing') text += '{}';
    if (malformed == 'deep') text = '${'[' * 14}0${']' * 14}';
    if (malformed == 'reject') {
      text = jsonEncode({
        'schema': 'p6_r7_owned_recovery_reply_v1',
        'epoch': config.epoch,
        'type': 'rejected',
        'state': 'frozen'
      });
    }
    final body = malformed == 'utf8'
        ? [0xff]
        : [
            if (malformed == 'bom') ...[0xef, 0xbb, 0xbf],
            ...utf8.encode(text)
          ];
    final header = ByteData(4)
      ..setUint32(
          0,
          malformed == 'oversize'
              ? 16385
              : malformed == 'zero'
                  ? 0
                  : body.length,
          Endian.little);
    incoming.addAll(header.buffer.asUint8List());
    incoming.addAll(body);
  }

  @override
  Future<List<int>> read(int maximum, Duration timeout) async {
    await readGate?.future;
    if (timedRead) return Completer<List<int>>().future;
    final count =
        [maximum, incoming.length, chunk].reduce((a, b) => a < b ? a : b);
    final result = incoming.take(count).toList();
    incoming.removeRange(0, count);
    return result;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
