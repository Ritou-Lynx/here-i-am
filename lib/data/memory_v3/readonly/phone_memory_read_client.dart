import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:memex/utils/result.dart';

/// Process-local desktop client for the explicitly-authorised phone read API.
/// Neither the connection code nor its bearer token is persisted or logged.
class PhoneMemoryReadClient extends ChangeNotifier {
  PhoneMemoryReadClient({
    Dio? dio,
    DateTime Function()? clock,
    Duration requestDeadline = _defaultRequestDeadline,
  })  : _dio = dio ?? _newLocalhostDio(),
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _requestDeadline = requestDeadline;

  static final instance = PhoneMemoryReadClient();
  static const _maxResponseBytes = 32 * 1024;
  static const _maxRequestBytes = 16 * 1024;
  static const _maxQueryChars = 2000;
  static const _maxConnectionCodeChars = 2048;
  static const _maxConnectionPayloadBytes = 1024;
  static const _maxCaptureAge = Duration(minutes: 30);
  static const _defaultRequestDeadline = Duration(seconds: 8);

  final Dio _dio;
  final DateTime Function() _clock;
  final Duration _requestDeadline;
  _PhoneConnection? _connection;
  Map<String, Object?>? _lastReceipt;
  int _generation = 0;

  bool get isConfigured => _connection != null;
  DateTime? get expiresAt => _connection?.expiresAt;
  Map<String, Object?>? get lastReceipt => _lastReceipt == null
      ? null
      : Map<String, Object?>.unmodifiable(_lastReceipt!);

