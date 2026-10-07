import 'dart:convert';
import 'package:crypto/crypto.dart';

typedef Json = Map<String, dynamic>;

class DomainPolicy {
  static const version = 'domain-policy-v1';
  static const ttl = Duration(days: 60);
  static const reminderAge = Duration(days: 7);
  static const maxItems = 5000;
  static const maxBytes = 50000000;
  static const maxOpBytes = 262144;
  static const maxPageBytes = 2097152;
}

enum DomainRoute { phone, shadow, core }

class DomainFailure implements Exception {
  const DomainFailure(this.code, {this.retryable = false, this.retryAfter});
  final String code;
  final bool retryable;
  final Duration? retryAfter;
  @override
  String toString() => 'DomainFailure($code)';
}

/// Values come from an explicitly authorized connection; no token is persisted.
class DomainBinding {
  const DomainBinding({
    required this.coreInstanceId,
    required this.principalId,
    required this.generation,
    required this.installationId,
    this.policyVersion = DomainPolicy.version,
    this.schemaVersion = 1,
  });
  final String coreInstanceId, principalId, installationId, policyVersion;
  final int generation, schemaVersion;
  Json forDomain(String domain) => {
        'core_instance_id': coreInstanceId,
        'principal_id': principalId,
        'credential_generation': generation,
        'installation_id': installationId,
        'view_policy_version': policyVersion,
        'domain': domain,
        'namespace': 'production',
        'schema_version': schemaVersion,
      };
}

// Core canonicalJSON sorts object keys, then uses ECMAScript JSON.stringify.
// Dart's encoder differs at the fixed/exponential number boundaries. Keep the
// shortest round-trippable IEEE-754 digits, but apply ECMAScript's formatting.
String _ecmaNumber(num value) {
  final number = value.toDouble();
  if (!number.isFinite) throw const DomainFailure('invalid_json_number');
  if (number == 0) return '0'; // Includes negative zero.
  final parts = number.abs().toString().toLowerCase().split('e');
  final mantissa = parts.first;
  final dot = mantissa.indexOf('.');
  var position = (dot < 0 ? mantissa.length : dot) +
      (parts.length == 2 ? int.parse(parts.last) : 0);
  var digits = mantissa.replaceAll('.', '');
  while (digits.startsWith('0')) {
    digits = digits.substring(1);
    position--;
  }
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }
  final String encoded;
  if (position > 0 && position <= 21) {
    encoded = position >= digits.length
        ? digits + '0' * (position - digits.length)
        : '${digits.substring(0, position)}.${digits.substring(position)}';
  } else if (position > -6 && position <= 0) {
    encoded = '0.${'0' * -position}$digits';
  } else {
    final exponent = position - 1;
    final fraction = digits.length == 1 ? '' : '.${digits.substring(1)}';
    encoded = '${digits[0]}${fraction}e${exponent >= 0 ? '+' : ''}$exponent';
  }
  return number < 0 ? '-$encoded' : encoded;
}

// JSON.stringify enumerates array-index object keys numerically before other
// string keys, even after Object.fromEntries receives lexicographically sorted
// entries. The upper excluded value is 2^32-1 (not a JavaScript array index).
int? _arrayIndex(String key) {
  final value = int.tryParse(key);
  return value != null &&
          value >= 0 &&
          value < 4294967295 &&
          value.toString() == key
      ? value
      : null;
}

String canonicalJson(dynamic value) {
  if (value == null || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is num) return _ecmaNumber(value);
  if (value is List) return '[${value.map(canonicalJson).join(',')}]';
  if (value is Map && value.keys.every((key) => key is String)) {
    final keys = value.keys.cast<String>().toList()
      ..sort((a, b) {
        final ai = _arrayIndex(a), bi = _arrayIndex(b);
        if (ai != null && bi != null) return ai.compareTo(bi);
        if (ai != null) return -1;
        if (bi != null) return 1;
        return a.compareTo(b);
      });
    return '{${keys.map((key) => '${jsonEncode(key)}:${canonicalJson(value[key])}').join(',')}}';
  }
  throw const DomainFailure('invalid_json_value');
}

String domainDigest(dynamic value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();
Json copyJson(Json value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)));
Json jsonObject(dynamic value) {
  if (value is! Map) throw const DomainFailure('invalid_response');
  return Map<String, dynamic>.from(value);
}

int jsonBytes(dynamic value) => utf8.encode(jsonEncode(value)).length;

abstract interface class DomainTransport {
  Future<Json> submit(String domain, Json intent);
  Future<Json> operation(String domain, String opId);
  Future<Json> changes(String domain, String? cursor);
  Future<Json> snapshot(String domain,
      {String? snapshotToken, String? pageToken});
  Future<void> acknowledge(String domain, String cursor, {String? snapshotId});
}
