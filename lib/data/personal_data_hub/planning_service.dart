import 'dart:async';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';
import 'planning_models.dart';

/// The owner-supplied trusted interaction adapter must durably bind this action
/// in the SAME db transaction. Core's verifier must understand the returned
/// reference; generating a UUID alone does not authorize a request on Core.
class PlanningUiAuthorization {
  const PlanningUiAuthorization(
      {required this.reference,
      required this.opId,
      required this.binding,
      required this.itemId,
      required this.status,
      required this.at});
  final String reference, opId, itemId, status;
  final DomainBinding binding;
  final DateTime at;
  Json toJson() => {
        'authorization_ref': reference,
        'op_id': opId,
        ...binding.forDomain('plan_items'),
        'kind': 'status',
        'actor': 'user_direct',
        'id': itemId,
        'patch': {'status': status},
        'at': at.toUtc().toIso8601String(),
        'source': 'planning_status_button'
      };
}

typedef PlanningAuthorize = Future<void> Function(
    GeneratedDatabase db, PlanningUiAuthorization action);

abstract interface class PlanningReader {
  Stream<void> get changes;
  Future<PlanningSnapshot> read(DateTime date);
  Future<void> synchronize();
  Future<String> setStatus(String itemId, PlanningStatusAction action);
}

/// View adapter over W7 replicas/outbox. No HTTP, credentials, route changes,
/// scheduler, autonomous writes, or second planning store are created here.
class PlanningService implements PlanningReader {
  PlanningService(
      {Map<String, DomainStore> stores = const {},
      this.authorize,
      this.syncDomain,
      Stream<void>? changes,
      PlanningConnection Function()? connection,
      DateTime Function()? clock})
      : stores = Map.unmodifiable(stores),
        _externalChanges = changes,
        _connection = connection ?? (() => PlanningConnection.unknown),
        clock = clock ?? DateTime.now {
    if (stores.keys.any((name) => !planningDomains.contains(name))) {
      throw const DomainFailure('unexpected_planning_domain');
    }
    final owners = stores.values
        .map((store) =>
            (store.binding.coreInstanceId, store.binding.installationId))
        .toSet();
    if (owners.length > 1) {
      throw const DomainFailure('planning_binding_mismatch');
    }
  }
  final Map<String, DomainStore> stores;
  final PlanningAuthorize? authorize;
  final Future<void> Function(String domain)? syncDomain;
  final Stream<void>? _externalChanges;
  final PlanningConnection Function() _connection;
  final DateTime Function() clock;