  static Dio _newLocalhostDio() {
    final dio = Dio(BaseOptions(
      baseUrl: 'http://127.0.0.1:47851',
      connectTimeout: const Duration(seconds: 3),
      sendTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 5),
      followRedirects: false,
      maxRedirects: 0,
      responseType: ResponseType.bytes,
      validateStatus: (status) => status != null && status < 400,
    ));
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (_) => 'DIRECT';
        return client;
      },
    );
    return dio;
  }

  Future<Result<void>> connect(String connectionCode) async {
    final candidate = _PhoneConnection.parse(connectionCode, now: _clock());
    if (candidate == null) {
      return const Error(PhoneMemoryReadException('invalid_connection_code'));
    }
    final generation = ++_generation;
    try {
      final status = await _getStatus(candidate);
      if (!_isCurrent(generation, candidate: null)) {
        return const Error(PhoneMemoryReadException('connection_revoked'));
      }
      _connection = candidate;
      _setReceipt(status.receipt('connected'));
      return const Ok.v();
    } on PhoneMemoryReadException catch (error) {
      return Error(error);
    } catch (_) {
      return const Error(PhoneMemoryReadException('phone_unavailable'));
    }
  }

  void disconnect() {
    ++_generation;
    if (_connection == null && _lastReceipt == null) return;
    _connection = null;
    _lastReceipt = null;
    notifyListeners();
  }

  /// A configured source never falls back to desktop-local Dreaming. Failure,
  /// expiry, and server unavailability are represented in [status].
  Future<PhoneMemoryReadContext> readContext({
    required String characterId,
    required String query,
  }) async {
    final connection = _connection;
    final generation = _generation;
    if (connection == null) return const PhoneMemoryReadContext.notConfigured();
    if (characterId != 'i') return const PhoneMemoryReadContext.isolated();
    final now = _clock();
    if (!connection.expiresAt.isAfter(now)) {
      _setReceipt(const {'source': 'phone_v3_live', 'status': 'unavailable'});
      return const PhoneMemoryReadContext.unavailable();
    }
    if (query.trim().isEmpty || query.length > _maxQueryChars) {
      return const PhoneMemoryReadContext.unavailable();
    }
    final request = <String, Object?>{
      'schema_version': 1,
      'character_id': 'i',
      'query': query,
    };
    if (utf8.encode(jsonEncode(request)).length > _maxRequestBytes) {
      return const PhoneMemoryReadContext.unavailable();
    }
    try {
      final response = await _request(
        'POST',
        '/v1/memory/read-context',
        connection,
        data: request,
      );
      final context = PhoneMemoryReadContext._fromWire(
        _decodeMap(response),
        expected: connection,
        now: _clock(),
        isAuthorizedNow: _leaseFor(
          generation: generation,
          expiresAt: connection.expiresAt,
        ),
      );
      if (!_isCurrent(generation, candidate: connection)) {
        return const PhoneMemoryReadContext.unavailable();
      }
      _setReceipt(context.receipt);
      return context;
    } catch (_) {
      if (!_isCurrent(generation, candidate: connection)) {
        return const PhoneMemoryReadContext.unavailable();
      }
      _setReceipt(const {'source': 'phone_v3_live', 'status': 'unavailable'});
      return const PhoneMemoryReadContext.unavailable();
    }
  }

  Future<_PhoneStatus> _getStatus(_PhoneConnection connection) async {
    final response = await _request('GET', '/v1/memory/status', connection);
    return _PhoneStatus.fromWire(
      _decodeMap(response),
      expected: connection,
      now: _clock(),
    );
  }

  bool _isCurrent(int generation, {_PhoneConnection? candidate}) =>
      _generation == generation &&
      (candidate == null || identical(_connection, candidate));

  /// This closure captures only a generation and expiry, never the bearer
  /// token. It is safe to carry with a bounded context until prompt rendering.
  bool Function() _leaseFor({
    required int generation,
    required DateTime expiresAt,
  }) =>
      () =>
          _generation == generation &&
          _connection != null &&
          expiresAt.isAfter(_clock());

  Future<List<int>> _request(
    String method,
    String path,
    _PhoneConnection connection, {
    Object? data,
  }) async {
    final stopwatch = Stopwatch()..start();
    final cancelToken = CancelToken();
    try {
      final response = await _dio
          .request<ResponseBody>(
            path,
            data: data,
            cancelToken: cancelToken,
            options: Options(
              method: method,
              headers: {'Authorization': 'Bearer ${connection.token}'},
              contentType: Headers.jsonContentType,
              responseType: ResponseType.stream,
              followRedirects: false,
              maxRedirects: 0,
            ),
          )
          .timeout(_requestDeadline);
      final body = response.data;
      if (body == null || _contentLengthExceedsLimit(body.headers)) {
        throw const PhoneMemoryReadException('invalid_phone_response');
      }
      final iterator = StreamIterator<Uint8List>(body.stream);
      final bytes = BytesBuilder(copy: false);
      try {
        while (true) {
          final remaining = _requestDeadline - stopwatch.elapsed;
          if (remaining <= Duration.zero) {
            throw const PhoneMemoryReadException('phone_request_timeout');
          }
          final hasNext = await iterator.moveNext().timeout(remaining);
          if (!hasNext) return bytes.takeBytes();
          if (iterator.current.length > _maxResponseBytes - bytes.length) {
            throw const PhoneMemoryReadException('invalid_phone_response');
          }
          bytes.add(iterator.current);
        }
      } finally {
        await iterator.cancel();
      }
    } finally {
      stopwatch.stop();
      cancelToken.cancel('phone_read_complete');
    }
  }

  static bool _contentLengthExceedsLimit(Map<String, List<String>>? headers) {
    final values = headers?['content-length'];
    final raw = values != null && values.length == 1 ? values.single : null;
    if (raw == null) return false;
    final length = int.tryParse(raw);
    return length == null || length > _maxResponseBytes;
  }

  Map<String, Object?> _decodeMap(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException();
      return decoded.map((key, value) => MapEntry('$key', value));
    } catch (_) {
      throw const PhoneMemoryReadException('invalid_phone_response');
    }
  }

  void _setReceipt(Map<String, Object?> value) {
    _lastReceipt = Map.unmodifiable(value);
    notifyListeners();
  }
}

