import 'package:uuid/uuid.dart';
import 'quick_capture_models.dart';

typedef QuickCaptureSubmit = Future<QuickCaptureResult> Function(
    QuickCaptureDraft draft);

/// UI-facing seam for W4. The host supplies the W7 outbox/domain adapter.
/// This class deliberately has no database, router, model, or chat dependency.
class QuickCaptureService {
  QuickCaptureService({required this.submit, Uuid? uuid}) : _uuid = uuid ?? const Uuid();
  final QuickCaptureSubmit submit;
  final Uuid _uuid;

  QuickCaptureDraft newDraft([String text = '']) =>
      QuickCaptureDraft(text, captureId: _uuid.v4());

  Future<QuickCaptureResult> send(QuickCaptureDraft draft) {
    if (draft.text.trim().isEmpty) {
      return Future.error(const FormatException('empty_capture'));
    }
    return submit(draft.captureId == null
        ? draft.copyWith(text: draft.text)
        : draft);
  }
}
