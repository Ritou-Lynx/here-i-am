import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'domain_protocol.dart';

/// Each replica, tombstone, correction and operation owns a SQLite row.
/// Root/domain metadata stays small. The caller owns the SQLite transaction.
class DomainRowStorage {
  DomainRowStorage(
    this.db, {
    required String installationId,
    required this.clock,
    this.fault,
  }) : legacyKey = 'personal_data_hub.v1.$installationId',
       prefix = 'personal_data_hub.v2.${component(installationId)}.';
  final GeneratedDatabase db;
  final DateTime Function() clock;
  final FutureOr<void> Function(String)? fault;
  final String legacyKey, prefix;
  static const bucket = 'personal_data_hub';
  static const collections = {
    'records': 'record',
    'phone_records': 'phone',
    'hidden_ids': 'tomb',
  };
  static String component(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  Future<Map<String, String>> rows({bool legacy = false}) async {
    final items = await db
        .customSelect(
          'SELECT key,value FROM kv_store WHERE bucket = ? AND (substr(key,1,?) = ?${legacy ? ' OR key = ?)' : ')'}',
          variables: [
            const Variable(bucket),
            Variable(prefix.length),
            Variable(prefix),
            if (legacy) Variable(legacyKey),
          ],
        )
        .get();
    return {
      for (final r in items) r.read<String>('key'): r.read<String>('value'),
    };
  }

  Json decode(String raw) {
    try {
      return jsonObject(jsonDecode(raw));
    } on FormatException {
      throw const DomainFailure('storage_corrupt');
    } on DomainFailure {
      throw const DomainFailure('storage_corrupt');
    }
  }

  Map<String, String> flatten(Json state) {
    final result = <String, String>{};
    void add(String key, Json row) {
      if (result.containsKey(key)) {
        throw const DomainFailure('storage_duplicate_identity');
      }
      result[key] = jsonEncode(row);
    }

    final domains = jsonObject(state['domains']);
    final outbox = state['outbox'];
    if (outbox is! List) throw const DomainFailure('storage_corrupt');
    add('${prefix}root', {
      'kind': 'root',
      'version': 2,
      'value': {...state}
        ..remove('domains')
        ..remove('outbox'),
    });
    for (final e in domains.entries) {
      final name = e.key, d = jsonObject(e.value);
      final base = '${prefix}d.${component(name)}.';
      final meta = {...d}..remove('corrections');
      for (final field in collections.keys) {
        meta.remove(field);
      }
      final present = collections.keys.where(d.containsKey).toList();
      add('${base}meta', {
        'kind': 'domain',
        'domain': name,
        'collections': present,
        'has_corrections': d.containsKey('corrections'),
        'value': meta,
      });
      for (final field in present) {
        for (final r in jsonObject(d[field]).entries) {
          add('$base${collections[field]!}.${component(r.key)}', {
            'kind': collections[field],
            'domain': name,
            'id': r.key,
            'value': r.value,
          });
        }
      }
      final corrections = d['corrections'] ?? <dynamic>[];
      if (corrections is! List) throw const DomainFailure('storage_corrupt');
      for (var i = 0; i < corrections.length; i++) {
        final c = jsonObject(corrections[i]);
        final op = c['op_id'], id = c['id'], field = c['field'];
        if (op is! String || id is! String || field is! String) {
          throw const DomainFailure('storage_corrupt');
        }
        add(
          '${base}correction.${component(op)}.${component(id)}.${component(field)}',
          {'kind': 'correction', 'domain': name, 'position': i, 'value': c},
        );
      }
    }
    for (var i = 0; i < outbox.length; i++) {
      final op = jsonObject(outbox[i]);
      if (op['op_id'] is! String) throw const DomainFailure('storage_corrupt');
      add('${prefix}op.${component(op['op_id'])}', {
        'kind': 'operation',
        'position': i,
        'value': op,
      });
    }
    return result;
  }

  Future<({Json state, bool migrated})> read() async {
    final stored = await rows(legacy: true);
    final old = stored.remove(legacyKey);
    if (old != null) {
      if (stored.isNotEmpty) {
        throw const DomainFailure('storage_format_conflict');
      }
      final state = decode(old);
      await writeDifference({}, flatten(state));
      await fault?.call('legacy_migration_before_commit');
      await db.customStatement(
        'DELETE FROM kv_store WHERE key = ? AND bucket = ?',
        [legacyKey, bucket],
      );
      db.notifyUpdates({const TableUpdate('kv_store')});
      return (state: state, migrated: true);
    }
    if (stored.isEmpty) {
      return (
        state: {'domains': <String, dynamic>{}, 'outbox': <dynamic>[]},
        migrated: false,
      );
    }
    final rawRoot = stored['${prefix}root'];
    if (rawRoot == null) throw const DomainFailure('storage_corrupt');
    final root = decode(rawRoot);
    if (root['kind'] != 'root' || root['version'] != 2) {
      throw const DomainFailure('storage_format_unsupported');
    }
    final state = {
      ...jsonObject(root['value']),
      'domains': <String, dynamic>{},
      'outbox': <dynamic>[],
    };
    final decoded = stored.entries
        .where((e) => e.key != '${prefix}root')
        .map((e) => decode(e.value))
        .toList();
    final domains = state['domains'] as Json;
    for (final r in decoded.where((r) => r['kind'] == 'domain')) {
      final name = r['domain'], present = r['collections'];
      if (name is! String ||
          domains.containsKey(name) ||
          present is! List ||
          present.any((v) => !collections.containsKey(v))) {
        throw const DomainFailure('storage_corrupt');
      }
      domains[name] = {
        ...jsonObject(r['value']),
        for (final field in present) field as String: <String, dynamic>{},
        if (r['has_corrections'] == true) 'corrections': <dynamic>[],
      };
    }
    final ops = <Json>[], corrections = <String, List<Json>>{};
    for (final r in decoded) {
      final kind = r['kind'];
      if (kind == 'domain') continue;
      if (kind == 'operation') {
        ops.add(r);
        continue;
      }
      final d = domains[r['domain']];
      if (d is! Map) throw const DomainFailure('storage_corrupt');
      if (kind == 'correction') {
        corrections.putIfAbsent(r['domain'] as String, () => []).add(r);
        continue;
      }
      final field = collections.entries
          .where((e) => e.value == kind)
          .firstOrNull
          ?.key;
      if (field == null ||
          r['id'] is! String ||
          d[field] is! Map ||
          (d[field] as Map).containsKey(r['id'])) {
        throw const DomainFailure('storage_corrupt');
      }
      d[field][r['id']] = r['value'];
    }
    List<Json> ordered(List<Json> items) {
      if (items.any((r) => r['position'] is! int || r['position'] < 0) ||
          items.map((r) => r['position']).toSet().length != items.length) {
        throw const DomainFailure('storage_corrupt');
      }
      items.sort(
        (a, b) => (a['position'] as int).compareTo(b['position'] as int),
      );
      return items.map((r) => jsonObject(r['value'])).toList();
    }

    state['outbox'] = ordered(ops);
    for (final e in corrections.entries) {
      if (domains[e.key]['corrections'] is! List) {
        throw const DomainFailure('storage_corrupt');
      }
      domains[e.key]['corrections'] = ordered(e.value);
    }
    // Fail closed on damaged identities, orphan rows or unknown formats.
    final rebuilt = flatten(state);
    if (stored.length != rebuilt.length ||
        stored.entries.any(
          (e) =>
              !rebuilt.containsKey(e.key) ||
              canonicalJson(jsonDecode(e.value)) !=
                  canonicalJson(jsonDecode(rebuilt[e.key]!)),
        )) {
      throw const DomainFailure('storage_corrupt');
    }
    return (state: state, migrated: false);
  }

  Future<void> save(Json state) async =>
      writeDifference(await rows(), flatten(state));

  Future<void> writeDifference(
    Map<String, String> before,
    Map<String, String> after,
  ) async {
    var changed = false;
    for (final key in before.keys.where((k) => !after.containsKey(k))) {
      await db.customStatement(
        'DELETE FROM kv_store WHERE key = ? AND bucket = ?',
        [key, bucket],
      );
      changed = true;
    }
    for (final e in after.entries) {
      if (before[e.key] == e.value) continue;
      await db.customStatement(
        'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?) '
        'ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
        [e.key, e.value, bucket, clock().millisecondsSinceEpoch],
      );
      changed = true;
      await fault?.call('storage_row_before_commit');
    }
    if (changed) db.notifyUpdates({const TableUpdate('kv_store')});
  }

  /// Works before owner connections attach, including previous whole-row stores.
  /// A previous cutover remains suppressed after credential replacement.
  static Future<Set<String>> suppressedDedupeDomains(
    GeneratedDatabase db,
  ) async {
    const oldPrefix = 'personal_data_hub.v1.';
    final items = await db
        .customSelect(
          'SELECT value FROM kv_store WHERE bucket = ? AND '
          "(substr(key,-5) = '.meta' OR substr(key,1,?) = ?)",
          variables: [
            const Variable(bucket),
            const Variable(oldPrefix.length),
            const Variable(oldPrefix),
          ],
        )
        .get();
    final result = <String>{};
    void inspect(String name, Json d) {
      if (d['local_dedupe_disabled'] == true ||
          d['route'] == 'core' ||
          d['route'] == 'shadow') {
        result.add(name);
      }
    }

    for (final row in items) {
      final value = jsonObject(jsonDecode(row.read<String>('value')));
      if (value['kind'] == 'domain') {
        inspect(value['domain'] as String, jsonObject(value['value']));
      } else if (value['domains'] is Map) {
        for (final e in jsonObject(value['domains']).entries) {
          inspect(e.key, jsonObject(e.value));
        }
      }
    }
    return result;
  }
}
