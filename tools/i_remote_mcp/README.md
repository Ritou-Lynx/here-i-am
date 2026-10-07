# i 远程 MCP（B2.1 只读 + B3 写回）

让 claude.ai 网页端通过自定义 connector 访问林埃的身份、最近可分享聊天和记忆检索（B2），并把网页端的聊天轮次和显式记录写回 Here I Am（B3）。规格见 [CONTINUITY_B1_B2_CONTRACT.md](../../docs/development/CONTINUITY_B1_B2_CONTRACT.md)「会话 2」与 [B3_WRITEBACK_DESIGN.md](../../docs/development/B3_WRITEBACK_DESIGN.md)。正式入口为 `https://i.ilynx.date/mcp`（Cloudflare 固定隧道）；下文 Tailscale Funnel 一节只作历史参考，已不作 claude.ai 入口。

- Streamable HTTP MCP，端点 `/mcp`；协议 `2025-06-18`，兼容 `2025-03-26`。
- 只读工具：`i_context`、`i_recall`（scope `i.read`）。配对 i_core 后另开写工具 `i_chat_turn`、`i_remember`（scope `i.write`）。
- 内置单用户 OAuth 2.1：DCR、口令授权页、PKCE S256、refresh token 轮换；令牌、授权码和口令只存哈希。
- 只用 Node 22 内置模块，无 npm 依赖。

## W3 领域工具（源码候选，默认未启用）

`domain_tools.mjs` 仅通过 schema6 Core 的领域 HTTP API 访问 captures、plan_items、plan_weeks、plan_days。没有数据库连接、worker 密钥、聊天读取或授权签发能力。Core 注册/模式、受信授权 verifier 和 scoped principal 由 owner 配置；本模块不升级/注册/启用领域。

| 工具 | Core 权限 | 操作 |
|---|---|---|
| `capture_add` | captures:create | 固定来源，user_via_agent，需要已验证 authorization_ref |
| `capture_list` | captures:read | 指定 id 或一致快照分页；返回有效 organizer/planner 处理状态 |
| `capture_ack` | captures:ack | 只写 planner；input_revision 绑定 text 的 field revision |
| `plan_list` | plan_items:read | 指定 id 或快照分页 |
| `plan_upsert` | plan_items:create / patch | base_revision=0 创建；其他版本只改提供的 data 字段 |
| `plan_set_status` | plan_items:status | 仅完成/放弃，固定 user_direct，需受信交互凭据与授权引用 |
| `week_get` / `week_set` | plan_weeks:read / create / patch | 完整周字段、容量、主线配额、欠账 |
| `day_get` / `day_set` | plan_days:read / create / patch | 今日队列和版本；更新须提交整个 edition 原子组 |

写入必须提供 `op_id`、稳定 `id`、`base_revision`、`created_at`、`expires_at`；时间使用 UTC 毫秒格式。新 op_id/id 为 UUID；修改迁入记录保留旧 id。网络失败返回 `transport_unknown`，原样重试；重复 op_id 改内容是 `idempotency_conflict`。不会自动读取最新版本并覆盖，不把 `needs_resolution` 当 accepted。Core 原始 `reason`、receipt、tombstone 会保留；字段错误/拒绝/冲突的 MCP `isError=true`。upsert 创建需全部业务字段，patch 可提供部分字段但必须完整满足原子组；Core 是最终校验者。

读工具使用 `{id}` 或 `{limit,snapshot_token,page_token}`，两种不能混用。分页返回 snapshot manifest、digest 和 next_page_token；最后一页确认该短期查询的 cursor 并释放快照，不保存本地副本。调用方若维护耐久同步副本，应直接使用 Core feed/snapshot 协议，不把本查询确认当成耐久副本提交。周键/日期属于业务字段，先分页找到目标 record id；本层不臆造其 id。

