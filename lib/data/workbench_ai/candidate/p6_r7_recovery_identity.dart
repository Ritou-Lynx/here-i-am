/// Pure recovery inspection primitives.  These types do not open files,
/// SQLite databases, processes, or network connections and cannot issue a
/// recovery permit.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../memory_v3/models/task_room_enums.dart';
import '../task_queue/workbench_task_queue_tool_host.dart';

const _markerSchema = 'p6_r7_candidate_dataset_v1';
const _databaseName = 'candidate.sqlite';
const _title = '公开文字验收';
const _goal = '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。';
final _sha256 = RegExp(r'^[a-f0-9]{64}$');
final _uuid = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$');

Never _reject() =>
    throw const FormatException('p6_r7_recovery_inspection_rejected');

void _require(bool condition) {
  if (!condition) _reject();
}

/// Trusted pins must come from the caller's authority, never from marker
/// bytes being examined.
class P6R7TrustedOrigin {
  const P6R7TrustedOrigin({
    required this.identityHash,
    required this.sourceClosureSha256,
    required this.nativeSha256,
    required this.canonicalDirectory,
    required this.datasetId,
  });

  final String identityHash;
  final String sourceClosureSha256;
  final String nativeSha256;
  final String canonicalDirectory;
  final String datasetId;
}

/// Immutable v1 origin marker.  It deliberately has no live-host admission.
class P6R7OriginIdentity {
  const P6R7OriginIdentity._({
    required this.datasetId,
    required this.canonicalDirectory,
    required this.originAdmissionSha256,
    required this.sourceClosureSha256,
    required this.nativeSha256,
    required this.identityHash,
  });

  final String datasetId;
  final String canonicalDirectory;
  final String originAdmissionSha256;
  final String sourceClosureSha256;
  final String nativeSha256;
  final String identityHash;

  static P6R7OriginIdentity inspect(
      List<int> markerBytes, P6R7TrustedOrigin trusted) {
    final value = P6R7StrictJson.decode(markerBytes);
    _require(value is Map<String, Object?>);
    final marker = value as Map<String, Object?>;
    const fields = {
      'schema',
      'dataset_id',
      'directory',
      'database',
      'admission_sha256',
      'source_closure_sha256',
      'native_sha256',
    };
    _require(marker.length == fields.length &&
        marker.keys.toSet().containsAll(fields));
    for (final key in fields) {
      _require(marker[key] is String);
    }
    _require(marker['schema'] == _markerSchema);
    _require(marker['database'] == _databaseName);
    final datasetId = marker['dataset_id'] as String;
    final directory = marker['directory'] as String;
    final admission = marker['admission_sha256'] as String;
    final closure = marker['source_closure_sha256'] as String;
    final native = marker['native_sha256'] as String;
    _require(_uuid.hasMatch(datasetId) && _sha256.hasMatch(admission));
    _require(_sha256.hasMatch(closure) && _sha256.hasMatch(native));
    _require(datasetId == trusted.datasetId &&
        directory == trusted.canonicalDirectory);
    _require(closure == trusted.sourceClosureSha256 &&
        native == trusted.nativeSha256);
    final ordered = <String, Object>{
      'schema': _markerSchema,
      'dataset_id': datasetId,
      'directory': directory,
      'database': _databaseName,
      'admission_sha256': admission,
      'source_closure_sha256': closure,
      'native_sha256': native,
    };
    final hash = sha256.convert(utf8.encode(jsonEncode(ordered))).toString();
    _require(hash == trusted.identityHash);
    return P6R7OriginIdentity._(
      datasetId: datasetId,
      canonicalDirectory: directory,
      originAdmissionSha256: admission,
      sourceClosureSha256: closure,
      nativeSha256: native,
      identityHash: hash,
    );
  }
}

/// A caller-supplied read-only SQLite projection.  This module only inspects
/// values already read by another layer; passing validation is not authority
/// to recover, spawn a host, or write a database.
class P6R7ReadOnlyProjection {
  const P6R7ReadOnlyProjection({
    required this.userVersion,
    required this.identityRows,
    required this.taskRows,
  });

  final int userVersion;
  final List<Map<String, Object?>> identityRows;
  final List<Map<String, Object?>> taskRows;
}

class P6R7RecoveryInspection {
  const P6R7RecoveryInspection._({required this.origin, required this.taskId});

  final P6R7OriginIdentity origin;
  final String? taskId;

  static P6R7RecoveryInspection inspect({
    required List<int> markerBytes,
    required P6R7TrustedOrigin trustedOrigin,
    required P6R7ReadOnlyProjection projection,
  }) {
    final origin = P6R7OriginIdentity.inspect(markerBytes, trustedOrigin);
    _require(
        projection.userVersion == 60 && projection.identityRows.length == 1);
    final identity = projection.identityRows.single;
    _require(identity.length == 2 &&
        identity['identity_hash'] == origin.identityHash &&
        identity.containsKey('task_id'));
    final taskId = identity['task_id'];
    if (taskId == null) {
      _require(projection.taskRows.isEmpty);
      return P6R7RecoveryInspection._(origin: origin, taskId: null);
    }
    _require(taskId is String && _uuid.hasMatch(taskId));
    _require(projection.taskRows.length == 1);
    final task = projection.taskRows.single;
    const fields = {
      'id',
      'title',
      'goal',
      'task_type',
      'executor',
      'conversation_id',
      'profile_id',
      'scope_type',
      'scope_id',
    };
    _require(
        task.length == fields.length && task.keys.toSet().containsAll(fields));
    final conversation = 'p6-r7-candidate-${origin.datasetId}';
    _require(task['id'] == taskId &&
        task['title'] == _title &&
        task['goal'] == _goal);
    _require(task['task_type'] == TaskType.other.value &&
        task['executor'] == 'workbench_runtime');
    _require(task['conversation_id'] == conversation &&
        task['profile_id'] ==
            DesktopWorkbenchTaskQueueAuthorizationFactory.profileId);
    _require(task['scope_type'] == 'conversation' &&
        task['scope_id'] == conversation);
    return P6R7RecoveryInspection._(origin: origin, taskId: taskId as String);
  }
}

