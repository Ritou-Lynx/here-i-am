# W5 Phase 2 Handoff — Orchestration 编排层完成

> 工作流：W5 AI Orchestration Phase 2
> 状态：编排层完成（纯 domain，无 UI），真实 Agent 执行器待 Phase 3
> 完成日期：2026-08-16
> 分支：codex/w5-orchestration
> 基线：v3-lab @ d6910cdc（含 W6 v2 集成基座，未改数据库迁移）

## 1. 已完成交付

### 1.1 编排层五件套（`lib/domain/whiteboard/orchestration/`）

| 文件 | 内容 |
|---|---|
| `intent_classifier.dart` | 规则 + 关键词打分分类 → `TaskIntent`（TaskType / confidence / matchedKeywords）；平局按优先级裁决（media > debugging > coding > content > research > link > planning > whiteboard） |
| `model_router.dart` | `ModelConfig.fromJson` + `ModelRouter.selectModel`：primary → fallback → local 三级链 + 额度检查（used >= total 视为耗尽；无 quota_key 的模型 fail-open 不限量）；配置读 `~/.hereiam/whiteboard/model_config.json`（`fromHomeConfigFile` / `fromFile`，缺文件抛带指引的 StateError） |
| `task_router.dart` | 固定路由表 `TaskRouter.fixedRouteTable`（coding/debugging → coding-agent、contentGeneration → content-agent、其余 → self）+ `registerExecutor` 按名注册 + `dispatch`；`TaskExecutor` / `TaskExecutionRequest` / `TaskExecutionResult`（含 `extra` 传递类型特定数据）；`InlineSelfExecutor` 林埃自执行占位 |
| `result_compressor.dart` | `ResultCompressor.compress`：长摘要截断（200 字符 + 省略号、空白折叠、decisions ≤5 / artifactRefs ≤8）+ `composeReply` 组装回复文本 |
| `lin_ai_orchestrator.dart` | `LinAiOrchestrator`：`classifyIntent` / `routeTask` / `selectModel` / `compressResult` 各环节独立暴露 + `handleUserMessage` 端到端闭环；产出 `OrchestrationOutcome`（reply / taskId / operations / modelSelection / compressed / status）；`ConversationTurnRecord` + `ConversationLogWriter` 接口 |

### 1.2 Agent 接口占位（`lib/domain/whiteboard/agents/`）

- `coding_agent.dart`：`CodingAgent` 接口 + `CodingRequest/CodingResult` + `MockCodingAgent` + `CodingAgentExecutor`（TaskExecutor 适配）。真实实现接线 Dev Room Bridge（Phase 3）。
- `content_agent.dart`：`ContentAgent` 接口 + `ContentRequest/ContentResult/GeneratedCardDraft`（含 fromJson/toJson）+ `MockContentAgent` + `ContentAgentExecutor`。

### 1.3 Canvas Action Log（Huabu 借鉴 § 2，`orchestration/canvas_action_log.dart`）

- `NodeRef`（id/type/label 三键硬约束，fromJson 拒绝多余键）+ `CanvasActionKind` + `CanvasActionEntry`（append-only 最小单元）；
- `CanvasActionLog` 接口 + `ThresholdCanvasActionLog` 内存实现：成功计数达阈值（默认 50）触发一次 `CanvasActionConsumer.consume(batch)` 后清零；**失败请求不计数**；消费端（记忆策展器）接口占位，Phase 3 接持久化与压缩分析。

### 1.4 Memory V3 写回（数据层）

- `lib/data/memory_v3/services/orchestration_chat_writer.dart`：`PersonaChatLogWriter`（ConversationLogWriter 的 Drift 实现）→ 写 PersonaChatMessages（含 taskRoomId 软引用），**不写任何 User-truth**。

### 1.5 测试（`test/domain/whiteboard/orchestration/`，57 项全通过）

| 文件 | 覆盖 |
|---|---|
| `intent_classifier_test.dart` | 13 项：各类型分类、平局裁决、单关键词置信度、未知/空 → other、大小写不敏感 |
| `model_router_test.dart` | 10 项：配置解析、primary/fallback/local 三级、全耗尽抛错、fail-open、未配置回落、文件加载/缺失 |
| `task_router_test.dart` | 9 项：固定路由表、按名注册派发、extra 草稿传递、覆盖注册、未注册抛错、InlineSelf |
| `result_compressor_test.dart` | 6 项：短摘要保留、长摘要截断、限量、空白折叠、回复组装 |
| `canvas_action_log_test.dart` | 8 项：append-only、失败不计数、阈值触发一次即清零、NodeRef 三键守卫（JSON 级内容键扫描）、fromJson 拒绝内容键 |
| `lin_ai_orchestrator_e2e_test.dart` | 11 项：端到端（房间 completed + 对话两回合 + Artifact + 回复）、coding 路由、unknown → self、失败房间、fallback 提示与 context 记录、无配置降级、状态机非法转移被拒、**User-truth 守卫（memory_cards 为空）**、**跨边界契约（WhiteboardOperation 往返 / actor=i / 授权 = taskId / place / payload 无内容）** |

### 1.6 验证结果

