import 'package:drift/drift.dart';

/// User-watched manga.
///
/// Architecture guard: this table has no FK to any Memex card system
/// (CardCache / fact_id). All cross-table references in this file are
/// soft references (text columns, no `.references()`), so the comic
/// domain can be lifted out of this project without Memex coupling.
class ComicMangas extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get characterId => text()();

  TextColumn get sourceSite => text()(); // 'manga_site_a' etc.
  TextColumn get comicUrl => text()(); // manga home page URL
  TextColumn get title => text()();
  TextColumn get coverUrl => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('active'))();
  // 'active' | 'paused' | 'removed'

  IntColumn get createdAt => integer()(); // seconds since epoch
  IntColumn get updatedAt => integer()(); // seconds since epoch

  /// JSON array of TopicThread intent objects: [{threadId, threadTitle}]
  /// Set by user to route co-reading cleanup to specific Topic Threads.
  TextColumn get intentsJson =>
      text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Manga chapter downloaded + Vision-processed by Hermes.
///
/// `id` matches the Hermes-side chapter record id so the two sides
/// stay in sync without a mapping column (same pattern as AiPurchaseLog).
class ComicChapters extends Table {
  TextColumn get id => text()(); // UUID v4, matches Hermes record
  TextColumn get mangaId => text()(); // → ComicMangas.id (soft ref, no FK)

  IntColumn get chapterNumber => integer()();
  TextColumn get chapterTitle => text().nullable()();
  TextColumn get chapterUrl => text()(); // source URL on the manga site

  IntColumn get pageCount => integer().withDefault(const Constant(0))();
  TextColumn get pagesJson => text().nullable()();
  // JSON: [{page_num, image_url, width, height}]

  TextColumn get commentsJson => text().nullable()();
  // JSON: [{user, text}] — reader comments from the manga site, text only

  TextColumn get coverUrl => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('pending'))();
  // 'pending' (metadata only) | 'ready' (images + screenplay ready) | 'failed'

  TextColumn get error => text().nullable()();

  IntColumn get createdAt => integer()(); // seconds since epoch
  IntColumn get updatedAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {id};
}

/// Structured screenplay for a single page (Vision extraction result).
///
/// One row per (chapter, page). The screenplay JSON is produced by
/// the Ollama Vision model on the Hermes side and pulled to the phone
/// as-is, so Lin Ai can read "who said what" without re-running Vision.
class ComicPageScreenplays extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get chapterId => text()(); // → ComicChapters.id (soft ref)
  IntColumn get pageNum => integer()(); // 1-indexed

  TextColumn get screenplayJson => text()();
  // JSON: {panels: [{panel_id, speaker, text, panel_desc}]}

  TextColumn get imageUrl => text().nullable()(); // proxied image URL on Hermes

  IntColumn get schemaVersion =>
      integer().withDefault(const Constant(1))();
  TextColumn get generatedByModel => text().nullable()(); // Vision model name

  IntColumn get createdAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {id};
}

/// Reading progress — one row per manga, upserted on every page turn.
class ComicReadingProgress extends Table {
  TextColumn get mangaId => text()(); // → ComicMangas.id (soft ref)
  TextColumn get chapterId => text().nullable()(); // → ComicChapters.id
  IntColumn get page => integer().withDefault(const Constant(1))(); // 1-indexed

  IntColumn get readAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {mangaId};
}

/// Per-manga sync cursor (pattern from ConversationCaptureCursors).
class ComicSyncCursor extends Table {
  TextColumn get mangaId => text()(); // → ComicMangas.id
  TextColumn get lastSyncedChapterId => text().nullable()();
  IntColumn get lastSyncedAt => integer().nullable()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {mangaId};
}