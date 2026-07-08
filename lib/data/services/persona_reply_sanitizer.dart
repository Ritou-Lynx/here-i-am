enum PersonaReplySegmentType { chat, action }

class PersonaReplySegment {
  final PersonaReplySegmentType type;
  final String text;

  const PersonaReplySegment({
    required this.type,
    required this.text,
  });
}

class PersonaReplySanitizer {
  static const int defaultMaxChatBubbles = 6;
  static const int _targetBubbleRunes = 46;
  static const int _tinyBubbleRunes = 5;

  static final RegExp _thinkingBlock = RegExp(
    r'<(?:think|thinking)\b[^>]*>[\s\S]*?<\/(?:think|thinking)>',
    caseSensitive: false,
  );
  // Unclosed / cut-off think tags (token limit, streaming truncation).
  static final RegExp _unclosedThink = RegExp(
    r'<(?:think|thinking)\b[^>]*>[\s\S]*$',
    caseSensitive: false,
  );
  static final RegExp _leadingReasoningLine = RegExp(
    r'^\s*(?:'
    r'(?:the\s+user|user)\s+(?:said|says|asked|asks|wants|is\s+asking|is\s+saying)'
    r'|i\s+(?:should|need|will|want)\b'
    r'|we\s+need\b'
    r'|(?:thought|thinking|reasoning|analysis)\s*:'
    '|\\u7528\\u6237(?:\\u8bf4|\\u95ee|\\u60f3|\\u5e0c\\u671b)'
    '|\\u6211(?:\\u5e94\\u8be5|\\u9700\\u8981|\\u8981)\\b'
    r')',
    caseSensitive: false,
  );
  static final RegExp _fullItalicLine = RegExp(
    r'^\s*(\*{1,3}|_{1,3})(.+?)\1\s*$',
    dotAll: true,
  );
  static final RegExp _leadingItalic = RegExp(
    r'^\s*(\*{1,3}|_{1,3})(.+?)\1\s*(\S[\s\S]*)$',
    dotAll: true,
  );
  static final RegExp _trailingItalic = RegExp(
    r'^([\s\S]*?\S)\s*(\*{1,3}|_{1,3})(.+?)\2\s*$',
    dotAll: true,
  );
  static final RegExp _inlineItalic = RegExp(
    r'(\*{1,3}|_{1,3})(.+?)\1',
    dotAll: true,
  );

  static List<PersonaReplySegment> splitVisibleReply(String text) {
    final cleaned = stripLeakedReasoning(text).trim();
    if (cleaned.isEmpty) return const [];

    final segments = <PersonaReplySegment>[];
    for (final rawLine in cleaned.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      segments.addAll(_splitLine(line));
    }

    return _mergeAdjacent(segments);
  }

  static String spokenTextOnly(String text) {
    final segments = splitVisibleReply(text);
    if (segments.isEmpty) return stripLeakedReasoning(text).trim();
    return segments
        .where((segment) => segment.type == PersonaReplySegmentType.chat)
        .map((segment) => segment.text)
        .join('\n')
        .trim();
  }

  static List<String> splitChatIntoBubbles(
    String text, {
    int maxBubbles = defaultMaxChatBubbles,
  }) {
    final cleaned = text.trim();
    if (cleaned.isEmpty) return const [];
    if (maxBubbles <= 1 || _shouldKeepChatTogether(cleaned)) {
      return [cleaned];
    }

    final rawPieces = <String>[];
    for (final rawLine in cleaned.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (_shouldKeepChatTogether(line)) {
        rawPieces.add(line);
        continue;
      }
      rawPieces.addAll(_splitLongPieces(_splitSentencePieces(line)));
    }

    final merged = _mergeTinyPieces(rawPieces);
    return _capBubbleCount(merged, maxBubbles);
  }

  static String stripLeakedReasoning(String text) {
    // Strip fully-closed think blocks first, then any unclosed open tag.
    var result = text
        .replaceAll(_thinkingBlock, '')
        .replaceAll(_unclosedThink, '')
        .trim();
    if (result.isEmpty) return result;

    final lines = result.split(RegExp(r'\r?\n'));
    var firstVisible = 0;
    while (firstVisible < lines.length) {
      final line = lines[firstVisible].trim();
      if (line.isEmpty) {
        firstVisible++;
        continue;
      }
      if (!_leadingReasoningLine.hasMatch(line)) break;
      firstVisible++;
    }
    if (firstVisible > 0 && firstVisible < lines.length) {
      result = lines.skip(firstVisible).join('\n').trim();
    }

    return result;
  }