/// Strict bounded JSON parser.  Map keys are compared after escape decoding,
/// so `a` and `\\u0061` cannot coexist in one object.
class P6R7StrictJson {
  static Object? decode(List<int> bytes,
      {int maximumBytes = 8192, int maximumNodes = 256}) {
    _require(maximumBytes > 0 && maximumBytes <= 1024 * 1024);
    _require(maximumNodes > 0 && maximumNodes <= 4096);
    _require(bytes.length <= maximumBytes);
    final text = utf8.decode(bytes, allowMalformed: false);
    final parser = _StrictParser(text, maximumNodes);
    final result = parser.value(0);
    parser.space();
    _require(parser.atEnd);
    return result;
  }
}

class _StrictParser {
  _StrictParser(this.text, this.maximumNodes);
  final String text;
  final int maximumNodes;
  int index = 0;
  int nodes = 0;
  bool get atEnd => index == text.length;
  int get _unit => index < text.length ? text.codeUnitAt(index) : -1;

  void space() {
    while (_unit == 0x20 || _unit == 0x0a || _unit == 0x0d || _unit == 0x09) {
      index++;
    }
  }

  Object? value(int depth) {
    _require(depth <= 12 && ++nodes <= maximumNodes);
    space();
    switch (_unit) {
      case 0x7b:
        return object(depth + 1);
      case 0x5b:
        return array(depth + 1);
      case 0x22:
        return string();
      case 0x74:
        return literal('true', true);
      case 0x66:
        return literal('false', false);
      case 0x6e:
        return literal('null', null);
      default:
        return number();
    }
  }

  Object? literal(String source, Object? result) {
    _require(text.startsWith(source, index));
    index += source.length;
    return result;
  }

  Map<String, Object?> object(int depth) {
    index++;
    space();
    final out = <String, Object?>{};
    if (_unit == 0x7d) {
      index++;
      return out;
    }
    while (true) {
      _require(_unit == 0x22);
      final key = string();
      _require(!out.containsKey(key));
      space();
      _require(_unit == 0x3a);
      index++;
      out[key] = value(depth);
      space();
      if (_unit == 0x7d) {
        index++;
        return out;
      }
      _require(_unit == 0x2c);
      index++;
      space();
    }
  }

  List<Object?> array(int depth) {
    index++;
    space();
    final out = <Object?>[];
    if (_unit == 0x5d) {
      index++;
      return out;
    }
    while (true) {
      out.add(value(depth));
      space();
      if (_unit == 0x5d) {
        index++;
        return out;
      }
      _require(_unit == 0x2c);
      index++;
      space();
    }
  }

  String string() {
    _require(_unit == 0x22);
    index++;
    final out = StringBuffer();
    while (true) {
      final c = _unit;
      _require(c >= 0);
      index++;
      if (c == 0x22) return out.toString();
      _require(c >= 0x20 && c < 0xd800 || c > 0xdfff);
      if (c != 0x5c) {
        out.writeCharCode(c);
        continue;
      }
      final escaped = _unit;
      _require(escaped >= 0);
      index++;
      const simple = {
        0x22: 0x22,
        0x5c: 0x5c,
        0x2f: 0x2f,
        0x62: 8,
        0x66: 12,
        0x6e: 10,
        0x72: 13,
        0x74: 9
      };
      if (simple.containsKey(escaped)) {
        out.writeCharCode(simple[escaped]!);
        continue;
      }
      _require(escaped == 0x75 && index + 4 <= text.length);
      final hex = text.substring(index, index + 4);
      _require(RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(hex));
      final code = int.parse(hex, radix: 16);
      _require(code < 0xd800 || code > 0xdfff);
      out.writeCharCode(code);
      index += 4;
    }
  }

  num number() {
    final start = index;
    if (_unit == 0x2d) index++;
    _require(_unit >= 0x30 && _unit <= 0x39);
    if (_unit == 0x30) {
      index++;
    } else {
      while (_unit >= 0x30 && _unit <= 0x39) {
        index++;
      }
    }
    if (_unit == 0x2e) {
      index++;
      _require(_unit >= 0x30 && _unit <= 0x39);
      while (_unit >= 0x30 && _unit <= 0x39) {
        index++;
      }
    }
    if (_unit == 0x65 || _unit == 0x45) {
      index++;
      if (_unit == 0x2b || _unit == 0x2d) index++;
      _require(_unit >= 0x30 && _unit <= 0x39);
      while (_unit >= 0x30 && _unit <= 0x39) {
        index++;
      }
    }
    final raw = text.substring(start, index);
    final parsed = num.tryParse(raw);
    _require(parsed != null && parsed.isFinite);
    return parsed!;
  }
}
