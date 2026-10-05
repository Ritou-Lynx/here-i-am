import 'package:flutter/foundation.dart';

enum QuickCaptureState { editing, sending, saved, failed }

@immutable
class QuickCaptureResult {
  const QuickCaptureResult({required this.captureId, required this.text,
    this.organizerMessage, this.plannerMessage, this.pendingIssues = const []});
  final String captureId;
  final String text;
  final String? organizerMessage;
  final String? plannerMessage;
  final List<String> pendingIssues;
}

@immutable
class QuickCaptureDraft {
  const QuickCaptureDraft(this.text, {this.captureId});
  final String text;
  final String? captureId;
  QuickCaptureDraft copyWith({String? text}) =>
      QuickCaptureDraft(text ?? this.text, captureId: captureId);
}
