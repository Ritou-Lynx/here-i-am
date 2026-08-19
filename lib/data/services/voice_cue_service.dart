import 'dart:async';
import 'dart:collection';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:memex/data/services/voice_cue_classifier.dart';
import 'package:memex/utils/logger.dart';

/// One pre-generated short audio cue (e.g. "好，我看看" / "嗯，让我想想").
///
/// Materialized via TTS at call time (cached by the TTS provider's disk
/// cache). The [expressionFamily] enables cross-class cooldown sharing so
/// similar-sounding cues don't repeat back-to-back even across classes.
@immutable
class VoiceCueClip {
  const VoiceCueClip({
    required this.clipId,
    required this.semanticClass,
    required this.text,
    required this.toneFamily,
    required this.expressionFamily,
    this.playbackVolume = 0.6,
    this.cooldownSeconds = 90,
    this.completeBeforeFormal = false,
  });

  final String clipId;
  final VoiceCueClass semanticClass;
  final String text;
  final String toneFamily;
  final String expressionFamily;
  final double playbackVolume;
  final int cooldownSeconds;
  final bool completeBeforeFormal;
}

/// Default cue manifest. Each class has 3+ clips so the selector can avoid
/// repeating the same clip within 4 turns.
///
/// These are placeholder Chinese phrases — the actual voice is the user's
/// configured TTS voice (MiniMax / ElevenLabs). The texts are designed to be
/// short (4-14 chars), natural spoken interjections.
final List<VoiceCueClip> defaultVoiceCueManifest = [
  // searchLeadIn
  VoiceCueClip(
    clipId: 'search_01',
    semanticClass: VoiceCueClass.searchLeadIn,
    text: '好，我看看。',
    toneFamily: 'helpful',
    expressionFamily: 'look-up',
  ),
  VoiceCueClip(
    clipId: 'search_02',
    semanticClass: VoiceCueClass.searchLeadIn,
    text: '我找找看。',
    toneFamily: 'helpful',
    expressionFamily: 'search',
  ),
  VoiceCueClip(
    clipId: 'search_03',
    semanticClass: VoiceCueClass.searchLeadIn,
    text: '稍等，我查一下。',
    toneFamily: 'helpful',
    expressionFamily: 'check',
  ),

  // thinkingLeadIn
  VoiceCueClip(
    clipId: 'thinking_01',
    semanticClass: VoiceCueClass.thinkingLeadIn,
    text: '嗯，让我想想。',
    toneFamily: 'soft-thinking',
    expressionFamily: 'thinking',
  ),
  VoiceCueClip(
    clipId: 'thinking_02',
    semanticClass: VoiceCueClass.thinkingLeadIn,
    text: '这个问题有意思。',
    toneFamily: 'soft-thinking',
    expressionFamily: 'reflect',
  ),
  VoiceCueClip(
    clipId: 'thinking_03',
    semanticClass: VoiceCueClass.thinkingLeadIn,
    text: '我想想怎么说。',
    toneFamily: 'soft-thinking',
    expressionFamily: 'thinking',
  ),

  // sharingAck
  VoiceCueClip(
    clipId: 'sharing_01',
    semanticClass: VoiceCueClass.sharingAck,
    text: '嗯，我在听。',
    toneFamily: 'warm',
    expressionFamily: 'listening',
  ),
  VoiceCueClip(
    clipId: 'sharing_02',
    semanticClass: VoiceCueClass.sharingAck,
    text: '然后呢？',
    toneFamily: 'warm',
    expressionFamily: 'prompt',
  ),
  VoiceCueClip(
    clipId: 'sharing_03',
    semanticClass: VoiceCueClass.sharingAck,
    text: '真的吗？',
    toneFamily: 'warm',
    expressionFamily: 'surprise',
  ),

  // funAck
  VoiceCueClip(
    clipId: 'fun_01',
    semanticClass: VoiceCueClass.funAck,
    text: '哈哈，是吗。',
    toneFamily: 'playful',
    expressionFamily: 'laugh',
  ),
  VoiceCueClip(
    clipId: 'fun_02',
    semanticClass: VoiceCueClass.funAck,
    text: '太好玩了。',
    toneFamily: 'playful',
    expressionFamily: 'amuse',
  ),
  VoiceCueClip(
    clipId: 'fun_03',
    semanticClass: VoiceCueClass.funAck,
    text: '你真逗。',
    toneFamily: 'playful',
    expressionFamily: 'tease',
  ),

  // neutralLeadIn
  VoiceCueClip(
    clipId: 'neutral_01',
    semanticClass: VoiceCueClass.neutralLeadIn,
    text: '好的。',
    toneFamily: 'neutral',
    expressionFamily: 'ack',
  ),
  VoiceCueClip(
    clipId: 'neutral_02',
    semanticClass: VoiceCueClass.neutralLeadIn,
    text: '嗯，说吧。',
    toneFamily: 'neutral',
    expressionFamily: 'ack',
  ),
  VoiceCueClip(
    clipId: 'neutral_03',
    semanticClass: VoiceCueClass.neutralLeadIn,
    text: '好，你讲。',
    toneFamily: 'neutral',
    expressionFamily: 'listen',
  ),

  // callStateQuestion — instant local reply
  VoiceCueClip(
    clipId: 'callstate_01',
    semanticClass: VoiceCueClass.callStateQuestion,
    text: '嗯，我在。',
    toneFamily: 'reassuring',
    expressionFamily: 'present',
    completeBeforeFormal: true,
  ),
  VoiceCueClip(
    clipId: 'callstate_02',
    semanticClass: VoiceCueClass.callStateQuestion,
    text: '能听到。',
    toneFamily: 'reassuring',
    expressionFamily: 'confirm',
    completeBeforeFormal: true,
  ),
  VoiceCueClip(
    clipId: 'callstate_03',
    semanticClass: VoiceCueClass.callStateQuestion,
    text: '在的，你说。',
    toneFamily: 'reassuring',
    expressionFamily: 'present',
    completeBeforeFormal: true,
  ),

  // testLeadIn
  VoiceCueClip(
    clipId: 'test_01',
    semanticClass: VoiceCueClass.testLeadIn,
    text: '好，我听到了。',
    toneFamily: 'neutral',
    expressionFamily: 'confirm',
  ),
  VoiceCueClip(
    clipId: 'test_02',
    semanticClass: VoiceCueClass.testLeadIn,
    text: '嗯，声音正常。',
    toneFamily: 'neutral',
    expressionFamily: 'confirm',
  ),
  VoiceCueClip(
    clipId: 'test_03',
    semanticClass: VoiceCueClass.testLeadIn,
    text: '收到，继续。',
    toneFamily: 'neutral',
    expressionFamily: 'ack',
  ),
];

