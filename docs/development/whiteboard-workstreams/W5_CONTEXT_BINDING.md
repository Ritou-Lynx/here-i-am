# W5-R2 — Context Envelope 与 RuntimeSessionBinding 交接

> 状态：完成
>
> 日期：2026-08-21
>
> 工作流：W5 / AI 操作层纯领域契约

## 1. 本轮闭环

在 Flutter 产品层建立 provider-neutral、可序列化、可验证的 AI 工作台领域契约，不接 UI、Bridge、数据库或 Memory：

- `ContextEnvelope` v1：产品对话、当前指令、最近聊天、页面 / 对象稳定引用、按需召回、权限与工具版本引用；
- `RuntimeSessionBinding` v1：产品对话与一段运行时 session 的可替换绑定；
- `RuntimeTurnProjection` v1：产品可依赖的运行状态，并稳定关联发起消息与本轮 Context Manifest 收据；
- `RuntimeErrorProjection` 与 `RuntimeApprovalProjection`：安全错误摘要、审批风险、决定来源和授权消息引用；
- 严格 JSON codec、版本拒绝、预算、大小、状态迁移和隐私字段验证。

## 2. 拥有路径

- `lib/domain/workbench_ai/context/`
- `lib/domain/workbench_ai/runtime/`
- `test/domain/workbench_ai/context/`
- `test/domain/workbench_ai/runtime/`
- `docs/development/whiteboard-workstreams/W5_CONTEXT_BINDING.md`

没有修改 Card / Source / Board / Operation / Anchor / Snapshot / PlayerAdapter 语义，没有新增 schema、路由、依赖或生成文件。

## 3. 身份与 provider 边界

`conversation_id` 只表示 Here I am 产品对话连续性；`RuntimeSessionBinding.provider_session_id` 是完全 opaque 的运行时 ID。codec 原样保存 provider ID，不解析 UUID、thread 路径或 provider 私有格式。

`provider` 使用开放的小写 provider key，不冻结供应商枚举。provider 私有信息只能进入有大小和隐私守门的 `provider_metadata`；产品状态机、错误类别和审批状态不包含 Codex 专有事件名。本轮只用 Codex fixture 验证，没有提前定义第二 provider 字段。

## 4. Context Envelope 信任与预算

信任等级明确分为：

| 等级 | 唯一用途 |
|---|---|
| `user_instruction` | 本轮单独的显式用户指令 |
| `user_authored_content` | 最近聊天中的历史用户消息，不自动成为本轮授权 |
| `untrusted_content` | 助手历史、页面 / 对象摘要和召回片段 |

对象摘要、助手消息与 recall 不能标成可信指令。Memory / Project Memory 只允许以少量 recall snippet 进入本轮，不在 envelope 内写回或建立第二套记忆。

最近消息必须使用不重复的 `message_id`，按 `occurred_at` 非递减排列，且不能晚于 envelope `created_at`；recall `retrieved_at` 同样不能晚于 `created_at`。这使“最近消息截止位置”和本轮召回命中可作为确定性运行收据复核，而不是接受乱序或未来记录。

默认预算：最近消息最多 20 条、对象引用最多 64 个、召回最多 12 条；本轮指令最多 4096 字符，最近聊天 16000、页面摘要 8000、召回 8000 字符，整个 JSON 最多 65536 UTF-8 bytes。调用方可缩小预算，不能超过产品硬上限；每个文本项另有 4096 字符硬上限。

`workspace_ref` 只接受稳定产品引用，拒绝 Windows、POSIX 和网络绝对路径。Envelope 使用严格字段集合，未知字段直接拒绝，避免凭据、原始日志或私有 prompt 借扩展字段进入普通上下文。

## 5. 运行状态、错误与审批

