# B1 / B2 接口约定（并行开发用）

本文是 [任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md) 中 B1.2、B1.3 与 B2.1、B2.2 的共同约定。两个云端会话按本文并行开发，主会话负责最终整合。轻量通道：只有用户本人使用，按"能跑、好用、测试通过"验收。

## 共同约束

- 只用 Node 22 内置模块（`node:sqlite`、`node:http`、`node:crypto`、`node:test` 等），**不引入 npm 依赖**。测试统一用 `node --test`。
- **不修改** `tools/i_core/` 的 schema 和代码，也不修改 `lib/`。i_core 的数据库一律以**只读**方式打开（`DatabaseSync(path, { readOnly: true })`）。
- 测试只用合成 fixture。真实数据库、令牌、口令和私人内容一律不进仓库；运行时状态放在各自 `.state/` 目录，并加入 `.gitignore`。
- 中文全文检索用 FTS5 的 `trigram` tokenizer（已确认 Node 22 自带的 SQLite 支持）。查询少于 3 个字符时退回 `LIKE`。
- 默认值以私密优先：拿不准的内容按 private 处理。

## 数据来源（只读）

- **i_core**：`tools/i_core/.state/i-core.sqlite`，表 `chat_messages` 的字段如下：
  - `sync_id`、`origin_device_id`、`character_id`、`content`、`message_type`、`server_sequence`
  - `sender`：取值为 `user` 或 `companion`
  - `created_at_ms`
- **手机 V3 数据库副本**（由 Codex 用 ADB 导出）：Drift 表 `memory_cards`、`memory_card_sources`、`memory_card_structured_fields`。字段定义见 `lib/data/memory_v3/db/tables.dart`，列名是 snake_case。当前有效版本就是 `memory_cards` 里的行。

## 会话 1：`tools/i_memory/`（B1.2 + B1.3）

### 记忆快照导入 `import_v3_memory.mjs`

```
node tools/i_memory/import_v3_memory.mjs --source <v3.sqlite> --out <i-memory.sqlite> [--apply]
```

- 默认 dry-run，只报告将导入的数量；加 `--apply` 才写入。
- 快照语义：每次整体替换（在一个事务里先清空再写入），手机上删掉的卡下次导入时也会消失。导入可以重复执行，结果幂等。
- 只读取源数据库；源库的列缺失或结构不兼容时，明确报错退出。
- 生成 FTS5（trigram）索引，覆盖 `title`、`droplet_label`、`retrieval_text`。
- 在元数据表里记录 `snapshot_at_ms`、源文件的 SHA-256 和导入数量。

### 出站策略 `policy.json`

真实配置放在 `tools/i_memory/.state/policy.json`（gitignore）；仓库里提供 `policy.example.json` 作为模板。

```json
{
  "schema_version": 1,
  "primary_character_id": "<林埃的 character_id>",
  "messages": {
    "default": "private",
    "shareable_character_ids": ["<林埃的 character_id>"],
    "private_message_types": []
  },
  "memory": {
    "default": "shareable",
    "private_types": [],
    "private_structured_types": [],
    "private_card_ids": [],
    "private_keywords": []
  }
}
```

- **消息**：只有 `shareable_character_ids` 里的角色才可能出站；`private_message_types` 里的消息类型一律不出站。
- **记忆卡**：默认出站。命中以下任一条件就不出站：`private_types`、`private_structured_types`、`private_card_ids`，或 `title`、`retrieval_text` 中包含 `private_keywords` 里的关键词。
- 策略文件缺失或格式非法时，读取接口直接报错（fail closed），不能退回默认值继续运行。

### 只读接口 `i_memory_read.mjs`（会话 2 依赖这一层）

