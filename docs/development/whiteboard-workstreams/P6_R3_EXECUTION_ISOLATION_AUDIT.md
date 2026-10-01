# P6-R3 执行隔离复核（2026-09-07）

## 结论与范围

承接用户“继续”，在现有 Goal 1/P6 内复核 R2 剩余阻断，不新建 Goal。基线仍为 `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b` + 已集成未提交的 R2 源；本轮只改合成探针/检测测试及状态文档。

**本机 CLI 0.153.4 的三组追加配置均未形成零工具目录；生产执行仍关闭，P6 未通过。** 该结论限定于受测版本、配置和当前公开接口，不宣称所有未来版本或其他执行架构都不可能隔离，也不把广告中的工具目录直接当作已执行动作。

主控 `/root`（Astra）负责探针与最终判定；只读子 Agent `/root/p6_r3_capability_audit`（Terra medium）独立核查官方文档和本地协议字段，无写入或真实调用。普通聊天、队列执行核心、真实 Bridge/App/手机和等待任务未操作；没有读取凭据、实际数据库或私人对话，没有发真实模型请求。

## 当前追加证据

受测 exe SHA-256：`e5aa76d19c7c94e2e9ef9b707d590206a73ac0e97c8ddc8382181242494bef75`。各次使用新的临时 home/空工作目录、最小子进程环境、loopback 假 Responses provider；MCP/hooks/managed 配置检查沿用 R2。所有响应为固定合成文字；server requests 均为 0，文字 turn completed 不算隔离通过。

| 变体 | 追加限制 | 实际完整目录 | 判定 / 临时报告目录后缀 |
|---|---|---|---|
| `strict` | 额外关闭 code-mode host、goals、sleep、skill search、tool suggest、multi-agent-v2 等；`code_mode.enabled=false`、跳过 host skill 发现 | `functions` 3 项、`collaboration` 6 项；exec 内仍有 2 个 skills 声明 | 未通过；`34tzIz` |
| `excluded` | 在 strict 上排除 functions/collaboration/skills/clock/web 的 code-mode 命名空间 | skills 声明消失；外层 functions 3 项与 collaboration 6 项仍存在 | 未通过；`OSCION` |
| `code-mode-excluded` | 保留排除列表，开启 code mode 与 host 检查排除规则是否只在启用时生效 | 外层 functions 3 项与 collaboration 6 项仍存在 | 未通过；`73FWEz` |
| baseline 正控 | 明确注入 `synthetic_noop`，检测完整目录/嵌套声明，不搜索普通文本 | 正确检测到 synthetic_noop；其余工具仍在 | 检测器正控通过，隔离未通过；`ZigdWK` |

`strict` 是本探针的变体名，不代表已使用 CLI `--strict-config`。`OSCION` 的 config/read 确认相关关闭值、排除列表与 requirements=null；这些回显不等于实际能力禁用。code-mode host 关闭时运行时会提示其执行器拒绝工作，但尚无对应证据证明外层协作工具全被禁止，不能据此签发 `tools_disabled=true`。

报告留在系统临时目录 `hereiam-text-only-probe-<后缀>/report.json`，原始合成请求也只留在该目录，不纳入交付。复跑入口：

```powershell
& D:/Nodejs/node.exe tools/dev_agent_bridge/workbench_text_only_probe.mjs '<已核实的绝对 Codex exe 路径>' --variant=excluded
& D:/Nodejs/node.exe tools/dev_agent_bridge/workbench_text_only_probe.mjs '<同一 exe 路径>' --catalog-control
```

## 接口审计与下一决定

- 当前生成的 thread/start、turn/start 协议没有内建工具全局 allowlist 或 tools/tool_choice 字段；`dynamicTools` 是附加工具，`environments=[]` 仅禁用环境访问。`multiAgentMode` 已标为 deprecated/ignored，不能用它去除协作工具。
- `features.code_mode.excluded_tool_namespaces` 作用于 code-mode 内的工具指导/执行暴露，不是外层目录的全局禁用。实测与此边界一致。
- `codex exec --ignore-user-config --ephemeral` 可跳过用户配置而沿用认证目录；这是 CLI help 中的候选能力，不是 App Server 接口，也未证明可禁用内建工具/host skills。没有改接此路径或用真实账户测试。
- 纯文本模型 API 是待用户选择的替代路线：不注册工具、保留当前 TaskRoom owner/幂等/结果持久化，普通聊天仍走现有 Codex。它可能涉及独立的 provider、凭据或计费，不能自动视为现有 Codex 登录可用；必须先确认接入来源再实施，不复制认证或直接发付费请求。
- 若坚持现有 Codex 通道，保留拒绝门控，等待可验证的限制机制或另行确认更完整的进程隔离架构；不能用提示词约束替代运行时边界，也不降低 P6 完成定义。

## 本轮修改与验证

- `workbench_text_only_probe.mjs`：保留 baseline，加入三组可复跑变体；正控仅依据解析后的工具目录。
- `workbench_text_only_probe_contract.mjs`：新增 compiled-tool 存在检查。
- `workbench_text_only_profile.test.mjs`：新增负例，普通文本出现测试工具名不算正控命中。
- Node 四文件专项/相邻回归 **32/32**；探针语法检查通过。没有 Dart 修改，R2 的 122/122 保留为上一轮证据，未重新构建或声称新增真人通过。

官方核对：[配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)、[App Server](https://learn.chatgpt.com/docs/app-server)。替代 API 的明确工具选择能力见 [Function calling](https://developers.openai.com/api/docs/guides/function-calling)；不把 API 的 `tool_choice=none` 推断为 Codex App Server 支持同名参数。