本机入口为 `node tools/i_remote_mcp/planner_server.mjs <外置私有配置.json>`。配置至少包含 `enabled:true`、`core_url`、`core_instance_id`、`credentials:[{token,scopes}]`，可指定 `port`（默认 47863）。token 必须是 Core 已签发的 scoped token，原样转发；不是网页 OAuth、聊天设备或 worker key。入口硬编码绑定 `127.0.0.1`，拒绝浏览器 Origin/Fetch 请求，未挂到公网 server；不创建聊天 handlers。最小规划配置的 scopes 是 captures:read/ack 和三个 plan 域的 read/create/patch。需要显式捕获或用户点完成时，另行配置最小 captures:create 或 plan_items:status 凭据；Core 仍需相应受信 actor/来源能力。

配置中的 scopes 是**目录上限**，不是新授权：Core 当前没有远程 token introspection，目录不能证明配置未过期；每条数据操作都由 Core 用同一真实 token 检查当前 generation/scope/归属，撤销或缩权立即拒绝。不能把目录声明说成已核验的真实 grants。若要求目录随权限即时变化，先增加经过审计的 Core introspection 接口；本包没有自造接口或开库绕过。

网页端仅可增加 `capture_add`、`week_get`、`day_get`；规划写工具在 createApp 装配时拒绝。显式添加 `server.mjs serve --domain-config <外置私有配置.json>` 才选择 Core notes 后端。配置为 `enabled:true, remember_backend:"core", core_url, core_instance_id, token, scopes`，scopes 限 captures:read/create/patch/delete。该 principal 必须 owner-only、来源限定 claude_web、actor 为 user_via_agent。可附 `plan_reads:{token,scopes}`，只能 plan_weeks:read/plan_days:read，并必须为另一 token：captures 的全局 owner-only 约束不能为读取计划而放宽。网页仍额外执行 OAuth i.read/i.write。未传配置保持原 B3 路径；Core 模式禁止旧 47862 note feed，记录不双写旧账本。聊天轮次仍使用既有独立 B3 账本。

Core `i_remember` 保留 add/update/delete/list 与 note_id 输出；写入增加上述稳定 intent 字段及 `authorization_ref`，update/delete 支持旧 note_id。新记录 provenance=claude_web，两个处理者按需处理；旧迁入 i_remember 记录 planner 始终 skipped。删除 permanent=true，Core 在线正文即时清除；不宣称物理页/WAL/离线备份已抹除，也不宣称下游用户改卡已删除。重试按 op_id 判重，不用正文 hash 猜测两个新记录是否相同。缺少受信授权引用时拒绝；MCP 不通过自动读取聊天制造证据。Core notes 不可用时上下文/聊天结果明确返回 remembered_notes_error，保留既有聊天结果，不回退旧 notes。

迁移复用 `tools/i_core/import_personal_notes.mjs` 的显式、默认 dry-run 流程；本包只验证合成关闭副本的 adoption、旧 ID/revision、即时墓碑及 planner skipped。没有读取真实 notes，没有运行生产迁移。生产切换仍须生命周期修复、现役 transcript/replay 保全、owner 凭据与 verifier、旧写入冻结及真实状态备份/对账等独立验收。

i_memory 的 v2 policy 增加必填 `domains:["chat","memory_v3"]`，可选其子集或空集；未列领域所有正文/ID/统计/快照时间出口均不读。未知领域拒绝；captures/plan/后续生活领域必须走 scoped API。v1 仅兼容固定的旧 chat/memory_v3 读取，不会自动获得新 Core 表；生产 policy 升到 v2 仍由 owner 执行，本包不改真实配置。

## 文件

