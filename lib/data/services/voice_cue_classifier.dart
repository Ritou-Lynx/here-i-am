/// Semantic classification of a user utterance for local voice cue selection.
///
/// Based on the Cove GPT-Live listener-cues design: the final ASR text is
/// classified (not just an endpoint-timer) so that farewells, call-state
/// questions, and reflective questions get the right response instead of a
/// mechanical "嗯".
enum VoiceCueClass {
  /// User is ending the call — no cue (let the agent say goodbye).
  farewell,

  /// "Can you hear me?" / "Are you there?" — instant local reply.
  callStateQuestion,

  /// "帮我找一下…" / "搜一下…" — search lead-in.
  searchLeadIn,

  /// "试一下延迟" — test context.
  testLeadIn,

  /// "你觉得…" / "为什么…" / "怎么才能…" — needs judgment / reflection.
  thinkingLeadIn,

  /// User is sharing something personal / a story.
  sharingAck,

  /// Something funny or playful.
  funAck,

  /// Default: short neutral acknowledgment.
  neutralLeadIn,

  /// No cue should be played.
  none,
}

/// Classifies final ASR text into a [VoiceCueClass].
///
/// Rules are intentionally simple keyword/pattern based — the goal is fast
/// classification that runs in <1ms, not NLU. The classification quality bar
/// is "better than always playing 嗯", not "perfect intent detection".
class VoiceCueClassifier {
  VoiceCueClassifier._();

  /// Classify [text] (final ASR transcript, trimmed).
  static VoiceCueClass classify(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return VoiceCueClass.none;

    // Farewell — no cue.
    if (_isFarewell(lower)) return VoiceCueClass.farewell;

    // Call-state questions — instant local reply.
    if (_isCallStateQuestion(lower)) return VoiceCueClass.callStateQuestion;

    // Explicit search / find — search lead-in.
    if (_isExplicitSearch(lower)) return VoiceCueClass.searchLeadIn;

    // Test context ("试一下延迟", "测试").
    if (_isTestContext(lower)) return VoiceCueClass.testLeadIn;

    // Reflective question — thinking lead-in.
    if (_isReflectiveQuestion(lower)) return VoiceCueClass.thinkingLeadIn;

    // Personal sharing — sharing ack.
    if (_isPersonalSharing(lower)) return VoiceCueClass.sharingAck;

    // Fun / play.
    if (_isFun(lower)) return VoiceCueClass.funAck;

    // Default.
    return VoiceCueClass.neutralLeadIn;
  }

  static bool _isFarewell(String text) {
    const keywords = [
      '我先挂了', '挂了', '挂电话', '再见', '拜拜', 'bye', 'goodbye',
      '我走了', '先这样', '就这样吧', '没事了', '不用了',
    ];
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  static bool _isCallStateQuestion(String text) {
    const keywords = [
      '你能听到吗', '听得到吗', '听得到', '能听见吗', '你在吗',
      '你在不在', '有人吗', '喂', 'hello', 'can you hear',
    ];
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  static bool _isExplicitSearch(String text) {
    const keywords = [
      '帮我找', '搜一下', '搜索', '查一下', '查找', '附近',
      '哪里有', '帮我查', 'search', 'find',
    ];
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  static bool _isTestContext(String text) {
    const keywords = ['试一下', '测试', '延迟', 'test', 'latency'];
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  static bool _isReflectiveQuestion(String text) {
    // Questions that need judgment / comparison / reflection.
    const questionMarkers = ['你觉得', '为什么', '怎么才能', '怎么办',
        '哪个好', '要不要', '该不该', '能不能', '怎么样', '如何'];
    for (final kw in questionMarkers) {
      if (text.contains(kw)) return true;
    }
    // Generic question ending with "?" or "？"
    if (text.endsWith('?') || text.endsWith('？')) return true;
    return false;
  }

  static bool _isPersonalSharing(String text) {
    // User is telling a story / sharing something about themselves.
    const keywords = [
      '我今天', '我昨天', '我刚才', '我跟你说', '你知道吗',
      '我遇到', '我发现', '我觉得好', '我开心', '我难过',
      '我累', '我开心', '我今天好',
    ];
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }

  static bool _isFun(String text) {
    const keywords = ['哈哈', '笑死', '搞笑', 'lol', '哈哈太',
        '好笑', '有趣', '好玩'];
    for (final kw in keywords) {
      if (text.contains(kw)) return true;
    }
    return false;
  }
}