# W5 — Codex App Server Phase A 交接

> 状态：完成
>
> 日期：2026-08-21
>
> 工作流：W5 / AI 操作层 Phase A

## 1. 本轮闭环

在 Windows 本机证明 Dev Agent Bridge 可以使用用户现有 ChatGPT 登录驱动 Codex App Server，同时不改变 Flutter 产品协议、Memory V3 schema、白板 Card / Board / Anchor / Snapshot / PlayerAdapter 语义，也不替换旧 `codex exec` 主路径。

新增的隔离适配层覆盖：

- App Server 进程启动、initialize / initialized 握手、优雅停止与异常退出；
- `account/read` 与 `model/list`；
- thread start / resume / fork / read / list / name / archive；
- turn start / steer / interrupt 与完成等待；
- JSONL notification、server request、审批响应、超时和悬挂请求回收；
- Bridge 进程停止后，用同一 thread ID 恢复工作。

## 2. 拥有路径

- `tools/dev_agent_bridge/codex_app_server_client.mjs`
- `tools/dev_agent_bridge/codex_app_server_client.test.mjs`
- `tools/dev_agent_bridge/codex_app_server_probe.mjs`
- `tools/dev_agent_bridge/test_fixtures/fake_codex_app_server.mjs`
- `tools/dev_agent_bridge/README.md`

Phase A 没有修改 Flutter、路由、数据库、生成文件和白板共享领域对象。旧 `tools/dev_agent_bridge/dev_agent_bridge.mjs` 仍以 `codex exec --json` 工作，后续只能在单独纵切中接入新 adapter。

## 3. 真实验收结果

最终报告位于忽略目录 `build/codex_app_server_phase_a_report.json`，报告不保存邮箱、提示词、回复正文、凭据或私有推理。

| 验收项 | 结果 |
|---|---|
| 认证 | `chatgpt`，套餐回报 `pro` |
| 模型发现 | 当前 CLI 暴露 4 个模型；验收显式使用 `gpt-5.5` |
| 持久 thread | 创建、命名、两轮执行、进程停止 / 重启后同 ID resume、read 均通过；ephemeral fork 保留两轮历史且 ID 独立 |
| 原生客户端可见性 | Codex Desktop 能按同一 thread ID 找到命名任务，且归档后出现在归档列表 |
| 事件流 | turn、item、message delta、token usage、rate limit、thread status、审批解决事件均收到 |
| 转向与停止 | 临时 thread 等待首个 message delta 后 steer 成功，interrupt 最终状态为 `interrupted` |
| 审批 | 真实 `item/commandExecution/requestApproval` 被客户端回绝，目标文件不存在，turn 正常完成 |
| 自动化回归 | Dev Agent Bridge Node 测试 13/13 通过；新增脚本语法检查通过 |

全部持久探针任务均已归档；控制、fork 与审批使用 ephemeral thread，不污染普通任务历史。

## 4. 已确认的运行约束

1. `turn/start` 返回不等于 turn 已经可 steer。生产协调器必须等待能证明模型开始生成的活动事件，再允许转向；失败时需向上层返回真实竞态，不得伪装成功。
2. 当前全局 Codex CLI 为 `0.142.4`，`model/list` 返回 `gpt-5.5`、`gpt-5.4`、`gpt-5.4-mini`、`gpt-5.3-codex-spark`。桌面配置中的 `gpt-5.6-sol` 需要更新 CLI；Phase A 没有擅自升级 CLI或修改全局配置。
3. 生产 adapter 必须在启动时发现并校验模型。请求模型不可用时 fail-fast，并把“客户端 / CLI 版本不匹配”作为可解释错误上报。
4. App Server 与 Codex Desktop 的持久 thread 可共享，但产品连续性仍属于 Here I am 的 `conversation_id` 与 runtime binding，不能反过来把 Codex thread 当人格或产品对话真相。
5. 审批请求是服务端主动 JSON-RPC request，不是普通 notification；必须由 Permission Broker 明确答复，超时不能自动放行。

## 5. 未完事项与下一纵切

Phase A 只证明运行时可用，不代表产品已经接线。后续按权威架构推进：

1. 冻结 provider-neutral `RuntimeAdapter` / event / error 契约，并把 `CodexAppServerClient` 接到 Bridge 的一个受控实验入口；
2. 建立 `ContextEnvelope` 与 `RuntimeSessionBinding`，但暂不新增永久 schema；
3. 建立只读 Here I am Tool Host，首个闭环只读取当前白板选择、Card / Source 内容和 Board 关系；
4. 上述契约稳定后，再做可撤销 `WhiteboardOperation` batch 和产品行动卡片。

并行时必须隔离 worktree。Bridge adapter、Flutter binding / product projection、只读 Tool Host 三条线不得静默修改对方契约；任何 schema、共享 operation 语义和最终集成都回到 W0 / W5 集成窗口。
