import 'package:memex/utils/jieba.dart';

class QueryMatch {
  final int score;
  final List<int> indexes;

  const QueryMatch({
    required this.score,
    required this.indexes,
  });

  bool get matched => score > 0;
}

class QueryMatcher {
  QueryMatcher._();

  static Future<String> tokenizeForIndex(String text) async {
    if (text.isEmpty) return text;
    await JiebaSegmenter.instance.ensureLoaded();
    if (JiebaSegmenter.instance.isLoaded && _containsCjk(text)) {
      return JiebaSegmenter.instance.cutForSearch(text).join(' ');
    }
    return _tokenizeFallback(text);
  }

  static Future<String> tokenizeForFtsQuery(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return trimmed;

    await JiebaSegmenter.instance.ensureLoaded();
    if (JiebaSegmenter.instance.isLoaded && _containsCjk(trimmed)) {
      final allCjkTokens = <String>[];
      final filteredTokens = <String>[];
      for (final word in JiebaSegmenter.instance.cut(trimmed)) {
        final token = word.trim();
        if (token.isEmpty) continue;
        if (_containsCjk(token)) {
          allCjkTokens.add(token);
          if (_cjkStopwords.contains(token)) continue;
          filteredTokens.add('"$token"');
        } else {
          final clean = token.replaceAll(RegExp(r'[^\w\-]'), '').trim();
          if (clean.length >= 2) {
            filteredTokens.add('"$clean"*');
          }
        }
      }
      if (filteredTokens.isNotEmpty) return filteredTokens.join(' OR ');
      // All tokens were stopwords — try emotion/relationship keywords first.
      for (final token in allCjkTokens) {
        if (_emotionKeywords.contains(token)) {
          filteredTokens.add('"$token"');
        }
      }
      if (filteredTokens.isNotEmpty) return filteredTokens.join(' OR ');
      // Final fallback: use the longest CJK tokens.
      final fallback = allCjkTokens.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final top = fallback.take(3).map((t) => '"$t"').toList();
      return top.isEmpty ? '' : top.join(' OR ');
    }

    return _tokenizeQueryFallback(trimmed);
  }

  static Future<List<String>> terms(String query, {int maxTerms = 12}) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    await JiebaSegmenter.instance.ensureLoaded();
    final tokens = <String>[];
    if (JiebaSegmenter.instance.isLoaded && _containsCjk(trimmed)) {
      for (final token in JiebaSegmenter.instance.cut(trimmed)) {
        _addToken(tokens, token);
      }
    } else {
      final buffer = StringBuffer();
      for (var i = 0; i < trimmed.length; i++) {
        final code = trimmed.codeUnitAt(i);
        if (_isCjk(code)) {
          _flushAscii(tokens, buffer);
          tokens.add(String.fromCharCode(code));
        } else if (_isAsciiWordCode(code)) {
          buffer.writeCharCode(code);
        } else {
          _flushAscii(tokens, buffer);
        }
      }
      _flushAscii(tokens, buffer);
    }

