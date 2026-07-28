import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:memex/data/services/asr/alibaba_asr_client.dart';
import 'package:memex/data/services/asr/alibaba_streaming_asr_client.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/utils/logger.dart';

enum VoiceInputState { idle, recording, processing }

const _voiceEndpointPollInterval = Duration(milliseconds: 200);
const _voiceEndpointInitialSilenceTimeout = Duration(seconds: 4);
const _voiceEndpointTrailingSilenceTimeout = Duration(milliseconds: 1500);
const _voiceEndpointMaxRecordingDuration = Duration(seconds: 60);
const _voiceEndpointSpeechThresholdDb = -45.0;

/// Drives the press-to-talk recording -> ASR pipeline.
///
/// Two modes:
///
/// **File mode** (press-to-talk, default):
///   idle ──toggle()──▶ recording ──toggle()──▶ processing ──(ASR)──▶ idle
///                          │
///                          └────cancel()────▶ idle (recording discarded)
///
///   Uses [AlibabaAsrClient] one-shot file recognition + amplitude-based
///   endpoint detection. Suitable for single-shot voice input buttons.
///
/// **Streaming mode** (voice call / inline voice mode):
///   idle ──startStreaming()──▶ streaming ──stopStreaming()──▶ idle
///                                   │
///                          ┌────────┴────────┐
///                  onStreamingEvent()   onStreamingSentence()
///
///   Uses [AlibabaStreamingAsrClient] real-time WebSocket ASR with server-side
///   VAD. The mic stays open; the server emits [SentenceBeginEvent] /
///   [SentenceEndEvent] events. No amplitude thresholding, no trailing-silence
///   timer - the NLS VAD is far more robust at distinguishing speech from
///   background noise.
///
/// Owned by the screen that uses it; call [dispose] when the screen unmounts.
class VoiceInputController extends ChangeNotifier {
  static final Logger _logger = getLogger('VoiceInputController');

  final AudioRecorder _recorder = AudioRecorder();

  VoiceInputState _state = VoiceInputState.idle;
  String? _currentPath;
  AsrClient? _asrClient;
  StreamSubscription<Amplitude>? _amplitudeSub;
  Timer? _endpointPollTimer;
  Timer? _watchdogTimer;
  DateTime? _recordingStartedAt;
  DateTime? _lastSpeechAt;
  Duration _autoStopInitialSilenceTimeout = _voiceEndpointInitialSilenceTimeout;
  Duration _autoStopMaxRecordingDuration = _voiceEndpointMaxRecordingDuration;
  bool _heardSpeech = false;
  bool _autoStopEnabled = false;
  bool _autoStopInProgress = false;
  bool _amplitudePollInProgress = false;

  // Streaming-mode state ------------------------------------------------
  AlibabaStreamingAsrClient? _streamingClient;
  StreamSubscription<StreamingAsrEvent>? _streamingEventSub;
  StreamSubscription<Uint8List>? _streamingAudioSub;
  bool _streamingStopping = false;
  bool _audioForwardingPaused = false;
  Timer? _bargeInPollTimer;
  bool _bargeInPollInProgress = false;

  static const double _bargeInThresholdDb = -25.0;
  static const Duration _bargeInPollInterval = Duration(milliseconds: 150);

  /// Called when automatic endpoint detection stops a recording (file mode).
  ///
  /// [text] is null when the recording was empty, too short, or ASR returned
  /// no usable text. The owner can decide whether to keep listening.
  Future<void> Function(String? text)? onAutoRecognitionComplete;

  /// Called for each [StreamingAsrEvent] in streaming mode (barge-in hook).
  ///
  /// Fires on the UI isolate as soon as the server emits the event. Use
  /// [SentenceBeginEvent] to interrupt TTS playback (barge-in) and
  /// [SentenceEndEvent] to dispatch the final text to the LLM.
  void Function(StreamingAsrEvent event)? onStreamingEvent;

  /// Called when client-side amplitude detection fires during TTS playback
  /// (barge-in). The threshold is high (-25 dB) so only real user speech
  /// triggers it, not speaker echo.
  void Function()? onBargeInDetected;

  /// Called when the streaming ASR session is lost unexpectedly (NLS WebSocket
  /// closed, server-side timeout, or event stream errored) while the user has
  /// not hung up. The owner should re-arm the mic by calling [startStreaming]
  /// again (the controller will already be back in [VoiceInputState.idle] and
  /// [isStreaming] will report false).
  ///
  /// Not fired during a graceful [stopStreaming] / [cancelStreaming].
  void Function()? onStreamingSessionLost;

