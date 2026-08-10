import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:memex/data/services/tts_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/sentence_splitter.dart';

class StreamingTtsSession {
  StreamingTtsSession({required this.voiceId, this.voiceMode = false});

  final String voiceId;

  /// When true, route playback through the voice-communication audio usage so
  /// it is audible during a VoIP call (notably over Bluetooth HFP, where the
  /// default media stream is suspended). Also keeps TTS on the same stream as
  /// the mic so platform AEC can cancel the echo.
  final bool voiceMode;
  final _log = getLogger('StreamingTts');
  final _splitter = SentenceSplitter();
  final _sentenceQueue = <String>[];
  final _pendingSentences = <String>[];
  final _segmentFiles = <File>[];
  bool _processingSentence = false;
  bool _llmDone = false;
  bool _disposed = false;

  /// Minimum rune count before a batch of sentences is sent to the TTS API.
  /// Short sentences ("嗯。", "好。", "然后呢。") are buffered until they
  /// accumulate past this threshold, then merged and sent as a single request.
  /// This avoids per-call minimum billing and reduces total API round-trips.
  /// The threshold is low enough that first-audio latency stays acceptable.
  static const int _minSentenceRunes = 24;

  /// The currently active AudioPlayer for a single segment. A fresh player is
  /// created per segment to avoid any ExoPlayer state carry-over between
  /// independent MP3 files (which caused double-playback glitches with both
  /// StreamAudioSource byte concatenation and ConcatenatingAudioSource).
  AudioPlayer? _segmentPlayer;

  Future<void> start() async {
    _splitter.onSentence = _onSentence;
    _log.info('start: voiceId=$voiceId voiceMode=$voiceMode');
  }

  void feedText(String chunk) {
    if (_disposed) return;
    _splitter.feed(chunk);
  }

  Future<void> finishAndWait() async {
    if (_disposed) return;
    _llmDone = true;
    _splitter.finish();
    _flushPendingSentences();
    _log.info('finishAndWait: waiting for TTS sentences...');

    // Wait for every queued sentence to finish synthesizing and writing its
    // audio bytes to a temp file.
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (_processingSentence || _sentenceQueue.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        _log.warning('finishAndWait: TTS sentences timed out');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _log.info(
        'finishAndWait: sentences done, segments=${_segmentFiles.length}');
    if (_segmentFiles.isEmpty) {
      await _dispose();
      return;
    }

    // Play each segment with its own AudioPlayer, sequentially. A fresh
    // player per file avoids ExoPlayer re-seeking / double-playback glitches
    // that occur when independent MP3 files share a single player (whether
    // via StreamAudioSource byte concatenation or ConcatenatingAudioSource).
    for (var i = 0; i < _segmentFiles.length; i++) {
      if (_disposed) break;
      final file = _segmentFiles[i];
      if (!await file.exists() || file.lengthSync() == 0) continue;

      _log.info('finishAndWait: playing segment $i/${_segmentFiles.length} '
          '(${file.lengthSync()} bytes)');

      final player = AudioPlayer();
      if (voiceMode) {
        try {
          await player.setAndroidAudioAttributes(
            const AndroidAudioAttributes(
              contentType: AndroidAudioContentType.speech,
              usage: AndroidAudioUsage.voiceCommunication,
            ),
          );
        } catch (e) {
          _log.warning('set audio attributes failed: $e');
        }
      }
      _segmentPlayer = player;

      try {
        await player.setFilePath(file.path);
        final segmentCompleter = Completer<void>();
        late StreamSubscription sub;
        sub = player.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            sub.cancel();
            if (!segmentCompleter.isCompleted) segmentCompleter.complete();
          }
        });
        await player.play();
        await segmentCompleter.future.timeout(
          const Duration(seconds: 90),
          onTimeout: () => _log.warning('segment $i playback timed out'),
        );
        await sub.cancel();
      } catch (e) {
        _log.warning('segment $i playback failed: $e');
      } finally {
        await player.dispose();
        _segmentPlayer = null;
      }
    }

    _log.info('finishAndWait: all segments played');
    await _dispose();
  }

  void _onSentence(String sentence) {
    if (_disposed) return;
    _pendingSentences.add(sentence);
    _tryFlushPending();
  }

  /// Merge buffered short sentences once they exceed [_minSentenceRunes] and
  /// enqueue the merged text for TTS. Long sentences are enqueued immediately
  /// (with any pending short prefix batched in front of them).
  void _tryFlushPending() {
    if (_pendingSentences.isEmpty) return;
    final merged = _pendingSentences.join('\n');
    if (merged.runes.length >= _minSentenceRunes || _llmDone) {
      _pendingSentences.clear();
      _sentenceQueue.add(merged);
      _processNextSentence();
    }
  }

  /// Flush any remaining short sentences after the LLM stream finishes.
  void _flushPendingSentences() {
    if (_pendingSentences.isEmpty) return;
    final merged = _pendingSentences.join('\n');
    _pendingSentences.clear();
    _sentenceQueue.add(merged);
    _processNextSentence();
  }

  Future<void> _processNextSentence() async {
    if (_processingSentence || _sentenceQueue.isEmpty || _disposed) return;
    _processingSentence = true;
    final sentence = _sentenceQueue.removeAt(0);
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

      if (!_disposed && bytes.isNotEmpty) {
        final file = File(
          '${Directory.systemTemp.path}/tts_seg_'
          '${DateTime.now().microsecondsSinceEpoch}_${_segmentFiles.length}.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        _segmentFiles.add(file);
        _log.fine('segment ${_segmentFiles.length}: ${bytes.length} bytes');
      }
    } catch (e) {
      _log.warning('TTS sentence failed: $e');
    }
    _processingSentence = false;
    if (_sentenceQueue.isNotEmpty) {
      _processNextSentence();
    }
  }

  Future<void> cancel() async {
    await _dispose();
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _log.info('_dispose: segments=${_segmentFiles.length}');
    _sentenceQueue.clear();
    _pendingSentences.clear();
    await _segmentPlayer?.dispose();
    _segmentPlayer = null;
    // Clean up temp files.
    for (final file in _segmentFiles) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    _segmentFiles.clear();
  }
}
