import 'dart:async';
import 'dart:io';

import 'package:memex/data/services/ordered_tts_queue.dart';
import 'package:memex/data/services/tts_service.dart';
import 'package:memex/domain/models/voice_turn_identity.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/sentence_splitter.dart';

/// Streaming TTS pipeline: feeds LLM text chunks to a sentence splitter,
/// synthesizes each sentence batch to audio, and plays segments in order.
///
/// Key improvements over the previous version (Cove GPT-Live identity protocol):
/// - Each segment carries a [VoiceTurnIdentity] + [seq]. Stale segments from a
///   previous generation are silently discarded by [OrderedTtsQueue].
/// - Segments are pushed to [OrderedTtsQueue] as soon as they're synthesized —
///   playback starts on the first segment without waiting for the LLM to
///   finish (pipeline / 边收边播).
/// - [cancel] is atomic: the queue drops all pending segments and stops the
///   current player. A stale `AudioPlayer.play()` Promise cannot mutate state
///   via the non-reusable playback claim in [OrderedTtsQueue].
class StreamingTtsSession {
  StreamingTtsSession({
    required this.voiceId,
    this.voiceMode = false,
    this.identity,
  });

  final String voiceId;

  /// When true, route playback through the voice-communication audio usage so
  /// it is audible during a VoIP call (notably over Bluetooth HFP, where the
  /// default media stream is suspended). Also keeps TTS on the same stream as
  /// the mic so platform AEC can cancel the echo.
  final bool voiceMode;

  /// Identity for this TTS generation. All segments produced by this session
  /// carry this identity. When null, a throwaway identity is used (backward
  /// compat for callers not yet migrated to the identity protocol).
  final VoiceTurnIdentity? identity;

  static final _log = getLogger('StreamingTts');

  final _splitter = SentenceSplitter();
  final _sentenceQueue = <String>[];
  final _pendingSentences = <String>[];

  bool _processingSentence = false;
  bool _llmDone = false;
  bool _disposed = false;
  int _seq = 0;

  late final OrderedTtsQueue _queue;

  /// Minimum rune count before a batch of sentences is sent to the TTS API.
  /// Short sentences ("嗯。", "好。", "然后呢。") are buffered until they
  /// accumulate past this threshold, then merged and sent as a single request.
  /// This avoids per-call minimum billing and reduces total API round-trips.
  ///
  /// Kept low (8) so a short reply in a voice call starts speaking quickly —
  /// a high threshold delays the first audio by however long it takes the
  /// LLM to accumulate more text, which users read as "slow to reply".
  static const int _minSentenceRunes = 8;

  /// Called when a segment starts playing. Useful for syncing subtitles.
  void Function(TtsSegment segment)? onSegmentStart;

  /// Called when all segments have finished playing (queue drained + LLM done).
  void Function()? onAllSegmentsPlayed;

  Future<void> start() async {
    _splitter.onSentence = _onSentence;
    _queue = OrderedTtsQueue(
      identity: identity ?? _throwawayIdentity(),
      voiceMode: voiceMode,
    );
    _queue.onSegmentStart = (segment) => onSegmentStart?.call(segment);
    _queue.onQueueDrained = () {
      if (_llmDone && _sentenceQueue.isEmpty && !_processingSentence) {
        onAllSegmentsPlayed?.call();
      }
    };
    _log.info(
        'start: voiceId=$voiceId voiceMode=$voiceMode identity=$identity');
  }

  void feedText(String chunk) {
    if (_disposed) return;
    _splitter.feed(chunk);
  }

