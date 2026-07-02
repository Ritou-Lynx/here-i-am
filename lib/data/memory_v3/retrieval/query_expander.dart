import 'intent_classifier.dart';

enum QueryExpansionStrategy {
  original,
  expanded,
  relaxed,
}

class QueryVariant {
  const QueryVariant({
    required this.query,
    required this.strategy,
    this.terms = const [],
  });

  final String query;
  final QueryExpansionStrategy strategy;
  final List<String> terms;
}

class QueryExpansionPlan {
  const QueryExpansionPlan({
    required this.originalQuery,
    required this.intent,
    required this.variants,
  });

  final String originalQuery;
  final QueryIntent intent;
  final List<QueryVariant> variants;
}

/// Lightweight query expansion for Memory V3 retrieval.
///
/// This is Phase 3 Lite: it improves keyword recall before embeddings exist.
/// The expander is intentionally deterministic so we can benchmark it later
/// against a real vector provider.
class QueryExpander {
  const QueryExpander._();

  static const int _maxExpandedTerms = 18;

  static QueryExpansionPlan expand(
    String query, {
    QueryIntent? intent,
  }) {
    final normalized = _normalize(query);
    final resolvedIntent = intent ?? IntentClassifier.classify(normalized);
    if (normalized.isEmpty) {
      return QueryExpansionPlan(
        originalQuery: normalized,
        intent: resolvedIntent,
        variants: const [],
      );
    }

    final variants = <QueryVariant>[
      QueryVariant(
        query: normalized,
        strategy: QueryExpansionStrategy.original,
        terms: const [],
      ),
    ];

    final expandedTerms = _expandedTermsFor(normalized, resolvedIntent);
    if (expandedTerms.isNotEmpty) {
      final expandedQuery = _joinUnique([normalized, ...expandedTerms]);
      if (expandedQuery != normalized) {
        variants.add(QueryVariant(
          query: expandedQuery,
          strategy: QueryExpansionStrategy.expanded,
          terms: expandedTerms,
        ));
      }
    }

    final relaxedTerms = _relaxedTermsFor(normalized, expandedTerms);
    if (relaxedTerms.isNotEmpty) {
      final relaxedQuery = _joinUnique(relaxedTerms);
      final existing = variants.map((v) => v.query).toSet();
      if (!existing.contains(relaxedQuery)) {
        variants.add(QueryVariant(
          query: relaxedQuery,
          strategy: QueryExpansionStrategy.relaxed,
          terms: relaxedTerms,
        ));
      }
    }

    return QueryExpansionPlan(
      originalQuery: normalized,
      intent: resolvedIntent,
      variants: variants,
    );
  }

  static List<String> _expandedTermsFor(String query, QueryIntent intent) {
    final terms = <String>[];

    for (final group in _synonymGroups) {
      if (_matchesAny(query, group.triggers)) {
        terms.addAll(group.expansions);
      }
    }

    switch (intent) {
      case QueryIntent.progressCheck:
        terms.addAll(['任务', '待办', '计划', '进度', '完成', '安排']);
      case QueryIntent.emotionRecall:
        terms.addAll(['心情', '情绪', '感受', '状态', '开心', '难过', '焦虑']);
      case QueryIntent.reflection:
        terms.addAll(['最近', '回顾', '总结', '变化', '收获', '复盘']);
      case QueryIntent.factLookup:
        break;
    }

    return _uniqueTerms(terms, maxTerms: _maxExpandedTerms);
  }

  static List<String> _relaxedTermsFor(
    String query,
    List<String> expandedTerms,
  ) {
    final terms = <String>[];
    terms.addAll(_knownTermsIn(query));
    terms.addAll(_asciiTermsIn(query));

    if (terms.isEmpty) {
      terms.addAll(_cjkChunks(query));
    }

    terms.addAll(expandedTerms.take(8));
    return _uniqueTerms(terms, maxTerms: 12);
  }

  static List<String> _knownTermsIn(String query) {
    final terms = <String>[];
    for (final term in _knownTerms) {
      if (query.contains(term)) terms.add(term);
    }
    terms.sort((a, b) => b.length.compareTo(a.length));
    return terms;
  }

  static List<String> _asciiTermsIn(String query) {
    return RegExp(r'[A-Za-z0-9_\-]{2,}')
        .allMatches(query)
        .map((m) => m.group(0)!.toLowerCase())
        .where((term) => !_stopTerms.contains(term))
        .toList();
  }

  static List<String> _cjkChunks(String query) {
    final chunks = RegExp(r'[\u3400-\u9fff]{2,}')
        .allMatches(query)
        .map((m) => m.group(0)!)
        .where((chunk) => !_stopTerms.contains(chunk))
        .toList();
    if (chunks.isEmpty) return const [];
    chunks.sort((a, b) => a.length.compareTo(b.length));
    return chunks.take(4).toList();
  }

