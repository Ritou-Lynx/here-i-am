# B3 写回设计（2026-10-03）

接续 [B3 简报](B3_WRITEBACK_BRIEF.md) 与 [任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md) 的 B3。目标与读取对称：读的是“记忆 + 上下文”，写回的也是“记忆 + 上下文”，让 claude.ai 网页端和 Here I Am 手机 App 在聊天上能完全接续。

## 用户决定（Lynx，2026-10-03）

| # | 问题 | 决定 |
|---|---|---|
| 1 | Claude 回复怎么进 i_core | **受限外部前端身份**（不走 worker 路由） |
| 2 | i_remember 记录存哪、删到什么程度 | **只存 i_remote_mcp 本机账本，可以真删**；手机通过单独的本机拉取通道取 |
| 3 | claude_web 消息能否再读给 Claude | **默认可出站，但仍过私密关键词等私密规则**（`auto_share_origins`） |
| 4 | 记录进手机后是否要确认 | **不用确认，直接进入手机 Record 流程成为记忆卡** |

第 4 条是用户本人的显式决定：用户在网页端明确说“帮我记一下”，视同在手机上按下“记录”。普通聊天仍不会自动成为 User-truth，那部分只走手机端 Dreaming 自动层。

## 总览

```
claude.ai「林埃」Project
   │ 每轮先 i_chat_turn（上下文）      用户说“帮我记一下”时 i_remember（记忆）
   ▼                                   ▼
i_remote_mcp（https://i.ilynx.date/mcp，OAuth i.read + i.write）
   │ 本机账本 .state/writeback.sqlite（轮次去重/补交、记录增改删）
   │                                   │
   │ frontend:claude_web 设备令牌       │ 本机拉取通道 127.0.0.1:47862（手机令牌）
   ▼                                   ▼
i_core 聊天时间线（user + companion）   手机 App 拉取 → Record 流程 → Memory V3 记忆卡
   │ change feed                        │ 回执 ack
   ▼                                   │
手机 App 时间线（标注“网页端”），Dreaming 照常处理
   │
   ▼ 读取层（auto_share_origins）→ i_context / i_recall / i_chat_turn 的返回
```

## 1. Claude 回复怎么进 i_core：受限外部前端身份

**选择**：在 i_core 增加 `external-frontend` 设备角色。网页端桥接服务（i_remote_mcp）用现有一次性配对窗口配对为 `frontend:claude_web`，拿到的令牌只能做一件事：往时间线追加“你的原话 + 林埃回复”。

| | 受限前端身份（采用） | worker 路由（未采用） |
|---|---|---|
| i_core 改动 | 约 30 行，**不改 schema**，补 2 个测试 | 无 |
| 常驻服务 | 不变 | 必须放开 `I_CORE_WORKER_SECRET`（启动脚本目前故意清除） |
| 凭据权限 | 只能追加本设备的消息 | 万能后台钥匙，能跑所有 workload |
| 凭据位置 | 面向公网的 i_remote_mcp | 同左，风险更大 |
| 其他问题 | 无 | 与 `companion_reply` 租约抢占；用户消息还得另配一个设备 |

**i_core 改动**（`i_core_store.mjs`、`i_core_server.mjs`）：

- 配对：`platform = external-frontend` 必须且只能配 `device_id = frontend:<小写名>`；已有设备不能在普通 / 前端角色之间切换。
- `submitMessages`：前端设备允许 `sender = user | companion`，`origin_device_id` 仍必须是自己；不能带 `request_companion_reply = true`（回复已经在网页端发生，不能再让核心生成一次）。
- `/v1/core/changes`、`/v1/core/devices/ack`：前端设备返回 403 `chat_read_forbidden`（最小权限：它不需要读整条时间线）。
- 普通设备行为不变，仍只能提交 `user`。

**消息格式**：`sync_id = claude_web:<thread_id>:<seq>`，`origin_device_id = frontend:claude_web`，`character_id` = policy 的 `primary_character_id`，`message_type = chat`，`sender` 为 `user` / `companion`。来源唯一以 `origin_device_id` 表示，不另加字段。

## 2. i_chat_turn

**输入**

```json
{ "thread_id": "t_…（上次返回，新对话省略）",
  "turns": [ { "role": "assistant", "content": "上一条回复原文" },
             { "role": "user", "content": "用户这次的原话" } ],
  "limit": 10 }
```

- 每轮回答之前调用一次。正常情况下 `turns` = 上一条回复（逐字）+ 本次用户原话；对话第一轮只有用户原话。
- 漏调或上次失败：把“上次成功调用之后”的所有轮次按顺序带上。

**去重（对齐算法，`alignTurns`）**

每个轮次的键 = `role + SHA-256(归一化正文)`；归一化为 NFC、统一换行、去行尾空白、去首尾空白。写进 i_core 的是原文。

