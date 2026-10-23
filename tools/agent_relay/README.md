# Agent Relay：Claude 规划审阅，Codex 本机执行，经 GitHub PR 自动接力

不再手动在两个窗口之间复制粘贴。Claude 只能用网页端，所以它留在 claude.ai/code 云端；Codex 在电脑上执行；两边通过同一个 PR 的评论交接。

```
你 ──一句话目标──▶ Claude（claude.ai/code 云端会话，订阅 PR）
                    │ ① 开 PR：任务合同 + 第 1 轮指令 [to-codex]
                    ▼
                GitHub PR ◀─────────────────────────────┐
                    │                                    │ ③ 推送 + 回帖 [to-claude]
                    ▼                                    │
     电脑上的 watcher（每 3 分钟看一次）─② codex exec─▶ Codex（PR 专用 worktree）
                    
     ④ 回帖唤醒 Claude → 读真实 diff 审阅 → 返修 [to-codex] / 完成 [done] / 问你 [to-human]
```

| 文件 | 给谁 | 作用 |
|---|---|---|
| [PROTOCOL.md](PROTOCOL.md) | 全部 | 交接契约：标签、评论标记、轮数、公开边界 |
| [BUILD_BRIEF.md](BUILD_BRIEF.md) | Codex | watcher 实现规格与测试清单 |
| [CODEX_ROUND_PROMPT.md](CODEX_ROUND_PROMPT.md) | watcher → Codex | 每轮执行提示词模板 |
| [`.claude/skills/agent-relay/SKILL.md`](../../.claude/skills/agent-relay/SKILL.md) | 云端 Claude | 发起、审阅、收尾的操作手册 |

## 做出来以后的效果

**你做的事只剩三件**：在 claude.ai/code 开会话说目标；手机收到通知时看一眼；最后自己验收并点合并。

一次典型接力：

| 时间 | 发生什么 | 你看到什么 |
|---|---|---|
| 0 分 | 你在 claude.ai/code 说“用接力做：给 X 加 Y” | — |
| ~10 分 | Claude 读代码、写合同、开 draft PR、发第 1 轮指令 | PR 出现，带 `agent-relay` 标签 |
| ≤3 分后 | watcher 接单，指令评论出现 👀 | — |
| +10~40 分 | Codex 实现、跑测试；watcher 提交、推送并回帖，评论变 🚀 | PR 里多了提交和一条 [to-claude] |
| +几分钟 | Claude 被唤醒，读 diff 审阅；不过关就发第 2 轮返修，循环 | PR 里一来一回的指令和结果 |
| 结束 | Claude 发 [done] 并 @你，列出需要你亲自做的事（构建、装机、真人体验） | **配置后通过微信 / Bark 收到提醒** |

中途 Codex 卡在需要你拍板的问题上，Claude 能按合同和仓库规则回答的就直接答；涉及产品取舍、权限、真实数据的才 @你。

**它不会做的**：不合并、不 force-push、不构建安装 App、不碰真实数据和账户。最多 4 轮（1 轮执行 + 3 轮返修），超了就停下 @你。

**限制，提前知道**：

- 电脑要开机、watcher 计划任务在跑；关机期间指令会排队，开机后 3 分钟内接上。
- 延迟主要是 Codex 的执行时间，加上最多 3 分钟轮询；不是实时聊天。
- 云端 Claude 没有 Flutter，审 Dart 改动靠读 diff 和 Codex 贴出的 analyze/测试结果；Node 工具它能自己跑测试复核。
- **仓库公开**，PR 和评论任何人可见。只适合源码工作；私人数据、生活资料、令牌永远不进 PR。
- 每轮都消耗 Claude 和 Codex 的额度。
- 随时叫停：给 PR 加 `relay-paused` 标签，或直接关闭 PR。

## 安装：交给 Codex

在**本仓库目录**里启动 Codex，按顺序发下面两段。

### 第一步：检查源码与工具

```text
确认运行 watcher 的主仓库已包含最新合并的 relay 实现，停在 v3-lab 或 detached HEAD，不占用 PR 分支。
读根目录 AGENTS.md 和 tools/agent_relay/PROTOCOL.md、README.md。
检查 node、gh、git 可用，核对 Codex 实际 exe 的安装布局；无需 npm install。
运行 node --test tools/agent_relay/relay_watcher.test.mjs tools/agent_relay/relay_core.test.mjs。
```

