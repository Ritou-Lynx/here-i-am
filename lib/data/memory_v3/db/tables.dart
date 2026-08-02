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
      text()(); // expense_entry / income_entry / sleep_record / reading_item / ...

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
  IntColumn get eventTime => integer()
      .nullable()(); // ms since epoch; when the event actually happened (from source message timestamps)

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

// ============================================================================
// 五、Project Memory 投影层 — i Continuity Gateway Phase 3
// ============================================================================

/// Policy-filtered current projection of one external project closeout.
///
/// This is deliberately separate from [MemoryCards]: project work is not
/// User-truth and must never enter ordinary life-memory candidate generation.
class ProjectMemoryItems extends Table {
  TextColumn get id => text()(); // stable Gateway event id
  TextColumn get projectId => text()(); // opaque user-level Gateway id
  TextColumn get projectKey => text()();
  TextColumn get itemType => text().withDefault(const Constant('closeout'))();
  TextColumn get summary => text()();
  TextColumn get decisionsJson => text().withDefault(const Constant('[]'))();
  TextColumn get openLoopsJson => text().withDefault(const Constant('[]'))();
  TextColumn get artifactRefsJson => text().withDefault(const Constant('[]'))();
  TextColumn get retrievalText => text()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get policyId => text()();
  IntColumn get policyVersion => integer().withDefault(const Constant(1))();
  TextColumn get memoryV3Policy => text()();
  TextColumn get sensitivity => text()();
  TextColumn get redactionState => text()();
  TextColumn get authority => text()();
  TextColumn get trustLevel => text()();
  IntColumn get occurredAt => integer()();
  IntColumn get receivedAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Provenance for a [ProjectMemoryItems] projection.
///
/// No transcript, shell output, diff, credential, or absolute path is stored.
class ProjectMemorySources extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text()(); // soft FK -> project_memory_items.id
  TextColumn get sourceEventId => text()();
  TextColumn get sourceUri => text()();
  TextColumn get sourceTool => text()();
  TextColumn get sourceSessionId => text()();
  TextColumn get contentHash => text()();
  IntColumn get receivedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 六、Life Insights — 跨 User-truth 聚合分析层
// ============================================================================
//
// Life Insights 是 V3 的分析层：读已有的 Memory Cards / COROS / Ledger 等原始
// 数据，产出结构化洞察（趋势/模式/基线/异常/预测），喂给三个消费者：
//   1. 观察面板 Insight Strip（展示）
//   2. Growth Pacts calibrate（推断合理目标）
//   3. Check-in snapshot（"该不该介入"信号）
//
// 现有 Insights Agent 是 Memex 遗产（读 Facts/PKM 文件系统），与此表无关。
// Dreaming 有意禁止下结论（NO CONCLUSIONS），不产出 insight。
// Record Organizer 只处理单条输入，不做跨卡片聚合。
// 这一层是全新的。

/// 每个洞察一行。按 (domain, insightType, period) 覆盖更新——同一周期同一
/// 类型重算时 overwrite，不 append。历史洞察通过 updatedAt 区间查询。
class LifeInsights extends Table {
  TextColumn get id => text()(); // UUID v4

  /// health | finance | schedule | reading | social | general
  TextColumn get domain => text()();

  /// trend | pattern | streak | baseline | anomaly | projection
  ///
  /// trend      — 时间趋势（"入睡时间在变早"）
  /// pattern    — 重复模式（"周日总超支"）
  /// streak     — 连续记录（"已连续 12 天早于 00:30"）
  /// baseline   — 能力基线（"稳定区间 23:45-00:45，极值 22:30"）
  /// anomaly    — 异常（"今天消费是平日 3 倍"）
  /// projection — 预测（"按当前速度月底读完 11 本，差目标 13 本"）
  TextColumn get insightType => text()();

  /// daily | weekly | monthly
  ///
  /// daily: 每天 1 条（如今日睡眠基线）
  /// weekly: 每周 1 条（如本周消费模式）
  /// monthly: 每月 1 条（如月度阅读进度预测）
  TextColumn get period => text()();

  /// 周期起始/结束，ms since epoch。
  /// 重算同一周期时用 (domain, insightType, period, periodStart) 做 upsert key。
  IntColumn get periodStart => integer()();
  IntColumn get periodEnd => integer()();

  /// 结构化数据点，JSON array[{date, value}]。
  /// 面板可用来画 sparkline；check-in 可用来判断趋势方向。
  /// 例：[{"date":"2026-07-20","value":"00:45"},{"date":"2026-07-21","value":"00:30"}]
  TextColumn get dataPointsJson => text().withDefault(const Constant('[]'))();

