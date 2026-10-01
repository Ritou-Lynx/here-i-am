import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_recovery_witness_client.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
      'isolated Win32 pipe ABI verifies process identity, partial frame and EOF',
      () async {
    final directory = Directory(r'D:\memex\tmp\p6-r7-review')
        .createTempSync('witness-client-native-smoke-');
    final image = p.join(directory.path, 'WitnessClientSmoke.exe');
    final source = File(p.join('test', 'data', 'workbench_ai', 'candidate',
            'fixtures', 'WitnessClientSmoke.cs'))
        .absolute;
    final compiled = await Process.run(
            r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
            [
              '/nologo',
              '/platform:x64',
              '/target:exe',
              '/warnaserror+',
              '/reference:System.Web.Extensions.dll',
              '/out:$image',
              source.path
            ],
            runInShell: false)
        .timeout(const Duration(seconds: 20));
    expect(compiled.exitCode, 0, reason: 'synthetic fixture compile exit');
    final digest = sha256.convert(File(image).readAsBytesSync()).toString();
    final random = Random.secure();
    final epoch = List.generate(
            32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final server =
        await Process.start(image, [epoch, '$pid'], runInShell: false);
    final lines = StreamIterator(
        server.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    final errors = server.stderr.drain<void>();
    P6R7RecoveryWitnessClient? client;
    try {
      expect(
          await lines.moveNext().timeout(const Duration(seconds: 10)), isTrue);
      final ready = jsonDecode(lines.current) as Map<String, dynamic>;
      expect(ready['pid'], server.pid);
      final config = P6R7RecoveryWitnessConfiguration.fromEnvironment({
        'P6_R7_WITNESS_PIPE': 'p6-r7-recovery-$epoch-app',
        'P6_R7_WITNESS_EPOCH': epoch,
        'P6_R7_WITNESS_PID': '${server.pid}',
        'P6_R7_WITNESS_CREATION': ready['creation'] as String,
        'P6_R7_WITNESS_IMAGE': image,
        'P6_R7_WITNESS_SHA256': digest,
        'P6_R7_WITNESS_ROLE': 'app',
      },
          trustedImage: image,
          trustedSha256: digest,
          expectedRole: P6R7WitnessRole.app);
      final diagnosticIo = _DiagnosticIo(p6R7WindowsWitnessIoForTesting());
      client = await P6R7RecoveryWitnessClient.connectForTesting(
          config, diagnosticIo,
          timeout: const Duration(seconds: 8));
      try {
        await client.ping();
      } on Object {
        final diagnostic =
            await lines.moveNext().timeout(const Duration(seconds: 27));
        fail(
            '${diagnosticIo.phase}/${diagnosticIo.lastReadLength}: ${diagnostic ? lines.current : 'synthetic_fixture_no_result'}');
      }
      expect(client.frozen, isFalse);
      await expectLater(client.ping(), throwsA(isA<FormatException>()));
      expect(client.frozen, isTrue);
      expect(
          await lines.moveNext().timeout(const Duration(seconds: 5)), isTrue);
      expect(jsonDecode(lines.current), {
        'client_pid_verified': true,
        'partial_frame_written': true,
        'eof_emitted': true
      });
      expect(await server.exitCode.timeout(const Duration(seconds: 5)), 0);
      await errors;
      File(p.join(directory.path, 'actual.json')).writeAsStringSync(jsonEncode({
        'schema': 'p6_r7_dart_witness_native_smoke_v1',
        'synthetic': true,
        'fixture_sha256': digest,
        'source_sha256': sha256.convert(source.readAsBytesSync()).toString(),
        'server_pid': server.pid,
        'server_creation': ready['creation'],
        'server_actual_exit_code': 0,
        'client_pid_verified': true,
        'partial_frame_verified': true,
        'eof_rejected': true,
        'real_app': false,
        'real_host': false,
        'real_native_executor': false,
      }));
    } finally {
      await client?.close();
      await lines.cancel();
      await server.stdin.close();
      // The fixture has its own deadline. No kill or arbitrary process lookup.
      await server.exitCode.timeout(const Duration(seconds: 28));
    }
  }, skip: !Platform.isWindows);

  test('live original synthetic Node child validates Toolhelp parent and exit',
      () async {
    final child = await Process.start(
        p6R7WitnessNodeImage,
        [
          '-e',
          "const timer=setTimeout(()=>process.exit(0),15000);process.stdin.resume();process.stdin.on('end',()=>clearTimeout(timer));"
        ],
        runInShell: false,
        environment: {
          for (final entry in Platform.environment.entries)
            if (!entry.key.toUpperCase().startsWith('P6_R7_WITNESS_') &&
                !{'NODE_OPTIONS', 'NODE_PATH'}
                    .contains(entry.key.toUpperCase()))
              entry.key: entry.value,
        },
        includeParentEnvironment: false);
    final out = child.stdout.drain<void>(), err = child.stderr.drain<void>();
    P6R7LiveChildIdentity? identity;
    try {
      identity = await P6R7LiveChildIdentity.captureLiveChildIdentity(child);
      expect(identity.pid, child.pid);
      expect(identity.parentPid, pid);
      expect(BigInt.parse(identity.creation) > BigInt.zero, isTrue);
      await identity.verifyLive();
      await child.stdin.close();
      expect(await child.exitCode.timeout(const Duration(seconds: 18)), 0);
      await Future.wait([out, err]);
      await expectLater(identity.verifyLive(), throwsA(isA<FormatException>()));
    } finally {
      await identity?.close();
      await child.stdin.close();
      await child.exitCode.timeout(const Duration(seconds: 18));
    }
  }, skip: !Platform.isWindows);
}

class _DiagnosticIo implements P6R7WitnessIo {
  _DiagnosticIo(this.delegate);
  final P6R7WitnessIo delegate;
  String phase = 'initial';
  int lastReadLength = -1;
  @override
  Future<void> connect(
          P6R7RecoveryWitnessConfiguration config, Duration timeout) =>
      delegate.connect(config, timeout);
  @override
  Future<P6R7WitnessServerObservation> observe(Duration timeout,
      {bool requireConnectedPipe = true}) async {
    phase = 'observe';
    return delegate.observe(timeout,
        requireConnectedPipe: requireConnectedPipe);
  }

  @override
  Future<List<int>> read(int maximum, Duration timeout) async {
    phase = 'read_enter';
    final value = await delegate.read(maximum, timeout);
    phase = 'read_return';
    lastReadLength = value.length;
    return value;
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    phase = 'write';
    return delegate.write(bytes, timeout);
  }

  @override
  Future<void> close() => delegate.close();
}
