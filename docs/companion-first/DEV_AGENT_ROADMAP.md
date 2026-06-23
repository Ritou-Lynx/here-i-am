# Dev Agent Room — 路线图

把 Claude Code 和 Codex 接进 Here I am，作为角色可以召唤的 coding 工具与可多轮 Dev Session，而不是把它们直接做成普通陪伴角色。
本文是可随时拾起的执行手册，不是产品讨论。

## 核心原则（决策已锁，不再讨论）

1. **agency 留在角色身上**：真正想替用户做事的是陪伴角色；Claude Code / Codex 是角色可召唤的 coding 能力。Dev Room 承载执行过程、diff、审批和审计，不把工具本身伪装成关系主体。
2. **手机不执行代理**：手机端只是控制台。真正的 CC / Codex 进程跑在常驻开发机上的 Bridge 里。
3. **桥接复用现成方案**：Bridge 第一版基于 MyPilot fork,不从零写 hooks/加密/重连。
4. **数据分层**：
   - **工程过程数据**（run/diff/审批/事件流）→ 专属表 `DevProjects` / `DevAgentRuns` / `DevAgentEvents` / `DevAgentApprovals`,不进 User-truth(它们不是"事实",是过程)
   - **每日工作产出**（coding_log)→ 进 `SharedLifeEntities`,所有角色平等可见,带署名
5. **权限默认最紧**：新建项目默认 `read_only`。`workspace_write` 和 `release_ops` 必须用户对项目显式升级。
6. **双入口**：Dev Room 仍在 Settings / Personal 作为控制台；Phase 5 后，主聊天里的角色也能创建或继续 Dev Session。
7. **不做访问圈层**：所有角色平等读取 User-truth。私密性来自"用户不主动记录",不来自系统隔离。这与"多个伴侣角色相互知道彼此存在"的产品设定一致。

## 路线图总览（2026-06-22 修订）

| Phase | 范围 | 状态 |
|---|---|---|
| 0 | Bridge 选型与原型 | ✅ 完成 |
| 1 | 只读远程台 | ✅ 完成 |
| 2 | 写权限 + worktree + apply/discard 真做 | ✅ 完成 |
| 4a | 多项目体验打磨（chip / 摘要 / cleanup / 删除） | ✅ 完成，dogfood 中 |
| 4a+ | 项目级 Git 操作（Pull / Push） | 📋 设计已确认，待实现 |
| **5** | **角色可召唤的多轮 Dev Session** | **🚧 已开始：Dev Room 多轮骨架已落地** |
| 3 | Daily Coding Log + 署名记忆卡片 | 接在 5 后面 |
| 4b | PR 自动开（release_ops 真启用） | 依赖 4a+ Push |
| 6 | 语音陪伴（通勤路上 Codex 读文章 + TTS） | 后续 |

**砍掉的**：原 Phase 5 "双代理协作（CC 写 + Codex review）" —— 太 niche，长期都不做。

### 几次重要的方向校正（防止以后忘）

1. **Phase 5 的主体不是 CC/Codex 人格化，而是角色召唤工具**：用户最终想要的是"某个角色替我叫 Codex/Claude Code 做事"，而不是把 Codex 本身变成伴侣角色。agency 留在角色，工具放大角色能力。
2. **必须引入 Dev Session**：一次性 run 无法支撑"读第一篇 → 讨论 → 再读第二篇 → 追问 → 改方案"这种场景。Phase 5 的核心数据结构是可多轮 `DevAgentSessions`，run 只是 session 里的执行回合。
3. **Dev Room 保留为多轮控制台**：用户可以在主聊天里让角色继续一个 Dev Session，也可以自己打开 Dev Room 直接追问、查看 diff、apply/discard。Dev Room 不是主关系入口，但必须是可靠的过程空间。
4. **绑定仍用独立表，不污染 CharacterModel**：新增 `DevAgentToolBindings` 或 `DevAgentSessionOwners` 这类独立表，记录哪个角色可召唤哪个项目/agent/权限档。普通角色模型不新增 Memex 特有耦合字段。
5. **Phase 3 不能太靠后**：coding_log + 署名是其他伴侣角色"听说过"这些工程产出的社会基础，必须在 Phase 5 后紧接着做，不能拖到末尾。

---

## Phase 0 — Bridge 选型与原型（2 天）