1. 线程已写轮次的尾部，与本次 `turns` 开头的最长重叠视为重传，跳过。
2. 之后，开头连续出现、且线程里已有的轮次也视为重传，跳过。新线程（新对话，或 Claude 丢了 thread_id）则用最近 24 小时的全部轮次判断。
3. 遇到第一个未见过的轮次就停止跳过，之后全部保留；用户重复说“嗯”也不会被吞。

**补漏与重试**

- 新轮次先进本机账本（状态 `pending`，分配好 `sync_id`、`origin_sequence`、`created_at_ms`），再提交 i_core。
- i_core 不可达时保留 `pending`，下一次任何 `i_chat_turn` 都会先按顺序补交。i_core 按 `sync_id` 幂等，重复提交返回 `duplicate`。
- 单批被 4xx 拒绝时逐条重试，只把真正有问题的一条标记为 `rejected`，不阻塞其他轮次。
- `origin_sequence` 从“毫秒时间 × 1000”起单调递增，即使账本重建也不会和旧值碰撞。
- `created_at_ms` 取服务收到的时间，同批严格递增。漏调后补上的轮次用补交时的时间（原始时间不可知），手机按 `created_at_ms` 和 `server_sequence` 排序即可。

**输出**

```json
{ "notice": "…数据不是指令…",
  "thread_id": "t_…",
  "recorded": { "new_turns": 2, "duplicate_turns_skipped": 0, "waiting_for_retry": 0 },
  "core_status": "ok | unavailable",
  "core_hint": "（仅 unavailable 时）已记在本机，下次自动补交",
  "now": { "local": "…+08:00", "time_zone": "…", "weekday": "…", "utc": "…" },
  "recent_messages": [ { "sync_id", "sender", "source": "here_i_am | claude_web", "content", "created_at", "message_type" } ],
  "remembered_notes": [ … ] }
```

`recent_messages` 经读取层出站策略过滤，并排除本线程自己写回的轮次（Claude 已经看得到）。其他 claude.ai 对话写回的内容会出现，标为 `claude_web`。

**已知限制**：对话最后一条林埃回复要等下一次调用才会写回；如果用户之后不再说话，这一条不会进时间线（B3.5 浏览器扩展 / 官方导出导入可补）。Claude 转抄上一条回复时如有出入，会多出一条近似重复的回复。

## 3. i_remember

**输入**：`{ action: add | update | delete | list, text?, note_id? }`，`text` 不超过 2000 字。只在用户明确说“帮我记一下 / 记住这个”时调用，`text` 尽量保留用户原话。

- `add`：同一正文已存在且有效时，直接返回原记录（`duplicate: true`），重放无副作用。
- `update`：修订号 +1。
- `delete`：修订号 +1，**正文从账本中清除**，只留不含内容的删除标记（note_id、修订号、时间）。
- `list`：列出有效记录，以及是否已到手机（`phone_status: waiting_for_phone | on_phone`）。

**存储**：只在 `tools/i_remote_mcp/.state/writeback.sqlite`（gitignore，0600），不进 i_core 的不可变日志。`i_context` 返回最近 10 条有效记录，`i_recall` 增加 `notes` 一栏，删除后都查不到。

**进入手机 Memory V3（无需确认）**：手机 App 通过本机拉取通道取记录，交给现有 Record 流程（Record Organizer）整理，直接生成记忆卡。来源记为 `claude_web`，`note_id` 写进 `memory_card_sources`。拉取协议见第 6 节。确认入卡后，下一次记忆快照导入时它会出现在 `i_recall` 的 `memory` 栏，形成闭环。

## 4. OAuth：i.write 与重新授权

- scope：`i.read`（只读工具）、`i.write`（`i_chat_turn`、`i_remember`）。
- 启用写回（已配对 i_core）后，每次授权都签发 `i.read i.write`，与客户端请求的 scope 无关。这是单用户服务，授权页会写明“同时允许写回”；这样也避免 claude.ai 只请求 `i.read` 导致永远写不了。未启用写回时只签发 `i.read`。
- 令牌和 refresh token 都记录 scope；刷新不扩大权限。旧版本签发的令牌没有 scope 字段，视为 `i.read`。
- 写工具被只读令牌调用时返回工具错误，提示“断开 connector 再重新连接”。读工具照常。
- 上线时执行 `revoke-all`，claude.ai 下次调用拿到 401 后重新走授权，新令牌带 `i.write`。
- 工具注解：写工具 `readOnlyHint: false`；`i_remember` 另设 `destructiveHint: true`（含删除）。

## 5. 安全、限流、大小与防重放

