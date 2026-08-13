import 'package:drift/drift.dart';

/// A book imported for co-reading (TXT now; EPUB/PDF later).
///
/// Architecture guard: no FK to Memex card system. All cross-table
/// references are soft (text columns). This domain can be lifted out
/// independently.
class Books extends Table {
  TextColumn get id => text()(); // UUID v4, matches server-side book id
  TextColumn get characterId => text()(); // companion who co-reads this book

  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get coverUrl => text().nullable()();

  TextColumn get format => text().withDefault(const Constant('txt'))();
  // 'txt' | 'epub' | 'pdf' (future)

  IntColumn get chapterCount => integer().withDefault(const Constant(0))();
  IntColumn get totalChars => integer().withDefault(const Constant(0))();

  TextColumn get splitMethod => text().nullable()();
  // 'pattern' | 'special' | 'size'
  TextColumn get splitPattern => text().nullable()();
  // e.g. '第X章', 'Chapter N', null for size-split

  TextColumn get status => text().withDefault(const Constant('active'))();
  // 'active' | 'removed'

  IntColumn get createdAt => integer()(); // seconds since epoch
  IntColumn get updatedAt => integer()();

  /// JSON array of TopicThread intent objects: [{threadId, threadTitle}]
  /// Set by user to route co-reading cleanup to specific Topic Threads.
  TextColumn get intentsJson =>
      text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A chapter within a book. Content is fetched from server on demand,
/// but we cache title + char count locally for the TOC.
class BookChapters extends Table {
  TextColumn get id => text()(); // '<bookId>_<number>'
  TextColumn get bookId => text()(); // → Books.id (soft ref)

  IntColumn get number => integer()(); // 1-indexed
  TextColumn get title => text()();
  IntColumn get chars => integer().withDefault(const Constant(0))();

  /// Cached chapter content (nullable — fetched lazily from server).
  TextColumn get content => text().nullable()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Reading progress — one row per book, upserted on scroll.
class BookReadingProgress extends Table {
  TextColumn get bookId => text()(); // → Books.id
  IntColumn get chapterNumber => integer().withDefault(const Constant(1))();
  /// Scroll offset ratio within the chapter (0.0 – 1.0) for precise resume.
  RealColumn get scrollRatio => real().withDefault(const Constant(0.0))();

  IntColumn get readAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {bookId};
}

/// AI pre-read notes for a chapter (generated server-side, cached locally).
class BookChapterNotes extends Table {
  TextColumn get id => text()(); // '<bookId>_<chapterNum>_note'
  TextColumn get bookId => text()(); // → Books.id
  IntColumn get chapterNumber => integer()();

  TextColumn get note => text()();
  // Short summary: characters, events, foreshadowing, chapter-end state

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A user-created highlight or note anchored to a stable character range.
///
/// This remains first-class reader data. It is deliberately not linked to
/// Memory V3: promotion into memory only happens through an explicit user
/// action, and a highlight without a note must not be treated as a belief.
class BookAnnotations extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get bookId => text()(); // → Books.id (soft ref)
  IntColumn get chapterNumber => integer()();

  IntColumn get startOffset => integer()(); // inclusive UTF-16 offset
  IntColumn get endOffset => integer()(); // exclusive UTF-16 offset
  TextColumn get quote => text()();
  TextColumn get prefixContext => text().withDefault(const Constant(''))();
  TextColumn get suffixContext => text().withDefault(const Constant(''))();
  TextColumn get contentFingerprint => text().withDefault(const Constant(''))();

  TextColumn get style => text().withDefault(const Constant('spring_rain'))();
  TextColumn get note => text().withDefault(const Constant(''))();

  IntColumn get createdAt => integer()(); // milliseconds since epoch
  IntColumn get updatedAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One bounded co-reading discussion window for a book or manga chapter.
///
/// This table deliberately stores only soft references. The persisted chat
/// rows remain the evidence of record; this row says which of those messages
/// were produced while the user was reading a specific work/chapter.
class CoReadingSessions extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get workType => text()(); // 'book' | 'comic'
  TextColumn get workId => text()();
  TextColumn get workTitle => text()();
  TextColumn get characterId => text()();
  TextColumn get chapterRef => text()(); // book chapter number / comic chapter id
  TextColumn get chapterTitle => text().withDefault(const Constant(''))();

  IntColumn get startedAt => integer()(); // milliseconds since epoch
  IntColumn get endedAt => integer().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  // 'active' | 'ready' | 'processing' | 'processed' | 'failed'
  IntColumn get processedAt => integer().nullable()();
  TextColumn get error => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Evidence links from a co-reading session to the shared companion chat.
class CoReadingSessionMessages extends Table {
  TextColumn get sessionId => text()(); // → CoReadingSessions.id (soft ref)
  IntColumn get messageId => integer()(); // → PersonaChatMessages.id (soft ref)
  /// Stable cross-device ID of the linked chat message, mirroring [messageId].
  /// Preferred for cross-device resolution; [messageId] stays as a local index.
  TextColumn get messageSyncId => text().nullable()();
  IntColumn get addedAt => integer()(); // milliseconds since epoch

  @override
  Set<Column> get primaryKey => {sessionId, messageId};
}
