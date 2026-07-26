import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:memex/db/app_database.dart';

/// Hermes HTTP server connection config for the comic co-reading pipeline.
///
/// Unlike [RemoteTaskService] (which targets Supabase), this client talks
/// directly to the Hermes-side comic HTTP server over Tailscale HTTPS. No
/// anon key is needed — the Tailscale network layer is the trust boundary
/// (same model as the Dev Agent Bridge).
class ComicRemoteConfig {
  final String baseUrl; // e.g. https://host.example.invalid:8443
  const ComicRemoteConfig({required this.baseUrl});

  bool get isValid => baseUrl.trim().isNotEmpty;
}

/// HTTP client for the Hermes comic server.
///
/// Endpoints (see docs/companion-first/COMIC_CO_READING_PLAN.md §2.1):
///   GET    /v1/comic/health
///   POST   /v1/comic/watches
///   GET    /v1/comic/watches
///   PATCH  /v1/comic/watches/:id
///   DELETE /v1/comic/watches/:id
///   GET    /v1/comic/chapters?manga_id=X&since=Y
///   GET    /v1/comic/chapters/:id
///   GET    /v1/comic/images/:chapter_id/:page_num
class ComicRemoteService {
  final AppDatabase _db;
  ComicRemoteService({required AppDatabase db}) : _db = db;

  static const _kBaseUrl = 'comic.hermes_url';

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

  Future<ComicRemoteConfig> getConfig() async {
    return ComicRemoteConfig(baseUrl: (await _kvGet(_kBaseUrl)) ?? '');
  }

  Future<void> saveConfig({required String baseUrl}) async {
    var url = baseUrl.trim();
    if (url.endsWith('/')) url = url.substring(0, url.length - 1);
    await _kvSet(_kBaseUrl, url);
  }

  Future<bool> isConfigured() async => (await getConfig()).isValid;

  // ── HTTP helpers ───────────────────────────────────────────────────────────
  Uri _uri(ComicRemoteConfig cfg, String path, [Map<String, String>? query]) {
    return Uri.parse('${cfg.baseUrl}$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  /// Connectivity check.
  Future<String?> testConnection() async {
    final cfg = await getConfig();
    if (!cfg.isValid) return '未配置 Hermes 漫画服务 URL';
    try {
      final resp = await http
          .get(_uri(cfg, '/v1/comic/health'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return null;
      return 'HTTP ${resp.statusCode}: ${resp.body}';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Watches ───────────────────────────────────────────────────────────────
  Future<bool> upsertWatch({
    required String id,
    required String characterId,
    required String sourceSite,
    required String comicUrl,
    required String title,
    String? coverUrl,
  }) async {
    final cfg = await getConfig();
    if (!cfg.isValid) return false;
    try {
      final resp = await http
          .post(
            _uri(cfg, '/v1/comic/watches'),
            headers: _headers,
            body: jsonEncode({
              'id': id,
              'character_id': characterId,
              'source_site': sourceSite,
              'comic_url': comicUrl,
              'comic_title': title,
              'cover_url': coverUrl,
              'status': 'active',
            }),
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getWatches() async {
    final cfg = await getConfig();
    if (!cfg.isValid) return [];
    try {
      final resp = await http
          .get(_uri(cfg, '/v1/comic/watches'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map && data['watches'] is List) {
        return (data['watches'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<bool> patchWatch(
    String id, {
    String? status,
    String? lastChapterUrl,
  }) async {
    final cfg = await getConfig();
    if (!cfg.isValid) return false;
    final body = <String, dynamic>{};
    if (status != null) body['status'] = status;
    if (lastChapterUrl != null) body['last_chapter_url'] = lastChapterUrl;
    if (body.isEmpty) return true;
    try {
      final resp = await http
          .patch(_uri(cfg, '/v1/comic/watches/$id'),
              headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteWatch(String id) async {
    final cfg = await getConfig();
    if (!cfg.isValid) return false;
    try {
      final resp = await http
          .delete(_uri(cfg, '/v1/comic/watches/$id'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  // ── Chapters ──────────────────────────────────────────────────────────────

  /// Incremental chapter pull. [since] is seconds-since-epoch; only chapters
  /// with `created_at > since` and `status = 'ready'` are returned.
  Future<List<Map<String, dynamic>>> getNewChapters(
    String mangaId, {
    int? since,
  }) async {
    final cfg = await getConfig();
    if (!cfg.isValid) return [];
    final query = <String, String>{'manga_id': mangaId, 'status': 'ready'};
    if (since != null) query['since'] = since.toString();
    try {
      final resp = await http
          .get(_uri(cfg, '/v1/comic/chapters', query), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is List) return data.cast<Map<String, dynamic>>();
      if (data is Map && data['chapters'] is List) {
        return (data['chapters'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Build the proxied image URL for a chapter page.
  /// The phone never connects to the manga site directly — all images go
  /// through the Hermes proxy.
  Future<String> imageUrl(String chapterId, int pageNum) async {
    final cfg = await getConfig();
    return '${cfg.baseUrl}/v1/comic/images/$chapterId/$pageNum';
  }

  /// Synchronous image URL builder when config is already known.
  String imageUrlFor(String baseUrl, String chapterId, int pageNum) {
    return '$baseUrl/v1/comic/images/$chapterId/$pageNum';
  }
}