import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/personal_data_hub/domain_protocol.dart';
import 'package:memex/data/personal_data_hub/food_connection.dart';
import 'package:memex/data/personal_data_hub/food_service.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/data/services/sync/core_sync_connection_store.dart';
import 'package:memex/db/app_database.dart';

const _connection = CoreSyncConnection(
  baseUrl: 'https://synthetic-core.example',
  deviceToken: 'synthetic-device-token',
  initialCursor: 'chat-cursor',
  coreNodeId: 'synthetic-core',
);

FoodCredential _credential(int generation, {String core = 'synthetic-core'}) =>
    FoodCredential(
      token: 'synthetic-food-token-${'x' * 24}-$generation',
      generation: generation,
      principalId: foodPhonePrincipalId,
      coreInstanceId: core,
      baseUrl: _connection.baseUrl,
    );

class _Transport implements DomainTransport {
  _Transport({this.failure});
  final String? failure;
  int changesCalls = 0;

  @override
  Future<Json> changes(String domain, String? cursor) async {
    changesCalls++;
    if (failure != null) throw DomainFailure(failure!);
    return {
      'next_cursor': 'food-cursor-$changesCalls',
      'policy_version': DomainPolicy.version,
      'records': <dynamic>[],
    };
  }

  @override
  Future<void> acknowledge(String domain, String cursor,
      {String? snapshotId}) async {}

  @override
  Future<Json> operation(String domain, String opId) =>
      throw const DomainFailure('unexpected_operation');

  @override
  Future<Json> snapshot(String domain,
          {String? snapshotToken, String? pageToken}) =>
      throw const DomainFailure('unexpected_snapshot');

  @override
  Future<Json> submit(String domain, Json intent) =>
      throw const DomainFailure('unexpected_submit');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late PersonalDataHub hub;
  late FoodCredentialStore credentialStore;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    credentialStore = FoodCredentialStore();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    hub = PersonalDataHub.forDatabase(db);
  });

  tearDown(() => db.close());

  FoodConnector connector({
    Future<CoreSyncConnection?> Function()? readConnection,
    FoodClaim? claim,
    DomainTransport Function(String, String, DomainBinding)? createTransport,
  }) =>
      FoodConnector(
        credentialStore: credentialStore,
        readConnection: readConnection ?? () async => _connection,
        claim: claim ?? (_) async => _credential(1),
        readInstallationId: () async => 'synthetic-installation',
        createTransport: createTransport ?? (_, __, ___) => _Transport(),
      );

  test('without chat connection does not claim or attach', () async {
    var claims = 0;
    final subject = connector(
      readConnection: () async => null,
      claim: (_) async {
        claims++;
        return _credential(1);
      },
    );
    await subject.ensureAttached(hub);
    expect(claims, 0);
    expect(hub.storeFor(foodDomainName), isNull);
    expect(subject.status.screenMessage, '尚未连接林埃核心');
  });

  test(
      'claim attaches core route, syncs, and repeated ensure keeps the replica',
      () async {
    var claims = 0;
    final transport = _Transport();
    final subject = connector(
      claim: (_) async => _credential(++claims),
      createTransport: (_, __, ___) => transport,
    );
    await subject.ensureAttached(hub);
    final attached = hub.storeFor(foodDomainName);
    expect(attached, isNotNull);
    expect(
        (await attached!.read())['domains'][foodDomainName]['route'], 'core');
    await hub.syncOnce(foodDomainName);
    expect(
        (await FoodService(store: attached).read(DateTime(2026, 10, 25))).error,
        isNull);
    await subject.ensureAttached(hub);
    expect(hub.storeFor(foodDomainName), same(attached));
    expect(claims, 1);
  });

  test('credential for another core is rejected before save or attach',
      () async {
    final subject =
        connector(claim: (_) async => _credential(1, core: 'wrong'));
    await subject.ensureAttached(hub);
    expect(await credentialStore.read(), isNull);
    expect(hub.storeFor(foodDomainName), isNull);
    expect(subject.status.phase, FoodConnectionPhase.failed);
  });

  test('unauthenticated sync clears and reclaims only once per process',
      () async {
    var claims = 0;
    var transports = 0;
    final subject = connector(
      claim: (_) async => _credential(++claims),
      createTransport: (_, __, ___) {
        transports++;
        return _Transport(failure: 'unauthenticated');
      },
    );
    await subject.ensureAttached(hub);
    await expectLater(
        hub.syncOnce(foodDomainName), throwsA(isA<DomainFailure>()));
    await subject.handleSyncResult(hub);
    expect(claims, 2);
    expect(transports, 2);
    await subject.handleSyncResult(hub);
    expect(claims, 2);
  });

  test('not provisioned is visible and disconnect clears credential and attach',
      () async {
    final blocked = connector(
      claim: (_) async =>
          throw const FoodConnectionException('food_not_provisioned'),
    );
    await blocked.ensureAttached(hub);
    expect(blocked.status.screenMessage, '电脑端尚未开通饮食同步');
    expect(hub.storeFor(foodDomainName), isNull);

    final connected = connector();
    await connected.ensureAttached(hub);
    expect(hub.storeFor(foodDomainName), isNotNull);
    await connected.disconnect(hub);
    expect(await credentialStore.read(), isNull);
    expect(hub.storeFor(foodDomainName), isNull);
    expect(connected.status.screenMessage, '尚未连接林埃核心');
  });
}