  /// 自然语言叙述，1-3 句。LLM 产出，给面板和 check-in 直接读。
  /// 例："最近一周入睡时间从 00:45 逐步提前到 23:50，趋势在变好，
  ///       但距离健康睡眠区间还有 20-50 分钟。"
  TextColumn get narrative => text()();

  /// 推断置信度 0.0-1.0。数据点少或矛盾时低。
  RealColumn get confidence => real().withDefault(const Constant(0.5))();

  /// 如果这条洞察暗示一个 Growth Pact（如"睡眠趋势→可建 habit pact"），
  /// 填一个 hint，供 GrowthPactService 消费。
  /// JSON: {suggestedKind, suggestedDomain, suggestedMetric}
  /// null = 无 pact 信号。
  TextColumn get pactSignalJson => text().nullable()();

  /// agent_inferred（默认，全靠 LLM 从数据推断）
  /// user_adjusted（用户看过后微调了 narrative 或 target）
  TextColumn get authority =>
      text().withDefault(const Constant('agent_inferred'))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 七、User Rhythms — 用户日常节律结构化层
// ============================================================================
//
// 这是"用户的生活是怎样的"的事实层。不设目标、不做判断，只结构化记录用户
// 当前阶段的作息、工作、课表等周期性节律。
//
// 来源：
//   - 对话信号（"我 7 点下班""周二有课"）→ Dreaming/Insights 推断
//   - COROS 数据（14 天睡眠中位数）→ 自动推断 sleep_pattern
//   - Memory Cards（schedule/task）→ 补充/验证
//
// 消费者：
//   - Check-in snapshot（"现在 06:00，用户通常 09:00 起，别打扰"）
//   - Life Insights（作为 baseline 推断输入）
//   - Growth Pacts（作为 target 的 dailyAdjust 依据，如"明天有早会→早点睡"）
//
// 中短期节律（实习 2-3 个月、兼职课表按学期）通过 validFrom/validUntil 管理
// 生命周期，过期自动淡出，不需要用户手动删除。

/// 每个节律一行。按星期几 + 时间段循环。
class UserRhythms extends Table {
  TextColumn get id => text()(); // UUID v4

  /// work_schedule | class_schedule | sleep_pattern | meal_pattern |
  /// exercise_pattern | commute_pattern | custom
  TextColumn get kind => text()();

  /// 自然语言描述，1 句话。
  /// 例："实习上班"、"私人中文接单"、"日常睡眠"
  TextColumn get description => text()();

  /// iCalendar RRULE 风格的循环规则，代码解析而非第三方库。
  /// 例：
  ///   "FREQ=DAILY;BYDAY=MO,TU,WE,TH,FR;10:00-19:00"  — 实习
  ///   "FREQ=WEEKLY;BYDAY=TU,FR,SU;22:00-23:30"       — 私人课
  ///   "FREQ=DAILY;01:00-09:00"                        — 睡眠窗口
  /// 对于不按星期循环的节律（如"每天 3 餐 8/12/18"），用 FREQ=DAILY。
  /// sleep_pattern 的 startTime/endTime 可跨午夜（如 23:30-07:00）。
  TextColumn get rrule => text()();

  /// home | office | remote | commute | unknown
  /// "在家上课"→ home，check-in 不会问"下课回家要多久"。
  TextColumn get location => text().withDefault(const Constant('unknown'))();

  /// 节律生效/失效时间，ms since epoch。null = 仍然有效。
  /// 用户说"实习结束了"→ validUntil 设为那天。新节律 validFrom 设为当天。
  IntColumn get validFrom => integer()();
  IntColumn get validUntil => integer().nullable()();

  /// agent_inferred（默认，从对话/数据推断）
  /// user_confirmed（用户明确确认过）
  /// user_adjusted（用户微调了 rrule 或时间）
  TextColumn get authority =>
      text().withDefault(const Constant('agent_inferred'))();

  /// 这个节律是怎么来的。
  /// conversation — 用户在聊天里说的
  /// data_pattern — 从 COROS/Ledger 数据模式推断的
  /// mixed — 两者都有
  TextColumn get origin => text().withDefault(const Constant('conversation'))();