  /// Last error message (for UI to surface). Cleared on next toggle.
  String? lastError;

  VoiceInputState get state => _state;
  bool get isRecording => _state == VoiceInputState.recording;
  bool get isProcessing => _state == VoiceInputState.processing;
  bool get isStreaming => _streamingClient != null;

  /// Toggle recording. From idle -> start; from recording -> stop & recognize.
  /// While processing, calls are ignored.
  ///
  /// Returns the recognized text on the recording -> idle transition, null
  /// otherwise. If ASR fails, returns null and sets [lastError].
  Future<String?> toggle({
    bool autoStop = false,
    Duration? initialSilenceTimeout,
    Duration? maxRecordingDuration,
  }) async {
    switch (_state) {
      case VoiceInputState.idle:
        await start(
          autoStop: autoStop,
          initialSilenceTimeout: initialSilenceTimeout,
          maxRecordingDuration: maxRecordingDuration,
        );
        return null;
      case VoiceInputState.recording:
        return stopAndRecognize();
      case VoiceInputState.processing:
        return null;
    }
  }

  /// Start recording if the controller is idle.
  Future<void> start({
    bool autoStop = false,
    Duration? initialSilenceTimeout,
    Duration? maxRecordingDuration,
  }) async {
    if (_state != VoiceInputState.idle) return;
    await _start(
      autoStop: autoStop,
      initialSilenceTimeout: initialSilenceTimeout,
      maxRecordingDuration: maxRecordingDuration,
    );
  }

  /// Stop the current recording and run ASR.
  Future<String?> stopAndRecognize() async {
    if (_state != VoiceInputState.recording) return null;
    return _stopAndRecognize();
  }

  /// Cancel an in-progress recording without sending it to ASR.
  /// No-op if not recording.
  Future<void> cancel() async {
    if (_state != VoiceInputState.recording) return;
    try {
      await _recorder.stop();
    } catch (e) {
      _logger.warning('cancel: stop error: $e');
    }
    await _stopEndpointDetection();
    await _deleteCurrentFile();
    _state = VoiceInputState.idle;
    notifyListeners();
    _logger.info('Recording cancelled');
  }

  // ── Streaming mode ───────────────────────────────────────────────────────