- `flutter test test/domain/whiteboard/`：200 项全通过（57 新增 + W0/W1/W2/W3/W4 既有 143 项零回归）；
- `flutter test test/data/memory_v3/services/task_room_* test/db/task_room_migration_real_test.dart test/db/whiteboard_migration_test.dart`：42 项全通过；
- `dart analyze lib/domain/whiteboard lib/data/memory_v3/services/orchestration_chat_writer.dart test/domain/whiteboard`：零 error/warning；
- 注：`record_organizer_service_test.dart` 的 `updateCard` 时间戳断言在**基线 v3-lab 上也失败**（毫秒级 flaky，预存在，与本次无关）。

---

## 2. 架构决策记录

### 2.1 编排产出 WhiteboardOperation[]，走与用户操作同一条执行路径（Huabu 三层命令架构）

- 内容生成 + 指定目标板时，编排器产出 `place` 操作（actor=`i`、**authorizationId = taskId**——任务由用户消息显式发起即本轮授权）；payload 只带 card_id / card_kind 元数据；inverse 为 remove。
- Phase 2 只**产出**操作（可审计、可往返、过 W0 契约测试）；实际应用执行器由 Task B（W1 集成窗口）提供，Phase 3 接线。

### 2.2 Canvas Action Log 只存 NodeRef，绝不存节点内容

- 与 Huabu 同一隐私线；NodeRef.fromJson 硬拒绝多余键 + 测试做 JSON 级字符串扫描守卫。
- **失败请求不追加**（比 Huabu 更收敛：失败行为连日志都不留，只保留可审计成功流），阈值计数只算成功。

### 2.3 模型配置 fail-open 语义

- 无 quota_key 的模型视为不限量；quota 行存在且 used >= total 才算耗尽。理由：配置文件不完整时不阻塞编排闭环（编排器在无配置时降级为 `unconfigured-local` 占位模型并照常完成闭环）。

### 2.4 编排对话写入 PersonaChatMessages（taskRoomId 软引用）

- 本项目无独立 ConversationTurns 表；W5 文档 § 2.1 已定「PersonaChatMessages 可承载白板对话」，Phase 2 落实：用户回合 + 林埃压缩摘要回合，均带 taskRoomId。

### 2.5 卡片草稿不落 User-truth

- MockContentAgent 产出 `GeneratedCardDraft`（draft_id），进 Artifact 表与白板操作 plan；**真实建卡（MemoryCards + WhiteboardCardExtras）留待用户确认后由执行器完成**，本轮守卫测试保证 memory_cards 零写入。

---

## 3. 未完成事项（Phase 3+）

1. **真实执行器接线**：CodingAgent → Dev Room Bridge；ContentAgent → 真实 LLM 内容生成。
2. **Action Log 持久化与记忆策展消费端**：Phase 2 只有接口 + 内存实现；落 Drift/JSONL 与 `CanvasActionConsumer` 压缩分析在 Phase 3。
3. **操作执行器**：`WhiteboardOperation[]` → 画布实际执行（Task B 提供执行器；编排侧已产出合法操作）。
4. **任务中心 UI / 决策面板 / 悬浮球状态指示**（W5 Phase 4-5）。
5. **模型额度消耗记账**：本轮只读 used 判断耗尽，不回写使用量。

---

## 4. 关键文件清单

**新增（lib）：**
- `lib/domain/whiteboard/orchestration/intent_classifier.dart`
- `lib/domain/whiteboard/orchestration/model_router.dart`
- `lib/domain/whiteboard/orchestration/task_router.dart`
- `lib/domain/whiteboard/orchestration/result_compressor.dart`
- `lib/domain/whiteboard/orchestration/lin_ai_orchestrator.dart`
- `lib/domain/whiteboard/orchestration/canvas_action_log.dart`
- `lib/domain/whiteboard/agents/coding_agent.dart`
- `lib/domain/whiteboard/agents/content_agent.dart`
- `lib/data/memory_v3/services/orchestration_chat_writer.dart`

**新增（test）：**
- `test/domain/whiteboard/orchestration/` 6 个测试文件（57 项）

**文档：**
- `docs/development/whiteboard-workstreams/W5_PHASE2_HANDOFF.md`（本文件）
- `docs/development/whiteboard-workstreams/W5_AI_ORCHESTRATION.md`（Phase 2 勾选 + 附录）
- `DEVLOG.md` / `docs/development/I_PROJECT_STATE.md`（追加条目）

**不修改：** 数据库迁移、路由、pubspec、W0-W4 共享契约、W1-W4/S 目录。

---

## 5. 验收清单

- [x] classifyIntent / routeTask / selectModel(含 fallback) / compressResult 全有单测
- [x] 端到端：一句用户消息 → TaskRoom（completed）+ 对话两回合（taskRoomId）+ Artifact，库中可查
- [x] 状态转移全经 TaskRoomService 状态机；非法转移（completed→running、终态同状态更新）被拒
- [x] Huabu 借鉴：编排产出 WhiteboardOperation[]（actor=i / authorizationId=taskId / 可往返）；Action Log 只存 NodeRef（守卫测试：三键约束 + JSON 内容键扫描）
- [x] 不自动写 User-truth（memory_cards 空守卫）；不改迁移/路由/pubspec；≥1 跨边界契约测试（WhiteboardOperation 往返）；analyze 零 error；handoff 更新

**Phase 2 编排层完成标记：2026-08-16**
**下一阶段：Phase 3 — Coding Agent（Dev Room Bridge）集成 + Action Log 持久化**
