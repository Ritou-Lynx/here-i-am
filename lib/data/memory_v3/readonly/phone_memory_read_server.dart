import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:yaml/yaml.dart';

import 'phone_dreaming_read_service.dart';

class PhoneMemoryReadIdentity {
  const PhoneMemoryReadIdentity(this.accountId, this.databaseIdentity);
  final String accountId;
  final Object databaseIdentity;
}

class PhoneMemoryReadSession {
  PhoneMemoryReadSession._(
      this._token, this.sessionId, this.expiresAt, this.port);
  final String _token;
  final String sessionId;
  final DateTime expiresAt;
  final int port;
  String get connectionCode => 'p5v1.${base64Url.encode(utf8.encode(jsonEncode({
            'v': 1,
            'token': _token,
            'session_id': sessionId,
            'expires_at': expiresAt.toUtc().toIso8601String(),
          }))).replaceAll('=', '')}';
}

/// Explicit, process-memory-only USB loopback session. Neither constructing nor
/// accessing [instance] starts a server or initializes a database.
class PhoneMemoryReadServer extends ChangeNotifier {
  PhoneMemoryReadServer({
    Future<PhoneMemoryReadIdentity?> Function()? identity,
    Future<Map<String, Object?>> Function(String query)? read,
    DateTime Function()? now,
    int port = 47851,
    Duration queryTimeout = const Duration(seconds: 8),
    Duration requestTimeout = const Duration(seconds: 4),
  })  : _identity = identity ?? _productionIdentity,
        _read = read,
        _now = now ?? DateTime.now,
        _port = port,
        _queryTimeout = queryTimeout,
        _requestTimeout = requestTimeout;

  static final instance = PhoneMemoryReadServer();
  final Future<PhoneMemoryReadIdentity?> Function() _identity;
  final Future<Map<String, Object?>> Function(String)? _read;
  final DateTime Function() _now;
  final int _port;
  final Duration _queryTimeout;
  final Duration _requestTimeout;
  HttpServer? _server;
  PhoneMemoryReadSession? _session;
  PhoneMemoryReadIdentity? _owner;
  Timer? _expiry;
  Timer? _identityPoll;
  bool _checkingIdentity = false;
  bool _starting = false;
  bool _queryBusy = false;
  int _generation = 0;
  bool _disposed = false;
  PhoneMemoryReadSession? get session => _session;
  bool get isRunning =>
      _session != null &&
      _server != null &&
      _now().isBefore(_session!.expiresAt);