| 文件 | 作用 |
|---|---|
| `server.mjs` | HTTP 路由、会话管理、CLI（`serve` / `set-passphrase` / `revoke-all`） |
| `oauth.mjs` | 授权服务器：元数据、注册、授权、令牌、限速、持久化 |
| `mcp.mjs` | JSON-RPC 处理、工具定义与输出白名单、身份加载 |
| `writeback.mjs` | B3 写回：本机账本、轮次对齐去重、i_core 前端客户端、记录增改删、手机拉取、限流 |
| `fixtures.mjs` | 测试用 fake readModel 与服务启动器（合成数据） |
| `*.test.mjs` | `node --test` 测试 |
| `CLAUDE_PROJECT_INSTRUCTIONS.md` | 给 claude.ai「林埃」Project 的指令（B2.2） |
| `.state/` | 运行时状态（`oauth.json`、`core-frontend.json`、`writeback.sqlite`、`phone-feed.json`），已 gitignore |

## 数据来源

工具通过 `tools/i_memory/i_memory_read.mjs` 的 `openReadModel()` 读取（会话 1 交付），首次调用工具时才动态加载；在它合入之前，服务和 OAuth 可以正常启动，工具调用会返回“数据源暂不可用”。

| 参数 | 环境变量 | 默认值 |
|---|---|---|
| `--core-db` | `I_CORE_DB` | `tools/i_core/.state/i-core.sqlite` |
| `--memory-db` | `I_MEMORY_DB` | `tools/i_memory/.state/i-memory.sqlite` |
| `--policy` | `I_MEMORY_POLICY` | `tools/i_memory/.state/policy.json` |

身份从 `~/.i/identity.json`（或 `$I_HOME/identity.json`）读取，读不到时用 `tools/i_continuity_gateway/identity.default.json`。返回时区默认用系统时区，可用 `I_REMOTE_MCP_TIMEZONE=Asia/Shanghai` 指定。

## 启动

```powershell
# 1. 首次设置口令（至少 12 个字符；交互输入不回显，会要求输入两次）
node tools/i_remote_mcp/server.mjs set-passphrase

# 2. 启动；--public-url 必须是 claude.ai 能访问的 https 地址（不带 /mcp）
node tools/i_remote_mcp/server.mjs serve --public-url https://<机器名>.<tailnet>.ts.net
```

| 参数 | 环境变量 | 默认值 |
|---|---|---|
| `--host` | `I_REMOTE_MCP_HOST` | `127.0.0.1` |
| `--port` | `I_REMOTE_MCP_PORT` | `47860` |
| `--public-url` | `I_REMOTE_MCP_PUBLIC_URL` | `http://<host>:<port>`（仅本机调试） |
| `--state-dir` | `I_REMOTE_MCP_STATE_DIR` | `tools/i_remote_mcp/.state` |

- `set-passphrase` 也可以从管道读取第一行（非交互，用于脚本）。改口令会吊销所有既有令牌。
- `revoke-all`：吊销所有令牌与授权码（口令不变），claude.ai 下次调用会要求重新授权。
- 口令连续错误 5 次锁定 15 分钟（锁定期间正确口令也会被拒）；锁定只在内存，重启服务即清空。

OAuth 参数：access token 1 小时、refresh token 30 天（每次使用后轮换，旧的被重放会吊销整条令牌链）、授权码 5 分钟一次性。

## B3 写回

配对 i_core 之前，服务只开放只读工具，行为与 B2 相同。启用步骤（本机执行）：

```powershell
# 1. i_core 临时打开配对窗口（一次性配对码，不写进常驻启动项），然后：
node tools/i_remote_mcp/server.mjs pair-core            # 输入同一个配对码；令牌写入 .state/core-frontend.json
#    i_core 地址默认 http://127.0.0.1:47841，可用 --core-url 或 I_CORE_URL 指定
# 2. 签发手机拉取令牌（只显示一次；再次运行即轮换）
node tools/i_remote_mcp/server.mjs issue-phone-token
# 3. 重启 serve；日志出现“写回已启用”和“手机拉取通道监听 …:47862”
# 4. 吊销旧的只读令牌，让 claude.ai 重新授权拿到 i.write
node tools/i_remote_mcp/server.mjs revoke-all
```

