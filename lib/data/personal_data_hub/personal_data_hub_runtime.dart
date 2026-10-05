import 'dart:async';
import 'package:drift/drift.dart';
import 'package:memex/data/memory_v3/models/organized_record.dart';
import 'package:memex/data/memory_v3/services/record_organizer_service.dart';
import 'package:memex/data/services/device_identity_service.dart';
import 'package:memex/db/app_database.dart';
import 'capture_consumer.dart';
import 'capture_consumer_ownership.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';
import 'personal_data_hub.dart';
import 'planning_models.dart';
import 'planning_reminders.dart';
import 'planning_service.dart';
import 'quick_capture_domain_adapter.dart';
import 'quick_capture_models.dart';
import 'quick_capture_service.dart';

/// One app-owned adapter. The owner supplies configured model extraction and
/// trusted authorization issuers; neither credentials nor routes are invented.
/// Hub connection/sync and committed DB events drive refresh automatically.
/// Dispose before closing the injected database. No screen owns this lifetime.
class PersonalDataHubRuntime implements PlanningReader {
  PersonalDataHubRuntime._({
    required this.db,
    required this.hub,
    required this.phoneStore,
    required this.alarms,
    required this.clock,
    required this.enablePlanningReminders,
    required this.ownsCaptureConnectionLifetime,
    this.planningAuthorize,
    this.quickCaptureAuthorize,
    this.extract,
    this.connection,
  });

  static Future<PersonalDataHubRuntime> create({
    required AppDatabase db,
    required PlanningAlarmScheduler alarms,
    bool enablePlanningReminders = true,
    bool ownsCaptureConnectionLifetime = false,
    PersonalDataHub? hub,
    PlanningAuthorize? planningAuthorize,
    QuickCaptureAuthorizationIssuer? quickCaptureAuthorize,
    Future<OrganizedRecord> Function(String text)? extract,
    PlanningConnection Function()? connection,
    DateTime Function()? clock,
  }) async {
    final owner = hub ?? PersonalDataHub.forDatabase(db);
    if (!identical(owner.db, db)) {
      throw const DomainFailure('database_mismatch');
    }
    final installationId = await DeviceIdentityService.getOrCreate();
    final runtime = PersonalDataHubRuntime._(
      db: db,
      hub: owner,
      alarms: alarms,
      enablePlanningReminders: enablePlanningReminders,
      ownsCaptureConnectionLifetime: ownsCaptureConnectionLifetime,
      clock: clock ?? DateTime.now,
      planningAuthorize: planningAuthorize,
      quickCaptureAuthorize: quickCaptureAuthorize,
      extract: extract,
      connection: connection,
      phoneStore: DomainStore(db,
          binding: DomainBinding(
              coreInstanceId: 'phone-local',
              principalId: 'phone-local',
              generation: 0,
              installationId: installationId),
          clock: clock),
    );
    if (ownsCaptureConnectionLifetime) {
      CaptureConsumerOwnership.forDatabase(db).resume();
    }
    runtime._subscription = db
        .tableUpdates(const TableUpdateQuery.onTableName('kv_store'))
        .listen((_) => runtime._backgroundRefresh());
    runtime._hubSubscription = owner.changes.listen((event) {
      if (runtime._disposed) return;
      final update = event == PersonalDataHubChange.connections
          ? runtime.ownerConnectionsChanged()
          : runtime.refresh();
      unawaited(update.catchError((Object _) {}));
    });
    try {
      await runtime.refresh(consume: false);
    } catch (_) {
      // Keep the app entry available if OS reminder registration fails.
    }
    // Model work must not hold the app or speech entry open.
    unawaited(runtime.refresh().catchError((Object _) {}));
    return runtime;
  }

  final AppDatabase db;
  final PersonalDataHub hub;
  final DomainStore phoneStore;
  final PlanningAlarmScheduler alarms;

