# 安全切换与前端身份：接力合同（2026-10-11）

背景见 [阶段 A 合同](RELAY_20261011_icore-stage-a.md) 末尾的 S1 记录。现状是 ChatGPT 任务在跑，Claude、ChatGPT 和 App 三端互通。遗留两个问题：

- 没有安全的停服和切换方法。注销会强杀会话，下次登录要做崩溃恢复，今天就因此卡在恢复锁上。
- ChatGPT 写回的消息被标成 `claude_web`。

分工照旧：Codex 在本机写代码，云端审查，用户只处理部署和真实数据。止损规则沿用阶段 A 合同第 0 节，另加两条：

- 只用合成数据，不碰生产任务。
- A 和 B 的改动路径互不重叠，可以分两个窗口并行。

**前置条件：** 先在 v3-lab 依次合并 #24 和 #21，A、B 都从合并后的 v3-lab 开分支。#21 的 MCP 代码是 B 的基础。

## 合同 A：普通用户正常关闭与带回滚的切换

```markdown
<!-- relay:contract v1 -->
## 目标
普通用户不需要审批材料就能正常关闭当前 Schema6 会话，并能把登录任务从旧任务切到新任务；任何一步失败都自动切回旧任务，且全程不触发崩溃恢复。
## 完成标准
- [ ] 新增 `tools/i_core/maintenance/stop-schema6-session.ps1`。参数为 `-TaskName`，从任务参数里读取 login 配置路径，并核对该配置的 sha256。在配置的 control root 下找到仍在运行的最新会话（`session-window.json` 记录的进程存活，是 powershell.exe，属于当前用户，hwnd 与记录一致）。复用 `close-schema6-session.ps1` 的 WM_CLOSE 发送和回执核对逻辑，但不读审批配置，也不核 pin。等待最多 35 秒，核对以下各项：
  - 宿主退出码为 0；
  - session-exit 和 lifecycle 回执为 clean_closed；
  - mcp-start/mcp-stop 成对出现；
  - 数据库目录没有 `-wal`/`-shm`/`-journal`；
  - 状态目录没有 `s6-recovery-pending.json`。
- [ ] 找不到运行中的会话时，不报错，输出 `already_stopped`，并照样检查数据库目录没有 `-wal`/`-shm`/`-journal`、状态目录没有恢复锁。
- [ ] 新增 `tools/i_core/maintenance/switch-login-task.ps1`。参数为 `-FromTask`、`-ToTask`、`-ReadyTimeoutSeconds`（默认 180）、可选的 `-PublicHealthUrl`，以及 `-DryRun`。按以下顺序执行：
  1. 只读检查：两个任务都存在；两份 login 配置的哈希都对得上，且指向同一个数据根；没有恢复锁。
  2. 调用 stop 脚本关闭当前会话。
  3. 停用旧任务，启用新任务。
  4. 启动新任务。
  5. 在超时内等新会话就绪：Core 和 MCP 端口都在监听，传了 URL 时公网检查返回 200。
  6. 第 3 到第 5 步失败时，先用 stop 脚本正常关闭新会话。关闭不干净或出现恢复锁时，立即停下并报告，**不启动旧任务**，避免叠加恢复。关闭干净时，停用新任务、启用旧任务、启动旧任务，再核对端口。
  `-DryRun` 只执行第 1 步。
- [ ] 错误可见：两个脚本的每一步都输出一行 JSON（`step`、`ok`、`detail`）。失败时 `detail` 原样带上异常文本，不用统一错误码替换，也没有吞掉异常的 catch。退出码约定：0 成功，1 已回滚，2 回滚失败或已停下等人工。
- [ ] 任务操作（读取、启用、停用、启动、读状态）集中在一个可替换的适配层。Windows CI 用合成数据跑三个场景：
  - 场景 1：用测试夹具启动真实合成会话，stop 脚本正常关闭，断言数据库目录没有 sidecar、状态目录没有恢复锁。
  - 场景 2：从会话 A 切到会话 B，断言 B 就绪，且 B 启动时没有进入恢复流程（具体判断字段由 Codex 在代码里找出并注明出处）。
  - 场景 3：B 的配置哈希故意写错，脚本自动回滚到 A，A 就绪，同样没有进入恢复流程。
  另加一条只在 CI 上跑的真实计划任务测试：注册一个只执行无害命令的任务，验证适配层的读取、启用、停用和启动后删除任务。
- [ ] 加进 `run_windows_tests.ps1` 现有的 maintenance 套件；README 补充两个脚本的用法（只写相对路径）。
## 允许修改的路径
- tools/i_core/maintenance/stop-schema6-session.ps1（新）
- tools/i_core/maintenance/switch-login-task.ps1（新）
- tools/i_core/maintenance/README.md
- tools/i_core/test_fixtures/release_schema6/（新增测试文件，以及 run_windows_tests.ps1 的套件列表）
## 禁止
- 改动 `tools/i_core/release_schema6/` 运行时包（48 项发布清单）、`close-schema6-session.ps1` 和审批类脚本
- 本机运行真实任务或接触生产数据；本机设置 `SCHEMA6_SYNTHETIC_TASK_TEST`
## 验证
- Windows CI 的 `Schema6 Windows maintenance acceptance` 和 `Schema6 Windows lifecycle and backup` 两项变绿
- 本机：`git diff --name-only origin/v3-lab...HEAD` 只包含允许的路径
```

