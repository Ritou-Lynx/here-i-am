# P6-R2-C2 Runtime 文本权限探针与关闭门控

日期：2026-09-07。工作包：`p6_r2_runtime_profile`。基线：`4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`。
分支：`codex/whiteboard-w0-p6-r2-runtime-profile`。按主窗最新指令保持未提交最小 diff，供选择性集成；无 push。

## 结论

**当前 CLI 的受测配置未实现零工具隔离，真实后台文本执行保持关闭。** 新 Bridge 对固定 `workbench_text_only_v1` 请求返回明确不可用；不创建、恢复或复用普通 persona 会话。未改变普通 Runtime 路径、账号、全局配置、真实 Bridge 或 App。

初版探针仅检查顶层 `tools` 缺失，曾误报为零工具，已向主窗和 B 撤回。正控发现 Codex 0.153.4 将目录放在 `input[type=additional_tools].tools`，修正版递归检查所有 `tools` 数组及 code-mode 工具声明。这是目录实测失败，不能降格为仅缺一份回执；也没有执行这些工具来推断权限。

## 实测证据与复跑

探针：`tools/dev_agent_bridge/workbench_text_only_probe.mjs`。
目录解析及负例测试：`workbench_text_only_probe_contract.mjs`、`workbench_text_only_profile.test.mjs`。

```powershell
& D:/Nodejs/node.exe tools/dev_agent_bridge/workbench_text_only_probe.mjs '<已核实的绝对 Codex exe 路径>'
& D:/Nodejs/node.exe tools/dev_agent_bridge/workbench_text_only_probe.mjs '<同一 exe 路径>' --catalog-control
```

- 受测 exe 的 initialize userAgent：`here_i_am_bridge/0.153.4`。
- exe SHA-256：`e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75`。
- 使用 child-only 新临时 home/工作目录及 allowlist OS 环境；不继承 API tokens、Codex 会话变量、proxy 或真实用户配置。没有复制认证凭据。
- 独立 AppServer 只配置 loopback 假 Responses provider，`requires_openai_auth=false`，未读取/刷新真实账号或连接云模型。假 provider 只发固定文本事件，不生成工具调用；所有 server request 都拒绝。
- 创建 thread 前核查配置层：临时 user config 为空，system config 为空，requirements 为 null，MCP 字典为空，hooks 所有事件为空数组。非空/未知 system 或 managed 层拒绝继续；未修改它们。
- 请求 thread/turn `environments=[]`，thread `runtimeWorkspaceRoots=[]`、`selectedCapabilityRoots=[]`、`dynamicTools=[]`、ephemeral、never/read-only，并尝试关闭 shell/apps/plugins/remote_plugin/multi_agent/JS/browser/image/skills 依赖等特性，`web_search=disabled`、`tools.view_image=false`。传入配置被回显不等于该选项受到运行时执行；探针以编译后的请求为证据。
- normal 最终报告：系统临时目录 `hereiam-text-only-probe-8FqXtT/report.json`，`passed=false`，固定文本 turn `completed`，server requests 为 0。
- 正控报告：系统临时目录 `hereiam-text-only-probe-EjpDwm/report.json`，`passed=false`、`control_detected=true`，额外 `synthetic_noop` 声明被准确检出。
- 探针最终脚本将 normal 隔离失败返回退出码 2，正控检出返回 0；退出码 0 的正控不表示隔离通过。上述报告生成于增加退出码行为之前，报告断言与最终脚本一致。
- 每次报告与 `synthetic-request.json` 只留在该次新临时目录；包含固定合成文本、CLI 内建工具/指令及临时路径。没有用户输入、真实账号凭据、私人数据库或真实项目文件内容。不提交原始 payload 或这些运行产物。
- 临时目录内另有 CLI 自身生成的状态文件，保留原处，未清理或纳入交付。

实测保留目录如下；顶层 `tools` 仍然缺失：

| JSON 路径 | 名称 |
|---|---|
| `$.input[0].tools` | `functions`、`collaboration` |
| `$.input[0].tools[0].tools` | `exec`、`wait`、`request_user_input` |
| `$.input[0].tools[1].tools` | `followup_task`、`interrupt_agent`、`list_agents`、`send_message`、`spawn_agent`、`wait_agent` |
| `$.input[0].tools[0].tools[0].description` 内 code-mode 声明 | `skills__list`、`skills__read`；正控另有 `synthetic_noop` |

