/// Session path resolver for native platforms (has `dart:io`).
library;

import 'dart:io';

/// Returns the temp-directory path for the W4 video session JSON file.
String? resolveSessionPath() {
  try {
    final temp = Directory.systemTemp.path;
    return '$temp${Platform.pathSeparator}whiteboard_w4_video_session.json';
  } catch (_) {
    return null;
  }
}