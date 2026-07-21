import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'package:memex/data/services/asr/alibaba_asr_client.dart';
import 'package:memex/data/services/asr/asr_client.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/utils/logger.dart';

enum VoiceInputState { idle, recording, processing }

const _voiceEndpointPollInterval = Duration(milliseconds: 200);
const _voiceEndpointInitialSilenceTimeout = Duration(seconds: 4);
const _voiceEndpointTrailingSilenceTimeout = Duration(milliseconds: 1500);
const _voiceEndpointMaxRecordingDuration = Duration(seconds: 60);
const _voiceEndpointSpeechThresholdDb = -45.0;

/// Drives the press-to-talk recording → ASR pipeline.
///
/// State machine:
///   idle ──toggle()──▶ recording ──toggle()──▶ processing ──(ASR)──▶ idle
///                            │
///                            └────cancel()────▶ idle (recording discarded)
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

  /// Called when automatic endpoint detection stops a recording.
  ///
  /// [text] is null when the recording was empty, too short, or ASR returned
  /// no usable text. The owner can decide whether to keep listening.
  Future<void> Function(String? text)? onAutoRecognitionComplete;

  /// Last error message (for UI to surface). Cleared on next toggle.
  String? lastError;

  VoiceInputState get state => _state;
  bool get isRecording => _state == VoiceInputState.recording;
  bool get isProcessing => _state == VoiceInputState.processing;

  /// Toggle recording. From idle → start; from recording → stop & recognize.
  /// While processing, calls are ignored.
  ///
  /// Returns the recognized text on the recording → idle transition, null
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

  Future<void> _start({
    required bool autoStop,
    Duration? initialSilenceTimeout,
    Duration? maxRecordingDuration,
  }) async {
    lastError = null;

    final config = await AsrConfig.load();
    if (config == null) {
      lastError = 'ASR 凭证未配置，请到设置 → 语音输入填入阿里 NLS 凭证';
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
      _logger.info('Recording started → $path');
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
      // <1KB = essentially silence / aborted recording
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
