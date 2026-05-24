import 'dart:io';

/// Provider-agnostic ASR interface. New providers (Xunfei, Whisper, etc.)
/// implement this — the rest of the app holds only this abstraction.
abstract class AsrClient {
  /// Recognize the spoken content of an audio file and return text.
  ///
  /// [audioFile] must be a 16kHz mono WAV PCM file for current providers.
  /// Throws [AsrException] on any failure (network, auth, bad audio).
  Future<String> recognize(File audioFile);
}

class AsrException implements Exception {
  final String message;
  final Object? cause;
  AsrException(this.message, [this.cause]);

  @override
  String toString() =>
      cause == null ? 'AsrException: $message' : 'AsrException: $message ($cause)';
}
