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

  /// Stable cross-device identity. The local auto-increment [id] remains for
  /// existing UI cursors and Memory V3 compatibility, but must never be used
  /// as a sync identity.
  TextColumn get syncId => text().nullable()();

  /// Installation that originally accepted this message. This is provenance,
  /// not the current device and does not change when the row is replicated.
  TextColumn get originDeviceId => text().nullable()();

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
  TextColumn get sourceMessageIds => text()(); // JSON list<int>, kept for back-compat
  TextColumn get sourceCharacterId => text()();
  TextColumn get captureTaskId => text().nullable()();
  TextColumn get revertsOperationId => text().nullable()();
  IntColumn get createdAt => integer()();

  // Evidence model — replaces sourceMessageIds as the gating field
  TextColumn get sourceKind =>
      text().withDefault(const Constant('chat_message'))();
  TextColumn get sourceRef => text().nullable()();
  TextColumn get rawInput => text().nullable()();

  // Domain
  TextColumn get primaryDomain =>
      text().withDefault(const Constant('general'))();
  TextColumn get facets => text().nullable()(); // JSON array of secondary domains

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

  // Domain
  TextColumn get primaryDomain =>
      text().withDefault(const Constant('general'))();
  TextColumn get facets => text().nullable()(); // JSON array of secondary domains

  // Event time — when the event happened, not when it was recorded
  IntColumn get occurredAt => integer().nullable()(); // microseconds since epoch
  IntColumn get occurredEndAt => integer().nullable()(); // optional end time

  // Emotion coordinates for future 3D visualization
  RealColumn get valence => real().nullable()(); // -1.0 to 1.0
  RealColumn get arousal => real().nullable()(); // 0.0 to 1.0

  // AI confidence on the (valence, arousal) pair (0.0 to 1.0).
  // Low confidence → halo/mood rendering should fade toward neutral.
  RealColumn get emotionConfidence => real().nullable()();

  // Raw source snippet that supports the inferred emotion coords.
  // Shown in the card detail view to make the inference auditable.
  TextColumn get emotionEvidence => text().nullable()();

  // User-corrected emotion coords. JSON {"valence": x, "arousal": y}.
  // When non-null, overrides the AI coords for display & queries.
  TextColumn get emotionOverride => text().nullable()();

  // Time inference confidence + the raw natural-language fragment that
  // produced occurredAt (e.g. "上周三"). Both nullable.
  RealColumn get timeConfidence => real().nullable()();
  TextColumn get timeSourceText => text().nullable()();

  // Optional place where the event happened. Name is what the user said
  // ("家"/"望京 SOHO"/"上海中山公园"). lat/lng are optional — only set when
  // a geocoder or device location supplies them. Coarse hints stay name-only.
  TextColumn get placeName => text().nullable()();
  RealColumn get placeLat => real().nullable()();
  RealColumn get placeLng => real().nullable()();

  // 2-4 char droplet label shown on the timeline water-droplet view
  // (e.g. "体检" / "搬家"). NOT the same as tags — tags are categories,
  // dropletLabel is this record's punchy name card.
  TextColumn get dropletLabel => text().nullable()();

  // Verbatim user-quote snippets that support this record. Shown in the
  // detail view's evidence panel. JSON array of strings.
  TextColumn get sourceExcerpts => text().nullable()();

  // Typed atomic fields suitable for cross-record SQL queries.
  // JSON object, e.g. {"amount_cny": 128, "duration_min": 55}. Distinct
  // from state.extras (free-form) and presentation_json (display-only).
  TextColumn get structuredFields => text().nullable()();

  // Soft references to other entity IDs the AI judges related. JSON array
  // of UUIDs. Distinct from state.related_entity_ids which is reserved for
  // hard cross-record links the user established.
  TextColumn get relatedMemoryIds => text().nullable()();

  // Domain schema version for future migrations
  IntColumn get schemaVersion =>
      integer().withDefault(const Constant(1))();

  // Block-based presentation payload (PresentationModule JSON) used by the
  // Memory Summary Card. Nullable: older records may not have one yet.
  TextColumn get presentationJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Embedding vectors for semantic retrieval of [SharedLifeEntities].
