import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:memex/data/memory_v3/notes/claude_web_note_feed_storage.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';
import 'package:memex/data/personal_data_hub/capture_owner_migration.dart';
import 'package:memex/data/personal_data_hub/domain_access.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/data/services/sync/core_sync_runtime_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:uuid/uuid.dart';

typedef DomainAccessLoader = Future<ConfiguredDomainAccess?> Function();
typedef DomainAccessReplacer = Future<void> Function(
  CoreSyncConnection expected,
  CoreDomainAccessGrant? next,
);

abstract interface class CoreDomainWorkflow {
  Future<CoreDomainWorkflowStatus> readStatus();
  Future<String> exportGrantBinding();
  Future<DomainGrantImportResult> importGrant(String envelopeJson);
  Future<void> revokeGrant();
  Future<String> freezeCaptureMigration();
  Future<String> exportFrozenCaptureManifest();
  Future<void> commitCaptureMigration(String envelopeJson);
  Future<void> abortCaptureMigration();
}

class CoreDomainWorkflowFailure implements Exception {
  const CoreDomainWorkflowFailure(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class DomainGrantImportResult {
  const DomainGrantImportResult({
    required this.rotated,
    required this.routeBindingBlocked,
  });
  final bool rotated;
  final bool routeBindingBlocked;
}

class CoreDomainGrantView {
  const CoreDomainGrantView({
    required this.coreInstanceId,
    required this.principalId,
    required this.credentialGeneration,
    required this.scopes,
  });
  final String coreInstanceId;
  final String principalId;
  final int credentialGeneration;
  final List<String> scopes;
}

class CoreDomainWorkflowStatus {
  const CoreDomainWorkflowStatus({
    required this.chatConfigured,
    required this.captureOwner,
    required this.routeBindingBlocked,
    this.pairedCoreInstanceId,
    this.installationId,
    this.grant,
    this.frozenMigrationId,
  });
  final bool chatConfigured;
  final String captureOwner;
  final bool routeBindingBlocked;
  final String? pairedCoreInstanceId;
  final String? installationId;
  final CoreDomainGrantView? grant;
  final String? frozenMigrationId;
}

/// Explicit product boundary for owner-provisioned domain authorization and
/// the capture migration. It accepts only exact Core CLI envelopes and never
/// logs, returns, or exposes bearer/HMAC material after import.
class CoreDomainWorkflowService implements CoreDomainWorkflow {
  CoreDomainWorkflowService({
    required this.db,
    required this.hub,
    required this.ownership,
    required this.readConnection,
    required this.replaceDomainAccess,
    required this.readInstallationId,
    required this.reloadRuntime,
    required this.readLegacyFeedConfig,
    DomainAccessLoader? loadAccess,
    String Function()? createMigrationId,
  })  : _loadAccess = loadAccess,
        _createMigrationId = createMigrationId ?? const Uuid().v4;

  factory CoreDomainWorkflowService.production() {
    final db = AppDatabase.instance;
    final hub = PersonalDataHub.forDatabase(db);
    final ownership = CaptureConsumerOwnership.forDatabase(db);
    final connectionStore = CoreSyncConnectionStore.instance;
    return CoreDomainWorkflowService(
      db: db,
      hub: hub,
      ownership: ownership,
      readConnection: connectionStore.read,
      replaceDomainAccess: (expected, next) => connectionStore
          .replaceDomainAccess(expected: expected, domainAccess: next),
      readInstallationId: DeviceIdentityService.getOrCreate,
      reloadRuntime: CoreSyncRuntimeService.instance.rebuildDomainRuntime,
      readLegacyFeedConfig: ClaudeWebNoteFeedStorage().readConfig,
    );
  }

  final AppDatabase db;
  final PersonalDataHub hub;
  final CaptureConsumerOwnership ownership;
  final Future<CoreSyncConnection?> Function() readConnection;
  final DomainAccessReplacer replaceDomainAccess;
  final Future<String> Function() readInstallationId;
  final Future<void> Function() reloadRuntime;
  final Future<ClaudeWebNoteFeedConfig?> Function() readLegacyFeedConfig;
  final DomainAccessLoader? _loadAccess;
  final String Function() _createMigrationId;

  static const _grantFormat = 'i-core-domain-access-export-v1';
  static const _installationBindingFormat =
      'i-core-phone-installation-binding-v1';
  static const _domainBindingFormat = 'i-core-domain-access-binding-v1';
  static const _manifestFormat = 'i-core-capture-migration-manifest-export-v1';
  static const _proofFormat = 'i-core-capture-migration-proof-v1';
  static const _grantKeys = {
    'protocol_version',
    'core_instance_id',
    'principal_id',
    'credential_generation',
    'installation_id',
    'policy_version',
    'schema_version',
    'token',
    'scopes',
    'authorization',
  };

  @override
  Future<CoreDomainWorkflowStatus> readStatus() async {
    final connection = await readConnection();
    final capture = await ownership.workflowState();
    final grant = connection?.domainAccess;
    String? installationId;
    if (connection != null) {
      try {
        installationId = await readInstallationId();
      } catch (_) {
        // Chat status remains usable; binding export will fail explicitly.
      }
    }
    return CoreDomainWorkflowStatus(
      chatConfigured: connection != null,
      captureOwner: capture.owner,
      routeBindingBlocked:
          grant != null && await _hasCoreRouteBindingMismatch(grant),
      pairedCoreInstanceId: connection?.coreNodeId,
      installationId: installationId,
      grant: grant == null
          ? null
          : CoreDomainGrantView(
              coreInstanceId: grant.coreInstanceId,
              principalId: grant.principalId,
              credentialGeneration: grant.credentialGeneration,
              scopes: List.unmodifiable(grant.scopes),
            ),
      frozenMigrationId: capture.frozenManifest?.migrationId,
    );
  }

  @override
  Future<String> exportGrantBinding() async {
    final connection = await readConnection();
    if (connection == null) {
      throw const CoreDomainWorkflowFailure(
          'chat_pair_required', '请先连接这台设备与核心');
    }
    final installationId = await readInstallationId();
    final grant = connection.domainAccess;
    if (grant == null) {
      return jsonEncode({
        'format': _installationBindingFormat,
        'binding': {
          'core_instance_id': connection.coreNodeId,
          // The App has one installation identity. Pair request.device_id and
          // domain installation_id deliberately carry this same value; the
          // pair response is checked before the connection is stored.
          'installation_id': installationId,
          'device_id': installationId,
        },
      });
    }
    return jsonEncode({
      'format': _domainBindingFormat,
      'binding': {
        'core_instance_id': connection.coreNodeId,
        'principal_id': grant.principalId,
        'installation_id': installationId,
      },
    });
  }

  @override
  Future<DomainGrantImportResult> importGrant(String envelopeJson) async {
    final grant = _parseGrantEnvelope(envelopeJson);
    final connection = await readConnection();
    if (connection == null) {
      throw const CoreDomainWorkflowFailure(
          'chat_pair_required', '请先连接这台设备与核心');
    }
    final installationId = await readInstallationId();
    if (grant.coreInstanceId != connection.coreNodeId ||
        grant.installationId != installationId ||
        grant.token == connection.deviceToken) {
      throw const CoreDomainWorkflowFailure(
          'grant_binding_mismatch', '授权不属于当前核心或当前安装实例');
    }
    final capture = await ownership.workflowState();
    final previous = connection.domainAccess;
    final unchanged = previous != null &&
        canonicalJson(previous.toJson()) == canonicalJson(grant.toJson());
    if (!unchanged && capture.frozenManifest != null) {
      throw const CoreDomainWorkflowFailure(
          'capture_migration_frozen', '捕获迁移已冻结，请先完成或中止迁移');
    }
    if (previous != null && !unchanged) {
      if (grant.coreInstanceId != previous.coreInstanceId ||
          grant.principalId != previous.principalId ||
          grant.installationId != previous.installationId ||
          grant.credentialGeneration <= previous.credentialGeneration) {
        throw const CoreDomainWorkflowFailure(
            'grant_rotation_invalid', '轮换授权必须保持主体绑定并提高凭据代次');
      }
    }
    if (!unchanged) {
      await replaceDomainAccess(connection, grant);
    }
    await _reloadAfterCredentialChange();
    return DomainGrantImportResult(
      rotated: previous != null && !unchanged,
      routeBindingBlocked: await _hasCoreRouteBindingMismatch(grant),
    );
  }

  @override
  Future<void> revokeGrant() async {
    final connection = await readConnection();
    if (connection == null) {
      throw const CoreDomainWorkflowFailure(
          'chat_pair_required', '当前没有可撤销的核心连接');
    }
    if (connection.domainAccess != null) {
      await replaceDomainAccess(connection, null);
    }
    await _reloadAfterCredentialChange();
  }

  @override
  Future<String> freezeCaptureMigration() async {
    final access = await _requireCaptureMigrationAccess();
    final feed = await readLegacyFeedConfig();
    if (feed == null) {
      throw const CoreDomainWorkflowFailure(
          'legacy_source_required', '请先连接并同步 Web 记录来源');
    }
    final manifest = await ownership.freezeCaptureMigration(
      store: access.captureStore!,
      migrationId: _createMigrationId(),
      sourceInstanceId: _sourceInstanceId(feed.baseUrl),
      sourceCursor: feed.cursor,
    );
    return _manifestEnvelope(manifest);
  }

  @override
  Future<String> exportFrozenCaptureManifest() async {
    final state = await ownership.workflowState();
    final manifest = state.frozenManifest;
    if (state.owner != 'legacy' || manifest == null) {
      throw const CoreDomainWorkflowFailure(
          'capture_migration_not_frozen', '当前没有已冻结的捕获迁移清单');
    }
    return _manifestEnvelope(manifest);
  }

  @override
  Future<void> commitCaptureMigration(String envelopeJson) async {
    final proof = _parseProofEnvelope(envelopeJson);
    final access = await _requireCaptureMigrationAccess();
    await ownership.commitCaptureMigration(
      store: access.captureStore!,
      adoptionProof: proof,
      refetchCurrentReceipt: access.captureAdoptionReceiptRefetch!,
    );
    try {
      await reloadRuntime();
    } catch (_) {
      throw const CoreDomainWorkflowFailure(
          'runtime_reload_failed', '接管已原子提交，但运行时重建失败；领域访问保持停止，请重新打开本页重试');
    }
  }

  @override
  Future<void> abortCaptureMigration() async {
    final state = await ownership.workflowState();
    final manifest = state.frozenManifest;
    if (manifest == null) {
      throw const CoreDomainWorkflowFailure(
          'capture_migration_not_frozen', '当前没有已冻结的捕获迁移');
    }
    await ownership.abortCaptureMigration(manifest.migrationId);
  }

  Future<ConfiguredDomainAccess> _requireCaptureMigrationAccess() async {
    final access = await (_loadAccess ?? _attachCurrentAccess).call();
    if (access?.captureStore == null ||
        access?.captureAdoptionVerifier == null ||
        access?.captureAdoptionReceiptRefetch == null) {
      throw const CoreDomainWorkflowFailure(
          'capture_owner_grant_required', '当前授权不包含捕获读取、接管与所有者权限');
    }
    ownership.configureAdoptionVerifier(access!.captureAdoptionVerifier);
    return access;
  }

  Future<void> _reloadAfterCredentialChange() async {
    try {
      await reloadRuntime();
    } catch (_) {
      throw const CoreDomainWorkflowFailure(
          'runtime_reload_failed', '安全凭据已更新，但运行时重建失败；领域访问保持停止，请重新导入或撤销以重试');
    }
  }

  Future<ConfiguredDomainAccess?> _attachCurrentAccess() async {
    final connection = await readConnection();
    if (connection == null) return null;
    return attachConfiguredDomainAccess(
      hub: hub,
      connection: connection,
      installationId: await readInstallationId(),
      currentConnection: readConnection,
    );
  }

  Future<bool> _hasCoreRouteBindingMismatch(CoreDomainAccessGrant grant) async {
    final binding = DomainBinding(
      coreInstanceId: grant.coreInstanceId,
      principalId: grant.principalId,
      generation: grant.credentialGeneration,
      installationId: grant.installationId,
      policyVersion: grant.policyVersion,
      schemaVersion: grant.schemaVersion,
    );
    final store = DomainStore(db, binding: binding);
    final state = await store.read();
    final domains = state['domains'];
    if (domains is! Map) return false;
    for (final entry in domains.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final domain = jsonObject(entry.value);
      if (domain['route'] == 'core' &&
          canonicalJson(domain['binding']) !=
              canonicalJson(binding.forDomain(entry.key as String))) {
        return true;
      }
    }
    return false;
  }

  CoreDomainAccessGrant _parseGrantEnvelope(String source) {
    try {
      if (source.length > 256 * 1024) throw const FormatException();
      final envelope = jsonObject(jsonDecode(source));
      _exact(envelope, const {'format', 'domain_access'});
      if (envelope['format'] != _grantFormat) throw const FormatException();
      final raw = jsonObject(envelope['domain_access']);
      _exact(raw, _grantKeys);
      final authorization = jsonObject(raw['authorization']);
      _exact(authorization, const {'scheme', 'key_id', 'secret'});
      return CoreDomainAccessGrant.fromJson(raw);
    } catch (_) {
      throw const CoreDomainWorkflowFailure(
          'grant_file_invalid', '领域授权文件无效或版本不受支持');
    }
  }

  Json _parseProofEnvelope(String source) {
    try {
      if (source.length > 8 * 1024 * 1024) throw const FormatException();
      final envelope = jsonObject(jsonDecode(source));
      _exact(envelope, const {'format', 'proof'});
      if (envelope['format'] != _proofFormat) throw const FormatException();
      return copyJson(jsonObject(envelope['proof']));
    } catch (_) {
      throw const CoreDomainWorkflowFailure(
          'proof_file_invalid', '核心接管证明无效或版本不受支持');
    }
  }

  static void _exact(Json value, Set<String> keys) {
    if (value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty) {
      throw const FormatException();
    }
  }

  static String _sourceInstanceId(String baseUrl) =>
      'claude-web-${sha256.convert(utf8.encode(baseUrl)).toString().substring(0, 32)}';

  static String _manifestEnvelope(CaptureMigrationManifest manifest) =>
      jsonEncode({
        'format': _manifestFormat,
        'manifest': manifest.value,
      });
}
