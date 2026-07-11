/// Memory V3 Drift tables.
///
/// Authoritative design: docs/memory-research/MEMORY_PROPOSAL_V3.md
///
/// 这个文件下所有表都是 V3 体系的一部分，跟 lib/db/tables.dart 中的
/// SharedLifeEntities / SharedLifeEventOperations 等 V2 表并存但语义不同。
/// V3 表族永远不跟 V2 表建外键，迁移按 V3 § 15 渐进切换执行。
///
/// 命名规则：表名 PascalCase（Drift 自动转 snake_case 作为 SQL 表名）。
/// 所有派生物表必带 schemaVersion / generatedByVersion / userCorrected。
/// 所有原始资料表字段只能新增（nullable），不能删除或重命名。
library;

import 'package:drift/drift.dart';

// ============================================================================
// 一、用户确认资料层（Memory Card）—— V3 § 4
// ============================================================================

/// 当前有效卡片本体。`memoryScope` 仅允许 `user_truth` / `script_summary`。
///
/// `presentationModule` 是 Memory Summary Card 的 block JSON。
/// `retrievalText` 是给 I / embedding 读取的自然语言。
/// `needsFollowUp` 是 Chat agent 主动追问的入口（V3 § 9.7）。
class MemoryCards extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get memoryScope =>
      text().withDefault(const Constant('user_truth'))();
  TextColumn get type => text()(); // fact / event / task / schedule / plan
  TextColumn get title => text()(); // 系统识别字段，Summary Card 不显示
  TextColumn get dropletLabel => text()(); // 2-4 字极短识别词

  TextColumn get presentationModule => text()(); // JSON block 列表
  TextColumn get retrievalText => text()();

  RealColumn get valence => real()(); // -1.0 ~ 1.0
  RealColumn get arousal => real()(); // 0.0 ~ 1.0

  TextColumn get status => text()
      .nullable()(); // 仅 task/schedule/plan：active / completed / cancelled
  TextColumn get needsFollowUp =>
      text().nullable()(); // JSON [{field, question}]

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  IntColumn get createdAt => integer()(); // ms since epoch
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 原始输入上下文，每张卡 1 条对应记录。
class MemoryCardSources extends Table {
  TextColumn get cardId => text()(); // FK soft → memory_cards.id
  TextColumn get rawInput => text()();
  IntColumn get recordedAt => integer()(); // 记录动作发生时间，ms
  TextColumn get recordedPlace => text().nullable()();

  /// 指向 asset.id / chat_message.id / 外部批次 id 等。
  /// 软引用，不写 FK 约束。
  TextColumn get sourceRef => text().nullable()();

  /// 记录方式元数据：record_button / fab / natural_command / import / system 等。
  TextColumn get sourceKind => text()();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {cardId};
}

/// 可选机器计算字段。type 由 AI 按内容判断。
class MemoryCardStructuredFields extends Table {
  TextColumn get cardId => text()(); // FK soft → memory_cards.id
  TextColumn get structuredFieldsType =>
      text()(); // expense_entry / sleep_record / reading_item / ...

  /// JSON object。业务时间字段 (occurredAt / nextActionAt / dueAt / startAt /
  /// remindAt / paidAt / sleepStart 等) 都在这里。
  TextColumn get fieldsJson => text()();

  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get generatedByVersion => text().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {cardId};
}

/// 卡片显式关联（用户或 AI 通过自然语言修正建立）。
class MemoryCardRelations extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get fromCardId => text()(); // soft FK
  TextColumn get toCardId => text()(); // soft FK
  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Memory Card 与 Asset 多对多。
class MemoryCardAssets extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get cardId => text()(); // soft FK
  TextColumn get assetId => text()(); // soft FK
  TextColumn get role => text()(); // source / evidence / display
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 二、Dreaming 自动产物层 —— V3 § 5
// ============================================================================

/// Dreaming 抽出的事实碎片。第三人称、单条原子。
class MemoryFragments extends Table {
  TextColumn get id => text()();
  TextColumn get content => text()(); // ≤ 80 字
  TextColumn get sourceMessageIds => text().nullable()(); // JSON array<int>
  TextColumn get sourceScope => text()
      .withDefault(const Constant('main_chat'))(); // main_chat / script_session

  RealColumn get emotionalWeight =>
      real().withDefault(const Constant(0.0))(); // 0~1，单维度

  TextColumn get status => text().withDefault(
      const Constant('active'))(); // active / consolidated / ignored / deleted
  BoolColumn get isUserTruthCandidate =>
      boolean().withDefault(const Constant(false))();

  TextColumn get generatedByVersion => text().nullable()();
  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  IntColumn get createdAt => integer()();
  IntColumn get eventTime => integer().nullable()(); // ms since epoch; when the event actually happened (from source message timestamps)

  @override
  Set<Column> get primaryKey => {id};
}

/// 人物 / 地点 / 作品 / 项目 / 长期主题 / 设备 / 疾病。
/// 临时行为不算 entity。
class MemoryEntities extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()(); // 标准名
  TextColumn get category =>
      text()(); // person / place / event / project / hobby / work / object
  TextColumn get status => text().withDefault(
      const Constant('seed'))(); // seed / active / merged / hidden / deleted

  TextColumn get aliases => text().nullable()(); // JSON array
  TextColumn get overview => text().nullable()(); // 一句话概述
  TextColumn get relationshipToUser =>
      text().nullable()(); // family / friend / colleague / self / other

  IntColumn get firstMentionedAt => integer().nullable()();
  IntColumn get lastMentionedAt => integer().nullable()();
  IntColumn get fragmentCount => integer().withDefault(const Constant(0))();

  TextColumn get mergedIntoId => text().nullable()(); // 被合并时指向新 entity

  TextColumn get generatedByVersion => text().nullable()();
  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Fragment / Memory Card / Episode 与 Entity 的多对多。
