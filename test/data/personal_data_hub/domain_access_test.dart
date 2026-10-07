import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/capture_consumer_ownership.dart';
import 'package:memex/data/personal_data_hub/domain_access.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/domain_store.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';
import 'package:memex/db/app_database.dart';

const secret = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
const captureScopes = [
  'captures:read',
  'captures:create',
  'captures:patch',
  'captures:delete',
  'captures:ack',
];

CoreDomainAccessGrant grant({
  String core = 'core-phone-ui-synthetic',
  String principal = 'phone-ui',
  int generation = 1,
  String installation = 'phone-install',
  List<String> scopes = const [
    'captures:read',
    'captures:create',
    'captures:patch',
    'captures:delete',
    'captures:ack',
    'plan_items:read',
    'plan_items:status',
    'plan_items:ack',
    'plan_days:read',
    'plan_days:ack',
    'plan_weeks:read',
    'plan_weeks:ack',
  ],
}) =>
    CoreDomainAccessGrant(
      protocolVersion: 1,
      coreInstanceId: core,
      principalId: principal,
      credentialGeneration: generation,
      installationId: installation,
      policyVersion: DomainPolicy.version,
      schemaVersion: 1,
      token: 'independent-domain-bearer',
      scopes: scopes,
      authorization: const CoreDomainAuthorizationGrant(
        scheme: 'hmac-sha256-v1',
        keyId: 'synthetic-key',
        secret: secret,
      ),
    );

Json vectorIntent() => {
      'domain_protocol_version': 1,
      'core_instance_id': 'core-phone-ui-synthetic',
      'schema_version': 1,
      'op_id': '00000000-0000-4000-8000-000000000001',
      'id': '00000000-0000-4000-8000-000000000002',
      'kind': 'create',
      'actor': 'user_direct',
      'base_revision': 0,
      'created_at': '2026-10-07T00:00:00.000Z',
      'expires_at': '2026-12-06T00:00:00.000Z',
      'data': {
        'text': '合成点击发送 🌧️',
        'source': 'phone_quick',
        'recorded_at': '2026-10-07T00:00:00.000Z',
      },
      'provenance': {
        'source': 'phone_quick',
        'source_refs': <dynamic>[],
        'import_batch_id': null,
      },
    };

Json vectorRequest() {
  final intent = vectorIntent();
  return {
    'action_id': 'local-audit-only',
    'domain': 'captures',
    'capture_id': intent['id'],
    'action': 'create',
    'actor': 'user_direct',
    'surface': 'quick_capture_send',
    'text_sha256': sha256
        .convert(utf8.encode(intent['data']['text'] as String))
        .toString(),
    'occurred_at': '2026-10-07T00:00:00.000Z',
    'binding': const DomainBinding(
      coreInstanceId: 'core-phone-ui-synthetic',
      principalId: 'phone-ui',
      generation: 1,
      installationId: 'phone-install',
    ).forDomain('captures'),
    'intent': intent,
  };
}

