/// 结果压缩器（W5 Phase 2）。
///
/// 把 Agent 长输出压缩为：一句话摘要 + 关键决策 + 产物引用。
/// 纯规则、确定性、无 LLM 调用；写回 Memory V3 的是压缩版，
/// 完整产物进 Artifact 表按需查看（W5 § 2.4 压缩策略）。
library;

import 'task_router.dart';

/// 压缩结果。
class CompressedResult {
  /// 一句话摘要（超过上限时截断加省略号）。
  final String summary;

  /// 关键决策（最多 [maxDecisions] 条）。
  final List<String> decisions;

  /// 产物引用（最多 [maxArtifactRefs] 条）。
  final List<String> artifactRefs;

  /// 摘要是否被截断。
  final bool truncated;

  /// 原始摘要长度（压缩前）。
  final int originalLength;

  const CompressedResult({
    required this.summary,
    required this.decisions,
    required this.artifactRefs,
    required this.truncated,
    required this.originalLength,
  });
}

/// 结果压缩器：长输出 → 摘要 + 决策 + 产物引用。
class ResultCompressor {
  static const int defaultMaxSummaryLength = 200;
  static const int maxDecisions = 5;
  static const int maxArtifactRefs = 8;

  /// 压缩一个执行结果。
  CompressedResult compress(
    TaskExecutionResult result, {
    int maxSummaryLength = defaultMaxSummaryLength,
  }) {
    final raw = result.summary.trim().replaceAll(RegExp(r'\s+'), ' ');
    final originalLength = raw.length;
    var truncated = false;
    var summary = raw;

    if (summary.length > maxSummaryLength) {
      summary = '${summary.substring(0, maxSummaryLength).trimRight()}…';
      truncated = true;
    }

    final decisions = result.decisions.take(maxDecisions).toList();
    final artifactRefs = result.artifactRefs.take(maxArtifactRefs).toList();

    return CompressedResult(
      summary: summary,
      decisions: decisions,
      artifactRefs: artifactRefs,
      truncated: truncated,
      originalLength: originalLength,
    );
  }

  /// 组装给用户的回复文本。
  ///
  /// [modelNote] 非空时附加模型提示（fallback 时由编排器传入）。
  String composeReply(
    CompressedResult compressed, {
    String? modelNote,
  }) {
    final buffer = StringBuffer(compressed.summary);
    if (compressed.decisions.isNotEmpty) {
      buffer.write('\n关键决策：${compressed.decisions.join('；')}');
    }
    if (compressed.artifactRefs.isNotEmpty) {
      buffer.write('\n产物：${compressed.artifactRefs.join('、')}');
    }
    if (modelNote != null && modelNote.isNotEmpty) {
      buffer.write('\n$modelNote');
    }
    return buffer.toString();
  }
}
