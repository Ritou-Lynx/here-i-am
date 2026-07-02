/// Lightweight intent classifier for memory-card queries.
///
/// Classifies a user query into one of four intents so the retrieval layer
/// can weight results appropriately. Uses keyword matching for Chinese;
/// fast, no model dependency.
///
/// Intents:
/// - [QueryIntent.factLookup]: "我昨天吃了什么" — specific fact retrieval
/// - [QueryIntent.progressCheck]: "那个任务做完了吗" — task/plan status
/// - [QueryIntent.reflection]: "最近有什么收获" — open-ended review
/// - [QueryIntent.emotionRecall]: "那天我开心吗" — emotion-focused
library;

enum QueryIntent {
  factLookup,
  progressCheck,
  reflection,
  emotionRecall,
}

class IntentClassifier {
  const IntentClassifier._();

  // ── Fact lookup ──────────────────────────────────────────────
  static final _factPatterns = [
    '什么', '谁', '哪', '怎么', '为什么', '多少', '多少钱', '几点', '几时',
    '什么时候', '在哪里', '在哪', '有没有', '是否', '是.?的', '告诉我',
    '记得', '记不记得', '知道', '知不知道', '上次', '上一次', '之前',
    '前几天', '前几周', '上个', '上周', '上个月', '昨天', '今天', '那天',
    '吃过', '吃了', '去过', '做了', '买了', '花了', '用了', '看了',
    '说过', '提起', '提到', '聊过',
  ];

  // ── Progress check ───────────────────────────────────────────
  static final _progressPatterns = [
    '做完', '完成了', '进度', '做到', '进行得', '怎么样.?了', '好了吗',
    '完了吗', '做了吗', '有没有做', '还没', '记得做', '别忘了',
    '任务', '计划', '待办', '日程', '安排',
  ];

  // ── Reflection ───────────────────────────────────────────────
  static final _reflectionPatterns = [
    '最近', '这段', '这周', '这个月', '这几个月', '今年', '以来',
    '总结', '回顾', '复盘', '梳理', '整理', '归纳',
    '收获', '变化', '进步', '成长', '学到了', '学到了什么',
    '有什么', '有哪些', '怎么样', '如何',
  ];

  // ── Emotion ──────────────────────────────────────────────────
  static final _emotionPatterns = [
    '开心', '难过', '伤心', '生气', '愤怒', '焦虑', '紧张',
    '激动', '兴奋', '感动', '失望', '沮丧', '烦躁', '平静',
    '情绪', '心情', '感觉', '感受', '心态', '状态',
    '那天我.*吗', '我当时.*吗',
  ];

  /// Classify [query] into one of the four intents.
  static QueryIntent classify(String query) {
    final q = query.trim();
    if (q.isEmpty) return QueryIntent.factLookup;

    // Order matters: progress check is more specific than fact lookup
    if (_matchesAny(q, _progressPatterns)) return QueryIntent.progressCheck;
    if (_matchesAny(q, _emotionPatterns)) return QueryIntent.emotionRecall;
    if (_matchesAny(q, _reflectionPatterns)) return QueryIntent.reflection;
    if (_matchesAny(q, _factPatterns)) return QueryIntent.factLookup;

    // Default: fact lookup (most common)
    return QueryIntent.factLookup;
  }

  /// Human-readable label for UI/debugging.
  static String label(QueryIntent intent) => switch (intent) {
        QueryIntent.factLookup => '事实查询',
        QueryIntent.progressCheck => '进度检查',
        QueryIntent.reflection => '回顾反思',
        QueryIntent.emotionRecall => '情绪回忆',
      };

  static bool _matchesAny(String query, List<String> patterns) {
    for (final p in patterns) {
      if (RegExp(p).hasMatch(query)) return true;
    }
    return false;
  }
}
