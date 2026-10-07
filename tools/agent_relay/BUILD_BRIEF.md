# Agent Relay watcher 实现规格（交给 Codex）

在用户 Windows 电脑上常驻的小脚本：每隔几分钟查一次 GitHub，发现 Claude 在 PR 上发的 `relay:to-codex` 指令，就在该 PR 的专用 worktree 里调用 `codex exec` 执行，推送后把结果回帖。协议见 [PROTOCOL.md](PROTOCOL.md)，每轮提示词见 [CODEX_ROUND_PROMPT.md](CODEX_ROUND_PROMPT.md)。

## 约束

- Node 22，`.mjs`，**零 npm 依赖**；与 `tools/i_remote_mcp/` 等同风格，用 `node --test` 测试。
- 只通过子进程调用 `gh`、`git`、`codex`；所有子进程调用经一个可注入的 `run(cmd, args, opts)` 函数，测试用假实现替换。
- 不引入 Flutter / Dart 改动，不改 `lib/`、`test/`、其他 `tools/`。
- `codex exec` 的参数名以本机 `codex exec --help` 为准（下文按常见写法：`--cd`、`--sandbox`、`--json`、`--output-last-message`，提示词经 stdin 传入 `-`）；与本机不符时按本机改，并在 README 记录实际版本。

## 文件

```
tools/agent_relay/
├─ relay_watcher.mjs          入口：--once（默认）| --loop | --dry-run | --config <path>
├─ relay_core.mjs             纯函数：解析、资格判定、提示词渲染、回帖拼装、脱敏
├─ relay_core.test.mjs
├─ relay_watcher.test.mjs     用假 run() 跑完整一轮
├─ relay.config.example.json
├─ install_relay_task.ps1     注册 / 移除 Windows 计划任务（每 3 分钟 --once）
└─ .state/                    已加入 .gitignore：config.json、state.json、lock、logs/
```

## 配置（`.state/config.json`，从 example 复制）

```json
{
  "repo": "Ritou-Lynx/here-i-am",
  "baseBranch": "v3-lab",
  "headPrefixes": ["claude/", "codex/"],
  "allowedAuthors": ["Ritou-Lynx"],
  "repoPath": "<本机主 clone 路径，只用来 fetch 和建 worktree>",
  "worktreeRoot": "<仓库外目录，如 %USERPROFILE%\\relay-worktrees>",
  "maxRounds": 4,
  "codexTimeoutMinutes": 60,
  "codexArgs": ["--sandbox", "workspace-write"],
  "summaryMaxChars": 6000,
  "mention": "@Ritou-Lynx"
}
```

`allowedAuthors` 首次冒烟时核对：Claude 经 GitHub 发的评论显示为哪个账号，就加哪个（可能就是用户本人账号）。

## 一次 `--once` 的流程

1. **加锁**：`.state/lock` 存在且对应进程仍在运行则直接退出；否则写入当前 PID。退出时删除。
2. **列 PR**：`gh pr list --repo <repo> --state open --label agent-relay --json number,headRefName,baseRefName,headRefOid,isCrossRepository,labels`。
3. **资格**（`isEligiblePr`）：按 PROTOCOL“PR 条件”逐条检查，不满足记日志跳过。
4. **找指令**：`gh api repos/<repo>/issues/<n>/comments --paginate`。取第一行匹配 `^<!-- relay:to-codex round=(\d+) -->\s*$` 的评论；作者在 `allowedAuthors`；评论 ID 不在 `state.json` 已处理集合。同一 PR 只取最早一条未处理的，每次 `--once` 全局最多执行一轮（串行，避免抢占电脑）。
5. **轮数**：`round > maxRounds` → 给 PR 加 `relay-needs-human`，发 `to-human`（说明超轮数），标记该评论已处理，结束。
6. **接单**：给指令评论加 `eyes` 反应（`gh api -X POST repos/<repo>/issues/comments/<id>/reactions -f content=eyes`），并把评论 ID 记为 `in_progress` 写入 state（崩溃后不会重复执行；`in_progress` 超过 `codexTimeoutMinutes`×2 的条目在下次运行时报 `failed`）。
7. **worktree**：路径 `<worktreeRoot>/pr-<n>`。
   - 不存在：在 `repoPath` 里 `git fetch origin <branch>`，`git worktree add <path> -B <branch> origin/<branch>`。
   - 已存在：`git fetch origin <branch>`；工作区不干净或本地领先远端 → 不动它，本轮 `failed` 并说明；否则 `git merge --ff-only origin/<branch>`。
   - 记录开始前 SHA。