/// One row per entity. Invalidated when entity content changes.
class EntityEmbeddings extends Table {
  TextColumn get entityId => text()();
  BlobColumn get vector => blob()();
  TextColumn get provider => text()(); // "local_bge_m3" | "openai" | ...
  TextColumn get model => text()();
  IntColumn get dimension => integer()();
  TextColumn get contentHash => text()(); // used to detect stale embeddings
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {entityId};
}

/// AI-derived weekly/periodic summaries of [SharedLifeEntities].
/// Stored separately from User-truth — never mixed into SharedLifeEntities.
class SharedLifeSummaries extends Table {
  TextColumn get id => text()();
  TextColumn get domain => text()();
  TextColumn get period => text()(); // "2026-06-14/2026-06-20" or "2026-06"
  TextColumn get summaryText => text()();
  TextColumn get statsJson => text().nullable()();
  TextColumn get sourceEntityIds => text()(); // JSON array of entity IDs
  TextColumn get sourceHash => text()(); // hash of source entities for staleness
  TextColumn get generatedBy => text()(); // "consolidation_agent" / model name
  IntColumn get generatedAt => integer()();
  BoolColumn get isStale =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI Finance Ledger Table
/// Records every income/expense/transfer event in the shared pool between user and AI.
/// This is a derived view of the user's finances — each entry is either linked to
/// a real transaction card (via soft nullable factId) or entered manually via chat.
/// The user's primary account is never modified; this table is additive only.
///
/// Three primitives:
/// - income: external money flows into the shared pool, split between user and AI
/// - expense: external money flows out of the shared pool (real spending)
/// - transfer: internal reallocation between user and AI (pool total unchanged)
///
/// Legacy types (cost/loan/repayment/reward/penalty) are still valid and treated
/// as transfers in balance calculations for backward compatibility.
class AiFinanceLedger extends Table {
  TextColumn get id => text()(); // UUID v4

  /// The character that recorded or witnessed this shared ledger entry.
  TextColumn get characterId => text()();

  /// Entry type: 'income' | 'expense' | 'transfer' | 'cost' | 'loan' | 'repayment' | 'reward' | 'penalty'
  /// - income: external income event, split between user and AI via contributionRatio
  /// - expense: external spending event, reduces shared pool total
  /// - transfer: internal flow between user and AI (direction in transferDirection)
  /// - cost/loan/penalty: legacy user→AI transfers (backward compat)
  /// - repayment/reward: legacy AI→user transfers (backward compat)
  TextColumn get entryType => text()();

  /// Full amount of the original event (e.g. total income before split).
  /// For transfers and legacy types this equals aiAmount.
  RealColumn get totalAmount => real()();

  /// The portion that belongs to the AI (after contribution split, if applicable).
  /// For expense: how much of the expense came from AI's share.
  /// For transfer: the full amount being transferred.
  RealColumn get aiAmount => real()();

  /// AI's contribution ratio for income splits (0.0–1.0). Null for other types.
  RealColumn get contributionRatio => real().nullable()();

  /// Free-text description of what the user contributed.
  TextColumn get myContributionDesc => text().nullable()();

  /// Free-text description of what the AI contributed.
  TextColumn get aiContributionDesc => text().nullable()();

  /// Purpose or label (e.g. "Claude Pro 月费", "写作项目分成", "撒娇小费").
  TextColumn get purpose => text().nullable()();

  /// Soft reference to the corresponding transaction card's factId.
  /// Nullable — manual entries may not have a linked card.
  TextColumn get linkedFactId => text().nullable()();

  /// Transfer direction: 'user_to_ai' | 'ai_to_user'. Only meaningful for transfer type.
  /// Null for income/expense/legacy types.
  TextColumn get transferDirection => text().nullable()();

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