  /// Capture-only engines must never own or cancel the main engine's alarms.
  final bool enablePlanningReminders;
  final bool ownsCaptureConnectionLifetime;
  final DateTime Function() clock;
  final PlanningAuthorize? planningAuthorize;
  final QuickCaptureAuthorizationIssuer? quickCaptureAuthorize;
  final Future<OrganizedRecord> Function(String text)? extract;
  final PlanningConnection Function()? connection;
  final _events = StreamController<void>.broadcast();
  StreamSubscription<dynamic>? _subscription, _hubSubscription;
  PlanningReminders? _reminders;
  String? _reminderBinding;
  DomainStore? _consumerStore;
  CaptureConsumer? _consumer;
  Future<void>? _refreshing;
  bool _pending = false, _consumeRequested = false, _disposed = false;
  int _ownerEpoch = 0;
  Object? lastRefreshError;

  @override
  Stream<void> get changes => _events.stream;

  void _checkOpen() {
    if (_disposed) throw StateError('PersonalDataHubRuntime is disposed');
  }

  PlanningService _planning() {
    _checkOpen();
    final epoch = _ownerEpoch;
    return PlanningService(
      stores: {
        for (final name in planningDomains)
          if (hub.storeFor(name) case final store?) name: store,
      },
      authorize: planningAuthorize == null
          ? null
          : (database, action) async {
              if (epoch != _ownerEpoch) {
                throw const DomainFailure('binding_changed');
              }
              await planningAuthorize!(database, action);
              if (epoch != _ownerEpoch) {
                throw const DomainFailure('binding_changed');
              }
            },
      syncDomain: hub.syncOnce,
      connection: connection,
      clock: clock,
    );
  }

  @override
  Future<PlanningSnapshot> read(DateTime date) => _planning().read(date);

  @override
  Future<String> setStatus(String itemId, PlanningStatusAction action) async {
    final op = await _planning().setStatus(itemId, action);
    await refresh(consume: false);
    return op;
  }

  @override
  Future<void> synchronize() async {
    try {
      await _planning().synchronize();
    } finally {
      await refresh();
    }
  }

  /// Also callable by an external owner. Hub connection events call this
  /// automatically; old reminders are cleared before registering new ones.
  Future<void> ownerConnectionsChanged() {
    _checkOpen();
    _ownerEpoch++;
    return refresh();
  }

  DomainStore get _captureStore => hub.storeFor('captures') ?? phoneStore;

  QuickCaptureDomainAdapter _quick() {
    _checkOpen();
    final store = _captureStore;
    if (!identical(_consumerStore, store)) {
      _consumerStore = store;
      _consumer = extract == null
          ? null
          : CaptureConsumer(
              db: db,
              store: store,
              organizer: RecordOrganizerServiceV3(db),
              extract: (text) async {
                if (_disposed || !identical(store, _captureStore)) {
                  throw const DomainFailure('binding_changed');
                }
                final value = await extract!(text);
                if (_disposed || !identical(store, _captureStore)) {
                  throw const DomainFailure('binding_changed');
                }
                return value;
              },
              decodeText: (data) => data['text'] as String,
              inputVersion: (record) =>
                  record['field_meta']?['text']?['rev'] as int?,
            );
    }
    final epoch = _ownerEpoch;
    return QuickCaptureDomainAdapter(
      store: store,
      consumer: _consumer,
      issueAuthorization: quickCaptureAuthorize == null
          ? null
          : (evidence) async {
              if (epoch != _ownerEpoch || !identical(store, _captureStore)) {
                throw const DomainFailure('binding_changed');
              }
              final ref = await quickCaptureAuthorize!(evidence);
              if (epoch != _ownerEpoch || !identical(store, _captureStore)) {
                throw const DomainFailure('binding_changed');
              }
              return ref;
            },
    );
  }

  late final quickCaptureService = QuickCaptureService(submit: (draft) async {
    final adapter = _quick();
    final saved = await adapter.submit(draft);
    // The send receipt only waits for durable storage. Model processing runs
    // separately so the caller can immediately return to the previous app.
    unawaited(refresh().catchError((Object _) {}));
    return saved;
  });

  Future<List<QuickCaptureResult>> recent() => _quick().recent();

  void _backgroundRefresh() {
    if (_disposed) return;
    unawaited(refresh(consume: false).catchError((Object _) {}));
  }

