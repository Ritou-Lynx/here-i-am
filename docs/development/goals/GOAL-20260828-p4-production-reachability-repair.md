# GOAL-20260828-p4-production-reachability-repair — P4 六命令生产接线返修

> 状态：真人通过（2026-09-05；R20 唯一候选 `e77045fa` 已完成 Runtime resize、remove placement、持久 Undo、冲突拒绝 / 可重试与完整重启验证；push / 发布未授权）
>
> 验收主窗 task/thread ID：`01a03e4a-e594-7b32-b3da-25705b8e1eb5`
>
> 父 Goal：[`GOAL-20260824-ai-workbench-wave1`](GOAL-20260824-ai-workbench-wave1.md)
>
> Roadmap：[`PRODUCT_ROADMAP.md`](../../companion-first/PRODUCT_ROADMAP.md) Gate 0
>
> 源码基线：`v3-lab@53d2dc91668b6ca5ba82cf9f4688f1b3ea609dbc`
>
> 控制面激活 commit：`69ddf56b325b774b0b1ffbe806e03edcab4fee27`
>
> 提出 / 确认日期：2026-08-28
>
> push / 发布：未授权

## 最终结果

桌面白板的人工入口与桌面 Runtime 对创建卡片、编辑正文、设置标签、移动、缩放、移除摆放六类操作都真实进入同一套 provider-neutral `DomainCommand / Receipt / Undo`，并在应用退出、重开后保持结果、行动记录和可用 Undo 一致；达不到这一生产闭环就不返回父 Goal 继续 P5 / P6 真人验收。

## 失败起点

- 合并后唯一候选 `v3-lab@53d2dc91` 的自动 Gate 通过，但 2026-08-28 真人复验确认：手动新建 / 标签 / 移动 / 缩放操作流畅，却没有 Domain Receipt 或持久 Undo。
- 白板真实打开并聚焦时，从桌面聊天连续两次请求创建并调整卡片：第一轮误找浏览器工具，第二轮称“当前工作台没有暴露可操作的白板窗口”，均未创建卡片或行动卡。
- 调用链复核确认 `executeUserDomainCommands` / `executeRuntimeDomainCommands` 没有生产调用者；普通桌面 Runtime 未注册或分发六类命令，手动 UI 仍直接写 repository / canvas adapter。现有 facade、executor 和自动测试是生产不可达孤岛。
- 因此本项是 P4 真人 Gate 失败，不是用户没有打开、聚焦或选择白板，也不是继续重试可解除的环境问题。

## 进入条件

- [x] 父 Goal 已保存失败转录、唯一候选指纹和自动 Gate 证据。
- [x] 六类 `WhiteboardDomainCommand`、Receipt、bounded inverse、真实 Drift action reader 与 restart hydration 已存在，可作为唯一实现基础。
- [x] 白板总纲确认：删除摆放只删除 `BoardItem`，不删除 Card；人工和 AI 写操作不得存在两套语义。
- [x] 用户明确确认创建本返修小 Goal。
- [x] 本控制面已作为独立、可追溯提交进入 `v3-lab`；P4-R 隔离 Worktree 从该提交创建，未带入主工作区 Voice V9.1 并行改动。

## 完成定义

### A. 人工入口生产接线

- [x] 白板 canvas 内嵌直接 UI 的 create / edit canonical plain body / set labels / move / resize / remove placement 在一次编辑保存或一次手势提交点构造 DomainCommand batch，并调用产品自有 facade；不得在旁路里直接提交 repository、snapshot 或 canvas adapter 作为最终权威写入。独立 full rich editor 仍是 repository writer，不包含在本条完成声明内。
- [x] 高频拖动 / 缩放的指针中间态可以留在 ViewModel，但手势结束的持久提交、Receipt、hash 与 Undo 必须来自同一 DomainCommand 执行结果。
- [x] host 为直接 UI 操作生成可审计、不可由模型伪造的用户操作引用；若现有共享接口不足，先提交最小兼容提案，由 W0 审核后再改，不得伪造聊天消息 ID。
- [x] 移除摆放只删除当前 `BoardItem`，Card 仍可从卡片库找到；创建、编辑和标签不自动写 User-truth。
- [x] 保持既有双击新建 / 原位编辑契约：同一 BoardItem 卡面、单一连续无框输入、首行标题 / 余下正文、原视觉与当前 viewport 不变；不得为接入 DomainCommand 替换成第二套编辑框。
- [x] 白板快捷卡片库的点击 / 拖入必须通过 manual-only DomainCommand 持久创建现有 Card 的 BoardItem，并产生 Receipt / Undo；不得只写 ViewModel 内存形成 reload 后消失的幽灵 placement。
- [x] 本 Goal 将 `EditCardBodyCommand` 明确定义为替换 Card 的 canonical 纯文本正文，不宣称替换 RichTextDocument 的 blocks / marks / assets；旧富文档投影与 Card body 不一致时统一返回 `stale` 并隐藏但保留文件与资源，重启和 Undo 后由同一 repository resolver 重新判定，所有生产消费者不得绕过该 resolver 裸读文件。

### B. Runtime 生产接线

- [x] 桌面 Runtime 注册并真实分发一个受限白板 DomainCommand 工具；明确的六类请求不再误落浏览器工具或普通文本回复。
- [x] 当前白板、角色 / conversation、runtime turn、授权和用户消息证据均由 host 提供；模型 payload 不能选择其他 board、扩大 capability、替换授权或绕过 expected hash。
- [x] Runtime adapter 严格解析六类命令 batch，只通过 `authorizeRuntimeDomainCommands` 与 `executeRuntimeDomainCommands` 进入同一 facade；不得直写 repository、snapshot 或 adapter。
- [x] 未打开白板、白板已切换、参数畸形、越权、hash 冲突、保存失败和 Runtime 中断均诚实 fail closed，白板与 action projection 零部分残留。
- [x] 同一授权 / turn / batch 重试保持幂等，不重复建卡或重复摆放。
- [x] Runtime host 生成的 Card / BoardItem ID 必须满足文件系统安全契约；已经落库的精确 legacy Runtime 冒号 ID 可受控读取 / 首次 rich 保存，但任意不安全 ID 仍拒绝，且单张异常卡不能拖垮整个卡片库。
- [x] Runtime create 未显式给坐标时必须由 host 放到当前 active viewport 的可见区域；不得默认落在远离视口的 `(0,0)` 后仍宣告用户可见操作完成。

### C. Receipt、Undo 与恢复

- [x] 人工与 Runtime 成功操作都产生可查看的“白板卡片操作”持久行动记录、Receipt 和 bounded Undo；详情与实际命令 / board / hash 一致。
- [x] 完全退出应用并重开后，白板结果、DomainCommand、Receipt、行动卡 `canUndo` 与 undo token 都从持久层恢复，不依赖旧 ViewModel 或进程内 Map。
- [x] 重开后 Undo 能恢复 Card / BoardItem / body / labels / geometry；再次重开结果仍一致。
- [x] W0 授权的人工标题兼容命令与正文同 batch 提交；Receipt、重启恢复与 Undo 同时覆盖标题，Runtime 不获得新增标题 capability。
- [x] Undo 前若目标状态已改变，必须以 hash / 状态冲突拒绝且不覆盖新状态；可重试 token 不因一次冲突被静默销毁。

### D. 自动与真人 Gate

- [x] 新增正常桌面 composition 下的生产调用链测试，能够在删除 Runtime 注册、tool dispatcher 或人工 facade 调用时明确失败；测试必须从真实 UI / conversation 入口发起，不能直接调用 coordinator 方法来伪造可达，也不能只测 facade / executor 孤岛。
- [x] 覆盖正常、无白板、畸形参数、错误 board / scope、payload 扩权、幂等、保存失败、hash 冲突、应用级关闭重建与 Undo 后再次重开。
- [x] P4 专项、桌面 conversation / action card、白板 UI 相邻回归、父 Goal exact 组合回归、changed-file analyze、`verify_critical_fixes.ps1` 与 `git diff --check` 全部通过；首个返修候选的历史绿灯不得代替第八轮修复后的复跑。
- [x] 从第八轮修复后的最终干净集成 commit 串行构建唯一 Windows Debug 候选，登记 commit、exe / kernel SHA-256、Bridge / Runtime 健康状态；`30a73ce3` 与旧 `53d2dc91` 均只保留为失败证据。
- [x] 真人依次完成：人工六类操作 → Runtime 六类操作 → 确认行动卡 / Receipt → 完全退出并重开 → 执行 Undo → 再次重开确认 → 制造冲突并确认拒绝；用户已于 2026-09-05 明确确认通过。
- [x] 更新本页、父 Goal、`I_PROJECT_STATE.md`、DEVLOG、Roadmap 与 i closeout；P4 已返回父 Goal，继续 P5 / P6。