### 目标
确认 Bridge 协议，跑通 "手机发字符串 → CC 在电脑上执行 → 手机收到流式输出"。

### 做什么
- 装 MyPilot：`npm install -g mypilot`，`mypilot init-hooks`，`mypilot start`
- 用 curl / Postman 摸清它的 HTTP/WS 协议（发任务、查状态、收事件、审批）
- 同时跑 `codex exec --json "hello"` 看 stream 格式
- 写一份 `docs/companion-first/DEV_AGENT_BRIDGE_PROTOCOL.md`，对齐两边事件 schema

### 完成判定
- 能列出 MyPilot 提供的全部 endpoint 和事件类型
- 能列出 Codex `--json` 的全部事件类型
- 决定：**fork MyPilot 加 Codex 适配**，还是**用 MyPilot 原样跑 CC + 自己另起一个 Codex bridge**

### 当前备注（2026-06-21）

见 `docs/companion-first/DEV_AGENT_MYPILOT_PROBE.md`。当前 Windows 开发机上
`mypilot@0.5.0` 被 `node-pty` native build 阻塞，原因是 Visual Studio Build
Tools 缺 Spectre-mitigated C++ libraries。阶段推进先使用项目内 Bridge 原型，
MyPilot fork 路线保留为后续 hook / reconnect / remote-control 底座。

### 触发下一步
协议文档落地、技术路径选定。

---

## Phase 1 — 只读远程台（1 周）

### 目标
在 App 里发任务给 CC / Codex，看进度，看最终输出。不能改文件、不能 commit。

### 数据层（Drift schema）

新建 `lib/db/dev_agent_tables.dart`：

```dart
class DevProjects extends Table {
  TextColumn get id => text()();                 // uuid
  TextColumn get name => text()();
  TextColumn get rootPath => text()();           // 电脑上的绝对路径
  TextColumn get defaultBranch => text().withDefault(const Constant('main'))();
  TextColumn get bridgeUrl => text()();          // 哪个 Bridge 负责这个项目
  TextColumn get permissionTier => text().withDefault(const Constant('read_only'))();
  IntColumn get createdAt => integer()();
  @override Set<Column> get primaryKey => {id};
}

class DevAgentRuns extends Table {
  TextColumn get id => text()();                 // uuid
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();          // 'claude_code' | 'codex'
  TextColumn get sessionId => text().nullable()(); // Bridge 侧 session
  TextColumn get initialPrompt => text()();
  TextColumn get status => text()();             // pending|running|waiting_approval|done|failed|aborted
  TextColumn get branch => text().nullable()();
  TextColumn get worktreePath => text().nullable()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  TextColumn get summary => text().nullable()(); // 最终一句话总结
  @override Set<Column> get primaryKey => {id};
}

class DevAgentEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get runId => text().references(DevAgentRuns, #id)();
  IntColumn get ts => integer()();
  TextColumn get kind => text()();               // text|tool_call|tool_result|file_change|test|error|approval_request
  TextColumn get payloadJson => text()();
}

class DevAgentApprovals extends Table {
  TextColumn get id => text()();                 // uuid
  TextColumn get runId => text().references(DevAgentRuns, #id)();
  TextColumn get kind => text()();               // command|write|commit|push|network
  TextColumn get descriptionJson => text()();    // 命令、影响范围
  TextColumn get status => text()();             // pending|approved|denied|expired
  IntColumn get createdAt => integer()();
  IntColumn get respondedAt => integer().nullable()();
  @override Set<Column> get primaryKey => {id};
}
```

记得 `dart run build_runner build --delete-conflicting-outputs`。

### Service 层

`lib/data/services/dev_agent_bridge_service.dart`：
- 单例，持有当前活跃 Bridge 连接（一台机一个）
- `Future<String> startRun(projectId, prompt, agentType)` → 返回 runId
- `Stream<DevAgentEvent> eventsFor(runId)` → 转发 Bridge 事件流，同时写入 `DevAgentEvents` 表
- `Future<void> abort(runId)`
- 连接管理：心跳、断线重连、离线缓冲（让 Bridge 缓冲，App 重连后拉取）

### UI 层

`lib/ui/dev_agent/`：
- `dev_room_screen.dart`：项目列表 + 每个项目的活跃 runs
- `dev_run_screen.dart`：一条 run 的完整视图
  - 顶部：状态徽章、agent 名、branch
  - 中部：事件流（text 气泡、tool call 折叠卡、file change 列表）
  - 底部：输入框（追问） + 终止按钮
