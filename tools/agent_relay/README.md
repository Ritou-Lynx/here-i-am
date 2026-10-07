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

**你做的事只剩三件**：在 claude.ai/code 开会话说目标；手机上收到 GitHub 通知时看一眼；最后自己验收并点合并。

一次典型接力：

| 时间 | 发生什么 | 你看到什么 |
|---|---|---|
| 0 分 | 你在 claude.ai/code 说“用接力做：给 X 加 Y” | — |
| ~10 分 | Claude 读代码、写合同、开 draft PR、发第 1 轮指令 | PR 出现，带 `agent-relay` 标签 |
| ≤3 分后 | watcher 接单，指令评论出现 👀 | — |
| +10~40 分 | Codex 实现、跑测试；watcher 提交、推送并回帖，评论变 🚀 | PR 里多了提交和一条 [to-claude] |
| +几分钟 | Claude 被唤醒，读 diff 审阅；不过关就发第 2 轮返修，循环 | PR 里一来一回的指令和结果 |
| 结束 | Claude 发 [done] 并 @你，列出需要你亲自做的事（构建、装机、真人体验） | **手机收到 GitHub 通知** |

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

### 第一步：实现 watcher

```text
拉取分支 claude/wonderful-carson-a26i9d，读 tools/agent_relay/BUILD_BRIEF.md、PROTOCOL.md、CODEX_ROUND_PROMPT.md 和根目录 AGENTS.md。
按 BUILD_BRIEF 在 tools/agent_relay/ 实现 watcher，零 npm 依赖，测试清单 12 项全部写成 node --test 用例。
先运行 codex exec --help、gh --version，把 codex exec 的实际参数对齐到本机版本。
完成后：node --test tools/agent_relay/ 全部通过；更新 docs/development/I_PROJECT_STATE.md 和 DEVLOG.md 顶部各一小段；提交并推送到同一分支（不 force）。
把测试结果和本机 codex / gh / node 版本告诉我。
```

### 第二步：本机配置和计划任务

```text
帮我把 Agent Relay watcher 在本机装好，不改仓库源码。

1. 确认 gh auth status 和 codex login status 都是当前用户已登录；没登录就停下告诉我怎么登。
2. 用 gh 在 Ritou-Lynx/here-i-am 建三个标签（已存在就跳过）：agent-relay、relay-paused、relay-needs-human。
3. 复制 tools/agent_relay/relay.config.example.json 为 tools/agent_relay/.state/config.json，填本机 repoPath 和仓库外的 worktreeRoot。
4. 运行 node tools/agent_relay/relay_watcher.mjs --dry-run，贴输出。
5. 用 install_relay_task.ps1 注册计划任务（当前用户、每 3 分钟），确认任务存在且上次运行结果为 0。
6. 告诉我已经可以冒烟了。
```

### 第三步：冒烟（找 Claude）

在 claude.ai/code 对本仓库开会话，说“接力冒烟”。Claude 会开一个只改 `tools/agent_relay/SMOKE.md` 的小 PR。看到 👀 → 🚀 → [to-claude] → Claude 审阅 → [done] 走通即完成。首次冒烟同时核对 Claude 评论显示的作者账号，必要时加进 `allowedAuthors`。

## 日常用法

在 claude.ai/code 对本仓库开会话：

> 用接力做：<目标>。

Claude 会按 SKILL 手册开 PR、发指令、订阅 PR。之后你可以关掉网页，等 GitHub 通知。想插话就在 PR 里直接评论，或回到那个会话说。
## watcher 已实现（2026-10-07）

零 npm 依赖，源码使用 Node 22 支持的 `.mjs` 与内置模块。`package.json` 只有目录测试入口及运行版本声明，没有 dependencies；无需 `npm install`。清单 12 项均已写成离线测试，额外覆盖仓库归属、并发锁回收、通知恢复、分支历史保护和超时清理阻断。

```powershell
node --test tools/agent_relay/
node tools/agent_relay/relay_watcher.mjs --dry-run
node tools/agent_relay/relay_watcher.mjs --once --config tools/agent_relay/.state/config.json
node tools/agent_relay/relay_watcher.mjs --loop --config tools/agent_relay/.state/config.json
```

