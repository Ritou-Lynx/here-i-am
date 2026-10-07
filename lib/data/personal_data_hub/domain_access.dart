import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';

import 'domain_http_transport.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';
import 'capture_owner_migration.dart';
import 'personal_data_hub.dart';
import 'planning_service.dart';

/// In-memory result of a separately provisioned domain credential. Attaching
/// the transport does not change the persisted route or capture bridge owner.
class ConfiguredDomainAccess {
  const ConfiguredDomainAccess(
      {required this.stores,
      required this.authorizeCapture,
      required this.authorizePlanning,
      required this.captureAdoptionVerifier,
      required this.captureAdoptionReceiptRefetch});

  final Map<String, DomainStore> stores;
  DomainStore? get captureStore => stores['captures'];
  final Future<String> Function(Json request)? authorizeCapture;
  final PlanningAuthorize? authorizePlanning;
  final CaptureAdoptionProofVerifier? captureAdoptionVerifier;
  final CaptureAdoptionReceiptRefetch? captureAdoptionReceiptRefetch;
}

/// Optional startup boundary. Local Hub startup must not depend on a platform
/// keystore or an owner-provisioned Core grant being readable. Database setup
/// and runtime construction intentionally remain outside this boundary.
Future<ConfiguredDomainAccess?> loadOptionalDomainAccess({
  required PersonalDataHub hub,
  Future<CoreSyncConnection?> Function()? readConnection,
  Future<String> Function()? readInstallationId,
  void Function(String code)? reportError,
}) async {
  final reader = readConnection ?? CoreSyncConnectionStore.instance.read;
  try {
    final connection = await reader();
    if (connection == null) return null;
    return await attachConfiguredDomainAccess(
      hub: hub,
      connection: connection,
      installationId:
          await (readInstallationId ?? DeviceIdentityService.getOrCreate)
              .call(),
      currentConnection: reader,
    );
  } catch (_) {
    reportError?.call('hub_domain_access_unavailable');
    return null;
  }
}

/// Signs only the final immutable intent produced by [DomainStore.enqueue].
/// The secret is supplied by the separately scoped domain grant and is never
/// written to the domain database, UI evidence, logs, or request body.
class DomainUiAuthorizationSigner {
  DomainUiAuthorizationSigner(CoreDomainAccessGrant grant,
      {Future<void> Function()? verifyCredential})
      : _grant = grant,
        _secret = _decodeSecret(grant.authorization.secret),
        _verifyCredential = verifyCredential;

  final CoreDomainAccessGrant _grant;
  final List<int> _secret;
  final Future<void> Function()? _verifyCredential;

  Future<String> issue(Json request) async {
    await _verifyCredential?.call();
    final domain = request['domain'];
    final binding = jsonObject(request['binding']);
    final intent = jsonObject(request['intent']);
    if (domain is! String ||
        !const {'captures', 'plan_items'}.contains(domain) ||
        intent.containsKey('authorization_ref') ||
        intent['core_instance_id'] != _grant.coreInstanceId ||
        intent['actor'] != 'user_direct') {
      throw const DomainFailure('actor_evidence_required');
    }
    final expectedBinding = <String, dynamic>{
      'core_instance_id': _grant.coreInstanceId,
      'principal_id': _grant.principalId,
      'credential_generation': _grant.credentialGeneration,
      'installation_id': _grant.installationId,
    };
    for (final entry in expectedBinding.entries) {
      if (binding[entry.key] != entry.value) {
        throw const DomainFailure('binding_changed');
      }
    }
    if (domain == 'captures') {
      _checkCaptureRequest(request, intent);
    } else {
      _checkPlanStatusRequest(request, intent);
    }
    final payload = <String, dynamic>{
      'protocol': 'i-domain-ui-v1',
      'domain': domain,
      'binding': expectedBinding,
      'intent': copyJson(intent),
    };
    final digest = Hmac(sha256, _secret)
        .convert(utf8.encode(canonicalJson(payload)))
        .bytes;
    final mac = base64UrlEncode(digest).replaceAll('=', '');
    return 'uia1.${_grant.authorization.keyId}.$mac';
  }

  void _checkCaptureRequest(Json request, Json intent) {
    final kind = intent['kind'];
    if (!const {'create', 'patch', 'delete'}.contains(kind) ||
        request['surface'] != 'quick_capture_send' ||
        request['capture_id'] != intent['id'] ||
        request['action'] != kind ||
        !_grant.scopes.contains('captures:$kind')) {
      throw const DomainFailure('scope_forbidden');
    }
    if (kind == 'create') {
      final data = jsonObject(intent['data']);
      final provenance = jsonObject(intent['provenance']);
      if (data['source'] != 'phone_quick' ||
          provenance['source'] != 'phone_quick' ||
          data['text'] is! String) {
        throw const DomainFailure('actor_evidence_required');
      }
      _checkTextDigest(request, data['text'] as String);
    } else if (kind == 'patch') {
      final patch = jsonObject(intent['patch']);
      if (patch.keys.toSet().difference(const {'text'}).isNotEmpty ||
          patch['text'] is! String) {
        throw const DomainFailure('actor_evidence_required');
      }
      _checkTextDigest(request, patch['text'] as String);
    }
  }

  void _checkPlanStatusRequest(Json request, Json intent) {
    final patch = jsonObject(intent['patch']);
    if (intent['kind'] != 'status' ||
        request['surface'] != 'planning_status' ||
        request['action'] != 'status' ||
        request['item_id'] != intent['id'] ||
        patch.length != 1 ||
        !const {'完成', '放弃'}.contains(patch['status']) ||
        request['status'] != patch['status'] ||
        !_grant.scopes.contains('plan_items:status')) {
      throw const DomainFailure('scope_forbidden');
    }
  }

