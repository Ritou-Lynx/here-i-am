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
  static final RegExp _thinkingBlock = RegExp(
    r'<(?:think|thinking)\b[^>]*>[\s\S]*?<\/(?:think|thinking)>',
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

  static String stripLeakedReasoning(String text) {
    var result = text.replaceAll(_thinkingBlock, '').trim();
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

  static String _wrapAction(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('*') && trimmed.endsWith('*')) return trimmed;
    return '*$trimmed*';
  }
}
