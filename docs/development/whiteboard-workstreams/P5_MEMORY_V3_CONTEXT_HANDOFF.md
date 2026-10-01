# P5 — Memory V3 Context 返修交接

> 日期：2026-08-26
> Goal / 工作包：`GOAL-20260824-ai-workbench-wave1` / P5
> 固定基线：`9237270e0b2b1c3f49a4ec395c6ae2b5a360daa3`
> 分支：`codex/whiteboard-w0-goal1-p5-repair`
> 初始代码与测试 commit：`8dfb95c8`
> 初始 handoff commit：`51f4c3d6`
> 第一轮审计追加返修 commit：`bd2b0cd3`
> 第二轮空证据返修 commit：`72462d88`
>
> 集成说明：`8dfb95c8` / `51f4c3d6` 不能单独视为最终交付；必须连同
> `bd2b0cd3`、`72462d88` 及包含本次更新的 handoff commit 一起审计、集成。

## 启动声明（执行时）

- 工作流：Goal 1 / P5 Memory V3 Context 返修。
- 闭环：桌面每轮注入真实林埃 Persona 与有界 Dreaming 关系上下文，保留按需 Memory Card 搜索。
- 拥有路径：Workbench context/coordinator、最小共享 Persona builder、对应测试、本 handoff。
- 已读契约：根 AGENTS、Roadmap、协作协议、白板总纲、Goal、Workbench 架构、旧 P5 handoff。
- 共享契约：Card / Source / Anchor / schema / 依赖 / 生成文件只读，不新增 permission lane。
- 不做：不接 Gateway/ADB，不读真实用户数据，不改 UI/Core 权威，不扩 P4/P6/W4。
- 验证：P5/P6/Companion 定向回归、changed-file analyze、diff check；不构建、不 push。

## 本轮闭环与真实支持范围

- `WorkbenchConversationCoordinator.instance` 现在配置产品宿主持有的 `WorkbenchRelationshipContextAssembler.production`；每次 turn 在进入 Runtime 前按 `conversationId + characterId + userText` 重新组装，而不是依赖 Codex thread 自带人格。
- 将 Companion 当前真实的 `# 你是林埃`、身份锚点和归属自检抽成 `CompanionPersonaPromptBuilder`，移动 Companion 与桌面 Workbench 同源。`CharacterModel` 的 `persona / systemPromptOverride / postHistoryInstructions / mesExample` 仍按既有契约忽略，没有恢复 legacy character-card prompt。
- 当前产品是单角色 i：只接受精确 `conversationId == persona:i` 与 `characterId == i`。conversation/character 不一致或非 i scope 在任何后端读取前 fail-closed，不为未知角色定义新 Persona。
- 最近关系上下文只读 `PersonaChatMessages` 中精确 character、`messageType=chat`、`taskRoomId IS NULL` 的最近消息；UI 已落库的当前 user message 只跳过最新一条相同文本，更早的重复短句仍保留。
- Dreaming 使用现有相关性查询得到 Episode / Fragment / Saga；它们明确标为 relationship recollection、**不是 User-truth**，并作为不可信召回内容而非指令或授权。
- 因 Dreaming 表当前没有 `character_id`，生产后端沿 `Saga → Episode → Fragment → source PersonaChatMessage` 反查证据。Fragment 的 stable sync IDs 可能只是 legacy local IDs 的子集，因此 sync/local 两套证据只要字段不是 `null` 就分别完整校验，不能互相替代；显式空串或纯空白不是 absent，而是 invalid。每套都必须是合法、非空、未超限、无重复且全部可解析到 i 主聊天。缺证据、malformed JSON、跨角色、非 chat、TaskRoom、未知 source scope、不可解析或超限链条均 fail-closed。
- 最近消息及 Dreaming 的 ID、标题、描述、叙事、内容都按不可信字段投影：控制符/换行压成单行，XML-like 分隔符替换为安全字符，UTF-16 截断不拆 surrogate pair。最终 prompt 只有产品宿主写入的一处 `</host_owned_relationship_context>`。
- `DreamingOrchestratorServiceV3` 新增默认关闭的 `strictDiagnostics`。移动 Companion 不传该参数，继续保留原来的吞错/空结果降级；只有 Workbench production 启用。Episode/Fragment 的 FTS 与 substring 等确定性路径全部失败，或 Saga FTS 失败时向 Workbench 抛出诊断异常，最终标为 `unavailable`，不再伪装成 `empty`；optional embedding 失败仍可降级。
- 每层状态区分 `available / empty / unavailable / rejected / isolated`。角色、最近聊天或 Dreaming 后端抛错会降级；整个上下文组装有 10 秒冷启动上限，挂起/失败不阻断普通 Runtime 回复，也不会把“没能查”伪装成“没有记忆”。
- 既有 `search_workbench_content` Memory Card / User-truth / Project Memory 按需搜索保持不变；本包没有新增写工具。Runtime 伪造 `record_explicit_memory` 或 payload 自授权仍返回 `unsupported_product_tool`，既有 search/queue permission lane 也继续由宿主持有。