- `dev_project_settings_screen.dart`：新增/编辑项目，配 Bridge URL、根路径、权限档

入口：Settings → "Dev Room"。

### 完成判定
- 在手机上能新建项目（`read_only` 档）
- 发任务 → 看到 CC / Codex 在电脑上跑起来
- 流式输出在 App 实时显示
- 任务结束 → `DevAgentRuns.status = done`，能看完整历史
- 手机杀进程重开，能恢复正在跑的 run 状态

### 触发下一步
读功能稳定 1 周无 Bridge 崩溃 / 数据丢失。

---

## Phase 2 — 写权限 + 审批闭环（1 周）

### 目标
让 CC / Codex 真正改代码，但任何写操作都必须手机审批。

### Bridge 改造
- 拦截所有 write / bash / commit / push hooks
- 命中拦截 → 调用 App 注册的 webhook → 等待审批 → 放行或拒绝

### App 改造

**worktree 隔离**：
- 项目升 `workspace_write` 后，每个 run 自动在 `{rootPath}/.dev-agent/worktrees/{runId}/` 创建 git worktree
- branch 名：`dev-agent/{runId-short}`
- 写入 `DevAgentRuns.branch` 和 `worktreePath`

**审批通知**：
- 收到 `approval_request` 事件 → 创建 `DevAgentApprovals` 行 → 触发本地通知
- 通知点击 → 跳到 `dev_approval_sheet`，显示命令 + 影响范围 + Approve / Deny 按钮
- 5 分钟未响应 → `expired`，Bridge 收到拒绝

**diff 视图**：
- run 结束（或暂停时）自动 `git diff` worktree → 存到 `DevAgentArtifacts`（或先复用 `DevAgentEvents` 的 file_change）
- `dev_run_screen` 顶部加 "查看 diff" 按钮，跳 `dev_diff_screen`
- `dev_diff_screen` 底部：Apply（merge 到 default branch）/ Discard（删 worktree）/ 留着

### 权限档行为

| 档位 | 读 | 写 worktree | commit | push | 网络 |
|---|---|---|---|---|---|
| `read_only` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `workspace_write` | ✅ | ✅ 自动 | ⚠️ 审批 | ❌ | ⚠️ 审批 |
| `release_ops` | ✅ | ✅ 自动 | ⚠️ 审批 | ⚠️ 审批 | ⚠️ 审批 |

`danger-full-access` **不在 App 里提供**，需要的话用户去电脑直接跑。

### 完成判定
- 给 CC 一个真实任务（"在 worktree 里补 RecordOrganizerService 的单测"）
- 手机看到 5+ 次审批请求，全部正确响应
- 任务完成后看到 diff，Apply 后 merge 到 personal-lab，无冲突无残留

### 触发下一步
连续 10 次任务无错误 merge / 无意外文件改动。

---

## Phase 3 — Daily Coding Log + 署名事实卡片（3 天）

### 目标
每天自动生成一张 coding 事实卡片，沉淀产出。所有角色平等可见，带 CC/Codex 署名，伴侣角色由此自然知道"今天她和 CC 在忙什么"。

### 数据流

每天定时（21:00 或第一次打开 Dev Room）：

1. 扫今天的 `DevAgentRuns`（`startedAt` 在今天）
2. 拉所有 run 的 summary、参与的 agent、合并/丢弃状态
3. 喂给一个轻量 agent（复用 `Insights` agent 类别，新 prompt）生成**粗粒度功能描述**（不是技术细节堆砌）：
   ```json
   {
     "date": "2026-06-21",
     "summary": "完成了 Dev Room 的数据层和审批 UI，Phase 2 基本收尾",
     "highlights": ["接通了 CC Bridge", "审批闭环跑通"],
     "authors": ["claude_code", "codex"],
     "contributions": {
       "claude_code": "实现数据层、Bridge 适配",
       "codex": "review 了审批流程，提了 3 个改进建议"
     },
     "mood_hint": "顺利",
     "run_ids": ["...", "..."]
   }
   ```
4. 写入两处：
   - **`SharedLifeEntities`**（`entityType = 'coding_log'`,带 `authorCharacterIds`）→ 所有角色平等检索
   - **DEVLOG.md**：人类可读条目（沿用项目现有约定）

### Coding Log 的关键字段