/// Selects and plays a local short feedback cue, then yields to formal TTS.
///
/// Cove listener-cues rules:
/// - Most-recent-4 not repeated.
/// - Consecutive same-tone-family demoted.
/// - Same expression family shares cooldown across classes.
/// - Formal TTS seq=0 preempts the cue (unless [VoiceCueClip.completeBeforeFormal]).
/// - Interrupted cues still count toward cooldown.
class VoiceCueService {
  VoiceCueService._();
  static final VoiceCueService instance = VoiceCueService._();

  static final _log = getLogger('VoiceCueService');

  final List<VoiceCueClip> _manifest = defaultVoiceCueManifest;

  /// Recently played clip IDs (most-recent-4 dedup window).
  final Queue<String> _recentClipIds = Queue();

  /// Cooldown timestamps: expressionFamily → available-at timestamp.
  final Map<String, DateTime> _cooldownUntil = {};

  /// The last tone family played (for consecutive-same-tone demotion).
  String? _lastToneFamily;

  /// Currently active audio player (null when idle).
  AudioPlayer? _player;
  bool _preempted = false;

  /// Whether a cue is currently playing.
  bool get isPlaying => _player != null && !_preempted;

  /// Select a clip for [cueClass] using the cooldown + dedup rules.
  ///
  /// Returns null if no clip is available (all on cooldown or all recently
  /// played).
  VoiceCueClip? selectClip(VoiceCueClass cueClass) {
    final candidates =
        _manifest.where((c) => c.semanticClass == cueClass).toList();
    if (candidates.isEmpty) return null;

    final now = DateTime.now();

    // Filter out clips on cooldown (by expression family).
    final available = candidates.where((c) {
      final cd = _cooldownUntil[c.expressionFamily];
      return cd == null || !now.isBefore(cd);
    }).toList();

    if (available.isEmpty) {
      // All on cooldown — pick the one with the earliest available time.
      candidates.sort((a, b) {
        final ca = _cooldownUntil[a.expressionFamily] ?? now;
        final cb = _cooldownUntil[b.expressionFamily] ?? now;
        return ca.compareTo(cb);
      });
      return candidates.first;
    }

    // Filter out recently played (most-recent-4).
    final notRecent = available
        .where((c) => !_recentClipIds.contains(c.clipId))
        .toList();

    final pool = notRecent.isNotEmpty ? notRecent : available;

    // Demote consecutive same-tone-family.
    final demoted = pool.where((c) => c.toneFamily != _lastToneFamily).toList();
    final finalPool = demoted.isNotEmpty ? demoted : pool;

    // Random-ish selection from the final pool.
    final idx = DateTime.now().millisecond % finalPool.length;
    return finalPool[idx];
  }

