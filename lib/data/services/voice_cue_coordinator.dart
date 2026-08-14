import 'dart:async';

import 'package:memex/data/services/tts_service.dart';
import 'package:memex/data/services/voice_cue_classifier.dart';
import 'package:memex/data/services/voice_cue_service.dart';
import 'package:memex/utils/logger.dart';

/// Coordinates the local voice cue lifecycle:
///
/// 1. [preGenerate] — warm the TTS disk cache for all cue clips at voice-mode
///    start so the first cue doesn't pay synthesis latency.
/// 2. [playCueFor] — classify the user's ASR text, select a clip, synthesize
///    (or cache-hit), and play it. Returns immediately; the caller does not
///    need to wait — the cue plays in the background.
/// 3. [preemptForFormalTts] — called when formal TTS seq=0 arrives. Stops the
///    cue immediately unless it has `completeBeforeFormal: true`.
///
/// The coordinator owns the TTS voiceId and tracks which clip is currently
/// playing so that [preemptForFormalTts] can check the `completeBeforeFormal`
/// flag.
class VoiceCueCoordinator {
  VoiceCueCoordinator._();
  static final VoiceCueCoordinator instance = VoiceCueCoordinator._();

  static final _log = getLogger('VoiceCueCoordinator');

  final VoiceCueService _cueService = VoiceCueService.instance;

  String? _voiceId;
  bool _voiceMode = false;
  VoiceCueClip? _currentClip;
  bool _enabled = true;

  /// Whether the cue system is enabled. When false, [playCueFor] is a no-op.
  bool get isEnabled => _enabled;

  /// Enable or disable the cue system.
  set isEnabled(bool value) => _enabled = value;

  /// Whether a cue is currently playing.
  bool get isPlaying => _currentClip != null && _cueService.isPlaying;

  /// Initialize for a voice session. Call when voice mode starts.
  void init({required String voiceId, bool voiceMode = false}) {
    _voiceId = voiceId;
    _voiceMode = voiceMode;
    _cueService.reset();
  }

  /// Warm the TTS disk cache for all cue clips. Best-effort.
  Future<void> preGenerate() async {
    final voiceId = _voiceId;
    if (voiceId == null || voiceId.isEmpty) return;
    var ok = 0;
    var fail = 0;
    for (final clip in defaultVoiceCueManifest) {
      try {
        await TtsService.textToSpeech(text: clip.text, voiceId: voiceId);
        ok++;
      } catch (e) {
        fail++;
        _log.fine('preGenerate failed for ${clip.clipId}: $e');
      }
    }
    _log.info('preGenerate: $ok ok, $fail failed');
  }

  /// Classify [asrText], select a clip, and play it. Returns the clip that
  /// was selected (or null if no cue should be played).
  ///
  /// This is fire-and-forget: the caller should NOT await it. The cue plays
  /// in the background; [preemptForFormalTts] will stop it when formal TTS
  /// arrives.
  Future<VoiceCueClip?> playCueFor(String asrText) async {
    if (!_enabled) return null;
    final voiceId = _voiceId;
    if (voiceId == null || voiceId.isEmpty) return null;

    final cueClass = VoiceCueClassifier.classify(asrText);
    if (cueClass == VoiceCueClass.none || cueClass == VoiceCueClass.farewell) {
      return null;
    }

    final clip = _cueService.selectClip(cueClass);
    if (clip == null) return null;

    _currentClip = clip;
    unawaited(_synthesizeAndPlay(clip, voiceId));
    return clip;
  }

  Future<void> _synthesizeAndPlay(
    VoiceCueClip clip,
    String voiceId,
  ) async {
    try {
      final audioPath =
          await TtsService.textToSpeech(text: clip.text, voiceId: voiceId);
      if (_currentClip?.clipId != clip.clipId) return;
      await _cueService.playClip(
        clip: clip,
        audioPath: audioPath,
        voiceMode: _voiceMode,
      );
    } catch (e) {
      _log.warning('synthesizeAndPlay ${clip.clipId} failed: $e');
    } finally {
      if (_currentClip?.clipId == clip.clipId) {
        _currentClip = null;
      }
    }
  }

  /// Preempt the currently playing cue. Called when formal TTS seq=0 arrives.
  ///
  /// Returns true if the cue was preempted (stopped), false if it should be
  /// allowed to finish (`completeBeforeFormal: true`).
  Future<bool> preemptForFormalTts() async {
    final clip = _currentClip;
    if (clip == null) return false;
    if (clip.completeBeforeFormal) {
      // Let it finish — the caller should wait briefly.
      _log.fine('Cue ${clip.clipId} has completeBeforeFormal, not preempting');
      return false;
    }
    await _cueService.preempt();
    _currentClip = null;
    return true;
  }

  /// Stop everything and reset. Call when voice mode ends.
  void reset() {
    _currentClip = null;
    _cueService.reset();
  }
}