  /// Signal that the LLM stream has finished and wait for all TTS segments to
  /// finish synthesizing and playing.
  ///
  /// Returns when the [OrderedTtsQueue] drains (all segments played).
  Future<void> finishAndWait() async {
    if (_disposed) return;
    _llmDone = true;
    _splitter.finish();
    _flushPendingSentences();
    _log.info('finishAndWait: waiting for synthesis + playback...');

    // Wait for all sentences to finish synthesizing.
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (_processingSentence || _sentenceQueue.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        _log.warning('finishAndWait: synthesis timed out');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // Mark the queue as done so onQueueDrained can fire.
    _queue.markDone();

    // Wait on the queue's actual drain coroutine, not a sampled
    // pending/isPlaying pair: between removing a pending segment and entering
    // playback both used to be false, so fast cache hits were cancelled before
    // the first sound reached the speaker.
    try {
      await _queue.waitUntilDrained().timeout(const Duration(seconds: 120));
    } on TimeoutException {
      _log.warning('finishAndWait: playback timed out');
    }

    _log.info('finishAndWait: all segments played');
    await _dispose();
  }

  Future<void> cancel() async {
    await _dispose();
  }

  /// Duck or restore active playback without cancelling the generation.
  Future<void> setVolume(double volume) => _queue.setVolume(volume);

  void _onSentence(String sentence) {
    if (_disposed) return;
    _pendingSentences.add(sentence);
    _tryFlushPending();
  }

  void _tryFlushPending() {
    if (_pendingSentences.isEmpty) return;
    final merged = _pendingSentences.join('\n');
    if (merged.runes.length >= _minSentenceRunes || _llmDone) {
      _pendingSentences.clear();
      _sentenceQueue.add(merged);
      unawaited(_processNextSentence());
    }
  }

  void _flushPendingSentences() {
    if (_pendingSentences.isEmpty) return;
    final merged = _pendingSentences.join('\n');
    _pendingSentences.clear();
    _sentenceQueue.add(merged);
    unawaited(_processNextSentence());
  }

  Future<void> _processNextSentence() async {
    if (_processingSentence || _sentenceQueue.isEmpty || _disposed) return;
    _processingSentence = true;
    final sentence = _sentenceQueue.removeAt(0);
    final currentSeq = _seq++;
    try {
      final bytes = <int>[];
      final stream = TtsService.streamTextToSpeech(
        text: sentence,
        voiceId: voiceId,
      );
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = stream.listen(
        (chunk) {
          if (!_disposed) bytes.addAll(chunk);
        },
        onError: (Object e) {
          _log.warning('TTS stream error: $e');
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future;
      await sub.cancel();

      if (!_disposed) {
        if (bytes.isEmpty) {
          // TTS synthesis failed / returned empty bytes. Push a silent
          // placeholder segment so the OrderedTtsQueue does not get stuck
          // waiting for this seq forever (seq gap would deadlock the queue).
          _log.warning(
              'TTS seq=$currentSeq returned empty, pushing placeholder');
        }
        final file = File(
          '${Directory.systemTemp.path}/tts_seg_'
          '${DateTime.now().microsecondsSinceEpoch}_$currentSeq.mp3',
        );
        if (bytes.isNotEmpty) {
          await file.writeAsBytes(bytes, flush: true);
          _log.fine('segment seq=$currentSeq: ${bytes.length} bytes');
        } else {
          // Write a minimal silent mp3 placeholder (48-byte valid mp3 header
          // with no audio frames) so the queue does not skip this seq.
          await file.writeAsBytes([
            0xFF,
            0xFB,
            0x90,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
            0x00,
          ], flush: true);
        }

        final segment = TtsSegment(
          identity: identity ?? _throwawayIdentity(),
          seq: currentSeq,
          file: file,
          text: sentence,
        );
        final result = _queue.push(segment);
        if (result == TtsQueuePushResult.staleIdentity) {
          _log.fine('Segment seq=$currentSeq rejected (stale identity)');
        }
      }
    } catch (e) {
      _log.warning('TTS sentence failed: $e');
    }
    _processingSentence = false;
    if (_sentenceQueue.isNotEmpty) {
      unawaited(_processNextSentence());
    }
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _log.info('_dispose');
    _sentenceQueue.clear();
    _pendingSentences.clear();
    try {
      await _queue.cancel();
    } catch (e) {
      _log.warning('queue cancel error: $e');
    }
  }

  VoiceTurnIdentity _throwawayIdentity() {
    return const VoiceTurnIdentity(
      callSessionId: 'throwaway',
      turnId: 'throwaway',
      turnSequence: 0,
      generationId: 'throwaway',
    );
  }
}