class PhoneMemoryReadException implements Exception {
  const PhoneMemoryReadException(this.code);
  final String code;
  @override
  String toString() => code;
}

class PhoneMemoryReadContext {
  const PhoneMemoryReadContext({
    required this.status,
    this.capturedAt,
    this.isAuthorizedNow,
    this.episodes = const [],
    this.fragments = const [],
    this.sagas = const [],
  });
  const PhoneMemoryReadContext.notConfigured() : this(status: 'not_configured');
  const PhoneMemoryReadContext.unavailable() : this(status: 'unavailable');
  const PhoneMemoryReadContext.isolated() : this(status: 'isolated');

  final String status;
  final DateTime? capturedAt;

  /// Process-local validity lease. It deliberately has no credential payload.
  final bool Function()? isAuthorizedNow;
  final List<PhoneMemoryEpisode> episodes;
  final List<PhoneMemoryFragment> fragments;
  final List<PhoneMemorySaga> sagas;

  Map<String, Object?> get receipt => {
        'source': 'phone_v3_live',
        'status': status,
        'episodes': episodes.length,
        'fragments': fragments.length,
        'sagas': sagas.length,
        if (capturedAt != null) 'captured_at': capturedAt!.toIso8601String(),
      };

  static PhoneMemoryReadContext _fromWire(
    Map<String, Object?> wire, {
    required _PhoneConnection expected,
    required DateTime now,
    required bool Function() isAuthorizedNow,
  }) {
    if (!_validEnvelope(wire, expected, now)) {
      throw const PhoneMemoryReadException('invalid_phone_response');
    }
    final status = wire['dreaming_status'];
    if (status is! String ||
        !const {'available', 'empty', 'unavailable'}.contains(status)) {
      throw const PhoneMemoryReadException('invalid_phone_response');
    }
    final dreaming = wire['dreaming'];
    if (dreaming is! Map) {
      throw const PhoneMemoryReadException('invalid_phone_response');
    }
    final map = dreaming.map((key, value) => MapEntry('$key', value));
    final episodes = _episodes(map['episodes']);
    final fragments = _fragments(map['fragments']);
    final sagas = _sagas(map['sagas']);
    if ((status == 'available') !=
        (episodes.isNotEmpty || fragments.isNotEmpty || sagas.isNotEmpty)) {
      throw const PhoneMemoryReadException('invalid_phone_response');
    }
    if (status == 'unavailable' &&
        (episodes.isNotEmpty || fragments.isNotEmpty || sagas.isNotEmpty)) {
      throw const PhoneMemoryReadException('invalid_phone_response');
    }
    return PhoneMemoryReadContext(
      status: status,
      capturedAt: DateTime.parse(wire['captured_at'] as String).toUtc(),
      isAuthorizedNow: isAuthorizedNow,
      episodes: episodes,
      fragments: fragments,
      sagas: sagas,
    );
  }
}

class PhoneMemoryEpisode {
  const PhoneMemoryEpisode(this.id, this.narrative, this.score);
  final String id;
  final String narrative;
  final int score;
}

class PhoneMemoryFragment {
  const PhoneMemoryFragment(this.id, this.content, this.score);
  final String id;
  final String content;
  final int score;
}

class PhoneMemorySaga {
  const PhoneMemorySaga(this.id, this.title, this.description);
  final String id;
  final String title;
  final String description;
}

class _PhoneConnection {
  const _PhoneConnection(this.token, this.sessionId, this.expiresAt);
  final String token;
  final String sessionId;
  final DateTime expiresAt;

