import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/memory_v3/models/task_room_enums.dart';
import 'package:memex/data/workbench_ai/candidate/p6_r7_recovery_identity.dart';
import 'package:memex/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart';

const _id = '123e4567-e89b-42d3-a456-426614174000';
const _dir = r'D:\p6-r7-app-data\run-123e4567-e89b-42d3-a456-426614174000';

void main() {
  List<int> marker({String admission = 'a'}) => utf8.encode(jsonEncode({
        'schema': 'p6_r7_candidate_dataset_v1',
        'dataset_id': _id,
        'directory': _dir,
        'database': 'candidate.sqlite',
        'admission_sha256': admission * 64,
        'source_closure_sha256': 'b' * 64,
        'native_sha256': 'c' * 64,
      }));
  P6R7TrustedOrigin trusted(List<int> bytes) => P6R7TrustedOrigin(
      identityHash: sha256
          .convert(utf8.encode(jsonEncode({
            'schema': 'p6_r7_candidate_dataset_v1',
            'dataset_id': _id,
            'directory': _dir,
            'database': 'candidate.sqlite',
            'admission_sha256': 'a' * 64,
            'source_closure_sha256': 'b' * 64,
            'native_sha256': 'c' * 64,
          })))
          .toString(),
      sourceClosureSha256: 'b' * 64,
      nativeSha256: 'c' * 64,
      canonicalDirectory: _dir,
      datasetId: _id);
  P6R7ReadOnlyProjection projection(String? id) => P6R7ReadOnlyProjection(
      userVersion: 60,
      identityRows: [
        {'identity_hash': trusted(marker()).identityHash, 'task_id': id}
      ],
      taskRows: id == null
          ? []
          : [
              {
                'id': id,
                'title': '公开文字验收',
                'goal': '只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。',
                'task_type': TaskType.other.value,
                'executor': 'workbench_runtime',
                'conversation_id': 'p6-r7-candidate-$_id',
                'profile_id':
                    DesktopWorkbenchTaskQueueAuthorizationFactory.profileId,
                'scope_type': 'conversation',
                'scope_id': 'p6-r7-candidate-$_id',
              }
            ]);

  test('preserves v1 marker hash and separates it from live admission', () {
    final origin = P6R7OriginIdentity.inspect(marker(), trusted(marker()));
    expect(origin.identityHash, trusted(marker()).identityHash);
    expect(origin.originAdmissionSha256, 'a' * 64);
    expect(
        () => P6R7OriginIdentity.inspect(
            marker(admission: 'd'), trusted(marker())),
        throwsFormatException);
  });

  test(
      'strict JSON rejects duplicate decoded keys, malformed forms, and every non-whitespace tail',
      () {
    for (final bytes in [
      utf8.encode('{"a":1,"\\u0061":2}'),
      utf8.encode('{"a":1}x'),
      utf8.encode('{"a":1}\n[]'),
      utf8.encode('{"a":NaN}'),
      utf8.encode('{"a":"\\ud800"}'),
      utf8.encode('{"a":1e9999}'),
      List<int>.filled(8193, 0x20),
    ]) {
      expect(() => P6R7StrictJson.decode(bytes), throwsFormatException);
    }
    expect(P6R7StrictJson.decode(utf8.encode('{"a":1}\r\n\t ')), {'a': 1});
  });

  test('validates exact one-task projection and strict null first generation',
      () {
    expect(
        P6R7RecoveryInspection.inspect(
                markerBytes: marker(),
                trustedOrigin: trusted(marker()),
                projection: projection(_id))
            .taskId,
        _id);
    expect(
        P6R7RecoveryInspection.inspect(
                markerBytes: marker(),
                trustedOrigin: trusted(marker()),
                projection: projection(null))
            .taskId,
        isNull);
    final invalid = projection(null);
    final bad = P6R7ReadOnlyProjection(
        userVersion: invalid.userVersion,
        identityRows: invalid.identityRows,
        taskRows: [{}]);
    expect(
        () => P6R7RecoveryInspection.inspect(
            markerBytes: marker(),
            trustedOrigin: trusted(marker()),
            projection: bad),
        throwsFormatException);
  });

  test('larger close receipts require an explicit bounded node budget', () {
    final bytes = utf8.encode(jsonEncode(List<int>.filled(300, 0)));
    expect(() => P6R7StrictJson.decode(bytes), throwsFormatException);
    expect(P6R7StrictJson.decode(bytes, maximumNodes: 4096), hasLength(300));
    for (final maximum in [0, 4097]) {
      expect(() => P6R7StrictJson.decode(bytes, maximumNodes: maximum),
          throwsFormatException);
    }
    expect(
        () => P6R7StrictJson.decode(
            utf8.encode(jsonEncode(List<int>.filled(4096, 0))),
            maximumBytes: 1024 * 1024,
            maximumNodes: 4096),
        throwsFormatException);
  });

  test('wrong task scope and trusted pins reject without issuing authority',
      () {
    final wrong = projection(_id);
    final task = Map<String, Object?>.from(wrong.taskRows.single)
      ..['scope_id'] = 'other';
    final bad = P6R7ReadOnlyProjection(
        userVersion: 60, identityRows: wrong.identityRows, taskRows: [task]);
    expect(
        () => P6R7RecoveryInspection.inspect(
            markerBytes: marker(),
            trustedOrigin: trusted(marker()),
            projection: bad),
        throwsFormatException);
  });

  test(
      'rejects the candidate conversation profile when it is not the queue authorization profile',
      () {
    final wrong = projection(_id);
    final task = Map<String, Object?>.from(wrong.taskRows.single)
      ..['profile_id'] = 'workbench_text_only_v1';
    final bad = P6R7ReadOnlyProjection(
        userVersion: wrong.userVersion,
        identityRows: wrong.identityRows,
        taskRows: [task]);
    expect(
        () => P6R7RecoveryInspection.inspect(
            markerBytes: marker(),
            trustedOrigin: trusted(marker()),
            projection: bad),
        throwsFormatException);
  });
}
