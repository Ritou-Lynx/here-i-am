import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/speech_transcription_service.dart';
import 'package:memex/data/services/streaming_transcriber.dart';
import 'package:memex/data/services/whisper_service.dart';

abstract interface class QuickCaptureSpeech {
  Future<String?> start(void Function(String) onText);
  Future<String?> finish();
  Future<void> cancel();
}

/// Keeps audio in memory and uses the configured on-device model only.
/// No model download, cloud upload, or settings change is initiated here.
class LocalQuickCaptureSpeech implements QuickCaptureSpeech {
  LocalQuickCaptureSpeech({
    SpeechTranscriptionService? transcription,
    AudioRecorder? recorder,
    this.localModelReady,
  })  : transcription = transcription ?? SpeechTranscriptionService.instance,
        _recorder = recorder;
  final SpeechTranscriptionService transcription;
  AudioRecorder? _recorder;
  AudioRecorder get recorder => _recorder ??= AudioRecorder();
  final Future<bool> Function()? localModelReady;
  Future<void>? _cancelInFlight;
  StreamingTranscriber? _streaming;
  StreamSubscription<Uint8List>? _subscription;
  final _pcm = BytesBuilder(copy: false);
  bool _recording = false;
  int _generation = 0;

  @override
  Future<String?> start(void Function(String) onText) async {
    try {
      return await _start(onText);
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  Future<String?> _start(void Function(String) onText) async {
    if (_cancelInFlight != null) return '录音已结束，可以继续用键盘输入。';
    final generation = ++_generation;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final unlocked =
          await const MethodChannel('com.memexlab.memex/quick_capture')
              .invokeMethod<bool>('awaitCaptureUnlock');
      if (unlocked != true || generation != _generation) {
        return '解锁后可开始录音，也可以用键盘输入。';
      }
    }
    if (!await (localModelReady?.call() ??
        transcription.supportsStreamingTranscription())) {
      return '本机语音模型尚未就绪，可以先用键盘输入；下载模型后可离线识别。';
    }
    if (generation != _generation) return null;
    if (!await recorder.hasPermission()) return '没有麦克风权限，可以用键盘输入。';
    final streaming = StreamingTranscriber(
      onTextChanged: (text) {
        if (generation == _generation) onText(text);
      },
    );
    _streaming = streaming;
    await streaming.init();
    if (generation != _generation) {
      streaming.dispose();
      return null;
    }
    _pcm.clear();
    final stream = await recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (generation != _generation) {
      await recorder.stop();
      return null;
    }
    _recording = true;
    _subscription = stream.listen((chunk) {
      // Bound the in-memory recording to five minutes.
      if (_pcm.length + chunk.length > 16000 * 2 * 300) return;
      _pcm.add(chunk);
      streaming.addAudioChunk(chunk);
    });
    return null;
  }

  @override
  Future<String?> finish() async {
    ++_generation;
    final wasRecording = _recording;
    _recording = false;
    if (wasRecording) await recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    _streaming?.dispose();
    _streaming = null;
    final bytes = _pcm.takeBytes();
    if (bytes.length < 2) return null;
    final data = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    // Recheck immediately before final calibration to avoid a changed cloud
    // preference causing an unexpected upload.
    if (!await transcription.supportsStreamingTranscription()) return null;
    return WhisperService.instance.transcribeSamples(samples);
  }

  @override
  Future<void> cancel() async {
    await (_cancelInFlight ??= _cancel());
  }

  Future<void> _cancel() async {
    ++_generation;
    final wasRecording = _recording;
    _recording = false;
    if (wasRecording) await recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    _streaming?.dispose();
    _streaming = null;
    _pcm.clear();
    await _recorder?.dispose();
  }
}