## 明确不做

- 不新增第七类 Runtime / AI 白板 capability，不做建白板、批量摆放、搜索整理、分组 / 连线扩张或 P4-T3/T4。唯一例外是 W0 为恢复既有人工双击编辑契约明确授权的 `EditCardTitleCommand`：只供 host/manual 使用，不向模型暴露，并须与正文同 batch、同 Receipt、同 Undo。
- 不恢复 AI 专用写旁路，不使用浏览器、UI Automation、剪贴板或模拟点击代替产品 DomainCommand 工具。
- 不改变 `CardContract`、`WhiteboardSnapshot`、Board / Card / Source / Anchor 身份或删除语义；确需共享契约变化时停在 W0 变更请求。
- 不做 schema migration、依赖升级、全仓格式化或 Markdown Vault / Gate 1A 权威切换；现有表不足时先报告，不在 worker 内静默扩表。
- 不在本轮新增 DB + filesystem journal，也不宣称 full rich-text authoring 已进入 P4 DomainCommand 闭环；内嵌编辑仅提供标题 + 纯文本正文，格式 / 媒体写入必须禁用或 fail closed，不能生成虚假 completed action。
- 不碰 P5 Memory V3、P6 长任务队列、W4 视频 / 字幕、移动 Companion、Codex Voice 或 i Gateway。
- 不自动写 User-truth，不读取或迁移真实私人资料，不 push、不发布。

## 工作包状态

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P4-R / 六命令生产纵切返修 | W1 历史实现 worker：Sol high 子 Agent + 手动隔离 Worktree；W0 曾追加人工标题、原编辑面、active viewport、编辑态键盘 / 滚动条与 rich evidence 窄修 | `/root/p4_reachability_worker` | `69ddf56b325b774b0b1ffbe806e03edcab4fee27` | `codex/whiteboard-w1-p4-production-reachability-r1` / `D:/memex/.worktrees/p4-production-reachability-r1` | 第十三轮已交付；Runtime 真人 Gate 暴露新缺口 | 第八轮 `b0b9f768` → `ad304823`；第九 / 十轮 `30790f31` → `3fd6a0ad`；第十一至十三轮 `f7407823` → `08b112e8` | `docs/development/whiteboard-workstreams/P4_PRODUCTION_REACHABILITY_REPAIR_HANDOFF.md` | 历史 P0/P1 已关闭，但自动测试漏掉 Runtime filesystem-safe ID、可见落点与快捷库持久 placement | 历史 Gate 只保留证据 | 人工六类通过；Runtime create 失败 | 由第十四轮同 Goal 返修补齐三条断链 |
| P4-R14 / Runtime create 与快捷库持久摆放 | 独立 Codex Task + 隔离 Worktree，Sol high；W0 显式授权最小 safe-ID / legacy 映射 / active viewport / manual-only place command 共享契约 | `01a04c96-d704-7462-95a7-8ee4495ea540` | `7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1` | `codex/whiteboard-w1-p4r-runtime-card-library` / `C:/Users/ExampleUser/.codex/worktrees/cf72/memex` | 已集成 / 已构建 / 真人失败，候选冻结 | worker `5f515512`、`4d533f2c`、`1999ebec`、`8982b9a5`、`715be434`；集成 `caecf05e..884dcd80` | 同一 P4 handoff | 两份 Terra medium 独立复核无阻断；真人暴露测试未覆盖的 selection / focus 连续性 | worker 目标 `87/87`、相邻 `35/35`、新增 `3/3`；主线 production route + facade `22/22`，critical `3/3` | Runtime create 与全局卡片库通过；快捷库新摆放出现，但 ArrowRight 无可见移动且 selection 消失 | 返回 P4-R15，修复 reload 后 selection 与画布 focus 连续性；不扩共享契约 |
| P4-R15 / manual reload 后交互连续性 | 独立 Codex Task + 隔离 Worktree，Sol high；W0 限定 W1 UI / production route 窄修 | `01a04d25-9ba3-7f21-afae-dc481ba27b14` | `884dcd801dbda5af721bbe6610c5bcd89fac9abb` | Codex Worktree / `C:/Users/ExampleUser/.codex/worktrees/3c06/memex` | 已交付 / 已独立复核 / 已集成 / 真人通过 | worker `245af967`；test-only `bf134301`；集成 `372885cb`、`a36e5236` | 同一 P4 handoff | Terra medium 初审发现 surface-switch 非空 selection 证据不足；test-only follow-up 关闭后复审 no findings，主窗逐行复核无生产阻断 | worker 核心/相邻 `38/38` + `40/40`；主窗 production route `7/7`、三文件 analyze clean、critical `3/3`、diff check PASS | 快捷库连续两次 ArrowRight 与聊天 composer → 点卡片 → Delete 均通过；选中框短暂闪烁但逻辑 selection 未丢失 | 返回 P4 Runtime 剩余五类操作；闪烁登记为非阻断视觉优化 |
| P4-R16 / 混合否定授权解析 | 独立 Codex Task + 隔离 Worktree，Sol high；W0 限定 Runtime intent / conversation production 证据窄修 | `01a04d7d-d383-79b2-a7ce-865f80761452` | `a36e523605bd16e0ae0329cb2521f8348fa3b0e5` | Codex Worktree / `C:/Users/ExampleUser/.codex/worktrees/8ad3/memex` | 已交付 / 已独立复核 / 已集成；capability 修复有效 | worker `4a15faad..daaa1e47`；集成 `2778478a..66017099` | 同一 P4 handoff | Terra medium 初审发现“不需要 / 不必”越权；follow-up 后复审无阻断，未扩标题解析或能力面 | Runtime `14/14`、coordinator `23/23`、analyze、critical、diff check PASS | 真人原句已越过 capability 层，但后续 target scope 失败；R16 结论保留 | 由 R17 补标题目标链，不回滚 R16 |
| P4-R17 / 当前白板唯一标题目标作用域 | 独立 Codex Task + 隔离 Worktree，Sol high；W0 只授权 Runtime host target resolver 窄修 | `01a04de1-94ba-7c63-b685-0e88301b9468` | `66017099e54ac6015949eb2419bf9a92e1dc7d55` | Codex Worktree / `C:/Users/ExampleUser/.codex/worktrees/8dd4/memex` | 已交付 / 已独立复核 / 已集成 / 已构建；正文与标签真人通过，移动失败后候选冻结 | worker `f026b23b`、`3228119a`、`a7a6b3da`；集成 `21ade156..1f77633a` | 同一 P4 handoff | exact unique current-board resolver、exact surface instance 与 quoted-literal / direct-target grammar 经独立复核关闭三项 P1，最终无 P0/P1；非规范语序 fail closed 为 P2 可用性边界 | Runtime `28/28` + coordinator `23/23` = `51/51`；analyze clean、critical `3/3`、diff check PASS | 标题仍为“Runtime 创建验收 R14”；正文为“R15 Runtime 正文编辑通过”；标签为小写“runtime验收”。移动 turn 180084ms 超时，零工具调用 / Receipt / 写入 | 转 R18 补授权目标 geometry 并实测 required-tool 支持 |
| P4-R18 / 相对几何与工具约束 | 独立 Codex Task + 隔离 Worktree，Sol high；W0 限定 Runtime host geometry 与 App Server wire probe | `01a05185-dbe9-7313-8e2c-d02fd40f051e` | `v3-lab@2edaf17a`；白板链与 `1f77633a` 相同 | `codex/whiteboard-w1-p4-r18` / `C:/Users/ExampleUser/.codex/worktrees/82ae/memex` | move / persistent Undo / restart 真人通过；Runtime resize 待验 | worker `9297fd1c`、`65b85ddc`、`f4ed3b75`、`c7d38601`；集成 `2b2275d4..eec22abb`；候选 `2ed4b015` | 同一 P4 handoff | 生产 turn、两次 DB 副本、Undo hydration 与 UI 状态一致 | 主线 `99/99`、静态守门、build、Undo / second restart audit PASS | move、first restart、Undo UI 均通过；second restart 保持 `undone`，按钮未恢复 | 当前只验 Runtime resize |
| P4-R19 / Runtime 相对 resize 授权与 fail-closed 路由 | 独立 Codex Task + 隔离 Worktree，Sol high；W0 限定 intent / selection guard 与直接测试 | `01a052f1-da65-7ad2-8f44-15a9ead2d80f` | `2ed4b015c3455d651e22f3918ec3058e5baa1762` | `codex/whiteboard-w1-p4-r19` / `C:/Users/ExampleUser/.codex/worktrees/7757/memex` | 已交付 / 已独立复审 / 已集成；新候选与真人 resize 待执行 | worker `37c77acd..523ec22a`；集成 `2a75a7c0..158158dc` | 同一 P4 handoff | 初审拦下 malformed exact-title 咨询劫持、trim 后 quote offset 越界与 single stale selection 空 geometry 三项阻断；follow-up 后复审无阻断 | 主线 Runtime `34/34`、coordinator `23/23`、critical `3/3`、两文件 analyze clean、diff check PASS | 未跑；自动 Gate 不替代真人 resize | 从 R19 集成基线构建唯一候选，重选 R14 卡后只验 width `+120` |
| P4-R20 / Runtime lock selection-clear 与真实 reattach 区分 | 原 R17 Task 复用隔离 Worktree，Sol high；W0 限定 surface lifecycle identity 与直接 / production route 测试 | `01a04de1-94ba-7c63-b685-0e88301b9468` | `722a646de5b0c5903e1c70fedf6a6f2138187315` | `codex/whiteboard-w1-p4r20-surface-selection-lock` / `C:/Users/ExampleUser/.codex/worktrees/8dd4/memex` | 真人通过 | worker `591caf3a + 3c6265c7`；handoff `cdf01946`；集成 `3674548b..03c2afd9`；候选 `e77045fa` | 同一 P4 handoff | 两份复审无 P0/P1；host attachment token 只放行同 attachment 的 lock 空 selection，fresh attach、非空 replacement、owner / board 变化与后续竞态继续 fail closed | 主线 Runtime + coordinator `59/59`、production route `8/8`、critical `3/3`、四文件 analyze clean、diff check PASS | resize、remove、Receipt / Undo、重启恢复与冲突拒绝 / 同 token 重试全部通过 | 返回父 Goal，进入 P5 真人 Gate |
| W0 / 审计、集成与唯一候选 | 本验收主窗 | `01a03e4a-e594-7b32-b3da-25705b8e1eb5` | R19 exact `722a646d` 的两次 `whiteboard_surface_changed` 零写现场 | `v3-lab` / `D:/memex` | 真人通过 | 第十四轮 `caecf05e` → `884dcd80`；第十五轮 `372885cb`、`a36e5236`；第十六轮 `2778478a..66017099`；第十七轮 `21ade156..1f77633a`；第十八轮 `2b2275d4..2ed4b015`；第十九轮 `2a75a7c0..722a646d`；第二十轮 `3674548b..03c2afd9`；候选 `e77045fa` | 本页 | R20 两份独立复审无 P0/P1；最终 DB / UI / Receipt 与重启结果逐项核对 | R20 integrated `59/59 + 8/8`、critical `3/3`、analyze / diff check PASS；Windows 候选已构建并指纹化 | 用户于 2026-09-05 确认最终冲突 / 恢复序列通过 | 已同步控制面与 i closeout，返回父 Goal 进入 P5 |

