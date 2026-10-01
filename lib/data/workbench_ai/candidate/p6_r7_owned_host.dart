import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'p6_r7_candidate_config.dart';
import 'p6_r7_recovery_identity.dart';
import 'p6_r7_recovery_witness_client.dart';
import '../task_queue/workbench_task_queue_tool_host.dart';

const _nodePath = r'D:\Nodejs\node.exe';
const _nodeHash =
    '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
final _hashPattern = RegExp(r'^[a-f0-9]{64}$');

String p6R7CandidateScopeHash(String datasetId) {
  candidateCheck(
      datasetId.length == 36 && p6R7CandidateUuid.hasMatch(datasetId));
  return sha256
      .convert(utf8.encode(jsonEncode({
        'profile_id': DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
        'scope_type': 'conversation',
        'scope_id': 'p6-r7-candidate-$datasetId',
        'title': p6R7CandidateTitle,
        'goal': p6R7CandidateGoal,
      })))
      .toString();
}

/// No first-generation witness discovery may leak into the successor Node.
/// Only the authenticated client's fixed node fields can be injected afresh.
@visibleForTesting
Map<String, String> p6R7NodeEnvironment(
    Map<String, String> inherited, Map<String, String>? authenticatedNode) {
  final environment = <String, String>{
    for (final entry in inherited.entries)
      if (!entry.key.toUpperCase().startsWith('P6_R7_WITNESS_'))
        entry.key: entry.value,
  };
  candidateCheck(!environment.keys.any((key) =>
      const {'NODE_OPTIONS', 'NODE_PATH'}.contains(key.toUpperCase())));
  if (authenticatedNode != null) environment.addAll(authenticatedNode);
  return environment;
}

/// A closed command surface: the caller can select only a pinned candidate.
class P6R7OwnedHostConfiguration {
  P6R7OwnedHostConfiguration._(this.arguments, this.enableToken,
      this.candidateRoot, this.hostRoot, this.folder, this.closureSha256);

  final List<String> arguments;
  final String enableToken;
  final String candidateRoot;
  final String hostRoot;
  final String folder;
  final String closureSha256;
  String get admissionPath => p.join(folder, 'admission.json');
  String _argument(String name) => arguments[arguments.indexOf(name) + 1];
  String get mode => _argument('--mode');
  String get dataDirectory => _argument('--data-dir');
  String get datasetId => p.basename(dataDirectory).substring(4);
  String get bootSha256 => _argument('--host-config-sha256');

