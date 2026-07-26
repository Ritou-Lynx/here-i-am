import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/data/services/comic/comic_remote_service.dart';
import 'package:uuid/uuid.dart';

/// Local library CRUD + Hermes sync for the comic co-reading feature.
///
/// Architecture guard: constructor-injected db, no MemexRouter import, no
/// FK to Memex card tables. See AGENTS.md architecture constraints.
class ComicLibraryService {
  final AppDatabase _db;
  final ComicRemoteService _remote;
  final _uuid = const Uuid();

  ComicLibraryService({
    required AppDatabase db,
    required ComicRemoteService remote,
  })  : _db = db,
        _remote = remote;

  static ComicLibraryService? _instance;
  static ComicLibraryService get instance {
    if (_instance == null) {
      throw Exception('ComicLibraryService not initialized. Call init() first.');
    }
    return _instance!;
  }

  static void init({required AppDatabase db, required ComicRemoteService remote}) {
    _instance = ComicLibraryService(db: db, remote: remote);
  }

  int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  // ── Watch management ───────────────────────────────────────────────────────

  /// Register a new manga watch. Writes locally first, then pushes to Hermes
  /// (fire-and-forget: local row is the source of truth; Hermes pull via
  /// cronjob will pick it up).
  Future<String> addWatch({
    required String characterId,
    required String sourceSite,
    required String comicUrl,
    required String title,
    String? coverUrl,
  }) async {
    // Use the manwa book id as the local id when present so the local row,
    // the server watch and the crawler's watch_id all share one key — that
    // shared key is what lets online sync line up with already-crawled
    // chapters without re-crawling.
    final bookMatch = RegExp(r'/book/(\d+)').firstMatch(comicUrl);
    final id = bookMatch?.group(1) ?? _uuid.v4();
    final now = _nowSeconds();
    await _db.into(_db.comicMangas).insertOnConflictUpdate(
          ComicMangasCompanion.insert(
            id: id,
            characterId: characterId,
            sourceSite: sourceSite,
            comicUrl: comicUrl,
            title: title,
            coverUrl: Value(coverUrl),
            createdAt: now,
            updatedAt: now,
          ),
        );
    // Fire-and-forget remote push
    _remote.upsertWatch(
      id: id,
      characterId: characterId,
      sourceSite: sourceSite,
      comicUrl: comicUrl,
      title: title,
      coverUrl: coverUrl,
    );
    return id;
  }

  Future<void> pauseWatch(String mangaId) async {
    await (_db.update(_db.comicMangas)
          ..where((t) => t.id.equals(mangaId)))
        .write(ComicMangasCompanion(
      status: const Value('paused'),
      updatedAt: Value(_nowSeconds()),
    ));
    _remote.patchWatch(mangaId, status: 'paused');
  }

  Future<void> resumeWatch(String mangaId) async {
    await (_db.update(_db.comicMangas)
          ..where((t) => t.id.equals(mangaId)))
        .write(ComicMangasCompanion(
      status: const Value('active'),
      updatedAt: Value(_nowSeconds()),
    ));
    _remote.patchWatch(mangaId, status: 'active');
  }

  Future<void> removeWatch(String mangaId) async {
    await (_db.update(_db.comicMangas)
          ..where((t) => t.id.equals(mangaId)))
        .write(ComicMangasCompanion(
      status: const Value('removed'),
      updatedAt: Value(_nowSeconds()),
    ));
    _remote.deleteWatch(mangaId);
  }

  // ── Local queries ──────────────────────────────────────────────────────────

