# P6-R4 A：真实 CLI 与合成 provider 工具行为

日期：2026-09-07。执行者：`/root/p6_r4_tool_behavior`，由主控复核及集成。
基线：`4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`。
隔离分支：`codex/whiteboard-w0-p6-r4-tool-behavior`。
承接 [R3 审计](P6_R3_EXECUTION_ISOLATION_AUDIT.md) 与 [R2 Runtime handoff](P6_R2_RUNTIME_PROFILE_HANDOFF.md)。

## 结论

**目录残留不全是不可执行的声明：在 `excluded` 配置下，`collaboration.list_agents({})` 实际返回本次合成根任务。零工具生产门控继续关闭，P6 未通过。**

同一配置下，合法 `functions.exec` 被明确拒绝，`request_user_input` 被 Default 模式拒绝。前者不是 JavaScript 格式错误；另一个仅打开 code-mode host / enabled 的对照成功计算 42、产生真实 cell ID，并用该 ID 成功执行 `functions.wait`。没有从列表查询推断 spawn、shell、真实文件或网络能力。

## 固定样例和结果

各例都启动自己的真实 CLI 进程、新临时 home 和空 cwd。函数调用使用 `function_call`、独立 `namespace` 与 `name`、JSON `arguments`；exec 使用 `custom_tool_call` 与原始 JavaScript `input`，不把 JSON 字符串或代码围栏误当自由格式源码。

| 样例 | 具体调用 | 观察到的运行时结果 | 判定 |
|---|---|---|---|
| 动态工具正控 | 注册并调用 `synthetic_echo({value:42})` | App Server 发出 `item/tool/call`，合成回执 `SYNTHETIC_ECHO_42` 出现在下一 provider 请求的相同 call ID 输出 | 动态调用链实际执行；只证明这条动态工具链 |
| excluded / exec | `functions.exec`，`text(6 * 7);` | `code-mode host is disabled` | 明确运行时拒绝；不是解析失败 |
| excluded / list | `collaboration.list_agents({})` | `{"agents":[{"agent_name":"/root","agent_status":"running"}]}` | 合成根任务查询实际执行；不是 spawn/电脑操作证明 |
| excluded / input | 一个完整合成问题，含 id/header/question/两个 options | `request_user_input is unavailable in Default mode` | 当前模式明确拒绝；不能外推为所有模式禁用 |
| enabled 对照 / exec + wait | exec pragma `yield_time_ms=1`，内存定时器 200ms 后 `text(6 * 7)`；随后用实际返回的 `cell_id="1"` 调用 `functions.wait` | `Script running with cell ID 1`，随后 `Script completed` 与 `42` | 内建 freeform 处理器与真实等待链实际执行，仅证明纯 JS evaluator |
| enabled 对照 / 解析负控 | `functions.exec`，`text(;` | `Script failed` 与 `SyntaxError: Unexpected token ';'` | 合法传输到达解析器后的源码解析错误；不算工具禁用 |

所有 6 个 turn 均有匹配的 `turn/completed`、`status=completed`；6 个归本探针所有的 CLI 进程均确认退出。动态正控以外没有发给宿主的 server request。合计 13 个 provider 请求均为 loopback `/v1/responses`，所有模型响应由固定合成服务生成。

这里的 `completed` 是探针轮次结束，不表示工具成功、生产隔离成立或真人 Gate 通过。脚本分别记录调用、输出、解析/策略/执行分类、终态和进程退出。`behavior_checks_passed=true` 只表示六个行为断言一致；`production_isolation_passed` 固定为 `false`。

## 边界与安全检查

