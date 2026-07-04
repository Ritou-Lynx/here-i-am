import 'dart:async';

/// Delivers foreground requests to open a persona chat.
///
/// Notification taps can arrive before the app shell is mounted, so the latest
/// request is kept until the companion-first home screen is ready to consume it.
class PersonaChatOpenService {
  PersonaChatOpenService._();
  static final PersonaChatOpenService instance = PersonaChatOpenService._();

  final _requests = StreamController<PersonaChatOpenRequest>.broadcast();
  PersonaChatOpenRequest? _pendingRequest;

  Stream<PersonaChatOpenRequest> get requests => _requests.stream;

  void requestOpen(String characterId, {bool startVoiceMode = false}) {
    if (characterId.isEmpty) return;
    final request = PersonaChatOpenRequest(
      characterId: characterId,
      startVoiceMode: startVoiceMode,
    );
    _pendingRequest = request;
    _requests.add(request);
  }

  PersonaChatOpenRequest? consumePending() {
    final request = _pendingRequest;
    _pendingRequest = null;
    return request;
  }

  void markHandled(PersonaChatOpenRequest request) {
    if (identical(_pendingRequest, request)) {
      _pendingRequest = null;
    }
  }
}

class PersonaChatOpenRequest {
  const PersonaChatOpenRequest({
    required this.characterId,
    this.startVoiceMode = false,
  });

  final String characterId;
  final bool startVoiceMode;
}
