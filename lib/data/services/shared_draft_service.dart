import 'dart:async';

import 'package:image_picker/image_picker.dart';

class SharedDraft {
  final String? text;
  final List<XFile> images;

  SharedDraft({this.text, this.images = const []});

  bool get isEmpty =>
      (text == null || text!.trim().isEmpty) && images.isEmpty;
}

class SharedDraftService {
  SharedDraftService._();

  static final SharedDraftService instance = SharedDraftService._();

  final _controller = StreamController<SharedDraft>.broadcast();
  Stream<SharedDraft> get stream => _controller.stream;

  void publish(SharedDraft draft) {
    _controller.add(draft);
  }
}