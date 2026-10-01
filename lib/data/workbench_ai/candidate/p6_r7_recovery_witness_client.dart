import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:io' as process_io show pid;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const _maximumFrame = 16384;
const p6R7RecoveryWitnessImage =
    r'D:\memex\tmp\p6-r7-review\owned-recovery-witness-04\OwnedRecoveryWitness.exe';
const p6R7RecoveryWitnessSha256 =
    '7381f83666994d5835c1580c37afbf80a7556c5a1d516596e6f4b794c4af823e';
const p6R7WitnessNodeImage = r'D:\Nodejs\node.exe';
const p6R7WitnessNodeSha256 =
    '58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f';
Never _reject() => throw const FormatException('candidate_witness_rejected');
void _need(bool value) {
  if (!value) _reject();
}

bool _hash(String value) =>
    value.length == 64 && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
bool _id(String value) =>
    value.length == 36 &&
    RegExp(r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$')
        .hasMatch(value);
bool _creation(String value) {
  final parsed = BigInt.tryParse(value);
  return parsed != null &&
      parsed > BigInt.zero &&
      parsed < (BigInt.one << 64) &&
      parsed.toString() == value;
}

void _path(String value) => _need(p.windows.isAbsolute(value) &&
    !value.startsWith(r'\\') &&
    !value.contains('\x00') &&
    p.windows.normalize(value) == value);

enum P6R7WitnessRole { app, successor }

/// Environment is discovery only. The two trusted pins must come from the
/// reviewed launch package/compiled constants, never from that environment.
class P6R7RecoveryWitnessConfiguration {
  P6R7RecoveryWitnessConfiguration.fromEnvironment(
      Map<String, String> environment,
      {String trustedImage = p6R7RecoveryWitnessImage,
      String trustedSha256 = p6R7RecoveryWitnessSha256,
      required P6R7WitnessRole expectedRole}) {
    String get(String key) => environment['P6_R7_WITNESS_$key'] ?? '';
    _path(trustedImage);
    _need(_hash(trustedSha256));
    _need(get('IMAGE') == trustedImage && get('SHA256') == trustedSha256);
    _need(get('ROLE') == expectedRole.name);
    epoch = get('EPOCH');
    _need(_hash(epoch));
    role = expectedRole;
    pipeName = get('PIPE');
    _need(pipeName == 'p6-r7-recovery-$epoch-${role.name}');
    final rawPid = get('PID');
    serverPid = int.tryParse(rawPid) ?? 0;
    _need(serverPid > 0 && serverPid <= 0x7fffffff && '$serverPid' == rawPid);
    serverCreation = get('CREATION');
    _need(_creation(serverCreation));
    image = trustedImage;
    imageSha256 = trustedSha256;
    final parent = get('PARENT_PID');
    serverParentPid = parent.isEmpty ? null : int.tryParse(parent);
    if (parent.isNotEmpty) {
      _need(serverParentPid != null &&
          serverParentPid! > 0 &&
          serverParentPid! <= 0x7fffffff &&
          '$serverParentPid' == parent);
    }
  }
  late final String epoch, pipeName, serverCreation, image, imageSha256;
  late final int serverPid;
  late final P6R7WitnessRole role;
  late final int? serverParentPid;
}

class P6R7WitnessServerObservation {
  const P6R7WitnessServerObservation(
      {required this.pipePid,
      required this.processPid,
      required this.creation,
      required this.image,
      required this.imageSha256,
      required this.alive,
      required this.originalHandleHeld});
  final int? pipePid;
  final int processPid;
  final String creation, image, imageSha256;
  final bool alive, originalHandleHeld;
}

/// Test seam; production always constructs the native adapter below.
@visibleForTesting
abstract interface class P6R7WitnessIo {
  Future<void> connect(
      P6R7RecoveryWitnessConfiguration config, Duration timeout);
  Future<P6R7WitnessServerObservation> observe(Duration timeout,
      {bool requireConnectedPipe = true});
  Future<List<int>> read(int maximum, Duration timeout);
  Future<int> write(List<int> bytes, Duration timeout);
  Future<void> close();
}

/// The production entry still enforces the compiled binary pins. This seam
/// permits an isolated, current-user synthetic server to exercise Win32 ABI.
@visibleForTesting
P6R7WitnessIo p6R7WindowsWitnessIoForTesting() => _WindowsWitnessIo();

/// An instance-bound, validated reply. Not serializable recovery authority.
class P6R7RecoveryPermit {
  P6R7RecoveryPermit._(
      this.datasetId,
      this.datasetIdentityHash,
      this.recoveryId,
      this.successorBootSha256,
      this.challenge,
      this._permitId);
  final String datasetId,
      datasetIdentityHash,
      recoveryId,
      successorBootSha256,
      challenge;
  final String _permitId;
}

class P6R7RecoveryWitnessClient {
  P6R7RecoveryWitnessClient._(this._config, this._io, this._timeout);
  final P6R7RecoveryWitnessConfiguration _config;
  final P6R7WitnessIo _io;
  final Duration _timeout;
  int _sequence = 0;
  bool _frozen = false, _busy = false, _claimStarted = false;
  bool _terminal = false;
  Timer? _keepAlive;
  Future<void> _serial = Future<void>.value();
  P6R7RecoveryPermit? _permit;
  Future<void>? _spawn, _dispose;
  bool get frozen => _frozen;

  /// Discovery for the same witness's first-generation Node channel only.
  Future<Map<String, String>> nodeEnvironment() async {
    _need(_config.role == P6R7WitnessRole.app &&
        !_terminal &&
        _config.serverParentPid != null);
    await _verify(_timeout);
    return Map.unmodifiable({
      'P6_R7_WITNESS_PIPE': 'p6-r7-recovery-${_config.epoch}-node',
      'P6_R7_WITNESS_EPOCH': _config.epoch,
      'P6_R7_WITNESS_PID': '${_config.serverPid}',
      'P6_R7_WITNESS_CREATION': _config.serverCreation,
      'P6_R7_WITNESS_IMAGE': _config.image,
      'P6_R7_WITNESS_SHA256': _config.imageSha256,
      'P6_R7_WITNESS_ROLE': 'node',
      'P6_R7_WITNESS_PARENT_PID': '${_config.serverParentPid}',
    });
  }

  static Future<P6R7RecoveryWitnessClient> connectWindows(
      P6R7RecoveryWitnessConfiguration config,
      {Duration timeout = const Duration(seconds: 15)}) {
    _need(config.image == p6R7RecoveryWitnessImage &&
        config.imageSha256 == p6R7RecoveryWitnessSha256);
    return _connect(config, _WindowsWitnessIo(), timeout);
  }

  @visibleForTesting
  static Future<P6R7RecoveryWitnessClient> connectForTesting(
          P6R7RecoveryWitnessConfiguration config, P6R7WitnessIo io,
          {Duration timeout = const Duration(seconds: 15)}) =>
      _connect(config, io, timeout);

  static Future<P6R7RecoveryWitnessClient> _connect(
      P6R7RecoveryWitnessConfiguration config,
      P6R7WitnessIo io,
      Duration timeout) async {
    final client = P6R7RecoveryWitnessClient._(config, io, timeout);
    try {
      _need(timeout > Duration.zero && timeout <= const Duration(seconds: 60));
      await io.connect(config, timeout).timeout(timeout);
      await client._verify(timeout);
      return client;
    } on Object {
      await client._freeze();
      _reject();
    }
  }

  Future<void> _verify(Duration timeout,
      {bool requireConnectedPipe = true}) async {
    _need(!_frozen);
    final observed = await _io
        .observe(timeout, requireConnectedPipe: requireConnectedPipe)
        .timeout(timeout);
    _need(!_frozen &&
        observed.originalHandleHeld &&
        observed.alive &&
        (observed.pipePid == _config.serverPid ||
            (!requireConnectedPipe && observed.pipePid == null)) &&
        observed.processPid == _config.serverPid &&
        observed.creation == _config.serverCreation &&
        observed.image.toLowerCase() == _config.image.toLowerCase() &&
        observed.imageSha256 == _config.imageSha256);
  }

  Future<void> _freeze() async {
    _frozen = true;
    _keepAlive?.cancel();
    _keepAlive = null;
    _dispose ??= Future<void>.sync(_io.close)
        .timeout(_timeout)
        .catchError((Object _) {});
    await _dispose;
  }

  Future<void> close() => _freeze();

  /// Opt-in keepalive for the 02 server's 120-second frame gap. Business
  /// exchanges are never interleaved; terminal commands stop this timer first.
  void startKeepAlive() {
    _need(!_terminal && !_frozen);
    _keepAlive ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_busy && !_terminal && !_frozen) {
        unawaited(ping().catchError((Object _) {}));
      }
    });
  }

  Future<void> ping() async {
    await _exchange('ping', {}, 'alive', '',
        allowedStates: const {
          'awaiting_node',
          'awaiting_barrier',
          'live',
          'awaiting_app_close',
          'awaiting_actual_exits',
          'closed_unclaimed',
          'claimed',
          'consumed',
        });
  }

  Future<Map<String, Object?>> _exchange(String type,
      Map<String, Object?> fields, String replyType, String replyState,
      {Set<String> extraKeys = const {},
      Set<String>? allowedStates,
      bool terminal = false}) {
    final result = _serial.then((_) => _exchangeNow(
        type, fields, replyType, replyState,
        extraKeys: extraKeys,
        allowedStates: allowedStates,
        terminal: terminal));
    _serial = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, Object?>> _exchangeNow(String type,
      Map<String, Object?> fields, String replyType, String replyState,
      {Set<String> extraKeys = const {},
      Set<String>? allowedStates,
      bool terminal = false}) async {
    try {
      _need(!_busy && !_frozen && !_terminal && _sequence < 0x7fffffff);
      _busy = true;
      if (terminal) {
        _terminal = true;
        _keepAlive?.cancel();
        _keepAlive = null;
      }
      final watch = Stopwatch()..start();
      Duration remaining() {
        final value = _timeout - watch.elapsed;
        _need(value > Duration.zero);
        return value;
      }

      await _verify(remaining());
      final sequence = ++_sequence;
      final payload = utf8.encode(jsonEncode({
        'schema': 'p6_r7_owned_recovery_command_v1',
        'epoch': _config.epoch,
        'sequence': sequence,
        'type': type,
        ...fields
      }));
      _need(payload.isNotEmpty && payload.length <= _maximumFrame);
      final frame = Uint8List(payload.length + 4);
      ByteData.sublistView(frame).setUint32(0, payload.length, Endian.little);
      frame.setRange(4, frame.length, payload);
      var written = 0;
      while (written < frame.length) {
        final count = await _io
            .write(frame.sublist(written), remaining())
            .timeout(remaining());
        _need(count > 0 && count <= frame.length - written);
        written += count;
      }
      Future<Uint8List> exact(int count) async {
        final bytes = BytesBuilder(copy: false);
        while (bytes.length < count) {
          final part = await _io
              .read(count - bytes.length, remaining())
              .timeout(remaining());
          _need(part.isNotEmpty && part.length <= count - bytes.length);
          bytes.add(part);
        }
        return bytes.takeBytes();
      }

      final size =
          ByteData.sublistView(await exact(4)).getUint32(0, Endian.little);
      _need(size > 0 && size <= _maximumFrame);
      final body = await exact(size);
      _need(body.length < 3 ||
          body[0] != 0xef ||
          body[1] != 0xbb ||
          body[2] != 0xbf);
      final decoded =
          _StrictWitnessJson(utf8.decode(body, allowMalformed: false)).parse();
      _need(decoded is Map<String, Object?>);
      final reply = decoded as Map<String, Object?>;
      final expected = {
        'schema',
        'epoch',
        'sequence',
        'type',
        'state',
        ...extraKeys
      };
      _need(reply.length == expected.length &&
          reply.keys.every(expected.contains));
      _need(reply['schema'] == 'p6_r7_owned_recovery_reply_v1' &&
          reply['epoch'] == _config.epoch &&
          reply['sequence'] is int &&
          reply['sequence'] == sequence &&
          reply['type'] == replyType &&
          (allowedStates == null
              ? reply['state'] == replyState
              : allowedStates.contains(reply['state'])));
      // 02 closes the role pipe after terminal ACKs. Only the already held
      // original process/image handles are rechecked after that terminal frame.
      await _verify(remaining(), requireConnectedPipe: !terminal);
      return reply;
    } on Object {
      await _freeze();
      _reject();
    } finally {
      _busy = false;
    }
  }

  Future<void> registerNode(
      {required int nodePid, required String nodeCreation}) async {
    _need(_config.role == P6R7WitnessRole.app &&
        nodePid > 0 &&
        nodePid <= 0x7fffffff &&
        _creation(nodeCreation));
    await _exchange(
        'register_node',
        {'node_pid': nodePid, 'node_creation': nodeCreation},
        'node_registration_pending',
        'awaiting_node');
  }

  Future<void> bindOrigin(
      {required String datasetId,
      required String dataDirectory,
      required String datasetIdentityHash,
      required String launchId,
      required String admissionSha256,
      required String scopeHash}) async {
    _need(_config.role == P6R7WitnessRole.app &&
        _id(datasetId) &&
        _id(launchId) &&
        _hash(datasetIdentityHash) &&
        _hash(admissionSha256) &&
        _hash(scopeHash));
    _path(dataDirectory);
    await _exchange(
        'bind_origin',
        {
          'dataset_id': datasetId,
          'canonical_data_directory': dataDirectory,
          'dataset_identity_hash': datasetIdentityHash,
          'launch_id': launchId,
          'admission_sha256': admissionSha256,
          'scope_hash': scopeHash
        },
        'origin_bound',
        'live');
  }

  Future<void> bindTask(
      {required String taskId, required String scopeHash}) async {
    _need(
        _config.role == P6R7WitnessRole.app && _id(taskId) && _hash(scopeHash));
    await _exchange('bind_task', {'task_id': taskId, 'scope_hash': scopeHash},
        'task_bound', 'live');
  }

  Future<void> appClosed(
      {required int nodeExitCode,
      required bool stdoutEof,
      required bool stderrEof,
      required bool stdinClosed,
      required bool storeClosed,
      required bool clientClosed,
      required String? taskId,
      required String scopeHash,
      required String hostClosedSha256,
      required String ownerManifestSha256}) async {
    _need(_config.role == P6R7WitnessRole.app &&
        nodeExitCode == 0 &&
        stdoutEof &&
        stderrEof &&
        stdinClosed &&
        storeClosed &&
        clientClosed &&
        (taskId == null || _id(taskId)) &&
        _hash(scopeHash) &&
        _hash(hostClosedSha256) &&
        _hash(ownerManifestSha256));
    await _exchange(
        'app_closed',
        {
          'node_exit_code': nodeExitCode,
          'stdout_eof': stdoutEof,
          'stderr_eof': stderrEof,
          'stdin_closed': stdinClosed,
          'store_closed': storeClosed,
          'client_closed': clientClosed,
          'task_id': taskId,
          'scope_hash': scopeHash,
          'host_closed_sha256': hostClosedSha256,
          'owner_manifest_sha256': ownerManifestSha256
        },
        'app_close_recorded',
        'awaiting_actual_exits',
        terminal: true);
  }

  Future<P6R7RecoveryPermit> claim(
      {required String datasetId,
      required String datasetIdentityHash,
      required String recoveryId,
      required String successorBootSha256,
      required String challenge}) async {
    try {
      _need(!_claimStarted &&
          _config.role == P6R7WitnessRole.successor &&
          _id(datasetId) &&
          _hash(datasetIdentityHash) &&
          _id(recoveryId) &&
          _hash(successorBootSha256) &&
          _hash(challenge));
      _claimStarted = true;
      final reply = await _exchange(
          'claim',
          {
            'recovery_id': recoveryId,
            'successor_boot_sha256': successorBootSha256,
            'challenge': challenge
          },
          'permit',
          'claimed',
          extraKeys: {
            'dataset_id',
            'dataset_identity_hash',
            'generation',
            'next_generation',
            'recovery_id',
            'successor_boot_sha256',
            'challenge',
            'permit_id'
          });
      _need(reply['dataset_id'] == datasetId &&
          reply['dataset_identity_hash'] == datasetIdentityHash &&
          reply['generation'] is int &&
          reply['generation'] == 1 &&
          reply['next_generation'] is int &&
          reply['next_generation'] == 2 &&
          reply['recovery_id'] == recoveryId &&
          reply['successor_boot_sha256'] == successorBootSha256 &&
          reply['challenge'] == challenge &&
          reply['permit_id'] is String &&
          _hash(reply['permit_id'] as String));
      return _permit = P6R7RecoveryPermit._(
          datasetId,
          datasetIdentityHash,
          recoveryId,
          successorBootSha256,
          challenge,
          reply['permit_id'] as String);
    } on Object {
      await _freeze();
      _reject();
    }
  }

  /// The callback is invoked at most once, after the consume ACK and another
  /// original-server-handle check. It must run the caller's final pre-spawn pins.
  /// This never grants permission to restore or write a database.
  Future<void> spawnSuccessorOnce(
          P6R7RecoveryPermit permit, Future<void> Function() spawn) =>
      _spawn ??= _consumeAndSpawn(permit, spawn);
  Future<void> _consumeAndSpawn(
      P6R7RecoveryPermit permit, Future<void> Function() spawn) async {
    try {
      _need(identical(permit, _permit) && !_frozen);
      await _exchange(
          'consume', {'permit_id': permit._permitId}, 'spawn_once', 'consumed',
          terminal: true);
      await _verify(_timeout, requireConnectedPipe: false);
      _need(!_frozen);
      await spawn();
    } on Object {
      await _freeze();
      _reject();
    }
  }
}