```dart
// SharedLifeEntities 里 coding_log 类型的 stateJson 结构
{
  "summary": "...",                          // 一句话总结,角色检索主要看这个
  "highlights": ["...", "..."],              // 2-4 个亮点
  "authorCharacterIds": ["claude_code", "codex"],  // 署名,UI 显示头像
  "contributions": { ... },                  // 谁做了什么
  "intensity": "light|normal|heavy",         // 给角色判断"今天累不累"
  "run_ids": ["..."]                         // 关联回 DevAgentRuns
}
```

### 署名怎么用

- 卡片 UI 顶部显示 CC/Codex 头像 + "在 X 的帮助下完成"
- 其他角色检索到这条卡片时,prompt 里带署名信息,他们的回应会自然提到"听说你和 CC 今天搞了..."
- 未来朋友圈/群聊里,这条卡片可以作为可评论对象；召唤工具的角色可以补充"我是怎么帮你推进这件事的"

### UI

`dev_room_screen` 顶部加"今日日志"卡片,点开看完整结构 + 跳转到对应 runs。

### 完成判定
- 连续 3 天每天自动生成日志,无重复无遗漏
- 日志能在普通 Memory Review 流里被发现(不是藏在 Dev Room 里)
- 伴侣角色被问"她今天忙什么"时,能从 coding_log 里答出来,并提到 CC/Codex 的名字

---

## Phase 4a — 多项目体验打磨（已完成）

✅ 项目卡片 ⋮ 菜单（编辑/删除 + 清理 worktree）
✅ 权限档彩色 chip（只读=蓝 / 写入=绿 / 发布=红）
✅ 运行摘要（"3 完成 · 上次 12 分钟前"）
✅ 列表按 createdAt 倒序
✅ Bridge `POST /v1/cleanup/worktrees` 批量清理
✅ 项目删除按钮

---

## Phase 4a+ — 项目级 Git 操作：Pull / Push（设计已确认，待实现）

### 目标

让用户在 Dev Room 里直接同步主工作副本的 Git 状态——pull 拉取远程、push 推送本地改动。这两个操作**不经过 agent、不进 worktree**，是确定性的 Bridge 端点 + 审批按钮。

Agent 改代码产生的 commit 仍然走 Phase 2 的 worktree → Apply 流程，不在本 Phase 范围内。

### 三个 Git 动作的归属

| 动作 | 触发方式 | 谁决策 | 经不经过 agent |
|---|---|---|---|
| 🔄 Pull | Dev Room 按钮 / 看到角标提醒 | 用户 | ❌ 固定 Bridge 端点 |
| ✅ Commit | agent run → review diff → Apply | 用户（审批 diff 后合并） | agent 在 worktree 里已 commit |
| 📤 Push | Apply 后，用户决定同步到远程 | 用户 | ❌ 固定 Bridge 端点 |

关键原则：**Pull 和 Push 是人对代码状态的判断，不是 agent 的决策。不交给 LLM。**

### 用户场景

**场景 A — 出门前同步**：打开 Dev Room，项目卡片角标显示"远程领先 3 commits"→ 点「拉取最新」→ 审批弹窗显示具体命令 → 确认 → 几秒后完成。

**场景 B — agent 改完代码后推送**：agent run 完成 → 看 diff → Apply（merge 到 personal-lab）→ 项目卡片显示"本地领先 1 commit"+「推送到远程」按钮 → 点按钮 → 审批弹窗 → 确认 → push 完成。

### Bridge 新增端点

```
POST /v1/projects/{id}/git-pull
  行为: cd {rootPath} && git fetch origin {defaultBranch} && git merge --ff-only origin/{defaultBranch}
  返回: { pulled: int, commits: [{hash, message}], currentHash: string }
  错误: 非 fast-forward / 有本地未提交改动 / fetch 失败 → 返回错误描述，不回滚
  
POST /v1/projects/{id}/git-push
  行为: cd {rootPath} && git push origin {defaultBranch}
  返回: { pushed: int, commits: [{hash, message}], remoteUrl: string }
  错误: 非 fast-forward / 无推送权限 / 网络错误 → 返回错误描述

GET /v1/projects/{id}/git-status
  返回: {
    branch: string,
    ahead: int,          // 本地领先远程的 commit 数
    behind: int,         // 远程领先本地的 commit 数
    lastFetch: int?,     // 上次 fetch 时间戳
    recentApplies: [{runId, summary, agentType, timestamp}],  // 最近 Apply 记录
    hasUncommittedChanges: bool
  }
```