| 参数 | 环境变量 | 默认值 |
|---|---|---|
| `--core-url` | `I_CORE_URL` | `http://127.0.0.1:47841` |
| `--phone-host` | `I_REMOTE_MCP_PHONE_HOST` | `127.0.0.1` |
| `--phone-port` | `I_REMOTE_MCP_PHONE_PORT` | `47862` |
| — | `I_REMOTE_MCP_WRITEBACK=0` | 临时关闭写回（只读工具照常） |

- `i_chat_turn`：每轮两次——回答前 `phase=start` 交用户原话并取上下文，回复写完后在同一条消息末尾 `phase=end` 交回复原文，最后一条回复也当场写回。按内容对齐去重，长文本另做近似去重（不可还原的 MinHash 指纹）；漏调的轮次下次补上，带 `addenda: [{type: frontend_backfill, approximate_time: true}]` 并在前后两条之间估算时间；i_core 不可达时记在本机账本、下次自动补交。写进 i_core 的消息 `origin_device_id = frontend:claude_web`，手机 feed 可据此标注“网页端”。
- `i_remember`：add / update / delete / list。记录只在本机账本，删除会清掉正文。手机经本机拉取通道 `GET /v1/remember/changes`、`POST /v1/remember/ack` 取走，进入 Record 流程直接成卡。
- 手机拉取通道只监听本机，**不要**接到 Cloudflare 隧道上；手机经 Tailscale Serve 访问。
- 限流、大小限制、scope 与重新授权规则见设计文档。
- 读取层需在 policy 里设 `messages.auto_share_origins: ["claude_web"]`，网页端写回的消息才会在其他对话里被读回（私密规则仍优先）。

## Tailscale Funnel 示例（历史参考，已弃用）

服务只监听 `127.0.0.1`，由 Funnel 终止 TLS 并对公网暴露：

```powershell
tailscale funnel --bg 47860          # 把 https://<机器名>.<tailnet>.ts.net/ 转发到 http://127.0.0.1:47860
tailscale funnel status              # 查看公网地址
tailscale funnel --https=443 off     # 关闭
```

公网地址即 `--public-url`。部署后自检（从外网）：

```powershell
curl -i https://<机器名>.<tailnet>.ts.net/mcp -X POST -d "{}"
# 预期 401，且带 WWW-Authenticate: Bearer resource_metadata="https://…/.well-known/oauth-protected-resource"
curl https://<机器名>.<tailnet>.ts.net/.well-known/oauth-authorization-server
```

开机自启（B2.3）由 Codex 在本机配置，例如 Windows 计划任务在登录时运行 `node …\server.mjs serve --public-url …`。

## 在 claude.ai 添加 connector

1. claude.ai → 设置（Settings）→ Connectors → 添加自定义 connector（Add custom connector）。
2. 名称填 `i`，URL 填 `https://<机器名>.<tailnet>.ts.net/mcp`（**带 `/mcp`**，必须与服务的 `resource` 完全一致）。高级设置里的 OAuth Client ID/Secret 留空（走 DCR）。
3. 点连接，浏览器会打开本服务的口令页，页面上显示“授权后将返回 claude.ai”；输入口令后跳回 claude.ai。
4. 在 connector 的工具设置里把 `i_context`、`i_recall` 设为“始终允许”；启用写回后再把 `i_chat_turn`、`i_remember` 设为“始终允许”（否则每轮都会弹确认）。
5. 新建「林埃」Project，把 [CLAUDE_PROJECT_INSTRUCTIONS.md](CLAUDE_PROJECT_INSTRUCTIONS.md) 中“指令正文”一节粘贴到 Project 指令里，并在该 Project 中启用这个 connector。

## 协议与安全要点

