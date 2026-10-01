# GOAL-20260826-authority-preflight — 数据权威盘点与迁移证据预备

> 状态：已完成（2026-08-26 用户真人通过并关闭）
>
> 验收主窗 task/thread ID：`01a03c7e-ceda-7351-9ed6-93c48e9c15d5`
>
> Roadmap：`docs/companion-first/PRODUCT_ROADMAP.md` 的 Gate 0 临时例外
>
> 基线：`v3-lab@603d7acd3862578109ce51d2c17f7020a5c8f5c4`
>
> 创建 / 确认日期：2026-08-26
>
> 集成目标：`v3-lab`
>
> push / 发布：未授权

## 最终结果

在不依赖私人电脑、不使用真实用户数据、不改变任何生产运行权威的前提下，形成一套可复核的当前对象盘点、预备迁移矩阵、合成 golden corpus 与隔离 harness 骨架，供 Goal 1 关闭后的正式 Gate 1A-0 使用。

本 Goal 是证据预备，不是 Gate 1A-0 的提前通过。P4 / P5 / P6 及其他未完成事实必须作为 unresolved input 显式保留，不能假设为绿。

## 进入条件

- [x] Goal 1 本轮候选人工验收已结束且结论为未通过。
- [x] 用户确认短期无法回私人电脑完成 P5 / P6，并明确同意执行独立预备 Goal。
- [x] Goal 1 已转为阻塞并冻结，不再同时派发、集成或构建。
- [x] Goal 1 收口文档已形成控制面提交 `603d7acd`。
- [x] 现有 COROS / 健康与 i Gateway 并行改动已识别为本 Goal 范围外。

## 完成定义

- [x] 建立当前对象清单，至少覆盖 Card / Memory Card、User-truth、SourceContent / SourceVersion、RichTextDocument、Board / BoardItem、Annotation / Anchor、Dreaming Fragment / Episode / Saga、Evidence、TaskArtifact / TaskRoom。
- [x] 每类对象都记录稳定身份、物理存储、当前权威、写入者、读取者、投影 / 索引、生命周期、删除 / 恢复、备份和已知越界；无法确认的字段必须标为 `unknown` 或 `blocked`，不得猜测。
- [x] 建立预备迁移矩阵，将每类对象标为保留、迁移、派生、只读兼容、降级保留或阻断，并记录证据路径；不提前决定正式物理 schema。
- [x] 建立不含真实用户数据的 golden corpus，覆盖中文正文、空值、版本、来源 / Anchor、富文本 marks / assets、重复 ID、无效元数据、外部移动 / 删除和冲突候选等迁移红灯。
- [x] 建立隔离 harness 骨架，只读取合成 fixture，在临时目录运行；不得打开、复制或修改生产数据库、Vault、用户附件或 Gateway ledger。
- [x] harness 至少能执行 fixture 载入、结构校验、确定性输出与失败分类；所有尚未实现的迁移步骤必须诚实返回 unsupported / blocked，不得伪造成功。
- [x] 输出预备 ADR 选项与待决问题，但不得把它称为正式 Authority ADR，不得宣称 Gate 1A-0 通过。
- [x] 定向测试、changed-file analyze（如有 Dart 变更）和 `git diff --check` 通过；每个工作包提供 commit、handoff、限制与干净工作树证据。
- [x] 验收主窗完成逐包审计、状态页 / Roadmap / `I_PROJECT_STATE.md` / DEVLOG 与 i closeout 收口；不构建 Windows / Android 产品候选。

## 明确不做

- 不修 UI-T、P4、P5、P6 或 W4，不触碰其拥有路径与真人 Gate。
- 不修改 Drift schema、迁移版本、生产 repository / service 注册、Runtime / Memory 接线、Record Organizer 或 User-truth 写入。
- 不切换 Markdown / YAML、RichTextDocument、SQLite、Source 或操作日志的默认权威，不双写。
- 不读取真实手机 / 私人电脑数据库，不使用真实聊天、Memory、Card、Source、凭据或生活资料作为 fixture。
- 不创建 1A-1 / 1A-2 / 1A-3、Gate 1B / 1C 或教师招聘实现。
- 不构建、安装、push、发布，也不清理其他工作线的分支、Worktree 或未提交改动。

