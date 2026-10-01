# W5-R1 — RuntimeAdapter / Codex App Server 产品化纵切交接

> 状态：完成
>
> 日期：2026-08-21
>
> 工作流：W5-R1 / AI 操作层 RuntimeAdapter

## 1. 本轮闭环

在 Dev Agent Bridge 内冻结 provider-neutral JavaScript `RuntimeAdapter`、标准事件和标准错误形状，将 Phase A 的 `CodexAppServerClient` 接成 `CodexAppServerAdapter`，并新增默认关闭、仅回环可访问、路径显式带 `experimental` 的本机 HTTP 入口。

入口已用确定性 fake App Server 从头覆盖：模型发现与校验、session start、provider session resume、turn start、游标事件读取、活动态后 steer、interrupt、approval 请求与显式回答、fail-closed session close、App Server 异常退出后的同 adapter 重连，以及 Bridge 停止前的子进程清理。自动化测试没有调用真实模型。

旧 `POST /v1/runs`、`commandFor('codex')` 与 `codex exec --json` 主路径保持原样；只有设置 `DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER=1` 时，health 才声明 `experimental_runtime_adapter_v1`。

## 2. 冻结协议

### RuntimeAdapter 能力

- `getAuthStatus()`
- `listCapabilities()`
- `startSession(config, contextManifest)`
- `resumeSession(providerSessionId, config)`
- `startTurn(sessionId, input)`
- `steerTurn(sessionId, turnId, input)`
- `interruptTurn(sessionId, turnId)`
- `respondToApproval(requestId, decision)`
- `streamEvents(sessionId)`；另提供 HTTP 轮询所需的 `readEvents(..., afterSequence)`
- `closeSession(sessionId)`

事件 `schema_version=1` 的稳定字段为 `event_id / sequence / occurred_at / session_id / turn_id? / kind / status? / data / provider_metadata?`。标准 kind 为 session / turn 状态、activity、message / delta、tool call / result、approval request / resolved、usage、warning、error。

错误 `schema_version=1` 的稳定字段为 `code / message / retryable / operation? / details? / provider_metadata?`。模型不可用、认证、session / turn / approval 不存在、活动态冲突、超时、provider 与 protocol 错误均有独立 code；HTTP 层据此返回确定性状态码。

Codex thread ID 只出现在 `provider_metadata.provider_session_id`，不升格为产品 session 身份；adapter 每次本地恢复产生新的 runtime session ID。

## 3. Codex adapter 行为

- App Server 初始化后并行读取 `account/read` 与 `model/list`；请求模型必须命中实际列表，否则在 `thread/start` / `thread/resume` 之前以 `model_unavailable` fail-fast。
- 不升级 CLI、不写入或覆盖用户全局 Codex 配置。
- App Server notification 投影为中立事件；provider method、item ID 与 provider status 只进入 `provider_metadata`。
- App Server 主动 approval request 被保存为待答请求；未知 server request 明确拒绝，找不到所属 session 的 approval 默认 decline，绝不自动放行。
- `steerTurn` 不把 `turn/start` 响应或 `turn/started` 当作可转向证明。它等待属于同一 turn 的 `item/*/started` 或 delta 活动事件，并在监听器安装后重新检查一次，覆盖活动事件恰好落在检查 / 订阅间隙的竞态；turn 已终止或等待超时会返回真实标准错误。
- client `stopped` 会使 `_readyPromise / account / models` 全部失效，清除已失去 provider 的 approval callbacks，并把原 session 标为 `unavailable`。下一次 auth / start / resume 在同一 adapter 上重新执行 initialize、`account/read` 与 `model/list`；resume 为原 provider thread 建立新的 runtime session，不复活旧的 unavailable session。
- `closeSession` 的冻结语义是 **interrupt-and-wait，不是 detach**：先从 map 删除本 session 的全部 approval callback 并向仍在线的 provider 发送 decline，再对仍活动 turn 请求 interrupt、等待对应 `turn/completed`，最后删除 provider binding 并写 closed event。关闭后的事件历史仍可读取，迟到的 approval answer 只返回 `approval_not_found`，不会再向 provider 发送决定。
- App Server 可在 `turn/start` response 之前发送 `turn/completed`。adapter 保留先到达的 terminal turn / idle session 状态，response 不得将其重写为 running / active；乱序 fixture 已覆盖，随后还能正常启动下一 turn。

## 4. Experimental 本机入口

