import 'dart:async';

import 'package:drift/drift.dart';

import 'domain_protocol.dart';
import 'domain_store.dart';
import 'food_models.dart';

abstract interface class FoodReader {
  Stream<void> get changes;
  Future<FoodDaySnapshot> read(DateTime date);
}

/// Read-only view over the configured food replica. It never changes a route,
/// synchronizes, writes an outbox operation, or opens another store.
class FoodService implements FoodReader {
  FoodService(
      {DomainStore? store,
      DateTime Function()? clock,
      this.missingStoreError = '尚未配置',
      this.connectionError})
      : _store = store,
        clock = clock ?? DateTime.now;

  final DomainStore? _store;
  final DateTime Function() clock;
  final String missingStoreError;
  final String? connectionError;

  @override
  Stream<void> get changes {
    final store = _store;
    if (store == null) return const Stream<void>.empty();
    return store.db
        .tableUpdates(const TableUpdateQuery.onTableName('kv_store'))
        .map<void>((_) {});
  }

  @override
  Future<FoodDaySnapshot> read(DateTime date) async {
    final key = foodDateKey(date);
    final store = _store;
    if (store == null) {
      return FoodDaySnapshot(date: key, error: missingStoreError);
    }
    try {
      final state = await store.read();
      final domain = store.domain(state, foodDomain);
      store.checkBinding(domain, foodDomain);
      if (domain['route'] != 'core') {
        return FoodDaySnapshot(date: key, error: '尚未启用');
      }
      if (domain['replica_requires_resync'] == true) {
        return FoodDaySnapshot(date: key, error: '副本需要重新同步');
      }
      if (domain['cursor'] == null) {
        return FoodDaySnapshot(
            date: key, error: connectionError ?? '等待首次同步');
      }
      final records = await store.visible(foodDomain);
      final entries = <FoodEntry>[];
      var invalidRecords = 0;
      for (final record in records) {
        try {
          final entry = FoodEntry.parse(record);
          if (!entry.voided && entry.localDate == key) entries.add(entry);
        } on Object {
          invalidRecords++;
        }
      }
      entries.sort((a, b) => a.eatenAt.compareTo(b.eatenAt));
      return FoodDaySnapshot(
        date: key,
        entries: List.unmodifiable(entries),
        totals: FoodTotals.sum(entries.map((entry) => entry.totals)),
        invalidRecords: invalidRecords,
        error: connectionError ??
            (invalidRecords == 0 ? null : '已跳过 $invalidRecords 条无法读取的记录'),
      );
    } on DomainFailure catch (error) {
      return FoodDaySnapshot(
        date: key,
        error: error.code == 'binding_changed' ? '连接已变更，请重新同步' : '读取失败',
      );
    } on Object {
      return FoodDaySnapshot(date: key, error: '读取失败');
    }
  }
}