## 有界限制

- 最终每轮最多：最近关系消息 8、Episode 4、Fragment 6、Saga 2。
- 证据展开最多：每 Saga 16 个 Episode ID、每 Episode 24 个 Fragment ID、每 Fragment 16 条源消息；全局最多扩展 24 个额外 Episode 与 96 个 Fragment 候选。
- 单条投影文本还会再次截断；后端即使返回超量结果，assembler 也会在最终投影处重新 `take(limit)`。

## 修改文件

- `lib/agent/companion_agent/companion_persona_prompt_builder.dart`
- `lib/agent/skills/companion_agent/companion_agent_skill.dart`
- `lib/data/memory_v3/services/dreaming_orchestrator_service.dart`
- `lib/data/workbench_ai/context/workbench_relationship_context.dart`
- `lib/data/workbench_ai/workbench_conversation_coordinator.dart`
- `test/data/memory_v3/services/dreaming_context_strict_mode_test.dart`
- `test/data/workbench_ai/context/workbench_dreaming_evidence_verifier_test.dart`
- `test/data/workbench_ai/context/workbench_relationship_context_test.dart`
- `test/data/workbench_ai/workbench_conversation_coordinator_test.dart`
- `docs/development/whiteboard-workstreams/P5_MEMORY_V3_CONTEXT_HANDOFF.md`

## 验证证据

- 审计返修最小集：`6/6` 通过。覆盖 real Drift provenance verifier 与 Dreaming strict/default 诊断。
- 第二轮空证据聚焦回归：`3/3` 通过；明确覆盖空 `sourceSyncIds` + 有效 local，以及空白 `sourceMessageIds` + 有效 sync，均拒绝。
- 最终受影响组合回归：`76/76` 通过。覆盖新增 relationship context/provenance/strict diagnostics、Workbench coordinator、既有 P5 search facade/runtime tool、P6 task queue/coordinator、白板 coordinator 受影响路径、Companion prompt 与 tool permission。
- 新增重点：i sync 子集不能掩盖 TaskRoom、另一 character 或非 chat 的 local 来源；malformed/空/超限证据拒绝；恶意 closing delimiter/换行不越界；emoji 截断不破坏 surrogate pair；Episode/Fragment/Saga 故障在 strict 模式诚实上浮，其中 Fragment 同类故障在默认模式仍维持旧 empty fallback。
- 既有重点：真实林埃身份出现；四个 `LEGACY_*` 与移动端工具说明不进入 Workbench；Episode/Fragment/Saga 命中和硬上限；空结果；后端抛错与挂起降级；重复短句；conversation mismatch 与非 i scope 拒绝；伪造写工具与 payload 扩权拒绝。
- changed-file analyze：5 个本轮改动源码/测试文件，`No issues found`。
- 第二轮窄返修 changed-file analyze：2 个文件，`No issues found`。
- `git diff --check` / staged diff check：通过；仅有仓库既有 CRLF 归一化提示，无 whitespace error。
- Flutter 测试/分析产生的三份 Windows plugin generated 差异均已恢复，未进入提交。
- 额外尝试的 `test/agent/character_tools_factory_memory_freeze_test.dart` 在加载阶段因基线已删除 `CharacterToolsFactory.buildCommentTools` 失败；该文件与 API 均未由本包修改。初始组合排除这个基线陈旧测试后为 `65/65`，本次扩大后的受影响组合为上述 `76/76`。

## 共享契约影响

- 无 Card / Source / Anchor / DB schema / migration / dependency / generated file 变更。
- 无新增搜索 permission lane，无 User-truth 写入、自动建卡或模型 payload 授权。
- 跨既有模块的改动限于：抽取 Companion 产品身份 Prompt，以及给 Dreaming query 增加默认关闭的诊断参数；默认 Companion 调用语义由测试证明不变。

## 已知限制与真人 Gate

- 自动测试使用合成 CharacterModel 与 Dreaming 投影，没有读取真实用户数据；真实私人电脑数据库的命中/空/失败会话 trace 仍由 W0 在唯一候选中真人验收。
- 当前 schema 没有 Dreaming `character_id`，因此只能通过源消息证据 fail-closed；缺少可核查 provenance 的旧 Dreaming 行不会注入。新增 character lane 或 schema 变更必须另提共享契约工作包。
- 上下文 10 秒超时后，本轮诚实降级为 unavailable；底层不可取消 Future 可能自行结束，但它没有写 User-truth/Memory 的能力。
- 待 W0：按顺序审计初始 `8dfb95c8`、第一轮返修 `bd2b0cd3`、第二轮返修 `72462d88` 与最终 handoff 提交，选择性集成后重跑唯一候选组合 Gate，再做真实 Persona / Episode / Fragment / Saga 命中、空、后端失败、错误 scope、写入与 payload 扩权拒绝真人 Gate。
