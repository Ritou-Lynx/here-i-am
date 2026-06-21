# Dev Agent Room — 路线图

把 Claude Code 和 Codex 接进 Here I am，作为可远程控制的"开发代理"，而不是普通陪伴角色。
本文是可随时拾起的执行手册，不是产品讨论。

## 核心原则（决策已锁，不再讨论）

1. **执行隔离，但角色平权**：Dev Room 的工程过程数据（run/diff/审批）独立于陪伴系统；但 CC/Codex 本身是一等公民角色，与其他伴侣角色平权，能被 @、能进群聊、能在朋友圈评论。
2. **手机不执行代理**：手机端只是控制台。真正的 CC / Codex 进程跑在常驻开发机上的 Bridge 里。
3. **桥接复用现成方案**：Bridge 第一版基于 MyPilot fork,不从零写 hooks/加密/重连。
4. **数据分层**：
   - **工程过程数据**（run/diff/审批/事件流）→ 专属表 `DevProjects` / `DevAgentRuns` / `DevAgentEvents` / `DevAgentApprovals`,不进 User-truth(它们不是"事实",是过程)
   - **每日工作产出**（coding_log)→ 进 `SharedLifeEntities`,所有角色平等可见,带署名
5. **权限默认最紧**：新建项目默认 `read_only`。`workspace_write` 和 `release_ops` 必须用户对项目显式升级。
6. **入口在 Settings / Personal**，不在生活空间内。
7. **不做访问圈层**：所有角色平等读取 User-truth。私密性来自"用户不主动记录",不来自系统隔离。这与"多个伴侣角色相互知道彼此存在"的产品设定一致。

## 路线图总览

| Phase | 范围 | 预估 | 可独立交付 |
|---|---|---|---|
| 0 | Bridge 选型与原型 | 2 天 | 是 |
| 1 | 只读远程台 | 1 周 | 是 |
| 2 | 写权限 + 审批闭环 | 1 周 | 是 |
| 3 | Daily Coding Log + 事实卡片 | 3 天 | 是 |
| 4 | 多项目 + PR 自动开 | 1 周 | 是 |
| 5 | 双代理协作（CC 实现、Codex review） | 待定 | 是 |

每个 Phase 自带"完成判定"和"下一步触发条件"，没做完不进下一阶段。

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
- 未来朋友圈/群聊里,这条卡片可以作为可评论对象,CC/Codex 自己也能在自己写的日志下补充评论

### UI

`dev_room_screen` 顶部加"今日日志"卡片,点开看完整结构 + 跳转到对应 runs。

### 完成判定
- 连续 3 天每天自动生成日志,无重复无遗漏
- 日志能在普通 Memory Review 流里被发现(不是藏在 Dev Room 里)
- 伴侣角色被问"她今天忙什么"时,能从 coding_log 里答出来,并提到 CC/Codex 的名字

---

## Phase 4 — 多项目 + PR 自动开（1 周）

### 目标
管多个仓库，一键开 PR。

### 做什么
- `DevProjects` 支持多行，UI 加项目切换
- `release_ops` 档加 `cc_open_pr` 工具：调 `gh pr create`，需审批
- PR 链接回写到 `DevAgentRuns.summary`
- Bridge 端配置 `GH_TOKEN`，App 不碰

### 完成判定
- 同时管 3 个项目，run 不串
- 一次任务从"补测试" → "开 PR" → "合并"全程在手机完成

---

## Phase 5 — 双代理协作（待定）

### 目标
CC 实现、Codex review，或反过来。

### 暂时不做的理由
- 两个 agent 互看输出 token 爆炸
- diff 冲突仲裁难
- 用户审两份意见更累

### 想做时的方向
- 不是"实时互看"，而是**接力**：CC 任务结束 → Codex 单独读 diff 出 review → 用户看 review → 决定 apply
- review 也是一个 `DevAgentRun`，`agentType = 'codex_reviewer'`
- 不要让两个 agent 在同一 worktree 里同时写

---

## 跨阶段：开发助理角色（可选，Phase 2 之后随时做）

主聊天里加一个普通 Companion 角色"小开发"（或别的名字）：
- persona：温和的工程助理，知道你有 Dev Room
- 工具：仅 `open_dev_room(project_name, task_description)`
- 行为：用户说"让 CC 帮我看看 X" → 调工具 → 在 Dev Room 创建 run → 返回 runId → 角色回："好，已经派给 CC 了，去 Dev Room 看进度"

这个角色不持有任何 CC 工具，只是入口。

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