  static _PhoneConnection? parse(String code, {required DateTime now}) {
    if (code.length > PhoneMemoryReadClient._maxConnectionCodeChars ||
        !RegExp(r'^p5v1\.[A-Za-z0-9_-]+$').hasMatch(code)) {
      return null;
    }
    try {
      final decoded = base64Url.decode(base64Url.normalize(code.substring(5)));
      if (decoded.length > PhoneMemoryReadClient._maxConnectionPayloadBytes) {
        return null;
      }
      final raw = utf8.decode(decoded);
      final value = jsonDecode(raw);
      if (value is! Map || value.length != 4 || value['v'] != 1) return null;
      final token = value['token'];
      final sessionId = value['session_id'];
      final expires = value['expires_at'];
      if (token is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{32,512}$').hasMatch(token) ||
          sessionId is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{1,120}$').hasMatch(sessionId) ||
          expires is! String) {
        return null;
      }
      final expiresAt = DateTime.parse(expires).toUtc();
      if (!expiresAt.isAfter(now)) return null;
      return _PhoneConnection(token, sessionId, expiresAt);
    } catch (_) {
      return null;
    }
  }
}

class _PhoneStatus {
  const _PhoneStatus(this.capturedAt);
  final DateTime capturedAt;
  Map<String, Object?> receipt(String status) => {
        'source': 'phone_v3_live',
        'status': status,
        'captured_at': capturedAt.toIso8601String()
      };
  static _PhoneStatus fromWire(Map<String, Object?> wire,
      {required _PhoneConnection expected, required DateTime now}) {
    if (!_validEnvelope(wire, expected, now)) {
      throw const PhoneMemoryReadException('invalid_phone_status');
    }
    return _PhoneStatus(DateTime.parse(wire['captured_at'] as String).toUtc());
  }
}

bool _validEnvelope(
    Map<String, Object?> wire, _PhoneConnection expected, DateTime now) {
  final captured = wire['captured_at'];
  final expires = wire['expires_at'];
  if (wire['schema_version'] != 1 ||
      wire['source_kind'] != 'phone_v3_live' ||
      wire['character_id'] != 'i' ||
      wire['session_id'] != expected.sessionId ||
      captured is! String ||
      expires is! String) {
    return false;
  }
  try {
    final capturedAt = DateTime.parse(captured).toUtc();
    final expiresAt = DateTime.parse(expires).toUtc();
    return expiresAt.isAfter(now) &&
        expiresAt == expected.expiresAt &&
        capturedAt.isBefore(expiresAt) &&
        !capturedAt.isBefore(
          now.subtract(PhoneMemoryReadClient._maxCaptureAge),
        ) &&
        !capturedAt.isAfter(now.add(const Duration(minutes: 1)));
  } catch (_) {
    return false;
  }
}

List<PhoneMemoryEpisode> _episodes(Object? value) =>
    _list(value, 4).map((item) {
      final m = _map(item);
      return PhoneMemoryEpisode(
          _text(m['id'], 120), _text(m['narrative'], 900), _score(m['score']));
    }).toList(growable: false);
List<PhoneMemoryFragment> _fragments(Object? value) =>
    _list(value, 6).map((item) {
      final m = _map(item);
      return PhoneMemoryFragment(
          _text(m['id'], 120), _text(m['content'], 300), _score(m['score']));
    }).toList(growable: false);
List<PhoneMemorySaga> _sagas(Object? value) => _list(value, 2).map((item) {
      final m = _map(item);
      return PhoneMemorySaga(_text(m['id'], 120), _text(m['title'], 160),
          _text(m['description'], 900));
    }).toList(growable: false);
List<Object?> _list(Object? value, int max) {
  if (value is! List || value.length > max) {
    throw const PhoneMemoryReadException('invalid_phone_response');
  }
  return List<Object?>.from(value);
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw const PhoneMemoryReadException('invalid_phone_response');
  }
  return value.map((k, v) => MapEntry('$k', v));
}

String _text(Object? value, int max) {
  if (value is! String || value.isEmpty || value.length > max) {
    throw const PhoneMemoryReadException('invalid_phone_response');
  }
  return value;
}

int _score(Object? value) {
  if (value is! int) {
    throw const PhoneMemoryReadException('invalid_phone_response');
  }
  return value;
}
