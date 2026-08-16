/// Session persistence for the W4 video study workflow.
///
/// Abstracts where a [VideoAnnotationSession] is persisted so restart
/// recovery works on every platform:
/// - Native (Windows / Android / ...): JSON file in the system temp dir.
/// - Web: `localStorage` (survives page reloads = restart recovery).
///
/// The factory uses conditional imports so `dart:io` never leaks onto web
/// and `dart:js_interop` never leaks into native builds.
library;

import 'package:memex/domain/whiteboard/video/video_domain.dart';

import 'session_store_io.dart'
    if (dart.library.js_interop) 'session_store_web.dart';

/// Persistence contract for a video annotation session.
abstract class VideoSessionStore {
  /// Persists [session], replacing any previous session.
  Future<void> save(VideoAnnotationSession session);

  /// Loads the persisted session, or null when none exists / is corrupted.
  Future<VideoAnnotationSession?> load();

  /// Removes the persisted session.
  Future<void> clear();
}

/// Creates the platform-appropriate session store.
VideoSessionStore createVideoSessionStore() => createVideoSessionStoreImpl();
