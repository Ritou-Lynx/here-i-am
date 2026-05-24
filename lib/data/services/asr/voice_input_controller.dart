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
  Future<String?> toggle() async {
    switch (_state) {
      case VoiceInputState.idle:
        await _start();
        return null;
      case VoiceInputState.recording:
        return _stopAndRecognize();
      case VoiceInputState.processing:
        return null;
    }
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
    await _deleteCurrentFile();
    _state = VoiceInputState.idle;
    notifyListeners();
    _logger.info('Recording cancelled');
  }

  Future<void> _start() async {
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
      _logger.info('Recording started → $path');
      notifyListeners();
    } catch (e) {
      lastError = '启动录音失败: $e';
      _logger.severe('start error: $e');
      notifyListeners();
    }
  }

  Future<String?> _stopAndRecognize() async {
    _state = VoiceInputState.processing;
    notifyListeners();

    String? recordedPath;
    try {
      recordedPath = await _recorder.stop();
    } catch (e) {
      _logger.severe('stop error: $e');
      lastError = '停止录音失败: $e';
      _state = VoiceInputState.idle;
      notifyListeners();
      return null;
    }

    final path = recordedPath ?? _currentPath;
    if (path == null) {
      lastError = '录音文件路径为空';
      _state = VoiceInputState.idle;
      notifyListeners();
      return null;
    }

    final file = File(path);
    if (!file.existsSync() || file.lengthSync() < 1024) {
      // <1KB = essentially silence / aborted recording
      _logger.warning('Recording too short (${file.existsSync() ? file.lengthSync() : 0} bytes), skipping ASR');
      lastError = '录音过短';
      await _deleteCurrentFile();
      _state = VoiceInputState.idle;
      notifyListeners();
      return null;
    }

    try {
      final text = await _asrClient!.recognize(file);
      _logger.info('ASR result: "$text"');
      await _deleteCurrentFile();
      _state = VoiceInputState.idle;
      notifyListeners();
      return text.trim().isEmpty ? null : text.trim();
    } catch (e) {
      _logger.severe('ASR error: $e');
      lastError = '识别失败: $e';
      await _deleteCurrentFile();
      _state = VoiceInputState.idle;
      notifyListeners();
      return null;
    }
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
    _deleteCurrentFile();
    _recorder.dispose();
    super.dispose();
  }
}
