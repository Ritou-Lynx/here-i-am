/// localStorage-backed session store for Flutter Web.
///
/// Survives page reloads, which is the web equivalent of restart recovery.
/// Thin wrapper over `dart:js_interop` — deliberately untested in the VM
/// test suite; the interface contract is covered by the file-backed store
/// tests and the serialization is shared [VideoAnnotationSession] JSON.
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:memex/domain/whiteboard/video/video_domain.dart';

import 'session_store.dart';

const _storageKey = 'whiteboard_w4_video_session';

extension type JSStorage._(JSObject _) implements JSObject {
  external JSString? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

JSStorage? _storage() => globalContext['localStorage'] as JSStorage?;

/// Persists the video annotation session in `window.localStorage`.
class LocalStorageVideoSessionStore implements VideoSessionStore {
  @override
  Future<void> save(VideoAnnotationSession session) async {
    final storage = _storage();
    if (storage == null) return;
    storage.setItem(_storageKey, jsonEncode(session.toJson()));
  }

  @override
  Future<VideoAnnotationSession?> load() async {
    final storage = _storage();
    if (storage == null) return null;
    final raw = storage.getItem(_storageKey);
    if (raw == null) return null;
    final value = raw.toDart;
    if (value.isEmpty) return null;
    try {
      return VideoAnnotationSession.fromJson(
          jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final storage = _storage();
    if (storage == null) return;
    storage.removeItem(_storageKey);
  }
}

/// Creates the localStorage-backed store (web platform).
VideoSessionStore createVideoSessionStoreImpl() =>
    LocalStorageVideoSessionStore();
