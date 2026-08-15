import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/orchestration/canvas_action_log.dart';

void main() {
  group('CanvasActionLog - 写入契约', () {
    test('append-only：条目不可变，追加后只增不改', () async {
      final log = ThresholdCanvasActionLog(
        consumer: _CountingConsumer(),
        threshold: 10,
      );
      await log.append(_entry('n1', succeeded: true));
      await log.append(_entry('n2', succeeded: true));

      expect(log.entries.length, 2);
      final first = log.entries.first;
      expect(first.nodeRef.id, 'n1');
      expect(first.nodeRef.type, 'note');
      expect(first.nodeRef.label, '卡片_n1');
    });

    test('失败请求不计数（但可审计）', () async {
      final consumer = _CountingConsumer();
      final log = ThresholdCanvasActionLog(
        consumer: consumer,
        threshold: 5,
      );
      for (var i = 0; i < 20; i++) {
        await log.append(_entry('n$i', succeeded: false));
      }
      expect(log.entries.length, 20);
      expect(log.pendingCount, 0);
      expect(log.triggerCount, 0);
      expect(consumer.batches, isEmpty);
    });

    test('达阈值触发一次消费并清零，不足阈值不触发', () async {
      final consumer = _CountingConsumer();
      final log = ThresholdCanvasActionLog(
        consumer: consumer,
        threshold: 5,
      );
      for (var i = 0; i < 4; i++) {
        await log.append(_entry('n$i'));
      }
      expect(log.triggerCount, 0);
      expect(log.pendingCount, 4);

      await log.append(_entry('n4'));
      expect(log.triggerCount, 1);
      expect(log.pendingCount, 0);
      expect(consumer.batches.length, 1);
      expect(consumer.batches.first.length, 5);

      // 再攒一轮又触发
      for (var i = 0; i < 5; i++) {
        await log.append(_entry('m$i'));
      }
      expect(log.triggerCount, 2);
      expect(log.pendingCount, 0);
    });

    test('阈值参数非法抛错', () {
      expect(
        () => ThresholdCanvasActionLog(
          consumer: _CountingConsumer(),
          threshold: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('NodeRef 守卫 - 只存 id/type/label，绝不存节点内容', () {
    test('toJson 只有三个键', () {
      const ref = NodeRef(id: 'n1', type: 'note', label: '标题');
      expect(ref.toJson().keys.toSet(), {'id', 'type', 'label'});
    });

    test('序列化后的整个条目 JSON 不含任何内容键', () {
      final entry = _entry('n1');
      final json = jsonEncode(entry.toJson());
      // 字符串级别守卫：内容类键名不得出现
      for (final forbidden in [
        'content',
        'body',
        'text',
        'summary',
        'markdown',
        '正文',
      ]) {
        expect(json.contains(forbidden), isFalse,
            reason: 'Action Log 不得携带节点内容，发现键/值包含: $forbidden');
      }
    });

    test('fromJson 拒绝多余键（内容泄漏防护）', () {
      expect(
        () => NodeRef.fromJson({
          'id': 'n1',
          'type': 'note',
          'label': '标题',
          'content': '这是正文，不允许',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('条目 JSON 往返一致', () {
      final entry = _entry('n1');
      final restored = CanvasActionEntry.fromJson(entry.toJson());
      expect(restored.nodeRef.id, entry.nodeRef.id);
      expect(restored.nodeRef.type, entry.nodeRef.type);
      expect(restored.nodeRef.label, entry.nodeRef.label);
      expect(restored.kind, entry.kind);
      expect(restored.succeeded, entry.succeeded);
    });
  });
}

CanvasActionEntry _entry(String id, {bool succeeded = true}) {
  return CanvasActionEntry(
    occurredAt: DateTime.utc(2026, 8, 16, 12),
    kind: CanvasActionKind.move,
    nodeRef: NodeRef(id: id, type: 'note', label: '卡片_$id'),
    succeeded: succeeded,
  );
}

class _CountingConsumer implements CanvasActionConsumer {
  final List<List<CanvasActionEntry>> batches = [];

  @override
  Future<void> consume(List<CanvasActionEntry> batch) async {
    batches.add(List.of(batch));
  }
}
