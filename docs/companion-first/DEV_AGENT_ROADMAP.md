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

## 路线图总览（2026-06-21 修订）

| Phase | 范围 | 状态 |
|---|---|---|
| 0 | Bridge 选型与原型 | ✅ 完成 |
| 1 | 只读远程台 | ✅ 完成 |
| 2 | 写权限 + worktree + apply/discard 真做 | ✅ 完成 |
| 4a | 多项目体验打磨（chip / 摘要 / cleanup / 删除） | ✅ 完成，dogfood 中 |
| **5** | **CC/Codex 完整聊天角色（一次到位，不切薄片）** | **下一步** |
| 3 | Daily Coding Log + 署名记忆卡片 | 接在 5 后面 |
| 4b | PR 自动开（release_ops 真启用） | 后续 |
| 6 | 语音陪伴（通勤路上 Codex 读文章 + TTS） | 后续 |

**砍掉的**：原 Phase 5 "双代理协作（CC 写 + Codex review）" —— 太 niche，长期都不做。

### 几次重要的方向校正（防止以后忘）

1. **Phase 5 不切薄片**：之前讨论过"5a 派单入口 / 5b 角色绑定 / 5c 多轮 / ..."的渐进方案，被否。原因：CC 是角色就意味着具备 coding 能力，不能拆成"先做聊天入口再加 coding"——那样过渡形态没人会用，纯粹是工程师"小步快跑"心理投射。本项目里 prompt cost 在用户、code cost 在 AI，"先 MVP 再迭代"的传统理由不成立。
2. **CC/Codex 是角色就拥有完整 coding 能力**：之前讨论过"人格平权但权限不平权"（入口像人，执行像工具），被否。用户的诉求是 Codex 角色 = Codex 本身，写文件 / commit / apply / discard 都在聊天里完成。worktree 隔离和审计日志这套底层 plumbing 继续存在，但 UX 不再有单独的"决策栏页面"——决策以聊天气泡里的按钮形式出现（"已改 3 个文件，要 apply 吗 [应用][丢弃][看 diff]"）。
3. **绑定用独立表，不污染 CharacterModel**：新增 `DevAgentCharacterBindings` 表（characterId / projectId / agentType / defaultPermissionTier / defaultMode），不在 CharacterModel 上加字段。符合 CLAUDE.md "companion 层可剥离" 红线。
4. **Phase 3 不能太靠后**：coding_log + 署名是其他伴侣角色"听说过" CC/Codex 的社会基础，必须在 5 之后立刻做，不能拖到末尾。

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

## Phase 4a — 多项目体验打磨（已完成）

✅ 项目卡片 ⋮ 菜单（编辑/删除 + 清理 worktree）
✅ 权限档彩色 chip（只读=蓝 / 写入=绿 / 发布=红）
✅ 运行摘要（"3 完成 · 上次 12 分钟前"）
✅ 列表按 createdAt 倒序
✅ Bridge `POST /v1/cleanup/worktrees` 批量清理
✅ 项目删除按钮

---

## Phase 5 — CC/Codex 完整聊天角色（下一步）

### 目标
让 CC/Codex 在主聊天里作为完整角色出现，写文件 / commit / apply / discard 都在聊天里完成。不切薄片。

### 数据层
新增 `DevAgentCharacterBindings` 表：
```dart
class DevAgentCharacterBindings extends Table {
  TextColumn get characterId => text()();             // 主键，对应 CharacterModel.id
  TextColumn get projectId => text().references(DevProjects, #id)();
  TextColumn get agentType => text()();               // 'claude_code' | 'codex'
  TextColumn get defaultPermissionTier => text().withDefault(const Constant('workspace_write'))();
  TextColumn get defaultMode => text().withDefault(const Constant('workspace_write'))();
  IntColumn get createdAt => integer()();
  @override Set<Column> get primaryKey => {characterId};
}
```

不污染 CharacterModel，删功能只需删表。

### 角色创建
- 角色编辑页加"绑定为 Dev Agent"开关
- 开启后让用户选 project + agentType + 默认权限档
- 头像可以是 Claude / OpenAI logo，或自己上传

### 聊天集成
- CC/Codex 角色在主聊天 persona 轮播里正常出现，可 @、进群聊、朋友圈评论
- 进入聊天后，CompanionAgent 那一层分岔：
  - 普通角色 → 走 LLM provider（现状）
  - dev agent 角色 → 走 bridge 多轮会话
- 复用 PersonaChatScreen，消息气泡里嵌入 tool call（文件操作、diff、命令）

### 多轮会话
- CC：`claude -p --resume <session_id>` 续接
- Codex：`codex exec resume <session_id>`
- bridge 端为每个 character 维护一个活跃 session_id
- 新消息发来时带上 session_id

### 写操作的决策 UX
worktree 隔离 / decision 日志 / apply / discard 这些底层 plumbing 全部保留，但 **UX 整合进聊天**：

```
[Codex] 我给 RecordOrganizerService 加了 12 个单测，覆盖率从 34% → 78%。
        [应用] [丢弃] [看 diff]
```

按钮直接调 decideRun，结果作为新消息附在下面：

```
[系统] 已合并到 personal-lab。
```

### 完成判定
- 主聊天能看到 CC/Codex 角色
- 跟他们说"看下 X 改成 Y" 真能改，diff 出现，决策按钮可用
- apply 真合到 default branch，UI 给反馈
- 多轮：下一句"再加点测试" 接着同个 session，不重新开

### 工程量
2-4 天，看具体绕路。不再保证 1 周/2 周这种数字。

---

## Phase 3 — Daily Coding Log + 署名记忆卡片（接 5 后面）

### 目标
每天自动生成一张 coding 事实卡片，带 CC/Codex 署名，进 `SharedLifeEntities`，让其他伴侣角色自然知道"你今天和 CC 在忙什么"。

（详细数据流见前面 Phase 3 章节，没变。）

### 关键
- 必须在 Phase 5 之后做：5 产生真实 run 数据，3 把它转成可被角色检索的卡片
- 不能跳过：是 CC/Codex 人格化的社会基础

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

**"开发助理"代理角色** —— 之前讨论过加一个普通 Companion 角色，只持 `open_dev_room` 工具作为入口。Phase 5 把 CC/Codex 自己变成角色后，这种代理就没用了，砍掉。

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