CoreSyncConnection connection(CoreDomainAccessGrant? access) =>
    CoreSyncConnection(
      baseUrl: 'https://core.example.invalid',
      deviceToken: 'chat-only-token',
      initialCursor: 'chat-cursor',
      coreNodeId: 'core-phone-ui-synthetic',
      domainAccess: access,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('full final intent signature matches the Core fixed vector', () async {
    final signer = DomainUiAuthorizationSigner(grant());
    expect(
      await signer.issue(vectorRequest()),
      'uia1.synthetic-key.jpAvn1guJxBC_3-rXcOIb1YwMecIm3twHYiGh0t1Cmo',
    );
    final changed = vectorRequest();
    changed['intent']['base_revision'] = 1;
    expect(
        await signer.issue(changed),
        isNot(endsWith(
          'jpAvn1guJxBC_3-rXcOIb1YwMecIm3twHYiGh0t1Cmo',
        )));
    final signed = vectorRequest();
    signed['intent']['authorization_ref'] = 'forged';
    await expectLater(
      signer.issue(signed),
      throwsA(isA<DomainFailure>()),
    );
  });

  test('plan status signer binds the item, status and final intent', () async {
    final signer = DomainUiAuthorizationSigner(grant());
    final intent = <String, dynamic>{
      'domain_protocol_version': 1,
      'core_instance_id': 'core-phone-ui-synthetic',
      'schema_version': 1,
      'op_id': '00000000-0000-4000-8000-000000000003',
      'id': 'plan-item-1',
      'kind': 'status',
      'actor': 'user_direct',
      'base_revision': 4,
      'created_at': '2026-10-07T00:00:00.000Z',
      'expires_at': '2026-12-06T00:00:00.000Z',
      'patch': {'status': '完成'},
    };
    final request = <String, dynamic>{
      'domain': 'plan_items',
      'item_id': 'plan-item-1',
      'action': 'status',
      'actor': 'user_direct',
      'surface': 'planning_status',
      'status': '完成',
      'binding': const DomainBinding(
        coreInstanceId: 'core-phone-ui-synthetic',
        principalId: 'phone-ui',
        generation: 1,
        installationId: 'phone-install',
      ).forDomain('plan_items'),
      'intent': intent,
    };
    expect(await signer.issue(request), startsWith('uia1.synthetic-key.'));
    request['status'] = '放弃';
    await expectLater(signer.issue(request), throwsA(isA<DomainFailure>()));
    request['status'] = '完成';
    intent['patch'] = {'status': '待办'};
    await expectLater(signer.issue(request), throwsA(isA<DomainFailure>()));
  });

  test(
      'optional grant attaches real transport without switching route or owner',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final hub = PersonalDataHub.forDatabase(db);
    final configured = await attachConfiguredDomainAccess(
      hub: hub,
      connection: connection(grant()),
      installationId: 'phone-install',
    );
    expect(configured, isNotNull);
    expect(hub.storeFor('captures'), same(configured!.captureStore));
    expect(
      configured.captureStore!
          .domain(await configured.captureStore!.read(), 'captures')['route'],
      'phone',
    );
    expect(configured.authorizeCapture, isNotNull);
    expect(configured.authorizePlanning, isNotNull);
    expect(hub.storeFor('plan_items'), isNotNull);
    expect(hub.storeFor('plan_days'), isNotNull);
    expect(hub.storeFor('plan_weeks'), isNotNull);
    expect(
      await CaptureConsumerOwnership.forDatabase(db).coreSelected(),
      isFalse,
    );
  });

  test('old or incomplete grants stay phone-local and do not attach', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final hub = PersonalDataHub.forDatabase(db);
    expect(
      await attachConfiguredDomainAccess(
        hub: hub,
        connection: connection(null),
        installationId: 'phone-install',
      ),
      isNull,
    );
    expect(
      await attachConfiguredDomainAccess(
        hub: hub,
        connection: connection(grant(scopes: const ['captures:read'])),
        installationId: 'phone-install',
      ),
      isNull,
    );
    expect(hub.storeFor('captures'), isNull);
  });

  test('planning read scopes attach without opening status writes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final hub = PersonalDataHub.forDatabase(db);
    final configured = await attachConfiguredDomainAccess(
      hub: hub,
      connection: connection(grant(scopes: const [
        'plan_items:read',
        'plan_items:ack',
        'plan_days:read',
        'plan_days:ack',
        'plan_weeks:read',
        'plan_weeks:ack',
      ])),
      installationId: 'phone-install',
    );
    expect(configured, isNotNull);
    expect(configured!.authorizePlanning, isNull);
    expect(configured.authorizeCapture, isNull);
    expect(hub.storeFor('plan_items'), isNotNull);
    expect(hub.storeFor('captures'), isNull);
  });

  test('a different persisted Core route is never silently retargeted',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final old = DomainStore(
      db,
      binding: const DomainBinding(
        coreInstanceId: 'old-core',
        principalId: 'old-phone',
        generation: 1,
        installationId: 'phone-install',
      ),
    );
    await old.configureRoute('captures', DomainRoute.core);
    final hub = PersonalDataHub.forDatabase(db);
    expect(
      await attachConfiguredDomainAccess(
        hub: hub,
        connection: connection(grant(scopes: captureScopes)),
        installationId: 'phone-install',
      ),
      isNull,
    );
    expect(hub.storeFor('captures'), isNull);
  });

  test('grant for another installation is ignored', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final hub = PersonalDataHub.forDatabase(db);
    expect(
      await attachConfiguredDomainAccess(
        hub: hub,
        connection: connection(grant()),
        installationId: 'restored-installation',
      ),
      isNull,
    );
    expect(hub.storeFor('captures'), isNull);
  });

  test('new phone binding preserves existing phone-local captures', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final oldStore = DomainStore(
      db,
      binding: const DomainBinding(
        coreInstanceId: 'phone-local',
        principalId: 'phone-local',
        generation: 0,
        installationId: 'phone-install',
      ),
    );
    await oldStore.enqueue(
      'captures',
      id: 'local-capture',
      kind: 'create',
      actor: 'user_direct',
      authorizationRef: 'local-ui:test',
      fields: {
        'data': {
          'text': '本机保留',
          'source': 'phone_quick',
          'recorded_at': '2026-10-07T00:00:00.000Z',
        },
        'provenance': {
          'source': 'phone_quick',
          'source_refs': <dynamic>[],
          'import_batch_id': null,
        },
      },
    );
    final hub = PersonalDataHub.forDatabase(db);
    final configured = await attachConfiguredDomainAccess(
      hub: hub,
      connection: connection(grant()),
      installationId: 'phone-install',
    );
    expect(configured, isNotNull);
    expect(
      (await configured!.captureStore!.visible('captures')).single['data']
          ['text'],
      '本机保留',
    );
    expect(
      configured.captureStore!
          .domain(await configured.captureStore!.read(), 'captures')['route'],
      'phone',
    );
  });

  test('clear or rotation rejects every later signature and request', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final hub = PersonalDataHub.forDatabase(db);
    CoreSyncConnection? active = connection(grant(scopes: captureScopes));
    final configured = await attachConfiguredDomainAccess(
      hub: hub,
      connection: active,
      installationId: 'phone-install',
      currentConnection: () async => active,
    );
    expect(await configured!.authorizeCapture!(vectorRequest()),
        startsWith('uia1.synthetic-key.'));

    active = connection(grant(generation: 2, scopes: captureScopes));
    await expectLater(
      configured.authorizeCapture!(vectorRequest()),
      throwsA(
        isA<DomainFailure>()
            .having((failure) => failure.code, 'code', 'binding_changed'),
      ),
    );
    await configured.captureStore!.configureRoute('captures', DomainRoute.core);
    await expectLater(
      hub.syncOnce('captures'),
      throwsA(
        isA<DomainFailure>()
            .having((failure) => failure.code, 'code', 'binding_changed'),
      ),
    );

    active = null;
    await expectLater(
      configured.authorizeCapture!(vectorRequest()),
      throwsA(
        isA<DomainFailure>()
            .having((failure) => failure.code, 'code', 'binding_changed'),
      ),
    );
    await expectLater(
      hub.syncOnce('captures'),
      throwsA(
        isA<DomainFailure>()
            .having((failure) => failure.code, 'code', 'binding_changed'),
      ),
    );
  });
}