  static P6R7OwnedHostConfiguration parse(List<String> args,
      {required String enableToken,
      required String candidateRoot,
      required String hostRoot}) {
    candidateCheck(kDebugMode && enableToken == p6R7CandidateEnableToken);
    candidateCheck(
        args.length == 9 && args.first == '--p6-r7-owned-host-candidate');
    final values = <String, String>{};
    for (var i = 1; i < args.length; i += 2) {
      candidateCheck(const {
            '--host-config',
            '--host-config-sha256',
            '--data-dir',
            '--mode'
          }.contains(args[i]) &&
          !values.containsKey(args[i]));
      values[args[i]] = args[i + 1];
    }
    final mode = values['--mode'];
    candidateCheck(mode == 'fresh' || mode == 'restart' || mode == 'recover');
    final dataRoot = candidateCanonicalPath(candidateRoot);
    candidateCheck(Directory(dataRoot).existsSync() &&
        p.basename(dataRoot) == 'p6-r7-app-data');
    final data =
        candidateCanonicalPath(values['--data-dir']!, mayBeMissing: true);
    candidateCheck(p.equals(p.dirname(data), dataRoot) &&
        p.basename(data).startsWith('run-') &&
        p6R7CandidateUuid.hasMatch(p.basename(data).substring(4)));
    candidateCheck(mode == 'fresh'
        ? FileSystemEntity.typeSync(data, followLinks: false) ==
            FileSystemEntityType.notFound
        : Directory(data).existsSync());
    final root = candidateCanonicalPath(hostRoot);
    candidateCheck(Directory(root).existsSync());
    final configPath = candidateCanonicalPath(values['--host-config']!);
    final folder = p.dirname(configPath);
    candidateCheck(p.equals(p.dirname(folder), root) &&
        RegExp(r'^app-lifecycle-owned-[0-9]{2}$')
            .hasMatch(p.basename(folder)) &&
        p.basename(configPath) == 'owned-host-config.json' &&
        !p.isWithin(dataRoot, folder) &&
        !p.isWithin(folder, dataRoot));
    final configHash = values['--host-config-sha256']!;
    candidateCheck(_hashPattern.hasMatch(configHash));
    final bytes = _pinnedBytes(configPath, configHash, maximum: 8192);
    final config = candidateJson(
        bytes, const {'schema', 'node_path', 'node_sha256', 'folder', 'pins'});
    candidateCheck(config['schema'] == 'p6_r7_owned_host_v1' &&
        config['node_path'] == _nodePath &&
        config['node_sha256'] == _nodeHash &&
        config['folder'] == folder);
    candidateCheck(config['pins'] is Map<String, dynamic>);
    final pins = config['pins'] as Map<String, dynamic>;
    candidateCheck(pins.length == 3 &&
        const {'launch.mjs', 'launcher-config.json', 'closure.json'}
            .every(pins.containsKey));
    for (final entry in pins.entries) {
      candidateCheck(
          entry.value is String && _hashPattern.hasMatch(entry.value));
      _pinnedBytes(p.join(folder, entry.key), entry.value as String,
          maximum: 1024 * 1024);
    }
    for (final name in ['admission.json', 'closed.json', 'events.jsonl']) {
      candidateCheck(
          FileSystemEntity.typeSync(p.join(folder, name), followLinks: false) ==
              FileSystemEntityType.notFound);
    }
    candidateCheck(!Platform.environment.keys.any((key) =>
        const {'NODE_OPTIONS', 'NODE_PATH'}.contains(key.toUpperCase())));
    _pinnedBytes(_nodePath, _nodeHash, maximum: 256 * 1024 * 1024);
    return P6R7OwnedHostConfiguration._(List.unmodifiable(args), enableToken,
        candidateRoot, hostRoot, folder, pins['closure.json'] as String);
  }

  /// Repeat every pin/path check immediately before Process.start.
  void verifyBeforeStart() {
    parse(arguments,
        enableToken: enableToken,
        candidateRoot: candidateRoot,
        hostRoot: hostRoot);
  }

  P6R7CandidateConfiguration readAdmission(
      {P6R7RecoveryInspection? recoveredOrigin}) {
    final path = candidateCanonicalPath(admissionPath);
    candidateCheck(File(path).lengthSync() <= 8192);
    final hash = sha256.convert(File(path).readAsBytesSync()).toString();
    final values = <String, String>{};
    for (var i = 1; i < arguments.length; i += 2) {
      values[arguments[i]] = arguments[i + 1];
    }
    final result = P6R7CandidateConfiguration.parse([
      '--p6-r7-app-candidate',
      '--admission',
      path,
      '--admission-sha256',
      hash,
      '--data-dir',
      values['--data-dir']!,
      '--mode',
      values['--mode']!,
    ],
        enableToken: enableToken,
        candidateRoot: candidateRoot,
        recoveredOrigin: recoveredOrigin);
    candidateCheck(result.sourceClosureSha256 == closureSha256);
    return result;
  }
}

List<int> _pinnedBytes(String path, String hash, {required int maximum}) {
  candidateCanonicalPath(path);
  final file = File(path);
  candidateCheck(file.lengthSync() <= maximum);
  final bytes = file.readAsBytesSync();
  candidateCheck(sha256.convert(bytes).toString() == hash);
  return bytes;
}

/// Owns the original Process and its write pipe for the entire App lifetime.
/// No kill operation is exposed. Native shutdown receipts remain host-owned.
class P6R7OwnedHost {
  P6R7OwnedHost();

  @visibleForTesting
  P6R7OwnedHost.forTesting(Process process) {
    _attach(process);
  }

  @visibleForTesting
  P6R7OwnedHost.startingForTesting(Future<Process> process) {
    _start = process.then(_attach);
  }

  Process? _process;
  Future<bool>? _terminated;
  Future<void>? _start;
  Future<bool>? _closing;
  int? _exitCode;
  bool _closed = false;
  bool _stdoutEof = false, _stderrEof = false, _stdinClosed = false;
  final _stopPreparing = Completer<void>();

