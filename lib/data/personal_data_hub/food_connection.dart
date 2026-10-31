import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';

import 'domain_http_transport.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';
import 'personal_data_hub.dart';

const foodDomainName = 'food_entries';
const foodPhonePrincipalId = 'phone-food-reader';

/// Must equal the Core phone principal's installation_id (foodPrincipalConfigs
/// in tools/i_core/personal_data_domains.mjs). Core binds snapshots and cursors
/// to it, so the replica binding cannot use this phone's device identity.
const foodPhoneInstallationId = 'food-phone';

class FoodCredential {
  const FoodCredential({
    required this.token,
    required this.generation,
    required this.principalId,
    required this.coreInstanceId,
    required this.baseUrl,
  });

  final String token;
  final int generation;
  final String principalId;
  final String coreInstanceId;
  final String baseUrl;
}

class FoodCredentialStore {
  FoodCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _prefix = 'i_core_food_';
  static const _token = '${_prefix}token';
  static const _generation = '${_prefix}generation';
  static const _principal = '${_prefix}principal_id';
  static const _core = '${_prefix}core_instance_id';
  static const _base = '${_prefix}base_url';

  Future<FoodCredential?> read() async {
    final values = await _storage.readAll();
    final generation = int.tryParse(values[_generation] ?? '');
    final token = values[_token];
    final principal = values[_principal];
    final core = values[_core];
    final base = values[_base];
    if (token == null ||
        token.isEmpty ||
        generation == null ||
        generation < 1 ||
        principal == null ||
        principal.isEmpty ||
        core == null ||
        core.isEmpty ||
        base == null ||
        base.isEmpty) {
      return null;
    }
    return FoodCredential(
        token: token,
        generation: generation,
        principalId: principal,
        coreInstanceId: core,
        baseUrl: base);
  }

  Future<void> save(FoodCredential value) async {
    await _storage.write(key: _token, value: value.token);
    await _storage.write(key: _generation, value: '${value.generation}');
    await _storage.write(key: _principal, value: value.principalId);
    await _storage.write(key: _core, value: value.coreInstanceId);
    await _storage.write(key: _base, value: value.baseUrl);
  }

  Future<void> clear() async {
    for (final key in const [_token, _generation, _principal, _core, _base]) {
      await _storage.delete(key: key);
    }
  }
}

class FoodConnectionException implements Exception {
  const FoodConnectionException(this.code);
  final String code;
  @override
  String toString() => 'FoodConnectionException($code)';
}

class FoodPhoneCredentialClient {
  FoodPhoneCredentialClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;

  Future<FoodCredential> claim(CoreSyncConnection connection) async {
    final uri =
        Uri.parse('${connection.baseUrl}/v1/core/food/phone-credential');
    try {
      final response = await _dio.postUri<dynamic>(uri,
          data: const <String, dynamic>{},
          options: Options(
            contentType: Headers.jsonContentType,
            responseType: ResponseType.json,
            followRedirects: false,
            validateStatus: (_) => true,
            headers: {
              'Authorization': 'Bearer ${connection.deviceToken}',
              'X-Core-Protocol': CoreSyncProtocol.version,
            },
          ));
      final body = response.data;
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        final error = body is Map ? body['error'] : null;
        final code = error is Map ? error['code']?.toString() : null;
        throw FoodConnectionException(_mappedCode(code));
      }
      if (body is! Map) throw const FoodConnectionException('invalid_response');
      final generation = body['generation'];
      final token = body['token'];
      if (body['format'] != 'food-phone-credential-v1' ||
          body['domain'] != foodDomainName ||
          body['principal_id'] != foodPhonePrincipalId ||
          body['core_instance_id'] != connection.coreNodeId ||
          generation is! int ||
          generation < 1 ||
          token is! String ||
          token.length < 24) {
        throw const FoodConnectionException('invalid_response');
      }
      return FoodCredential(
          token: token,
          generation: generation,
          principalId: foodPhonePrincipalId,
          coreInstanceId: connection.coreNodeId,
          baseUrl: connection.baseUrl);
    } on FoodConnectionException {
      rethrow;
    } on DioException {
      throw const FoodConnectionException('network_error');
    } on FormatException {
      throw const FoodConnectionException('invalid_response');
    }
  }

  String _mappedCode(String? code) => switch (code) {
        'food_not_provisioned' => 'food_not_provisioned',
        'phone_device_required' => 'phone_device_required',
        'unauthorized' => 'unauthorized',
        _ => 'network_error',
      };
}

