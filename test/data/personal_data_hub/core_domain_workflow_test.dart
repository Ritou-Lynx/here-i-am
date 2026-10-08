import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';
import 'package:memex/data/personal_data_hub/core_domain_workflow.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

const _secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

CoreDomainAccessGrant _grant({
  int generation = 1,
  String core = 'core-workflow',
  String installation = 'phone-install',
}) =>
    CoreDomainAccessGrant(
      protocolVersion: 1,
      coreInstanceId: core,
      principalId: 'phone-owner',
      credentialGeneration: generation,
      installationId: installation,
      policyVersion: DomainPolicy.version,
      schemaVersion: 1,
      token: 'domain-bearer-$generation',
      scopes: const [
        'captures:read',
        'captures:ack',
        'captures:adopt',
        'captures:owner',
      ],
      authorization: CoreDomainAuthorizationGrant(
        scheme: 'hmac-sha256-v1',
        keyId: 'owner-key-$generation',
        secret: _secret,
      ),
    );

CoreSyncConnection _connection(CoreDomainAccessGrant? grant) =>
    CoreSyncConnection(
      baseUrl: 'https://core.example.invalid',
      deviceToken: 'chat-only-token',
      initialCursor: 'chat-cursor',
      coreNodeId: 'core-workflow',
      domainAccess: grant,
    );

String _envelope(CoreDomainAccessGrant grant) => jsonEncode({
      'format': 'i-core-domain-access-export-v1',
      'domain_access': grant.toJson(),
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late CoreSyncConnection connection;
  late int reloads;
  late CoreDomainWorkflowService workflow;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connection = _connection(null);
    reloads = 0;
    workflow = CoreDomainWorkflowService(
      db: db,
      hub: PersonalDataHub.forDatabase(db),
      ownership: CaptureConsumerOwnership(db),
      readConnection: () async => connection,
      replaceDomainAccess: (expected, next) async {
        expect(identical(expected, connection), isTrue);
        connection = CoreSyncConnection(
          baseUrl: connection.baseUrl,
          deviceToken: connection.deviceToken,
          initialCursor: connection.initialCursor,
          coreNodeId: connection.coreNodeId,
          domainAccess: next,
        );
      },
      readInstallationId: () async => 'phone-install',
      reloadRuntime: () async => reloads++,
      readLegacyFeedConfig: () async => null,
    );
  });

  tearDown(() => db.close());

  test('exact protected grant envelope imports, rotates and revokes separately',
      () async {
    final installationBinding =
        jsonDecode(await workflow.exportGrantBinding()) as Map<String, dynamic>;
    expect(installationBinding, {
      'format': 'i-core-phone-installation-binding-v1',
      'binding': {
        'core_instance_id': 'core-workflow',
        'installation_id': 'phone-install',
        'device_id': 'phone-install',
      },
    });
    final first = await workflow.importGrant(_envelope(_grant()));
    expect(first.rotated, isFalse);
    expect(first.routeBindingBlocked, isFalse);
    expect(connection.deviceToken, 'chat-only-token');
    expect(connection.domainAccess!.credentialGeneration, 1);
    expect(reloads, 1);

    final status = await workflow.readStatus();
    expect(status.grant!.principalId, 'phone-owner');
    expect(status.grant!.credentialGeneration, 1);
    expect(status.pairedCoreInstanceId, 'core-workflow');
    expect(status.installationId, 'phone-install');
    final binding =
        jsonDecode(await workflow.exportGrantBinding()) as Map<String, dynamic>;
    expect(binding, {
      'format': 'i-core-domain-access-binding-v1',
      'binding': {
        'core_instance_id': 'core-workflow',
        'principal_id': 'phone-owner',
        'installation_id': 'phone-install',
      },
    });
    expect(jsonEncode(binding), isNot(contains('chat-only-token')));
    expect(jsonEncode(binding), isNot(contains(_secret)));

    final second = await workflow.importGrant(_envelope(_grant(generation: 2)));
    expect(second.rotated, isTrue);
    expect(connection.domainAccess!.credentialGeneration, 2);
    expect(reloads, 2);

    await workflow.revokeGrant();
    expect(connection.domainAccess, isNull);
    expect(connection.deviceToken, 'chat-only-token');
    expect(reloads, 3);
  });

  test('raw, unknown and wrong-installation grants fail without replacement',
      () async {
    await expectLater(
      workflow.importGrant(jsonEncode(_grant().toJson())),
      throwsA(isA<CoreDomainWorkflowFailure>()
          .having((e) => e.code, 'code', 'grant_file_invalid')),
    );
    final unknown = jsonDecode(_envelope(_grant())) as Map<String, dynamic>
      ..['extra'] = true;
    await expectLater(
      workflow.importGrant(jsonEncode(unknown)),
      throwsA(isA<CoreDomainWorkflowFailure>()
          .having((e) => e.code, 'code', 'grant_file_invalid')),
    );
    await expectLater(
      workflow.importGrant(_envelope(_grant(installation: 'other-phone'))),
      throwsA(isA<CoreDomainWorkflowFailure>()
          .having((e) => e.code, 'code', 'grant_binding_mismatch')),
    );
    expect(connection.domainAccess, isNull);
    expect(reloads, 0);
  });

  test('rotation never silently retargets an existing core route', () async {
    final old = _grant();
    connection = _connection(old);
    final oldBinding = DomainBinding(
      coreInstanceId: old.coreInstanceId,
      principalId: old.principalId,
      generation: old.credentialGeneration,
      installationId: old.installationId,
    );
    final oldStore = DomainStore(db, binding: oldBinding);
    await oldStore.commitCoreMigration('captures', () async {});

    final result = await workflow.importGrant(_envelope(_grant(generation: 2)));
    expect(result.routeBindingBlocked, isTrue);
    final state = await oldStore.read();
    final captures = oldStore.domain(state, 'captures');
    expect(captures['route'], 'core');
    expect(canonicalJson(captures['binding']),
        canonicalJson(oldBinding.forDomain('captures')));
    expect(connection.domainAccess!.credentialGeneration, 2);
    expect(reloads, 1);
  });

  test('same grant import retries runtime rebuild after an earlier failure',
      () async {
    var attempts = 0;
    final retrying = CoreDomainWorkflowService(
      db: db,
      hub: PersonalDataHub.forDatabase(db),
      ownership: CaptureConsumerOwnership(db),
      readConnection: () async => connection,
      replaceDomainAccess: (expected, next) async {
        expect(identical(expected, connection), isTrue);
        connection = CoreSyncConnection(
          baseUrl: connection.baseUrl,
          deviceToken: connection.deviceToken,
          initialCursor: connection.initialCursor,
          coreNodeId: connection.coreNodeId,
          domainAccess: next,
        );
      },
      readInstallationId: () async => 'phone-install',
      reloadRuntime: () async {
        attempts++;
        if (attempts == 1) throw StateError('synthetic reload failure');
      },
      readLegacyFeedConfig: () async => null,
    );
    final source = _envelope(_grant());
    await expectLater(
      retrying.importGrant(source),
      throwsA(isA<CoreDomainWorkflowFailure>()
          .having((e) => e.code, 'code', 'runtime_reload_failed')),
    );
    expect(connection.domainAccess!.credentialGeneration, 1);
    await retrying.importGrant(source);
    expect(attempts, 2);
  });
}
