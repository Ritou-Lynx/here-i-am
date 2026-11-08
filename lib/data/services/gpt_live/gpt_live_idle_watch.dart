enum GptLiveIdleAction { none, prompt, hangup }

class GptLiveIdleWatch {
  GptLiveIdleWatch({
    required this.idleMinutes,
    required DateTime lastTranscriptAt,
  }) : _lastTranscriptAt = lastTranscriptAt;

  final int idleMinutes;
  DateTime _lastTranscriptAt;
  DateTime? _promptedAt;

  static const promptGracePeriod = Duration(seconds: 20);

  void recordTranscript(DateTime at, {required bool fromUser}) {
    if (_promptedAt == null || fromUser) {
      _lastTranscriptAt = at;
      _promptedAt = null;
      return;
    }
    _promptedAt = at;
  }

  GptLiveIdleAction evaluate(DateTime now) {
    if (idleMinutes <= 0) return GptLiveIdleAction.none;
    final promptedAt = _promptedAt;
    if (promptedAt != null) {
      return now.difference(promptedAt) >= promptGracePeriod
          ? GptLiveIdleAction.hangup
          : GptLiveIdleAction.none;
    }
    if (now.difference(_lastTranscriptAt) >= Duration(minutes: idleMinutes)) {
      _promptedAt = now;
      return GptLiveIdleAction.prompt;
    }
    return GptLiveIdleAction.none;
  }
}