8. **执行**：用模板渲染提示词（contract = PR 描述，instruction = 评论正文，去掉第一行标记），`codex exec --cd <worktree> <codexArgs...> --json --output-last-message <logs/pr-n-round-N.last.txt> -`，stdin 传提示词，环境变量加 `SKIP_PROJECT_STATE=1`。stdout 全量写 `logs/pr-n-round-N.jsonl`。超时则终止进程树，`failed`。
9. **判定状态**：
   - Codex 退出码非 0 或无最后消息 → `failed`。
   - `git status --porcelain` 非空 → `dirty`（不替 Codex 提交，回帖列出 `git status --short`）。
   - 最后消息首行 `STATUS: blocked` → `blocked`。
   - 否则 `done`。
10. **推送**：只要有新提交（且不是 `dirty`），`git push origin HEAD:refs/heads/<branch>`。被拒（Claude 期间推过）→ `git fetch` 后 `git merge --no-edit origin/<branch>`；无冲突再推一次，有冲突则 `git merge --abort`，状态改 `failed` 并说明。**永不 force。**
11. **回帖**：`gh pr comment <n> --repo <repo> --body-file <tmp>`，格式：

    ```markdown
    <!-- relay:to-claude round=N status=done sha=abc1234 -->
    **[to-claude] 第 N 轮 · done**

    提交：abc1234（start…end，共 K 个）
    改动文件：
    - path/a
    - path/b

    <Codex 最后消息，经脱敏与截断>
    ```

    `failed` / `dirty` 时附原因和最多 30 行相关输出（同样脱敏）。
12. **收尾**：指令评论加 `rocket`（done/blocked）或 `confused`（failed/dirty）；state 记为已处理（含状态、SHA、时间）；释放锁。

`--loop` 只是每 `pollSeconds`（默认 180）调用一次上述流程。`--dry-run` 只打印将要处理的 PR、评论、渲染后的提示词和将要执行的命令，不加反应、不跑 Codex、不推送、不回帖、不写 state。

## 脱敏（`redact`）

回帖前对正文做替换，命中任一模式的片段换成 `[已隐藏]`，并在回帖末尾注明“部分内容已隐藏，全文见本机日志”：

- `gh[pousr]_[A-Za-z0-9]{20,}`、`github_pat_[A-Za-z0-9_]{20,}`
- `sk-[A-Za-z0-9_-]{20,}`、`Bearer\s+[A-Za-z0-9._~+/-]{16,}`
- `-----BEGIN [A-Z ]*PRIVATE KEY-----` 到对应 END
- Windows 用户目录绝对路径 `[A-Za-z]:\\Users\\[^\\\s]+` → `%USERPROFILE%`
- 然后截断到 `summaryMaxChars`。

## 测试（`node --test tools/agent_relay/`，全部用假 `run()`，不联网）

1. 标记解析：合法 `to-codex`；第二行才出现的标记、round 非数字、多余空格变体、`to-claude` 都不当指令。
2. 资格：缺 `agent-relay`、有 `relay-paused`、有 `relay-needs-human`、fork、base 非 `v3-lab`、head 前缀不符 → 全部跳过。
3. 作者不在白名单 → 跳过且不加反应。
4. 已处理评论不重复执行；`in_progress` 超时条目报 `failed`。
5. `round=5`（maxRounds=4）→ 加 `relay-needs-human` + 发 `to-human`，不跑 Codex。
6. 完整一轮 done：命令顺序为 反应 eyes → fetch/worktree → codex（stdin 是渲染后的提示词、带 `SKIP_PROJECT_STATE=1`）→ push（无 `--force` 字样）→ 回帖首行格式正确 → 反应 rocket。
7. Codex 退出码 1 → `failed`，不推送。
8. 工作区留有未提交改动 → `dirty`，不推送、不提交。
9. 推送被拒 → fetch + merge 成功后重推；merge 冲突 → `merge --abort`、`failed`。
10. 脱敏：上面每个模式各一例被替换；超长截断。
11. 锁：已有存活锁时立即退出、不调用 `gh`。
12. `--dry-run` 不产生任何写操作（假 `run()` 断言未收到 POST、push、comment）。

## 验收

- `node --test tools/agent_relay/` 全部通过。
- `node tools/agent_relay/relay_watcher.mjs --dry-run` 在本机能列出当前带 `agent-relay` 的 PR（没有就输出“无待处理”）。
- `install_relay_task.ps1` 注册的计划任务以当前普通用户身份运行（与 `codex login status`、`gh auth status` 同一用户），间隔 3 分钟，可用 `-Remove` 删除。
- README 补上“本机实际版本”一节：`node`、`gh`、`codex` 版本和实际使用的 `codex exec` 参数。
- 真实冒烟由用户通知 Claude 开一个测试 PR 完成（见 README）。