  @override
  Stream<void> get changes {
    final dbs = stores.values.map((store) => store.db).toSet();
    // A controller multiplexes independent connection and committed DB events.
    late StreamController<void> events;
    final subscriptions = <StreamSubscription<dynamic>>[];
    events = StreamController<void>(onListen: () {
      void listen(Stream<dynamic> source) => subscriptions.add(
          source.listen((_) => events.add(null), onError: events.addError));
      for (final db in dbs) {
        listen(db.tableUpdates(const TableUpdateQuery.onTableName('kv_store')));
      }
      if (_externalChanges != null) listen(_externalChanges);
    }, onCancel: () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    });
    return events.stream;
  }

  @override
  Future<PlanningSnapshot> read(DateTime date) async {
    final records = <String, List<Json>>{};
    final errors = <String, String>{};
    final operations = <String, PlanningOperation>{};
    var writable = false;
    for (final name in planningDomains) {
      final store = stores[name];
      if (store == null) {
        errors[name] = '尚未配置';
        continue;
      }
      try {
        await store.db.transaction(() async {
          final state = await store.read(), domain = store.domain(state, name);
          store.checkBinding(domain, name);
          if (domain['route'] != 'core') {
            errors[name] = '尚未启用';
            return;
          }
          if (domain['replica_requires_resync'] == true) {
            errors[name] = '副本需要重新同步';
            return;
          }
          records[name] = await store.visible(name);
          if (domain['cursor'] == null) errors[name] = '等待首次同步';
          if (name == 'plan_items') {
            writable = authorize != null && domain['cursor'] != null;
            for (final raw in state['outbox'] as List) {
              final op = jsonObject(raw);
              if (op['domain'] == name &&
                  op['namespace'] == 'production' &&
                  op['intent']?['kind'] == 'status') {
                operations[op['id'] as String] = PlanningOperation(
                    op['op_id'] as String,
                    op['id'] as String,
                    op['state'] as String,
                    op['reason'] as String?);
              }
            }
          }
        });
      } on DomainFailure catch (e) {
        errors[name] = e.code == 'binding_changed' ? '连接已变更，请重新同步' : '读取失败';
      }
    }
    final key = planningDateKey(date);
    final days = (records['plan_days'] ?? [])
        .map(PlanningDay.new)
        .where((day) => day.date.compareTo(key) <= 0)
        .toList()
      ..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.version.compareTo(a.version);
      });
    final weeks = (records['plan_weeks'] ?? [])
        .map(PlanningWeek.new)
        .where((week) => week.key == planningWeekKey(date))
        .toList();
    return PlanningSnapshot(
        day: days.firstOrNull,
        week: weeks.firstOrNull,
        items: {
          for (final raw in records['plan_items'] ?? <Json>[])
            raw['id'] as String: PlanningItem(raw)
        },
        operations: operations,
        domainErrors: errors,
        connection: _connection(),
        statusWritable: writable);
  }

  @override
  Future<void> synchronize() async {
    if (syncDomain == null) return;
    // Do not let one offline/forbidden domain prevent the others recovering.
    Object? firstError;
    for (final name in planningDomains) {
      final store = stores[name];
      if (store == null) continue;
      try {
        final domain = store.domain(await store.read(), name);
        store.checkBinding(domain, name);
        if (domain['route'] == 'core') await syncDomain!(name);
      } catch (e) {
        firstError ??= e;
      }
    }
    if (firstError != null) throw firstError;
  }

  @override
  Future<String> setStatus(String itemId, PlanningStatusAction action) async {
    final store = stores['plan_items'];
    if (store == null || authorize == null) {
      throw const DomainFailure('planning_status_not_configured');
    }
    return store.db.transaction(() async {
      final state = await store.read(),
          domain = store.domain(state, 'plan_items');
      store.checkBinding(domain, 'plan_items');
      if (domain['route'] != 'core' ||
          domain['cursor'] == null ||
          domain['replica_requires_resync'] == true) {
        throw const DomainFailure('planning_status_not_ready');
      }
      final raw = domain['records'][itemId];
      if (raw == null ||
          raw['deleted_at'] != null ||
          domain['hidden_ids']?[itemId] != null) {
        throw const DomainFailure('planning_item_unavailable');
      }
      final item = PlanningItem(jsonObject(raw));
      if (!item.canChangeStatus) {
        throw const DomainFailure('planning_item_terminal');
      }
      if ((state['outbox'] as List).any((op) =>
          op['domain'] == 'plan_items' &&
          op['id'] == itemId &&
          op['namespace'] == 'production' &&
          !['accepted', 'duplicate'].contains(op['state']))) {
        throw const DomainFailure('planning_action_unresolved');
      }
      final ref = 'planning-ui:${const Uuid().v4()}';
      final op = await store.enqueue('plan_items',
          id: itemId,
          kind: 'status',
          actor: 'user_direct',
          authorizationRef: ref,
          baseRevision: item.revision,
          fields: {
            'patch': {'status': action.value}
          });
      await authorize!(
          store.db,
          PlanningUiAuthorization(
              reference: ref,
              opId: op,
              binding: store.binding,
              itemId: itemId,
              status: action.value,
              at: clock()));
      return op;
    });
  }
}
