import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import 'package:memex/data/services/asr/alibaba_asr_client.dart';
import 'package:memex/data/services/asr/alibaba_streaming_asr_client.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/barge_in_detector.dart';
import 'package:memex/utils/logger.dart';

enum VoiceInputState { idle, recording, processing }

const _voiceEndpointPollInterval = Duration(milliseconds: 200);
const _voiceEndpointInitialSilenceTimeout = Duration(seconds: 4);
const _voiceEndpointTrailingSilenceTimeout = Duration(milliseconds: 1350);
const _voiceEndpointMaxRecordingDuration = Duration(seconds: 60);
const _voiceEndpointSpeechThresholdDb = -45.0;

/// Adaptive endpoint thresholds (Cove GPT-Live section 7).
/// Short utterances (< 1800ms) use a shorter trailing silence (900ms);
/// longer utterances use 1350ms. The hard per-sentence limit is 60s,
/// counted from the first real speech, not from "entering listening".
const _adaptiveShortThreshold = Duration(milliseconds: 1800);
const _adaptiveShortSilence = Duration(milliseconds: 900);
const _adaptiveLongSilence = Duration(milliseconds: 1350);

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

  /// Ensures the RECORD_AUDIO permission is granted before recording starts.
  ///
  /// When the app is visible (foreground), a missing permission triggers the
  /// system authorization dialog (so the user can pick the appropriate grant
  /// mode); a user refusal is a hard stop.
  ///
  /// From the background no dialog can be shown: the request throws (no
  /// Activity) and the check itself is unreliable — Samsung's One UI (and
  /// Android 11+ in general) reports `while-in-use` grants as denied while
  /// the app is backgrounded, even when a foreground service is running and
  /// the system would actually allow recording. In that case we optimistically
  /// proceed and let the OS arbitrate at AudioRecord time; a real denial
  /// surfaces as a recorder start error handled by the caller.
  Future<bool> _ensureMicPermission() async {
    if (await _recorder.hasPermission()) return true;
    try {
      final status = await Permission.microphone
          .request()
          .timeout(const Duration(seconds: 10),
              onTimeout: () => PermissionStatus.denied);
      if (status.isGranted) return true;
      // Foreground: the user refused the system dialog — hard stop.
      return false;
    } catch (e) {
      _logger.warning(
          'mic permission request unavailable ($e); proceeding ',
          'optimistically — the system arbitrates at AudioRecord time');
      return true;
    }
  }

  /// Maps a recorder-start error to a user-facing message. Permission denial
  /// errors (the OS refused AudioRecord — e.g. the grant is `while-in-use`
  /// and the app is backgrounded without a foreground service) are translated
  /// to an actionable hint; everything else keeps the raw detail.
  static String _friendlyMicError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('permission') ||
        msg.contains('securityexception') ||
        msg.contains('麦克风')) {
      return '麦克风权限未授予：请到系统设置 → 应用 → 故我在 V3 → 权限 → 麦克风，确认已允许后重试';
    }
    return '启动录音失败: $e';
  }

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

  /// Two-stage barge-in detector (duck → interrupt → restore) with PCM
  /// preroll ring buffer. Active while TTS plays (audio forwarding paused).
  BargeInDetector? _bargeInDetector;

  // Press-to-talk streaming state ----------------------------------------
  bool _pressToTalkActive = false;
  final StringBuffer _pressToTalkBuffer = StringBuffer();
  Timer? _pressToTalkWatchdog;

  static const Duration _pressToTalkMaxDuration = Duration(minutes: 5);

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

  /// Called when client-side barge-in detection fires during TTS playback.
  ///
  /// Two-stage: [onBargeInDuck] fires first (~240ms continuous voice) to
  /// lower TTS volume. [onBargeInDetected] fires when interrupt is confirmed
  /// (~520ms continuous voice). [onBargeInRestore] fires if the duck was a
  /// false alarm (~160ms silence after duck).
  void Function()? onBargeInDuck;
  void Function()? onBargeInDetected;
  void Function()? onBargeInRestore;

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

  /// Whether a press-to-talk streaming session is active.
  bool get isPressToTalk => _pressToTalkActive;

  /// Intermediate text accumulated so far during press-to-talk (for UI display).
  String get pressToTalkPartialText => _pressToTalkBuffer.toString().trim();

  /// Called during press-to-talk when a new sentence is finalized, with the
  /// full accumulated text so far. Use for live transcription display.
  void Function(String accumulatedText)? onPressToTalkUpdate;

  /// Called when press-to-talk auto-stops (watchdog timeout). The screen
  /// should treat this like a manual stop: send the text as a message.
  Future<void> Function(String? text)? onPressToTalkAutoComplete;

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

  // ── Press-to-talk streaming ─────────────────────────────────────────────

  /// Start a press-to-talk streaming session. Uses streaming ASR (same NLS
  /// engine as voice-call mode) but with normal mic routing (no VoIP/AEC)
  /// and sentence accumulation instead of per-sentence dispatch.
  ///
  /// Call [stopPressToTalk] to end and get the combined text.
  Future<void> startPressToTalk() async {
    if (_pressToTalkActive || _streamingClient != null) return;
    _pressToTalkActive = true;
    _pressToTalkBuffer.clear();

    await startStreaming(useVoiceCommunication: false);

    // If startStreaming failed (lastError set, state still idle), bail.
    if (_streamingClient == null) {
      _pressToTalkActive = false;
      return;
    }

    // Safety watchdog: auto-stop after max duration.
    _pressToTalkWatchdog?.cancel();
    _pressToTalkWatchdog = Timer(_pressToTalkMaxDuration, () {
      _logger.info('Press-to-talk watchdog: max duration reached, auto-stopping');
      unawaited(() async {
        final text = await stopPressToTalk();
        await onPressToTalkAutoComplete?.call(text);
      }());
    });
  }

  /// Stop press-to-talk and return the accumulated recognized text.
  /// Returns null if nothing was recognized.
  Future<String?> stopPressToTalk() async {
    if (!_pressToTalkActive) return null;
    _pressToTalkWatchdog?.cancel();
    _pressToTalkWatchdog = null;

    await stopStreaming();

    _pressToTalkActive = false;
    final text = _pressToTalkBuffer.toString().trim();
    _pressToTalkBuffer.clear();
    return text.isEmpty ? null : text;
  }

  /// Cancel press-to-talk without returning text.
  Future<void> cancelPressToTalk() async {
    if (!_pressToTalkActive) return;
    _pressToTalkWatchdog?.cancel();
    _pressToTalkWatchdog = null;
    _pressToTalkActive = false;
    _pressToTalkBuffer.clear();
    await cancelStreaming();
  }

  /// Internal: accumulate a finalized sentence during press-to-talk.
  void _accumulatePressToTalkSentence(String text) {
    if (!_pressToTalkActive) return;
    if (_pressToTalkBuffer.isNotEmpty) {
      _pressToTalkBuffer.write(' ');
    }
    _pressToTalkBuffer.write(text);
    onPressToTalkUpdate?.call(pressToTalkPartialText);
  }

  // ── Streaming mode ───────────────────────────────────────────────────────

  /// Start a streaming ASR session. The mic stays open until [stopStreaming]
  /// or [cancelStreaming] is called. Server-side VAD drives sentence events
  /// via [onStreamingEvent].
  ///
  /// Uses `record.startStream` with `AudioEncoder.pcm16bits` + echo cancel +
  /// noise suppress. PCM chunks are forwarded directly to the NLS gateway
  /// without touching local storage.
  ///
  /// [useVoiceCommunication]: when true (default), routes the mic through
  /// `VOICE_COMMUNICATION` audio source for platform AEC (voice-call mode).
  /// When false, uses the default mic source (press-to-talk / normal recording).
  Future<void> startStreaming({bool useVoiceCommunication = true}) async {
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

    if (!await _ensureMicPermission()) {
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
          // Accumulate for press-to-talk mode.
          final sentenceText = event.text.trim();
          if (sentenceText.isNotEmpty) {
            _accumulatePressToTalkSentence(sentenceText);
          }
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
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          // VoIP call path: route mic through the voice-call audio source so
          // the platform AEC cancels speaker echo (TTS output) from the mic
          // signal, and set MODE_IN_COMMUNICATION so mic + speaker coexist.
          // For press-to-talk (useVoiceCommunication=false), use default mic
          // source — no AEC needed since TTS is not playing simultaneously.
          androidConfig: useVoiceCommunication
              ? const AndroidRecordConfig(
                  audioSource: AndroidAudioSource.voiceCommunication,
                  audioManagerMode: AudioManagerMode.modeInCommunication,
                )
              : const AndroidRecordConfig(
                  audioSource: AndroidAudioSource.mic,
                  audioManagerMode: AudioManagerMode.modeNormal,
                ),
        ),
      );
      _streamingAudioSub = audioStream.listen(
        (chunk) {
          if (!_audioForwardingPaused) {
            _streamingClient?.sendAudio(chunk);
          } else {
            // TTS is playing — feed PCM to the barge-in detector instead
            // of dropping it. The detector runs duck/interrupt/restore.
            _feedBargeInDetector(chunk);
          }
        },
        onError: (Object e) {
          _logger.warning('Audio stream error: $e');
        },
      );
    } catch (e) {
      _logger.severe('Failed to start PCM stream: $e');
      lastError = _friendlyMicError(e);
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
  /// chunks are fed to the [BargeInDetector] for two-stage duck/interrupt.
  ///
  /// This is a defense-in-depth guard. With the TTS player routed through the
  /// voice-communication stream (see `_voiceCallTtsContext`), the platform AEC
  /// should cancel speaker echo and the NLS server-side VAD will not fire on
  /// TTS output. The detector catches any residual echo that slips past AEC
  /// on misbehaving devices.
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

  /// Start two-stage barge-in detection. Audio chunks arriving while
  /// forwarding is paused are fed to [BargeInDetector].
  void startBargeInDetection() {
    if (_bargeInDetector != null) return;
    _bargeInDetector = BargeInDetector();
    _bargeInDetector!.onEvent = (event, prerollSnapshot) {
      switch (event) {
        case BargeInEvent.duck:
          _logger.info('Barge-in: duck stage');
          onBargeInDuck?.call();
        case BargeInEvent.interrupt:
          _logger.info('Barge-in: interrupt confirmed');
          stopBargeInDetection();
          onBargeInDetected?.call();
        case BargeInEvent.restore:
          _logger.info('Barge-in: false alarm, restore');
          onBargeInRestore?.call();
      }
    };
    _bargeInDetector!.start(16000);
    _logger.info('Barge-in detector started (duck=${BargeInDetector().duckMs}ms, '
        'interrupt=${BargeInDetector().interruptMs}ms)');
  }

  void stopBargeInDetection() {
    _bargeInDetector?.stop();
    _bargeInDetector = null;
  }

  /// Convert a PCM16 mono chunk (Uint8List of 16-bit samples) to Float32List
  /// and feed it to the barge-in detector.
  void _feedBargeInDetector(Uint8List chunk) {
    final detector = _bargeInDetector;
    if (detector == null) return;
    // PCM16 mono → Float32 (normalized -1.0 to 1.0).
    final sampleCount = chunk.length ~/ 2;
    if (sampleCount == 0) return;
    final floats = Float32List(sampleCount);
    final byteData = ByteData.sublistView(chunk);
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      floats[i] = sample / 32768.0;
    }
    detector.push(floats, 16000);
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

    if (!await _ensureMicPermission()) {
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
      lastError = _friendlyMicError(e);
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
    _pressToTalkWatchdog?.cancel();
    _pressToTalkWatchdog = null;
    _pressToTalkActive = false;
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

  // Adaptive trailing silence (Cove section 7):
  // Short utterances (< 1800ms of speech) → 900ms silence to end.
  // Longer utterances (>= 1800ms) → 1350ms silence.
  final speechDuration = lastSpeech.difference(startedAt);
  final adaptiveSilence = speechDuration < _adaptiveShortThreshold
      ? _adaptiveShortSilence
      : _adaptiveLongSilence;
  // Use the shorter of the caller-provided timeout and the adaptive one
  // so callers that explicitly pass a timeout still get their value honored.
  final effectiveSilence = trailingSilenceTimeout < adaptiveSilence
      ? trailingSilenceTimeout
      : adaptiveSilence;
  return now.difference(lastSpeech) >= effectiveSilence;
}