## 拟定拥有路径

P4-R 派发时可写的范围只包含完成这条纵切所需的以下路径及对应测试 / handoff；最终清单由派发提示词锁定：

- `lib/data/workbench_ai/`：Runtime tool 注册、host-owned scope 与 adapter；
- `lib/ui/whiteboard/`、`lib/ui/whiteboard_canvas/`：人工六命令在提交点接入同一 facade；
- `lib/ui/character/widgets/persona_chat_screen.dart`：只允许六命令意图路由与行动卡接线的窄修改；
- 对应 `test/data/workbench_ai/`、`test/data/whiteboard/domain_commands/`、`test/ui/desktop/`、`test/ui/whiteboard/` 与 `test/whiteboard_canvas/`；
- `docs/development/whiteboard-workstreams/P4_PRODUCTION_REACHABILITY_REPAIR_HANDOFF.md`。

`lib/data/whiteboard/domain_commands/`、`lib/domain/workbench_ai/permissions/`、`CardContract`、`WhiteboardSnapshot`、Drift schema、依赖与生成文件默认只读；若现有接口确实不足，P4-R 只能在 handoff 提交最小兼容提案，等待 W0 主窗裁决和显式追加拥有路径，不能自行修改。第十四轮中，W0 已显式追加授权仅限 manual-only 的“放入已有 Card”命令及 executor / manual port 必要接线；不得暴露给 Runtime，也不改变 Card / Board / Source 身份语义。

Roadmap、Goal、`I_PROJECT_STATE.md` 和 DEVLOG 也由 worker 只读。作为本次单 worker / 主窗隔离的明确收口例外：P4-R 在 handoff 中提交完整状态事实和可直接采用的 DEVLOG / 当前态摘要，并在自身任务结束前执行一次 i closeout；W0 主窗在审计、集成和真人 Gate 后统一写入这些版本化状态文档并执行集成 closeout。这样不取消白板总纲的状态交接要求，也避免 worker 与主窗同时争写控制面。

## 依赖与集成顺序

1. 本控制面先独立提交，确认 `v3-lab` 精确派发基线；主工作区现有 Voice V9.1 / Roadmap 未提交改动不得进入 P4-R Worktree。
2. 只派发一个 P4-R 长任务到隔离 Worktree。它的固定角色是“W1 六命令生产纵切实现 worker”，不是 W0；开始写代码前按白板总纲声明 W1、W0 共享契约只读、获准的窄 `workbench_ai` adapter 路径、不做事项和验证。
3. P4-R 先证明生产入口和授权模型，再接人工 UI；若需要 schema、依赖或破坏性共享契约变更，停止并返回 W0，不继续堆旁路。
4. worker 必须提交功能 commit、测试、干净工作树和 handoff；不 push。
5. W0 审计生产调用者、权限 / hash / 幂等 / rollback、共享契约与真实测试断言；失败只返回原 P4-R 任务返修。
6. 审计通过后选择性集成到 `v3-lab`，串行跑专项与父 Goal 组合 Gate，再构建唯一候选。
7. 真人 Gate 失败仍返回 P4-R；通过后关闭本小 Goal，并把父 Goal 恢复为活动，继续 P5 / P6 真人验收。

## 失败路由

| 失败 | 返回 |
|---|---|
| 人工操作仍直写 repository / adapter | P4-R 人工接线 |
| Runtime 误找浏览器、只回复文字或无法获取已打开白板 | P4-R Runtime adapter / tool registry |
| Runtime create 落在不可见 `(0,0)` 或使用不安全 Card / BoardItem ID | P4-R host-owned 可见落点 / safe-ID 与 legacy 兼容 |
| 快捷卡片库拖入只写内存，后续 move / resize 返回 `placement_not_found` | P4-R manual-only place command / 单一持久写路径 |
| 单张 legacy / 非法 ID 卡导致卡片库整体加载失败 | P4-R repository / RichTextStorage 按卡隔离与安全降级 |
| 模型可改 board / scope / capability / authorization | P4-R host-owned 授权 |
| 失败后出现半张卡、半次摆放或孤儿 action | P4-R executor / persistence rollback |
| 重开后 Receipt、`canUndo` 或 token 丢失 | P4-R persistent reader / hydration |
| Undo 覆盖后续修改或冲突后 token 消失 | P4-R hash conflict / retry |
| 需要 schema、依赖或共享身份语义变化 | 停止实现，提交 W0 变更请求并等待用户裁决 |

## 决策与授权记录