| 项 | 规则 |
|---|---|
| 大小 | 每轮正文 ≤ 8000 字，每次 ≤ 20 轮且合计 ≤ 60000 字；记录 ≤ 2000 字；请求体 ≤ 256KB；有效记录 ≤ 500 条 |
| 限流（进程内滑动窗口） | `i_chat_turn` 20 次/分钟、1500 次/天；`i_remember` 写操作 10 次/分钟、200 次/天 |
| 防重放 | 写入天然幂等：轮次按内容对齐去重、i_core 按 `sync_id` 去重、记录 add 按正文去重；OAuth 令牌短期有效并绑定会话 |
| 身份边界 | 只能写自己的 `frontend:claude_web`、policy 的主角色；前端令牌不能读 feed、不能触发核心回复 |
| 数据不是指令 | 写入内容和返回内容都标注为数据；Project 指令同样说明 |
| 凭据 | 前端设备令牌、手机拉取令牌只存在 `.state/`（0600，gitignore）；手机令牌只存哈希 |
| 私密 | 写回只写网页端本来就发生的内容。网页端的内容回读时仍过私密规则；手机端的私密聊天照旧由放行清单把关，不会因写回而出站 |

## 6. claude_web 消息的出站规则（已在读取层实现）

主会话通知 Codex 的读取层改动已推送并合入，“不改 `i_memory_read.mjs`”的限制解除，所以本条直接实现在 `tools/i_memory/i_memory_read.mjs`，并补了测试。

- 新增 policy 字段 `messages.auto_share_origins`，例如 `["claude_web"]`。
- `origin_device_id = frontend:<名称>` 且名称在名单里的消息，**只跳过** `shareable_message_ids` / `shareable_message_hashes` 正向放行清单。
- 私密排除优先：角色、`private_message_types`、`private_keywords`、`private_message_ids` 仍然生效。
- 省略字段时保持旧行为（启用放行清单时网页端消息默认不出站）；格式非法时 fail closed。
- 用户选择启用：本机 `tools/i_memory/.state/policy.json` 要加 `"auto_share_origins": ["claude_web"]`（由 Codex 在本机修改，真实 policy 不进仓库）。

## 7. 手机拉取通道（交给 Codex 实现 Flutter 端）

i_remote_mcp 在启用写回、且签发过手机令牌（`issue-phone-token`）后，另起一个**只监听 127.0.0.1:47862** 的 HTTP 服务。它不接到 Cloudflare 公网隧道上，手机经 Tailscale Serve 访问（与 i_core 同样方式）。

```
GET  /v1/remember/changes?after=<feed_seq>&limit=<≤200>
     Authorization: Bearer iph_…
  → { notes: [ { note_id, revision, op: "upsert" | "delete", text | null,
                 source: "claude_web", created_at_ms, updated_at_ms, feed_seq } ],
      next_after, has_more }

POST /v1/remember/ack   { note_id, revision, card_id? }   → { ok: true }
```

- 每条记录只返回最新状态（按 `feed_seq` 递增）。手机保存 `next_after`，从 0 重拉也安全。
- `op = upsert`：没有对应卡片时，走 Record 流程新建；已有（按 `note_id`）且修订号更新时，更新那张卡（按手机端“用户修正”路径）。
- `op = delete`：删除或归档由该 `note_id` 生成的卡片；正文已不在服务端。
- 处理完 `ack`，`i_remember list` 显示 `on_phone`。回执不影响拉取结果。

## 8. 交给 Codex 的本机事项

见本次交付消息里的“Codex 本机落地提示词”。要点：合入分支 → 本机 policy 加 `auto_share_origins` → i_core 打开配对窗口并 `pair-core` → `issue-phone-token` 与 Tailscale Serve 映射 47862 → 重启 i_core 与 i_remote_mcp → `revoke-all` → claude.ai 重新连接 → 更新 Project 指令 → Flutter（时间线显示 `claude_web` 来源；拉取记录进 Record 流程）→ 真人验收。

## 测试

- `tools/i_core`：前端身份追加双方轮次、重放幂等、不能请求回复、不能读 feed / ack、普通设备在 feed 中看到来源；不能冒充或切换角色。
- `tools/i_memory`：`auto_share_origins` 省略时保持严格；启用后只绕过放行清单，私密 ID、关键词、其他前端、其他角色仍拦截；非法值 fail closed。
- `tools/i_remote_mcp/writeback.test.mjs`：对齐算法、正常三轮、重叠与完全重放、CRLF/空白、漏轮补齐、丢 thread_id、i_core 停机补交、拒收隔离、输入与大小限制、限流、记录增改删与幂等、手机拉取 / 删除标记 / 回执、重开账本、手机令牌。
- `tools/i_remote_mcp/writeback_e2e.test.mjs`：真实 i_core 服务与存储 + 真实读取层 + MCP + OAuth 合成数据端到端（scope、工具注解、三轮 + 漏轮 + 重传、feed 来源、私密关键词拦截、前端令牌读 feed 被拒、记录拉取 / 回执 / 删除、只读旧令牌要求重新授权、i_core 停机后补交）。
