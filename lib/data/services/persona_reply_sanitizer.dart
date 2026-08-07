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
  static final RegExp _visibleReplyBlock = RegExp(
    r'<visible_reply\b[^>]*>([\s\S]*?)<\/visible_reply>',
    caseSensitive: false,
  );
  static final RegExp _visibleReplyOpen = RegExp(
    r'<visible_reply\b[^>]*>',
    caseSensitive: false,
  );
  static final RegExp _visibleReplyClose = RegExp(
    r'<\/visible_reply>',
    caseSensitive: false,
  );
  static final RegExp _englishResponsePlanning = RegExp(
    r"\b(?:i\s+(?:should|need|must|will|want\s+to|ought\s+to)|"
    r'we\s+need\s+to)\b[\s\S]{0,160}\b(?:respond|reply|acknowledge|ask|'
    r'clarify|address|mention|express|show|avoid|focus|figure\s+out|deliver|'
    r'keep\s+my\s+reasoning|visible\s+response|dialogue|'
    r'use\s+(?:chinese|english)|stay\s+in\s+character)\b',
    caseSensitive: false,
  );
  static final RegExp _englishAnalyticalOpener = RegExp(
    r"^(?:there(?:'s|\s+is|\s+are)\b|i(?:'m|\s+am)\s+noticing|"
    r'looking\s+at\b|given\s+the\b|based\s+on\b|it\s+seems\b|'
    r'let\s+me\b|so\s+the\b|this\s+means\b|the\s+(?:key|main|real)\b|'
    r"what(?:'s|\s+is)\s+(?:happening|going\s+on)|"
    r'both\s+\w+\s+(?:actually|records?|entries))',
    caseSensitive: false,
  );
  static final RegExp _chineseMetaReference = RegExp(
    r'(?:用户|这段对话|聊天记录|对话发生在|身份自然地回应|以.+?的身份)',
  );
  static final RegExp _chineseResponsePlanning = RegExp(
    r'(?:我(?:意识到|判断|认为|应该|需要|得|要)|接下来(?:应该|需要|要))'
    r'[\s\S]{0,120}'
    r'(?:回应|回复|回答|询问|确认|澄清|表达|表现|关注|安慰|共情|避免|使用中文|保持角色)',
  );
  static final RegExp _chineseUserAnalysis = RegExp(
    r'^(?:她|他|用户)(?:刚才|刚刚|现在|似乎|可能|正在|提到|说|问)'
    r'[\s\S]{0,160}'
    r'(?:我(?:应该|需要|得|要)|应该|需要)'
    r'[\s\S]{0,120}'
    r'(?:回应|回复|回答|询问|确认|澄清|表达|表现|关注|安慰|共情|避免)',
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

  /// TTS audio tags that the companion agent may emit to steer TTS delivery
  /// (emotion, breath, pacing). Two provider-specific sets are recognized:
  ///
  /// - **ElevenLabs v3** — square brackets, English tone words:
  ///   `[softly]`, `[low voice]`, `[breathing heavily]`, `[whispers]`,
  ///   `[amused]`, `[eager]`, `[needy]`, `[pause]`, `[short pause]`,
  ///   `[quiet breath]`, `[long pause]`.
  ///
  /// - **MiniMax Speech 2.8** — parentheses, lowercase sound events (19):
  ///   `(breath)`, `(pant)`, `(inhale)`, `(exhale)`, `(gasps)`,
  ///   `(laughs)`, `(chuckle)`, `(sniffs)`, `(sighs)`, `(coughs)`,
  ///   `(snorts)`, `(clear-throat)`, `(burps)`, `(groans)`, `(sneezes)`,
  ///   `(hissing)`, `(lip-smacking)`, `(humming)`, `(emm)`.
  ///
  /// Both sets are stripped from chat UI text so the user never sees raw
  /// control tags. The TTS path keeps whichever tags match its provider.
  static final RegExp _ttsAudioTag = RegExp(
    r'(?:'
    r'\[\s*(?:'
    r'softly|low voice|breathing heavily|whispers|amused|eager|needy|'
    r'pause|short pause|quiet breath|long pause'
    r')\s*\]'
    r'|'
    r'\(\s*(?:'
    r'breath|pant|inhale|exhale|gasps|laughs|chuckle|sniffs|sighs|coughs|'
    r'snorts|clear-throat|burps|groans|sneezes|hissing|lip-smacking|'
    r'humming|emm'
    r')\s*\)'
    r')',
    caseSensitive: false,
  );

  /// Remove TTS audio tags from [text]. Used when rendering text for the chat
  /// UI so the user never sees `[softly]` etc. The TTS path keeps the tags.
  static String stripTtsTags(String text) =>
      text.replaceAll(_ttsAudioTag, '').trim();

  /// The model sometimes writes action / stage-direction text inside square
  /// brackets (the TTS-tag format), often mixed with an English tone word,
  /// e.g. `[low, 呼吸放软下来]`. The whitelist [_ttsAudioTag] only strips
  /// pure-English tone tags, so a bracket containing Chinese is neither
  /// stripped nor star-wrapped, and leaks into the chat as plain white text.
  /// Convert any bracket that contains a CJK character into star-wrapped
  /// action syntax so the existing italic-action recognition takes over: a
  /// leading ASCII tone prefix (e.g. `low, `) is dropped, the remaining
  /// Chinese description is wrapped in `*...*`. Markdown links (`[text](url)`,
  /// detected by a `(` right after the bracket) are left untouched.
  static String _convertBracketActions(String text) {
    return text.replaceAllMapped(
      RegExp(r'\[([^\]]*[\u4e00-\u9fff][^\]]*)\](?!\()'),
      (m) {
        var inner = m.group(1)!.trim();
        inner = inner
            .replaceFirst(RegExp(r'^[A-Za-z][A-Za-z\s,.\-]*[,，]\s*'), '')
            .trim();
        if (inner.isEmpty) return '';
        return '*$inner*';
      },
    );
  }

  static List<PersonaReplySegment> splitVisibleReply(
    String text, {
    String? characterName,
    bool stripTtsTags = false,
  }) {
    var cleaned = stripLeakedReasoning(text).trim();
    if (cleaned.isEmpty) return const [];
    if (stripTtsTags) cleaned = PersonaReplySanitizer.stripTtsTags(cleaned);
    cleaned = _convertBracketActions(cleaned);

    final segments = <PersonaReplySegment>[];
    for (final rawLine in cleaned.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      segments.addAll(_splitLine(line, characterName: characterName));
    }

    return _mergeAdjacent(segments);
  }

  /// Returns text suitable for TTS, keeping both spoken dialogue and
  /// action / inner-monologue segments so the voice also narrates stage
  /// directions (e.g. `*轻轻笑了笑*` is read aloud as `轻轻笑了笑`).
  /// Italic markers (`*`/`_`) wrapping action segments are stripped.
  static String spokenTextOnly(
    String text, {
    String? characterName,
    bool stripTtsTags = false,
  }) {
    final segments = splitVisibleReply(
      text,
      characterName: characterName,
      stripTtsTags: stripTtsTags,
    );
    if (segments.isEmpty) {
      var raw = stripLeakedReasoning(text).trim();
      if (stripTtsTags) raw = PersonaReplySanitizer.stripTtsTags(raw);
      return _stripEmphasisMarkers(raw);
    }
    return segments
        .map((segment) => segment.type == PersonaReplySegmentType.action
            ? _stripEmphasisMarkers(segment.text)
            : segment.text)
        .join('\n')
        .trim();
  }

  /// Remove Markdown emphasis wrappers (`*`/`_`) so TTS engines do not
  /// synthesize literal asterisks. Inline markers are removed too.
  static String _stripEmphasisMarkers(String text) {
    return text
        .replaceAll(RegExp(r'\*{1,3}|_{1,3}'), '')
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
    // A response envelope is the primary safety boundary. Compatible models
    // may emit untagged analysis before their answer even on a non-streaming
    // request; anything outside this envelope is never user-visible.
    final visibleBlock = _visibleReplyBlock.firstMatch(text);
    if (visibleBlock != null) {
      return visibleBlock.group(1)!.trim();
    }
    final visibleOpen = _visibleReplyOpen.firstMatch(text);
    if (visibleOpen != null) {
      return text
          .substring(visibleOpen.end)
          .replaceFirst(_visibleReplyClose, '')
          .trim();
    }

    // Strip fully-closed think blocks first, then any unclosed open tag.
    var result = text
        .replaceAll(_thinkingBlock, '')
        .replaceAll(_unclosedThink, '')
        .trim();
    if (result.isEmpty) return result;

    result = _stripLeadingEnglishReasoningBlock(result);
    if (result.isEmpty) return result;

    result = _stripLeadingReasoningSentences(result);
    if (result.isEmpty) return result;

    final lines = result.split(RegExp(r'\r?\n'));
    var firstVisible = 0;
    while (firstVisible < lines.length) {
      final line = lines[firstVisible].trim();
      if (line.isEmpty) {
        firstVisible++;
        continue;
      }
      if (!_looksLikeLeakedReasoning(line)) break;
      firstVisible++;
    }
    if (firstVisible > 0 && firstVisible < lines.length) {
      result = lines.skip(firstVisible).join('\n').trim();
    }

    return result;
  }

  static String _stripLeadingReasoningSentences(String text) {
    var remainder = text.trimLeft();
    while (remainder.isNotEmpty) {
      final boundary = RegExp(r'[.!?。！？](?:\s+|(?=[\u3400-\u9fff*<]))')
          .firstMatch(remainder);
      final lineBreak = remainder.indexOf('\n');
      final boundaryEnd = boundary?.end;
      final candidateEnd = switch ((boundaryEnd, lineBreak)) {
        (final int sentenceEnd, final int newline) when newline >= 0 =>
          sentenceEnd < newline ? sentenceEnd : newline,
        (final int sentenceEnd, _) => sentenceEnd,
        (_, final int newline) when newline >= 0 => newline,
        _ => remainder.length,
      };
      final candidate = remainder.substring(0, candidateEnd).trim();
      if (!_looksLikeLeakedReasoning(candidate)) break;
      remainder = remainder.substring(candidateEnd).trimLeft();
    }
    return remainder.trim();
  }

  static String _stripLeadingEnglishReasoningBlock(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.isEmpty) return text;

    if (trimmed.codeUnitAt(0) > 127) return text;

    final cjkTotal =
        RegExp(r'[\u4e00-\u9fff]').allMatches(trimmed).length;
    if (cjkTotal < 15) return text;

    final sampleEnd = trimmed.length < 80 ? trimmed.length : 80;
    final sample = trimmed.substring(0, sampleEnd);
    final asciiInSample = RegExp(r'[a-zA-Z]').allMatches(sample).length;
    final cjkInSample = RegExp(r'[\u4e00-\u9fff]').allMatches(sample).length;
    if (asciiInSample < 10 || asciiInSample < cjkInSample * 3) return text;

    final boundaryRe = RegExp(
      r'[.!?](?:\s+(?=[A-Z])|(?=[\u4e00-\u9fff])|\s*$)|[。！？]|\n+',
    );

    var lastReasoningEnd = 0;
    var prevEnd = 0;

    for (final m in boundaryRe.allMatches(trimmed)) {
      final segment = trimmed.substring(prevEnd, m.start);
      final segAscii = RegExp(r'[a-zA-Z]').allMatches(segment).length;
      final segCjk = RegExp(r'[\u4e00-\u9fff]').allMatches(segment).length;
      prevEnd = m.end;

      if (segAscii >= segCjk && segAscii > 3) {
        lastReasoningEnd = m.end;
      }
    }

    if (lastReasoningEnd > 0 && lastReasoningEnd < trimmed.length) {
      var remainder = trimmed.substring(lastReasoningEnd).trim();
      remainder = _stripChineseReasoningPrefix(remainder);
      if (remainder.isNotEmpty) return remainder;
    }
    return text;
  }

  static String _stripChineseReasoningPrefix(String text) {
    var remainder = text;
    final sentenceRe = RegExp(r'[^。！？\n]+[。！？\n]?');
    while (remainder.isNotEmpty) {
      final m = sentenceRe.firstMatch(remainder);
      if (m == null) break;
      final sentence = m.group(0)!.trim();
      if (sentence.isEmpty) {
        remainder = remainder.substring(m.end).trimLeft();
        continue;
      }
      if (_looksLikeLeakedReasoning(sentence) ||
          _isChineseReasoningContinuation(sentence)) {
        remainder = remainder.substring(m.end).trimLeft();
      } else {
        break;
      }
    }
    return remainder.trim();
  }

  static bool _isChineseReasoningContinuation(String text) {
    if (RegExp(r'^\d').hasMatch(text)) return true;
    return RegExp(
      r'(?:让我|我需要|我得|我要再|我应该告诉|我应该提出|'
      r'重新(?:转换|核实|检查|计算)|'
      r'仔细(?:核实|检查|看看|分析)|'
      r'不过从.+?来看|'
      r'既然.+?那么.+?应该|'
      r'还有个更重要的问题|'
      r'另外[，,]既然|'
      r'我需要再|需要再仔细|'
      r'所以.+?可能是|'
      r'我应该|'
      r'但这与.+?矛盾|'
      r'这样的话|'
      r'可能确实是|'
      r'她(?:可能|应该|是因为|说|提到|的))',
    ).hasMatch(text);
  }

  static bool _looksLikeLeakedReasoning(String text) {
    final line = text.trim();
    if (line.isEmpty) return false;
    if (_leadingReasoningLine.hasMatch(line)) return true;
    if (_englishAnalyticalOpener.hasMatch(line)) return true;

    if (RegExp(r"^(?:the\s+user(?:'s)?|user)\b", caseSensitive: false)
        .hasMatch(line)) {
      return true;
    }

    final englishPlanning = _englishResponsePlanning.hasMatch(line);
    if (englishPlanning) return true;

    final chineseMeta = _chineseMetaReference.hasMatch(line);
    final chinesePlanning = _chineseResponsePlanning.hasMatch(line);
    return (chineseMeta && chinesePlanning) ||
        _chineseUserAnalysis.hasMatch(line);
  }

  static List<PersonaReplySegment> _splitLine(
    String line, {
    String? characterName,
  }) {
    final inlineSegments = _splitInlineItalicActions(line);
    if (inlineSegments != null) {
      return _applyActionPerspective(inlineSegments, characterName);
    }

    final fullItalic = _fullItalicLine.firstMatch(line);
    if (fullItalic != null) {
      final action = fullItalic.group(2)!.trim();
      // Standalone italic lines are usually stage direction / inner
      // monologue, but a long natural-language line is more likely ordinary
      // Markdown emphasis (e.g. `*I really mean it.*`) and must stay in the
      // chat bubble. Fall back to chat (keeping the markers so Markdown still
      // renders emphasis) when the wrapped text does not look like a stage
      // direction.
      if (_looksLikeStageDirection(action)) {
        return [
          PersonaReplySegment(
            type: PersonaReplySegmentType.action,
            text: _normalizeActionText(_wrapAction(action), characterName),
          ),
        ];
      }
      return [
        PersonaReplySegment(
          type: PersonaReplySegmentType.chat,
          text: line,
        ),
      ];
    }

    final leadingItalic = _leadingItalic.firstMatch(line);
    if (leadingItalic != null) {
      final action = leadingItalic.group(2)!.trim();
      final chat = leadingItalic.group(3)!.trim();
      if (_looksLikeStageDirection(action)) {
        return [
          PersonaReplySegment(
            type: PersonaReplySegmentType.action,
            text: _normalizeActionText(_wrapAction(action), characterName),
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
      if (_looksLikeStageDirection(action)) {
        return [
          PersonaReplySegment(
            type: PersonaReplySegmentType.chat,
            text: chat,
          ),
          PersonaReplySegment(
            type: PersonaReplySegmentType.action,
            text: _normalizeActionText(_wrapAction(action), characterName),
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
      if (_looksLikeStageDirection(candidate)) {
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
      '\\u547c\\u5438|\\u76b1\\u7709|'
      '\\u8f7b\\u58f0|\\u4f4e\\u58f0|\\u67d4\\u58f0|\\u5462\\u5583|\\u4f4e\\u8bed|\\u6e29\\u67d4|'
      '\\u8f7b\\u7b11|\\u6d45\\u7b11|\\u51b7\\u7b11|\\u82e6\\u7b11|\\u62bf\\u5634|\\u6487\\u5634|\\u54ac\\u5507|\\u8214\\u5507|'
      '\\u5782\\u7738|\\u62ac\\u7738|\\u7737\\u773c|\\u95ed\\u773c|\\u7741\\u773c|\\u6311\\u7709|\\u8038\\u80a9|\\u6b6a\\u5634)',
    ).hasMatch(normalized);
  }

  /// Decide whether an italic phrase is a roleplay stage direction
  /// (action description / inner monologue) and should be peeled out of the
  /// chat bubble into the dedicated action row.
  ///
  /// Combines the existing keyword/subject heuristic with a short-action
  /// heuristic that catches common action phrases the keyword list misses
  /// (e.g. `*走过去*`, `*抬了抬眉毛*`, `*leans closer*`) so they don't render
  /// as plain italic emphasis inside the chat bubble.
  static bool _looksLikeStageDirection(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    if (_looksLikeAction(normalized)) return true;
    return _looksLikeShortStageDirection(normalized);
  }

  /// Lightweight short-stage-direction heuristic.
  ///
  /// Hard rules (any failure short-circuits to false):
  /// * ≤ 24 runes - too long likely means natural-language emphasis, not a
  ///   beat-length stage direction.
  /// * No strong sentence-ending punctuation (！？!?…) - `。` is allowed
  ///   because stage directions commonly end with it (e.g. `想了一下。`).
  /// * No quotes (straight / curly / Chinese) - quoted spans are speech.
  ///
  /// Triggers when either:
  /// * The text ends with a typical action suffix (了/着/一下/起/过去/过来/
  ///   回去/上来/下来/起来), optionally followed by `。`/`,`.
  /// * It contains a stage-direction verb seed the keyword table doesn't
  ///   cover (走过去, 抬眼, 想了一下, 凑近, turns, leans, etc.).
  static bool _looksLikeShortStageDirection(String text) {
    if (text.runes.length > 24) return false;
    if (RegExp(r'[\uff01\uff1f!?\u2026]').hasMatch(text)) return false;
    if (RegExp(r'["\u201c\u201d\u300c\u300d]').hasMatch(text)) return false;

    final stageVerbs = RegExp(
      '(\u8d70|\u8df3|\u9760|\u62ac|\u4f4e|\u4f38|\u63e1|\u62b1|'
      '\u62cd|\u6478|\u62c9|\u5750|\u7ad9|\u8f6c|\u7ffb|\u62a1|'
      '\u542c|\u5012|\u53f9|\u4f4f|\u5f00\u53e3|\u60f3|'
      '\u54bd|\u54bd\u4e86|\u6293|\u6293\u4e86|\u63a8|'
      '\u8e6f|\u8e0f|\u8e29|\u51d1|\u62ce|\u635f|'
      'leads?|closes?|opens?|turns?|pushes?|pulls?|gives?|takes?|'
      r'hands?|picks?|drops?|throws?|slides?|shifts?|exhales?|inhales?)',
    );
    if (stageVerbs.hasMatch(text)) return true;

    final actionEnding = RegExp(
      r'(?:了|着|一下|起|过去|过来|回去|上来|下来|起来)[。，,]?$',
    );
    return actionEnding.hasMatch(text);
  }

  /// Strip self-referential subjects from action text.
  ///
  /// Chinese stage directions / inner monologue don't need a subject pronoun —
  /// "靠在椅背上，看着屏幕笑了一下。" reads more naturally than either
  /// "林埃靠在椅背上…" or "我靠在椅背上…". The subject is always the speaker.
  static String _normalizeActionText(String actionText, String? characterName) {
    if (!actionText.startsWith('*') || !actionText.endsWith('*')) {
      return actionText;
    }
    var inner = actionText.substring(1, actionText.length - 1);

    // Strip leading subjects: the character name (e.g. "林埃") or first-person
    // pronoun "我". These are always redundant in action lines.
    final subjects = <String>['我'];
    if (characterName != null && characterName.isNotEmpty) {
      subjects.add(characterName);
    }
    for (final sub in subjects) {
      // Leading subject, optionally followed by punctuation
      inner = inner.replaceAll(RegExp('^$sub[，,。.]?\\s*'), '');
    }

    // Remove any remaining occurrences in the middle of the text
    for (final sub in subjects) {
      inner = inner.replaceAll(sub, '');
    }

    inner = inner.trim();
    if (inner.isEmpty) return actionText; // safety
    return '*$inner*';
  }

  /// Apply action-perspective normalization to every action segment in [segments].
  static List<PersonaReplySegment> _applyActionPerspective(
    List<PersonaReplySegment> segments,
    String? characterName,
  ) {
    if (characterName == null || characterName.isEmpty) return segments;
    return segments.map((seg) {
      if (seg.type != PersonaReplySegmentType.action) return seg;
      return PersonaReplySegment(
        type: seg.type,
        text: _normalizeActionText(seg.text, characterName),
      );
    }).toList();
  }

  static String _wrapAction(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('*') && trimmed.endsWith('*')) return trimmed;
    return '*$trimmed*';
  }
}
