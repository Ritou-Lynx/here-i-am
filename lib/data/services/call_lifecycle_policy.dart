/// Pure lifecycle rules shared by the call router, foreground session and UI.
///
/// Keeping these decisions free of Flutter/plugin state makes the retry and
/// out-of-order behavior directly testable.
class CallGenerationTracker {
  int _watermark = -1;
  int _terminatedWatermark = -1;
  int? _activeGeneration;

  int? get activeGeneration => _activeGeneration;
  int get watermark => _watermark;
  int get terminatedWatermark => _terminatedWatermark;

  /// Returns true exactly once for a live generation.
  ///
  /// A newer start observed while another call is still active advances the
  /// watermark but waits for a retry after the active call ends. This matches
  /// the router's three-delivery window without allowing an old generation to
  /// replace a newer one.
  bool shouldStart(int? generation) {
    final candidate = generation ?? _watermark + 1;
    if (candidate <= _terminatedWatermark) return false;

    if (_activeGeneration != null) {
      _observe(candidate);
      return false;
    }
    if (candidate < _watermark) return false;

    _observe(candidate);
    _activeGeneration = candidate;
    return true;
  }

  /// Records the termination even when its start has not arrived yet.
  ///
  /// A generation-less end comes from the legacy native broadcast bridge and
  /// deliberately remains a force-end operation.
  bool shouldEnd(int? generation) {
    if (generation == null) {
      terminateActive();
      return true;
    }

    _observe(generation);
    if (generation > _terminatedWatermark) {
      _terminatedWatermark = generation;
    }
    if (_activeGeneration != generation) return false;

    _activeGeneration = null;
    return true;
  }

  /// Marks a locally failed active start as terminal so a delivery retry does
  /// not reopen it after failure cleanup.
  void terminateActive() {
    final active = _activeGeneration;
    if (active != null && active > _terminatedWatermark) {
      _terminatedWatermark = active;
    }
    _activeGeneration = null;
  }

  void _observe(int generation) {
    if (generation > _watermark) _watermark = generation;
  }
}

/// Serializes short call startup and teardown work without covering speech.
///
/// Generation termination happens before an end operation is enqueued, so a
/// queued start can observe cancellation immediately when its turn arrives.
class CallLifecycleQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

/// Selects an explicit agent-composed opening for the answered character.
/// User-initiated calls have no pending record and therefore return null.
String? resolvePendingCallOpening({
  required String characterId,
  required ({String characterId, String opening})? pending,
}) {
  if (pending == null || pending.characterId != characterId) return null;
  final opening = pending.opening.trim();
  return opening.isEmpty ? null : opening;
}

/// Whether the call overlay should hand an avatar value to [LocalImage].
/// Bare seeds/names such as the legacy value `i` intentionally fall back to
/// the initial-letter avatar instead of being treated as filesystem paths.
bool isLoadableCallAvatar(String? avatar) {
  final value = avatar?.trim() ?? '';
  if (value.isEmpty) return false;

  final uri = Uri.tryParse(value);
  if (uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty) {
    return true;
  }

  // A Windows drive prefix is a local path, not a URI scheme.
  if (RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value)) return true;
  // Malformed/unsupported URI-like values must not fall through merely
  // because their text contains a slash.
  if (uri != null && uri.scheme.isNotEmpty) return false;

  if (value.contains('/') || value.contains(r'\')) return true;
  final lower = value.toLowerCase();
  return const [
    '.png',
    '.jpg',
    '.jpeg',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
  ].any(lower.endsWith);
}