- 2026-08-28：用户在 P4 真人失败后明确要求“建一个返修小 goal”，确认创建本 Goal。
- 2026-08-28：用户随后明确说“按协议执行并派发这个返修 Goal”，授权在本页边界内创建独立任务 / Worktree、实施、主动回收、本地选择性集成、自动 Gate 与唯一候选构建；不授权 push、发布、扩大 Goal 或绕过真人 Gate。
- 2026-08-28：两次桌面独立任务装载只返回 client id（`c84a9c94-4f6e-4286-ba61-ee73f2709c1e`、`32117d39-d2d8-444b-82d0-9f6d39a4940a`），均未生成可回收的正式 task/thread；首个装载目录已失去 Git worktree 元数据，第二个任务仅含“不要工作、回复 READY”的无副作用探针。为避免继续空等或产生双写者，W0 按协议降级为同模型等级的单一 Sol high 子 Agent，并使用手动隔离 Worktree；该偏差不改变拥有路径、验收 Gate 或集成责任。
- 2026-08-28：首轮交付经独立 Sol high 只读复核判定为 4 个 P1、3 个 P2，主要涉及白板与行动记录分裂提交、人工 / Runtime 并发覆盖、咨询问句误授权与真人“宽度调整”漏授权、失败预览可被普通保存旁路、prompt 不可信字段、生产 mutation gate 不完整及 Domain commit 无界等待。W0 未集成该交付，并把同一任务退回原 worker。
- 2026-08-28：W0 依据本 Goal 已写明的 fail-closed、持久 Undo 与失败路由，追加授权 worker 窄改 Domain facade / executor、action 精确更新和同库事务接线；仍禁止 schema、依赖、Card / Board / wire identity 与其它 Goal 变更。若无 schema 条件下无法形成有界且不静默后台写的 commit 生命周期，worker 必须停回兼容提案，不能伪绿。
- 2026-08-28：二至七轮只在同一 worker / Worktree 内关闭原子事务、并发、失败预览、pending、生产 mutation gate、prompt/scope 上界、Persona 真实发送接线及中文只读问句误授权；独立复核最终明确“可集成”，没有并行产生第二套实现。
- 2026-08-29：`30a73ce3` 真人 Gate 在人工第一项即失败：空白双击后出现额外且颜色改变的编辑框，原单一连续输入面被替换为只读标题 + 正文 / 标签表单，无法输入标题；Domain receipt 后 active surface reload 又以持久 viewport 覆盖当前 viewport，造成白板跳位。W0 立即终止后续 Gate、作废该候选并返回原 worker。
- 2026-08-29：W0 追加授权最小 `EditCardTitleCommand` 与仅 manual 可用的权限映射，使标题与正文同 batch 原子提交 / Receipt / Undo；禁止向 Runtime schema 或模型授权扩大。第八轮还必须移除生产 `_DomainCardEditSurface` 替换、恢复既有 CompactCardEditor 的透明单面视觉与连续输入契约，并在 active reload 中保持当前 viewport。
- 2026-08-29：两份独立原子性复核共同否决“只让新卡走 Domain”的双写语义与本轮扩建 DB + filesystem journal，W0 采用计算型 `CardDocumentState.stale`：Domain 只原子提交 Drift canonical 纯文本和 action；rich 文件不参与提交且不得被 receipt 后旁路改写。Repository 仅在 `document.toPlainText().trim() == card.body` 时返回富文档，否则返回 null / stale、保留旧文件与 assets；Card Library、媒体预览及 compact / full editor 均必须经统一 resolver。full editor 的跨窗口富文本版本冲突留作明确 P2，不得扩大本 Goal 的完成声明。
- 2026-08-29：full rich editor 继续作为独立 repository writer，现有跨窗口 optimistic conflict 是已接受的 P2 架构债；stale 页面只改标签时不得重写旧富文档，白板内嵌编辑的格式 / 媒体变化必须 fail closed。该例外不影响 P4 canonical 纯文本闭环，也不能被描述为 full rich authoring 已完成 DomainCommand 化。
- 2026-08-29：`7fa6cbb9` 人工六类操作全部通过后，Runtime create 首项失败。W0 对真实数据库只读取证确认：Domain action 确实 completed，Card / BoardItem 已落库，但 Runtime host 生成了含冒号的 ID，placement 默认写在 `(0,0)` 而 active viewport 远离该点；全局卡片库 rich hydration 因 `unsafe card id` 失败。快捷库再次拖入只生成内存 placement，随后的多次 resize action 均以 `placement_not_found` 冲突结束。候选立即冻结，未删除或迁移真实数据。
- 2026-08-29：W0 依据既有“真人失败返回原 P4-R”授权，派发第十四轮独立任务 `01a04c96-d704-7462-95a7-8ee4495ea540`。本轮只补 deterministic safe IDs + 精确 legacy 映射、host-owned active viewport 可见落点、manual-only 持久 place command 和单卡失败隔离；不改 schema、不写真实数据、不新增 Runtime capability。
- 2026-08-29：R14 交付与两份独立复核确认实现边界成立；复核指出的 manual-only 伪造 grant 和真实 production route 组合证据缺口由 test-only 提交补齐。W0 选择性集成五笔提交到 `v3-lab@884dcd80`，没有触碰并行 Voice / i Gateway 改动或生产用户数据。
- 2026-08-30：R18 旧候选的相对 resize 指令在没有白板授权上下文和产品工具调用的情况下约 180 秒超时，数据库几何与 Card 字段保持不变。W0 按既有真人失败路由派发 R19，只允许修严格相对尺寸 intent、quote 隔离、selection / authoritative snapshot fail-closed 与直接测试；不改 timeout、schema、六命令、DomainCommand / Receipt / Undo、DB 或 UI。
- 2026-08-30：R19 首个代码提交经独立 Sol high 审查判定三个阻断：malformed exact-title 普通咨询被劫持、trim 后 quote span 可越界、single stale selection 可形成空 geometry 授权。原任务 follow-up 全部关闭后复审确认可集成；W0 选择性集成 `2a75a7c0..158158dc`，没有带入并行 BLE / Voice / Gateway 改动。
- 本 Goal 是父 Goal 的窄返修解锁项，不取代父 Goal 的 UI-T / P5 / P6 / W4 历史和完成定义。
- 选择单一端到端 worker，避免 Runtime、facade 与人工 UI 在多个写任务间形成第二套契约；不做并行实现。

## 集成记录

