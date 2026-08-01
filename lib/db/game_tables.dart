import 'package:drift/drift.dart';

/// Imported SillyTavern character cards (role-play game cards).
///
/// Architecture guard: no FK to Memex card system. All cross-table
/// references are soft (text columns). This domain can be lifted out
/// independently.
class GameCharacterCards extends Table {
  TextColumn get id => text()(); // UUID v4

  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Full SillyTavern card JSON (character spec v2 or legacy).
  TextColumn get cardJson => text()();

  /// Local file path to extracted avatar image (nullable — cards may have none).
  TextColumn get avatarPath => text().nullable()();

  /// Original filename the user imported (e.g. "阿黛尔.json").
  TextColumn get sourceFilename => text().withDefault(const Constant(''))();

  IntColumn get importedAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {id};
}

/// A game session (one save-file).
///
/// Sessions support branching: when the user loads any historical
/// save_marker and continues, we create a new GameSession with
/// [parentSessionId] pointing at the origin and [branchFromMessageId]
/// marking the exact message where the branch diverged. This keeps
/// every branch as an independent, fully isolated session.
class GameSessions extends Table {
  TextColumn get id => text()(); // UUID v4

  /// Soft reference to [GameCharacterCards.id].
  /// Nullable so sessions survive card deletion.
  TextColumn get cardId => text().nullable()();

  /// Redundant copy of the card title for display after card deletion.
  TextColumn get cardTitle => text()();

  /// Full card JSON snapshot at session-creation time.
  /// Ensures the session always plays back with the original card,
  /// even if the user later edits or deletes the card from the library.
  TextColumn get cardSnapshotJson => text()();

  /// User-visible session title (auto-generated or user-renamed).
  TextColumn get sessionTitle => text()();

  /// 'active'  — in progress
  /// 'ended'   — game ended, summary generated
  /// 'archived'— soft-deleted (hidden from default list)
  TextColumn get status =>
      text().withDefault(const Constant('active'))();

  // ── Branching ────────────────────────────────────────────────────────────

  /// Parent session this one was branched from (null = root session).
  TextColumn get parentSessionId => text().nullable()();

  /// The [GameMessages.id] in [parentSessionId] at which this branch diverged.
  /// Messages in the new session start from a copy of all messages up to
  /// (and including) this point.
  IntColumn get branchFromMessageId => integer().nullable()();

  // ── Story state ──────────────────────────────────────────────────────────

  /// Arbitrary JSON blob the game agent may persist (lorebook state, flags…).
  /// Snapshotted on each save_marker.
  TextColumn get worldStateJson => text().nullable()();

  /// AI-generated story summary, produced when session ends (or on explicit save).
  TextColumn get storySummary => text().nullable()();

  /// Whether a game_log entry has already been injected into User-truth.
  BoolColumn get gameLogInjected =>
      boolean().withDefault(const Constant(false))();

  // ── Timestamps ───────────────────────────────────────────────────────────

  IntColumn get createdAt => integer()(); // seconds since epoch
  IntColumn get lastPlayedAt => integer()(); // seconds since epoch

  @override
  Set<Column> get primaryKey => {id};
}

/// Chat messages for a game session.
///
/// Kept completely separate from [PersonaChatMessages] so the game
/// context can never leak into companion memory queries.
class GameMessages extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Soft reference to [GameSessions.id].
  TextColumn get sessionId => text()();

  /// 'user' | 'assistant' | 'system'
  TextColumn get role => text()();

  TextColumn get content => text()();

  /// 'normal'      — regular in-character message
  /// 'ooc'         — out-of-character instruction from user
  /// 'save_marker' — synthetic marker inserted when user saves
  TextColumn get messageType =>
      text().withDefault(const Constant('normal'))();

  /// Human-readable label for save_marker messages (e.g. "第1章结束").
  /// Null for non-marker messages.
  TextColumn get savepointLabel => text().nullable()();

  IntColumn get timestamp => integer()(); // seconds since epoch
}