/// jsonDecode alone silently drops duplicate decoded object keys.
class _StrictWitnessJson {
  _StrictWitnessJson(this.text);
  final String text;
  int at = 0;
  void space() {
    while (at < text.length && ' \t\r\n'.contains(text[at])) {
      at++;
    }
  }

  Object? parse() {
    final value = valueAt(0);
    space();
    _need(at == text.length);
    return value;
  }

  String string() {
    _need(at < text.length && text[at] == '"');
    final start = at++;
    while (at < text.length) {
      final c = text[at++];
      if (c == '\\') {
        _need(at < text.length);
        at++;
      } else if (c == '"') {
        return jsonDecode(text.substring(start, at)) as String;
      }
    }
    _reject();
  }

  Object? valueAt(int depth) {
    _need(depth <= 12);
    space();
    _need(at < text.length);
    if (text[at] == '"') return string();
    if (text[at] == '{') {
      at++;
      space();
      final result = <String, Object?>{};
      if (at < text.length && text[at] == '}') {
        at++;
        return result;
      }
      while (true) {
        space();
        final key = string();
        _need(!result.containsKey(key));
        space();
        _need(at < text.length && text[at++] == ':');
        result[key] = valueAt(depth + 1);
        space();
        _need(at < text.length);
        final delimiter = text[at++];
        if (delimiter == '}') return result;
        _need(delimiter == ',');
      }
    }
    if (text[at] == '[') {
      at++;
      space();
      final result = <Object?>[];
      if (at < text.length && text[at] == ']') {
        at++;
        return result;
      }
      while (true) {
        result.add(valueAt(depth + 1));
        space();
        _need(at < text.length);
        final delimiter = text[at++];
        if (delimiter == ']') return result;
        _need(delimiter == ',');
      }
    }
    final start = at;
    while (at < text.length && !' \t\r\n,]}'.contains(text[at])) {
      at++;
    }
    _need(at > start);
    final value = jsonDecode(text.substring(start, at));
    _need(value == null || value is bool || value is num);
    return value;
  }
}

