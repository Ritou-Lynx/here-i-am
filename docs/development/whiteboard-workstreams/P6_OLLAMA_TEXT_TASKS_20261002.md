# P6 长任务改走 Ollama 纯文本（2026-10-02）

## 决定

用户确认长任务改用 Ollama（已订阅云端模型），简化优先。每次执行尝试只发一个不带工具的 `/api/chat` 流式请求，本机不执行任何东西。因此生产路径不再需要 Codex CLI 文字 profile、WFP / Job / 提权 helper、Witness 与批次授权，也就没有 UAC 弹窗。暂停、取消和宿主退出都在应用进程内中断请求，停止结果可以如实确认。

## 改动

- 新增 `lib/data/workbench_ai/task_queue/ollama_text_task_gateway.dart`：环境配置、Ollama 网关、未配置后端和生产默认选择。
- 执行引擎 `WorkbenchTaskQueueExecution` 的持久化、租约、幂等，以及暂停 / 恢复 / 取消 / 重试语义都不变。新增开始前可用性检查：未配置时直接拒绝，任务保持 pending，不消耗重试次数。新增错误码 `text_task_model_unconfigured`，工具宿主给出中文提示。
- `WorkbenchRuntimeTaskQueueTool.production()` 默认使用 Ollama；未配置或配置不安全时 fail-closed。旧的 Bridge 文字 profile 客户端保留给 P6-R7 验收入口和既有测试，生产不再引用。

## 配置（Windows 用 `setx` 后重启 App）

| 变量 | 作用 |
|---|---|
| `HIA_TASK_OLLAMA_MODEL` | 必填。不设置时长任务保持关闭 |
| `OLLAMA_API_KEY` | 直连 ollama.com 时设置；设置后默认地址为 `https://ollama.com` |
| `HIA_TASK_OLLAMA_URL` | 可选，覆盖地址；只允许 https 或本机 http |

- 直连云端：`setx OLLAMA_API_KEY <key>`，`setx HIA_TASK_OLLAMA_MODEL gpt-oss:120b`（直连时模型名不带 `-cloud`）。
- 本机 Ollama 应用登录后：只设 `setx HIA_TASK_OLLAMA_MODEL gpt-oss:120b-cloud`，地址默认 `http://127.0.0.1:11434`。

长任务的目标文本和已保存的部分结果会发送到所选 Ollama 端点；请求里不附带人格、记忆或聊天记录。

## 验证

- `test/data/workbench_ai/task_queue/ollama_text_task_gateway_test.dart`，12 项：本地假 Ollama 走真实 HTTP 流，配合真实执行引擎和内存库，覆盖配置选择与拒绝、完成结果精确落库且请求不含 `tools`、HTTP 拒绝后重试成功、中途 provider 错误、长度截断不算完成、断流后显式恢复并带上部分文本、暂停后恢复、取消、宿主退出确认清理，以及未配置时任务保持 pending。
- 相邻回归：`test/data/workbench_ai`、`test/domain/workbench_ai`、`test/ui/desktop` 和两个 P6 验收入口目录，494 过、11 跳；改动文件 analyze 无问题。
- 真实模型：`ollama_live_test.dart` 默认跳过。GitHub `Ollama live check` 会在 runner 上安装 Ollama，用 `qwen2.5:1.5b` 跑一个结果确定的任务；云端作业只能手动触发，需要仓库 secret `OLLAMA_API_KEY` 和模型名。
- Windows 构建和白板集成测试以 GitHub CI 为准。

## 未完

- 在真实 App 里跑一次长任务，看结果呈现与体验：属于真人主观项，异步看结果即可。
- 旧原生隔离链路（C# helper、Witness、批次授权、P6-R7 验收入口）已不在生产路径上，是否删除另行决定。
- AGENTS.md 里"工作台长任务生产执行保持拒绝"这条：默认仍 fail-closed，配置模型即启用；是否改写这条规则由用户决定。