## 工作包状态

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| B0 控制面与隔离 | 验收主窗 | `01a03c7e-ceda-7351-9ed6-93c48e9c15d5` | `603d7acd` | `v3-lab` | 已集成 | `b0a71770` | 本页 | 通过 | 文档一致性 / `git diff --check` 通过 | 不需要 | 主动等待并回收 A1 |
| A1 权威对象盘点与预备迁移矩阵 | 独立 Codex 任务 + Worktree | 当前 `01a03c91-8bae-7491-a3b2-4cb20f4f8a92`；错误基线任务 `01a03c90-2cf7-72b1-84b7-9e14d9f9fb49` 已停止 | `b0a71770eaa8128d1ee67d60331ce79c6ecc4835` | detached / `C:/Users/ExampleUser/.codex/worktrees/c493/here-i-am` | 已集成 | 内容 `89b67680` + handoff `10eacaae`；集成 `98c137eb` + `7f63be06` | `docs/development/data-authority-preflight/A1_AUTHORITY_INVENTORY_HANDOFF.md` | 通过：范围 / 祖先 / 事实边界 / unresolved input / handoff 已复核 | `LINK_TARGETS_OK`、覆盖关键词无缺失、`git diff --check` 通过 | 不需要 | 以 `7f63be06` 为 A2 基线；A1 不再写入 |
| A2 合成 Golden Corpus 与隔离 Harness | 独立 Codex 任务 + Worktree | `01a03c9b-75f4-7a23-bec4-224f5c77f739` | `e72a5f733bace240312fd5a4b37a771e68d2fe89` | detached / `C:/Users/ExampleUser/.codex/worktrees/2d6b/here-i-am` | 真人通过 | worker 最终链至 `a519e98e`；主窗最终树集成 `ce4e089c` | `docs/development/data-authority-preflight/A2_GOLDEN_HARNESS_HANDOFF.md` | 通过：两轮返修后逐项分类、隔离边界与 handoff 已复核 | 定向测试 `7/7`、changed-path analyze 零问题、`git diff --check` 通过 | 2026-08-26 用户确认通过 | 本 Goal 已关闭；blocked / unsupported 继续作为正式 Gate 输入 |
| W0 统一审计与收口 | 验收主窗 | `01a03c7e-ceda-7351-9ed6-93c48e9c15d5` | A1 `7f63be06`；A2 `ce4e089c` | `v3-lab` | 真人通过 | `ce4e089c` + 本页关闭提交 | 本页 | A1 / A2 均通过 | 组合校验通过；确定性报告 `2016` bytes、`migrationExecuted=false` | 2026-08-26 用户确认通过并关闭 | 无后续派发；Goal 1 继续阻塞，不解锁 1A-0 |

固定状态枚举：`待派发 → 进行中 → 等待用户 → 已交付 → 已审计 → 已集成 → 已构建 → 真人通过`；终止状态为 `失败`、`取消`、`被取代`。本 Goal 不构建产品候选，完成时以文档 / harness 审计和用户审阅取代“已构建”阶段，但不得把它映射为 Gate 1A-0 真人通过。

## 依赖与集成顺序

1. B0 先固化 Goal、Roadmap 例外和 Goal 1 阻塞状态。
2. A1 从 B0 激活提交创建隔离 Worktree，完成只读盘点与预备迁移矩阵。
3. W0 审计 A1 的证据覆盖、未知项和边界；未通过则返回 A1 原任务返修。
4. A2 只从已审计 A1 基线启动，依据已确认对象范围建立合成 corpus 与隔离 harness。
5. W0 审计 A2 不读取真实数据、不接生产路径、失败分类诚实，再运行组合校验。
6. 用户审阅预备结论后收口本 Goal；Goal 1 仍保持阻塞，正式 Gate 1A-0 仍未创建。

## 派发与基线记录