  Future<Result<PhoneMemoryReadSession>> start() async {
    if (_disposed || _starting) return Error(StateError('session_unavailable'));
    if (isRunning) return Ok(_session!);
    if (_server != null) await stop();
    _starting = true;
    final generation = ++_generation;
    final result = await runResult<PhoneMemoryReadSession>(() async {
      final owner = await _identity().timeout(_requestTimeout);
      if (owner == null || owner.accountId.trim().isEmpty) {
        throw StateError('identity_unavailable');
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port,
          shared: false);
      if (_disposed || generation != _generation) {
        await server.close(force: true);
        throw StateError('session_closed');
      }
      server.idleTimeout = _requestTimeout;
      server.autoCompress = false;
      final random = Random.secure();
      String secret(int length) => base64Url
          .encode(List.generate(length, (_) => random.nextInt(256)))
          .replaceAll('=', '');
      final session = PhoneMemoryReadSession._(secret(32), secret(18),
          _now().toUtc().add(const Duration(minutes: 30)), server.port);
      _server = server;
      _owner = owner;
      _session = session;
      _expiry = Timer(const Duration(minutes: 30), () {
        unawaited(stop());
      });
      _identityPoll = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_checkingIdentity) return;
        _checkingIdentity = true;
        unawaited(_authorized(generation).whenComplete(() {
          _checkingIdentity = false;
        }));
      });
      server.listen((request) {
        unawaited(_handle(request, generation));
      }, onError: (Object _) {
        unawaited(stop());
      });
      _notify();
      return session;
    });
    _starting = false;
    return switch (result) {
      Ok(:final value) => Ok(value),
      Error() => Error(StateError('session_unavailable')),
    };
  }

  Future<Result<void>> stop() async {
    ++_generation;
    _session = null;
    _owner = null;
    _expiry?.cancel();
    _identityPoll?.cancel();
    _expiry = null;
    _identityPoll = null;
    final server = _server;
    _server = null;
    _notify();
    final result = await runResultVoid(() async {
      await server?.close(force: true);
    });
    return result is Ok<void>
        ? const Ok.v()
        : Error(StateError('session_close_failed'));
  }

  Future<bool> _authorized(int generation) async {
    if (generation != _generation || !isRunning) {
      if (generation == _generation && _session != null) unawaited(stop());
      return false;
    }
    final result = await runResult(() => _identity().timeout(_requestTimeout));
    final identity =
        result is Ok<PhoneMemoryReadIdentity?> ? result.value : null;
    final valid = generation == _generation &&
        isRunning &&
        identity != null &&
        identity.accountId == _owner?.accountId &&
        identical(identity.databaseIdentity, _owner?.databaseIdentity);
    if (!valid && generation == _generation) unawaited(stop());
    return valid;
  }

  Future<void> _handle(HttpRequest request, int generation) async {
    StreamSubscription<List<int>>? bodySubscription;
    final result = await runResult<void>(() async {
      final session = _session;
      if (request.headers['origin'] != null) {
        return _error(request, 403, 'origin_forbidden');
      }
      if (request.uri.hasQuery || request.uri.hasFragment) {
        return _error(request, 400, 'invalid_request');
      }
      if (session == null ||
          !_matches(request.headers['authorization'], session._token)) {
        return _error(request, 401, 'unauthorized');
      }
      if (!await _authorized(generation)) {
        return _error(request, 401, 'session_invalid');
      }
      final path = request.uri.path;
      if (!const {'/v1/memory/status', '/v1/memory/read-context'}
          .contains(path)) {
        return _error(request, 404, 'not_found');
      }
      if (request.method != (path.endsWith('/status') ? 'GET' : 'POST')) {
        return _error(request, 405, 'method_not_allowed');
      }
      if (path.endsWith('/status')) {
        if (request.contentLength > 0 ||
            request.headers['transfer-encoding'] != null) {
          return _error(request, 400, 'invalid_request');
        }
        return _send(request, 200, _metadata(session));
      }
      if (_queryBusy) return _error(request, 429, 'query_busy');
      _queryBusy = true;
      // Retain this lock until underlying work completes even after timeout;
      // Future.timeout cannot cancel a database operation.
      Future<Map<String, Object?>>? work;
      try {
        if (request.contentLength > 16384) {
          return _error(request, 413, 'request_too_large');
        }
        if (request.headers.contentType?.mimeType != 'application/json' ||
            request.headers['content-encoding'] != null) {
          return _error(request, 400, 'invalid_request');
        }
        final bytes = <int>[];
        final bodyDone = Completer<void>();
        bodySubscription = request.listen((chunk) {
          if (bodyDone.isCompleted) return;
          if (bytes.length + chunk.length > 16384) {
            bodySubscription?.pause();
            bodyDone.completeError(const _RequestTooLarge());
          } else {
            bytes.addAll(chunk);
          }
        }, onDone: () {
          if (!bodyDone.isCompleted) bodyDone.complete();
        }, onError: (Object error) {
          if (!bodyDone.isCompleted) bodyDone.completeError(error);
        });
        // Do not cancel the request before sending the bounded error response:
        // cancellation destroys its socket, hiding 413 from the client.
        await bodyDone.future.timeout(_requestTimeout, onTimeout: () {
          bodySubscription?.pause();
          throw TimeoutException('request_timeout');
        });
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map<String, dynamic> ||
            body.length != 3 ||
            body['schema_version'] != 1 ||
            body['character_id'] != 'i' ||
            body['query'] is! String ||
            (body['query'] as String).trim().isEmpty ||
            (body['query'] as String).length > 2000) {
          return _error(request, 400, 'invalid_request');
        }
        if (!await _authorized(generation)) {
          return _error(request, 401, 'session_invalid');
        }
        final database = _owner?.databaseIdentity;
        work = Future.sync(() => _read != null
            ? _read(body['query'] as String)
            : PhoneDreamingReadService(database as AppDatabase)
                .read(body['query'] as String));
        final readResult = await runResult(() => work!.timeout(_queryTimeout));
        if (!await _authorized(generation)) {
          return _error(request, 401, 'session_invalid');
        }
        if (readResult is Error<Map<String, Object?>>) {
          return _send(request, 200, {
            ..._metadata(session),
            'dreaming_status': 'unavailable',
            'reason': 'read_unavailable',
            'dreaming': _empty
          });
        }
        final dreaming = (readResult as Ok<Map<String, Object?>>).value;
        final available =
            dreaming.values.any((value) => value is List && value.isNotEmpty);
        return _send(request, 200, {
          ..._metadata(session),
          'dreaming_status': available ? 'available' : 'empty',
          'dreaming': dreaming
        });
      } finally {
        if (work == null) {
          _queryBusy = false;
        } else {
          unawaited(work.then<void>((_) {
            _queryBusy = false;
          }, onError: (Object _) {
            _queryBusy = false;
          }));
        }
      }
    });
    if (result is Error<void>) {
      final error = result.error;
      await runResultVoid(() => _error(
          request,
          error is _RequestTooLarge
              ? 413
              : error is FormatException
                  ? 400
                  : 503,
          error is _RequestTooLarge
              ? 'request_too_large'
              : error is FormatException
                  ? 'invalid_request'
                  : 'request_unavailable'));
    }
    await runResultVoid(() async {
      await bodySubscription?.cancel();
    });
  }

  static const _empty = {
    'episodes': <Object>[],
    'fragments': <Object>[],
    'sagas': <Object>[]
  };
  Map<String, Object?> _metadata(PhoneMemoryReadSession session) => {
        'schema_version': 1,
        'source_kind': 'phone_v3_live',
        'character_id': 'i',
        'session_id': session.sessionId,
        'captured_at': _now().toUtc().toIso8601String(),
        'expires_at': session.expiresAt.toUtc().toIso8601String(),
      };
  static bool _matches(List<String>? values, String token) {
    if (values == null || values.length != 1) return false;
    final expected = 'Bearer $token';
    final actual = values.single;
    var difference = actual.length ^ expected.length;
    for (var i = 0; i < expected.length; i++) {
      difference |= expected.codeUnitAt(i) ^
          (i < actual.length ? actual.codeUnitAt(i) : 0);
    }
    return difference == 0;
  }

  static Future<void> _error(HttpRequest request, int status, String code) =>
      _send(request, status, {
        'error': {'code': code}
      });
  static Future<void> _send(
      HttpRequest request, int status, Map<String, Object?> body) async {
    var bytes = utf8.encode(jsonEncode(body));
    if (bytes.length > 32768) {
      status = 503;
      bytes = utf8.encode('{"error":{"code":"response_too_large"}}');
    }
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('cache-control', 'no-store');
    request.response.headers.set('x-content-type-options', 'nosniff');
    request.response.persistentConnection = false;
    request.response.add(bytes);
    await request.response.close();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  static Future<PhoneMemoryReadIdentity?> _productionIdentity() async {
    final account = await UserStorage.getUserId();
    if (account == null ||
        account.isEmpty ||
        !AppDatabase.isInitialized ||
        AppDatabase.activeUserId != account) {
      return null;
    }
    final db = AppDatabase.instance;
    // getCharacter() seeds/migrates files. Read only the existing enabled flag.
    final file = File(
        '${CharacterService.instance.getCharactersPath(account)}${Platform.pathSeparator}i.yaml');
    if (!await file.exists() || await file.length() > 262144) return null;
    final yaml = loadYaml(await file.readAsString());
    if (yaml is! YamlMap ||
        yaml['enabled'] != true ||
        AppDatabase.activeUserId != account ||
        !identical(db, AppDatabase.instance) ||
        await UserStorage.getUserId() != account) {
      return null;
    }
    return PhoneMemoryReadIdentity(account, db);
  }
}

class _RequestTooLarge implements Exception {
  const _RequestTooLarge();
}