## 接口与兼容合同

调用者只从受控 Dart 入口传 `config.runtime_profile='workbench_text_only_v1'`。不把模型 payload 的 cwd/config/provider/tools 映射到此入口。B 拥有 Dart Runtime client；本包不修改 Dart。

Adapter 在 `_ensureReady`、thread/start、thread/resume 或现有 session 复用之前拒绝。未知/空/null 显式 profile 为 `invalid_request`，不会降级为普通会话。GET capabilities 增加 `runtime_profiles`，其中此 profile 为 `available=false`。

HTTP start/resume：501，沿用已有 error envelope：

```json
{"experimental":true,"error":{"schema_version":1,"code":"unsupported_capability","message":"The text-only runtime isolation has not been verified.","retryable":false,"operation":"startSession","details":{"profile":"workbench_text_only_v1","available":false,"reason":"text_only_isolation_unverified","fail_closed":true}}}
```

resume 的 operation 是 `resumeSession`。即使请求混入能力开启项或伪造 receipt，也走相同拒绝；不接触 provider。本包不生成成功回执。

B/主窗约定未来成功响应至少具有：

```json
{"execution_profile_receipt":{"profile":"workbench_text_only_v1","version":1,"isolation_verified":true,"tools_disabled":true}}
```

这是未来实现必须验证的合同，不是可以由请求者自报的许可。旧 Bridge 可能忽略新增 config 并返回普通会话 200；Dart 必须在任何 turn 前严格检查 profile/version/两个 boolean，缺失或不符时拒绝，绝不能 fallback。后续实现还必须用当前进程、CLI/配置/能力目录的证据来支撑回执，不能仅凭版本号、请求字段回显、无 dynamicTools 或模型自述发 true。

未来 close 成功至少具有：

```json
{"stop_receipt":{"profile":"workbench_text_only_v1","version":1,"session_id":"<本次本地session_id>","provider_terminal_confirmed":true}}
```

现有 `closeSession` 在 `client.isReady=false` 时会本地写 interrupted 并返回 closed；**这不能支撑 terminal stop 回执**。专用 profile 本轮无法创建，因此不会进入此路径。本包不改普通 close 行为。未来启用时，离线/超时/仅接受 interrupt 都不得发 confirmed=true，应返回 `stop_unconfirmed`；只有真实对应 turn terminal 证据才能确认。Dart 必须拒绝缺失、不匹配或 false 的 stop receipt。

## 修改与验证

拥有路径仅限：

- `tools/dev_agent_bridge/codex_app_server_adapter.mjs`：固定 profile 前置拒绝、capabilities 不可用声明。
- `tools/dev_agent_bridge/experimental_runtime_api.mjs`：unsupported_capability 对应 HTTP 501。
- `tools/dev_agent_bridge/experimental_runtime_api.test.mjs`：HTTP start/resume 拒绝与零启动断言。
- `tools/dev_agent_bridge/workbench_text_only_profile.mjs`：固定 profile 名和拒绝合同。
- `tools/dev_agent_bridge/workbench_text_only_profile.test.mjs`：复用/覆盖/伪造回执拒绝、目录检测负例。
- `tools/dev_agent_bridge/workbench_text_only_probe.mjs`：显式手动合成探针。
- `tools/dev_agent_bridge/workbench_text_only_probe_contract.mjs`：完整请求目录提取。
- 本 handoff。

Node 专项及相邻回归：`workbench_text_only_profile`、`codex_app_server_adapter`、`experimental_runtime_api`、`codex_app_server_client` 四组共 **31/31 通过**。`git diff --check` 通过。无 Flutter/Dart 构建、设备/App/DB 操作、真实 Bridge 重启或真实账号探测。

下一步由主窗集成拒绝门控和 B 的队列生命周期代码，产品明确呈现受限失败；真实文本执行和相关 P6 真人 Gate 仍未通过。本包不扩展为独立登录、复制凭据、新计费 provider、放开沙箱或通用工具权限系统。

官方核对来源：[App Server](https://learn.chatgpt.com/docs/app-server)、[配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)。官方配置项及本地 schema 只支持尝试限制；本机最终实测结果优先，不将文档布尔项推断为零工具保证。