  static bool _matchesAny(String query, Iterable<String> terms) {
    for (final term in terms) {
      if (query.contains(term)) return true;
    }
    return false;
  }

  static String _normalize(String query) {
    return query.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _joinUnique(Iterable<String> terms) {
    return _uniqueTerms(terms).join(' ');
  }

  static List<String> _uniqueTerms(
    Iterable<String> terms, {
    int maxTerms = 32,
  }) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in terms) {
      final term = raw.trim();
      if (term.isEmpty || _stopTerms.contains(term)) continue;
      if (seen.add(term)) result.add(term);
      if (result.length >= maxTerms) break;
    }
    return result;
  }

  static final List<_SynonymGroup> _synonymGroups = [
    _SynonymGroup(
      triggers: ['花钱', '消费', '支出', '开销', '账单', '多少钱', '花了', '付款', '支付'],
      expansions: ['消费', '支出', '花费', '开销', '账单', '付款', '支付', '价格'],
    ),
    _SynonymGroup(
      triggers: ['买', '购买', '下单', '入手', '采购'],
      expansions: ['购买', '买了', '下单', '入手', '采购', '消费', '付款'],
    ),
    _SynonymGroup(
      triggers: ['吃', '饭', '早餐', '早饭', '午饭', '午餐', '晚饭', '晚餐', '外卖', '餐厅'],
      expansions: ['吃', '吃了', '饭', '早餐', '午餐', '晚餐', '外卖', '餐厅', '食物'],
    ),
    _SynonymGroup(
      triggers: ['喝', '咖啡', '奶茶', '饮料', '拿铁'],
      expansions: ['喝', '咖啡', '奶茶', '饮料', '拿铁', '美式', '茶'],
    ),
    _SynonymGroup(
      triggers: ['睡', '睡眠', '睡觉', '昨晚', '休息', '熬夜'],
      expansions: ['睡眠', '睡觉', '休息', '昨晚', '今天', '最近一次', '熬夜'],
    ),
    _SynonymGroup(
      triggers: ['运动', '锻炼', '跑步', '健身', '步数', '身体', '健康'],
      expansions: ['运动', '锻炼', '跑步', '健身', '步数', '身体', '健康'],
    ),
    _SynonymGroup(
      triggers: ['心情', '情绪', '感受', '感觉', '状态', '压力', '焦虑'],
      expansions: ['心情', '情绪', '感受', '感觉', '状态', '压力', '焦虑'],
    ),
    _SynonymGroup(
      triggers: ['任务', '待办', '计划', '安排', '进度', '完成', '做完', '提醒', '日程'],
      expansions: ['任务', '待办', '计划', '安排', '进度', '完成', '提醒', '日程'],
    ),
    _SynonymGroup(
      triggers: ['图片', '照片', '截图', '识图', '画面', '相册'],
      expansions: ['图片', '照片', '截图', '识图', '画面', '相册'],
    ),
    _SynonymGroup(
      triggers: ['书', '阅读', '读书', '小说', '文章', '笔记', '划线'],
      expansions: ['书', '阅读', '读书', '小说', '文章', '笔记', '划线'],
    ),
    _SynonymGroup(
      triggers: ['最近', '这周', '这段时间', '这个月', '以来', '回顾', '总结'],
      expansions: ['最近', '近期', '这周', '这个月', '回顾', '总结', '复盘'],
    ),
  ];

  static final Set<String> _knownTerms = {
    for (final group in _synonymGroups) ...group.triggers,
    for (final group in _synonymGroups) ...group.expansions,
    '昨天',
    '今天',
    '前天',
    '上次',
    '之前',
  };

  static const Set<String> _stopTerms = {
    '我',
    '你',
    '他',
    '她',
    '我们',
    '你们',
    '他们',
    '有没有',
    '是否',
    '什么',
    '哪',
    '哪天',
    '怎么',
    '怎么样',
    '如何',
    '记得',
    '记不记得',
    '记过',
    '帮我',
    '告诉我',
    '一下',
    '那个',
    '这个',
    '那次',
    '那天',
    '吗',
    '呢',
    '啊',
    '吧',
    '的',
    '了',
    '着',
    '过',
    '和',
    '跟',
    '在',
    '是',
    '有',
    '没有',
    '想',
    '问',
    '查',
    '查一下',
    '帮',
    '看看',
    '关于',
  };
}

class _SynonymGroup {
  const _SynonymGroup({
    required this.triggers,
    required this.expansions,
  });

  final List<String> triggers;
  final List<String> expansions;
}