  void _checkTextDigest(Json request, String text) {
    final expected = sha256.convert(utf8.encode(text)).toString();
    if (request['text_sha256'] != expected) {
      throw const DomainFailure('actor_evidence_required');
    }
  }

  static List<int> _decodeSecret(String value) {
    final padded = value.padRight((value.length + 3) ~/ 4 * 4, '=');
    final bytes = base64Url.decode(padded);
    if (bytes.length != 32) {
      throw const FormatException('domain authorization key must be 32 bytes');
    }
    return bytes;
  }
}

/// Converts an optional owner-provisioned pairing grant into a real captures
/// transport. Old pairings and incomplete grants stay on phone-local storage.
/// Existing Core routes with a different binding are never retargeted here.
Future<ConfiguredDomainAccess?> attachConfiguredDomainAccess({
  required PersonalDataHub hub,
  required CoreSyncConnection connection,
  required String installationId,
  Future<CoreSyncConnection?> Function()? currentConnection,
}) async {
  final grant = connection.domainAccess;
  if (grant == null ||
      grant.protocolVersion != 1 ||
      grant.policyVersion != DomainPolicy.version ||
      grant.schemaVersion != 1 ||
      grant.authorization.scheme != 'hmac-sha256-v1' ||
      grant.coreInstanceId != connection.coreNodeId ||
      grant.installationId != installationId ||
      grant.token == connection.deviceToken) {
    return null;
  }
  final binding = DomainBinding(
    coreInstanceId: grant.coreInstanceId,
    principalId: grant.principalId,
    generation: grant.credentialGeneration,
    installationId: grant.installationId,
    policyVersion: grant.policyVersion,
    schemaVersion: grant.schemaVersion,
  );
  final readConnection =
      currentConnection ?? CoreSyncConnectionStore.instance.read;
  final expectedConnection = canonicalJson(_connectionIdentity(connection));
  Future<void> verifyCredential() async {
    final current = await readConnection();
    if (current == null ||
        canonicalJson(_connectionIdentity(current)) != expectedConnection) {
      throw const DomainFailure('binding_changed');
    }
  }

  const readRequirements = {
    'captures': {'captures:read', 'captures:ack'},
    'plan_items': {'plan_items:read', 'plan_items:ack'},
    'plan_days': {'plan_days:read', 'plan_days:ack'},
    'plan_weeks': {'plan_weeks:read', 'plan_weeks:ack'},
  };
  final stores = <String, DomainStore>{};
  DomainHttpTransport? captureTransport;
  for (final entry in readRequirements.entries) {
    if (!entry.value.every(grant.scopes.contains)) continue;
    final name = entry.key;
    final store = DomainStore(hub.db, binding: binding);
    final state = await store.read();
    final existing = (state['domains'] as Map?)?[name];
    if (existing is Map &&
        canonicalJson(existing['binding']) !=
            canonicalJson(binding.forDomain(name))) {
      if (existing['route'] != 'phone') continue;
      await store.resetCredentialView(name);
    }
    final transport = DomainHttpTransport(
      baseUrl: connection.baseUrl,
      token: grant.token,
      binding: binding,
      verifyCredential: verifyCredential,
    );
    hub.attach(
      name,
      store,
      transport,
      allowLocalRecall: name == 'captures',
    );
    if (name == 'captures') captureTransport = transport;
    stores[name] = store;
  }
  if (stores.isEmpty) return null;
  final signer = DomainUiAuthorizationSigner(
    grant,
    verifyCredential: verifyCredential,
  );
  final captureAdoptionVerifier = stores.containsKey('captures') &&
          grant.scopes.contains('captures:adopt') &&
          grant.scopes.contains('captures:owner')
      ? CaptureAdoptionProofVerifier(grant, verifyCredential: verifyCredential)
      : null;
  final captureAdoptionReceiptRefetch =
      captureAdoptionVerifier != null && captureTransport != null
          ? createCaptureAdoptionReceiptRefetch(captureTransport, grant)
          : null;
  final authorizeCapture = stores.containsKey('captures') &&
          const {
            'captures:create',
            'captures:patch',
            'captures:delete',
          }.every(grant.scopes.contains)
      ? signer.issue
      : null;
  PlanningAuthorize? authorizePlanning;
  if (stores.containsKey('plan_items') &&
      grant.scopes.contains('plan_items:status')) {
    authorizePlanning =
        (GeneratedDatabase db, PlanningUiAuthorization action) async {
      final request = action.toAuthorizationRequest();
      final ref = await signer.issue(request);
      await db.customStatement(
        'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)',
        [
          'planning_action.${action.actionId}',
          jsonEncode(action.toJson(authorizationRef: ref)),
          'planning_ui_authorization',
          action.at.millisecondsSinceEpoch,
        ],
      );
      return ref;
    };
  }
  return ConfiguredDomainAccess(
    stores: Map.unmodifiable(stores),
    authorizeCapture: authorizeCapture,
    authorizePlanning: authorizePlanning,
    captureAdoptionVerifier: captureAdoptionVerifier,
    captureAdoptionReceiptRefetch: captureAdoptionReceiptRefetch,
  );
}

Json _connectionIdentity(CoreSyncConnection connection) => {
      'base_url': connection.baseUrl,
      'device_token': connection.deviceToken,
      'initial_cursor': connection.initialCursor,
      'core_node_id': connection.coreNodeId,
      'domain_access': connection.domainAccess?.toJson(),
    };