### App 侧审批

Pull 和 Push 各产生一条 `DevAgentApprovals`，kind 分别为 `git_pull` / `git_push`：

```
┌──────────────────────────────────┐
│ 审批：拉取远程代码                 │
│                                  │
│ 将在 D:\鱼\here-i-am 执行：       │
│ git fetch && git merge --ff-only │
│ origin/personal-lab              │
│                                  │
│ 预计快进合并 3 个 commit。         │
│                                  │
│       [取消]    [确认拉取]         │
└──────────────────────────────────┘
```

与 agent run 审批一致：5 分钟未响应 → `expired`，Bridge 不执行。

### Dev Room UI 改动

项目卡片增加 Git 状态行和操作按钮：

```
┌──────────────────────────────────┐
│ 🔴 here-i-am                📋  │
│ personal-lab                     │
│                                  │
│ ⚠ 远程领先 3 commits · 2h 前     │  ← 仅 behind > 0 时显示
│                                  │
│ 3 完成 · 上次 12 分钟前           │  ← 现有运行摘要
│                                  │
│ 📤 本地领先 1 commit              │  ← 仅 ahead > 0 时显示
│    [📤 推送到远程]                │
│                                  │
│ 最近合并:                        │
│ ✅ "加 RecordOrganizer 重试上限"  │
│    (Claude Code, 5 分钟前)       │
│ ⏳ "重构 handler"                │
│    (Codex, 运行中)               │
└──────────────────────────────────┘
```

Pull 按钮仅 behind > 0 时显示。Push 按钮仅 ahead > 0 时显示。两者可同时出现（本地和远程各自有新 commit）。

### 权限档行为

| 档位 | git-pull | git-push |
|---|---|---|
| `read_only` | ❌ | ❌ |
| `workspace_write` | ⚠️ 审批 | ❌ |
| `release_ops` | ⚠️ 审批 | ⚠️ 审批 |

`workspace_write` 可以 pull 但不能 push——push 需要 `release_ops`。这与 Phase 2 原有权限表一致：`workspace_write` 允许本地 commit，但不允许远程推送。

### 与 Phase 4b（PR 自动开）的关系

Phase 4b 的 `release_ops` 模式下，Apply 不再直接 fast-forward merge 到 `personal-lab`，而是 `git push origin dev-agent/{short} && gh pr create`。此时：
- Push 按钮操作的不是 worktree 分支，而是主分支 `personal-lab`
- 如果用户想手动 push 主分支（不走 PR），仍然可以用 Push 按钮
- Phase 4b 不改本 Phase 的端点，只在 Apply 逻辑里加分支

### 完成判定

- `read_only` 项目不显示 pull/push 按钮
- `workspace_write` 项目能 pull，push 按钮不显示
- `release_ops` 项目能 pull 且能 push
- pull 非 fast-forward 时弹错误提示，不损坏本地
- push 被远程拒绝时弹错误提示
- git-status 在项目卡片打开时自动刷新，角标准确

---

## Phase 5 — 角色可召唤的多轮 Dev Session（已开始）

### 目标
让普通陪伴角色可以召唤 Claude Code / Codex 去读资料、改代码、做 review，并把结果带回聊天；同时保留 Dev Room 作为可多轮追问、查看进度、审批、diff、apply/discard 的控制台。

### 当前进度（2026-06-22）

- ✅ 数据层已新增 `DevAgentSessions` / `DevAgentSessionMessages` / `DevAgentToolBindings`
- ✅ `DevAgentRuns` 已可关联 app 侧 `devSessionId`
- ✅ Dev Room 已有 Claude/Codex 会话入口、最近会话列表和 `DevSessionScreen`
- ✅ Bridge 原生 resume 前，App 先用最近会话上下文 + 新 run 模拟多轮
- ✅ 主聊天 companion 角色已接入 `dev_session_start_or_continue` 工具，可异步创建/继续 Dev Session
- ✅ Dev Session 完成后可回流到召唤角色聊天，并带可打开 Dev Room 的结果卡片
- ✅ 结果回流后会排 `dev_session_followup` 后台任务，让召唤角色用自己的口吻解释结果/建议下一步
- ✅ 主聊天里“继续刚才那个 / 下一篇 / 接着看”会自动复用该角色最近 active Dev Session
- ⏭️ 下一步：角色工具绑定 UI（默认项目 / 默认 agent / 权限档），收紧哪些角色能召唤哪些工具