  Future<List<ComicManga>> getLibrary() async {
    final query = _db.select(_db.comicMangas)
      ..where((t) => t.status.equals('active'))
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  Future<ComicManga?> getManga(String mangaId) async {
    return (_db.select(_db.comicMangas)
          ..where((t) => t.id.equals(mangaId)))
        .getSingleOrNull();
  }

  Future<List<ComicChapter>> getChapters(String mangaId) async {
    final query = _db.select(_db.comicChapters)
      ..where((t) => t.mangaId.equals(mangaId))
      ..orderBy([(t) => OrderingTerm.asc(t.chapterNumber)]);
    return query.get();
  }

  Future<ComicChapter?> getChapter(String chapterId) async {
    return (_db.select(_db.comicChapters)
          ..where((t) => t.id.equals(chapterId)))
        .getSingleOrNull();
  }

  Future<ComicChapter?> getLatestReadyChapter(String mangaId) async {
    final chapters = await (_db.select(_db.comicChapters)
          ..where((t) => t.mangaId.equals(mangaId) & t.status.equals('ready'))
          ..orderBy([(t) => OrderingTerm.desc(t.chapterNumber)])
          ..limit(1))
        .get();
    return chapters.isEmpty ? null : chapters.first;
  }

  // ── Sync (pull from Hermes) ────────────────────────────────────────────────

  /// Pull new ready chapters from Hermes for a manga. Returns the list of
  /// newly synced chapter ids (empty if nothing new or remote unavailable).
  Future<List<String>> syncNewChapters(String mangaId) async {
    // 1. Get sync cursor
    final cursor = await (_db.select(_db.comicSyncCursor)
          ..where((t) => t.mangaId.equals(mangaId)))
        .getSingleOrNull();
    final since = cursor?.lastSyncedAt;

    // 2. Pull from Hermes
    final remoteChapters = await _remote.getNewChapters(mangaId, since: since);
    if (remoteChapters.isEmpty) return [];

    final newIds = <String>[];
    final now = _nowSeconds();

    for (final remote in remoteChapters) {
      final id = remote['id'] as String?;
      if (id == null) continue;

      // Don't skip existing chapters — we need to update comments and other
      // metadata that may have changed since the last sync.
      final existing = await getChapter(id);
      newIds.add(id);

      // Update manga title if we got a real title from the server
      final remoteTitle = remote['comic_title'] as String?;
      if (remoteTitle != null && !remoteTitle.startsWith('漫画')) {
        final manga = await getManga(mangaId);
        if (manga != null && manga.title != remoteTitle) {
          await (_db.update(_db.comicMangas)..where((t) => t.id.equals(mangaId)))
              .write(ComicMangasCompanion(
            title: Value(remoteTitle),
            updatedAt: Value(now),
          ));
        }
      }

      // The crawler writes `pages` / `screenplay` as JSON arrays, while older
      // docs/clients used the `*_json` string form. Accept both so sync never
      // silently drops the screenplay.
      final rawPages = remote['pages_json'] ?? remote['pages'];
      final pagesJson = rawPages is String
          ? rawPages
          : (rawPages is List ? jsonEncode(rawPages) : null);
      final rawSp = remote['screenplay_json'] ?? remote['screenplay'];
      final screenplayJson = rawSp is String
          ? rawSp
          : (rawSp is List ? jsonEncode(rawSp) : null);
      final rawComments = remote['comments_json'] ?? remote['comments'];
      final commentsJson = rawComments is String
          ? rawComments
          : (rawComments is List ? jsonEncode(rawComments) : null);

      // Upsert chapter
      await _db.into(_db.comicChapters).insertOnConflictUpdate(
            ComicChaptersCompanion.insert(
              id: id,
              mangaId: remote['watch_id'] as String? ?? mangaId,
              chapterNumber: (remote['chapter_number'] as num?)?.toInt() ?? 0,
              chapterTitle: Value(remote['chapter_title'] as String?),
              chapterUrl: remote['chapter_url'] as String? ?? '',
              pageCount: Value((remote['page_count'] as num?)?.toInt() ?? 0),
              pagesJson: Value(pagesJson),
              commentsJson: Value(commentsJson),
              coverUrl: Value(remote['cover_url'] as String?),
              status: const Value('ready'),
              createdAt: (remote['created_at'] as num?)?.toInt() ?? now,
              updatedAt: now,
            ),
          );

      // Upsert page screenplays
      if (screenplayJson != null) {
        await _upsertScreenplays(id, screenplayJson, remote['ocr_model'] as String?);
      }
    }

    // 3. Update sync cursor
    await _db.into(_db.comicSyncCursor).insertOnConflictUpdate(
          ComicSyncCursorCompanion.insert(
            mangaId: mangaId,
            lastSyncedAt: Value(now),
          ),
        );

    return newIds;
  }

  /// Sync all active watches' titles from the server watch list.
  /// Also removes local mangas that were deleted on the server.
  Future<void> syncWatchTitles() async {
    final watches = await _remote.getWatches();
    if (watches.isEmpty) return;
    final now = _nowSeconds();
    final remoteIds = <String>{};
    for (final w in watches) {
      final id = w['id'] as String?;
      final title = w['comic_title'] as String?;
      final status = w['status'] as String?;
      if (id == null) continue;
      remoteIds.add(id);
      if (title == null) continue;
      // Remove local manga if server says removed
      if (status == 'removed') {
        await (_db.update(_db.comicMangas)..where((t) => t.id.equals(id)))
            .write(ComicMangasCompanion(
          status: const Value('removed'),
          updatedAt: Value(now),
        ));
        continue;
      }
      // Update title if different
      final manga = await getManga(id);
      if (manga != null && manga.title != title) {
        await (_db.update(_db.comicMangas)..where((t) => t.id.equals(id)))
            .write(ComicMangasCompanion(
          title: Value(title),
          updatedAt: Value(now),
        ));
      }
    }
  }

  /// Sync all active watches. Returns total new chapter count.
  Future<int> syncAll() async {
    await syncWatchTitles();
    final library = await getLibrary();
    var total = 0;
    for (final manga in library) {
      total += (await syncNewChapters(manga.id)).length;
    }
    return total;
  }

  Future<void> _upsertScreenplays(
    String chapterId,
    String screenplayJson,
    String? modelName,
  ) async {
    final List<dynamic> pages = jsonDecode(screenplayJson);
    final now = _nowSeconds();
    for (final page in pages) {
      final pageNum = (page['page_num'] as num?)?.toInt() ?? 1;
      final pageJson = jsonEncode(page);
      final pageId = _uuid.v4();

      // Delete existing screenplay for this (chapter, page) then insert
      await (_db.delete(_db.comicPageScreenplays)
            ..where((t) =>
                t.chapterId.equals(chapterId) & t.pageNum.equals(pageNum)))
          .go();
      await _db.into(_db.comicPageScreenplays).insert(
            ComicPageScreenplaysCompanion(
              id: Value(pageId),
              chapterId: Value(chapterId),
              pageNum: Value(pageNum),
              screenplayJson: Value(pageJson),
              generatedByModel: Value(modelName),
              createdAt: Value(now),
            ),
          );
    }
  }
}