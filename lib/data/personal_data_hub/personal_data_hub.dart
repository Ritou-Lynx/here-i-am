import 'dart:async';
import 'package:memex/db/app_database.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';
import 'domain_sync_engine.dart';

enum PersonalDataHubChange { connections, synchronized }

/// App-scoped, inert until an owner supplies scoped domain connections.
/// No startup registration, migration, credentials, model call, or timer.
class PersonalDataHub {
  PersonalDataHub._(this.db);
  static final _instances = Expando<PersonalDataHub>();
  factory PersonalDataHub.forDatabase(AppDatabase db) =>
      _instances[db] ??= PersonalDataHub._(db);
  final AppDatabase db;
  final _stores = <String, DomainStore>{};
  final _engines = <String, DomainSyncEngine>{};
  final _recallDomains = <String>{};
  final Map<String, String> lastSyncErrors = {};
  final syncedDomains = <String>{};
  final _changes = StreamController<PersonalDataHubChange>.broadcast();
  Stream<PersonalDataHubChange> get changes => _changes.stream;
  bool get hasConnections => _engines.isNotEmpty;

  void attach(String domain, DomainStore store, DomainTransport transport,
      {required bool allowLocalRecall}) {
    if (!identical(db, store.db)) {
      throw const DomainFailure('database_mismatch');
    }
    _stores[domain] = store;
    _engines[domain] = DomainSyncEngine(store, transport);
    if (allowLocalRecall) {
      _recallDomains.add(domain);
    } else {
      _recallDomains.remove(domain);
    }
    syncedDomains.remove(domain);
    lastSyncErrors.remove(domain);
    _changes.add(PersonalDataHubChange.connections);
  }

  DomainStore? storeFor(String domain) => _stores[domain];
  Future<void> syncOnce(String domain) async {
    final engine = _engines[domain];
    if (engine == null) throw const DomainFailure('domain_not_configured');
    try {
      await engine.syncOnce(domain);
      syncedDomains.add(domain);
      lastSyncErrors.remove(domain);
    } on DomainFailure catch (error) {
      lastSyncErrors[domain] = error.code;
      rethrow;
    } catch (_) {
      lastSyncErrors[domain] = 'sync_failed';
      rethrow;
    } finally {
      _changes.add(PersonalDataHubChange.synchronized);
    }
  }

  /// Foreground-only pass. An unavailable domain must not block chat or other
  /// scoped domains; its error remains visible to the owning screen.
  Future<void> syncConfiguredOnce() async {
    for (final name in _engines.keys.toList()) {
      try {
        await syncOnce(name);
        lastSyncErrors.remove(name);
      } on DomainFailure catch (e) {
        lastSyncErrors[name] = e.code;
      } catch (_) {
        lastSyncErrors[name] = 'sync_failed';
      }
    }
  }

  Future<String> recallPending(String query) async {
    final lines = <String>[];
    final words = query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    for (final name in _recallDomains) {
      final store = _stores[name]!;
      final rows = await store.visible(name);
      for (final row in rows) {
        if (row['sync_label'] != '未同步') continue;
        final data = canonicalJson(row['data']);
        if (!words.any((w) => data.toLowerCase().contains(w))) continue;
        lines.add('未同步的记录（仅本机，$name）：$data');
        if (lines.length >= 10) return lines.join('\n');
      }
    }
    return lines.join('\n');
  }
}