  /// 推断置信度 0.0-1.0。对话只提 1 次 → 0.3；提 3 次 → 0.7；数据验证 → 0.9。
  RealColumn get confidence => real().withDefault(const Constant(0.5))();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 八、Growth Pacts — 成长契约（教练模式的目标/习惯/约定追踪层）
// ============================================================================
//
// Growth Pacts 是"用户对未来的自己有期待"的结构化载体。和 Topic Thread 一样
// 是活文档 + append-only 执行日志的模式，但面向"目标/习惯/约定"。
//
// 核心设计：target 是 agent_inferred 且可变的，不是用户手设的固定值。
// 林埃基于 Life Insights 推断的 baseline + dailyAdjust 形成当前生效目标，
// 用户可以微调（user_adjusted）但不需要主动设定。
//
// 生命周期：
//   emerging（开始注意模式）→ active（正式督促）→ calibrating（持续调整）
//   → achieved（达成）/ faded（不再相关）
//
// authority 分层（和 Topic Thread 一致）：
//   - target / baseline → agent_inferred（默认），user_adjusted（用户微调时）
//   - stakes（罚款/奖励）→ user_confirmed（严格，用户必须同意才能罚）
//   - check 记录 → agent_inferred（系统观察），user_confirmed（用户自报）

/// 每个 pact 一行（活文档）。target 是活的，随 Life Insights 重新推断而变。
class GrowthPacts extends Table {
  TextColumn get id => text()(); // UUID v4

  /// goal | habit | agreement
  ///
  /// goal      = 有终点的目标（"年底读 24 本""每天 10000 步"）
  /// habit     = 无终点的习惯（"11 点前睡""不刷短视频超 30min"）
  /// agreement = 用户和 AI 之间的约定（"连续 3 天没运动罚 10 元"）
  TextColumn get kind => text()();

  /// health | finance | schedule | reading | social | custom
  TextColumn get domain => text()();

  /// 1-2 句话描述这个 pact 是什么。
  /// 例："每天 11 点前睡觉"、"每周支出控制在 500 以内"、"连续 3 天没运动罚 10 元"
  TextColumn get description => text()();

  /// 推断的目标 JSON，agent_inferred 且可变。
  /// {
  ///   "baseline": {metric, range, period, confidence},
  ///   "current":  {metric, range, period},
  ///   "dailyAdjust": [{"date","adjustedRange","reason"}],
  ///   "confidence": 0.0-1.0
  /// }
  ///
  /// baseline: Life Insights 推断的历史基线（如"稳定入睡 23:45-00:45"）
  /// current:  当前生效目标（可能被 dailyAdjust 临时调整）
  /// dailyAdjust: 每日动态调整记录（如"明天有早会→今晚 23:15"）
  TextColumn get targetJson => text().withDefault(const Constant('{}'))();

  /// 赏罚 JSON，user_confirmed（严格）。
  /// {
  ///   "penaltyPerMiss": 10,       // 每次 miss 罚多少 CNY
  ///   "rewardPerHit": 0,          // 每次 hit 奖多少
  ///   "maxPenaltyWeek": 50,       // 每周罚款上限
  ///   "graceStreak": 3            // 连续 miss 多少次才开始罚
  /// }
  /// null = 无赏罚约定（纯习惯督促，不涉及钱）。
  TextColumn get stakesJson => text().nullable()();

  /// emerging | active | paused | achieved | faded | abandoned
  ///
  /// emerging  — 林埃注意到模式，pact 已创建但还没正式督促
  /// active    — 正式督促中，check-in 会注入
  /// paused    — 用户或 AI 暂停（如出差/生病）
  /// achieved  — 达成（habit 不会 achieved，只有 goal 会）
  /// faded     — 长期不相关，淡出
  /// abandoned — 用户明确放弃
  TextColumn get status =>
      text().withDefault(const Constant('emerging'))();

  /// agent_inferred（默认）| user_adjusted（用户微调过 target）
  TextColumn get authority =>
      text().withDefault(const Constant('agent_inferred'))();

  /// 这个 pact 怎么来的。
  /// conversation — 用户在聊天里表达了期待（"我想早睡"）
  /// data_pattern — Life Insights 从数据模式发现的（"连续 14 天晚睡"）
  /// mixed — 两者都有
  TextColumn get origin => text().withDefault(const Constant('conversation'))();

  /// 上次重新推断 target 的时间。Dreaming/Insights 跑时顺带 re-calibrate。
  IntColumn get lastCalibratedAt => integer().nullable()();

  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Pact 执行日志，append-only。每次 check-in 检查 pact 状态时追加一行。
class GrowthPactChecks extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get pactId => text()(); // soft FK → growth_pacts.id

  /// 检查时间，ms since epoch
  IntColumn get checkedAt => integer()();

  /// hit | miss | partial | skipped
  ///
  /// hit     — 达到目标（23:30 前睡了）
  /// miss    — 未达到（01:40 才睡）
  /// partial — 部分达到（23:45 睡，目标 23:30，差 15 分钟）
  /// skipped — 本次跳过（用户暂停了 pact / 数据不足无法判断）
  TextColumn get result => text()();