- 控制面创建：`v3-lab@69ddf56b325b774b0b1ffbe806e03edcab4fee27`；提交只包含本返修 Goal 及父 Goal / Roadmap / 当前态 / DEVLOG 的 P4 控制面片段，未带入主工作区 Voice V9.1 并行改动。
- P4-R 历史派发：唯一写入 worker `/root/p4_reachability_worker` 从上述基线进入 `D:/memex/.worktrees/p4-production-reachability-r1`；最终第八轮交付与回收结果见本节末两项。
- P4-R 首轮交付：实现 `0fe885f65cd667d87156fb4353fad28df35dd532`、handoff `973ff8b8e0c565ed95517f496bdac4dc02f9d96c`，worktree clean；worker 报告专项 `9/9`、P4 / conversation / action card `46/46`、白板 / Persona 相邻 `90/90`。
- W0 首轮审计：结论不通过，首轮提交不进入 `v3-lab` 或 Windows 候选；二轮继续复用 `/root/p4_reachability_worker`、原分支与原 Worktree，避免产生第二套写实现。
- P4-R 最终交付：worker HEAD `f73ab8905b7bb9a6439a6a623d4d239c60f7a571`，worktree clean；完整 14 笔提交选择性集成为 `v3-lab@c0a742b4..30a73ce3`，与主工作区并行 Voice / Roadmap 改动零路径冲突。
- W0 集成自动 Gate：Runtime `10/10`、真实 SQLite 原子 / reopen / Undo `9/9`、production route + conversation `25/25`、Persona 真实 send-path `1/1`、核心组合 `67/67`、白板 / Persona / route 相邻 `107/107`；20 个 P4 文件 analyze 零问题，Persona 两文件仅既有 19 项 warning/info且新增区域无诊断；critical fixes `3/3`、`git diff --check` 通过。
- 首个已失败候选：从 detached clean `30a73ce3625a01b75ebb6076628a24908452cade` 构建 `memex.exe`，SHA-256 `930CA88968489F75FD30B785EE7D39A935D7B7E6DDD502FA406D94D6238E252B`；`kernel_blob.bin` SHA-256 `5E6E8DF19EC7563CC48DA991E66E43225F444665A6CF8A1F1934D68BE7039FB3`。Bridge health 正常，experimental Runtime 11 项能力与 7 个模型可读；候选 PID `46168` 已启动、`127.0.0.1:1455` 返回 `200`。旧 `53d2dc91` 进程已按精确路径停止；真人第一项失败后，`30a73ce3` 也已作废。
- P4-R 第八轮最终交付：worker `b0b9f768..ad304823` 恢复 production CompactCardEditor 的单一透明连续输入面、manual-only 标题 batch、active viewport、canonical plain body / rich stale resolver、Runtime 执行侧标题防线和失败草稿可见性；两轮仅测试修复关闭 Windows rich read teardown 竞争与 Card Library 真实文件 I/O 的 fake-clock 等待。W0 选择性集成为 `v3-lab@4c621771..94eb8a9e`，无冲突且未触碰主工作区并行改动。
- W0 第八轮自动 Gate：核心组合 `73/73`；白板 / Persona / route 相邻首跑在 Windows teardown 出现一次瞬时红点，随后 exact `1/1`、缩小组合 `29/29`、完整复跑 `107/107` 均通过；Repository `39/39`、full editor `5/5`、Card Library `13/13`、compact editor `4/4`。22 个改动 Dart 文件 analyze 零问题，critical fixes `3/3`、`git diff --check` 通过。首次扩展 Card Library 全文件暴露旧 fake-clock 等待不再能推进真实 rich I/O，已以有界真实时钟测试助手修复，未修改产品代码或吞超时。
- 新唯一候选：控制面经独立只读复核后提交为 `v3-lab@779499716448ecf1557cbc53b9348fbb3697c6f0`，从 detached clean `D:/memex/.worktrees/p4-final-candidate-77949971` 串行构建 Windows Debug（853.0s）。`memex.exe` SHA-256 `830D10BB1485A496FC0476E52E17412FD49B08859669A0AA96E16CB797A5EB33`；`kernel_blob.bin` SHA-256 `EA4C172D11C9B46D465ECBA8F00E9BB0683B1008BF883355B271E77F9D74A10F`。构建生成文件仅有行尾噪声，恢复后 Worktree clean；Bridge `/v1/health` 为 ok，experimental Runtime header 正确、11 项能力与 7 个模型可读。旧失败候选 PID `46168` 已按精确路径停止；新候选 PID `55856` 运行且窗口可见，`127.0.0.1:1455` 由该 PID 监听并返回 `200`。
- 第九轮触发：`77949971` 人工第 1–2 项通过后，用户打开白板直接新建卡片的 full editor，顶部错误提示“富文本文件缺失，当前已用数据库正文投影恢复”。代码与独立审计确认 CreateCard / inline Domain 只应写 Drift canonical plain body、首次 rich save 前没有 `rich_text.json` 是正常状态；正文、标题、标签、首次保存与 Undo 未见损坏。现有模型没有持久 materialization provenance，故拒绝用目录是否存在静默区分（整目录真实丢失会产生假阴性），第九轮只做 no-schema 中性状态文案与真实 production 路径测试。
- 第九 / 十轮交付与集成：worker 先以 `30790f31..0a86be8a` 把 missing 改为中性事实，并覆盖真实 desktop mouse 双击→inline Domain 保存→右键展开 full editor、首次正文 rich 保存与 tag-only 零物化。独立复核又发现空正文 media-only 卡在整目录丢失时会被旧 `body.isEmpty` 门控静默，遂以 `3badd36f..3fd6a0ad` 让所有 missing 一律提示，并明确“编辑正文并保存后”；共享 object 在整目录删除前后均保留。两轮最终无新增 P1/P2，W0 精确集成为 `b4a8da87..526db238`。主线 full editor / production route / restart Undo 组合 `25/25`，直接 Dart analyze 三项零问题，critical `3/3`、diff-check 通过；Flutter analyze wrapper 的 60 秒启动挂起未冒充通过。
- 第十轮唯一候选：从 exact `526db23840d68df99beec09b055cc61c653ebcd4` 建 detached clean `D:/memex/.worktrees/p4-final-candidate-526db238`，关键守门 `3/3` 后串行构建 Windows Debug（258.3s）。`memex.exe` SHA-256 `01ECAE79DC31BCDBC12D8534F168E999C331634CEB279A01066B6DB1BA34DD16`；`kernel_blob.bin` SHA-256 `E902EFE1F367F99EA16709A86653F653BCD2223CD15B8B8334D512F449B2141F`。构建器只产生三个已确认的生成文件行尾噪声，精确恢复后 Worktree clean；Bridge health 为 ok，experimental header 正确、11 项能力与 7 个模型可读。旧候选 PID `55856` 已按精确路径停止；新 PID `9956` 运行，`127.0.0.1:1455` 由其监听并返回 `200`。
- 第十一轮触发：`526db238` 真人第 1 项确认三个回归。其一，内嵌编辑右侧出现原本没有的滚动条；其二，编辑态 Delete / Backspace 被外层 `CallbackShortcuts` 抢占并直接移除 BoardItem，违反“编辑态删字、退出编辑并选中后才移除摆放”；其三，正常新建 canonical plain Card 回卡片库全屏编辑时仍显示 rich 物化通知，用户明确通知本身不应出现。W0 停止后续 Gate、作废候选并返回 P4-R；corrupt / stale 仍须可见，不用目录 heuristic 掩盖异常。
- 第十一至十三轮交付与集成：编辑态 `_buildShortcuts` 只保留 Escape，文字删除 / 选择 / 导航 / Undo 交由输入框；内嵌编辑用不可被后代重新开启的 delegating `ScrollBehavior` 仅抑制 scrollbar 绘制。rich 生命周期证据进入既有 `kv_store`，按 bucket / schema version / cardId / createdAt incarnation fail closed；`saveRichText` 的正文投影与 evidence 同 Drift transaction，正常 plain missing 静默，evidenced missing 才提示，corrupt / stale 不变。worker `f7407823..08b112e8` 经两轮独立复审后集成为 `a8ef84d9..7fa6cbb9`；不改 schema、Card presentation、Snapshot / Undo 或 AI Runtime。
- 第十三轮主窗 Gate：集成前后各自复跑，最终 `v3-lab` 上 compact `5/5`、真实 production mouse / keyboard `1/1`、rich repository screen `9/9`、统一 Repository `41/41`、restart / Undo `1/1`，critical fixes `3/3`、diff-check 通过。返回白板的选择测试先等待 route settle、主动清空旧 selection，再点击真实 Card GestureDetector 主体中心，排除旧 selection 假绿。
- 第十三轮唯一候选：从 exact `7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1` 建 detached clean `D:/memex/.worktrees/p4-final-candidate-7fa6cbb9`，关键守门 `3/3` 后串行构建 Windows Debug（238.1s）。`memex.exe` SHA-256 `94F08DB2464220BE436844A1B31A68D4EE7A6AEBBFF02435FD9EBA70A04E2787`；`kernel_blob.bin` SHA-256 `16C63D627CD161A32771143FB7C4BA0837A0C848FF1DA2C4B1C4BA4552475D81`。三个 generated plugin 文件仅有归一化行尾噪声，精确恢复后 Worktree clean；旧 PID `9956` 已按路径优雅关闭，新 PID `34688` 窗口可见、响应正常并独占 1455，App 返回 `200`，Bridge health `ok`，experimental header 正确、11 项能力与 7 个模型可读。
- 明确保留债务：full-rich 双写者或 rich 与 linkSource / softDelete / restore 并发仍可能诚实落 stale；Memory V3 物理删除可能遗留 orphan KV / rich 文件；当前完整备份不包含 whiteboard rich root。三项均不阻断本轮两项真人回归，但不得宣称已经解决。
- 第十三轮真人第 1 项通过：空白双击新建后的编辑面无右侧滚动条；编辑态 Backspace / Delete 只删除文字，不移除 BoardItem；按 Escape 退出后单击选中，再按 Delete 才从白板移除摆放。该结论只属于 `7fa6cbb9` 候选；下一项验证同一 Card 回卡片库进入 full editor 时不显示正常 plain missing 的 rich 内部通知。
- 第十三轮真人第 2 项通过：刚才创建、随后只从白板移除摆放的同一 Card 在卡片库仍可找到；进入 full editor 后正文正常显示，顶部不出现“富文本文件缺失”或“当前没有可用富文本版本”等内部通知。本轮两条用户反馈均完成真人闭环，继续 P4 人工六命令的 labels / move / resize。
- 第十三轮真人第 3 项通过：回到白板新建并保存卡片后，通过右键添加 `p4验收` 标签成功；标签可见，卡片内容 / 外形无异常，白板 viewport 不跳动。下一项单独验证人工 move。
- 第十三轮真人第 4 项通过：选中带 `p4验收` 标签的卡片并拖到明显不同位置后，卡片稳定停在新位置；内容、标签与尺寸保持不变，白板 viewport 不跳动。下一项单独验证人工 resize。
- 第十三轮真人第 5 项通过：拖动右下角缩放手柄后卡片尺寸明确改变；内容与 `p4验收` 标签保留，卡片位置及白板 viewport 无异常跳动。结合第 1 项已经覆盖 create / edit / remove，人工 create / edit / labels / move / resize / remove 六类操作全部通过；下一阶段进入 Runtime 六命令。
- 第十三轮 Runtime create 首项失败：对话行动记录显示 completed，但新 Card / BoardItem 实际以 `card:<seed>:0` / `item:<seed>:0` 和 `(0,0)` 落库，远离 active viewport，白板上不可见。全局卡片库读取富文本时拒绝冒号 ID；快捷库拖入的临时 placement 未落盘，后续 move / resize 连续产生 `placement_not_found`。`7fa6cbb9` 候选冻结，后续 Runtime / Receipt / restart / Undo / conflict Gate 全部停止。
- 第十四轮派发：独立任务 `01a04c96-d704-7462-95a7-8ee4495ea540` 从 exact `7fa6cbb9` 隔离实施；完成、审计、统一回归与新候选构建前，不恢复真人验收。
- 第十四轮交付与集成：Runtime 新建 ID 改为确定性的 `card_<24hex>_<index>` / `item_<24hex>_<index>`，未给坐标时按 host 捕获的 active viewport 与实际尺寸居中；精确 legacy `card:<24hex>:<index>` 只映射到隔离安全目录，其它不安全 ID 继续拒绝且 repository 只隔离该类单卡错误。快捷卡片库 click / drag 改走 manual-only `PlaceExistingCardCommand`，由 facade / Drift / Receipt / reload 呈现，Runtime schema 与六项 capability 不扩张。worker 五笔提交选择性集成为 `v3-lab@caecf05e..884dcd80`；目标 `87/87`、相邻 `35/35`、新增三条证据 `3/3`，主线 facade + production route `22/22`、critical `3/3`，两份独立复核无阻断。
- 第十四轮唯一候选：从 exact `884dcd801dbda5af721bbe6610c5bcd89fac9abb` 建 detached clean `D:/memex/.worktrees/p4-final-candidate-884dcd80`。本机 Pub cache 只补建缺失的 `active_roots/78` 空目录后依赖登记成功；关键守门 `3/3`，Windows Debug 构建成功（224.1s）。`memex.exe` SHA-256 `435D265CB1BBBF66241F9C1D9BD358A2C073C9178C4181DA9B1CFC7A690A517F`；`kernel_blob.bin` SHA-256 `B51DC962903D12DECDB67893FD45F9D67A18443C330EA3353F76F587A16627F1`。三个 generated plugin 文件仅有换行噪声并已精确恢复，Worktree clean。旧 PID `34688` 按精确路径停止；新 PID `45904` 运行并监听 `127.0.0.1:1455`，App 返回 `200`，Bridge health `ok`，experimental header 正确、11 项能力与 7 个模型可读。
- 第十四轮真人第 1 项通过：用户要求 Runtime 创建标题“Runtime 创建验收 R14”的卡片后，卡片立即出现在当前 active viewport，关闭了此前“completed 但落在不可见 `(0,0)`”的失败。
- 同步登记两个新观察：其一，从已聚焦聊天输入发起 Runtime 后，单击卡片虽更新 selection，却没有显式把焦点交回白板 `CallbackShortcuts`，因此 Delete 未产生 remove action；这不推翻 create 通过，但须在 P4 关闭前补真实聊天 → 卡片 → Delete 交叉焦点 Gate。其二，人工 DomainCommand 与 Runtime 共用 facade 时，每次都把持久 action projection 写成关系主对话行动卡，导致“白板卡片操作已完成，可撤销”不断刷入对话；Receipt / Undo 必须保留，但上位契约只要求主对话呈现任务发起、关键决定和结果摘要，因此该展示归为非阻断体验债，后续应把人工 action 路由到白板操作历史 / Undo 面，而不是删除审计。
- 第十四轮真人第 2 项通过：从桌面侧栏进入独立全局卡片库可正常加载，没有再出现 `Unsafe card ID` 或全库加载失败；搜索可找到“Runtime 创建验收 R14”。这同时覆盖 legacy unsafe Card 的单卡隔离与 R14 safe-ID 新卡的全局可发现性。
- 第十四轮真人第 3 项失败：从白板左上角快捷卡片库单击“Runtime 创建验收 R14”后，新 BoardItem 出现；紧接着按 ArrowRight 没有可确认的右移，selection 反而消失。候选立即冻结，未继续 drag / restart / Undo。只读审计确认 manual host 每次提交都会 lock + reload，而 `loadFromSnapshot` 无条件清空 selection；move 成功后没有恢复 selection，快捷库 / 聊天切回画布也缺少真实鼠标焦点断言。当前仅凭现场不能断言 move Receipt 是否落盘，但用户可见交互连续性 Gate 已明确失败。
- 第十五轮派发：独立任务 `01a04d25-9ba3-7f21-afae-dc481ba27b14` 从 exact `884dcd80` 创建隔离 Worktree `C:/Users/ExampleUser/.codex/worktrees/3c06/memex`，只修 surviving selection 与画布 focus continuity，并补快捷库连续 nudge、聊天 → 卡片 Delete、失败 / route switch 的 production 证据；不改共享领域契约、schema、Runtime capability 或行动卡呈现路由。
- 第十五轮交付与集成：route manual port 在 lock/reload 前捕获 selection，只有 applied Receipt、当前 surface/board 仍匹配、未进入 reconciliation-required 且 reload 后 BoardItem 仍存在时才恢复；画布显式拥有 FocusNode，并在真实鼠标选择及成功 placement / move / resize 后安全收回焦点，编辑态文本键仍归输入框。worker `245af967` 后，独立审计指出原 surface-switch 测试未从非空 selection 开始；test-only `bf134301` 在真实 route → Host → Facade/Drift save gate 内关闭缺口，复审 no findings。W0 选择性集成为 `v3-lab@372885cb..a36e5236`；主窗 production route `7/7`、三文件 analyze clean、critical `3/3`、diff check PASS。
- 第十五轮唯一候选：从 exact `a36e523605bd16e0ae0329cb2521f8348fa3b0e5` 建 detached clean `D:/memex/.worktrees/p4-final-candidate-a36e5236`。Pub Cache 的 C 盘入口是指向 `D:/C_Moved/pub_cache` 的 junction；从真实目标补建缺失 `active_roots/35` 后依赖登记成功。构建前 critical `3/3`，Windows Debug 构建成功（327.1s）。`memex.exe` SHA-256 `91A0E18EA9AE372577307BAF6D2867D7344D22EE4EFC7A6CC50A6C70C363156E`；`kernel_blob.bin` SHA-256 `D96FA04273682A17A8238605D77912B08D0695D66667DA361EF80B94DFB5A9A6`。三个 generated plugin 文件仅有换行噪声并已精确恢复，Worktree clean。旧 PID `45904` 经精确路径核对后停止；新 PID `22276` 运行，`1455` 返回 `200`，Bridge health `ok`，experimental header 正确、11 项能力与 7 个模型可读。
- 第十六轮交付与集成：Runtime 授权解析先剥离引号内容，再按局部子句提取正向能力并减去否定能力。worker 首轮 `4a15faad..e5d22ad0` 经 Terra medium 独立复核发现“不需要 / 不必”仍可能越权；follow-up `2ad8c134..daaa1e47` 补齐“不想 / 不希望”与中英文逗号边界后复审无阻断。W0 选择性集成为 `v3-lab@2778478a..66017099`；主窗确认未扩 tool schema、标题解析、六类 capability、Card / Board / Receipt / Undo 或数据库 schema。Runtime `14/14`、coordinator `23/23`、目标 analyze clean、critical `3/3`、diff check PASS。
- 第十六轮唯一候选：从 exact `66017099e54ac6015949eb2419bf9a92e1dc7d55` 建 detached clean `D:/memex/.worktrees/p4-r16-candidate-66017099`。Pub Cache junction 的真实目标只补建缺失空目录 `active_roots/f4` 后，离线依赖登记成功；Windows Debug 构建成功（223.3s）。`memex.exe` SHA-256 `22FE4911FDA7DAD2B6B4FDBA97FC5B8B9E2A8D19855812A3A9A9F15270F5A6BF`；`kernel_blob.bin` SHA-256 `52132BCF1DA3AC5BC091B483EACFE9B1C35C8BD686CC692A7BF59BE26DBD1FC8`。生成文件只出现可核对的行尾噪声并已精确恢复，Worktree clean。旧 PID `22276` 经精确路径核对后停止；新 PID `56408` 运行且响应，App `1455` 返回 `200`，Bridge health `ok`，experimental header 正确、11 项能力与 7 个模型可读。