**A0（只读，先于编码，Codex 在本机做一次）：** 读 10-11 被注销强杀的那次 cleanclose 会话的回执，包括 `session-message-*`、`session-phase-*` 和 `session-exit*`。查清楚注销时为什么没能正常关闭；系统设计上会处理 WM_QUERYENDSESSION/WM_ENDSESSION。只汇报现象和推断，不改代码。这关系到以后**每次重启或注销**是否都要走一次恢复。

## 合同 B：按调用方区分写回身份

```markdown
<!-- relay:contract v1 -->
## 目标
ChatGPT 写回的聊天带 `chatgpt_web` 来源，Claude 保持 `claude_web`。身份在授权时绑定到令牌上，客户端无法自报。
## 完成标准
- [ ] `oauth.mjs`：根据授权码记录里的 `redirect_uri` 推导前端：等于 `CHATGPT_CALLBACK_URI` 时为 `chatgpt_web`，其他情况为 `claude_web`。推导结果写进 access token 和 refresh 族，刷新时继承，`verifyAccessToken` 返回这个字段。旧令牌没有该字段时按 `claude_web` 处理，保证兼容。
- [ ] `writeback.mjs`：前端定义改成表：
  - `claude_web`：设备 `frontend:claude_web`，显示名“claude.ai 网页端”，凭据文件 `core-frontend.json`（不变）；
  - `chatgpt_web`：设备 `frontend:chatgpt_web`，显示名“ChatGPT 网页端”，凭据文件 `core-frontend-chatgpt_web.json`。
  写回时的 device_id、origin_device_id、幂等键前缀和 source 都取自调用方前端。线程按前端隔离：拿 ChatGPT 令牌续写 claude_web 线程会被拒绝，反过来也一样。
- [ ] `chatgpt_web` 没有配对凭据时，`i_chat_turn` 返回明确的错误 `frontend_not_paired:chatgpt_web`，**不回退成 claude_web**。
- [ ] `server.mjs pair-core` 增加 `--frontend chatgpt_web`（默认 claude_web），写入对应的凭据文件。
- [ ] `mcp.mjs`：`i_chat_turn` 的描述按调用方生成，不再写死 claude_web。
- [ ] 不改的部分：`domain_tools` 的随手记和笔记仍只接受 claude_web，App 不改，历史消息不改。
- [ ] 新增测试，覆盖以下各项：
  - 两个客户端各写一轮，来源分别正确；
  - 用 ChatGPT 令牌伪造 claude_web（包括请求参数、线程 id 和刷新令牌三种方式）都会被拒绝；
  - chatgpt_web 未配对时得到明确错误；
  - Claude 原有流程的现有测试全部不改且通过。
- [ ] README 和 `CLAUDE_PROJECT_INSTRUCTIONS.md` 补充：读取策略的 `messages.auto_share_origins` 需要加入 `chatgpt_web`。
## 允许修改的路径
- tools/i_remote_mcp/（含新增测试）
- tools/i_memory/README.md、tools/i_memory/policy.example.json（只改示例和说明）
## 禁止
- 改动 Core（`tools/i_core/`）、App（`lib/`）和真实配置
## 验证
- Linux：`node --test tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs` 全部通过
- Windows CI 的 `MCP ChatGPT compatibility (Windows)` 变绿，六文件候选能正常生成
```

