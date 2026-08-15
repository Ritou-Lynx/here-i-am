import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/whiteboard/orchestration/result_compressor.dart';
import 'package:memex/domain/whiteboard/orchestration/task_router.dart';

void main() {
  final compressor = ResultCompressor();

  group('ResultCompressor - 长输出压缩', () {
    test('短摘要原样保留，不截断', () {
      final compressed = compressor.compress(const TaskExecutionResult(
        status: ExecutionStatus.completed,
        summary: '已添加导出功能',
        decisions: ['选择 JSON'],
        artifactRefs: ['diff-1.patch'],
      ));
      expect(compressed.summary, '已添加导出功能');
      expect(compressed.truncated, isFalse);
      expect(compressed.decisions, ['选择 JSON']);
      expect(compressed.artifactRefs, ['diff-1.patch']);
    });

    test('超过上限截断并标记', () {
      final long = '长' * 300;
      final compressed = compressor.compress(TaskExecutionResult(
        status: ExecutionStatus.completed,
        summary: long,
      ));
      expect(compressed.summary.length, lessThanOrEqualTo(201));
      expect(compressed.summary.endsWith('…'), isTrue);
      expect(compressed.truncated, isTrue);
      expect(compressed.originalLength, 300);
    });

    test('决策与产物引用限量（decisions ≤ 5，artifactRefs ≤ 8）', () {
      final compressed = compressor.compress(TaskExecutionResult(
        status: ExecutionStatus.completed,
        summary: 's',
        decisions: List.generate(9, (i) => 'd$i'),
        artifactRefs: List.generate(12, (i) => 'a$i'),
      ));
      expect(compressed.decisions.length, 5);
      expect(compressed.artifactRefs.length, 8);
    });

    test('空白折叠：多行/多空格合并为单空格', () {
      final compressed = compressor.compress(const TaskExecutionResult(
        status: ExecutionStatus.completed,
        summary: '第一行\n  第二行  第三行',
      ));
      expect(compressed.summary, '第一行 第二行 第三行');
    });
  });

  group('ResultCompressor - 回复组装', () {
    test('composeReply 含摘要、决策与产物', () {
      final compressed = compressor.compress(const TaskExecutionResult(
        status: ExecutionStatus.completed,
        summary: '导出功能已完成',
        decisions: ['选择 JSON Schema v2'],
        artifactRefs: ['diff-789.patch'],
      ));
      final reply = compressor.composeReply(compressed);
      expect(reply, contains('导出功能已完成'));
      expect(reply, contains('关键决策：选择 JSON Schema v2'));
      expect(reply, contains('产物：diff-789.patch'));
    });

    test('composeReply 附加模型提示', () {
      final compressed = compressor.compress(const TaskExecutionResult(
        status: ExecutionStatus.completed,
        summary: '完成',
      ));
      final reply = compressor.composeReply(
        compressed,
        modelNote: '（当前使用备用模型 gemini-pro）',
      );
      expect(reply, contains('备用模型 gemini-pro'));
    });
  });
}
