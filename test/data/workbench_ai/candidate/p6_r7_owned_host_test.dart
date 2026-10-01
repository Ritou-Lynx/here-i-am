import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_candidate_config.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_owned_host.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
      'waits for actual exit and both pipe EOFs; drains without retaining text',
      () async {
    final process = _Process();
    final owner = P6R7OwnedHost.forTesting(process);
    final closing = owner.close();
    var completed = false;
    unawaited(closing.then((_) => completed = true));
    process.out.add(utf8.encode('discard stdout'));
    process.err.add(utf8.encode('discard stderr'));
    await _tick();
    expect(process.received, ['shutdown\n']);
    process.exit.complete(0);
    await process.out.close();
    await _tick();
    expect(completed, isFalse);
    expect(process.inputClosed, isFalse);
    await process.err.close();
    expect(await closing, isTrue);
    expect(process.inputClosed, isTrue);
    expect(await owner.close(), isTrue);
    expect(process.received, ['shutdown\n']);
  });

  test('nonzero exit never becomes confirmed or closes stdin', () async {
    final process = _Process();
    final owner = P6R7OwnedHost.forTesting(process);
    await process.finish(4);
    expect(await owner.close(), isFalse);
    expect(await owner.close(), isFalse);
    expect(process.received, isEmpty);
    expect(process.inputClosed, isFalse);
    await process.stdin.close();
  });

  test('timeout retains the same pipe and a later retry can confirm exit',
      () async {
    final process = _Process();
    final owner = P6R7OwnedHost.forTesting(process);
    expect(
        await owner.close(timeout: const Duration(milliseconds: 10)), isFalse);
    expect(process.inputClosed, isFalse);
    final retry = owner.close();
    await _tick();
    expect(process.received, ['shutdown\n', 'shutdown\n']);
    await process.finish(0);
    expect(await retry, isTrue);
  });

  test('concurrent close shares one attempt and emits only one command',
      () async {
    final process = _Process();
    final owner = P6R7OwnedHost.forTesting(process);
    final first = owner.close();
    final second = owner.close();
    expect(identical(first, second), isTrue);
    await _tick();
    expect(process.received, ['shutdown\n']);
    await process.finish(0);
    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  test('pipe stream error is handled but never counted as EOF success',
      () async {
    final process = _Process();
    final owner = P6R7OwnedHost.forTesting(process);
    process.err.addError(StateError('private raw error'));
    await process.finish(0);
    expect(await owner.close(), isFalse);
    expect(process.inputClosed, isFalse);
    await process.stdin.close();
  });

  test('owner with no started process can close without spawning', () async {
    expect(await P6R7OwnedHost().close(), isTrue);
  });

  test(
      'close during pending spawn retains its future and shuts down that process',
      () async {
    final spawned = Completer<Process>();
    final owner = P6R7OwnedHost.startingForTesting(spawned.future);
    final process = _Process();
    final first = owner.close();
    final second = owner.close();
    var resolved = false;
    unawaited(first.then((_) => resolved = true));
    await _tick();
    expect(resolved, isFalse);
    expect(process.received, isEmpty);
    expect(identical(first, second), isTrue);
    spawned.complete(process);
    await _tick();
    expect(process.received, ['shutdown\n']);
    expect(resolved, isFalse);
    await process.finish(0);
    expect(await first, isTrue);
  });

  test('failed stdin write is unconfirmed and never kills the process',
      () async {
    final process = _Process();
    final owner = P6R7OwnedHost.forTesting(process);
    await process.stdin.close();
    expect(await owner.close(), isFalse);
    expect(process.exit.isCompleted, isFalse);
    await process.finish(4);
    expect(await owner.close(), isFalse);
  });

  group('closed boot surface', () {
    late Directory sandbox;
    late Directory root;
    late Directory folder;
    late Directory dataRoot;
    late File config;
    late Map<String, dynamic> document;
    const run = 'run-123e4567-e89b-42d3-a456-426614174000';

    setUp(() {
      sandbox = Directory.systemTemp.createTempSync('p6-owned-host-test-');
      root = Directory(p.join(sandbox.path, 'hosts'))..createSync();
      folder = Directory(p.join(root.path, 'app-lifecycle-owned-01'))
        ..createSync();
      dataRoot = Directory(p.join(sandbox.path, 'p6-r7-app-data'))
        ..createSync();
      final pins = <String, String>{};
      for (final name in [
        'launch.mjs',
        'launcher-config.json',
        'closure.json'
      ]) {
        final file = File(p.join(folder.path, name))..writeAsStringSync('{}');
        pins[name] = _hash(file);
      }
      document = {
        'schema': 'p6_r7_owned_host_v1',
        'node_path': r'D:\Nodejs\node.exe',
        'node_sha256':
            '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f',
        'folder': folder.path,
        'pins': pins,
      };
      config = File(p.join(folder.path, 'owned-host-config.json'))
        ..writeAsStringSync(jsonEncode(document));
    });
    tearDown(() => sandbox.deleteSync(recursive: true));

    List<String> args() => [
          '--p6-r7-owned-host-candidate',
          '--host-config',
          config.path,
          '--host-config-sha256',
          _hash(config),
          '--data-dir',
          p.join(dataRoot.path, run),
          '--mode',
          'fresh'
        ];
    P6R7OwnedHostConfiguration parse([List<String>? input]) =>
        P6R7OwnedHostConfiguration.parse(input ?? args(),
            enableToken: p6R7CandidateEnableToken,
            candidateRoot: dataRoot.path,
            hostRoot: root.path);

    test('accepts fixed configuration and rechecks pins before any spawn', () {
      final boot = parse();
      boot.verifyBeforeStart();
      expect(boot.closureSha256, (document['pins'] as Map)['closure.json']);
      File(p.join(folder.path, 'launch.mjs')).writeAsStringSync('changed');
      expect(boot.verifyBeforeStart, throwsFormatException);
    }, skip: !Platform.isWindows);

    test('config byte drift is rejected before spawn', () {
      final input = args();
      config.writeAsStringSync('${config.readAsStringSync()} ');
      expect(() => parse(input), throwsFormatException);
    });

    test('each pinned input drift is rejected without spawning a process', () {
      for (final name in [
        'launch.mjs',
        'launcher-config.json',
        'closure.json'
      ]) {
        final file = File(p.join(folder.path, name));
        file.writeAsStringSync('changed');
        expect(() => parse(), throwsFormatException);
        file.writeAsStringSync('{}');
      }
    });

    test('spawn repeats pin checks and failed spawn retains safe close',
        () async {
      final boot = parse();
      File(p.join(folder.path, 'launch.mjs')).writeAsStringSync('changed');
      final owner = P6R7OwnedHost();
      await expectLater(owner.start(boot), throwsFormatException);
      expect(await owner.close(), isTrue);
    }, skip: !Platform.isWindows);

    test('a closed startup owner cannot later spawn a process', () async {
      final boot = parse();
      final owner = P6R7OwnedHost();
      expect(await owner.close(), isTrue);
      await expectLater(owner.start(boot), throwsFormatException);
      expect(await owner.close(), isTrue);
    }, skip: !Platform.isWindows);

    test(
        'close interrupts admission wait immediately and requests same-host shutdown',
        () async {
      final boot = parse();
      File(boot.admissionPath).createSync();
      final process = _Process();
      final owner = P6R7OwnedHost.forTesting(process);
      final admission =
          owner.waitForAdmission(boot, timeout: const Duration(hours: 1));
      final rejected = expectLater(admission, throwsFormatException);
      final closing = owner.close();
      await rejected.timeout(const Duration(seconds: 1));
      await _tick();
      expect(process.received, ['shutdown\n']);
      expect(process.inputClosed, isFalse);
      await process.finish(0);
      expect(await closing, isTrue);
    }, skip: !Platform.isWindows);

    test(
        'empty launcher claim waits for a complete admission and returns only an unverified config',
        () async {
      final boot = parse();
      final file = File(boot.admissionPath)..createSync();
      final process = _Process();
      final owner = P6R7OwnedHost.forTesting(process);
      final waiting = owner.waitForAdmission(boot);
      var completed = false;
      unawaited(waiting.then((_) => completed = true));
      await _tick();
      expect(completed, isFalse);

      file.writeAsStringSync(jsonEncode({
        'schema': 'p6_r7_app_candidate_admission_v1',
        'launch_id': '123e4567-e89b-42d3-a456-426614174000',
        'base_uri': 'http://127.0.0.1:52341',
        'profile': p6R7CandidateProfile,
        'source_closure_sha256': boot.closureSha256,
        'native_sha256': p6R7NativeHash,
        'admission_token': 'b' * 64,
      }));
      final ready = await waiting;
      // Admission publication alone cannot attest a host or open candidate DB.
      expect(ready.liveHostVerified, isFalse);
      await process.finish(0);
      expect(await owner.close(), isTrue);
    }, skip: !Platform.isWindows);

    test('empty launcher claim reaches the supplied admission deadline', () async {
      final boot = parse();
      File(boot.admissionPath).createSync();
      final process = _Process();
      final owner = P6R7OwnedHost.forTesting(process);
      await expectLater(
          owner.waitForAdmission(boot,
              timeout: const Duration(milliseconds: 1)),
          throwsFormatException);
      expect(process.received, isEmpty);
      await process.finish(4);
      expect(await owner.close(), isFalse);
    }, skip: !Platform.isWindows);

    test('a directory cannot stand in for an unpublished admission', () async {
      final boot = parse();
      Directory(boot.admissionPath).createSync();
      final process = _Process();
      final owner = P6R7OwnedHost.forTesting(process);
      await expectLater(owner.waitForAdmission(boot), throwsFormatException);
      expect(process.received, isEmpty);
      await process.finish(4);
      expect(await owner.close(), isFalse);
    }, skip: !Platform.isWindows);

    test('nonempty malformed admission remains an immediate rejection', () async {
      final boot = parse();
      File(boot.admissionPath).writeAsStringSync('{');
      final process = _Process();
      final owner = P6R7OwnedHost.forTesting(process);
      await expectLater(owner.waitForAdmission(boot), throwsFormatException);
      expect(process.received, isEmpty);
      await process.finish(4);
      expect(await owner.close(), isFalse);
    }, skip: !Platform.isWindows);

    test('admission must bind the pinned closure; no network or real host',
        () async {
      final boot = parse();
      final process = _Process();
      final owner = P6R7OwnedHost.forTesting(process);
      await expectLater(
          owner.waitForAdmission(boot,
              timeout: const Duration(milliseconds: 1)),
          throwsFormatException);
      final admission = <String, dynamic>{
        'schema': 'p6_r7_app_candidate_admission_v1',
        'launch_id': '123e4567-e89b-42d3-a456-426614174000',
        'base_uri': 'http://127.0.0.1:52341',
        'profile': p6R7CandidateProfile,
        'source_closure_sha256': 'a' * 64,
        'native_sha256': p6R7NativeHash,
        'admission_token': 'b' * 64,
      };
      final file = File(boot.admissionPath)
        ..writeAsStringSync(jsonEncode(admission));
      expect(boot.readAdmission, throwsFormatException);
      admission['source_closure_sha256'] = boot.closureSha256;
      file.writeAsStringSync(jsonEncode(admission));
      final ready = await owner.waitForAdmission(boot);
      expect(ready.sourceClosureSha256, boot.closureSha256);
      expect(ready.liveHostVerified, isFalse);
      await process.finish(0);
      expect(await owner.close(), isTrue);
    }, skip: !Platform.isWindows);

    test('existing admission, closed or event files reject reuse', () {
      for (final name in ['admission.json', 'closed.json', 'events.jsonl']) {
        final file = File(p.join(folder.path, name))..writeAsStringSync('{}');
        expect(() => parse(), throwsFormatException);
        file.deleteSync();
      }
    });

    test(
        'outside data/root, invalid run, and reused fresh data fail before spawn',
        () {
      var input = args();
      input[6] = p.join(sandbox.path, run);
      expect(() => parse(input), throwsFormatException);
      input = args();
      input[6] = p.join(dataRoot.path, 'run-arbitrary');
      expect(() => parse(input), throwsFormatException);
      Directory(p.join(dataRoot.path, run)).createSync();
      expect(() => parse(), throwsFormatException);
      expect(
          () => P6R7OwnedHostConfiguration.parse(args(),
              enableToken: p6R7CandidateEnableToken,
              candidateRoot: dataRoot.path,
              hostRoot: sandbox.path),
          throwsFormatException);
    });

    test('arbitrary node, pin names, extra configuration, and extra CLI reject',
        () {
      for (final change in <void Function(Map<String, dynamic>)>[
        (value) => value['node_path'] = r'C:\other.exe',
        (value) => value['node_sha256'] = 'f' * 64,
        (value) => value['command'] = 'arbitrary',
        (value) => value['pins'] = {'../outside.js': 'f' * 64},
      ]) {
        final changed = Map<String, dynamic>.of(document);
        change(changed);
        config.writeAsStringSync(jsonEncode(changed));
        expect(() => parse(), throwsFormatException);
      }
      config.writeAsStringSync(jsonEncode(document));
      expect(
          () => parse([...args(), '--shell', 'true']), throwsFormatException);
    });
  });
}

String _hash(File file) => sha256.convert(file.readAsBytesSync()).toString();
Future<void> _tick() => Future<void>.delayed(Duration.zero);

class _Process implements Process {
  _Process() {
    _input.stream.listen((bytes) => received.add(utf8.decode(bytes)),
        onDone: () => inputClosed = true);
    stdin = IOSink(_input.sink);
  }
  final out = StreamController<List<int>>();
  final err = StreamController<List<int>>();
  final exit = Completer<int>();
  final _input = StreamController<List<int>>();
  final received = <String>[];
  bool inputClosed = false;
  @override
  late final IOSink stdin;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Future<int> get exitCode => exit.future;
  @override
  int get pid => 100;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) =>
      throw StateError('kill is forbidden');
  Future<void> finish(int code) async {
    exit.complete(code);
    await out.close();
    await err.close();
    await _tick();
  }
}