## C：部署（A、B 都完成后进行，用户在场）

1. 用 #21 的工具生成包含 B 的六文件候选。用 #24 的工具生成新配置，并注册新任务（先不启用）。
2. 在真实读取策略的 `auto_share_origins` 里加入 `chatgpt_web`。**这一步改动真实配置，届时单独征得同意。**
3. 用 A 的 `switch-login-task.ps1` 先执行 `-DryRun`，再正式切换。
4. 在 App 里生成配对码，执行 `pair-core --frontend chatgpt_web`。**这一步写入真实数据，届时单独征得同意。**
5. 验收：ChatGPT 和 Claude 各发一轮，确认 App 里来源分开显示，Claude 也能读到 chatgpt_web 的消息。

## D：收尾的决定

- **AgentRelay：** 保持停用，闪窗已确认来自它。以后要恢复接力时，改用不弹窗的启动方式，作为单独小任务。
- **恢复中断的详细记录：** 涉及 Core 运行时包（`runtime_child`/`recovery_adapter` 在 48 项发布清单里），改了就必须换包。现在不单独做，记为下一次 Core 发版的必带项。失败记录要直接写明 `commitStarted`、是否存在 `s6-copy-*`、原数据库和 sidecar 是否被动过。

## 第 1 轮审核（2026-10-12）

**A（PR #26）**
- A0 的现象：窗口钩子已就绪，但会话消息、阶段和退出回执都没有写出来；MCP 有启动回执，没有停止回执；宿主以 0xC000013A 退出。
  - 现有 CI 只用 `send_session_message` 直接发送 WM_QUERYENDSESSION/WM_ENDSESSION，从来没在真实注销下验证过。
  - 推断：真实注销时，会话宿主（带控制台的 powershell.exe）在窗口消息处理之前就被终止了。
  - 修复要改 `session_window.ps1`，它属于运行时包，所以记为下一次 Core 发版的必带项，附带一项 L3 验收：在专用测试机上用合成数据根做真实注销和重启。
  - 在那之前，注销和重启都按"会触发崩溃恢复"对待，停服只用 A 的脚本。
- CI 维护套件唯一的失败是 `synthetic_com_run_not_observed`。原因：测试任务用的登录类型是 3（交互令牌），而 hosted runner 以服务身份运行，没有交互会话，任务启动不起来。这是测试夹具的问题，不是生产脚本的问题。
- 脚本逻辑核对通过：
  - 只读预检同时检查两份配置；
  - 停旧失败时返回 2，不再往下执行；
  - 回滚前要求新会话正常关闭、没有 sidecar；
  - 每一步错误原样输出。

**B（PR #25）**：本地复跑 193/193 通过。需要返修三点：
1. 老令牌：现有 ChatGPT 连接是在 B 之前授权的，refresh 记录里没有 `frontend` 字段，刷新时会一直按 `claude_web` 处理，部署后标注仍然错误。
2. `i_chat_turn` 现在会拒绝任何未知参数。这比合同要求更严，可能让 Claude 现有的调用失败；只需拒绝与身份相关的字段。
3. ChatGPT 的工具列表丢了只读的领域工具 `week_get`/`day_get`；只应隐藏 `capture_add` 和 `i_remember`。
