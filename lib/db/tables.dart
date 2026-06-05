import 'package:drift/drift.dart';

/// Tasks Table
/// Stores persistent background tasks
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get payload => text().nullable()();
  TextColumn get status =>
      text()(); // pending, processing, completed, failed, retrying
  IntColumn get priority => integer().withDefault(const Constant(0))();

  // Timestamps
  IntColumn get createdAt => integer().nullable()();
  IntColumn get scheduledAt => integer().nullable()(); // timestamp
  IntColumn get completedAt => integer().nullable()();
  IntColumn get updatedAt => integer().nullable()();

  // Retry logic
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  IntColumn get maxRetries => integer().withDefault(const Constant(3))();

  TextColumn get error => text().nullable()();
  TextColumn get result => text().nullable()();
  TextColumn get bizId => text().nullable()();
  TextColumn get dependencies => text().nullable()(); // JSON list of task IDs

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-Value Store Table
/// For simple persistent storage
class KvStore extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  TextColumn get bucket => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Agent Activity Messages Table
/// Stores history of agent status updates
class AgentActivityMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  // 'tool_call', 'thought', 'info', 'error', 'warn', 'plan'
  TextColumn get type => text()();
  TextColumn get title => text()();
  TextColumn get content => text().nullable()();
  TextColumn get icon => text().nullable()();
  TextColumn get agentName => text().withDefault(const Constant('Unknown'))();
  TextColumn get agentId => text().nullable()();
  TextColumn get scene => text().nullable()();
  TextColumn get sceneId => text().nullable()();
  TextColumn get userId => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
}

/// Card Metadata Cache Table
/// Stores extracted metadata for quick filtering and querying
class CardCache extends Table {
  TextColumn get factId => text()(); // Primary Key: yyyy/mm/dd.md#ts_n
  TextColumn get cardPath => text()(); // Relative path or absolute path
  IntColumn get timestamp => integer()(); // Seconds since epoch
  TextColumn get tags => text()(); // JSON list of string tags

  @override
  Set<Column> get primaryKey => {factId};
}

/// System Actions Table
/// Stores system-level actions (e.g. Calendar, Reminders) waiting for user confirmation
class SystemActions extends Table {
  TextColumn get id => text()(); // Primary Key: uuid
  TextColumn get actionType => text()(); // 'calendar', 'reminder'
  TextColumn get actionData =>
      text().nullable()(); // JSON payload (title, start_time, etc.)
  TextColumn get status =>
      text()(); // 'pending', 'completed', 'failed', 'rejected'
  TextColumn get factId => text().nullable()(); // Associated fact_id
  IntColumn get createdAt => integer().nullable()(); // Seconds since epoch
  IntColumn get updatedAt => integer().nullable()(); // Seconds since epoch

  @override
  Set<Column> get primaryKey => {id};
}

/// Clarification Requests Table
/// Stores agent-created questions that need a lightweight user answer.
class ClarificationRequests extends Table {
  TextColumn get id => text()();
  TextColumn get question => text()();
  TextColumn get responseType =>
      text()(); // confirm, single_choice, multi_choice, short_text
  TextColumn get options => text().nullable()(); // JSON list
  TextColumn get status =>
      text()(); // pending, answered, completed, dismissed, failed, expired
  TextColumn get answerData => text().nullable()(); // JSON payload
  TextColumn get entityType => text().nullable()();
  TextColumn get entityLabel => text().nullable()();
  TextColumn get evidenceFactIds => text().nullable()(); // JSON list
  TextColumn get reason => text().nullable()();
  TextColumn get impact => text().nullable()();
  RealColumn get confidence => real().nullable()();
  TextColumn get proposedMemory => text().nullable()();
  TextColumn get resolutionTarget =>
      text().nullable()(); // auto, memory, pkm, card, insight, none
  TextColumn get sourceAgent => text().nullable()();
  TextColumn get dedupeKey => text().nullable()();
  TextColumn get factId => text().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get createdAt => integer().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  IntColumn get answeredAt => integer().nullable()();
  IntColumn get expiresAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Generic per-user notification table. Producer writes rows keyed by
/// (userId, notificationType, subjectKey). Physical delete model:
/// dismissing a notification removes its row. At most one row per triple,
/// enforced by a UNIQUE index.
class UserNotifications extends Table {
  /// UUID v4 string.
  TextColumn get id => text()();
  TextColumn get userId => text()();

  /// Open string namespace. First value: 'card_detail_update'.
  TextColumn get notificationType => text()();

  /// Type-specific aggregation key. For card_detail_update: factId.
  TextColumn get subjectKey => text()();

  /// Opaque JSON blob defined by the producer. Null allowed.
  TextColumn get payload => text().nullable()();

  /// Seconds since epoch.
  IntColumn get createdAt => integer()();

  /// Seconds since epoch.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// System Message Queue Table
/// Stores AI-initiated system triggers (checkin pulses, AI-created reminders).
/// Processed by the agent in foreground turns, one at a time.
class SystemMessageQueue extends Table {
  TextColumn get id => text()();
  TextColumn get triggerType => text()();
  TextColumn get body => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get createdAt => integer()();
  IntColumn get scheduledFor => integer().nullable()();
  IntColumn get processedAt => integer().nullable()();
  TextColumn get context => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Persona Chat Messages Table
/// Stores chat messages between user and their AI companion character.
class PersonaChatMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get characterId => text()();
  BoolColumn get isFromCharacter => boolean()();
  TextColumn get content => text()();
  TextColumn get factId => text().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();
  DateTimeColumn get timestamp => dateTime()();