- 未授权访问 `/mcp`（任意方法）返回 `401` 与 `WWW-Authenticate: Bearer resource_metadata=…`；无效或过期令牌带 `error="invalid_token"`。
- 元数据：`/.well-known/oauth-protected-resource`（及 `/.well-known/oauth-protected-resource/mcp`）、`/.well-known/oauth-authorization-server`。
- `/register` 默认只接受 claude.ai 的回调（`https://claude.ai/api/mcp/auth_callback` 与 `https://claude.com/api/mcp/auth_callback`），防止他人注册自己的回调后诱导你在授权页输入口令；以后接 ChatGPT 等其他客户端时，用环境变量 `I_REMOTE_MCP_EXTRA_REDIRECT_URIS`（逗号分隔，精确匹配，必须 https）追加。注册为 public client（`token_endpoint_auth_method: none`）。客户端最多保留 50 个，超出淘汰最早的。
- `/authorize`：`client_id` 未知或 `redirect_uri` 与注册不一致时直接显示错误页，不重定向；只接受 `code_challenge_method=S256`；带 `resource` 时必须等于本服务的 `/mcp` 地址。
- `/token`：`application/x-www-form-urlencoded`；错误码遵循 RFC 6749（失效的 refresh token 返回 `invalid_grant`）。授权码被重放会吊销由它签发的令牌。
- 会话：`initialize` 响应带 `Mcp-Session-Id`，后续请求必须带上；会话绑定令牌家族（刷新后仍可用，换一次授权则不行）；`DELETE /mcp` 结束会话；服务重启后会话失效，客户端收到 404 会重新 initialize。
- 只返回 JSON 响应，不开 SSE 流（`GET /mcp` 返回 405，规范允许）。
- 带 `Origin` 头的请求只接受 `https://claude.ai`、`https://claude.com` 和本服务自身来源，防 DNS rebinding。
- 工具输出逐字段白名单投影；`character_id`、`origin_device_id`、`stats()` 私密计数和策略细节都不会返回。数据源报错时只返回通用提示，不泄露路径或异常内容。

## 测试

```powershell
node --test "tools/i_remote_mcp/*.test.mjs"
# 或在目录内：cd tools/i_remote_mcp; node --test
```

Node 22 的 `node --test <目录>` 不会展开目录（会把目录当模块执行而失败），所以用 glob 或在目录内运行。测试在随机端口启动真实 HTTP 服务，用可注入时钟覆盖过期分支，只用合成数据。

## 需实测