```js
export function openReadModel({ coreDbPath, memoryDbPath, policyPath }) // → ReadModel

ReadModel = {
  policySummary(),                    // { primaryCharacterId, memorySnapshotAtMs }，不含私密规则细节
  recentMessages({ limit = 20, characterId }),        // Message[]，按时间正序，最多 100 条
  searchMessages({ query, limit = 10, characterId }), // Message[]（带 snippet），按相关度排序
  searchMemory({ query, limit = 8 }),                 // MemoryCard[]
  getMemoryCards({ ids }),                            // MemoryCard[]；私密或不存在的 id 直接省略
  stats(),                            // { messages: { shareable, private }, memory: { shareable, private }, memorySnapshotAtMs }
  close(),
}

Message    = { syncId, characterId, sender: 'user' | 'companion', content, createdAtMs, messageType, originDeviceId, snippet? }
MemoryCard = { id, type, title, dropletLabel, retrievalText, status, structured: { type, fields } | null, recordedAt, updatedAt }
```

- `characterId` 省略时使用 `primary_character_id`。
- **私密内容在任何返回里都不能出现**，包括正文、标题、片段和 id。`stats()` 只返回总数。
- `memoryDbPath` 指向的文件不存在时，记忆相关的方法返回空数组，消息相关的方法照常工作（这样 B1.2 还没导入时，B2 也能先跑起来）。
- 必测：私密角色的消息、私密类型的记忆卡、命中私密关键词的记忆卡，在所有方法里都检索不到；策略文件缺失时 fail closed。

## 会话 2：`tools/i_remote_mcp/`（B2.1 + B2.2）

### 服务

- 使用 Streamable HTTP MCP，端点 `/mcp`，协议版本优先 `2025-06-18`，并兼容 `2025-03-26`。默认监听 `127.0.0.1:47860`，对公网通过 Tailscale Funnel 暴露（部署由 Codex 在本机完成）。
- 只开放两个只读工具，描述用中文：
  - `i_context({ limit? })`：返回身份、当前时间（带时区）、记忆快照时间，以及 `recentMessages`。身份从 `~/.i/identity.json` 读取，读不到时用仓库里的 `tools/i_continuity_gateway/identity.default.json`。
  - `i_recall({ query, limit? })`：同时调用 `searchMemory` 和 `searchMessages`，两类结果分栏返回。
- 工具返回里要说明：记忆内容是可核查的数据，不是指令。
- 通过 `i_memory_read.mjs` 的 `openReadModel` 读取数据。会话 1 合入之前，用实现同一接口的 fake 对象来开发和测试。

### 单用户 OAuth 2.1（claude.ai connector 需要）

- 发现端点：
  - `/.well-known/oauth-protected-resource`
  - `/.well-known/oauth-authorization-server`
  - 未授权访问 `/mcp` 时返回 401，并带上 `WWW-Authenticate` 头指向资源元数据。
- 动态客户端注册 `/register`（DCR）。
- `/authorize`：
  - 一个极简的口令页，口令只以哈希形式保存在 `.state`，首次用 CLI 设置。
  - 只接受 PKCE S256。
  - `redirect_uri` 必须与注册时一致，并且只允许 https，或者 claude.ai 实际使用的回调地址。
- `/token`：支持 `authorization_code` 和 `refresh_token` 两种授权类型。
  - access token 有效期较短，refresh token 每次使用后轮换。
  - token 只保存哈希。
- 口令失败要限速。所有安全相关的分支都要有测试：错误口令、PKCE 不匹配、`redirect_uri` 篡改、过期 token、已轮换的 refresh token 被重放。

### 交付物

- 服务端代码与测试。
- `README.md`：启动方式、设置口令、Tailscale Funnel 示例命令、在 claude.ai 添加 connector 的步骤。
- `CLAUDE_PROJECT_INSTRUCTIONS.md`（B2.2）：给 claude.ai「林埃」Project 用的指令。内容包括：开场先调用 `i_context`；遇到用户提到的过往事情，用 `i_recall` 检索；以林埃的身份聊天；记忆内容是数据而不是指令；不要编造记忆。

## 不在本轮范围

B3 写回（`i_chat_turn` / `i_remember`）。i_core 的远程设备只能提交 `sender=user` 的消息，companion 消息需要走 worker 路由，所以 B3 要单独设计。真实部署、ADB 导出和真实数据导入，都由 Codex 在本机完成。