## 真人验收

- 最终唯一候选：exact `e77045fafebdc6d19f7a00ae4b2eb98e452fd5f8`，detached clean Worktree `D:/memex/.worktrees/p4-r20-candidate-e77045fa`；`memex.exe` SHA-256 `BE3BE7A7037327C735883998C430D02C6CC9373504202D773B76AFFFE0C11CB9`，`kernel_blob.bin` SHA-256 `0CCDAE9E95572A9A37B1AF21BA634D653BBBBE85DB680342B644E7387A1367C2`。验收时 App / Bridge / Runtime 健康，Bridge 显式使用当时模型目录可用的 `gpt-5.6-sol`。
- 上一唯一候选：exact `1f77633a7f4d17d0601bee76a5c641966c9149b5`。正文与标签真实通过后的事实为：标题“Runtime 创建验收 R14”、正文“R15 Runtime 正文编辑通过”、标签小写“runtime验收”；随后移动 Gate 在首次白板工具调用前超时且零写，候选已冻结，只保留失败证据。
- 第十五轮真人第 1 项：通过。快捷库单击 R14 卡后新 BoardItem 出现，连续两次 ArrowRight 均向右移动，逻辑 selection 全程保留。每次移动提交期间选中框会短暂闪一下，随后恢复；用户确认并未解除选中，登记为非阻断视觉抖动，不冻结当前候选。
- 第十五轮真人第 2 项：通过。聊天输入框先取得光标后，单击新摆放卡片再按 Delete，目标 BoardItem 正确从白板消失；跨焦点删除 Gate 闭环。
- Runtime 正文编辑真人 Gate：失败。用户明确只改 R14 卡正文，并限定不改标题、标签、位置或大小；产品返回 `unsupported_product_tool`，只读核对显示正文仍为旧值且其余字段未改。运行时输入没有注入白板 capability block；源码与两份独立审计确认，尾句局部否定触发 `_containsNegatedWhiteboardWrite` 全句短路，使授权为 null，标准工具调用在 conversation dispatcher 被拒，未进入 adapter / facade / Drift。
- 第十六轮返修：Sol high 独立任务 `01a04d7d-d383-79b2-a7ce-865f80761452` 从 exact `a36e5236` 隔离完成 capability 级授权解析与 exact 真人原句回归；两轮交付和 Terra medium 独立复核闭环后集成为 `2778478a..66017099`，未新增标题解析、tool schema、Runtime capability 或共享领域契约。自动 Gate 通过不代替当前真人重测。
- 第十六轮真人重测：失败。标准正文写工具已被调用，但返回 `whiteboard_target_outside_scope`；只读核对确认正文仍为旧值，标题、标签、位置和大小均未改。该轮真实 host context 的 `selected_item_ids` / `selected_card_ids` 均为空；R16 exact 测试固定预选 `item_a` 且 fake Runtime 硬编码 `card_a`，没有覆盖原句中的当前白板标题目标。
- 第十七轮派发：Sol high 独立任务 `01a04de1-94ba-7c63-b685-0e88301b9468` 从 exact `66017099` 创建 Worktree `C:/Users/ExampleUser/.codex/worktrees/8dd4/memex`；只补 host-owned、current-board-only、精确唯一标题→稳定 target scope 与完整零写拒绝矩阵，不开放整板、全局库或模糊匹配，不改六命令 schema / 共享领域契约。
- 第十七轮交付与集成：current-board-only resolver 只接受直接目标句中的精确唯一标题；正文引号 literal 保持不透明，0 / 多义 / 跨板 / 仅库卡全部拒绝；同 Card 多 placement 时 Card 级写允许、placement 写因 item 多义拒绝。授权绑定 exact surface instance，flush / invoke / durable 前的同 board 重挂或切换均零写失败。worker `f026b23b..a7a6b3da` 经独立复核先后关闭同 owner / board reattach、literal scope hijack 与过宽语法三项 P1，最终 no P0/P1。W0 选择性集成为 `v3-lab@21ade156..1f77633a`；Runtime `28/28` + coordinator `23/23` = `51/51`，目标 analyze clean、critical `3/3`、diff check PASS。
- 第十七轮唯一候选：从 exact `1f77633a7f4d17d0601bee76a5c641966c9149b5` 建 detached `D:/memex/.worktrees/p4-r17-candidate-1f77633a`。Pub Cache 真实目标只补建缺失空目录 `active_roots/b4` 后离线依赖登记成功，`pubspec.lock` 未变；Windows Debug 构建成功（210.3s）。`memex.exe` SHA-256 `32B0CFF7837E1ED93454A3EFF1E3E069C79168E7B72EAE3813DF8EC7ABE155B5`；`kernel_blob.bin` SHA-256 `5763C7717C3BB2B6970CCE54A40A8E1BD15F4922E725E400A451DB06BA094C3D`。三个 generated plugin 文件只有无内容 diff 的行尾 / stat 噪声。旧 PID `56408` 已按精确路径停止；新 PID `52368` 运行，App `1455`、Bridge health 与 experimental Runtime 11 项能力 / 7 个模型均健康。
- 第十七轮真人重测：正文与标签均通过。Runtime 把正文改为“R15 Runtime 正文编辑通过”，标题“Runtime 创建验收 R14”、原标签、位置和大小保持不变；随后仍按该标题把标签设为小写“runtime验收”。前三次标签环境失败都在白板工具调用前结束，不计产品失败。R17 current-board exact-title scope 与 R16 单能力授权已覆盖两类命令。
- 第十八轮触发：随后请求把当前白板标题为“Runtime 创建验收 R14”的卡片右移 120 像素。host 已解析唯一 Card / BoardItem 并授权 `move_placement`，但授权 prompt 没有当前 `x/y`，而 schema 只接受绝对坐标；模型反复走内部 `exec/search`，从未调用 `whiteboard_domain_commands`。生产 turn `01a05107-88e4-7160-b57c-3c5903296cb7` 在 `180084ms` 被 `runtime_timeout` 中断，零 payload、host result、Receipt 和持久写入，移动 Gate 明确失败。
- 第十八轮派发：Sol high 独立任务 `01a05185-dbe9-7313-8e2c-d02fd40f051e` 从已提交 `v3-lab@2edaf17a` 创建分支 `codex/whiteboard-w1-p4-r18` 与 Worktree `C:/Users/ExampleUser/.codex/worktrees/82ae/memex`；只补 host-bounded target placement geometry，并真实 feature-probe 当前 App Server 的 per-turn required / allow-only dynamic tool 字段。若不支持则停在兼容提案，不猜字段、不做伪实现；不延长三分钟 timeout，不改六命令、Card / BoardItem / DomainCommand / Receipt / Undo 或数据库。
- 第十八轮交付与集成：R18 从同一 authoritative snapshot 暴露 exact target placement 的 `item_id/x/y/width/height`，只在已授权 move / resize 时出现；geometry 不参与 scope，0 / 多义 / forged target 继续零写拒绝。领域与 Runtime 共用坐标 ±1,000,000、宽 `80..3000`、高 `60..3000` 的几何策略，非法值在 request hash / Facade / action 前拒绝。首轮独立复核发现极端 finite 坐标与非法尺寸时序两项 P1，follow-up `f4ed3b75` 关闭后终审无 P0/P1/P2。真实 App Server schema 证明当前版本没有 per-turn required / allow-only tool 字段，因此 Bridge / Runtime client 零伪接线。worker `9297fd1c..c7d38601` 集成为 `v3-lab@2b2275d4..eec22abb`；主线自动 Gate `99/99`、四文件 analyze clean、critical `3/3`、diff check PASS。
- 第十八轮唯一候选：从 exact `2ed4b015c3455d651e22f3918ec3058e5baa1762` 创建 detached Worktree `D:/memex/.worktrees/p4-r18-candidate-2ed4b015`；Pub cache 改用其真实 `D:/C_Moved/pub_cache` 路径离线登记，`pubspec.lock` 未变。构建前 critical `3/3`，Windows Debug 构建成功（228.3s）；exe `33F10A94…2B017`、kernel `C5BF7E43…21BB0`，生成文件仅换行 / stat 噪声并经索引刷新后 Worktree clean。旧 App / Bridge 已按精确路径停止；新 App PID `37380`、Bridge PID `32764`，App / Bridge、experimental Runtime 11 项能力 / 7 个模型与 ChatGPT auth 健康。
- 第十八轮 move / persistent Undo / restart 真人通过。Lynx 最终确认行动卡显示“已撤销”且按钮消失；DB 审计证明 x 恢复原值、其它字段未变、再次重启仍 `undone` 且不可重复。无 busy / Toast 的即时反馈记为非阻断债；当前只验 Runtime resize。
- 第十九轮触发：用户输入“把选中卡片卡片宽度增加 120 像素”，产品返回“电脑回复等待超时”。provider thread `01a052e3-3080-7f41-ac8b-4eff3c4c77d4` / turn `01a052e3-323c-7663-ad13-8ba0035b6533` 实际为 `gpt-5.6-sol / ultra`；host 归一化为“当前选中卡片宽度增加 120 像素”，却没有生成 `untrusted_whiteboard_context`、selection / geometry 或 capability grant，约 180 秒本地探索后中止，零 `whiteboard_domain_commands`、action、Receipt 与晚到写入。DB 仍为 x `1039.862130884688`、y `1045.1693417620572`、width `887.5555555555558`、height `740.4444444444441`。
- 第十九轮交付、审查与集成：R19 用共享窄 grammar 接受“宽度 / 高度 / 尺寸 / 大小 + 增加 / 减少 + 明确阿拉伯数字”，并在 selection-bound relative resize 中要求表面与 authoritative snapshot 都恰好一个存活 item；quoted literal、普通咨询、否定、显式标题与 stale selection 均 fail closed。初审三项阻断经 `16aab238` follow-up 关闭，最终复审无阻断。worker `37c77acd..523ec22a` 选择性集成为 `v3-lab@2a75a7c0..158158dc`；主线 Runtime `34/34`、coordinator `23/23`、critical `3/3`、两文件 analyze clean、diff check PASS。未构建 / 安装 / 运行新候选，真人 resize Gate 尚未开始。
- 第十九轮唯一候选与真人失败：从 exact `722a646d` 构建 Windows Debug，exe SHA-256 `63ABD9F0528163CA371EA7393A3F19A470B299398F8A0128259DD82233AA3717`、kernel `D4A71497A4BFC6F6DDA26A1F67B0F6D5E8BF36B0CA8318EFA5D1E70876BD820B`；App / Bridge / Runtime 健康。真人连续两次在明确单选后请求宽度 `+120`，均返回 `whiteboard_surface_changed`；零 action、零 Receipt、零持久写，宽度保持 `887.5555555555558`。第二次仍运行该旧候选，不登记为 R20 失败。
- 第二十轮交付、审查与集成：根因是 production route 进入 readonly 时同步清空 selection 并发布同 attachment 新 snapshot，旧实例 gate 将其误判为真实重挂。R20 新增 host-owned attachment token：每次 attach 更新，selection-only snapshot 保留；lock 后仅放行同 token 的空 selection，fresh attach、非空 replacement、owner / board 变化与后续竞态继续 fail closed。两份独立复审无 P0/P1；worker `591caf3a + 3c6265c7` 与 handoff `cdf01946` 选择性集成为 `v3-lab@3674548b..03c2afd9`。主线 Runtime + coordinator `59/59`、真实 production route `8/8`、critical `3/3`、四文件 analyze 与 diff check 通过；随后从包含该集成的 exact `e77045fa` 构建并启动唯一候选。
- 第二十轮 Runtime resize / Undo 真人通过：目标卡宽度从 `887.5555555555558` 增加 `120`，其余 geometry 与 Card 字段未改；完整重启后 DB 仍保留新宽度。执行持久 Undo 后宽度精确恢复，行动卡显示“已撤销”且按钮消失；用户与只读 DB 复核一致。
- 第二十轮 remove / conflict / retry / restart 真人通过：Runtime remove 只移除目标 `BoardItem`，Card 本体仍可在卡片库找到；随后移动另一张控制卡，先点旧 remove Undo 被 `snapshot_changed_after_batch` 拒绝，目标仍缺席、控制卡保持新位置且旧 token 未销毁。撤销控制卡移动后，以同一旧 token 重试成功，目标卡按原位置 / 尺寸恢复；完整退出重开后两张卡 geometry、Card 标题 / 正文 / 标签与两笔 `undone` 状态稳定。用户于 2026-09-05 明确确认通过。
- 最新失败候选：`884dcd801dbda5af721bbe6610c5bcd89fac9abb`；exe `435D265C...A517F`、kernel `B51DC962...627F1`，旧 PID `45904` 已按精确路径停止；其 App / Bridge / experimental Runtime 当时健康但真人快捷库交互 Gate 失败，只保留失败证据。
- 第十四轮真人第 1 项：通过；Runtime 新卡立即出现在当前视口。
- 第十四轮真人第 2 项：通过；全局卡片库正常打开，无 unsafe-ID 加载失败，并能检索到“Runtime 创建验收 R14”。下一项验证白板内快捷卡片库的摆放确实持久落盘。
- 第十四轮真人第 3 项：失败；快捷库新摆放出现，但 ArrowRight 无可确认移动且 selection 消失。停止本候选后续 Gate，返回 R15 返修 selection / focus continuity。
- 最新失败候选：`7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1`；exe `94F08DB2...A04E2787`、kernel `16C63D62...2475D81`，旧 PID `34688` 已按精确路径停止，只保留失败证据。`526db238` 及 PID `9956` 只保留更早失败证据。
- 场景：人工六命令、Runtime 六命令、行动卡 / Receipt、应用完全退出重开、Undo、再次重开、冲突拒绝。
- 结果：`7fa6cbb9` 人工六类、`884dcd80` Runtime create / 全局卡片库、`a36e5236` R15 两项、`1f77633a` 精确标题正文 / 标签编辑、`2ed4b015` move / persistent Undo / restart，以及 `e77045fa` resize / remove / conflict / retry / restart 均有真人观察与持久层证据；P4 六命令生产纵切真人通过。
- 未完事项：P5 / P6 返回父 Goal 继续真人 Gate；W4 维持 `0/18` 非阻断红灯。当前 Codex 环境曾把默认模型解析到不兼容的 `gpt-6-astra`，本次验收按 Bridge 已支持的显式模型选择恢复；正式 per-turn required / allow-only tool wire 仍等待上游 schema/capability，均作为后续 Bridge 兼容项保留，不反向否定 P4 已通过的六命令闭环。

