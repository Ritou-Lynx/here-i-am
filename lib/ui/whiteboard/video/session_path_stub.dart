/// Session path resolver — stub for platforms without `dart:io` (Web).
library;

/// Returns `null` on platforms without a local filesystem.
String? resolveSessionPath() => null;