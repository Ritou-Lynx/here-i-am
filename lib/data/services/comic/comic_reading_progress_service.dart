import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';

/// Records and queries manga reading progress.
///
/// One row per manga (upsert on every page turn). Lin Ai queries this
/// to know "where did the user leave off" in daily chat.
///
/// Architecture guard: constructor-injected db, no MemexRouter import.
class ComicReadingProgressService {
  final AppDatabase _db;
  ComicReadingProgressService({required AppDatabase db}) : _db = db;

  static ComicReadingProgressService? _instance;
  static ComicReadingProgressService get instance {
    if (_instance == null) {
      throw Exception(
          'ComicReadingProgressService not initialized. Call init() first.');
    }
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  static void init({required AppDatabase db}) {
    _instance = ComicReadingProgressService(db: db);
  }

  int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Record current page. Called on every page turn in the reader.
  Future<void> recordProgress({
    required String mangaId,
    String? chapterId,
    required int page,
  }) async {
    await _db.into(_db.comicReadingProgress).insertOnConflictUpdate(
          ComicReadingProgressCompanion.insert(
            mangaId: mangaId,
            chapterId: Value(chapterId),
            page: Value(page),
            readAt: _nowSeconds(),
          ),
        );
  }

  /// Get progress for a manga. Returns null if never read.
  Future<ComicReadingProgressData?> getProgress(String mangaId) async {
    return (_db.select(_db.comicReadingProgress)
          ..where((t) => t.mangaId.equals(mangaId)))
        .getSingleOrNull();
  }

  /// Find the most recently read manga (within [withinMinutes] ago).
  /// Used by Lin Ai's `comic_current_page` tool to know what the user
  /// is reading right now.
  Future<ComicManga?> getCurrentlyReadingManga({
    int withinMinutes = 30,
  }) async {
    final cutoff =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - withinMinutes * 60;
    final progressRows = await (_db.select(_db.comicReadingProgress)
          ..where((t) => t.readAt.isBiggerThanValue(cutoff))
          ..orderBy([(t) => OrderingTerm.desc(t.readAt)])
          ..limit(1))
        .get();
    if (progressRows.isEmpty) return null;
    return (_db.select(_db.comicMangas)
          ..where((t) => t.id.equals(progressRows.first.mangaId)))
        .getSingleOrNull();
  }

  /// Get all manga with reading progress, ordered by most recent.
  Future<List<ComicReadingProgressData>> getRecentProgress({
    int limit = 10,
  }) async {
    return (_db.select(_db.comicReadingProgress)
          ..orderBy([(t) => OrderingTerm.desc(t.readAt)])
          ..limit(limit))
        .get();
  }
}