  /// Serial, coalescing refresh. Explicit refresh/send may consume captures;
  /// committed DB notifications only reread views and reconcile reminders.
  /// This method never performs network sync or changes a domain route.
  Future<void> refresh({bool consume = true}) {
    _checkOpen();
    _pending = true;
    _consumeRequested |= consume;
    if (_refreshing case final active?) return active;
    final done = Completer<void>();
    _refreshing = done.future;
    unawaited(_drain(done));
    return done.future;
  }

  Future<void> _clearOwnedReminders() async {
    // A fresh/empty hub has never acquired reminder ownership. In particular,
    // a second capture engine must not scan and clear an installation prefix.
    if (_reminders == null) return;
    await _reminders!.reconcile(const []);
    _reminders = null;
    _reminderBinding = null;
  }

  Future<void> _reconcilePlanning(int epoch) async {
    if (!enablePlanningReminders) return;
    final store = hub.storeFor('plan_items');
    if (store == null) {
      await _clearOwnedReminders();
      return;
    }
    var ready = false;
    try {
      final domain = store.domain(await store.read(), 'plan_items');
      store.checkBinding(domain, 'plan_items');
      ready = domain['route'] == 'core' &&
          domain['cursor'] != null &&
          domain['replica_requires_resync'] != true;
    } on DomainFailure {
      // Only this runtime's previously acquired owner may be invalidated.
      await _clearOwnedReminders();
      rethrow;
    }
    if (epoch != _ownerEpoch || !identical(store, hub.storeFor('plan_items'))) {
      _pending = true;
      return;
    }
    if (!ready) {
      await _clearOwnedReminders();
      return;
    }
    final snapshot = await read(clock());
    if (epoch != _ownerEpoch || !identical(store, hub.storeFor('plan_items'))) {
      _pending = true;
      return;
    }
    final fingerprint = canonicalJson(store.binding.forDomain('plan_items'));
    if (_reminderBinding != fingerprint) {
      await _clearOwnedReminders();
      _reminders = PlanningReminders(
          db: db, alarms: alarms, binding: store.binding, clock: clock);
      _reminderBinding = fingerprint;
    }
    await _reminders!.reconcile(snapshot.items.values);
  }

  Future<void> _drain(Completer<void> done) async {
    try {
      while (_pending && !_disposed) {
        _pending = false;
        final consume = _consumeRequested;
        _consumeRequested = false;
        final epoch = _ownerEpoch;
        Object? reminderError;
        StackTrace? reminderStack;
        try {
          await _reconcilePlanning(epoch);
          if (epoch != _ownerEpoch) {
            _pending = true;
            continue;
          }
        } catch (error, stack) {
          // Reminder permissions must not prevent durable captures processing.
          reminderError = error;
          reminderStack = stack;
        }
        if (consume && epoch == _ownerEpoch && !_disposed) {
          _quick();
          try {
            final ownership = CaptureConsumerOwnership.forDatabase(db);
            // Phone quick captures have a distinct source and never wait for
            // the remote web bridge's Gate, lease, or network response.
            await _consumer?.consume(allowRemoteWeb: false);
            if (await ownership.coreSelected()) {
              await ownership.runCore((lease) async {
                await _consumer?.consume(verifyRemoteOwnership: lease.verify);
              }, bindingFingerprint: canonicalJson(_captureStore.binding.forDomain('captures')));
            }
          } on DomainFailure catch (error) {
            if (error.code != 'binding_changed' || epoch == _ownerEpoch) {
              rethrow;
            }
            _pending = true;
            continue;
          }
        }
        if (reminderError != null) {
          Error.throwWithStackTrace(reminderError, reminderStack!);
        }
        lastRefreshError = null;
        if (!_disposed) _events.add(null);
      }
      done.complete();
    } catch (e, stack) {
      lastRefreshError = e;
      if (!_disposed) _events.add(null);
      done.completeError(e, stack);
    } finally {
      _refreshing = null;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (ownsCaptureConnectionLifetime) {
      await CaptureConsumerOwnership.forDatabase(db).suspend();
    }
    await _subscription?.cancel();
    await _hubSubscription?.cancel();
    try {
      await _refreshing;
    } catch (_) {
      // Errors are retained in lastRefreshError; teardown must release streams.
    }
    await _events.close();
  }
}