class MemoryEntityLinks extends Table {
  TextColumn get id => text()();
  TextColumn get sourceTable =>
      text()(); // memory_fragments / memory_cards / memory_episodes
  TextColumn get sourceId => text()();
  TextColumn get entityId => text()();
  TextColumn get relation =>
      text()(); // mentioned / about / with / caused_by / located_at
  RealColumn get confidence => real().withDefault(const Constant(1.0))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 同一 entity 下多 fragment 凝结成的具体经历，第一人称叙事。
class MemoryEpisodes extends Table {
  TextColumn get id => text()();
  TextColumn get primaryEntityId => text()(); // soft FK → memory_entities.id
  TextColumn get topicId =>
      text().withDefault(const Constant('__ungrouped__'))();

  TextColumn get narrative => text()(); // 第一人称
  TextColumn get sourceFragmentIds => text()(); // JSON array

  IntColumn get significance => integer()(); // 1-10
  TextColumn get confidence => text()(); // high / medium / low

  RealColumn get valence => real()();
  RealColumn get arousal => real()();

  TextColumn get occurredAtRange => text().nullable()(); // JSON {start, end}，可空

  TextColumn get status => text().withDefault(
      const Constant('active'))(); // active / hidden / stale / deleted

  TextColumn get generatedByVersion => text().nullable()();
  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 跨 Episode 的长期叙事。允许一个主题多条 Saga 并存
/// （状态趋势 / 互动模式 / 重要事件叙事）。
class MemorySagas extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text()(); // 必须含"覆盖时段"

  TextColumn get episodeIds => text()(); // JSON array

  /// JSON {valence, arousal, connection}
  TextColumn get emotionalAxis => text()();

  TextColumn get status => text().withDefault(
      const Constant('active'))(); // active / hidden / merged / stale / deleted

  TextColumn get generatedByVersion => text().nullable()();
  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Saga 历史快照。Deep Dreaming 更新当前 Saga 前，把旧版复制一份到这里。
/// 不参与检索，只在用户查看历史时拉出。
class MemorySagaSnapshots extends Table {
  TextColumn get id => text()();
  TextColumn get sagaId => text()(); // 对应 memory_sagas.id

  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get episodeIds => text()();
  TextColumn get emotionalAxis => text()();

  TextColumn get generatedByVersion => text().nullable()();

  IntColumn get snapshotAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 三、原始资料与审计层 —— V3 § 6
// ============================================================================

/// 任何独立资源：图片 / 截图 / 音频 / 链接 / 健康同步批次 / 账单 / 订单 / 文件。
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get assetType =>
      text()(); // image / audio / link / health_sync / order / bill / file
  TextColumn get storagePath => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get originatorRef => text().nullable()(); // 聊天消息 id / 外部导入批次 id

  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  IntColumn get createdAt => integer()();
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Asset 上的识别结果。挂在 asset 而非 Memory Card，因为同一 asset 可能被
/// 多张卡引用。
class AssetAnalysis extends Table {
  TextColumn get id => text()();
  TextColumn get assetId => text()(); // soft FK
  TextColumn get analysisType =>
      text()(); // image_label / ocr / audio_transcript / link_extract / link_summary
  TextColumn get content => text()();
  TextColumn get modelProvider => text().nullable()();
  TextColumn get modelName => text().nullable()();
  BoolColumn get userCorrected =>
      boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 用户对任何 AI 派生物的修正记录。剥离机制的核心：
/// 换方案重生成派生物前必须先查这张表，对应字段有修正记录就用用户版本。
class UserCorrections extends Table {
  TextColumn get id => text()();
  TextColumn get targetTable =>
      text()(); // memory_cards / memory_episodes / memory_entities / memory_sagas / asset_analysis
  TextColumn get targetId => text()();
  TextColumn get field => text()(); // 改的字段名
  TextColumn get oldValue => text().nullable()(); // JSON
  TextColumn get newValue => text()(); // JSON
  TextColumn get correctionType =>
      text()(); // edit / reject / merge / split / confirm / hide

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// append-only 审计日志。仅供修订历史页面、撤销、系统维护使用。
/// **I 的任何工具都不可读取这张表。**
class MemoryCardOperations extends Table {
  TextColumn get id => text()();
  TextColumn get cardId => text()(); // soft FK
  TextColumn get operationType =>
      text()(); // create / update / delete / restore / correct / merge / split / derive
  TextColumn get payload => text()(); // JSON
  TextColumn get sourceKind =>
      text()(); // tool_call / record_button / fab / natural_command / import / system

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 四、索引 / 召回辅助 —— V3 § 7
// ============================================================================

/// 每次召回记录，用于 novelty penalty。
class MemoryRecallEvents extends Table {
  TextColumn get id => text()();
  TextColumn get targetTable =>
      text()(); // memory_cards / memory_episodes / memory_sagas
  TextColumn get targetId => text()();
  TextColumn get chatMessageId => text().nullable()();
  TextColumn get query => text().nullable()();
  RealColumn get score => real()();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// V3 embedding 表。区别于 V2 的 EntityEmbeddings：
/// 用 (targetTable, targetId) 复合 key，可以索引 Memory Card / Episode / Saga 等多种。
class MemoryEmbeddings extends Table {
  TextColumn get targetTable => text()();
  TextColumn get targetId => text()();
  BlobColumn get vector => blob()();
  TextColumn get provider => text()();
  TextColumn get model => text()();
  IntColumn get dimension => integer()();
  TextColumn get contentHash => text()(); // stale 判断
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {targetTable, targetId};
}