一句话边界：

> 角色决定要不要召唤工具；Bridge 执行工具；Dev Room 承载过程；聊天承载关系、解释和决策。

### 场景目标

小红书共读应当能这样跑：

1. 用户在主聊天里说："我们读一下这批小红书原文，先从第一篇开始。"
2. 角色创建一个 `DevAgentSession`，召唤 Codex 读取第一篇 markdown。
3. Codex 的结果回到这个 session；角色用自己的口吻总结、追问用户。
4. 用户继续说："第二篇拿来对比一下。"
5. 系统继续同一个 session，不要求用户新建任务。
6. 用户也可以打开 Dev Room，直接在这个 session 里输入"继续下一篇"或查看历史、artifact、决策。

### 数据层

新增长期会话表。一次性 `DevAgentRuns` 继续存在，但变成 session 下的一次执行回合。

```dart
class DevAgentSessions extends Table {
  TextColumn get id => text()();                 // uuid
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();          // 'claude_code' | 'codex'
  TextColumn get title => text()();
  TextColumn get goal => text().nullable()();
  TextColumn get mode => text().withDefault(const Constant('read_only'))();
  TextColumn get ownerCharacterId => text().nullable()(); // 哪个角色召唤的；用户直接创建则为空
  TextColumn get providerSessionId => text().nullable()(); // Claude/Codex 侧 session id
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  @override Set<Column> get primaryKey => {id};
}

class DevAgentSessionMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(DevAgentSessions, #id)();
  TextColumn get role => text()();               // user|character|agent|system
  TextColumn get content => text()();
  TextColumn get linkedRunId => text().nullable()();
  IntColumn get createdAt => integer()();
  @override Set<Column> get primaryKey => {id};
}

class DevAgentToolBindings extends Table {
  TextColumn get characterId => text()();        // 哪个角色能召唤
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();          // 默认召唤 Claude Code 还是 Codex
  TextColumn get defaultPermissionTier => text().withDefault(const Constant('read_only'))();
  TextColumn get defaultMode => text().withDefault(const Constant('read_only'))();
  IntColumn get createdAt => integer()();
  @override Set<Column> get primaryKey => {characterId, projectId, agentType};
}
```

### Bridge 协议

新增 session 级接口：

- `POST /v1/sessions`：创建长期 Dev Session，返回 `bridge_session_id`
- `POST /v1/sessions/{id}/messages`：向同一个 session 继续发消息
- `GET /v1/sessions/{id}`：查 session 状态、当前活跃 run
- `GET /v1/sessions/{id}/events?after=...`：拉多轮事件流

CLI 侧续接：

- Claude Code：优先验证 `claude -p --resume <session_id>` 或当前版本等价参数
- Codex：优先验证 `codex exec resume <session_id>` 或 `codex exec resume --last`

如果某个 CLI 的非交互 resume 不稳定，Bridge 仍可用"session transcript + new run"模拟多轮，但必须在 UI 上标注为同一 Dev Session。

### 聊天集成

普通 companion 角色新增一个工具：

```text
dev_session.start_or_continue(project, agent_type, goal, message, mode)
```

行为：

- 角色根据聊天语境决定是否召唤 Claude Code / Codex。
- 用户不需要去 Dev Room 新建任务。
- 角色收到 session 结果后，用自己的口吻解释，而不是把原始事件流直接丢给用户。
- 如果有 diff / apply / discard / approval，聊天气泡里出现按钮；按钮背后仍调 Dev Room/Bridge 的 decision 接口。

### Dev Room 集成

Dev Room 从"run 列表"升级为"session 列表 + run 历史"：

- 项目下显示活跃 Dev Sessions。
- 点进 session 后能继续输入消息。
- session 里显示关联 runs、artifacts、approvals、decisions。
- 用户可以不经过角色，直接在 Dev Room 里继续追问。

### 写操作的决策 UX

worktree 隔离 / decision 日志 / apply / discard 全部保留，但可以出现在聊天气泡或 Dev Room 两处：

```text
[角色] Codex 已经按我们的讨论改完了，主要动了 3 个文件。
       [应用] [丢弃] [看 diff]
```

按钮直接调 Bridge decision；结果同时写入 session message：

```text
[系统] 已合并到 personal-lab。
```

