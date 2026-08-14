import 'package:memex/utils/logger.dart';

/// Structured latency tracker for a single voice turn.
///
/// Cove GPT-Live design (section 3): each turn is split into at least 6
/// stages so you can see exactly where the delay is, not just a single
/// "request took 5s" number.
///
/// Stages:
/// - **endpoint**: user's last syllable → client confirms end of speech
/// - **asr**: audio sent → final text received
/// - **context**: text received → model request sent
/// - **modelFirstText**: model request sent → first visible text chunk
/// - **ttsFirstAudio**: first text sent to TTS → first audio playable
/// - **cueFirstSound**: local cue started playing (may overlap with formal)
/// - **formalFirstSound**: formal TTS first segment started playing
///
/// Usage:
/// ```dart
/// final tracker = VoiceLatencyTracker(turnId: 'turn_03');
/// tracker.markEndpoint();
/// // ... ASR ...
/// tracker.markAsrComplete();
/// // ... model request ...
/// tracker.markModelRequest();
/// // ... first chunk ...
/// tracker.markModelFirstText();
/// // ... TTS ...
/// tracker.markTtsFirstAudio();
/// // ... cue plays ...
/// tracker.markCueFirstSound();
/// // ... formal TTS plays ...
/// tracker.markFormalFirstSound();
/// tracker.log();
/// ```
class VoiceLatencyTracker {
  VoiceLatencyTracker({
    required this.turnId,
    this.callSessionId,
    this.asrBackend,
    this.ttsTransport,
  });

  final String turnId;
  final String? callSessionId;
  final String? asrBackend;
  final String? ttsTransport;

  static final _log = getLogger('VoiceLatency');

  DateTime? _endpointAt;
  DateTime? _asrCompleteAt;
  DateTime? _modelRequestAt;
  DateTime? _modelFirstTextAt;
  DateTime? _ttsFirstAudioAt;
  DateTime? _cueFirstSoundAt;
  DateTime? _formalFirstSoundAt;
  DateTime? _turnStartAt;

  /// Mark the start of this turn (user started speaking or endpoint fired).
  void markTurnStart() => _turnStartAt ??= DateTime.now();

  /// Mark when the user's last syllable was detected (endpoint).
  void markEndpoint() => _endpointAt ??= DateTime.now();

  /// Mark when ASR returned the final text.
  void markAsrComplete() => _asrCompleteAt ??= DateTime.now();

  /// Mark when the model request was sent.
  void markModelRequest() => _modelRequestAt ??= DateTime.now();

  /// Mark when the first text chunk arrived from the model.
  void markModelFirstText() => _modelFirstTextAt ??= DateTime.now();

  /// Mark when the first TTS audio segment is ready / starts playing.
  void markTtsFirstAudio() => _ttsFirstAudioAt ??= DateTime.now();

  /// Mark when the local cue started playing (may be before formal TTS).
  void markCueFirstSound() => _cueFirstSoundAt ??= DateTime.now();

  /// Mark when the formal TTS first segment started playing.
  void markFormalFirstSound() => _formalFirstSoundAt ??= DateTime.now();

  /// Compute the elapsed milliseconds between two timestamps.
  int _elapsed(DateTime? from, DateTime? to) {
    if (from == null || to == null) return -1;
    return to.difference(from).inMilliseconds;
  }

  /// Build a structured latency record.
  Map<String, dynamic> toMap() {
    return {
      'event': 'voice_latency',
      'turn_id': turnId,
      if (callSessionId != null) 'call_session_id': callSessionId,
      'endpoint_ms': _elapsed(_endpointAt, _asrCompleteAt),
      'asr_ms': _elapsed(_asrCompleteAt, _modelRequestAt),
      'context_ms': _elapsed(_modelRequestAt, _modelFirstTextAt) >= 0
          ? _elapsed(_modelRequestAt, _modelFirstTextAt)
          : -1,
      // model_first_text_ms is from model request to first text.
      'model_first_text_ms': _elapsed(_modelRequestAt, _modelFirstTextAt),
      'tts_first_audio_ms': _elapsed(_modelFirstTextAt, _ttsFirstAudioAt),
      // first_sound_ms = cue (local feedback) or formal, whichever first.
      'first_sound_ms': _firstSoundMs(),
      'formal_first_sound_ms': _elapsed(_turnStartAt, _formalFirstSoundAt),
      if (asrBackend != null) 'asr_backend': asrBackend,
      if (ttsTransport != null) 'tts_transport': ttsTransport,
    };
  }

  int _firstSoundMs() {
    final cue = _cueFirstSoundAt;
    final formal = _formalFirstSoundAt;
    final start = _turnStartAt ?? _endpointAt;
    if (start == null) return -1;
    if (cue != null && formal != null) {
      return cue.isBefore(formal)
          ? start.difference(cue).inMilliseconds.abs()
          : start.difference(formal).inMilliseconds.abs();
    }
    if (cue != null) return start.difference(cue).inMilliseconds.abs();
    if (formal != null) return start.difference(formal).inMilliseconds.abs();
    return -1;
  }

  /// Log the structured record. Call at the end of each turn.
  void log() {
    final m = toMap();
    final buf = StringBuffer('voice_latency $turnId:');
    for (final entry in m.entries) {
      if (entry.key == 'event' || entry.key == 'turn_id') continue;
      buf.write(' ${entry.key}=${entry.value}');
    }
    _log.info(buf.toString());
  }
}