- 保留 R3 `excluded` 限制；对照只改变 `features.code_mode_host` 与 `features.code_mode.enabled` 两个布尔值。排除 functions/collaboration/skills/clock/web 的列表、关闭 shell/apps/plugins/multi-agent 等设置不变。
- CLI 仅配置合成 loopback provider，`requires_openai_auth=false`，无 auth/env_key；启动前钉住 exe SHA-256。读取 config/read 和 requirements 后再核对实际 provider、URL、认证要求、配置层、MCP、hooks，未知/非空管理配置拒绝继续。
- 子进程只继承列明 OS 运行变量；HOME/USERPROFILE/CODEX_HOME/APPDATA/LOCALAPPDATA/TEMP/TMP 指向本次临时目录，不继承真实 token、proxy 或 Codex 会话变量。未读取真实 auth、DB、私人对话或实际项目内容。
- 固定 provider 不接受认证头、压缩、其他路由或方法；每例至多 5 请求、每请求至多 2 MB；仅允许计划内的动态回声回执，其余宿主请求拒绝。
- 仅执行纯内存整数计算、定时器、合成根列表；没有用真实文件读写、外部网络请求、shell、App/Bridge/手机或真实 P6 task 作样例。配置/路由检查不是完整 OS 网络隔离证明。
- 进程关闭只针对自身句柄。超时分支请求 interrupt 后等待对应 `turn/completed`，不会仅凭 interrupt ACK 发终止成功；本轮没有发生该超时分支。

## 未测与证据缺口

- `excluded` 下 exec 不能产生有效 cell ID，因此该配置的 `functions.wait` 未投递；未用假 ID 报禁用。enabled 对照的有效 wait 结果不能外推到 excluded。
- 没有证明合成 child thread 继承隔离，因此未调用 spawn，也未调用 followup/send/interrupt/wait_agent；未创建子线程，未用假 target/no-op 推断禁用。list_agents 的成功只覆盖一个只读工具。
- 未测试 Plan 模式、真实 shell/文件/网络能力，也不推广到其他 exe、配置或未来版本。目录隐藏与工具实际拒绝是不同证据。
- 没有修改生产 adapter/profile/client，未放宽 `tools_disabled` Gate，未 commit/push/build；未将本包测试等同 P6 或 Goal 1 完成。

## 交付与复跑

仅新增以下三个文件；主控预先复制的 14 个只读 overlay 差异全部保留，不属于本包交付：

- `tools/dev_agent_bridge/workbench_tool_behavior_probe.mjs`
- `tools/dev_agent_bridge/workbench_tool_behavior_probe.test.mjs`
- 本 handoff。

受测 CLI：`C:/Users/ExampleUser/AppData/Local/OpenAI/Codex/bin/8e5b6932251c2c1c/codex.exe`，initialize 版本 `0.153.4`。
SHA-256：`e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75`。

```powershell
& D:/Nodejs/node.exe --test tools/dev_agent_bridge/workbench_tool_behavior_probe.test.mjs
& D:/Nodejs/node.exe tools/dev_agent_bridge/workbench_tool_behavior_probe.mjs C:/Users/ExampleUser/AppData/Local/OpenAI/Codex/bin/8e5b6932251c2c1c/codex.exe
```

最终报告：`C:/Users/ExampleUser/AppData/Local/Temp/hereiam-tool-behavior-probe-9s5uio/report.json`。六个子目录各有独立 report 与原始合成请求。之前的 `SPfZt5` 为五例探索，`xvtjRM` 为增加解析负控后的中间版；最终判定使用 `9s5uio`，临时证据未纳入仓库。

验证：专项 **7/7 通过**，最终六例行为断言通过，脚本退出码 0；语法检查通过。测试覆盖合法 wire 形态、输出/call ID 绑定、拒绝/解析/执行区分、错误正控文本防误报及隔离检查。`git diff --check` 通过。主控负责独立复核、选择性集成与全局状态/closeout。

官方依据：[App Server](https://learn.chatgpt.com/docs/app-server)、[Responses 工具协议](https://developers.openai.com/api/reference/typescript/resources/beta/subresources/responses/methods/create)。官方文档用于协议核对；上述受测工具行为结论来自真实 CLI 与合成 provider 回执，不由文档或配置回显推断。