### 第二步：本机配置和计划任务

```text
帮我把 Agent Relay watcher 在本机装好，不改仓库源码。

1. 确认 gh auth status 和 codex login status 都是当前用户已登录；没登录就停下告诉我怎么登。
2. 用 gh 在 Ritou-Lynx/here-i-am 建三个标签（已存在就跳过）：agent-relay、relay-paused、relay-needs-human。
3. 复制 tools/agent_relay/relay.config.example.json 为 tools/agent_relay/.state/config.json，填本机 repoPath 和仓库外的 worktreeRoot；按实际安装布局填写 codexSearch，或用 codexPath 指向实际 exe，删除不用的占位字段。
4. 运行 node tools/agent_relay/relay_watcher.mjs --dry-run，贴输出。
5. 先用 install_relay_task.ps1 -ShowAction 只读预览，再注册计划任务（当前用户、每 3 分钟、conhost headless）；手动触发一次，核对 task-last.log 和实际 LastTaskResult。
6. 告诉我已经可以冒烟了。
```

### 第三步：冒烟（找 Claude）

在 claude.ai/code 对本仓库开会话，说“接力冒烟”。Claude 会开一个只改 `tools/agent_relay/SMOKE.md` 的小 PR。看到 👀 → 🚀 → [to-claude] → Claude 审阅 → [done] 走通即完成。首次冒烟同时核对 Claude 评论显示的作者账号，必要时加进 `allowedAuthors`。

## 日常用法

在 claude.ai/code 对本仓库开会话：

> 用接力做：<目标>。

Claude 会按 SKILL 手册开 PR、发指令、订阅 PR。之后你可以关掉网页，等手机通知。想插话就在 PR 里直接评论，或回到那个会话说。

## 手机通知

接力评论使用自己的 GitHub 账号发送，GitHub 不会通知自己。watcher 可用 PushPlus 推到微信，也可给 iPhone 加一份 Bark。