enum FoodConnectionPhase { disconnected, connected, notProvisioned, failed }

class FoodConnectionStatus {
  const FoodConnectionStatus(this.phase, [this.detail]);
  final FoodConnectionPhase phase;

  /// Short error code shown with a failure, never a token or URL.
  final String? detail;
  String get label => switch (phase) {
        FoodConnectionPhase.connected => '已连接',
        FoodConnectionPhase.notProvisioned => '电脑端尚未开通',
        FoodConnectionPhase.disconnected || FoodConnectionPhase.failed => '未连接',
      };
  String get screenMessage => switch (phase) {
        FoodConnectionPhase.notProvisioned => '电脑端尚未开通饮食同步',
        FoodConnectionPhase.failed =>
          detail == null ? '同步失败，下拉重试' : '同步失败（$detail），下拉重试',
        _ => '尚未连接林埃核心',
      };
}

typedef FoodClaim = Future<FoodCredential> Function(
    CoreSyncConnection connection);

class FoodConnector extends ChangeNotifier {
  FoodConnector({
    FoodCredentialStore? credentialStore,
    Future<CoreSyncConnection?> Function()? readConnection,
    FoodClaim? claim,
    DomainTransport Function(
            String baseUrl, String token, DomainBinding binding)?
        createTransport,
  })  : _credentialStore = credentialStore ?? FoodCredentialStore(),
        _readConnection =
            readConnection ?? CoreSyncConnectionStore.instance.read,
        _claim = claim ?? FoodPhoneCredentialClient().claim,
        _createTransport = createTransport ??
            ((baseUrl, token, binding) => DomainHttpTransport(
                baseUrl: baseUrl, token: token, binding: binding));

  static final FoodConnector instance = FoodConnector();
  final FoodCredentialStore _credentialStore;
  final Future<CoreSyncConnection?> Function() _readConnection;
  final FoodClaim _claim;
  final DomainTransport Function(String, String, DomainBinding)
      _createTransport;
  FoodConnectionStatus _status =
      const FoodConnectionStatus(FoodConnectionPhase.disconnected);
  FoodConnectionStatus get status => _status;
  bool _reclaimedThisProcess = false;
  Future<void>? _activeEnsure;

  Future<void> ensureAttached(PersonalDataHub hub) {
    final running = _activeEnsure;
    if (running != null) return running;
    late final Future<void> tracked;
    tracked = _ensureAttached(hub).whenComplete(() {
      if (identical(_activeEnsure, tracked)) _activeEnsure = null;
    });
    _activeEnsure = tracked;
    return tracked;
  }

