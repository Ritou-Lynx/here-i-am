import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/book/book_remote_service.dart';

/// Local-first book library CRUD + server sync.
///
/// Architecture guard: constructor-injected db, no MemexRouter import,
/// no FK to Memex card tables.
class BookLibraryService {
  final AppDatabase _db;
  final BookRemoteService _remote;

  BookLibraryService({required AppDatabase db, required BookRemoteService remote})
      : _db = db,
        _remote = remote;

  static BookLibraryService? _instance;
  static bool get isInitialized => _instance != null;
  static BookLibraryService get instance {
    if (_instance == null) {
      throw Exception('BookLibraryService not initialized. Call init() first.');
    }
    return _instance!;
  }

  static void init({required AppDatabase db, required BookRemoteService remote}) {
    _instance = BookLibraryService(db: db, remote: remote);
  }

  int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── Import ─────────────────────────────────────────────────────────────────

  /// Import a TXT file: upload to server → receive metadata → store locally.
  /// Returns the local Book row, or null on failure.
  Future<Book?> importTxt(
    Uint8List bytes,
    String filename, {
    required String characterId,
    String? title,
    String? author,
  }) async {
    final result = await _remote.importBook(bytes, filename, title: title, author: author);
    if (result == null) return null;

    final id = result['id'] as String;
    final now = _now();

    // Insert book
    await _db.into(_db.books).insertOnConflictUpdate(
          BooksCompanion.insert(
            id: id,
            characterId: characterId,
            title: result['title'] as String? ?? filename,
            author: Value(result['author'] as String? ?? ''),
            format: const Value('txt'),
            chapterCount: Value((result['chapter_count'] as num?)?.toInt() ?? 0),
            totalChars: Value((result['total_chars'] as num?)?.toInt() ?? 0),
            splitMethod: Value(result['split_method'] as String?),
            splitPattern: Value(result['split_pattern'] as String?),
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Fetch chapter list and cache TOC locally
    await _syncChapters(id);

    return getBook(id);
  }

  /// Sync chapter TOC from server for a book.
  Future<void> _syncChapters(String bookId) async {
    final base = await _remote.getBaseUrl();
    if (base.isEmpty) return;
    try {
      final uri = Uri.parse('$base/v1/book/books/$bookId/chapters');
      final resp = await http
          .get(uri, headers: {'Content-Type': 'application/json'})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return;
      final data = jsonDecode(resp.body);
      final chapters = (data['chapters'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final now = _now();
      for (final ch in chapters) {
        final number = (ch['number'] as num?)?.toInt() ?? 0;
        if (number == 0) continue;
        await _db.into(_db.bookChapters).insertOnConflictUpdate(
              BookChaptersCompanion.insert(
                id: '${bookId}_$number',
                bookId: bookId,
                number: number,
                title: ch['title'] as String? ?? '第 $number 章',
                chars: Value((ch['chars'] as num?)?.toInt() ?? 0),
                createdAt: now,
              ),
            );
      }
    } catch (_) {
      // Non-fatal: TOC will be incomplete but book still usable
    }
  }

  // ── Local queries ──────────────────────────────────────────────────────────

  Future<List<Book>> getLibrary() async {
    return (_db.select(_db.books)
          ..where((t) => t.status.equals('active'))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<Book?> getBook(String bookId) async {
    return (_db.select(_db.books)..where((t) => t.id.equals(bookId)))
        .getSingleOrNull();
  }

  Future<List<BookChapter>> getChapters(String bookId) async {
    return (_db.select(_db.bookChapters)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.asc(t.number)]))
        .get();
  }

  Future<BookChapter?> getChapter(String bookId, int number) async {
    return (_db.select(_db.bookChapters)
          ..where((t) => t.bookId.equals(bookId) & t.number.equals(number)))
        .getSingleOrNull();
  }

  /// Get chapter content — from local cache first, then server.
  Future<String?> getChapterContent(String bookId, int number) async {
    final local = await getChapter(bookId, number);
    if (local?.content != null && local!.content!.isNotEmpty) {
      return local.content;
    }
    // Fetch from server and cache
    final content = await _remote.getChapterContent(bookId, number);
    if (content != null) {
      await (_db.update(_db.bookChapters)
            ..where((t) => t.bookId.equals(bookId) & t.number.equals(number)))
          .write(BookChaptersCompanion(content: Value(content)));
    }
    return content;
  }

  // ── Progress ───────────────────────────────────────────────────────────────

  Future<BookReadingProgressData?> getProgress(String bookId) async {
    return (_db.select(_db.bookReadingProgress)
          ..where((t) => t.bookId.equals(bookId)))
        .getSingleOrNull();
  }

  Future<void> recordProgress({
    required String bookId,
    required int chapterNumber,
    double scrollRatio = 0.0,
  }) async {
    await _db.into(_db.bookReadingProgress).insertOnConflictUpdate(
          BookReadingProgressCompanion.insert(
            bookId: bookId,
            chapterNumber: Value(chapterNumber),
            scrollRatio: Value(scrollRatio),
            readAt: _now(),
          ),
        );
    // Touch the book's updatedAt so it sorts to top of library
    await (_db.update(_db.books)..where((t) => t.id.equals(bookId)))
        .write(BooksCompanion(updatedAt: Value(_now())));
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<void> removeBook(String bookId) async {
    await (_db.update(_db.books)..where((t) => t.id.equals(bookId)))
        .write(BooksCompanion(status: const Value('removed'), updatedAt: Value(_now())));
  }
}
