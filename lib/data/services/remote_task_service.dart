import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:memex/db/app_database.dart';

/// Supabase connection config for the remote purchase task queue.
class RemoteTaskConfig {
  final String baseUrl; // e.g. https://xxxx.supabase.co
  final String anonKey;
  const RemoteTaskConfig({required this.baseUrl, required this.anonKey});

  bool get isValid => baseUrl.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}

/// Bridges Memex (phone) and Hermes (desktop) via a Supabase REST table.
///
/// Memex enqueues purchase tasks; Hermes polls them via cronjob, executes the
/// Taobao order + Alipay payment, and writes status back. Memex pulls status
/// changes to update the local [AiPurchaseLog] and notify the user.
///
/// Table schema (create in Supabase SQL editor — see docs/shopping-pipeline.md):
///   purchase_tasks(id text pk, character_id, status, instruction, budget_cny,
///     product_hint, product_url, cashier_url, actual_price_cny, final_status,
///     error, result_note, created_at, updated_at)
///
/// The local AiPurchaseLog.id is reused verbatim as the remote row id, so no
/// extra mapping column is needed.
class RemoteTaskService {
  final AppDatabase _db;
  RemoteTaskService({required AppDatabase db}) : _db = db;

  static const _kBaseUrl = 'shopping.supabase_url';
  static const _kAnonKey = 'shopping.supabase_key';
  static const _table = 'purchase_tasks';

  // ── Config (persisted in KvStore) ──────────────────────────────────────────
  Future<String?> _kvGet(String key) async {
    final row = await (_db.select(_db.kvStore)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _kvSet(String key, String value) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _db.into(_db.kvStore).insertOnConflictUpdate(
          KvStoreCompanion.insert(
            key: key,
            value: Value(value),
            updatedAt: Value(now),
          ),
        );
  }

  Future<RemoteTaskConfig> getConfig() async {
    return RemoteTaskConfig(
      baseUrl: (await _kvGet(_kBaseUrl)) ?? '',
      anonKey: (await _kvGet(_kAnonKey)) ?? '',
    );
  }

  Future<void> saveConfig(
      {required String baseUrl, required String anonKey}) async {
    // Normalize: strip trailing slash.
    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    await _kvSet(_kBaseUrl, url);
    await _kvSet(_kAnonKey, anonKey.trim());
  }

  Future<bool> isConfigured() async => (await getConfig()).isValid;

  // ── REST helpers ───────────────────────────────────────────────────────────
  Map<String, String> _headers(RemoteTaskConfig cfg,
      {bool returnRepresentation = false}) {
    return {
      'apikey': cfg.anonKey,
      'Authorization': 'Bearer ${cfg.anonKey}',
      'Content-Type': 'application/json',
      'Prefer': returnRepresentation ? 'return=representation' : 'return=minimal',
    };
  }

  Uri _tableUri(RemoteTaskConfig cfg, [Map<String, String>? query]) {
    return Uri.parse('${cfg.baseUrl}/rest/v1/$_table')
        .replace(queryParameters: query);
  }

  /// Enqueue a purchase task. Returns true on success.
  ///
  /// [id] should be the local AiPurchaseLog id so the two stay in sync.
  Future<bool> enqueueTask({
    required String id,
    required String characterId,
    required String instruction,
    double? budgetCny,
    String? productHint,
    String? productUrl,
  }) async {
    final cfg = await getConfig();
    if (!cfg.isValid) return false;

    final now = DateTime.now().toUtc().toIso8601String();
    final body = jsonEncode([
      {
        'id': id,
        'character_id': characterId,
        'status': 'queued',
        'instruction': instruction,
        'budget_cny': budgetCny,
        'product_hint': productHint,
        'product_url': productUrl,
        'created_at': now,
        'updated_at': now,
      }
    ]);

    try {
      final resp = await http
          .post(_tableUri(cfg), headers: _headers(cfg), body: body)
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Fetch a single task row by id. Returns null if not found or on error.
  Future<Map<String, dynamic>?> getTask(String id) async {
    final cfg = await getConfig();
    if (!cfg.isValid) return null;

    try {
      final resp = await http
          .get(
            _tableUri(cfg, {'id': 'eq.$id', 'select': '*'}),
            headers: _headers(cfg),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final list = jsonDecode(resp.body) as List<dynamic>;
      if (list.isEmpty) return null;
      return list.first as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Fetch all tasks for a set of ids in one round-trip.
  Future<List<Map<String, dynamic>>> getTasks(List<String> ids) async {
    final cfg = await getConfig();
    if (!cfg.isValid || ids.isEmpty) return [];

    final inClause = '(${ids.join(",")})';
    try {
      final resp = await http
          .get(
            _tableUri(cfg, {'id': 'in.$inClause', 'select': '*'}),
            headers: _headers(cfg),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final list = jsonDecode(resp.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Connectivity check: GET with limit 1. Returns null on success, else an
  /// error string for display in the settings page.
  Future<String?> testConnection() async {
    final cfg = await getConfig();
    if (!cfg.isValid) return '未配置 Supabase URL 或 key';
    try {
      final resp = await http
          .get(
            _tableUri(cfg, {'select': 'id', 'limit': '1'}),
            headers: _headers(cfg),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) return null;
      return 'HTTP ${resp.statusCode}: ${resp.body}';
    } catch (e) {
      return e.toString();
    }
  }
}
