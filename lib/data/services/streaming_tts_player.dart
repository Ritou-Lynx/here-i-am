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
  bool _processingSentence = false;
  bool _llmDone = false;
  bool _disposed = false;
  Completer<void>? _playbackCompleter;
  StreamSubscription<PlayerState>? _stateSub;

  Future<void> start() async {
    _splitter.onSentence = _onSentence;
    _stateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _source.isDone &&
          _sentenceQueue.isEmpty &&
          !_processingSentence) {
        _playbackCompleter?.complete();
      }
    });
    await _player.setAudioSource(_source, preload: false);
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
    _source.markDone();
    if (_source._buffer.isEmpty &&
        !_processingSentence &&
        _sentenceQueue.isEmpty) {
      await _dispose();
      return;
    }
    _playbackCompleter = Completer<void>();
    await _player.play();
    await _playbackCompleter!.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {},
    );
    await _dispose();
  }

  void _onSentence(String sentence) {
    if (_disposed) return;
    _sentenceQueue.add(sentence);
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
      _playbackCompleter?.complete();
    }
  }

  Future<void> cancel() async {
    await _dispose();
  }

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _ttsSubscriptions) {
      await sub.cancel();
    }
    _ttsSubscriptions.clear();
    _sentenceQueue.clear();
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
