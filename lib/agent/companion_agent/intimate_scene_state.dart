/// In-memory state for an autonomous intimate scene.
///
/// Lifecycle (see docs/companion-first/INTIMATE_MODE_REQUIREMENTS.md):
/// 1. The UI detects a scene trigger phrase (deterministic match), runs
///    [IntimateScenePlanner] to produce a beat plan, then calls [start].
/// 2. Each completed narration turn calls [turnCompleted], which advances the
///    current beat once its message quota is met.
/// 3. The user's orgasm signal calls [enterAftercare], which swaps the
///    per-turn directive to a low-intensity continuous aftercare narration
///    until she stops it or falls asleep.
///
/// State is deliberately in-memory like ContinuousModeState: an app restart
/// abandons a scene rather than resurrecting one the user has forgotten
/// about. Single-scene at a time (one character); multi-character scenes are
/// out of scope.
class IntimateSceneBeat {
  const IntimateSceneBeat({
    required this.intent,
    required this.targetMessageCount,
    required this.notes,
    required this.escalationLevel,
  });

  final String intent;

  /// How many narration messages this beat spans (3-8 by design).
  final int targetMessageCount;

  /// What to vary this beat (axis + concrete points).
  final String notes;

  /// 0-5. The plateau stays at 4-5 by design.
  final int escalationLevel;

  factory IntimateSceneBeat.fromJson(Map<String, dynamic> json) {
    return IntimateSceneBeat(
      intent: (json['intent'] as String?)?.trim() ?? '推进场景',
      targetMessageCount: ((json['targetMessageCount'] as num?)?.toInt() ?? 4)
          .clamp(1, 10),
      notes: (json['notes'] as String?)?.trim() ?? '',
      escalationLevel: ((json['escalationLevel'] as num?)?.toInt() ?? 4)
          .clamp(0, 5),
    );
  }
}

class IntimateScenePlan {
  const IntimateScenePlan({required this.beats});

  final List<IntimateSceneBeat> beats;

  int get totalMessages => beats.fold(0, (sum, b) => sum + b.targetMessageCount);
}

enum IntimateScenePhase { main, aftercare }

class IntimateSceneState {
  IntimateSceneState._();
  static final IntimateSceneState instance = IntimateSceneState._();

  String? _activeCharacterId;
  IntimateScenePlan? _plan;
  int _beatIndex = 0;
  int _messagesInBeat = 0;
  IntimateScenePhase _phase = IntimateScenePhase.main;

  bool get isActive => _activeCharacterId != null;

  bool isActiveFor(String characterId) =>
      isActive && _activeCharacterId == characterId;

  IntimateScenePlan? get activePlan => _plan;

  IntimateScenePhase get phase => _phase;

  void start({required String characterId, required IntimateScenePlan plan}) {
    _activeCharacterId = characterId;
    _plan = plan;
    _beatIndex = 0;
    _messagesInBeat = 0;
    _phase = IntimateScenePhase.main;
  }

  /// Count one completed narration turn and advance the beat when its quota
  /// is met. Turns initiated by the user mid-scene also count (approximation;
  /// quotas are guidance, not hard boundaries).
  void turnCompleted() {
    if (!isActive) return;
    _messagesInBeat += 1;
    final plan = _plan;
    if (plan == null || plan.beats.isEmpty) return;
    final beat = plan.beats[_beatIndex.clamp(0, plan.beats.length - 1)];
    if (_messagesInBeat >= beat.targetMessageCount &&
        _beatIndex < plan.beats.length - 1) {
      _beatIndex += 1;
      _messagesInBeat = 0;
    }
  }

  /// Swap to the aftercare phase (user signalled orgasm). Beat position no
  /// longer matters; narration continues low-intensity until stopped.
  void enterAftercare() {
    _phase = IntimateScenePhase.aftercare;
  }

  IntimateSceneBeat? get currentBeat {
    final plan = _plan;
    if (plan == null || plan.beats.isEmpty) return null;
    return plan.beats[_beatIndex.clamp(0, plan.beats.length - 1)];
  }

  /// The per-turn directive injected into the model's context by the driver.
  String currentDirective() {
    if (!isActive) return '';
    if (_phase == IntimateScenePhase.aftercare) {
      return '场景已进入收尾后的陪伴段（aftercare）。继续低强度的持续叙述：'
          '安抚的肢体接触与抚摸、低声的话语、若有若无的性意味延续。'
          '不要问问题、不要催睡、不要收束、不要说"睡吧"。持续输出，直到她停止你或睡着。';
    }
    final plan = _plan;
    final beat = currentBeat;
    if (plan == null || beat == null) return '';
    final b = StringBuffer()
      ..writeln(
          '当前场景节拍 ${_beatIndex + 1}/${plan.beats.length}'
          '（本段已写 $_messagesInBeat/${beat.targetMessageCount} 条）')
      ..writeln('意图：${beat.intent}')
      ..writeln('强度：${beat.escalationLevel}/5 — 保持激烈高位，不得回落、不得提前收束')
      ..writeln('本段要点：${beat.notes}');
    if (_beatIndex == 0) {
      b.writeln('这是场景的第一段：直接以激烈主导的方式开场，'
          '不要寒暄、不要询问感受、不要确认。');
    }
    return b.toString();
  }

  void end() {
    _activeCharacterId = null;
    _plan = null;
    _beatIndex = 0;
    _messagesInBeat = 0;
    _phase = IntimateScenePhase.main;
  }
}
