/// File-backed session store for platforms with a local filesystem.
library;

import 'dart:convert';
import 'dart:io';

import 'package:memex/domain/whiteboard/video/video_domain.dart';

import 'session_store.dart';

/// Persists the video annotation session as JSON in the system temp dir.
class FileVideoSessionStore implements VideoSessionStore {
  final File file;

  FileVideoSessionStore({File? file}) : file = file ?? _defaultFile();

  static File _defaultFile() {
    final tmp = Directory.systemTemp;
    return File(
        '${tmp.path}${Platform.pathSeparator}whiteboard_w4_video_session.json');
  }

  @override
  Future<void> save(VideoAnnotationSession session) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(session.toJson()));
  }

  @override
  Future<VideoAnnotationSession?> load() async {
    try {
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      return VideoAnnotationSession.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup.
    }
  }
}

/// Creates the file-backed store (native platforms).
VideoSessionStore createVideoSessionStoreImpl() => FileVideoSessionStore();