  static List<PersonaReplySegment> _splitLine(String line) {
    final inlineSegments = _splitInlineItalicActions(line);
    if (inlineSegments != null) return inlineSegments;

    final fullItalic = _fullItalicLine.firstMatch(line);
    if (fullItalic != null) {
      final action = fullItalic.group(2)!.trim();
      if (_looksLikeAction(action)) {
        return [
          PersonaReplySegment(
            type: PersonaReplySegmentType.action,
            text: _wrapAction(action),
          ),
        ];
      }
    }

    final leadingItalic = _leadingItalic.firstMatch(line);
    if (leadingItalic != null) {
      final action = leadingItalic.group(2)!.trim();
      final chat = leadingItalic.group(3)!.trim();
      if (_looksLikeAction(action)) {
        return [
          PersonaReplySegment(
            type: PersonaReplySegmentType.action,
            text: _wrapAction(action),
          ),
          PersonaReplySegment(
            type: PersonaReplySegmentType.chat,
            text: chat,
          ),
        ];
      }
    }

    final trailingItalic = _trailingItalic.firstMatch(line);
    if (trailingItalic != null) {
      final chat = trailingItalic.group(1)!.trim();
      final action = trailingItalic.group(3)!.trim();
      if (_looksLikeAction(action)) {
        return [
          PersonaReplySegment(
            type: PersonaReplySegmentType.chat,
            text: chat,
          ),
          PersonaReplySegment(
            type: PersonaReplySegmentType.action,
            text: _wrapAction(action),
          ),
        ];
      }
    }

    return [
      PersonaReplySegment(
        type: PersonaReplySegmentType.chat,
        text: line,
      ),
    ];
  }

  static List<PersonaReplySegment>? _splitInlineItalicActions(String line) {
    final segments = <PersonaReplySegment>[];
    final chatBuffer = StringBuffer();
    var cursor = 0;
    var foundAction = false;

    void flushChat() {
      final chat = chatBuffer.toString().trim();
      if (chat.isEmpty) {
        chatBuffer.clear();
        return;
      }
      segments.add(PersonaReplySegment(
        type: PersonaReplySegmentType.chat,
        text: chat,
      ));
      chatBuffer.clear();
    }

    for (final match in _inlineItalic.allMatches(line)) {
      chatBuffer.write(line.substring(cursor, match.start));
      final raw = match.group(0)!;
      final candidate = match.group(2)!.trim();
      if (_looksLikeAction(candidate)) {
        flushChat();
        segments.add(PersonaReplySegment(
          type: PersonaReplySegmentType.action,
          text: _wrapAction(candidate),
        ));
        foundAction = true;
      } else {
        chatBuffer.write(raw);
      }
      cursor = match.end;
    }

    if (!foundAction) return null;

    chatBuffer.write(line.substring(cursor));
    flushChat();
    return segments;
  }

  static bool _shouldKeepChatTogether(String text) {
    if (text.contains('```')) return true;
    if (RegExp(r'`[^`]+`').hasMatch(text)) return true;
    if (RegExp(r'https?:\/\/\S+').hasMatch(text)) return true;
    if (RegExp(r'\[[^\]]+\]\([^)]+\)').hasMatch(text)) return true;
    final lines = text.split(RegExp(r'\r?\n'));
    return lines.any((line) {
      final trimmed = line.trimLeft();
      return RegExp(r'^(?:[-*+]\s+|\d+[.)]\s+|>\s+|#{1,6}\s+|\|)')
          .hasMatch(trimmed);
    });
  }