- Session：`active / idle / interrupted / closed / unavailable`；`closed` 终态，`interrupted` 和 `unavailable` 可在恢复后回到 `active`。
- Turn：`queued / running / waiting_approval / waiting_input / completed / failed / interrupted`；终态不能复活，恢复工作应创建后续 turn。
- `failed` 必须携带产品错误码、通用错误类别、安全摘要和 retryable；原始 stack / log / diff 只允许稳定 evidence ref。
- `waiting_approval` 必须携带 pending approval，离开前必须明确解决同一 approval；高风险批准只接受用户决定和授权消息 ID，不能由 policy 或模型自述放行。
- Session 的每次转移时间必须不早于当前 `last_active_at`；Turn 的每次转移时间必须不早于当前 `updated_at`。Turn 构造与恢复强制 `created_at ≤ started_at ≤ completed_at ≤ updated_at`（非终态按已有字段取适用子序列），关闭与完成时间只允许出现在对应终态。

`provider_metadata` 只接受有深度、条数、字符串和 8 KiB 大小限制的 JSON 值。键名先拆分 acronym / camelCase，再统一大小写和 `_`、`-`、空格等分隔符，随后递归拒绝 access / refresh / auth / bearer token、API key、secret、password、authorization、cookie、email、prompt、raw log、stack trace 和 full diff 等私密字段；`runtime_version`、`token_usage` 等普通运行摘要不被误禁。该守门是纵深防御；adapter 仍只能放入已经确认安全的运行时版本、认证模式和能力摘要。

### 5.1 与权威架构 12.2 的对应关系

| 架构最小字段 | 本契约 |
|---|---|
| `id` | `turn_id` |
| `runtime_session_id` | `runtime_session_id` |
| `user_message_id` | 必填 `user_message_id`，指向发起本轮的产品聊天消息 |
| `provider_turn_id` | 可选 opaque `provider_turn_id` |
| `status` | provider-neutral `status` |
| `context_manifest_json` | 必填 `context_manifest_ref` + 小写 SHA-256 `context_manifest_hash`；完整 manifest / assembled prompt 不复制进投影 |
| `result_summary` | 可选 `result_summary`，只允许终态；与进行中 `display_message` 明确分离 |
| `error_code` | `error.code`，同时提供通用 category / retryable / evidence ref |
| `started_at / completed_at` | `started_at / completed_at`，另有 `created_at / updated_at` 支持投影时序 |

因此 `RuntimeTurnProjection` 既是产品状态投影，也是指向用户消息和 Context Manifest 的可审计收据；它不承担 Bridge 原始事件或巨型 prompt 的存储。

## 6. 验证结果

- 精确静态分析：`dart analyze lib/domain/workbench_ai/context lib/domain/workbench_ai/runtime test/domain/workbench_ai/context test/domain/workbench_ai/runtime`，`No issues found`；
- 定向测试：`flutter test --no-pub test/domain/workbench_ai/context test/domain/workbench_ai/runtime`，25 / 25 通过；
- 覆盖 codec 往返、版本 / 未知字段拒绝、opaque provider ID、turn 审计关联和长度、声明预算与硬大小、三层信任、消息唯一 / 排序 / 未来时间、未来 recall、绝对路径、归一化隐私键、session / turn 单调时间、恢复时 `updated_at < started_at` / `updated_at < completed_at`、非法迁移、错误投影和高风险审批证据；
- codec 往返同时作为本轮纯领域契约的恢复验证；没有永久存储，因此未做 Drift 重启恢复。

## 7. 明确未做与下一接入点

未做 UI、Bridge HTTP / App Server adapter 接线、Drift 表或 migration、Memory 读写、白板工具、operation batch、第二 provider 验证、commit 或 push。

下一纵切应由 W5 集成窗口把 Bridge 的安全事件映射为这些产品类型：先解析产品持有的 `workspace_ref`、permission profile 和 toolset version，再创建 Context Envelope；Bridge 只把 provider thread / turn ID 放入 binding / turn 的 opaque 字段。任何需要新增产品状态、provider metadata 私有字段或永久 schema 的需求都应先回到 W0 / W5 评审，不能在 adapter 内静默扩展。