  Future<void> _ensureAttached(PersonalDataHub hub) async {
    try {
      final connection = await _readConnection();
      if (connection == null) {
        hub.detach(foodDomainName);
        _setStatus(FoodConnectionPhase.disconnected);
        return;
      }
      var credential = await _credentialStore.read();
      if (credential == null ||
          credential.baseUrl != connection.baseUrl ||
          credential.coreInstanceId != connection.coreNodeId ||
          credential.principalId != foodPhonePrincipalId) {
        await _credentialStore.clear();
        credential = await _claim(connection);
        if (!_matchesConnection(credential, connection)) {
          throw const FoodConnectionException('invalid_response');
        }
        await _credentialStore.save(credential);
      }
      final binding = DomainBinding(
          coreInstanceId: connection.coreNodeId,
          principalId: foodPhonePrincipalId,
          generation: credential.generation,
          installationId: foodPhoneInstallationId);
      final attached = hub.storeFor(foodDomainName);
      if (attached != null &&
          canonicalJson(attached.binding.forDomain(foodDomainName)) ==
              canonicalJson(binding.forDomain(foodDomainName))) {
        // A sync failure stays visible until a later sync succeeds.
        if (_status.phase != FoodConnectionPhase.failed) {
          _setStatus(FoodConnectionPhase.connected);
        }
        return;
      }
      final store = DomainStore(hub.db, binding: binding);
      final state = await store.read();
      final domain = store.domain(state, foodDomainName);
      if (canonicalJson(domain['binding']) !=
          canonicalJson(binding.forDomain(foodDomainName))) {
        await store.resetCredentialView(foodDomainName);
      }
      final refreshed = store.domain(await store.read(), foodDomainName);
      if (refreshed['route'] != DomainRoute.core.name) {
        await store.configureRoute(foodDomainName, DomainRoute.core);
      }
      hub.attach(foodDomainName, store,
          _createTransport(connection.baseUrl, credential.token, binding),
          allowLocalRecall: false);
      _setStatus(FoodConnectionPhase.connected);
    } on FoodConnectionException catch (error) {
      if (error.code == 'food_not_provisioned') {
        hub.detach(foodDomainName);
        _setStatus(FoodConnectionPhase.notProvisioned);
      } else {
        hub.detach(foodDomainName);
        _setStatus(FoodConnectionPhase.failed);
      }
    } catch (_) {
      hub.detach(foodDomainName);
      _setStatus(FoodConnectionPhase.failed);
    }
  }

  bool _matchesConnection(
          FoodCredential credential, CoreSyncConnection connection) =>
      credential.baseUrl == connection.baseUrl &&
      credential.coreInstanceId == connection.coreNodeId &&
      credential.principalId == foodPhonePrincipalId &&
      credential.generation > 0 &&
      credential.token.length >= 24;

  Future<void> handleSyncResult(PersonalDataHub hub) async {
    final error = hub.lastSyncErrors[foodDomainName];
    if (error == null) {
      if (hub.storeFor(foodDomainName) != null) {
        _setStatus(FoodConnectionPhase.connected);
      }
      return;
    }
    if (!['unauthenticated', 'credential_expired'].contains(error)) {
      _setStatus(FoodConnectionPhase.failed, _safeDetail(error));
      return;
    }
    if (_reclaimedThisProcess) {
      _setStatus(FoodConnectionPhase.failed, _safeDetail(error));
      return;
    }
    _reclaimedThisProcess = true;
    await _credentialStore.clear();
    hub.detach(foodDomainName);
    await ensureAttached(hub);
    if (hub.storeFor(foodDomainName) != null) {
      try {
        await hub.syncOnce(foodDomainName);
      } catch (_) {
        _setStatus(FoodConnectionPhase.failed);
      }
      final retried = hub.lastSyncErrors[foodDomainName];
      if (retried == null) {
        _setStatus(FoodConnectionPhase.connected);
      } else {
        _setStatus(FoodConnectionPhase.failed, _safeDetail(retried));
      }
    }
  }

  static String? _safeDetail(Object? code) {
    final text = code?.toString();
    if (text == null || !RegExp(r'^[a-z0-9_]{1,48}$').hasMatch(text)) {
      return null;
    }
    return text;
  }

  Future<void> disconnect(PersonalDataHub hub) async {
    try {
      await _credentialStore.clear();
    } finally {
      hub.detach(foodDomainName);
    }
    _setStatus(FoodConnectionPhase.disconnected);
  }

  void _setStatus(FoodConnectionPhase phase, [String? detail]) {
    if (_status.phase == phase && _status.detail == detail) return;
    _status = FoodConnectionStatus(phase, detail);
    notifyListeners();
  }
}