- 2026-08-26 首次创建的 A1 任务 `01a03c90-2cf7-72b1-84b7-9e14d9f9fb49` 自动落在 detached `9145fe61`，不包含激活提交 `b0a71770`。W0 在写入前触发基线守门并停止任务；该任务无交付、不得复用。
- A1 已重派为 `01a03c91-8bae-7491-a3b2-4cb20f4f8a92`，Worktree `C:/Users/ExampleUser/.codex/worktrees/c493/here-i-am`；W0 外部核对 HEAD 为 `b0a71770eaa8128d1ee67d60331ce79c6ecc4835`、工作树干净、detached 状态符合隔离任务预期。
- A1 内容提交 `89b67680` 首次 handoff 因 task ID、基线时态与验证证据不自包含被退回；原任务以 `10eacaae` 补齐后通过。W0 在 `v3-lab` 依次集成为 `98c137eb`、`7f63be06`，重新验证链接、覆盖和 diff check 均通过。
- A1 的关键红灯是当前白板 Card 复用 `MemoryCards` 并写成 `user_truth`；这只是正式 Gate 的阻断证据，不授权 A2 创建中性 Card schema 或切换权威。
- A2 已派发为 `01a03c9b-75f4-7a23-bec4-224f5c77f739`，Worktree `C:/Users/ExampleUser/.codex/worktrees/2d6b/here-i-am`；W0 核对 HEAD 为 `e72a5f733bace240312fd5a4b37a771e68d2fe89`、工作树干净，并证明其包含 A1 集成提交 `7f63be06`。
- A2 初次交付因字符串路径守门、宽松 manifest 与红灯样例 / 断言不足被 W0 退回；第二轮修复了真实路径 / link 隔离、严格清单和结构化 corpus，第三轮补齐全部对象精确分类与未声明文件拒绝。worker 最终 HEAD 为 `a519e98e`；W0 未把被驳回的中间态逐项标为接受，而以最终树状态集成为 `ce4e089c`。
- W0 独立复现定向测试 `7/7` 与变更范围 `dart analyze` 零问题；普通 `dart test` 首次被 Windows Worktree 原生构建缓存锁拒绝，改用项目已解析的 test runner 后沙箱又无法监听 SIGINT，获批在沙箱外只读运行后通过。harness 在仓库外系统临时目录生成 `2016` bytes 确定性报告，明确 `migrationExecuted=false`。

## 拥有路径与共享契约

- A1 拥有：`docs/development/data-authority-preflight/` 下的盘点、矩阵、预备 ADR 与 handoff 文档。
- A2 拥有：`tools/data_authority_preflight/`、`test/data_authority_preflight/` 及自己的 handoff。
- 只读：`lib/db/`、`lib/data/`、`lib/domain/`、`lib/agent/`、白板契约与现有迁移 / 测试；不得修改 `*.g.dart`。
- 共享契约：全部只读。发现 Card / Source / Anchor / RichText / Memory / Task 语义冲突时，只登记证据和正式 Gate 1A-0 的变更请求。
- 禁止路径：Goal 1 的 UI-T / P4 / P5 / P6 交付路径、现有 COROS / 健康与 `tools/i_continuity_gateway/` 并行改动。

## 自动 Gate

- 文档链接、对象覆盖表、迁移枚举和 unresolved input 可机器检查。
- 合成 fixture 不包含绝对用户路径、真实 ID、聊天 / Memory 正文、凭据或数据库副本。
- harness 仅接受显式 fixture 根与临时输出根；默认拒绝生产路径和未声明输入。
- 相同输入连续运行输出一致；未知 schema / 对象类型返回明确失败分类。
- `git diff --check` 通过；如产生 Dart 代码，只分析实际变更文件。

## 真人 Gate

- 当前电脑可打开并阅读对象清单、矩阵、预备 ADR 选项与 harness 报告。
- 用户能够区分“当前事实”“预备建议”“unknown / blocked”与“正式 Gate 1A-0 尚未决定”。
- 不要求私人电脑、真实数据库、Windows 产品候选或手机安装。

## 失败返回

- A1 证据缺失、对象漏项或把推断写成事实：返回 A1。
- A2 需要真实数据、生产 schema / service 修改或默认权威切换才能成立：停止并记录为正式 Gate 1A-0 输入，不扩大本 Goal。
- 发现与 Goal 1 有代码或数据依赖：停止对应工作包，保留 Goal 1 为红，不用 mock 成功绕过。

## Goal 结论

- 完成时间：2026-08-26。
- 最终基线：交付集成 `v3-lab@ce4e089c`；关闭前主线 `v3-lab@f9c0b695`；以本页关闭提交完成控制面收口。
- push：未授权。
- 对 Gate 0 / 1A-0 的影响：无解锁作用；只提供可复用预备证据。
- 后续：Goal 1 继续阻塞、冻结，等待返回私人电脑后返修与真人复验；当前无活动 Goal，不自动创建正式 Gate 1A-0。