`--once` 是默认模式。`--loop` 使用 `pollSeconds`（默认 180）。`--dry-run` 只做读取和打印：没有本机配置时用当前仓库及默认白名单查询 PR，不创建配置、锁、日志或 state，不加反应、不运行 Codex、不推送和回帖。安装前应核对 `allowedAuthors`。

### 本机实际版本

2026-10-07 核对：

| 工具 | 实际版本与验证 |
|---|---|
| Node（原终端 PATH） | `v24.14.1`，全部 39 项通过 |
| Node 22（临时官方便携版） | `v22.23.3`，全部 39 项通过；未替换本机 Node |
| Codex | `codex-cli 0.160.0`，已先运行 `codex exec --help` 对齐参数 |
| GitHub CLI | `gh 2.102.0 (2026-09-30)`，官方便携包经 SHA-256 校验；原终端 PATH 找不到 gh，本轮仅临时加入进程 PATH 验证，未全局安装 |

实际启动参数如下。提示词通过 stdin 传入，最后的 `-` 不省略；子进程环境加入 `SKIP_PROJECT_STATE=1`，不改全局配置。

```text
codex exec --cd <PR-worktree> --sandbox workspace-write --json --output-last-message <local-log.last.txt> -
```

本机只读 dry-run 已返回“无待处理”，未调用真实 Codex 执行任务。真实 PR 接力冒烟、本机持久配置与计划任务仍按上文第二、三步进行。

### 执行与恢复边界

- 所有进程调用经可注入 `run(cmd, args, opts)`；业务操作只调用 `gh`、`git`、`codex`。为满足 Windows 超时终止整棵进程树，另使用系统清理辅助 `taskkill.exe /PID <本轮子进程PID> /T /F`，也经过同一 `run`，有独立超时，不使用进程名或通配符。清理无法确认时写入 `.state/cleanup-blocked.json`，只允许补送已有通知，阻止新任务；核验进程树已退出后才能人工移除标记。
- 仅使用已确认仓库的 origin，并核对 fetch/push 目标、既有 worktree 的 Git common-dir、分支和仓库根。创建 worktree 不使用会重置已有分支的 `-B`；已有脏改动或领先提交均保留并报告失败。
- 推送被拒时只尝试一次普通合并和重推，冲突执行 `merge --abort`；永不 force。Codex 非零退出、缺少最后消息、未提交改动均不推送。
- 接单先保存 `in_progress`。崩溃或通知失败都不重跑同一评论；执行结果先持久化，失败的回帖/反应在下次轮询补送，不把通知故障当作执行失败。网络中断时已发出的评论可能重复投递，执行仍不会重复。
- `.state/` 已被忽略；配置、原始 JSONL、最后消息、stderr 和结果详情只留本机。公开回帖先对完整内容脱敏，再限制摘要长度和诊断行数，避免截断私钥后漏扫。请勿提交本机日志。
- 活锁直接退出；旧锁恢复由单独保护文件串行处理。如果恢复时崩溃遗留 `lock.recover`，脚本明确报错；先核验没有 watcher/Codex 在工作，再移除残留恢复文件。不要直接删存活进程的锁。

### Windows 计划任务脚本

`install_relay_task.ps1` 默认注册当前用户的 Interactive/Limited 任务，每 3 分钟 `--once`，登录后执行，重叠触发忽略；无需保存密码或管理员运行级别。可用 `-NodePath`、`-GhPath`、`-CodexPath` 指定稳定的可执行文件；脚本把这些工具目录加入任务自身的 PATH，避免计划任务缺少终端 PATH。已有同名任务不会被覆盖；`-Remove` 只移除该任务，`-WhatIf` 可预览注册动作。Codex 程序路径随桌面应用更新变化时，应移除并重新注册以刷新路径。本次仅交付脚本并检查 PowerShell 语法，没有注册任务。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent_relay/install_relay_task.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/agent_relay/install_relay_task.ps1 -Remove
```