- **claude.ai 实际回调地址**：官方文档写明 `https://claude.ai/api/mcp/auth_callback`（[Authentication for connectors](https://claude.com/docs/connectors/building/authentication)）；首次授权时以服务日志里的 `/authorize` 请求为准。
- **claude.ai 是否发送 `resource` 参数、发送的值是否带结尾斜杠**：服务对结尾斜杠做了归一化，其他值会被拒为 `invalid_target`。
- **claude.ai 请求 `/mcp` 时是否带 `Origin` 头**：若带的不是 `https://claude.ai` / `https://claude.com`，会被 403，需要把实际值加入 `server.mjs` 的 `DEFAULT_ALLOWED_ORIGINS`。
- **只返回 JSON、不提供 SSE 是否被 claude.ai 接受**：规范允许，未实测。
- **Tailscale Funnel 在 Windows 上的具体命令与后台常驻方式**（`--bg` 需要较新版本的 tailscale）。
- Claude Code CLI 使用 `http://localhost:<随机端口>/callback` 回调，按约定“只允许 https”目前会被拒；需要时再放开回环地址。

## 脱敏运行诊断

`serve --log-dir <本机日志目录>`（或 `I_REMOTE_MCP_LOG_DIR`）把诊断追加到按 UTC 日期分开的 `YYYY-MM-DD.jsonl`。未指定目录时，CLI 将相同 JSONL 写到 stderr；直接嵌入 `createApp()` 时，诊断默认不输出。

每个完成的 HTTP 请求产生 `http_request`；每条实际经过 RPC 处理器的消息另产生 `mcp_rpc`。每行都有 `timestamp`（UTC ISO 8601）、`method`、`path`、`status`、`ua_family`、`origin`。UA 只保留固定家族：`claude`、`edge`、`firefox`、`chromium`、`safari`、`curl`、`node`、`python-httpx`、`python-requests`、`other` 或 `absent`；客户端可伪造 UA，因此家族不能证明来源。

- GET `/authorize` 额外记录 `callback` / `resource`；只保留已知 Claude callback 和本服务 resource（保留尾斜杠差异），去除账号、密码、query 和 fragment。Origin 仅保留已知 Claude 或本服务来源。未知 URL（包括额外配置的 callback）统一为 `[redacted]`，缺失为 `null`。它们用于判断是否带参和已知端点是否匹配，不回显任意外部 URL。
- `mcp_rpc` 只记录白名单 `rpc_method` / `tool`、`outcome`（`success`、`error`、`no_response`）及必要的固定 `error_code`。未知方法或工具名为 `other`；JSON-RPC 错误为白名单数值码，工具错误为 `tool_error` 或 `data_source_unavailable`。HTTP 拒绝发生在 RPC 处理前时仅有 HTTP 状态，不能算作工具执行。
- 不记录原始 UA、Authorization / Cookie / session 头、请求 ID、IP、口令、授权码、token、其他 query、body、工具参数或结果内容、原始异常。未知 HTTP 路径和方法也替换为固定标签。旧 `log` 回调仍可接收脱敏的 method/path/status；不再接收异常正文。
- 日志基于响应 `finish`，说明本服务完成了响应写入，不代表远端客户端已接收或用户已验收；中途断开且未完成的响应不产生日志。诊断回调报错不会改变 MCP/OAuth 响应。落盘失败仅报告 `diagnostic_write_failed`，不输出路径或系统异常。每日分文件不自动删除旧日志。

已有私密运行目录可只更新 `server.mjs` 和新增 `diagnostics.mjs`，保持已有 `i_memory`、数据库、policy 和 OAuth 状态。嵌入启动器接线示例：

```js
import { createApp } from './server.mjs';
import { createJsonlDiagnosticWriter } from './diagnostics.mjs';
const diagnostic = createJsonlDiagnosticWriter({
  logDir: configuredLocalLogDirectory,
  onWriteError: (code) => process.stderr.write(`${code}\n`),
});
const { server } = createApp({
  stateDir, publicUrl, getReadModel,
  diagnostic, // 只将 createApp 投影后的记录交给 writer，不传原始请求或异常。
});
```

正式验收应分别看到 GET authorize 的 callback/resource/Origin、POST authorize / token 的成功 HTTP 状态，以及 `mcp_rpc` 中 `rpc_method: tools/call`、已知工具名和 `outcome: success`。这些日志没有改变 OAuth 元数据、MCP 工具定义或 JSON/SSE 行为；仍需实际 connector 完成授权与工具调用。


## day_get 事项标题（2026-10-06）

Core captures 模式的 `plan_reads` 继续使用独立只读凭据。除 `plan_weeks:read`、`plan_days:read` 外，可明确授予 `plan_items:read`；该凭据仍不能写规划或读取 captures/chat。`day_get` 单记录和分页结果会在原始 day/queues 外返回 `item_titles`（ID → title/revision）及 `item_title_issues`。缺事项权限、已删除或暂不可读的事项明确报问题，不猜标题。最多解析500个不同ID，保留原队列ID；事项标题是各自当前版本，不是跨领域原子快照。网页端不因此开放 `plan_list` 或规划写工具。

仅提交/合入源码不会修改现役 MCP、启用 Core captures 或签发生产凭据。按部署前审计的 D3，真实增改删闭环验收前继续保留47862记事桥，移交时只启用一个消费者。