  /// 实际值（自由格式，按 pact domain 约定）。
  /// 例："01:40"（入睡时间）、"6800"（步数）、"520"（消费）
  TextColumn get actualValue => text().nullable()();

  /// 本次对比的目标值（可能被 dailyAdjust 调整过）。
  /// 例："23:30"（原目标）、"23:15"（今日调整后）
  TextColumn get targetValue => text().nullable()();

  /// 证据 JSON，软引用 Memory Card。
  /// [{"cardId":"...","note":"COROS sleep record"}]
  TextColumn get evidenceJson =>
      text().withDefault(const Constant('[]'))();

  /// 如果本次 miss 触发了罚款，填 AiFinanceLedger 行的 ID。null = 无罚款。
  TextColumn get penaltyLedgerId => text().nullable()();

  /// 如果本次 hit 触发了奖励，填 AiFinanceLedger 行的 ID。null = 无奖励。
  TextColumn get rewardLedgerId => text().nullable()();

  /// checkin — check-in pulse 检查
  /// user_report — 用户主动汇报
  /// auto_detected — 系统自动检测（如 COROS 同步后）
  TextColumn get sourceType =>
      text().withDefault(const Constant('checkin'))();

  /// agent_inferred（系统判断）| user_confirmed（用户确认）
  TextColumn get authority =>
      text().withDefault(const Constant('agent_inferred'))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ============================================================================
// 九、Topic Thread 话题追踪层 — docs/memory-research/TOPIC_THREAD_DESIGN.md
// ============================================================================

/// 长期话题追踪主文档（活文档）。
///
/// 每个 TopicThread 代表用户持续关注的一个话题，随着时间和阅读/对话积累而演进。
/// 治理独立于 i Gateway Project Memory，不需要项目注册。
/// corePositions 只能由用户确认更新（user_confirmed），不允许 AI 自主写入。
class TopicThreads extends Table {
  TextColumn get id => text()(); // UUID v4, stable
  TextColumn get title => text()(); // 话题名，用户命名

  /// 当前思考所在阶段（一句话）。agent_inferred + user_confirmed。
  TextColumn get currentStage => text().withDefault(const Constant(''))();

  /// 已确认的洞察/立场。JSON array<String>。严格 user_confirmed。
  TextColumn get corePositionsJson =>
      text().withDefault(const Constant('[]'))();

  /// 还没想清楚的问题。JSON array<String>。agent_inferred + user_confirmed。
  TextColumn get openQuestionsJson =>
      text().withDefault(const Constant('[]'))();

  /// 逗号分隔标签，用于粗粒度分类和检索。
  TextColumn get tags => text().withDefault(const Constant(''))();

  /// active | paused | archived
  TextColumn get status =>
      text().withDefault(const Constant('active'))();

  IntColumn get lastDiscussedAt => integer().nullable()(); // ms since epoch
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 每次与某话题相关的讨论摘要（append-only）。
///
/// [sourceType] 标记来源类型：chat | book_reading | comic_reading |
/// project_work | standalone
/// [linkedCardIds] 和 [linkedProjectMemoryIds] 是软引用（无 FK 约束）。
/// [authority] 标记写入权限级别：user_confirmed | agent_inferred
class TopicThreadSessions extends Table {
  TextColumn get id => text()(); // UUID v4
  TextColumn get threadId => text()(); // soft FK → topic_threads.id

  IntColumn get occurredAt => integer()(); // 讨论时间戳，ms since epoch

  /// 这次讨论了什么、得出什么（≤200 字）。
  TextColumn get summary => text()();

  /// chat | book_reading | comic_reading | project_work | standalone
  TextColumn get sourceType =>
      text().withDefault(const Constant('chat'))();

  /// 来源引用 JSON：{ bookTitle?, chapterTitle?, mangaId?, chapterId?,
  /// projectKey?, note? }
  TextColumn get sourceRefJson =>
      text().withDefault(const Constant('{}'))();

  /// 关联 Memory Card IDs。JSON array<String>，软引用，无 FK 约束。
  TextColumn get linkedCardIds =>
      text().withDefault(const Constant('[]'))();

  /// 关联 ProjectMemoryItem IDs。JSON array<String>，软引用，无 FK 约束。
  /// 访问时按原始项目政策解引用（personal_full 全文，work_redacted 脱敏）。
  TextColumn get linkedProjectMemoryIds =>
      text().withDefault(const Constant('[]'))();

  /// user_confirmed | agent_inferred
  TextColumn get authority =>
      text().withDefault(const Constant('agent_inferred'))();

  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
