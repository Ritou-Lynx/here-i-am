import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';
import '../../../data/personal_data_hub/quick_capture_models.dart';
import '../../../data/personal_data_hub/quick_capture_service.dart';
import '../../../data/personal_data_hub/quick_capture_speech.dart';

class QuickCaptureViewModel extends ChangeNotifier {
  QuickCaptureViewModel(
    this.service, {
    this.speech,
    QuickCaptureDraft? restored,
  }) : draft = restored ?? service.newDraft() {
    send = Command0<QuickCaptureResult>(
      () => runResult(() async {
        if (recording || voice.running) await finishVoice.execute();
        return service.send(draft);
      }),
    );
    voice = Command0<String?>(
      () => runResult(() async {
        final result = await speech?.start((text) {
          if (!_disposed && !cancelled) setText(text);
        });
        if (cancelled || _disposed) {
          await speech?.cancel();
          return null;
        }
        recording = speech != null && result == null;
        notice = result ?? (speech == null ? '可用键盘输入。' : null);
        return result;
      }),
    );
    finishVoice = Command0<void>(
      () => runResultVoid(() async {
        final text = await speech?.finish();
        recording = false;
        if (!_disposed && !cancelled && text != null && text.isNotEmpty) {
          setText(text);
        }
      }),
    );
    for (final command in [send, voice, finishVoice]) {
      command.addListener(_changed);
    }
  }
  final QuickCaptureService service;
  final QuickCaptureSpeech? speech;
  QuickCaptureDraft draft;
  late final Command0<QuickCaptureResult> send;
  late final Command0<String?> voice;
  late final Command0<void> finishVoice;
  bool recording = false, cancelled = false, _disposed = false;
  String? notice;
  QuickCaptureResult? get result => switch (send.result) {
        Ok(:final value) => value,
        _ => null,
      };
  String? get error => send.error
      ? '保存失败，内容仍在，请重试。'
      : voice.error || finishVoice.error
          ? '语音暂不可用，可以继续编辑或用键盘输入。'
          : null;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void setText(String text) {
    draft = draft.copyWith(text: text);
    _changed();
  }

  Future<void> keyboard() async {
    await finishVoice.execute();
    _changed();
  }

  Future<void> cancel() async {
    cancelled = true;
    await speech?.cancel();
    recording = false;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    for (final command in [send, voice, finishVoice]) {
      command.removeListener(_changed);
      // In-flight Command completes after route disposal; retain it until then.
      if (!command.running) command.dispose();
    }
    super.dispose();
  }
}
