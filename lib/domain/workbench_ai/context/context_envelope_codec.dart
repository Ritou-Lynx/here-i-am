library;

import 'dart:convert';

import 'context_envelope.dart';

abstract final class ContextEnvelopeCodec {
  static String encode(ContextEnvelope envelope) {
    final encoded = jsonEncode(envelope.toJson());
    final byteLength = utf8.encode(encoded).length;
    if (byteLength > envelope.budget.maxEnvelopeBytes) {
      throw FormatException(
        'ContextEnvelope is $byteLength bytes, above its declared limit '
        '${envelope.budget.maxEnvelopeBytes}',
      );
    }
    return encoded;
  }

  static ContextEnvelope decode(String encoded) {
    final byteLength = utf8.encode(encoded).length;
    if (byteLength > ContextEnvelopeLimits.maxEnvelopeBytes) {
      throw const FormatException(
        'ContextEnvelope exceeds its hard byte limit',
      );
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ContextEnvelope must be a JSON object');
    }
    final envelope = ContextEnvelope.fromJson(decoded);
    encode(envelope);
    return envelope;
  }
}