  Future<void> start(P6R7OwnedHostConfiguration config,
      {P6R7RecoveryWitnessClient? witness}) {
    return _start ??= _spawn(config, witness);
  }

  Future<void> _spawn(P6R7OwnedHostConfiguration config,
      P6R7RecoveryWitnessClient? witness) async {
    candidateCheck(_process == null && !_stopPreparing.isCompleted);
    candidateCheck(config.mode != 'recover' || witness == null);
    final nodeDiscovery =
        witness == null ? null : await witness.nodeEnvironment();
    config.verifyBeforeStart();
    // Dart's normal Windows process uses redirected pipes and CREATE_NO_WINDOW.
    // No shell, detached mode, environment override, preload or command override.
    final process = await Process.start(
        _nodePath, ['--use-env-proxy', p.join(config.folder, 'launch.mjs')],
        workingDirectory: config.folder,
        environment: p6R7NodeEnvironment(Platform.environment, nodeDiscovery),
        includeParentEnvironment: false,
        runInShell: false,
        mode: ProcessStartMode.normal);
    _attach(process);
    if (witness != null) {
      final identity =
          await P6R7LiveChildIdentity.captureLiveChildIdentity(process);
      try {
        await witness.registerNode(
            nodePid: identity.pid, nodeCreation: identity.creation);
        await identity.verifyLive();
      } finally {
        await identity.close();
      }
    }
  }

  void _attach(Process process) {
    _process = process;
    // A child can close its read end before the next requested shutdown. Keep
    // that asynchronous pipe error handled without inventing a cleanup result.
    unawaited(process.stdin.done.then<void>((_) {}, onError: (Object _) {}));
    // Drain immediately, discard all raw text, and require both real pipe EOFs.
    final stdoutDone = _drain(process.stdout).then((ok) => _stdoutEof = ok);
    final stderrDone = _drain(process.stderr).then((ok) => _stderrEof = ok);
    final exit = process.exitCode.then((code) {
      _exitCode = code;
      return code == 0;
    }, onError: (Object _) => false);
    _terminated = Future.wait([exit, stdoutDone, stderrDone])
        .then((results) => results.every((result) => result));
  }

  static Future<bool> _drain(Stream<List<int>> pipe) async {
    try {
      await pipe.drain<void>();
      return true;
    } on Object {
      return false;
    }
  }

  Future<P6R7CandidateConfiguration> waitForAdmission(
      P6R7OwnedHostConfiguration config,
      {Duration timeout = const Duration(seconds: 180),
      P6R7RecoveryInspection? recoveredOrigin}) async {
    candidateCheck(_process != null && !_stopPreparing.isCompleted);
    final watch = Stopwatch()..start();
    Future<void> waitForPublicationChange() {
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) return Future<void>.value();
      final delay = remaining < const Duration(milliseconds: 100)
          ? remaining
          : const Duration(milliseconds: 100);
      return Future.any<void>([
        Future<void>.delayed(delay),
        _stopPreparing.future,
      ]);
    }

