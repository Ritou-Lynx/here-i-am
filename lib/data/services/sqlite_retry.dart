import 'dart:async';

bool isSqliteDatabaseLocked(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('database is locked') ||
      text.contains('database is busy') ||
      text.contains('sqlite_busy');
}

Future<T> retryOnSqliteLocked<T>(
  Future<T> Function() action, {
  int attempts = 6,
  Duration initialDelay = const Duration(milliseconds: 120),
}) async {
  Object? lastError;
  StackTrace? lastStackTrace;

  for (var i = 0; i < attempts; i++) {
    try {
      return await action();
    } catch (error, stackTrace) {
      if (!isSqliteDatabaseLocked(error) || i == attempts - 1) {
        rethrow;
      }
      lastError = error;
      lastStackTrace = stackTrace;
      await Future<void>.delayed(
        Duration(milliseconds: initialDelay.inMilliseconds * (i + 1)),
      );
    }
  }

  Error.throwWithStackTrace(lastError!, lastStackTrace!);
}
