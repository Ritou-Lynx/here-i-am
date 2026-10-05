import 'package:flutter/foundation.dart';
import '../../data/personal_data_hub/quick_capture_models.dart';
import '../../data/personal_data_hub/quick_capture_service.dart';

class QuickCaptureController extends ChangeNotifier {
  QuickCaptureController(this.service) : draft = service.newDraft();
  final QuickCaptureService service;
  QuickCaptureDraft draft;
  QuickCaptureState state = QuickCaptureState.editing;
  QuickCaptureResult? result;
  String? error;
  void setText(String value) { draft = draft.copyWith(text: value); notifyListeners(); }
  Future<void> send() async {
    state = QuickCaptureState.sending; error = null; notifyListeners();
    try { result = await service.send(draft); state = QuickCaptureState.saved; }
    catch (e) { error = e.toString(); state = QuickCaptureState.failed; }
    notifyListeners();
  }
}