    final seen = <String>{};
    final unique = <String>[];
    for (final token in tokens) {
      if (seen.add(token)) unique.add(token);
      if (unique.length >= maxTerms) break;
    }
    return unique;
  }

  static Future<QueryMatch> match(
    String query,
    String text, {
    Iterable<String> extraTerms = const [],
    int phraseBoost = 5,
  }) async {
    final lowerText = text.toLowerCase();
    final normalizedQuery = query.trim().toLowerCase();
    final allTerms = <String>{
      ...await terms(query),
      ...extraTerms
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty),
    }.toList();
    if (normalizedQuery.isEmpty && allTerms.isEmpty) {
      return const QueryMatch(score: 0, indexes: []);
    }

    var score = 0;
    final indexes = <int>[];
    if (normalizedQuery.isNotEmpty) {
      final phraseIdx = lowerText.indexOf(normalizedQuery);
      if (phraseIdx >= 0) {
        score += phraseBoost + allTerms.length;
        indexes.add(phraseIdx);
      }
    }
    for (final term in allTerms) {
      final idx = lowerText.indexOf(term);
      if (idx >= 0) {
        score += term.length > 1 ? 2 : 1;
        indexes.add(idx);
      }
    }
    indexes.sort();
    return QueryMatch(score: score, indexes: indexes);
  }

  static String snippet({
    required String content,
    required List<int> matchIndexes,
    int maxChars = 800,
    int contextRadius = 240,
  }) {
    if (content.length <= maxChars) return content;
    if (matchIndexes.isEmpty) {
      return '${content.substring(0, maxChars)}...';
    }

    final sorted = [...matchIndexes]..sort();
    final windows = <({int start, int end})>[];
    for (final idx in sorted) {
      final start = (idx - contextRadius).clamp(0, content.length);
      final end = (idx + contextRadius).clamp(0, content.length);
      if (windows.isNotEmpty && start <= windows.last.end + 80) {
        final last = windows.removeLast();
        windows.add((start: last.start, end: end > last.end ? end : last.end));
      } else {
        windows.add((start: start, end: end));
      }
    }

    final parts = <String>[];
    var used = 0;
    for (final window in windows) {
      if (used >= maxChars) break;
      final remaining = maxChars - used;
      final text = content.substring(window.start, window.end);
      final clipped =
          text.length > remaining ? '${text.substring(0, remaining)}...' : text;
      parts.add(
        '${window.start > 0 ? '...' : ''}${clipped.replaceAll('\n', ' ')}${window.end < content.length ? '...' : ''}',
      );
      used += clipped.length;
    }

    return parts.join('\n...\n');
  }

  static bool _isCjk(int code) {
    return (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0xF900 && code <= 0xFAFF) ||
        (code >= 0x3040 && code <= 0x30FF) ||
        (code >= 0xFF00 && code <= 0xFFEF) ||
        (code >= 0x3000 && code <= 0x303F);
  }

  static bool _containsCjk(String text) {
    for (var i = 0; i < text.length; i++) {
      if (_isCjk(text.codeUnitAt(i))) return true;
    }
    return false;
  }

  static bool _isAsciiWordCode(int code) {
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x61 && code <= 0x7A) ||
        code == 0x5F ||
        code == 0x2D;
  }

  static String _tokenizeFallback(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (_isCjk(code)) {
        if (buffer.isNotEmpty && !buffer.toString().endsWith(' ')) {
          buffer.write(' ');
        }
        buffer.writeCharCode(code);
        buffer.write(' ');
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString().trim();
  }

  static String _tokenizeQueryFallback(String query) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < query.length; i++) {
      final code = query.codeUnitAt(i);
      if (_isCjk(code)) {
        _flushFtsAscii(tokens, buffer);
        tokens.add(String.fromCharCode(code));
      } else if (_isAsciiWordCode(code)) {
        buffer.writeCharCode(code);
      } else {
        _flushFtsAscii(tokens, buffer);
      }
    }
    _flushFtsAscii(tokens, buffer);
    return tokens.join(' OR ');
  }

  static void _flushFtsAscii(List<String> tokens, StringBuffer buffer) {
    if (buffer.isEmpty) return;
    tokens.add('"${buffer.toString()}"*');
    buffer.clear();
  }

  static void _flushAscii(List<String> tokens, StringBuffer buffer) {
    if (buffer.isEmpty) return;
    _addToken(tokens, buffer.toString());
    buffer.clear();
  }

  static void _addToken(List<String> tokens, String token) {
    final trimmed = token.trim().toLowerCase();
    if (trimmed.isEmpty) return;
    if (!_containsCjk(trimmed) && trimmed.length < 2) return;
    tokens.add(trimmed);
  }

  static const _cjkStopwords = <String>{
    '我', '你', '她', '他', '它', '们', '的', '了', '吗', '呢', '吧', '啊',
    '哦', '嘛', '呀', '哈', '嗯', '噢', '哎', '唉',
    '是', '在', '有', '没', '也', '就', '都', '还', '会', '要', '能',
    '可', '可以', '这', '那', '什么', '怎么', '哪', '谁', '多', '几',
    '和', '跟', '与', '把', '被', '让', '给', '对', '从', '到', '向',
    '很', '太', '真', '好', '过', '着', '得', '地',
    '个', '些', '种', '点', '下', '上', '里', '天', '来', '去',
    '起', '出', '回', '做', '说', '看', '想', '知道',
    '不', '用', '加', '又', '再', '别', '只', '才', '已', '而', '且',
    '但', '或', '如果', '虽然', '因为', '所以', '然后', '但是',
    '时候', '东西', '事情', '一个', '自己', '什', '么',
    '记得', '记', '时', '候', '哪天', '一下', '一点',
    '今天', '昨天', '明天', '现在', '之前', '以后',
    // 高频泛化词——在记忆召回查询中几乎不携带区分度
    '问题', '讨论', '选择', '直接', '觉得', '告诉', '其实',
    '完全', '根本', '到底', '究竟', '真的', '确实', '好像',
    // 保留情感/关系词不在停用词里（眼泪、拒绝、在乎等本身有语义）
  };

  // 情感/关系关键词白名单——在 FTS 停用词过滤后补充进查询，
  // 避免"别管眼泪""不在乎"这类情绪句因所有词都被过滤而召回全空。
  static const _emotionKeywords = <String>{
    '眼泪', '哭', '难过', '伤心', '生气', '愤怒', '委屈', '害怕', '担心',
    '开心', '高兴', '快乐', '幸福', '感动', '温暖', '期待', '失望',
    '在乎', '拒绝', '接受', '允许', '答应', '拒', '不理', '不管',
    '亲', '吻', '抱', '碰', '触', '抚摸', '靠近', '离开',
    '想你', '爱你', '喜欢', '讨厌', '嫌弃', '需要', '依赖',
    '坚持', '放弃', '忍', '憋', '忍不住',
    '界限', '底线', '松动', '破防', '让步',
  };

  /// Return content keywords suitable for substring fallback search.
  /// Jieba-segmented, stopword-filtered, deduplicated, max [limit] tokens.
  static Future<List<String>> contentKeywords(String query,
      {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    await JiebaSegmenter.instance.ensureLoaded();
    final result = <String>[];
    final seen = <String>{};
    if (JiebaSegmenter.instance.isLoaded && _containsCjk(trimmed)) {
      final allTokens = <String>[];
      for (final word in JiebaSegmenter.instance.cut(trimmed)) {
        final token = word.trim();
        if (token.isEmpty || token.length < 2) continue;
        allTokens.add(token);
        if (_cjkStopwords.contains(token)) continue;
        if (seen.add(token)) result.add(token);
        if (result.length >= limit) break;
      }
      // If all tokens were stopwords, try emotion/relationship keywords.
      if (result.isEmpty) {
        for (final token in allTokens) {
          if (_emotionKeywords.contains(token) && seen.add(token)) {
            result.add(token);
            if (result.length >= limit) break;
          }
        }
      }
    } else {
      for (final word in trimmed.split(RegExp(r'\s+'))) {
        final clean = word.replaceAll(RegExp(r'[^\w\-]'), '').toLowerCase();
        if (clean.length < 2) continue;
        if (seen.add(clean)) result.add(clean);
        if (result.length >= limit) break;
      }
    }
    return result;
  }
}