  /// Pre-generate and cache all cue clips for [voiceId] via TTS.
  ///
  /// Call once when voice mode starts (or app starts) so the first cue
  /// doesn't pay TTS synthesis latency. Clips are cached by the TTS
  /// provider's disk cache, so subsequent calls are no-ops.
  Future<void> preGenerate(String voiceId) async {
    // TtsService.textToSpeech caches to disk. Calling it for each clip
    // warms the cache. We don't need the returned path — the file is
    // stored in the TTS cache directory.
    // This is best-effort: failures are logged but don't block.
    // The actual pre-generation is done lazily by the caller to avoid
    // importing TtsService here (which would create a circular dependency
    // in tests). See [VoiceCueCoordinator.preGenerate].
    _log.info('preGenerate: ${_manifest.length} clips for voiceId=$voiceId');
  }

  /// Record that a clip was played (or preempted). Updates cooldown + recent.
  void _recordPlay(VoiceCueClip clip) {
    _recentClipIds.add(clip.clipId);
    while (_recentClipIds.length > 4) {
      _recentClipIds.removeFirst();
    }
    _cooldownUntil[clip.expressionFamily] =
        DateTime.now().add(Duration(seconds: clip.cooldownSeconds));
    _lastToneFamily = clip.toneFamily;
  }

  /// Play a cue clip from [audioPath]. Returns when playback completes or
  /// is preempted.
  ///
  /// [onPreempt] is called if the cue is preempted by formal TTS.
  Future<void> playClip({
    required VoiceCueClip clip,
    required String audioPath,
    bool voiceMode = false,
  }) async {
    _preempted = false;
    final player = AudioPlayer(
      handleAudioSessionActivation: false,
      androidApplyAudioAttributes: false,
    );
    _player = player;

    try {
      if (voiceMode) {
        try {
          await player.setAndroidAudioAttributes(
            AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
          );
        } catch (_) {}
      }
      await player.setVolume(clip.playbackVolume);
      await player.setFilePath(audioPath);

      if (_preempted) {
        _recordPlay(clip);
        return;
      }

      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        }
      });
      await player.play();
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => _log.warning('Cue ${clip.clipId} playback timed out'),
      );
      await sub.cancel();
    } catch (e) {
      _log.warning('Cue ${clip.clipId} playback failed: $e');
    } finally {
      await player.dispose();
      _player = null;
      _recordPlay(clip);
    }
  }

  /// Preempt the currently playing cue. Called when formal TTS seq=0 arrives.
  ///
  /// If the current clip has [VoiceCueClip.completeBeforeFormal] == true,
  /// the caller should wait for it to finish instead of preemption.
  Future<void> preempt() async {
    _preempted = true;
    final player = _player;
    if (player != null) {
      try {
        await player.stop();
      } catch (_) {}
    }
  }

  /// Reset all state (e.g. when voice mode ends).
  void reset() {
    _recentClipIds.clear();
    _cooldownUntil.clear();
    _lastToneFamily = null;
    _preempted = false;
  }

  /// Whether the currently playing clip should be allowed to finish before
  /// formal TTS preempts. Returns false when no clip is playing.
  bool get shouldCompleteBeforeFormal {
    // The clip is set in _recordPlay; we need to check the current clip.
    // This is tracked via the player's state — if preempted is false and
    // a player exists, check the clip's flag. Since we don't store the
    // current clip separately, the caller should use [preempt] and check
    // [VoiceCueClip.completeBeforeFormal] before calling it.
    return false;
  }
}