// Only local named-pipe mode is changed (PIPE_NOWAIT); no DACL, elevation,
// process rights, shell, environment or service configuration is modified.
class _WindowsWitnessIo implements P6R7WitnessIo {
  late final _Kernel _k;
  int _pipe = 0, _process = 0, _image = 0;
  final _files = <int>[];
  bool _closed = false;
  late P6R7RecoveryWitnessConfiguration _config;

  @override
  Future<void> connect(
      P6R7RecoveryWitnessConfiguration config, Duration timeout) async {
    _need(Platform.isWindows && !_closed);
    _config = config;
    _k = _Kernel();
    final watch = Stopwatch()..start();
    while (true) {
      _need(!_closed && watch.elapsed < timeout);
      _pipe = _k.open('\\\\.\\pipe\\${config.pipeName}', 0xc0000000, 0, 0);
      if (_pipe != -1 && _pipe != 0) break;
      final error = _k.lastOpenError;
      _pipe = 0;
      _need(error == 2 || error == 231);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    final mode = _k.alloc<Uint32>(4)..value = 1; // byte-read + PIPE_NOWAIT
    try {
      _need(_k.setPipe(_pipe, mode, nullptr, nullptr) != 0);
    } finally {
      _k.free(mode);
    }
    _need(_k.pipePid(_pipe) == config.serverPid);
    _process = _k.openProcess(
        0x00101000, 0, config.serverPid); // query + synchronize only
    _need(_process != 0 &&
        _k.processPid(_process) == config.serverPid &&
        _k.wait(_process, 0) == 258);
    final root = p.windows.rootPrefix(config.image);
    var at = root;
    _pin(at, true);
    for (final part in p.windows
        .relative(p.windows.dirname(config.image), from: root)
        .split('\\')) {
      if (part == '.') continue;
      at = p.windows.join(at, part);
      _pin(at, true);
    }
    _image = _pin(config.image, false);
  }

  int _pin(String path, bool directory) {
    final handle = _k.open(
        path, directory ? 0x80 : 0x80000000, directory ? 3 : 1, 0x02200000);
    _need(handle != 0 && handle != -1);
    _files.add(handle);
    _k.verifyFile(handle, path, directory);
    return handle;
  }

  @override
  Future<P6R7WitnessServerObservation> observe(Duration timeout,
      {bool requireConnectedPipe = true}) async {
    _need(!_closed && _pipe != 0 && _process != 0 && _image != 0);
    final pipePid = requireConnectedPipe ? _k.pipePid(_pipe) : null;
    final processPid = _k.processPid(_process);
    final creation = _k.creation(_process);
    final image = _k.processImage(_process);
    _k.verifyFile(_image, _config.image, false);
    final digest = _k.hashFile(_image, timeout);
    _need((!requireConnectedPipe || _k.pipePid(_pipe) == pipePid) &&
        _k.processPid(_process) == processPid &&
        _k.creation(_process) == creation);
    return P6R7WitnessServerObservation(
        pipePid: pipePid,
        processPid: processPid,
        creation: creation,
        image: image,
        imageSha256: digest,
        alive: _k.wait(_process, 0) == 258,
        originalHandleHeld: true);
  }

  @override
  Future<List<int>> read(int maximum, Duration timeout) async {
    _need(maximum > 0 && maximum <= _maximumFrame);
    final watch = Stopwatch()..start();
    while (true) {
      _need(!_closed && watch.elapsed < timeout);
      final result = _k.transfer(_pipe, null, maximum);
      if (result.$1 == 0 && result.$2.isNotEmpty) return result.$2;
      // PIPE_NOWAIT can return success with zero bytes between fragmented
      // writes. That is no data yet; broken pipe is a distinct Win32 error.
      _need(result.$1 == 0 || result.$1 == 232);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  Future<int> write(List<int> bytes, Duration timeout) async {
    _need(bytes.isNotEmpty && bytes.length <= _maximumFrame + 4);
    final watch = Stopwatch()..start();
    while (true) {
      _need(!_closed && watch.elapsed < timeout);
      final result = _k.transfer(_pipe, bytes, bytes.length);
      _need(result.$1 == 0);
      if (result.$2.isNotEmpty) return result.$2.length;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final handles = [_pipe, _process, ..._files.reversed];
    var success = true;
    for (final handle in handles) {
      if (handle != 0 && handle != -1 && _k.close(handle) == 0) success = false;
    }
    _need(success);
  }
}

/// Captures a new query/synchronize handle while the Process.start child is
/// alive. Dart does not expose its private process handle for duplication.
/// This is registration evidence, never recovery or process-kill authority.
class P6R7LiveChildIdentity {
  P6R7LiveChildIdentity._(this._io, this.pid, this.parentPid, this._timeout);
  final P6R7WitnessChildIo _io;
  final int pid, parentPid;
  final Duration _timeout;
  late final String creation;
  bool _closed = false, _failed = false, _exitObserved = false;
  Future<void>? _close;

  static Future<P6R7LiveChildIdentity> captureLiveChildIdentity(Process child,
      {int? expectedParentPid,
      Duration timeout = const Duration(seconds: 15)}) {
    _need(Platform.isWindows &&
        (expectedParentPid ?? process_io.pid) == process_io.pid);
    return _capture(_WindowsWitnessChildIo(), child.pid, process_io.pid,
        child.exitCode, timeout);
  }

  @visibleForTesting
  static Future<P6R7LiveChildIdentity> captureForTesting(P6R7WitnessChildIo io,
          int childPid, int parentPid, Future<int> originalExit,
          {Duration timeout = const Duration(seconds: 15)}) =>
      _capture(io, childPid, parentPid, originalExit, timeout);

  static Future<P6R7LiveChildIdentity> _capture(
      P6R7WitnessChildIo io,
      int childPid,
      int parentPid,
      Future<int> originalExit,
      Duration timeout) async {
    final identity = P6R7LiveChildIdentity._(io, childPid, parentPid, timeout);
    unawaited(originalExit.then<void>((_) => identity._exitObserved = true,
        onError: (Object _, StackTrace __) {
      identity._exitObserved = true;
    }));
    try {
      _need(childPid > 0 &&
          parentPid > 0 &&
          childPid != parentPid &&
          timeout > Duration.zero &&
          timeout <= const Duration(seconds: 60));
      await io.capture(childPid, parentPid, timeout).timeout(timeout);
      final value = await io.observe(timeout).timeout(timeout);
      identity._check(value);
      identity.creation = value.creation;
      await identity.verifyLive();
      return identity;
    } on Object {
      identity._failed = true;
      try {
        await identity.close();
      } on Object {/* Fixed failure below. */}
      _reject();
    }
  }

  void _check(P6R7WitnessChildObservation value) {
    _need(!_closed &&
        !_failed &&
        !_exitObserved &&
        value.originalHandleHeld &&
        value.alive &&
        value.pid == pid &&
        value.parentPid == parentPid &&
        _creation(value.creation) &&
        _creation(value.parentCreation) &&
        BigInt.parse(value.creation) >= BigInt.parse(value.parentCreation) &&
        value.image.toLowerCase() == p6R7WitnessNodeImage.toLowerCase() &&
        value.imageSha256 == p6R7WitnessNodeSha256);
  }

  Future<void> verifyLive() async {
    try {
      _need(!_closed && !_failed && !_exitObserved);
      final value = await _io.observe(_timeout).timeout(_timeout);
      _check(value);
      _need(value.creation == creation);
    } on Object {
      _failed = true;
      _reject();
    }
  }

  Future<void> close() => _close ??= _closeOnce();
  Future<void> _closeOnce() async {
    _closed = true;
    try {
      await _io.close().timeout(_timeout);
    } on Object {
      _failed = true;
      _reject();
    }
  }
}

@visibleForTesting
class P6R7WitnessChildObservation {
  const P6R7WitnessChildObservation(
      {required this.pid,
      required this.parentPid,
      required this.creation,
      required this.parentCreation,
      required this.image,
      required this.imageSha256,
      required this.alive,
      required this.originalHandleHeld});
  final int pid, parentPid;
  final String creation, parentCreation, image, imageSha256;
  final bool alive, originalHandleHeld;
}

@visibleForTesting
abstract interface class P6R7WitnessChildIo {
  Future<void> capture(int pid, int parentPid, Duration timeout);
  Future<P6R7WitnessChildObservation> observe(Duration timeout);
  Future<void> close();
}

class _WindowsWitnessChildIo implements P6R7WitnessChildIo {
  final _k = _Kernel();
  final _files = <int>[];
  int _process = 0, _parent = 0, _image = 0, _pid = 0;
  bool _closed = false;
  @override
  Future<void> capture(int pid, int parentPid, Duration timeout) async {
    _need(!_closed && Platform.isWindows && sizeOf<IntPtr>() == 8);
    _pid = pid;
    _process = _k.openProcess(0x00101000, 0, pid);
    _parent = _k.openProcess(0x00101000, 0, parentPid);
    _need(_process != 0 &&
        _parent != 0 &&
        _k.processPid(_parent) == parentPid &&
        _k.wait(_parent, 0) == 258 &&
        _k.wait(_process, 0) == 258);
    final root = p.windows.rootPrefix(p6R7WitnessNodeImage);
    var at = root;
    _pin(at, true);
    for (final part in p.windows
        .relative(p.windows.dirname(p6R7WitnessNodeImage), from: root)
        .split('\\')) {
      if (part == '.') continue;
      at = p.windows.join(at, part);
      _pin(at, true);
    }
    _image = _pin(p6R7WitnessNodeImage, false);
  }

  int _pin(String path, bool directory) {
    final handle = _k.open(
        path, directory ? 0x80 : 0x80000000, directory ? 3 : 1, 0x02200000);
    _need(handle != 0 && handle != -1);
    _files.add(handle);
    _k.verifyFile(handle, path, directory);
    return handle;
  }

  @override
  Future<P6R7WitnessChildObservation> observe(Duration timeout) async {
    _need(!_closed &&
        _process != 0 &&
        _parent != 0 &&
        _image != 0 &&
        _k.wait(_process, 0) == 258 &&
        _k.wait(_parent, 0) == 258);
    final creation = _k.creation(_process);
    final parentCreation = _k.creation(_parent);
    final parentPid = _k.parentPid(_pid);
    _need(parentPid == _k.processPid(_parent));
    final image = _k.processImage(_process);
    _k.verifyFile(_image, p6R7WitnessNodeImage, false);
    final digest = _k.hashFile(_image, timeout);
    _need(_k.processPid(_process) == _pid &&
        _k.creation(_process) == creation &&
        _k.creation(_parent) == parentCreation &&
        _k.wait(_parent, 0) == 258);
    return P6R7WitnessChildObservation(
        pid: _pid,
        parentPid: parentPid,
        creation: creation,
        parentCreation: parentCreation,
        image: image,
        imageSha256: digest,
        alive: _k.wait(_process, 0) == 258,
        originalHandleHeld: true);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    var success = true;
    for (final handle in [_process, _parent, ..._files.reversed]) {
      if (handle != 0 && handle != -1 && _k.close(handle) == 0) success = false;
    }
    _need(success);
  }
}

class _Kernel {
  int lastOpenError = 0;
  late final snapshot = library.lookupFunction<IntPtr Function(Uint32, Uint32),
      int Function(int, int)>('CreateToolhelp32Snapshot');
  late final processFirst = library.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)>('Process32FirstW');
  late final processNext = library.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint8>),
      int Function(int, Pointer<Uint8>)>('Process32NextW');
  int parentPid(int target) {
    _need(sizeOf<IntPtr>() == 8);
    final handle = snapshot(2, 0);
    _need(handle != 0 && handle != -1);
    final entry = alloc<Uint8>(568);
    try {
      entry.cast<Uint32>().value = 568;
      var ok = processFirst(handle, entry);
      for (var count = 0; ok != 0 && count < 8192; count++) {
        if ((entry + 8).cast<Uint32>().value == target) {
          return (entry + 32).cast<Uint32>().value;
        }
        ok = processNext(handle, entry);
      }
      _reject();
    } finally {
      free(entry);
      _need(close(handle) != 0);
    }
  }

  final DynamicLibrary library = DynamicLibrary.open('kernel32.dll');
  late final heap = library
      .lookupFunction<IntPtr Function(), int Function()>('GetProcessHeap')();
  late final heapAlloc = library.lookupFunction<
      Pointer<Void> Function(IntPtr, Uint32, IntPtr),
      Pointer<Void> Function(int, int, int)>('HeapAlloc');
  late final heapFree = library.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Void>),
      int Function(int, int, Pointer<Void>)>('HeapFree');
  late final createFile = library.lookupFunction<
      IntPtr Function(Pointer<Uint16>, Uint32, Uint32, Pointer<Void>, Uint32,
          Uint32, IntPtr),
      int Function(Pointer<Uint16>, int, int, Pointer<Void>, int, int,
          int)>('CreateFileW');
  late final setPipe = library.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>, Pointer<Uint32>, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>, Pointer<Uint32>,
          Pointer<Uint32>)>('SetNamedPipeHandleState');
  late final error =
      library.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  late final close = library
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
  late final openProcess = library.lookupFunction<
      IntPtr Function(Uint32, Int32, Uint32),
      int Function(int, int, int)>('OpenProcess');
  late final processPid =
      library.lookupFunction<Uint32 Function(IntPtr), int Function(int)>(
          'GetProcessId');
  late final getPipePid = library.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('GetNamedPipeServerProcessId');
  late final wait = library.lookupFunction<Uint32 Function(IntPtr, Uint32),
      int Function(int, int)>('WaitForSingleObject');
  late final getTimes = library.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>),
      int Function(int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>,
          Pointer<Uint64>)>('GetProcessTimes');
  late final queryImage = library.lookupFunction<
      Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>),
      int Function(int, int, Pointer<Uint16>,
          Pointer<Uint32>)>('QueryFullProcessImageNameW');
  late final fileInfo = library.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint32>),
      int Function(int, Pointer<Uint32>)>('GetFileInformationByHandle');
  late final finalPath = library.lookupFunction<
      Uint32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32),
      int Function(
          int, Pointer<Uint16>, int, int)>('GetFinalPathNameByHandleW');
  late final seek = library.lookupFunction<
      Int32 Function(IntPtr, Int64, Pointer<Int64>, Uint32),
      int Function(int, int, Pointer<Int64>, int)>('SetFilePointerEx');
  late final readFile = library.lookupFunction<
      Int32 Function(
          IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
          Pointer<Void>)>('ReadFile');
  late final writeFile = library.lookupFunction<
      Int32 Function(
          IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Void>),
      int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
          Pointer<Void>)>('WriteFile');
  Pointer<T> alloc<T extends NativeType>(int bytes) {
    final value = heapAlloc(heap, 8, bytes);
    _need(value != nullptr);
    return value.cast<T>();
  }

  void free(Pointer pointer) =>
      _need(heapFree(heap, 0, pointer.cast<Void>()) != 0);
  int open(String path, int access, int sharing, int flags) {
    final text = alloc<Uint16>((path.length + 1) * 2);
    try {
      text
          .asTypedList(path.length + 1)
          .setRange(0, path.length, path.codeUnits);
      final handle = createFile(text, access, sharing, nullptr, 3, flags, 0);
      lastOpenError = (handle == 0 || handle == -1) ? error() : 0;
      return handle;
    } finally {
      free(text);
    }
  }

  int pipePid(int pipe) {
    final value = alloc<Uint32>(4);
    try {
      _need(getPipePid(pipe, value) != 0);
      return value.value;
    } finally {
      free(value);
    }
  }

  String creation(int process) {
    final times = alloc<Uint64>(32);
    try {
      _need(getTimes(process, times, times + 1, times + 2, times + 3) != 0);
      return times.value.toUnsigned(64).toString();
    } finally {
      free(times);
    }
  }

  String processImage(int process) {
    final text = alloc<Uint16>(65536), count = alloc<Uint32>(4)..value = 32768;
    try {
      _need(queryImage(process, 0, text, count) != 0 &&
          count.value > 0 &&
          count.value < 32768);
      return String.fromCharCodes(text.asTypedList(count.value));
    } finally {
      free(text);
      free(count);
    }
  }

  void verifyFile(int file, String expected, bool directory) {
    final info = alloc<Uint32>(52), text = alloc<Uint16>(65536);
    try {
      _need(fileInfo(file, info) != 0 &&
          (info.value & 0x400) == 0 &&
          ((info.value & 0x10) != 0) == directory);
      final count = finalPath(file, text, 32768, 0);
      _need(count > 4 && count < 32768);
      final actual = String.fromCharCodes(text.asTypedList(count));
      _need(actual.startsWith('\\\\?\\') &&
          actual.substring(4).toLowerCase() == expected.toLowerCase());
    } finally {
      free(info);
      free(text);
    }
  }

  (int, List<int>) transfer(int file, List<int>? input, int count) {
    final bytes = alloc<Uint8>(count), actual = alloc<Uint32>(4);
    try {
      if (input != null) bytes.asTypedList(count).setAll(0, input);
      final ok = input == null
          ? readFile(file, bytes, count, actual, nullptr)
          : writeFile(file, bytes, count, actual, nullptr);
      final status = ok == 0 ? error() : 0;
      _need(actual.value <= count);
      return (status, List<int>.of(bytes.asTypedList(actual.value)));
    } finally {
      free(bytes);
      free(actual);
    }
  }

  String hashFile(int file, Duration timeout) {
    final position = alloc<Int64>(8);
    try {
      _need(seek(file, 0, position, 0) != 0 && position.value == 0);
    } finally {
      free(position);
    }
    final sink = _DigestSink(), watch = Stopwatch()..start();
    final hash = sha256.startChunkedConversion(sink);
    var total = 0;
    while (true) {
      _need(watch.elapsed < timeout);
      final result = transfer(file, null, 65536);
      _need(result.$1 == 0);
      if (result.$2.isEmpty) break;
      total += result.$2.length;
      _need(total <= 256 * 1024 * 1024);
      hash.add(result.$2);
    }
    _need(total > 0);
    hash.close();
    return sink.value!.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) {
    _need(value == null);
    value = digest;
  }

  @override
  void close() {}
}