## Goal 结论

- 完成时间：2026-09-05。
- 最终基线：`v3-lab` 包含 `03c2afd913a69e294a5395179a3e779d502d4b48`；真人候选 exact `e77045fafebdc6d19f7a00ae4b2eb98e452fd5f8`。
- 最终候选：exe `BE3BE7A7037327C735883998C430D02C6CC9373504202D773B76AFFFE0C11CB9`；kernel `0CCDAE9E95572A9A37B1AF21BA634D653BBBBE85DB680342B644E7387A1367C2`。
- push：未授权。
- 返回目标：[`GOAL-20260824-ai-workbench-wave1`](GOAL-20260824-ai-workbench-wave1.md) 的 P5 / P6 真人 Gate。

## 2026-09-07 目标追踪完成复核

自动续跑仍指向本已完成的小 Goal；主控读取目标工具确认仍为 paused。本次只读复核原目标，不以父 Goal 的 P6 工作扩张本小 Goal，不重做已通过的真人操作。

| 原目标要求 | 本次复核的证据 |
|---|---|
| 干净控制面、隔离 W1 与可追溯交付 | 本页进入条件/工作包、W1 与 R20 handoff；Git 验证 `69ddf56b` 是候选与当前主线祖先，历史 clean 起点由当时交接佐证 |
| 主动回收、独立审计、本地集成 | 两份 R20 独立审计与 `3674548b..03c2afd9`；Git 验证 `03c2afd9` 进入 `e77045fa`，后者进入当前 `4ba05b11` |
| 自动 Gate 与唯一候选 | 本页 R20 `59/59`、production route `8/8`、critical `3/3`、analyze/diff 记录；本次重新读取候选 HEAD，Worktree 当前 clean；exe/kernel SHA-256 与上节两项完整指纹完全一致 |
| 真人退出重开、Undo、冲突拒绝/可重试 | 本页 9 月 5 日 resize/remove/conflict/retry/restart 具体记录和 DEVLOG；包含宽度持久恢复、Card 保留、冲突零覆盖、同 token 重试及再次重启后的稳定状态 |
| 范围和外部动作限制 | 本次未操作真实 App/DB、未构建/安装、未 push/发布；P6 的单独授权与证据仍留在父 Goal，不替代本 Goal 验收 |

主控与只读 Terra 审计均未发现原目标未完成项；目标工具现已更新为 `complete`。这是把目标追踪与 9 月 5 日既有完成事实对齐，不新增真人通过或发布声明。