前缀：`/experimental/v1/runtime`；响应头：`x-hereiam-experimental: runtime-adapter-v1`。入口默认关闭且只接受 loopback，覆盖 auth、capabilities、session start / resume / close、turn start / steer / interrupt、events cursor read、approval answer，以及供停止脚本使用的 `host/stop-app-server`。

JSON 请求体上限为 256 KiB；超限或 malformed JSON 统一投影为 `invalid_request` / HTTP 400。`activity_timeout_ms` 必须是有限正数，负数、0 与 Infinity 均在调用 provider 前被拒绝。

可选 `DEV_AGENT_EXPERIMENTAL_CODEX_MODEL` 作为实验入口默认模型。测试专用的 App Server command / args 只能通过显式 experimental 环境变量注入，不影响旧 Bridge agent 命令解析。

## 5. 修改与拥有路径

- 新增 `tools/dev_agent_bridge/runtime_adapter.mjs`
- 新增 `tools/dev_agent_bridge/codex_app_server_adapter.mjs`
- 新增 `tools/dev_agent_bridge/experimental_runtime_api.mjs`
- 新增对应 adapter / HTTP 纵切测试
- 更新 fake App Server，使过早 steer 确定性失败，并修正 Phase A client 测试先等待活动事件
- `dev_agent_bridge.mjs` 只增加 gated experimental 路由与 health feature；旧 run 路由未改
- `stop_bridge.ps1` 先调用 loopback cleanup 等待 App Server 子进程退出；入口不可用时递归清理 Bridge descendants，再 Force 停父进程
- 更新 `tools/dev_agent_bridge/README.md`

未修改 Flutter、schema、白板领域、路由、`I_PROJECT_STATE.md` 或 `DEVLOG.md`；未 commit / push。

## 6. 验证

- Dev Agent Bridge Node 全量：29 / 29 通过；原 Bridge 13 / 13 仍通过。使用 `--test-concurrency=1` 避免 Windows 同时拉起多个 Node test worker / fake server 时的进程启动争用。
- 新增确定性覆盖：Runtime event / error 精确形状、auth / capability / model discovery、模型 fail-fast、turn event cursor、活动态 steer 竞态、interrupt、approval、adapter 替换后 resume、同 adapter client exit → reinitialize → resume、pending approval close fail-closed、active turn close interrupt-and-wait、completed-before-response 乱序、请求体上限 / malformed JSON / timeout 参数、cleanup endpoint 等待 App Server stdin close 与 process exit。
- Bridge 下全部 14 个 `.mjs` 文件 `node --check` 通过，`stop_bridge.ps1` PowerShell AST 解析无错误。
- 没有运行真实 App Server probe，没有调用真实模型，没有修改全局 Codex 配置。

## 7. 恢复与兼容

- Bridge 默认配置下不会启动 App Server，旧 `codex exec` 行为不变。
- 关闭 experimental 开关即可完全撤下新 HTTP 表面；代码回退不要求迁移 state 或数据库。
- provider session resume 在新 adapter / Bridge 生命周期中重新建立本地 runtime session；同一 adapter 的 client 意外退出后也会失效 readiness 并重新 initialize，再按同 provider thread ID resume。Phase A 已单独证明真实 App Server 进程重启后同 thread ID 可恢复。
- `stop_bridge.ps1` 不再假设 Force 停父进程会触发可靠的子进程 EOF：它先调用 `host/stop-app-server`，确定性 fixture 证明该响应返回前子进程已记录 `stdin_closed` 与 `process_exit`；若本地 endpoint 因自定义 HTTPS 等原因不可用，脚本显式递归停止 Bridge descendants 后再停止父进程。
- 本轮 runtime session、事件与 approval map 仍为 Bridge 进程内状态，没有写永久 schema；这是进入 `RuntimeSessionBinding` 设计前的有意停点。

## 8. 未完事项 / 下一接入点

1. Context Envelope 与产品持有的 `RuntimeSessionBinding` 尚未接入；`context_manifest` 当前仅由 adapter 保留，不注入 Codex prompt。
2. 事件标准已冻结形状，但 tool call / result 的 Codex item 细分投影需在只读 Tool Host 纵切按真实事件 fixture 补齐。
3. approval 超时策略与 Permission Broker 尚未实现；当前不会自动批准，产品接入前需定义超时 decline / cancel 与审计。
4. experimental session / event 恢复仍依赖上层 binding；正式持久化、schema、Flutter 行动卡片与详情抽屉不在本轮。
5. 下一闭环按权威架构进入 `Context Envelope + RuntimeSessionBinding`，随后才是只读 Here I am Tool Host；任何 schema 或共享 WhiteboardOperation 变更回到 W0 / W5 集成评审。