1. 在 [PushPlus](https://www.pushplus.plus/) 用微信扫码，取得自己的 token。可选：安装 iPhone Bark，复制设备 key；默认服务器为 `https://api.day.app`，自建服务器必须使用 HTTPS。
2. 仅在已忽略的 `tools/agent_relay/.state/config.json` 中添加 `notify`，填写 `pushplusToken`，可选填写 `barkKey` 和 `barkServer`。不使用的字段留空串；真实 token/key 不写进示例、PR、评论或提示词。
3. 合并并更新本机运行目录后，由用户执行测试并确认手机收到：

```powershell
node tools/agent_relay/relay_watcher.mjs --test-notify
```

命令打印各通道的 `ok` / `failed` / `off`。至少一个成功返回 0，全部失败或关闭返回 1。`--dry-run`（包括与 `--test-notify` 同用）只预览，不发通知、不写 state。

通知涵盖白名单作者的 `done`、`to-human` 第一行标记和 watcher 已投递的 failed 回帖；暂停或待人工处理的 open 接力 PR 仍会提醒。`to-codex` 以及 done/blocked 的 `to-claude` 不提醒。每个通道独立超时 10 秒，通知失败不改变接力结果。

首次启用只建立历史基线，不补发旧评论。新通知至少一个启用通道成功即视为送达；全部失败下次轮询补发，累计 3 次后停止。手机通知记录在顶层 `notified` / `notifyEnabledAt`，与 GitHub 回帖的 `comments[id].notification` 分开。两个通道都留空时输出“未配置通知通道”。源码验证全部使用假 fetch，不发送真实通知；手机实际送达留给合并后的用户验证。

## 已知坑（冒烟所得）

- 运行 watcher 的目录不能检出任何 PR 分支，否则 watcher 建不了 PR 专用 worktree（报 `already used by worktree`）。主仓库停在 `v3-lab`，或用 detached HEAD。
- Codex 启动时会尝试连接 config 里所有 MCP 服务，本机没开的会打印 `rmcp::transport` 报错，不影响执行。
- watcher 代码更新后要让运行它的目录跟上新提交，计划任务才会用到新逻辑。

## watcher 已实现（2026-10-07）

零 npm 依赖，源码使用 Node 22 支持的 `.mjs` 与内置模块。`package.json` 只有目录测试入口及运行版本声明，没有 dependencies；无需 `npm install`。清单 12 项均已写成离线测试，额外覆盖仓库归属、并发锁回收、通知恢复、分支历史保护和超时清理阻断。

```powershell
node --test tools/agent_relay/
node tools/agent_relay/relay_watcher.mjs --dry-run
node tools/agent_relay/relay_watcher.mjs --once --config tools/agent_relay/.state/config.json
node tools/agent_relay/relay_watcher.mjs --loop --config tools/agent_relay/.state/config.json
```

`--once` 是默认模式。`--loop` 使用 `pollSeconds`（默认 180）。`--dry-run` 只做读取和打印：没有本机配置时用当前仓库及默认白名单查询 PR，不创建配置、锁、日志或 state，不加反应、不运行 Codex、不推送和回帖。安装前应核对 `allowedAuthors`。

每次发现待处理评论后，watcher 在领取之前按 `codexSearch` → `codexPath` → PATH 解析 Codex，并用解析出的绝对路径启动。`codexSearch` 只列出 `root` 的直接子目录，`dirPattern` 必须以 `^` 开头、以 `$` 结尾；先校验每个候选，再用 `lstat` 读取通过校验的 exe 修改时间，选取 `mtimeMs` 最大的文件，时间相同时按目录名字典序取最大的。`relativeExe` 是不含 `..` 的相对路径。示例以 `^[0-9a-f]{16}$` 匹配散列目录，目录内为 `codex.exe`；路径仍是占位，须按实际安装布局替换或删除不用的字段。

`codexSearch` 和 `codexPath` 的候选必须为普通文件；文件及父目录中的符号链接或目录联接、主仓库和 worktreeRoot 内的路径都会被拒绝。PATH 保持通常的可执行文件查找行为。Windows 只接受 `.exe`，不能填 `.cmd`/`.ps1` shim。都找不到时只记录 `codex_not_found`，返回 `codex-not-found`：不领取、不计轮数、不回帖，下一次轮询重试；`--once` 和 dry-run 对该状态返回非零。dry-run 命令预览显示实际解析路径。每轮本机 `result.json` 记录 `codexSource`（`search`/`path`/`PATH`）和 `codexDir`（仅 exe 所在目录名）。

### 本机实际版本

2026-10-07 核对：

| 工具 | 实际版本与验证 |
|---|---|
| Node（原终端 PATH） | `v24.14.1`，全部 48 项通过 |
| Node 22（临时官方便携版） | `v22.23.3`，全部 48 项通过；未替换本机 Node |
| Codex | `codex-cli 0.160.0`，已先运行 `codex exec --help` 对齐参数 |
| GitHub CLI | `gh 2.102.0 (2026-09-30)`，官方便携包经 SHA-256 校验，已安装在固定用户程序目录；gh 与 Codex 的实际 exe 均经 Node spawn(shell:false) 验证，未改全局 PATH |

实际启动参数如下。提示词通过 stdin 传入，最后的 `-` 不省略；子进程环境加入 `SKIP_PROJECT_STATE=1`，不改全局配置。

```text
codex exec --cd <PR-worktree> --sandbox workspace-write --json --output-last-message <local-log.last.txt> -
```

本机固定 gh、登录检查、标签、持久配置及普通用户计划任务已安装完成。只读 dry-run 与计划任务实际执行均返回“无待处理”，LastTaskResult 为 0，未调用真实 Codex 执行任务；现在可按第三步通知 Claude 发起真实 PR 接力冒烟。

### 执行与恢复边界

- 所有进程调用经可注入 `run(cmd, args, opts)`；业务操作只调用 `gh`、`git`、`codex`。为满足 Windows 超时终止整棵进程树，另使用系统清理辅助 `taskkill.exe /PID <本轮子进程PID> /T /F`，也经过同一 `run`，有独立超时，不使用进程名或通配符。清理无法确认时写入 `.state/cleanup-blocked.json`，只允许补送已有通知，阻止新任务；核验进程树已退出后才能人工移除标记。
- 仅使用已确认仓库的 origin，并核对 fetch/push 目标、既有 worktree 的 Git common-dir、分支和仓库根。创建 worktree 不使用会重置已有分支的 `-B`；已有脏改动或领先提交均保留并报告失败。
- 推送被拒时只尝试一次普通合并和重推，冲突执行 `merge --abort`；永不 force。Codex 非零退出或缺少最后消息不推送；成功轮次的工作区改动由 watcher 提交，暂存或提交失败不推送。
- 接单先保存 `in_progress`。崩溃或通知失败都不重跑同一评论；执行结果先持久化，失败的回帖/反应在下次轮询补送，不把通知故障当作执行失败。网络中断时已发出的评论可能重复投递，执行仍不会重复。
- `.state/` 已被忽略；配置、原始 JSONL、最后消息、stderr 和结果详情只留本机。公开回帖先对完整内容脱敏，再限制摘要长度和诊断行数，避免截断私钥后漏扫。请勿提交本机日志。
- 活锁直接退出；旧锁恢复由单独保护文件串行处理。如果恢复时崩溃遗留 `lock.recover`，脚本明确报错；先核验没有 watcher/Codex 在工作，再移除残留恢复文件。不要直接删存活进程的锁。

### Windows 计划任务脚本

`install_relay_task.ps1` 默认注册当前用户的 Interactive/Limited 任务，每 3 分钟 `--once`，登录后执行，重叠触发忽略；无需保存密码或管理员运行级别。Action 为 `%SystemRoot%\System32\conhost.exe --headless <powershell.exe> -NoProfile -NonInteractive -EncodedCommand ...`，缺少 conhost 时直接报错。可用 `-NodePath`、`-GhPath` 指定可执行文件；node、gh、git 的目录加入任务 PATH，继承 PATH 中含 `codex.exe` 的目录会被剔除。注册时不要求 Codex 存在；`-CodexPath` 已移除，传入会提示使用配置里的 `codexPath`/`codexSearch`。

`-ShowAction` 仅打印 Execute 和解码后的命令，不注册、不创建配置或日志，也不访问现役任务；尚未创建配置时同样可预览。已有同名任务仍拒绝覆盖，须先 `-Remove`；`-WhatIf` 保留注册/删除预览。脚本保存为带 BOM 的 UTF-8，以便 Windows PowerShell 5.1 正确读取中文。任务日志固定 UTF-8 解码，注册默认 LastTaskResult 不作为运行证据。

```powershell
powershell -NoProfile -File tools/agent_relay/install_relay_task.ps1 -ShowAction
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent_relay/install_relay_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent_relay/install_relay_task.ps1 -Remove
```

### 更新与旧 VBS 方式迁移（合并后，经用户授权执行）

1. 主仓库拉到最新 `v3-lab`；更新运行目录才会使用新的 watcher。
2. 在现有 `.state/config.json` 填写实际 `codexSearch`，保留原 state、回执和日志。候选按 exe 修改时间选取，支持散列目录名；时间相同时按目录名字典序取最大的。用 dry-run 核对选中结果。
3. 用 `-ShowAction` 核对 headless 命令。用 `-Remove` 删除旧任务，再用新脚本注册，直接由 conhost 包装 PowerShell，无需 VBS。
4. 手动触发一次，确认 `task-last.log` 为“无待处理”，且这次运行的 `LastTaskResult` 为 0。
5. 确认后删除旧 VBS 启动器。以上是迁移步骤，源码测试或 ShowAction 通过不代表现役任务已迁移。

后续 Codex 更新由每轮解析处理；只要搜索目录布局仍符合配置，就无需重新注册任务。

### 新提交职责（2026-10-07，8877a50 规格）

Codex 只实现和验证，不提交；最后消息增加 `COMMIT: 一行中文提交信息`。watcher 在确认原分支与起始历史、且 Codex 成功并给出最后消息后，执行 `git add -A`，然后用 COMMIT 内容及 `relay: PR #<n> 第 N 轮` 两段信息提交，设置 `SKIP_PROJECT_STATE=1`。COMMIT 缺失、空白或为“无”时默认 `relay: 第 N 轮`。提交失败返回 failed、附工作区状态且不推送；移除 dirty 结果状态。Codex 已自行提交的兼容路径仍保留。原本就存在的脏工作区继续拒绝执行，避免提交其他人的改动。

离线测试覆盖提交信息与默认值、blocked 的部分改动、暂存/提交 hook 失败、无改动、Codex 自行提交、既有恢复保护及 Codex 路径解析。`--once` 的 failed / cleanup-blocked / codex-not-found 返回非零，计划任务 action 对程序启动错误也返回非零，输出保存在忽略目录 `.state/logs/task-last.log`，不以注册时的默认 LastTaskResult 当作执行证据。