  /// Message type: 'chat' (default) or 'action' (narrative/action description).
  TextColumn get messageType => text().withDefault(const Constant('chat'))();

  /// JSON-encoded list of attachment objects, e.g.
  /// [{"mimeType": "image/webp", "base64": "..."}]
  /// Null for text-only messages.
  TextColumn get attachmentsJson => text().nullable()();
}

/// Per-character extraction cursor for asynchronous conversation capture.
///
/// Queued and extracted IDs are separate so a failed background task can be
/// retried without losing messages that arrived while it was running.
class ConversationCaptureCursors extends Table {
  TextColumn get characterId => text()();
  IntColumn get lastExtractedMessageId =>
      integer().withDefault(const Constant(0))();
  IntColumn get lastQueuedMessageId =>
      integer().withDefault(const Constant(0))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {characterId};
}

/// Append-only operation log extracted from companion conversations.
///
/// Undo is represented by an additional `undo` row that points at the original
/// operation. Existing evidence rows are never rewritten or deleted.
class SharedLifeEventOperations extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get entityId => text()(); // UUID v4
  TextColumn get operationType => text()();
  TextColumn get entityType => text()();
  TextColumn get title => text()();
  TextColumn get patchJson => text()();
  TextColumn get sourceMessageIds => text()(); // JSON list<int>
  TextColumn get sourceCharacterId => text()();
  TextColumn get captureTaskId => text().nullable()();
  TextColumn get revertsOperationId => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Current-state projection rebuilt from [SharedLifeEventOperations].
class SharedLifeEntities extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get entityType => text()();
  TextColumn get title => text()();
  TextColumn get stateJson => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get sourceCharacterId => text()();
  TextColumn get lastOperationId => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI Finance Ledger Table
/// Records every income/cost/loan/repayment event that belongs to the AI companion.
/// This is a derived view of the user's finances — each entry is either linked to
/// a real transaction card (via soft nullable factId) or entered manually via chat.
/// The user's primary account is never modified; this table is additive only.
class AiFinanceLedger extends Table {
  TextColumn get id => text()(); // UUID v4

  /// The character this ledger entry belongs to.
  TextColumn get characterId => text()();

  /// Entry type: 'income' | 'cost' | 'loan' | 'repayment'
  /// - income: AI earned a share of a real income event
  /// - cost: an expense tagged as AI-related (e.g. Claude subscription)
  /// - loan: AI's costs exceeded its balance; user covered the gap
  /// - repayment: AI repaid a previous loan from its balance
  TextColumn get entryType => text()();

  /// Full amount of the original event (e.g. total income before split).
  /// For cost/loan/repayment entries this equals aiAmount.
  RealColumn get totalAmount => real()();

  /// The portion that belongs to the AI (after contribution split, if applicable).
  RealColumn get aiAmount => real()();

  /// AI's contribution ratio for income splits (0.0–1.0). Null for cost/loan/repayment.
  RealColumn get contributionRatio => real().nullable()();

  /// Free-text description of what the user contributed.
  TextColumn get myContributionDesc => text().nullable()();

  /// Free-text description of what the AI contributed.
  TextColumn get aiContributionDesc => text().nullable()();

  /// Purpose or label (e.g. "Claude Pro 月费", "写作项目分成").
  TextColumn get purpose => text().nullable()();

  /// Soft reference to the corresponding transaction card's factId.
  /// Nullable — manual entries may not have a linked card.
  TextColumn get linkedFactId => text().nullable()();

  /// Seconds since epoch when this entry was recorded.
  IntColumn get recordedAt => integer()();

  /// Any extra notes from the conversation.
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI Purchase Log Table
/// Records every purchase attempt made by the AI companion, from search to payment.
/// Status flow: searching → selected → ordering → payment_pushed → completed | failed | aborted
class AiPurchaseLog extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get characterId => text()();

  /// 'manual_approval' | 'auto_silent' (future)
  TextColumn get paymentMode => text()();

  /// 'searching' | 'selected' | 'ordering' | 'payment_pushed' | 'completed' | 'failed' | 'aborted'
  TextColumn get status => text()();

  /// The user's original purchase instruction verbatim.
  TextColumn get userInstruction => text()();

  TextColumn get productPlatform =>
      text().withDefault(const Constant('taobao'))();
  TextColumn get productId => text().nullable()();
  TextColumn get productTitle => text().nullable()();
  TextColumn get productUrl => text().nullable()();

  /// Estimated or confirmed price in CNY.
  RealColumn get priceCny => real().nullable()();

  /// Alipay cashier URL (cashier*.alipay.com or *excashier*.alipay.com).
  TextColumn get cashierUrl => text().nullable()();

  /// Reason for failure or abort (budget exceeded, whitelist violation, etc.).
  TextColumn get failureReason => text().nullable()();

  /// Soft link to AiFinanceLedger id — reserved for future finance integration.
  TextColumn get linkedLedgerId => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Voice Call Sessions — one row per call.
class VoiceCallSessions extends Table {
  TextColumn get id => text()(); // UUID
  TextColumn get characterId => text()();
  TextColumn get userId => text()();
  IntColumn get startedAt => integer()(); // epoch seconds
  IntColumn get endedAt => integer().nullable()();

  /// Key-facts summary written by post-call LLM pass (B plan).
  TextColumn get summary => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Voice Call Messages — each spoken turn within a session.
class VoiceCallMessages extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();

  /// 'user' or 'companion'
  TextColumn get role => text()();
  TextColumn get content => text()();
  IntColumn get createdAt => integer()(); // epoch seconds
}