  static List<String> _splitSentencePieces(String text) {
    final pieces = <String>[];
    final buffer = StringBuffer();
    final runes = text.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      final char = String.fromCharCode(runes[i]);
      buffer.write(char);
      if (!_isSentenceBoundary(char)) continue;

      while (i + 1 < runes.length) {
        final next = String.fromCharCode(runes[i + 1]);
        if (!_isClosingPunctuation(next)) break;
        buffer.write(next);
        i++;
      }

      final piece = buffer.toString().trim();
      if (piece.isNotEmpty) pieces.add(piece);
      buffer.clear();
    }

    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) pieces.add(tail);
    return pieces.isEmpty ? [text.trim()] : pieces;
  }

  static List<String> _splitLongPieces(List<String> pieces) {
    final result = <String>[];
    for (final piece in pieces) {
      if (piece.runes.length <= _targetBubbleRunes * 2 ||
          !_hasSoftBoundary(piece)) {
        result.add(piece);
        continue;
      }
      result.addAll(_splitBySoftBoundary(piece));
    }
    return result;
  }

  static List<String> _splitBySoftBoundary(String text) {
    final pieces = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(char);
      if (!_isSoftBoundary(char) ||
          buffer.toString().trim().runes.length < _targetBubbleRunes) {
        continue;
      }
      final piece = buffer.toString().trim();
      if (piece.isNotEmpty) pieces.add(piece);
      buffer.clear();
    }
    final tail = buffer.toString().trim();
    if (tail.isNotEmpty) pieces.add(tail);
    return pieces;
  }

  static List<String> _mergeTinyPieces(List<String> pieces) {
    final result = <String>[];
    for (final raw in pieces) {
      final piece = raw.trim();
      if (piece.isEmpty) continue;
      if (piece.runes.length <= _tinyBubbleRunes && result.isNotEmpty) {
        result[result.length - 1] = _joinAdjacentText(result.last, piece);
        continue;
      }
      result.add(piece);
    }
    return result;
  }

  static List<String> _capBubbleCount(List<String> pieces, int maxBubbles) {
    if (pieces.length <= maxBubbles) return pieces;
    final result = pieces.take(maxBubbles - 1).toList();
    result.add(_joinTextPieces(pieces.skip(maxBubbles - 1)));
    return result;
  }

  static String _joinTextPieces(Iterable<String> pieces) {
    var result = '';
    for (final raw in pieces) {
      final piece = raw.trim();
      if (piece.isEmpty) continue;
      result = result.isEmpty ? piece : _joinAdjacentText(result, piece);
    }
    return result;
  }

  static String _joinAdjacentText(String left, String right) {
    if (_needsSpaceBetween(left, right)) return '$left $right';
    return '$left$right';
  }

  static bool _needsSpaceBetween(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    final leftLast = String.fromCharCode(left.runes.last);
    final rightFirst = String.fromCharCode(right.runes.first);
    return RegExp(r'[A-Za-z0-9\)\]]').hasMatch(leftLast) &&
        RegExp(r'[A-Za-z0-9\(\[]').hasMatch(rightFirst);
  }

  static bool _isSentenceBoundary(String char) =>
      RegExp(r'[。！？!?…]+').hasMatch(char);

  static bool _isClosingPunctuation(String char) =>
      RegExp(r'[”’」』）)]').hasMatch(char);

  static bool _hasSoftBoundary(String text) =>
      text.contains(RegExp(r'[，,；;、]'));

  static bool _isSoftBoundary(String char) => RegExp(r'[，,；;、]').hasMatch(char);

  static List<PersonaReplySegment> _mergeAdjacent(
    List<PersonaReplySegment> segments,
  ) {
    final merged = <PersonaReplySegment>[];
    for (final segment in segments) {
      if (segment.text.trim().isEmpty) continue;
      if (merged.isNotEmpty && merged.last.type == segment.type) {
        final previous = merged.removeLast();
        merged.add(PersonaReplySegment(
          type: previous.type,
          text: '${previous.text}\n${segment.text}',
        ));
      } else {
        merged.add(segment);
      }
    }
    return merged;
  }

  static bool _looksLikeAction(String text) {
    final normalized = text.trim();
    if (normalized.length < 2 || normalized.length > 240) return false;
    if (RegExp(r'["\u201c\u201d\u300c\u300d]').hasMatch(normalized)) {
      return false;
    }

    final lower = normalized.toLowerCase();
    final englishAction = RegExp(
      r'\b(?:smiles?|laughs?|nods?|shakes?|sighs?|looks?|leans?|reaches?|'
      r'touches?|holds?|hugs?|steps?|sits?|stands?|tilts?|whispers?|'
      r'pauses?|breathes?|glances?|stares?|blinks?)\b',
    ).hasMatch(lower);
    if (englishAction) return true;

    return RegExp(
      '(\\u5979|\\u4ed6|\\u6211|ta|TA|'
      '\\u8f7b\\u8f7b|\\u6162\\u6162|\\u9760\\u8fd1|'
      '\\u51d1\\u8fd1|\\u770b\\u7740|\\u671b\\u7740|'
      '\\u76ef\\u7740|\\u7b11|\\u53f9|\\u70b9\\u5934|'
      '\\u6447\\u5934|\\u7728\\u773c|\\u5782\\u773c|'
      '\\u62ac\\u773c|\\u4f4e\\u5934|\\u6b6a\\u5934|'
      '\\u504f\\u5934|\\u4f38\\u624b|\\u63e1\\u4f4f|'
      '\\u62b1\\u4f4f|\\u62cd\\u62cd|\\u6478\\u6478|'
      '\\u62c9\\u4f4f|\\u5750\\u4e0b|\\u7ad9\\u8d77|'
      '\\u8d70\\u8fd1|\\u6c89\\u9ed8|\\u505c\\u987f|'
      '\\u547c\\u5438|\\u76b1\\u7709)',
    ).hasMatch(normalized);
  }

  /// Split the chat portion of a reply into individual speech bubbles.
  ///
  /// A paragraph break (double newline or more) separates bubbles, e.g.:
  /// "第一段话\n\n第二段话" → ["第一段话", "第二段话"].
  /// Single newlines within a bubble are preserved as soft line breaks.
  static List<String> splitChatIntoBubbles(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return [];
    return trimmed
        .split(RegExp(r'\n\s*\n'))
        .map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toList();
  }

  static String _wrapAction(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('*') && trimmed.endsWith('*')) return trimmed;
    return '*$trimmed*';
  }
}
