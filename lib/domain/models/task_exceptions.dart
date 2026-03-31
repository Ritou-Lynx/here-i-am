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

/// Exception thrown when an LLM API call fails with a non-retryable HTTP error
/// (e.g. 401, 403, 400). Task executor will skip retries and invoke the failure handler.
class NonRetryableLlmException implements NonRetryableTaskException {
  @override
  final String message;

  final int? statusCode;
  final Object? originalError;

  NonRetryableLlmException(
    this.message, {
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() =>
      "NonRetryableLlmException: $message${statusCode != null ? ' (HTTP $statusCode)' : ''}";
}
