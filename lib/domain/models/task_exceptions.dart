/// Base exception for tasks that should fail immediately instead of retrying.
abstract class NonRetryableTaskException implements Exception {
  String get message;
}

/// Exception thrown when LLM configuration is invalid or missing required fields.
class InvalidModelConfigException implements NonRetryableTaskException {
  @override
  final String message;

  InvalidModelConfigException(
      [this.message = 'The LLM configuration is invalid.']);

  @override
  String toString() => "InvalidModelConfigException: $message";
}
