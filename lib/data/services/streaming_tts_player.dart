import 'dart:async';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:memex/data/services/tts_service.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/sentence_splitter.dart';

class _GrowingBufferSource extends StreamAudioSource {
  final _buffer = <int>[];
  final _controller = StreamController<Uint8List>.broadcast();
  bool _done = false;

  void addBytes(List<int> bytes) {
    if (_done) return;
    _buffer.addAll(bytes);
    _controller.add(Uint8List.fromList(bytes));
  }

  void markDone() {
    if (_done) return;
    _done = true;
    _controller.close();
  }

  bool get isDone => _done;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final s = start ?? 0;
    final existing = s < _buffer.length
        ? Uint8List.fromList(_buffer.sublist(s, end))
        : Uint8List(0);

    Stream<Uint8List> stream;
    if (_done) {
      stream = existing.isNotEmpty
          ? Stream.value(existing)
          : const Stream.empty();
    } else {
      final merged = StreamController<Uint8List>();
      if (existing.isNotEmpty) merged.add(existing);
      _controller.stream.listen(
        merged.add,
        onError: merged.addError,
        onDone: merged.close,
      );
      stream = merged.stream;
    }

    return StreamAudioResponse(
      sourceLength: _done ? _buffer.length : null,
      contentLength: _done ? (_buffer.length - s) : null,
      offset: s,
      stream: stream,
      contentType: 'audio/mpeg',
    );
  }
}

class StreamingTtsSession {
  StreamingTtsSession({required this.voiceId, this.voiceMode = false});

  final String voiceId;

  /// When true, route playback through the voice-communication audio usage so
  /// it is audible during a VoIP call (notably over Bluetooth HFP, where the
  /// default media stream is suspended). Also keeps TTS on the same stream as
  /// the mic so platform AEC can cancel the echo.
  final bool voiceMode;
  final _log = getLogger('StreamingTts');
  final _player = AudioPlayer();
  final _source = _GrowingBufferSource();
  final _splitter = SentenceSplitter();
  final _ttsSubscriptions = <StreamSubscription<List<int>>>[];
  final _sentenceQueue = <String>[];
  final _pendingSentences = <String>[];
  bool _processingSentence = false;
  bool _llmDone = false;
  bool _disposed = false;

  /// Minimum rune count before a batch of sentences is sent to the TTS API.
  /// Short sentences ("嗯。", "好。", "然后呢。") are buffered until they
  /// accumulate past this threshold, then merged and sent as a single request.
  /// This avoids per-call minimum billing and reduces total API round-trips.
  /// The threshold is low enough that first-audio latency stays acceptable.
  static const int _minSentenceRunes = 24;
  Completer<void>? _playbackCompleter;
  StreamSubscription<PlayerState>? _stateSub;

  Future<void> start() async {
    _splitter.onSentence = _onSentence;
    _log.info('start: voiceId=$voiceId voiceMode=$voiceMode');
    _stateSub = _player.playerStateStream.listen((state) {
      _log.fine('player state: ${state.processingState} playing=${state.playing} '
          'done=${_source.isDone} queue=${_sentenceQueue.length} '
          'proc=$_processingSentence completer=${_playbackCompleter?.isCompleted}');
      if (state.processingState == ProcessingState.completed &&
          _source.isDone &&
          _sentenceQueue.isEmpty &&
          !_processingSentence) {
        _log.info('playback completed');
        _playbackCompleter?.complete();
      } else if (state.processingState == ProcessingState.idle &&
          !state.playing &&
          _playbackCompleter != null &&
          !_playbackCompleter!.isCompleted) {
        // Playback failed (e.g. format probe error) or was stopped early.
        // Complete the completer so the caller does not hang in the speaking
        // phase until the 120s timeout.
        _log.warning('playback stopped/failed before completion');
        _playbackCompleter!.complete();
      }
    });
    await _player.setAudioSource(_source, preload: false);
    _log.info('start: setAudioSource done');
    if (voiceMode) {
      // Pin the Android audio usage to voice-communication explicitly. Relying
      // on just_audio's configurationStream subscription is racy (broadcast
      // stream won't replay the value configured by the unawaited VoIP-session
      // enter), which leaves the player on the default media usage — silent
      // over Bluetooth HFP during a call.
      try {
        await _player.setAndroidAudioAttributes(
          const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
        );
      } catch (e) {
        _log.warning('set voice-communication audio attributes failed: $e');
      }
    }
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

    // Wait for every queued sentence to finish streaming its audio bytes into
    // the buffer before marking the source done. Marking done too early (with
    // an empty buffer) makes ExoPlayer's format probe read EOF and fail with
    // UnrecognizedInputFormatException, so the reply is never heard — the
    // bytes that arrive afterwards are also dropped by addBytes().
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (_processingSentence ||
        _sentenceQueue.isNotEmpty ||
        _ttsSubscriptions.isNotEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        _log.warning('finishAndWait: TTS sentences timed out');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _log.info('finishAndWait: sentences done, bufferBytes=${_source._buffer.length}');
    if (_source._buffer.isEmpty) {
      // Nothing was synthesized (e.g. all text filtered); nothing to play.
      await _dispose();
      return;
    }
    _source.markDone();
    _playbackCompleter = Completer<void>();
    _log.info('finishAndWait: play()');
    await _player.play();
    await _playbackCompleter!.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () => _log.warning('finishAndWait: playback timed out'),
    );
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
      final stream = TtsService.streamTextToSpeech(
        text: sentence,
        voiceId: voiceId,
      );
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;
      sub = stream.listen(
        (bytes) {
          if (!_disposed) _source.addBytes(bytes);
        },
        onError: (Object e) {
          _log.warning('TTS stream error: $e');
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          _ttsSubscriptions.remove(sub);
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      _ttsSubscriptions.add(sub);
      await completer.future;
    } catch (e) {
      _log.warning('TTS sentence failed: $e');
    }
    _processingSentence = false;
    if (_sentenceQueue.isNotEmpty) {
      _processNextSentence();
    } else if (_llmDone && _ttsSubscriptions.isEmpty && _source.isDone) {
      // Playback completion is owned by finishAndWait: the completer is only
      // created after markDone()+play(), and completing it here races with
      // play() and would cut the audio off (or hang the speaking phase).
    }
  }

  Future<void> cancel() async {
    await _dispose();
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _log.info('_dispose: bufferBytes=${_source._buffer.length}');
    for (final sub in _ttsSubscriptions) {
      await sub.cancel();
    }
    _ttsSubscriptions.clear();
    _sentenceQueue.clear();
    _pendingSentences.clear();
    await _stateSub?.cancel();
    _stateSub = null;
    await _player.stop();
    await _player.dispose();
    _source.markDone();
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      _playbackCompleter!.complete();
    }
  }
}
