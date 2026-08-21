library;

import 'dart:convert';

import 'runtime_projection.dart';
import 'runtime_session_binding.dart';

abstract final class RuntimeSessionBindingCodec {
  static String encode(RuntimeSessionBinding binding) {
    return _encodeBounded(binding.toJson(), 'RuntimeSessionBinding');
  }

  static RuntimeSessionBinding decode(String encoded) {
    return RuntimeSessionBinding.fromJson(
      _decodeBounded(encoded, 'RuntimeSessionBinding'),
    );
  }
}

abstract final class RuntimeTurnProjectionCodec {
  static String encode(RuntimeTurnProjection projection) {
    return _encodeBounded(projection.toJson(), 'RuntimeTurnProjection');
  }

  static RuntimeTurnProjection decode(String encoded) {
    return RuntimeTurnProjection.fromJson(
      _decodeBounded(encoded, 'RuntimeTurnProjection'),
    );
  }
}

String _encodeBounded(Map<String, dynamic> json, String type) {
  final encoded = jsonEncode(json);
  if (utf8.encode(encoded).length > runtimeContractMaxEncodedBytes) {
    throw FormatException('$type exceeds its hard byte limit');
  }
  return encoded;
}

Map<String, dynamic> _decodeBounded(String encoded, String type) {
  if (utf8.encode(encoded).length > runtimeContractMaxEncodedBytes) {
    throw FormatException('$type exceeds its hard byte limit');
  }
  final decoded = jsonDecode(encoded);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$type must be a JSON object');
  }
  return decoded;
}
