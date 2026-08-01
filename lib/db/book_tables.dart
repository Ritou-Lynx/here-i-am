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
