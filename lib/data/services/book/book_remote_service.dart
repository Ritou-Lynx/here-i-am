import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:memex/db/app_database.dart';

/// HTTP client for the Hermes book server (parallel to ComicRemoteService).
///
/// Endpoints (see tools/book_server/book_server.mjs):
///   GET    /v1/book/health
///   POST   /v1/book/import
///   GET    /v1/book/books
///   GET    /v1/book/books/:id
///   DELETE /v1/book/books/:id
///   GET    /v1/book/books/:id/chapters
///   GET    /v1/book/books/:id/chapters/:num
///   GET    /v1/book/books/:id/notes
///   POST   /v1/book/books/:id/notes
class BookRemoteService {
  final AppDatabase _db;
  BookRemoteService({required AppDatabase db}) : _db = db;

  static const _kBaseUrl = 'book.hermes_url';
  static const _kComicBaseUrl = 'comic.hermes_url';

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

  /// Resolves the book server URL. Falls back to the comic server URL when
  /// `book.hermes_url` is unset, because the merged comic_server now also
  /// serves `/v1/book/*` on the same listener. This keeps existing installs
  /// working without forcing a separate book URL config.
  Future<String> getBaseUrl() async {
    final own = await _kvGet(_kBaseUrl);
    if (own != null && own.trim().isNotEmpty) return own;
    final comic = await _kvGet(_kComicBaseUrl);
    return comic ?? '';
  }

  Future<void> saveBaseUrl(String url) async {
    var trimmed = url.trim();
    if (trimmed.endsWith('/')) trimmed = trimmed.substring(0, trimmed.length - 1);
    await _kvSet(_kBaseUrl, trimmed);
  }

  Future<bool> isConfigured() async => (await getBaseUrl()).isNotEmpty;

  // ── HTTP helpers ───────────────────────────────────────────────────────────

  Uri _uri(String base, String path, [Map<String, String>? query]) {
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  /// Connectivity check.
  Future<String?> testConnection() async {
    final base = await getBaseUrl();
    if (base.isEmpty) return '未配置书籍服务地址';
    try {
      final resp = await http
          .get(_uri(base, '/v1/book/health'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) return null;
      return 'HTTP ${resp.statusCode}: ${resp.body}';
    } catch (e) {
      return e.toString();
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Upload a TXT file to the server for processing.
  /// Returns the book metadata from the server.
  /// Throws on failure so the UI can show the actual error.
  Future<Map<String, dynamic>?> importBook(
    Uint8List bytes,
    String filename, {
    String? title,
    String? author,
  }) async {
    final base = await getBaseUrl();
    if (base.isEmpty) throw Exception('未配置书籍服务地址');
    final uri = _uri(base, '/v1/book/import', {
      'filename': filename,
      if (title != null && title.isNotEmpty) 'title': title,
      if (author != null && author.isNotEmpty) 'author': author,
    });
    final resp = await http
        .post(uri, headers: {'Content-Type': 'application/octet-stream'}, body: bytes)
        .timeout(const Duration(seconds: 120));
    if (resp.statusCode == 201) {
      final data = jsonDecode(resp.body);
      return data['book'] as Map<String, dynamic>?;
    }
    throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
  }

  // ── Books ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getBooks() async {
    final base = await getBaseUrl();
    if (base.isEmpty) return [];
    try {
      final resp = await http
          .get(_uri(base, '/v1/book/books'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['books'] is List) {
        return (data['books'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── Chapters ───────────────────────────────────────────────────────────────

  /// Fetch chapter content from server.
  Future<String?> getChapterContent(String bookId, int number) async {
    final base = await getBaseUrl();
    if (base.isEmpty) return null;
    try {
      final resp = await http
          .get(_uri(base, '/v1/book/books/$bookId/chapters/$number'), headers: _headers)
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body);
      return data['chapter']?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch AI-generated summaries (characters + chapter summaries).
  /// Returns null if summaries haven't been generated yet.
  Future<Map<String, dynamic>?> getSummaries(String bookId) async {
    final base = await getBaseUrl();
    if (base.isEmpty) return null;
    try {
      final resp = await http
          .get(_uri(base, '/v1/book/books/$bookId/summaries'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      return jsonDecode(resp.body) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  /// Fetch single chapter summary (extracted from summaries.json).
  Future<String?> getChapterSummary(String bookId, int number) async {
    final summaries = await getSummaries(bookId);
    if (summaries == null) return null;
    final list = summaries['chapter_summaries'] as List<dynamic>?;
    if (list == null) return null;
    for (final s in list) {
      if (s is Map && s['number'] == number) {
        return s['summary'] as String?;
      }
    }
    return null;
  }

  // ── Notes ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNotes(String bookId) async {
    final base = await getBaseUrl();
    if (base.isEmpty) return [];
    try {
      final resp = await http
          .get(_uri(base, '/v1/book/books/$bookId/notes'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body);
      if (data is Map && data['notes'] is List) {
        return (data['notes'] as List).cast<Map<String, dynamic>>();
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