  /// Start a streaming ASR session. The mic stays open until [stopStreaming]
  /// or [cancelStreaming] is called. Server-side VAD drives sentence events
  /// via [onStreamingEvent].
  ///
  /// Uses `record.startStream` with `AudioEncoder.pcm16bits` + echo cancel +
  /// noise suppress. PCM chunks are forwarded directly to the NLS gateway
  /// without touching local storage.
  Future<void> startStreaming() async {
    if (_state != VoiceInputState.idle) {
      _logger.warning('startStreaming called in state $_state - ignoring');
      return;
    }
    if (_streamingClient != null) {
      _logger.warning('startStreaming called but session already active');
      return;
    }

    // Always start with audio forwarding enabled. A previous TTS pause may
    // have left the flag set; the new session needs a clean slate.
    _audioForwardingPaused = false;

    lastError = null;

    final config = await AsrConfig.load();
    if (config == null) {
      lastError = 'ASR 凭证未配置，请到设置 -> 语音输入填入阿里 NLS 凭证';
      notifyListeners();
      return;
    }

    if (!await _recorder.hasPermission()) {
      lastError = '麦克风权限未授予';
      notifyListeners();
      return;
    }

    _streamingClient = AlibabaStreamingAsrClient(config);

    Stream<StreamingAsrEvent> events;
    try {
      events = await _streamingClient!.start();
    } catch (e) {
      _logger.severe('Streaming ASR start failed: $e');
      lastError = '流式 ASR 启动失败: $e';
      await _streamingClient!.dispose();
      _streamingClient = null;
      notifyListeners();
      return;
    }

    _state = VoiceInputState.recording;
    _recordingStartedAt = DateTime.now();
    notifyListeners();

    _streamingEventSub = events.listen(
      (event) {
        onStreamingEvent?.call(event);
        if (event is SentenceEndEvent) {
          _logger.info('Streaming sentence #${event.index}: '
              '"${event.text.length > 60 ? '${event.text.substring(0, 60)}...' : event.text}"');
        }
      },
      onError: (Object e, StackTrace st) {
        _logger.severe('Streaming ASR event stream error: $e');
        lastError = '流式 ASR 错误: $e';
        _handleStreamingSessionLost();
      },
      onDone: () {
        _logger.info('Streaming ASR event stream done');
        _handleStreamingSessionLost();
      },
    );

    try {
      final audioStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          // VoIP call path: route mic through the voice-call audio source so
          // the platform AEC cancels speaker echo (TTS output) from the mic
          // signal, and set MODE_IN_COMMUNICATION so mic + speaker coexist.
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
          ),
        ),
      );
      _streamingAudioSub = audioStream.listen(
        (chunk) {
          if (!_audioForwardingPaused) {
            _streamingClient?.sendAudio(chunk);
          }
        },
        onError: (Object e) {
          _logger.warning('Audio stream error: $e');
        },
      );
    } catch (e) {
      _logger.severe('Failed to start PCM stream: $e');
      lastError = '启动录音失败: $e';
      await _cancelStreamingInternal();
      notifyListeners();
      return;
    }

    _logger.info('Streaming session started');
  }

  /// Gracefully stop the streaming session. Sends [StopTranscription] to the
  /// server, waits for [TranscriptionCompleted], and tears down the mic.
  Future<void> stopStreaming() async {
    if (_streamingClient == null || _streamingStopping) return;
    _streamingStopping = true;

    _state = VoiceInputState.processing;
    notifyListeners();

    try {
      await _streamingAudioSub?.cancel();
    } catch (e) {
      _logger.warning('streaming audio sub cancel: $e');
    }
    _streamingAudioSub = null;

    try {
      await _recorder.stop();
    } catch (e) {
      _logger.warning('streaming recorder stop: $e');
    }

    try {
      await _streamingClient?.stop();
    } catch (e) {
      _logger.warning('streaming client stop: $e');
    }

    await _cancelStreamingInternal();
    _streamingStopping = false;
    _state = VoiceInputState.idle;
    notifyListeners();
    _logger.info('Streaming session stopped');
  }

  /// Hard-cancel a streaming session without the graceful stop handshake.
  /// Use when the user hung up or the screen is unmounting mid-session.
  Future<void> cancelStreaming() async {
    if (_streamingClient == null) return;
    await _cancelStreamingInternal();
    _state = VoiceInputState.idle;
    notifyListeners();
    _logger.info('Streaming session cancelled');
  }

  /// Pause forwarding mic audio to the NLS server. Call this while TTS is
  /// playing so the speaker output is not recognized as user speech (echo
  /// loop) — a fallback for devices where the platform AEC leaks echo. The
  /// mic stays open (VoIP call audio session keeps mic + speaker coexisting),
  /// chunks are simply dropped. Starts barge-in amplitude polling so the user
  /// can interrupt by speaking.
  ///
  /// This is a defense-in-depth guard. With the TTS player routed through the
  /// voice-communication stream (see `_voiceCallTtsContext`), the platform AEC
  /// should cancel speaker echo and the NLS server-side VAD will not fire on
  /// TTS output. The pause + amplitude poller catches any residual echo that
  /// slips past AEC on misbehaving devices.
  void pauseAudioForwarding() {
    _audioForwardingPaused = true;
    startBargeInDetection();
  }

  /// Resume forwarding mic audio to the NLS server after TTS stops. If the NLS
  /// session was lost during TTS (idle timeout while audio was paused), the
  /// [onStreamingSessionLost] path already reset state to idle; the caller's
  /// TTS-complete handler re-arms the mic via [startStreaming].
  void resumeAudioForwarding() {
    _audioForwardingPaused = false;
    stopBargeInDetection();
  }

  /// Start polling mic amplitude while TTS plays. If the level exceeds
  /// [_bargeInThresholdDb] (-25 dB, well above speaker echo), fire
  /// [onBargeInDetected] so the UI can stop TTS and resume forwarding.
  void startBargeInDetection() {
    if (_bargeInPollTimer != null) return;
    _bargeInPollTimer = Timer.periodic(
      _bargeInPollInterval,
      (_) => unawaited(_pollBargeInAmplitude()),
    );
  }

  void stopBargeInDetection() {
    _bargeInPollTimer?.cancel();
    _bargeInPollTimer = null;
    _bargeInPollInProgress = false;
  }

  Future<void> _pollBargeInAmplitude() async {
    if (_bargeInPollInProgress || _bargeInPollTimer == null) return;
    _bargeInPollInProgress = true;
    try {
      final amplitude = await _recorder
          .getAmplitude()
          .timeout(const Duration(seconds: 1), onTimeout: () {
        return Amplitude(current: -160.0, max: -160.0);
      });
      if (amplitude.current >= _bargeInThresholdDb) {
        _logger.info(
          'Barge-in detected: ${amplitude.current.toStringAsFixed(1)}dB '
          '>= ${_bargeInThresholdDb}dB',
        );
        stopBargeInDetection();
        onBargeInDetected?.call();
      }
    } catch (e) {
      _logger.fine('Barge-in poll error: $e');
    } finally {
      _bargeInPollInProgress = false;
    }
  }

  Future<void> _cancelStreamingInternal() async {
    stopBargeInDetection();
    _audioForwardingPaused = false;
    try {
      await _streamingAudioSub?.cancel();
    } catch (e) {
      _logger.warning('streaming audio sub cancel: $e');
    }
    _streamingAudioSub = null;

    try {
      await _streamingEventSub?.cancel();
    } catch (e) {
      _logger.warning('streaming event sub cancel: $e');
    }
    _streamingEventSub = null;

    try {
      await _recorder.stop();
    } catch (e) {
      _logger.fine('recorder stop during streaming teardown: $e');
    }

    final client = _streamingClient;
    _streamingClient = null;
    if (client != null) {
      try {
        await client.dispose();
      } catch (e) {
        _logger.warning('streaming client dispose: $e');
      }
    }
  }

  /// Handles an unexpected end of the NLS event stream (server closed the
  /// WebSocket, idle timeout, or stream error) while the user has not hung up.
  ///
  /// Two cases:
  /// * **TTS playing** (`_audioForwardingPaused`): the NLS idle-close is
  ///   expected (no audio was sent). Only dispose the NLS client so
  ///   [isStreaming] reports false — the mic stays open (VoIP call session
  ///   owns it) and the TTS-complete handler re-arms a fresh NLS session.
  /// * **Otherwise**: full teardown (mic + client) so the owner can re-arm.
  ///
  /// Skipped when a graceful [stopStreaming] / [cancelStreaming] is already in
  /// progress ([_streamingStopping] == true).
  void _handleStreamingSessionLost() {
    if (_streamingStopping || _streamingClient == null) return;
    if (_audioForwardingPaused) {
      // TTS owns the lifecycle; do a full teardown so startStreaming can
      // re-arm cleanly later, but don't fire onStreamingSessionLost (the
      // TTS-complete handler re-arms the mic itself).
      _logger.info('NLS session closed during TTS; full teardown (no callback)');
      unawaited(() async {
        await _cancelStreamingInternal();
        _streamingStopping = false;
        _state = VoiceInputState.idle;
        notifyListeners();
      }());
      return;
    }
    _logger.warning('Streaming session lost unexpectedly; tearing down mic');
    // Run the full internal teardown so the recorder is released and state
    // resets to idle. Fire-and-forget; the callback notifies the owner.
    unawaited(() async {
      await _cancelStreamingInternal();
      _streamingStopping = false;
      _state = VoiceInputState.idle;
      notifyListeners();
      onStreamingSessionLost?.call();
    }());
  }

  // ── File-mode internals (unchanged) ──────────────────────────────────────

  Future<void> _start({
    required bool autoStop,
    Duration? initialSilenceTimeout,
    Duration? maxRecordingDuration,
  }) async {
    lastError = null;

    final config = await AsrConfig.load();
    if (config == null) {
      lastError = 'ASR 凭证未配置，请到设置 -> 语音输入填入阿里 NLS 凭证';
      notifyListeners();
      return;
    }
    _asrClient = AlibabaAsrClient(config);

    if (!await _recorder.hasPermission()) {
      lastError = '麦克风权限未授予';
      notifyListeners();
      return;
    }

    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'voice_input_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _currentPath = path;
      _state = VoiceInputState.recording;
      _recordingStartedAt = DateTime.now();
      _lastSpeechAt = null;
      _autoStopInitialSilenceTimeout =
          initialSilenceTimeout ?? _voiceEndpointInitialSilenceTimeout;
      _autoStopMaxRecordingDuration =
          maxRecordingDuration ?? _voiceEndpointMaxRecordingDuration;
      _heardSpeech = false;
      _autoStopEnabled = autoStop;
      _autoStopInProgress = false;
      if (autoStop) {
        _startEndpointDetection();
      }
      _logger.info('Recording started -> $path');
      notifyListeners();
    } catch (e) {
      lastError = '启动录音失败: $e';
      _logger.severe('start error: $e');
      notifyListeners();
    }
  }

  Future<String?> _stopAndRecognize() async {
    await _stopEndpointDetection();
    _state = VoiceInputState.processing;
    notifyListeners();

    String? recordedPath;
    try {
      recordedPath = await _recorder.stop();
    } catch (e) {
      _logger.severe('stop error: $e');
      lastError = '停止录音失败: $e';
      _state = VoiceInputState.idle;
      _clearEndpointState();
      notifyListeners();
      return null;
    }

    final path = recordedPath ?? _currentPath;
    if (path == null) {
      lastError = '录音文件路径为空';
      _state = VoiceInputState.idle;
      _clearEndpointState();
      notifyListeners();
      return null;
    }

    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1024) {
      _logger.warning(
          'Recording too short (${file.existsSync() ? file.lengthSync() : 0} bytes), skipping ASR');
      lastError = '录音过短';
      await _deleteCurrentFile();
      _state = VoiceInputState.idle;
      _clearEndpointState();
      notifyListeners();
      return null;
    }

    try {
      final text = await _asrClient!.recognize(file);
      _logger.info('ASR result: "$text"');
      await _deleteCurrentFile();
      _state = VoiceInputState.idle;
      _clearEndpointState();
      notifyListeners();
      return text.trim().isEmpty ? null : text.trim();
    } catch (e) {
      _logger.severe('ASR error: $e');
      lastError = '识别失败: $e';
      await _deleteCurrentFile();
      _state = VoiceInputState.idle;
      _clearEndpointState();
      notifyListeners();
      return null;
    }
  }

  void _startEndpointDetection() {
    _endpointPollTimer?.cancel();
    _endpointPollTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    unawaited(_amplitudeSub?.cancel());
    _amplitudeSub = null;
    _amplitudePollInProgress = false;
    _logger.info(
      'Voice endpoint detection started: '
      'threshold=${_voiceEndpointSpeechThresholdDb.toStringAsFixed(1)}dB '
      'trailing=${_voiceEndpointTrailingSilenceTimeout.inMilliseconds}ms '
      'initial=${_autoStopInitialSilenceTimeout.inMilliseconds}ms '
      'max=${_autoStopMaxRecordingDuration.inMilliseconds}ms',
    );
    _amplitudeSub = _recorder
        .onAmplitudeChanged(_voiceEndpointPollInterval)
        .listen(_handleAmplitude, onError: (Object e) {
      _logger.warning('Amplitude monitor error: $e');
    });
    _endpointPollTimer = Timer.periodic(
      _voiceEndpointPollInterval,
      (_) => unawaited(_pollEndpointAmplitude()),
    );
    _watchdogTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _watchdogCheck(),
    );
  }

  void _watchdogCheck() {
    if (!_autoStopEnabled ||
        _state != VoiceInputState.recording ||
        _autoStopInProgress) {
      return;
    }
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed >= _autoStopMaxRecordingDuration) {
      _logger.warning(
        'Watchdog: max recording duration exceeded (${elapsed.inSeconds}s), '
        'forcing auto-stop',
      );
      _autoStopInProgress = true;
      unawaited(_autoStopAndRecognize());
    }
  }

  Future<void> _pollEndpointAmplitude() async {
    if (!_autoStopEnabled ||
        _state != VoiceInputState.recording ||
        _autoStopInProgress ||
        _amplitudePollInProgress) {
      return;
    }
    _amplitudePollInProgress = true;
    try {
      final amplitude = await _recorder
          .getAmplitude()
          .timeout(const Duration(seconds: 2), onTimeout: () {
        _logger.warning('Amplitude poll timeout');
        return Amplitude(current: -160.0, max: -160.0);
      });
      _handleAmplitude(amplitude);
    } catch (e) {
      _logger.warning('Amplitude poll error: $e');
    } finally {
      _amplitudePollInProgress = false;
    }
  }

  void _handleAmplitude(Amplitude amplitude) {
    if (!_autoStopEnabled ||
        _state != VoiceInputState.recording ||
        _autoStopInProgress) {
      return;
    }

    final now = DateTime.now();
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return;

    final isSpeech = voiceInputAmplitudeIsSpeech(amplitude.current);
    if (isSpeech) {
      _heardSpeech = true;
      _lastSpeechAt = now;
    }

    _logger.fine(
      'Amplitude: current=${amplitude.current.toStringAsFixed(1)}dB '
      'max=${amplitude.max.toStringAsFixed(1)}dB '
      'speech=$isSpeech heardSpeech=$_heardSpeech',
    );

    if (!voiceInputShouldAutoStop(
      now: now,
      startedAt: startedAt,
      lastSpeechAt: _lastSpeechAt,
      heardSpeech: _heardSpeech,
      initialSilenceTimeout: _autoStopInitialSilenceTimeout,
      maxRecordingDuration: _autoStopMaxRecordingDuration,
    )) {
      return;
    }

    _autoStopInProgress = true;
    _logger.info(
      'Voice endpoint auto-stop: current=${amplitude.current.toStringAsFixed(1)}dB '
      'max=${amplitude.max.toStringAsFixed(1)}dB '
      'heardSpeech=$_heardSpeech',
    );
    unawaited(_autoStopAndRecognize());
  }

  Future<void> _autoStopAndRecognize() async {
    final text =
        _heardSpeech ? await stopAndRecognize() : await _stopBlankRecording();
    _autoStopInProgress = false;
    await onAutoRecognitionComplete?.call(text);
  }

  Future<String?> _stopBlankRecording() async {
    await _stopEndpointDetection();
    try {
      await _recorder.stop();
    } catch (e) {
      _logger.warning('blank stop error: $e');
    }
    await _deleteCurrentFile();
    _state = VoiceInputState.idle;
    _clearEndpointState();
    notifyListeners();
    return null;
  }

  Future<void> _stopEndpointDetection() async {
    _endpointPollTimer?.cancel();
    _endpointPollTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    final sub = _amplitudeSub;
    _amplitudeSub = null;
    if (sub != null) {
      await sub.cancel();
    }
    _autoStopEnabled = false;
    _amplitudePollInProgress = false;
  }

  void _clearEndpointState() {
    _recordingStartedAt = null;
    _lastSpeechAt = null;
    _autoStopInitialSilenceTimeout = _voiceEndpointInitialSilenceTimeout;
    _autoStopMaxRecordingDuration = _voiceEndpointMaxRecordingDuration;
    _heardSpeech = false;
    _autoStopEnabled = false;
    _autoStopInProgress = false;
    _amplitudePollInProgress = false;
  }

  Future<void> _deleteCurrentFile() async {
    final path = _currentPath;
    _currentPath = null;
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (e) {
      _logger.warning('Delete recording failed: $e');
    }
  }

  @override
  void dispose() {
    if (_streamingClient != null) {
      unawaited(_cancelStreamingInternal());
    }
    if (_state == VoiceInputState.recording) {
      _recorder.stop().catchError((_) => null);
    }
    unawaited(_stopEndpointDetection());
    _deleteCurrentFile();
    _recorder.dispose();
    super.dispose();
  }
}

@visibleForTesting
bool voiceInputAmplitudeIsSpeech(
  double db, {
  double thresholdDb = _voiceEndpointSpeechThresholdDb,
}) {
  return db >= thresholdDb;
}

@visibleForTesting
bool voiceInputShouldAutoStop({
  required DateTime now,
  required DateTime startedAt,
  required DateTime? lastSpeechAt,
  required bool heardSpeech,
  Duration initialSilenceTimeout = _voiceEndpointInitialSilenceTimeout,
  Duration trailingSilenceTimeout = _voiceEndpointTrailingSilenceTimeout,
  Duration maxRecordingDuration = _voiceEndpointMaxRecordingDuration,
}) {
  final elapsed = now.difference(startedAt);
  if (elapsed >= maxRecordingDuration) return true;

  if (!heardSpeech) {
    return elapsed >= initialSilenceTimeout;
  }

  final lastSpeech = lastSpeechAt;
  if (lastSpeech == null) return false;
  return now.difference(lastSpeech) >= trailingSilenceTimeout;
}