### 完成判定

- Dev Room 能创建一个长期 session，并在同一 session 里连续追问，不需要每次新建任务。
- 主聊天里的普通角色能创建/继续 Dev Session，并把结果用自己的语气带回聊天。
- 小红书共读场景跑通：第一篇 → 讨论 → 第二篇对比 → 形成产品建议，全程同一 session。
- 写权限场景跑通：角色召唤 Codex/Claude Code 改代码，diff 出现，聊天或 Dev Room 中可 apply/discard。
- 手机杀进程重开后，session 历史、关联 run、decision、artifact 仍可恢复。

### 工程量

这是 Phase 5 的主干，不再拆成"假入口"和"真能力"两个产品形态；但工程实现按数据层 → Dev Room 多轮 → 聊天工具 → 回流 UX 顺序推进。

---

## Phase 3 — Daily Coding Log + 署名记忆卡片（接 5 后面）

### 目标
每天自动生成一张 coding 事实卡片，带 CC/Codex 署名，进 `SharedLifeEntities`，让其他伴侣角色自然知道"你今天和 CC 在忙什么"。

（详细数据流见前面 Phase 3 章节，没变。）

### 关键
- 必须在 Phase 5 之后做：5 产生真实 session/run 数据，3 把它转成可被角色检索的卡片
- 不能跳过：这是其他角色自然知道"我召唤工具帮你做了什么"的社会基础

---

## Phase 4b — PR 自动开（release_ops 真启用）

### 目标
release_ops 项目的 apply 改成"推 dev-agent 分支 + 调 gh pr create"，PR URL 回贴聊天。

### 做什么
- Bridge 配 `GH_TOKEN`（环境变量或 `gh auth`）
- release_ops 模式下，apply 不再 fast-forward merge 本地 default，改为 `git push origin dev-agent/{short} && gh pr create --title ... --body ...`
- PR URL 作为 artifact，聊天里给链接

### 完成判定
- 真实仓库走一次：CC 改 → apply → PR 自动开 → GitHub 上能看到

---

## Phase 6 — 语音陪伴（通勤路上 Codex 读文章）

### 目标
路上用蓝牙耳机听 Codex 讲解文章 / 汇报项目进度。

### 做什么
- 复用项目里现有 ElevenLabs TTS
- Codex 消息自动 TTS 播放
- 蓝牙耳机控制（下一段、暂停、长按提问）
- 锁屏播放控制

### 完成判定
- 通勤路上完全免手能听完一篇小红书归档文章 + 提问 + 听回答

---

## 已砍掉的方向

**原 Phase 5 "双代理协作（CC 写 + Codex review）"** —— 太 niche，token 成本高、仲裁难、用户审两份意见更累。需要时手动派两个 run 就行，不值得做产品化。

**"CC/Codex 完整人格角色"** —— 改为"角色召唤 coding 工具"。Claude Code / Codex 保持为 Bridge 侧能力，不直接承担关系主体；普通角色负责决定、解释和陪伴。

**"开发助理"代理角色** —— 不单独造一个只负责转发的角色。Phase 5 让所有合适的陪伴角色都能召唤 Dev Session，避免多一层空壳入口。

---

## 安全红线

任何阶段都不能违反：

1. **手机端不存任何 token**（GitHub、Claude API、OpenAI），全部在 Bridge 端
2. **Bridge URL 必须 HTTPS / Tailscale**，不接受明文 HTTP
3. **任何 `bash` / `write` / `commit` / `push` / `network`** 在 `workspace_write` 以上必须审批
4. **审批不能批量"全部同意"**，每条单独点
5. **worktree 路径绝不在用户家目录根部**，强制在 `{projectRoot}/.dev-agent/worktrees/` 下
6. **Dev Room 过程数据**(run/diff/审批/事件流)不写入 `CardCache` / `KnowledgeInsight` / PKM 任何表;只有 Phase 3 的 coding_log 进 `SharedLifeEntities`
7. **任何阶段都不引入** `danger-full-access` 路径

---

## 拾起指南（隔了几周回来怎么办）

1. 看 `DEVLOG.md` 最近条目，确认上次停在哪
2. 看本文件，找到对应 Phase 的"完成判定"
3. 没满足判定 → 接着做当前 Phase
4. 满足 → 进下一 Phase 的"做什么"
5. Bridge 起不来 → 先跑 Phase 0 的协议验证
