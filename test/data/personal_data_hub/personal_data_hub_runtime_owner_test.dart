import 'dart:async';
import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub_runtime_owner.dart';
import 'package:memex/data/personal_data_hub/planning_reminders.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/widgets/personal_data_hub_runtime_scope.dart';
import 'package:memex/utils/result.dart';

class _NoAlarms implements PlanningAlarmScheduler {
  @override
  Future<void> cancel(String id) async {}
  @override
  Future<void> schedule(String id, DateTime at) async {}
}

// Widget publication does not require SQLite; real connection lifecycle is
// covered by the service tests below, outside Flutter's simulated clock.
class _ScopeRuntime implements PersonalDataHubRuntime {
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onDispose, required this.child});
  final VoidCallback onDispose;
  final Widget child;
  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final databases = <AppDatabase>[];
  final owners = <PersonalDataHubRuntimeOwner>[];
  final runtimes = <PersonalDataHubRuntime>[];
  final now = DateTime.utc(2026, 10, 5);
  AppDatabase database() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    databases.add(db);
    return db;
  }

  Future<PersonalDataHubRuntime> runtime(AppDatabase db) async {
    final value = await PersonalDataHubRuntime.create(
        db: db, alarms: _NoAlarms(), clock: () => now);
    await value.refresh(consume: false);
    runtimes.add(value);
    return value;
  }

  PersonalDataHubRuntimeOwner owner(
      Future<PersonalDataHubRuntime> Function() create) {
    final value = PersonalDataHubRuntimeOwner(create: create);
    owners.add(value);
    return value;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(
        {DeviceIdentityService.preferenceKey: 'synthetic-owner-install'});
    DeviceIdentityService.resetForTesting();
  });
  tearDown(() async {
    for (final value in owners.reversed) {
      await value.suspend();
      value.dispose();
    }
    for (final value in runtimes) {
      await value.dispose();
    }
    for (final db in databases) {
      await db.close();
    }
    await AppDatabase.closeCurrent();
    AppDatabase.setDatabaseFactoryForTesting(null);
    owners.clear();
    runtimes.clear();
    databases.clear();
  });

  test('same-process database replacement releases old runtime before close',
      () async {
    var activeDb = database();
    final firstDb = activeDb;
    final host = owner(() => runtime(activeDb));
    final first = (await host.future).valueOrThrow;
    await first.quickCaptureService
        .send(first.quickCaptureService.newDraft('old synthetic capture'));
    await host.suspend();
    await host.suspend();
    expect(() => first.read(now), throwsStateError);
    await firstDb.close();
    activeDb = database();
    await host.reload();
    final second = (await host.future).valueOrThrow;
    expect(identical(second.db, activeDb), isTrue);
    expect(await second.recent(), isEmpty);
    final receipt = await second.quickCaptureService
        .send(second.quickCaptureService.newDraft('new synthetic capture'));
    expect(receipt.deliveryMessage, contains('本机'));
    expect((await second.recent()).single.text, 'new synthetic capture');
    expect((await second.phoneStore.read())['outbox'], isEmpty);
  });

  test('suspend invalidates pending creation and awaits its eventual disposal',
      () async {
    final pending = Completer<PersonalDataHubRuntime>();
    final host = owner(() => pending.future);
    final obsolete = host.future;
    var detached = false;
    final stopping = host.suspend().then((_) => detached = true);
    await Future<void>.delayed(Duration.zero);
    expect(detached, isFalse);
    expect(await host.future, isA<Error<PersonalDataHubRuntime>>());
    final lateRuntime = await runtime(database());
    pending.complete(lateRuntime);
    await stopping;
    expect(await obsolete, isA<Error<PersonalDataHubRuntime>>());
    expect(() => lateRuntime.read(now), throwsStateError);
  });

  test('dispose releases a late factory result without publishing or leaking',
      () async {
    final pending = Completer<PersonalDataHubRuntime>();
    final host = owner(() => pending.future);
    final obsolete = host.future;
    host.dispose();
    expect(PersonalDataHubRuntimeOwner.current, isNull);
    final lateRuntime = await runtime(database());
    pending.complete(lateRuntime);
    expect(await obsolete, isA<Error<PersonalDataHubRuntime>>());
    await host.suspend();
    expect(() => lateRuntime.read(now), throwsStateError);
  });

  test(
      'concurrent reloads coalesce and repeated resets retain one live runtime',
      () async {
    var calls = 0;
    final db = database();
    final host = owner(() {
      calls++;
      return runtime(db);
    });
    final first = (await host.future).valueOrThrow;
    await Future.wait([host.reload(), host.reload(), host.reload()]);
    expect(calls, 2);
    expect(() => first.read(now), throwsStateError);
    final second = (await host.future).valueOrThrow;
    await host.suspend();
    await host.suspend();
    await Future.wait([host.reload(), host.reload()]);
    expect(calls, 3);
    expect(() => second.read(now), throwsStateError);
    expect((await (await host.future).valueOrThrow.read(now)).items, isEmpty);
  });

  test('a newer suspend wins over reload awaiting an obsolete factory',
      () async {
    final pending = Completer<PersonalDataHubRuntime>();
    var calls = 0;
    final host = owner(() {
      calls++;
      return pending.future;
    });
    final reloading = host.reload();
    final stopping = host.suspend();
    final lateRuntime = await runtime(database());
    pending.complete(lateRuntime);
    await Future.wait([reloading, stopping]);
    expect(calls, 1);
    expect(await host.future, isA<Error<PersonalDataHubRuntime>>());
    expect(() => lateRuntime.read(now), throwsStateError);
  });

  test('creation error remains explicit and a later reload can recover',
      () async {
    var fail = true;
    final db = database();
    final host = owner(() async {
      if (fail) throw StateError('synthetic unavailable database');
      return runtime(db);
    });
    expect(await host.future, isA<Error<PersonalDataHubRuntime>>());
    fail = false;
    await host.reload();
    expect(await host.future, isA<Ok<PersonalDataHubRuntime>>());
  });

  test('singleton same-user init after suspend and close creates a writable DB',
      () async {
    var opens = 0;
    AppDatabase.setDatabaseFactoryForTesting((id) {
      expect(id, 'synthetic-same-user');
      opens++;
      return database();
    });
    Future<PersonalDataHubRuntime> create() async {
      await AppDatabase.init('synthetic-same-user');
      return runtime(AppDatabase.instance);
    }

    final host = owner(create);
    final first = (await host.future).valueOrThrow;
    await AppDatabase.init('synthetic-same-user');
    expect(opens, 1);
    await host.suspend();
    await AppDatabase.closeCurrent();
    expect(AppDatabase.isInitialized, isFalse);
    expect(AppDatabase.activeUserId, isNull);
    await host.reload();
    final second = (await host.future).valueOrThrow;
    expect(opens, 2);
    expect(identical(first.db, second.db), isFalse);
    expect(() => first.read(now), throwsStateError);
    await second.quickCaptureService
        .send(second.quickCaptureService.newDraft('after same-user reset'));
    expect((await second.recent()).single.text, 'after same-user reset');
  });

  test(
      'closeCurrent waits for a pending singleton open and repeated close is safe',
      () async {
    final opening = Completer<void>();
    var opens = 0;
    AppDatabase.setDatabaseFactoryForTesting((_) {
      opens++;
      final db = AppDatabase.forTesting(LazyDatabase(() async {
        await opening.future;
        return NativeDatabase.memory();
      }));
      databases.add(db);
      return db;
    });
    final initializing = AppDatabase.init('synthetic-pending-user');
    var closed = false;
    final closing = AppDatabase.closeCurrent().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    opening.complete();
    await Future.wait([initializing, closing]);
    expect(AppDatabase.isInitialized, isFalse);
    await Future.wait([AppDatabase.closeCurrent(), AppDatabase.closeCurrent()]);
    await AppDatabase.init('synthetic-pending-user');
    expect(opens, 2);
    expect(AppDatabase.activeUserId, 'synthetic-pending-user');
  });

  testWidgets('scope clears old Ok while a replacement is still loading',
      (tester) async {
    final first = _ScopeRuntime(), second = _ScopeRuntime();
    final pending = Completer<PersonalDataHubRuntime>();
    final entered = Completer<void>();
    var calls = 0;
    var childDisposals = 0;
    final host = owner(() {
      if (++calls == 1) return Future.value(first);
      entered.complete();
      return pending.future;
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: host,
      child: PersonalDataHubRuntimeScope(
        child: _MountProbe(
          onDispose: () => childDisposals++,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(builder: (context) {
              final result = context.watch<Result<PersonalDataHubRuntime>?>();
              return Text(switch (result) {
                Ok(:final value) => identical(value, first) ? 'old' : 'new',
                Error() => 'suspended',
                null => 'loading',
              });
            }),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('old'), findsOneWidget);
    final reloading = host.reload();
    await tester.pump();
    await entered.future;
    await tester.pump();
    try {
      expect(find.text('old'), findsNothing);
      expect(find.text('loading'), findsOneWidget);
      expect(childDisposals, 0);
    } finally {
      pending.complete(second);
    }
    await tester.pump();
    await reloading;
    await tester.pump();
    expect(find.text('new'), findsOneWidget);
    // Release while the widget fake clock can still flush async cleanup.
    final stopped = host.suspend();
    await tester.pump();
    await stopped;
    expect(childDisposals, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(childDisposals, 1);
    host.dispose();
    owners.remove(host);
  });
}