    while (watch.elapsed < timeout) {
      candidateCheck(_exitCode == null && !_stopPreparing.isCompleted);
      final type =
          FileSystemEntity.typeSync(config.admissionPath, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        candidateCheck(type == FileSystemEntityType.file);
        candidateCanonicalPath(config.admissionPath);
        // The pinned launcher claims the pathname with an empty exclusive file
        // before its preflight. Only that zero-byte publication state may wait;
        // any nonempty bytes remain a one-shot, fail-closed admission parse.
        if (File(config.admissionPath).lengthSync() == 0) {
          await waitForPublicationChange();
          continue;
        }
        return config.readAdmission(recoveredOrigin: recoveredOrigin);
      }
      await waitForPublicationChange();
    }
    throw const FormatException('candidate_admission_rejected');
  }

  Future<bool> close({Duration timeout = const Duration(seconds: 180)}) {
    if (!_stopPreparing.isCompleted) _stopPreparing.complete();
    if (_closed) return Future.value(true);
    final active = _closing;
    if (active != null) return active;
    late final Future<bool> attempt;
    attempt = _close(timeout).whenComplete(() {
      if (identical(_closing, attempt)) _closing = null;
    });
    _closing = attempt;
    return attempt;
  }

  Future<bool> _close(Duration timeout) async {
    try {
      // Also preserves ownership if the window closes during Process.start.
      if (_start != null) {
        try {
          await _start;
        } on Object {/* No spawn can remain in flight. */}
      }
      final process = _process;
      if (process == null) return true;
      final watch = Stopwatch()..start();
      if (_exitCode == null) {
        process.stdin.write('shutdown\n');
        await process.stdin.flush().timeout(timeout);
      }
      final remaining = timeout - watch.elapsed;
      if (remaining <= Duration.zero) return false;
      final success =
          await _terminated!.timeout(remaining, onTimeout: () => false);
      if (!success) return false;
      await process.stdin.close().timeout(remaining);
      _stdinClosed = true;
      _closed = true;
      return true;
    } on Object {
      return false;
    }
  }

  P6R7OwnedHostWitnessReceipt readWitnessClose(
      P6R7OwnedHostConfiguration config) {
    candidateCheck(_closed &&
        _exitCode == 0 &&
        _stdoutEof &&
        _stderrEof &&
        _stdinClosed &&
        _process != null);
    final path = candidateCanonicalPath(p.join(config.folder, 'closed.json'));
    candidateCheck(FileSystemEntity.typeSync(path, followLinks: false) ==
            FileSystemEntityType.file &&
        File(path).lengthSync() <= 1024 * 1024);
    return P6R7OwnedHostWitnessReceipt.inspect(File(path).readAsBytesSync(),
        expectedPid: _process!.pid);
  }
}

/// A bounded receipt projection. Actual process/EOF/pipe completion is checked
/// by readWitnessClose, not inferred from these JSON bytes.
class P6R7OwnedHostWitnessReceipt {
  P6R7OwnedHostWitnessReceipt._(
      this.hostClosedSha256, this.ownerManifestSha256);
  final String hostClosedSha256, ownerManifestSha256;
  @visibleForTesting
  static P6R7OwnedHostWitnessReceipt inspect(List<int> bytes,
      {required int expectedPid}) {
    final parsed = P6R7StrictJson.decode(bytes,
        maximumBytes: 1024 * 1024, maximumNodes: 4096);
    candidateCheck(parsed is Map<String, Object?>);
    final value = parsed as Map<String, Object?>;
    const keys = {
      'schema',
      'utc',
      'pid',
      'shutdown_reason',
      'result',
      'snapshot'
    };
    candidateCheck(value.length == keys.length &&
        keys.every(value.containsKey) &&
        value['schema'] == 'p6_r7_app_lifecycle_running_close_v1' &&
        value['pid'] is int &&
        value['pid'] == expectedPid &&
        value['shutdown_reason'] == 'input_shutdown' &&
        value['utc'] is String &&
        value['result'] is Map<String, Object?> &&
        value['snapshot'] is Map<String, Object?>);
    final result = value['result'] as Map<String, Object?>;
    candidateCheck(result.length == 4 &&
        result['status'] == 'closed' &&
        result['runtime_closed'] == true &&
        result['http_server_closed'] == true);
    final proof = result['witness_close'];
    candidateCheck(proof is Map<String, Object?>);
    final hashes = proof as Map<String, Object?>;
    candidateCheck(hashes.length == 2 &&
        const {'host_closed_sha256', 'owner_manifest_sha256'}
            .every(hashes.containsKey));
    for (final hash in hashes.values) {
      candidateCheck(
          hash is String && hash.length == 64 && _hashPattern.hasMatch(hash));
    }
    final hostHash = hashes['host_closed_sha256'] as String;
    final snapshot = value['snapshot'] as Map<String, Object?>;
    final compact = jsonEncode(snapshot);
    candidateCheck(
        snapshot['schema'] == 'p6_r7_app_candidate_host_evidence_v2' &&
            compact.codeUnits.every((unit) => unit <= 127) &&
            sha256.convert(utf8.encode(compact)).toString() == hostHash);
    return P6R7OwnedHostWitnessReceipt._(
        hostHash, hashes['owner_manifest_sha256'] as String);
  }
}
