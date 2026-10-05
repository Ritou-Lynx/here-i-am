# Here I Am Product Roadmap

> 状态：当前权威产品与执行路线
>
> 最后更新：2026-10-01
>
> 执行基线：`v3-lab`

> 2026-10-02 白板工作台暂停：用户因整体计划调整暂停桌面白板工作台开发。收尾事实、未完项与接续步骤以 [工作台暂停收尾](../development/whiteboard-workstreams/WORKBENCH_PAUSE_20261002.md) 为准；下方各条为历史快照。

> 2026-10-01 暂停落点：Goal 1 本地验收已完成，源码已在主 worktree `v3-lab`，受控清单 104/104 同哈希；用户要求暂停后续工作。生产启用评估与减弹窗改造尚未开始，生产继续默认关闭。见 [暂停交接](../development/whiteboard-workstreams/GOAL1_MAIN_WORKTREE_PAUSE_20261001.md)。

> 2026-10-01 最终本地验收：Goal 1 的 UI-T、P4、限定 P5 与 P6 已按 [最终本地验收](../development/whiteboard-workstreams/GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md) 收口。最终组合候选的受控源码 104/104 同哈希；既有 UI-T/P4/P5 真人 Gate 按受影响范围复核后保留，P6 同一隔离普通入口完成任务生命周期与清理 Gate。生产长任务执行仍默认关闭，commit/push/发布均未执行。以下历史进展按各自日期阅读。
>
> 2026-10-01 当前进展：Goal 1 的同一隔离普通 Windows 组合候选已补齐 P6 受控本地终态交付故障后唯一 retry→completed 的实际 Gate；任务 `b2b1680e…223f6` 最终 1–2000 逐行精确、两次原生六项清理与普通关窗均通过。该候选源码清单 104/104 当前哈希一致，普通入口 P6 隔离生命周期证据已齐。UI-T、P4 和限定 P5 的既有真人结果保留；父 Goal 仍需判断受新接线影响的跨包真人复核及最终收口，生产默认拒绝、无 commit/push/发布。见 [组合接线记录](../development/whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。下方旧进度均按当时快照阅读。
>
> 2026-09-30 当前进展：P6 同一 App 哈希的隔离真人入口已验普通短聊零任务、队列全生命周期、预设失败后唯一重试完成、精确结果、取消态/完成态重启，以及运行中异常退出后诚实中断、显式恢复与完整清理；见 [run11](../development/whiteboard-workstreams/P6_R7_RUN11_20260929.md)、[run13](../development/whiteboard-workstreams/P6_R7_RUN13_20260929.md)、[run14](../development/whiteboard-workstreams/P6_R7_RUN14_20260930.md)。生产 profile 继续拒绝；父 Goal 1 的唯一集成候选和跨包真人 Gate 尚未完成，仍保持活动。下列 9 月 12 日审计和 R7 状态是历史快照，不再代表当前待验项。
>
> 审计状态：`authority-preflight` 已关闭；Goal 1 的 UI-T、P4 已真人通过，P4 exact `e77045fa` 完成持久 Undo/冲突/重启恢复。2026-09-06 P5 在手机 Dreaming 只读限定范围内通过，权限按用户确认的“自动拦截 + 真人只读回复”组合判定，不冒称真人实际调用未知写工具。persona `4ba05b11` 冻结，双端候选指纹见 P5 整合记录。P6 入队、指定 ID 状态查询及 App 重启后等待态保留已通过；用户已授权并派发 [P6-R2 返修](../development/whiteboard-workstreams/P6_R2_REPAIR_PLAN.md)，分离指定任务强绑定、执行核心与 Runtime 权限隔离；第一轮代码已本地集成，主控 122/122 回归与 Bridge 31/31 通过；后台工具隔离未成立，真实执行及写入真人 Gate 尚未解锁。P6 与父 Goal 未通过。手机近期聊天/结构化事实/UserRhythm 未接入；连接提示改进及 W4 非阻断。push / 发布未授权。正式 Gate 1A-0 已在独立合同链完成并关闭；P6 / Goal 1 未通过不因此解锁 Gate 1A-1、生产权威迁移或 MDA-2。
>
> P6 最新 R7（2026-09-12）：v5本机八项网络事件矩阵与完整回收实际通过（5019bbd0、exit0、pendingfalse），原同步负控false保留；既有失败实例均已独立回查或清理。19/19、自测233、真实文件等待22断言与独立核对通过。此结果不等于真实CLI持续隔离或生产接线。真实账户请求0，生产拒绝，账户/停止接线及App/真人Gate仍待，P6与Goal1未通过。详见[R7](../development/whiteboard-workstreams/P6_R7_EXECUTION_BOUNDARY_PLAN.md)。
>
> R6 历史证据（旧 CLI pin）：专用登录、固定公开文字真实回合和匹配 terminal/实际 close 分别通过，组合 170/170、合成 14/14。桌面更新后的 R7 使用不同可执行文件 hash，不继承旧候选隔离或真人结果。见 [R6](../development/whiteboard-workstreams/P6_R6_TEXT_GATE_PLAN.md#认证状态与当前剩余)。

本文回答四个问题：Here I Am 最终是什么、数据以哪里为准、当前真实基线在哪里、下一阶段按什么 Gate 推进。它不是无限任务清单，也不替代阶段 Goal。每次只从本路线提出一个可验收 Goal；Goal 的规划、派发、等待、审计和集成遵守 [`COLLABORATION_EXECUTION_PROTOCOL.md`](../development/COLLABORATION_EXECUTION_PROTOCOL.md)。

领域路线可以细化 Memory V3、白板、阅读、跨设备、教师招聘和数据恢复，但不得覆盖本文已经确认的目标边界与优先级。本文规定目标状态，不会仅凭文字立即改变当前运行 schema：任何数据权威迁移在 ADR、兼容、试迁移、回滚和真人 Gate 通过前，仍以当前运行代码及现行共享契约为唯一运行依据。

2026-08-26 用户明确确认：Goal 1 不取消、不取代；`GOAL-20260826-authority-preflight` 已关闭后，仅恢复 UI-T、P4、P6 返修。三包现已完成隔离交付、审计、逐包本地集成、`108/108` 组合自动验证与 `v3-lab@fad8b736` 的 Windows Debug 集成构建；这不是最终真人通过。Goal 1 已按约回到阻塞态，P5、最终真人 Gate、W4 红灯、push、发布以及正式 Gate 1A-0 当时均未解锁；其后 Gate 1A-0 已由独立合同链完成并关闭。

2026-08-28 真人复验推翻了“P4 只差重开 Undo”的旧判断：合并后唯一候选 `v3-lab@53d2dc91` 中，手动六类操作仍绕过 Domain Receipt / 持久 Undo，桌面 Runtime 也没有注册或分发六类 DomainCommand。父 Goal 因此阻塞，用户已创建窄返修 Goal [`GOAL-20260828-p4-production-reachability-repair`](../development/goals/GOAL-20260828-p4-production-reachability-repair.md)；它只补人工 / Runtime 共用生产纵切与退出重开 Undo，不扩张 P5、P6、W4 或 Gate 1A。

2026-08-29 真人 Gate 进一步推翻了“P4 只剩退出重开”的判断：`30a73ce3` 在人工第一项即把既有透明单面 `CompactCardEditor` 替换成异色表单，标题不可编辑；每次 Domain receipt 后的整板 reload 还用持久 viewport 覆盖用户当前 pan / zoom，造成白板跳位。该候选已作废。原 W1 第八轮现已恢复既有双击单面 UX、manual-only 标题与正文同 batch / Receipt / Undo、active viewport，并补 Runtime 执行侧标题防线和保存失败可见性；两轮 test-only 清理关闭 Windows teardown 与真实 rich I/O 等待不稳定。W0 完成独立复核、主线集成和核心 `73/73`、相邻最终 `107/107`、Repository `39/39`、Card Library `13/13` 等自动 Gate。Domain 正文仍严格限定为 canonical 纯文本替换；repository 计算型 stale 隐藏但保留投影不匹配的旧 RichTextDocument / assets，不新增跨 DB / filesystem journal，也不把 P4 扩大成 full rich-text authoring。新唯一候选 `77949971` 已从 detached clean Worktree 构建、指纹化并启动；真人 Gate 完成前，P4 仍未通过。

2026-08-29 `77949971` 的人工双击编辑、标题 / 正文、viewport 与右键标签曾通过，但进入白板直接新建卡片的 full editor 时，系统把正常尚无 rich 文件的 canonical plain Card 错误宣告为“富文本文件缺失 / 数据库正文投影恢复”。第九 / 十轮改成中性通知并集成为 `526db238`，自动 Gate 全绿，但新候选真人第 1 项再次失败：内嵌编辑右侧出现滚动条，Delete / Backspace 被画布快捷键抢占并直接移除 BoardItem；回卡片库全屏编辑时，中性 rich 物化通知本身仍是正常新卡不应出现的内部噪声。候选已冻结，旧真人通过项不沿用；P4-R 必须让编辑态键盘事件归输入框、退出编辑后 Delete 才移除摆放，并让正常新卡无通知，corrupt / stale 继续可见。

第十一至十三轮现已关闭这三项回归：编辑态仅保留画布 Escape，文字删除 / 选择 / 导航与 Undo 归输入框；内嵌编辑不再绘制 Windows scrollbar；既有 KV 以 Card incarnation 记录 rich materialization evidence，使正常 plain missing 静默、真实曾物化后丢失才告警，corrupt / stale 仍可见。worker `f7407823..08b112e8` 经独立复审后集成为 `a8ef84d9..7fa6cbb9`，集成态定向 `57/57` 与关键守门通过。exact `7fa6cbb9` Windows 候选已构建并健康运行，完整真人 Gate 从第 1 项重新开始；full-rich 并发、物理删除孤儿清理与 rich root 备份仍是后续债。

`7fa6cbb9` 的人工 create / edit / labels / move / resize / remove 六类真人操作随后全部通过，但 Runtime create 首项再次推翻自动绿灯：Domain action 与 Card / BoardItem 已成功落库，Runtime host 却生成富文本文件系统拒绝的冒号 ID，并把未指定坐标默认写在远离 active viewport 的 `(0,0)`；快捷卡片库的 drag / click 又只生成未落盘的 ViewModel placement，后续写操作返回 `placement_not_found`，单张 unsafe Card 还能中止全局卡片库加载。该候选已冻结，真实数据只读取证后保持原样；同一 P4-R Goal 已派发第十四轮，只补 safe ID 与精确 legacy 映射、host-owned 可见落点、manual-only 持久 place command 和按卡失败隔离，不改 schema 或新增 Runtime capability。

第十四轮已把这三条断链收回同一权威路径：Runtime 使用确定性 safe ID，缺省坐标按 active viewport 可见居中；精确 legacy 冒号 ID 只进入隔离安全目录，其它非法 ID 仍 fail closed；快捷卡片库 click / drag 通过 manual-only DomainCommand 落入 Drift / Receipt / reload，失败不留幽灵 placement，Runtime capability 不扩张。worker `5f515512..715be434` 经两份独立复核后集成为 `v3-lab@caecf05e..884dcd80`，自动 Gate 与关键守门通过；exact `884dcd80` detached clean Windows Debug 候选已构建、指纹化并启动，App / Bridge / Runtime 健康，真人从 Runtime create 首项重验。

`884dcd80` 的 Runtime create 首项现已真人通过：新卡立即出现在当前视口。后续操作暴露一个跨焦点缺口——用户从聊天输入切回白板、单击卡片后 Delete 未到达画布；它不推翻创建与持久化结论，但必须在 P4 关闭前形成真实 Gate。另有一项非阻断呈现债：手动白板操作当前也把可撤销行动卡逐条持久投到主关系对话；底层 Receipt / Undo / append-only 审计继续保留，手动过程提示应迁往白板操作历史或撤销表面，主对话只保留用户需要的授权、失败与结果摘要。

随后全局卡片库真人 Gate 通过：桌面侧栏独立卡片库可正常加载，没有再因 legacy unsafe Card 导致 `Unsafe card ID` 或全库失败，并能检索到“Runtime 创建验收 R14”。当前只继续验证白板内快捷卡片库是否通过 manual-only DomainCommand 形成持久 placement，而不是再次混测全局检索。

白板内快捷库的下一项真人 Gate 随即失败：单击 R14 卡后新摆放出现，但 ArrowRight 没有可确认右移且 selection 消失。两份只读审计确认 production manual command 的 lock / reload 会清空 selection，而既有测试等待时序过强且没有断言真实鼠标焦点与 reload 后 selection 连续性。`884dcd80` 因此冻结；create / global library 仅保留为已观察证据，不能把快捷库持久移动、Receipt 或 restart 宣称通过。R15 只修 W1 交互连续性与 production route 证据，不改共享领域契约。

R15 现已在 production route/manual UI 边界恢复“仅限持久 reload 后仍存在 BoardItem”的 selection，并让画布在真实鼠标选择及成功 placement / move / resize 后显式收回焦点；失败、目标已移除、reconciliation failure 或 surface/route 已切换时仍不恢复陈旧 selection。worker `245af967` 与审计补强 `bf134301` 经独立复核后集成为 `v3-lab@372885cb..a36e5236`；主窗 production route `7/7`、三文件 analyze、critical `3/3` 与 diff check 均通过。exact `a36e5236` detached clean Windows Debug 候选已构建、指纹化并启动，App / Bridge / Runtime 健康。快捷库新摆放后连续两次 ArrowRight 已真人通过，逻辑 selection 保留；每次移动的选中框短暂闪烁后恢复，登记为非阻断视觉抖动。聊天输入拿过焦点后，单击卡片再按 Delete 也已正确移除 BoardItem，R15 两项真人返修闭环。当前恢复 Runtime 剩余五类操作，先验正文编辑；行动卡占用主关系对话仍是非阻断呈现路由债，本轮没有顺带修改。

Runtime 正文编辑首项随即失败：用户明确要求把 R14 卡片正文改为新值，同时限定“不改标题、标签、位置或大小”，产品回复 `unsupported_product_tool`，并只读确认所有字段均未误改。两份独立审计和运行时输入证据共同确认：全局否定短路先于正向能力提取，尾句对其它字段的限制把 `edit_card_body` 授权也整体清空；因此标准白板工具调用在 conversation dispatcher 被拒，未进入 adapter / facade / Drift。`a36e5236` 候选冻结，后续 Receipt / restart / Undo / conflict Gate 停止；同一 P4-R 已派发 R16 独立任务 `01a04d7d-d383-79b2-a7ce-865f80761452`，只做 capability 级授权解析与 exact 真人原句回归，不扩六类能力或共享领域契约。

R16 已把授权解析改为“先识别逐项正向能力，再减去同一局部子句内的否定能力”，并先剥离引号内容，避免正文示例文本干扰授权。worker 首轮 `4a15faad..e5d22ad0` 经 Terra medium 独立复核发现“不需要 / 不必”仍可能越权；follow-up `2ad8c134..daaa1e47` 补齐“不想 / 不希望”和中英文逗号边界后复审无阻断。W0 选择性集成为 `v3-lab@2778478a..66017099`；Runtime `14/14`、coordinator `23/23`、目标 analyze、critical `3/3` 与 diff check 均通过。exact `66017099e54ac6015949eb2419bf9a92e1dc7d55` detached clean Windows Debug 候选已构建并启动（PID `56408`），App / Bridge / Runtime 健康；现在只用原句重测正文编辑，真人结果出来前不恢复后续 Gate，也未 push 或发布。

原句在 `66017099` 上已越过 capability 授权，却被 `whiteboard_target_outside_scope` 拒绝；所有字段仍零误改。该轮真实 host context 直接显示 `selected_item_ids` / `selected_card_ids` 均为空，而 R16 exact production 测试固定预选 `item_a` 且让 fake Runtime 预知 `card_a`，因此漏掉“当前白板上标题为…”的自然语言目标链。两份独立审计确认生产没有 current-board title resolver，只有 selection-derived scope；不能靠隐藏点击顺序把原句判绿。`66017099` 冻结后，同一 P4-R 已派发 Sol high R17 `01a04de1-94ba-7c63-b685-0e88301b9468`，只补 host-owned、当前板、精确唯一标题到稳定目标的 fail-closed 解析；不开放整板 / 全局库 / 模糊匹配，不改六命令或共享领域契约。

R17 已把未预选场景收回 host-owned 当前板边界：仅对直接目标句做精确唯一标题解析，0 / 多义 / 跨板 / 仅卡片库全部拒绝；Card 多 placement 时正文 / 标签可按 Card 写，placement 操作因 item 多义拒绝。授权同时绑定 exact surface 实例，flush、invoke 与 durable 前任一重挂或切板都 fail closed；正文引号 literal 不参与标题作用域解析。worker `f026b23b..a7a6b3da` 经独立复核关闭三项 P1 后，W0 集成为 `v3-lab@21ade156..1f77633a`；Runtime + coordinator `51/51`、目标 analyze、critical `3/3` 与 diff check 均通过。清除 process-memory binding 后，2026-08-30 正文与标签真人通过；真实状态是标题仍为“Runtime 创建验收 R14”、正文为“R15 Runtime 正文编辑通过”、标签为小写“runtime验收”。随后“右移 120 像素”turn 已获得唯一目标与 `move_placement` 授权，却因上下文缺当前 `x/y`、动态白板工具仅为软提示而没有调用产品工具，`180084ms` 后 `runtime_timeout`；零 payload、host result、Receipt 与写入。`1f77633a` 候选已冻结，R18 只补 bounded placement geometry 并真实探测 App Server required-tool wire；P5 / P6、其它 P4 Gate、push 与发布仍未解锁。

R18 已只向本轮获准 move / resize 的 exact target 注入同一 authoritative snapshot 的 `item_id/x/y/width/height`，geometry 不参与 scope，0 / 多义 / forged target 仍 fail closed；领域与 Runtime 共用坐标 ±1,000,000、宽 `80..3000`、高 `60..3000` 的唯一边界。首轮独立复核拦下极端 finite 坐标可持久化和非法尺寸先建 action 两项 P1，follow-up 后终审无 P0/P1/P2。真实 `codex-cli 0.151.0-alpha.7.2` schema 证明 `TurnStartParams` 没有 per-turn required / allow-only tool 字段。exact `2ed4b015` 的唯一 move 把 x 精确增加 120、y 不变，真人移动与首次重启保留通过；持久 Undo 把 x 恢复原值，Card 三字段与尺寸未变，第二次重启仍 `undone` 且不可重复。Lynx 最终确认行动卡显示“已撤销”、按钮消失，故 persistent Undo 真人闭环通过。无 busy / Toast 的即时反馈仍登记为非阻断债。当前只恢复 Runtime resize；remove / conflict 尚未放行。

随后在同一旧候选输入“当前选中卡片宽度增加 120 像素”，宿主没有生成白板授权上下文，provider 在本地探索约 180 秒后超时；零白板工具、action、Receipt 与持久写入，原 geometry 保持不变。R19 `01a052f1-da65-7ad2-8f44-15a9ead2d80f` 只补严格相对尺寸意图、完整 quoted-literal 隔离和 selection / authoritative snapshot 双重 fail-closed；独立复核先拦下 malformed exact-title 咨询劫持、trim 后 quote offset 越界与 stale selection 空 geometry 三项阻断，follow-up 后确认可集成。worker `37c77acd..523ec22a` 已选择性集成为 `v3-lab@2a75a7c0..158158dc`；主线 Runtime `34/34`、coordinator `23/23`、critical `3/3`、两文件 analyze 与 diff check 均通过。自动证据不代替真人 Gate；当前尚无 R19 新候选，remove / conflict 继续冻结。

exact `722a646d` R19 候选随后完成构建并健康启动，但真人连续两次宽度 `+120` 均返回 `whiteboard_surface_changed`，零 action / Receipt / 持久写。根因不是用户未选中，而是 production route 进入 readonly 时同步清空 selection 并发布同 attachment 新 snapshot，R17 的严格实例 gate 将其误判为真实重挂。R20 只新增 host-owned attachment token：selection-only snapshot 保留 token，每次 fresh attach 更新 token；lock 后仅允许同 token 的空 selection，非空 replacement、换 owner / board 与后续竞态继续 fail closed。两份独立复审无 P0/P1，worker `591caf3a + 3c6265c7` 与 handoff `cdf01946` 已集成为 `v3-lab@3674548b..03c2afd9`；主线 Runtime + coordinator `59/59`、真实 production route `8/8`、目标 analyze、critical `3/3` 与 diff check 全绿。当前尚未构建 R20 新候选，remove / conflict 继续冻结。

2026-09-05，P4 在 exact `e77045fa` 唯一 Windows 候选上完成最终真人 Gate：resize `+120`、完整重启保持、持久 Undo 精确恢复、remove 只删除 BoardItem、Card 本体仍可检索；在后续控制卡移动造成快照变化后，旧 Undo 先以 `snapshot_changed_after_batch` 拒绝且 token 未销毁，撤销后续移动后同 token 重试精确恢复，再次完整重启仍稳定。Lynx 明确确认通过。该候选 exe SHA-256 为 `BE3BE7A7037327C735883998C430D02C6CC9373504202D773B76AFFFE0C11CB9`，kernel 为 `0CCDAE9E95572A9A37B1AF21BA634D653BBBBE85DB680342B644E7387A1367C2`；P4 子 Goal 关闭，父 Goal 解锁 P5。Bridge 的正式 per-turn required / allow-only wire 仍等待上游 App Server schema，当前 Codex 模型目录兼容需显式选择可用模型，均保留为非阻断兼容项。

2026-08-28 并行例外 Goal [`GOAL-20260828-legacy-cleanup-wave1`](../development/goals/GOAL-20260828-legacy-cleanup-wave1.md) 已验收通过并进入 `v3-lab@a29b212e`：第一批零注册 / 零调用孤岛与退役测试已删除，仍有效的 Tavern / Companion 覆盖已迁移或保留，全仓退役测试编译错误归零。该清理不改变产品路线、数据权威或 P4 主 Goal，也未触碰 SharedLife、CardCache、日程、UI 大簇、schema、依赖或用户数据。

---

## 1. 产品北极星与设备关系

Here I Am 是一个本地优先的 AI companion。用户自然生活、聊天、学习和工作；林埃在合适的时候理解、记住、提醒、回应并协助行动，但不把用户变成数据库管理员，也不把产品变成暴露内部 Agent 结构的任务管理器。

### 1.1 电脑是数据权威，不等于所有交互都必须发生在电脑

- 第一版由用户的主电脑运行 Here I Am Core，作为唯一权威写入者和数据恢复起点。主电脑目前是随身笔记本，除睡眠时段外常开；夜间 Core 离线是预期状态，客户端按离线优先设计，不上云（2026-10-05，见[个人数据中枢 ADR](../development/PERSONAL_DATA_HUB_ADR_20261005.md) 第 3 节）。
- 手机是同一个系统的便携前端，负责高频聊天、快捷记录和便捷查看；桌面负责深度阅读、白板组织、资料处理和长期任务。
- 日常使用哪一端更多取决于场景，不由数据权威关系决定。
- 当前开发优先级是桌面端；手机新功能开发暂停至 Gate 2 真人评审，或用户明确提出只能由移动场景完成的高频 companion 需求。暂停期间继续维护主聊天、语音、显式记录、近期查看、通知，以及必要的 Core 协议兼容、Android 系统兼容、安全和严重故障修复；不新增页面、完整卡片视图或新的数据产品面。2026-10-05 用户确认的例外：个人数据中枢的"记一下"页、今天/本周页和手机同步底层（总规划 W4、W5、W7-0），属于只能在移动场景完成的高频需求；其余手机新功能照旧暂停。
- 手机与桌面使用同一条主关系聊天、同一份 Memory V3 和同一个逻辑卡片库。白板悬浮球只是主聊天的桌面入口，不建立第二条关系聊天。
- TaskRoom 只服务真正的长期任务，过程与主关系聊天、Dreaming 隔离；主聊天只接收用户需要的目标、决定、依据和结果摘要。

### 1.2 正式产品表面

| 表面 | 当前职责 | 数据边界 |
|---|---|---|
| Here I Am Core（主电脑） | 权威数据、索引、Memory、调度、审计、备份与恢复 | SQLite 和权威文件只由 Core 直接访问 |
| Desktop AI Workbench | 卡片库、白板、阅读与资料处理、林埃入口 | 当前主力开发表面；经 Core 服务读写 |
| Mobile Companion | 主聊天、语音、快捷记录、近期查看与通知 | 便携客户端；不形成第二权威数据库 |

客户端不能通过网络挂载原始 SQLite；同一类产物也不能由多台设备各自生成再事后合并。2026-10-05 起（[个人数据中枢 ADR](../development/PERSONAL_DATA_HUB_ADR_20261005.md) 第 1.3、5 节）：手机是聊天回复、Record Organizer、Dreaming、提醒和 check-in 的指定执行者，Core 不可达时照常运行；它的产出是带幂等键的 `pending` intent，进有界 outbox，恢复连接后补交，由 Core 接受后才算权威。手机不是第二数据库或多主写入者。UI 必须区分 `pending / accepted / rejected / expired / needs_resolution`，不得把待提交内容显示为已经进入权威聊天、Memory 或 Card；手机上的林埃可以读本机的待同步记录，但注入时必须标明"未同步"。

### 1.3 产品四层保持不变

| 层 | 作用 | 代表能力 |
|---|---|---|
| 角色关系层 | 用户与林埃持续相处 | 主聊天、语音、来电、关系记忆 |
| User-truth 层 | 用户主动确认的真实生活资料 | Memory Card、日程、任务、事实 |
| 生活产物层 | 从 User-truth 和外部数据形成可查看产物 | Memory Review、Schedule、Health、Interests、Project Memory |
| 主动陪伴层 | 林埃基于记忆与现实上下文主动触达 | Check-in、提醒、出门建议、睡前陪伴 |

---

## 2. 不可回退的产品与数据契约

### 2.1 记忆、聊天与事实写入

- 普通角色聊天默认不自动生成 User-truth。
- User-truth 只从消息级“记录”、悬浮球保存、明确自然语言指令、外部数据流和专门学习循环进入；当前唯一整理入口仍是 `RecordOrganizerServiceV3`。
- Dreaming 的 Fragment / Episode / Saga 属于关系记忆沉淀，不等同于 User-truth。
- Project Memory 是 Memory V3 的特殊 domain，不进入普通 User-truth，也不污染关系记忆。
- 林埃读取 User-truth、Project Memory 和卡片内容时按需检索，不把整库预加载进每轮对话。
- 对话中明确说“把这一段整理成日记”等指令，构成范围明确、可审计、可撤销的卡片创建授权；林埃完成后在主聊天中给出简短回应。

### 2.2 统一卡片库

- 手机“记录”页与桌面“卡片库”最终是同一个逻辑卡片库的不同视图；手机 UI 的完整合并不属于近期 Gate。
- 所有可见内容使用同一种稳定 `Card` 身份。书籍、网页、图片、视频、摘录、日记、事实和普通笔记可以有不同预览与能力，但不建立彼此隔离的卡片数据库。
- Card 是中性内容身份，不天然等于 User-truth。事实确认、来源、所有者和审核状态是 Card 的元数据或领域关系；普通工作卡、AI 按用户要求创建的卡片和 Dreaming 观察不能因进入统一卡片库就被标成已确认事实。
- Gate 1A 的 ADR 必须定义最小中性 Card 语义、物理 schema 与迁移映射，但 Roadmap 不提前写死新表名或 `kind / owner / visibility / truth_status` 等枚举。至少必须覆盖稳定 `card_id`、内容角色、owner / created-by、生命周期、当前权威 revision，以及独立的 User-truth / provenance / Evidence 关系。
- 目标模型中，每张 Card 都有一份可读 Markdown envelope；YAML 保存稳定 `card_id`、权威 revision 和开放元数据，正文保存当前 Card 内容。系统只读字段、用户可编辑字段和派生字段必须有明确 schema；文件可由用户人工阅读和编辑。
- 原始书籍、PDF、图片、视频和网页快照属于 `SourceContent / SourceVersion`；Card 的 Markdown 保存其来源引用、用户正文与元数据，不把大文件二进制或整本书正文塞入 Markdown。
- 媒体原件、结构化 Anchor、Evidence Claim、任务回执和其他领域状态继续作为 Markdown 所引用的结构化对象，不要求把全部运行状态序列化进文件。
- SQLite 保存操作日志、白板与关系、同步状态、版本映射，以及可重建的 Card 目录和全文索引。操作日志与不可重建领域状态属于必须备份的结构化权威；目录、FTS 等投影可以重建；二者都不是 Card 当前正文的第二权威。
- 文件夹只表达用户定义的物理收藏位置，不承担固定产品分区语义。标签、双链、搜索与白板负责逻辑组织。
- 普通 Card-to-Card 语义链接以稳定 `card_id` 加可读标题表达；正向 Markdown 链接是这类关系的权威，反链由索引派生。Source/Version/Anchor、Evidence 引用、BoardGroup 和 `BoardEdge` 继续使用各自结构化权威；`BoardEdge` 不反向改写普通双链语义。

### 2.3 Board、Source、Anchor 与删除语义

- `BoardItem` 只表示某张 Card 在某张白板上的一次摆放，保存布局和局部视图状态；删除 BoardItem 不删除 Card。
- 同一卡片可在同一或不同白板出现多次，不复制正文或原件。
- Board 删除与 Card 删除是两条独立生命周期；删除白板不删除其中卡片。
- Card 删除把权威 Markdown 和受管理附件移入应用回收站并写 tombstone；外部删除进入待恢复状态，不伪造仍有正文的空卡片。
- 应用删除与外部删除都提供 30 天恢复窗口；恢复来自最后有效版本。批量或破坏性操作需要明确确认。
- “永久删除”只承诺从在线 Vault、索引和未来备份中移除；已经进入不可变备份的历史密文仍按保留政策到期，产品必须在确认前如实说明，不能暗示会立即从 WORM 历史版本消失。
- 右键菜单必须区分“从白板移除”和“删除卡片”；键盘 Delete 在白板内默认只移除 BoardItem。
- `Anchor` 必须绑定确切 `SourceVersion`。来源变化时只自动迁移精确匹配；模糊匹配待确认，无法匹配继续保留在旧版本。

### 2.4 编辑、版本、冲突与 AI 权限

- App 写入、用户直接编辑 Markdown 和导入文件都进入同一版本链与操作日志。
- 单文件保存使用原子替换；跨 Markdown、Source、operation log、SQLite、FTS 和 Receipt 的提交必须使用显式 intent/journal、revision hash 与启动恢复协议，不能把单文件原子替换误当成跨介质事务。
- 无效 YAML 不覆盖最后有效版本；App 与外部同时编辑时保留双方，不以最后写入静默覆盖。外部修改被接纳时也进入同一版本链，并生成可审计的外部编辑操作。
- 重命名和移动不改变 `card_id`；同哈希重复导入只复用既有 `SourceContent` / object blob，不自动合并逻辑 Card。重复 ID、不同版本、不同译本和用户有意创建的同内容卡片必须显式处理。
- 所有人工和 AI 写操作复用同一 `DomainCommand / Receipt / Undo` 语义，不允许 AI 专用旁路。
- 用户给出明确且有界的创建或编辑请求时，林埃可直接执行并返回回执与撤销；没有授权时只提出建议。破坏性批量操作仍需确认。
- AI 对白板的摆放默认靠近调用位置、选择范围或当前空白视口，并提供定位、高亮和整批撤销；不自动建立固定分区。

### 2.5 当前 Card 与 RichTextDocument 契约的迁移红灯

当前白板卡与 Memory Card 的物理复用可能把普通工作卡写成 `user_truth`；现有白板总纲又把 `RichTextDocument` 的 block tree / marks / asset refs 作为共享持久结构。本路线确认的目标模型是“中性 Card 身份 + Markdown/YAML Card 正文权威”，因此这里包含两项硬架构迁移，不是措辞调整。

在正式迁移 Gate 通过前：

1. 现有 `MemoryCards`、`RichTextDocument` 和当前持久化路径继续作为唯一运行权威，任何功能线不得提前双写或静默破坏调用者；
2. Gate 1A 的第一份 Goal 必须先完成对象盘点与迁移矩阵：现有 Memory Card、白板普通卡、Source、Annotation、Dreaming、Evidence 投影和 TaskArtifact 分别迁移成什么、是否属于 User-truth、由谁写入、正文或状态以哪里为准、如何回滚；
3. W0 必须提交中性 Card 语义与物理 schema、User-truth 关系、Record Organizer 写入边界、正文权威、双向兼容、旧数据迁移和回滚路径的 ADR；Roadmap 不预先决定新建 `cards` 表还是演进现有 schema；
4. 切换后的 Markdown envelope/revision 是 Card 当前正文唯一权威。`RichTextDocument` 若保留，只能作为从权威 revision 可确定性重建的编辑器内存态、可丢弃缓存或兼容输入；它不能独立提交并在重启后与 Markdown 竞争。所有保存只通过同一 DomainCommand 生成新的 Markdown revision、parent hash 和 Receipt；
5. ADR 必须提供现有 block / mark / asset / Anchor 到 Markdown 的映射表与 golden corpus，把每一项标为无损映射、受控扩展、降级保留或迁移阻断；未分类项阻断切换。语料必须覆盖中文 IME、嵌套列表与引用、重叠 marks、代码、图片/视频/附件、脚注候选、空块、历史版本和外部文件编辑；
6. 必须定义 Markdown、Source、operation log、SQLite、FTS 和 Receipt 的唯一 commit protocol，并对文件前后、日志前后、DB 前后、索引前后和回执前后逐点注入崩溃；重启后只能收敛到完整旧 revision 或完整新 revision；
7. 正式切换前必须具备最小外部编辑安全集：重复 ID 检测、无效 YAML 隔离、外部移动/删除、复制、App 与外部并发修改的双方保全，以及最后有效版本恢复；完整导入、搜索和交互体验继续留在 Gate 1B；
8. 旧路径、试迁移、新路径、回滚和再迁移都必须验证主聊天、消息级记录、悬浮球、“记一下”、Memory Review、更正与按需召回连续可用，且普通 Card 不会误入 User-truth；
9. 在任何真实迁移前先建立一份校验锁定、已完成恢复验证的离线救援快照。完成试迁移、保留迁移后新增写入的无损回滚、再迁移和真人签字后，才能切换运行权威。

### 2.6 AI Workbench、权限与视觉边界

- Here I Am 持有产品上下文、权限、审计、撤销和结果落地；Codex App Server 是首个 RuntimeAdapter，不是第二人格。
- 模型 payload 不能扩权；搜索、卡片、白板和文件能力由产品侧按 turn 授权。
- 普通短 turn 不创建 TaskRoom。主聊天与 Dreaming 的生产查询必须排除 TaskRoom lane；若当前实现仍有泄漏，作为数据边界缺陷修复，不能把旧行为提升为产品语义。
- 手机当前唯一主力视觉仍是“春雨昼眠”；Desktop 保持独立信息架构和 `DesktopWorkspaceTheme`，不复制手机页面或整套视觉。
- 记忆云、圆柱大厅、坠落动画、暮雨玫瑰和 R0–R7 时辰色板只作历史追溯。

### 2.7 外部平台内容采集契约

- Here I Am 不使用非官方工具运营用户的平台账号；不得把只读、研究或临时试点包装成账号自动化的生产授权。
- 用户分享链接、截图或文件，只授权处理该项内容，不授权搜索相关 Feed、评论区、用户主页或推荐内容。
- 除非平台提供正式 API 和明确权限，否则禁止登录态自动搜索、翻页和批量读取；登录门槛、验证码或风控状态不是待绕过的技术故障。
- 不通过随机等待、降低频率、UA、浏览器指纹、隐藏 WebView 或模拟真人操作绕过反爬与平台限制。
- 捕获与解析分离：多链接可以在本地提取、规范化、去重并进入 Link Inbox；网络解析只按来源能力逐项、显式执行。待解析项不是 Card、Source 或 User-truth，解析成功并经确认前不得显示成已入库内容。

### 2.8 工程与发布

- 唯一日常开发与集成分支是 `v3-lab`；并行工作使用隔离 worktree 和临时 `codex/*` 分支。
- 同一时刻只有一个活动 Goal、一个验收主窗和一个唯一构建候选。
- 阻塞 Goal 可以保留其历史与未完 Gate，但不得同时派发、集成或构建；只有用户明确确认的、依赖与拥有路径完全隔离的临时 Goal 可以在此期间成为唯一活动 Goal。
- 阶段完成必须经过：工作包交付 → 主窗审计 → 选择性集成 → 统一回归 → 真人验收 → 用户确认 push。
- Android 只构建和安装 `hereIAmV3`；push、发布和破坏性操作不由“执行并派发”自动授权。

---

## 3. 2026-08-26 真实基线

| 领域 | 已建立 | 尚未闭环 |
|---|---|---|
| 已恢复的 AI 工作台 Goal | UI-T、P4 已真人通过；P5 已按限定手机 Dreaming 来源和用户确认的组合权限方式通过；同一 Windows 候选未变 | P6 入队/status/App 重启后等待态保留通过；P6-R2 第一轮目标绑定/执行核心/拒绝门控已本地集成并通过回归，生产隔离尚未成立，写入真人验收暂缓；父 Goal 未完成。W4、push / 发布不随 P5 自动解锁 |
| 已关闭的临时预备 Goal | `GOAL-20260826-authority-preflight` 已通过用户真人审阅并关闭，只使用代码实况与合成数据 | 已交付对象盘点、迁移矩阵、golden corpus 与隔离 harness 骨架；没有切换生产权威，也不证明 Gate 1A-0 通过 |
| Desktop Whiteboard | Card/Source/Board/Anchor 骨架、卡片库、画布、链接入库、视频研读、通用命令基础 | Markdown 权威迁移、完整删除/恢复、文件导入与外部编辑冲突、生产搜索和灾难恢复尚未形成统一 Gate |
| Memory / Chat lanes | Memory V3、Dreaming、显式 Record Organizer、Project Memory 与 TaskRoom 数据层已存在 | 中性 Card 与 User-truth 尚未拆清；主聊天和 Dreaming 对 TaskRoom lane 的过滤必须复核，不能假设隔离已经实现 |
| Cross-device Core | 私人电脑唯一权威核心方向、稳定消息 ID、核心 API/change feed、手机 outbox 与部分同步链已存在 | 仍有旧“双机整包往返/last-writer-wins”验收叙事；需统一为单权威 Core、仅提交意图的客户端 outbox 和可防双活的灾难接管 |
| Backup / Restore | 配置加密、S3 推拉、记忆整包快照与恢复前 safety snapshot 已实现 | 现有实现不满足不可变 S3、四份副本、外部资料根、分阶段恢复、密钥恢复和真实灾难演练 |
| Teacher Recruitment | 历史 Phase 0 试点证明登录、检索和查询拆分在技术上曾可运行；教材包已完成 OCR、结构、知识树与查询接口。该试点保留为“技术验证完成、产品路线失效”的历史证据 | 2026-08-26 账号违规预警已推翻登录态 discovery 的生产可用性，登录态小红书 MCP 正式退役。当前可用基线是用户人工选材、链接导入、匿名单篇解析和教材 OCR；尚缺 Link Inbox、本地去重、逐项解析及 `needs_screenshot` 等诚实状态，也尚未建立正式 Source/Evidence/Batch 数据层、全深圳轻量普查、深样本、看板和真人 Pilot Gate |
| Reading / Co-reading | 小说/漫画阅读、Topic Thread、划线批注基础和新调研输入已存在 | 统一 ReadingPackage、白板阅读窗、稳定跨格式 Anchor 与真实作品验收未闭环；主动品味系统明确延期 |
| Mobile Companion | 主聊天、语音、显式记录、Memory V3 与便携捕获能力存在 | 手机新功能开发暂停；Android FGS、数据安全和严重故障修复仍按证据处理，统一卡片库移动视图和 Core 完整切换以后再做 |
| Health / 多端活动检测 | Android 已有按需 UsageStats、App 前台心跳、标准 BLE HRS 软件闭环和 Health 状态面；COROS 精确 APK `3056968E…761D4` 的零大缺口 8 小时 Gate 已通过；MDA-1 控制面源码已合入本地 v3-lab | 现役仍固定 v4，活动域 schema 5 未部署；Windows/第二 Android/iPhone collector、睡眠推断与受控介入尚未实现；三星重启恢复与产品耗电预算不在 COROS 可用 v1 结论内 |

当前状态以 [`GOAL-20260824-ai-workbench-wave1.md`](../development/goals/GOAL-20260824-ai-workbench-wave1.md)、[`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md) 和当前可达提交为证据。Roadmap 不把“代码存在、自动 Gate 通过或已经 push”写成“真人通过”。

Android 严重崩溃、Memory 真实误召回、数据损坏、安全漏洞和 Project Memory 权威对账属于持续可信性维护，不因桌面优先而失效。它们由真实证据触发；若需要中断当前 Goal，必须由用户按协作协议明确取代，而不是静默插队。

---

## 4. 固定执行顺序：从安全底座进入真实需求

### Gate 0 — 关闭当前活动 Goal

[`GOAL-20260824-ai-workbench-wave1`](../development/goals/GOAL-20260824-ai-workbench-wave1.md) 的 UI-T 与 P4 已真人通过。P4 旧候选陆续暴露的生产不可达、编辑态键盘 / 滚动条、正常新卡 full editor 通知、safe ID、可见落点、快捷库持久写、selection / focus、capability、current-board title scope、相对 geometry 与 surface lifecycle 缺口，均已在 [`GOAL-20260828-p4-production-reachability-repair`](../development/goals/GOAL-20260828-p4-production-reachability-repair.md) 中逐轮返修，并由 exact `e77045fa` 完成最终冲突 / 恢复真人 Gate。P5 已于 2026-09-06 按限定来源与组合验收方式通过；Gate 0 当前只剩 P6 与父 Goal 最终收口。

历史失败与当前未完 Gate 为：

- UI-T：真实系统剪贴板、回复期间编辑、`Win + H` 与菜单主题真人通过；Typeless 2.3.1 不向 Flutter Windows 输入框注入，保留为非阻断外部兼容红灯；
- P4：exact `e77045fa` 已完成人工 / Runtime 六命令、行动卡 / Receipt、完整退出重开、持久 Undo、冲突拒绝与同 token 重试恢复，真人通过。选中框瞬时闪烁、手动行动卡主对话噪声和 Undo 无即时成功提示仍为非阻断呈现债；
- P5：2026-09-06 **限定范围通过**。persona `4ba05b11` 冻结；手机历史样例获用户基本认可，真实 empty 与自然到期 unavailable 回复诚实。权限为用户确认的四组自动拒绝证据 + 真人只读回复，二者不互相冒充。双端候选指纹与历史自动回归见 `docs/development/whiteboard-workstreams/P5_PHONE_READONLY_INTEGRATION.md`。手机近期聊天、结构化事实、UserRhythm 未接入，不声称全量准确/时效；连接提示改进非阻断。
- P6：受控生产 Runtime 队列入口已接入。首个 enqueue/pending、同 ID status 及 App 重启后 pending 保留样例通过：新进程、原候选指纹、精确只读 DB 与用户回显一致，更新时间/队列元数据不变。**P6-R2 已授权并派发，整体未通过**：隔离补目标强绑定、执行核心及 Runtime profile，见 [返修计划](../development/whiteboard-workstreams/P6_R2_REPAIR_PLAN.md)。后台工具隔离探针未通过，生产执行保持拒绝，取消等写入真人测试暂缓；不能以内部状态测试替代真实执行生命周期/运行中恢复。不启动既有等待任务，不伪造运行状态，不声称已观察到误取消。

W4 匿名字幕 `0/18`、第二个 WebView2 播放器重建超时和时间轴拖动消失等缺陷继续作为非阻断红灯，不伪称通过，也不阻塞与视频无关的返修。

**退出条件**：当前 Goal 状态页、`I_PROJECT_STATE.md`、DEVLOG、唯一候选和真人结果全部收口；未通过则返修或由用户正式取代，不能静默进入下一 Goal。

#### 已关闭的临时例外 — Authority Preflight

用户已明确确认 [`GOAL-20260826-authority-preflight`](../development/goals/GOAL-20260826-authority-preflight.md) 曾在 Goal 1 阻塞期间成为唯一活动 Goal，并于 2026-08-26 真人通过、关闭。它只允许：

- 基于当前代码与权威文档盘点 Card、User-truth、Source、Dreaming、Evidence、TaskArtifact 等对象；
- 用合成、无隐私数据建立迁移矩阵、golden corpus 和隔离 harness 骨架；
- 把 P4 / P5 / P6 及其他未通过事实明确标为 unresolved input，而不是假设成立。

它不得修改生产 schema、默认读写权威、Runtime / Memory 接线或真实用户数据，不得把输出称为正式 ADR 通过，也不解锁 Gate 1A-0、1A-1 或后续 Gate。临时 Goal 关闭后，Gate 0 仍须回到 Goal 1 返修与真人验收。

### Phase 1 — Desktop Data-Safe & Basic Operations MVP

这是所有需求驱动开发之前的新硬阶段。它由三个连续 Gate 组成，不得打包成一个无法独立验收的巨型 Goal，也不等同于“已有 S3 按钮能用”或“能创建几张卡片”。

**原排期窗口（历史）**：原先只承诺完成 Gate 0，并在其关闭后提案 Gate 1A-0；后者已按获准的隔离合同链完成，当前 Goal 1 / P6 仍未通过。1A-1 及 Gate 1B、1C、Gate 2 继续依赖各自合同、迁移验证、授权与真人 Gate，不以旧“1–4 周”窗口或未经验证的“1–2 周”估算作当前工期承诺。

#### Gate 1A — 数据权威与可逆 Vault 迁移

Gate 1A 是阶段 Gate，不是一个 Goal。它至少拆成以下连续停止点，任何时刻仍只创建一个活动 Goal：

1. **1A-0 — Authority ADR & Migration Harness**：完成权威对象盘点、Card / User-truth / Source / Evidence / Dreaming / TaskArtifact / Capture / ImportCandidate / Link Inbox Item 迁移矩阵、Markdown / RichText 数据流、物理 schema 比较、跨介质 commit/recovery 协议、golden corpus 和隔离迁移 harness；不切换默认运行权威；
2. **1A-1 — Neutral Card & User-truth Decoupling**：落地中性 Card catalog、User-truth 领域关系、Record Organizer 兼容和旧调用者适配；普通工作卡对 User-truth 检索必须零误升格；
3. **1A-2 — Reversible Markdown Vault Cutover**：完成 Markdown revision、外部编辑最小安全集、历史/索引一致性、旧 → 新 → 旧 → 新无损往返和可恢复切换；
4. **1A-3 — Core Intent, Epoch & Fencing Integration**：主电脑 Core 成为唯一权威写入者；客户端只通过版本化 API 提交意图并读取 accepted 状态。outbox 是有界、加密、耐久的提交日志，不是权威数据库；ADR 必须定义对象范围、容量/TTL、满载行为、幂等键、拒绝/过期/人工处理、协议版本以及 Core 接受前不得触发的下游事件。持久 Core epoch / instance id、fencing token、租约或权威登记位置、重新配对、change-feed epoch 和旧 token 失效必须通过故障注入与集成演练。

每个停止点必须独立验收；任一项失败都保持当前停止点为红，返回同一 Goal 返修，不得启动下一项：

`Capture / ImportCandidate / Link Inbox Item` 是捕获与待处理对象，不是 Card、Source 或 User-truth。1A-0 必须定义它们的稳定身份、URL / note id 去重、幂等、取消、失败、重启恢复、Core 接受边界，以及 Core 接受前不得触发的建卡、Source 入库、索引和下游事件；只交付 ADR、fixtures 与迁移盘点，不实现导入 UI，也不扩大成新功能 Goal。

- **1A-0 通过**：ADR 已选择唯一正文权威、操作/领域状态边界和 commit/recovery 模型；迁移矩阵无未分类对象；golden corpus 与隔离 harness 可重复运行；生产运行权威未切换；
- **1A-1 通过**：普通工作卡进入 User-truth 检索或召回的误升格为零；显式记录、主聊天、Memory Review 与既有召回契约连续；
- **1A-2 通过**：锁定的真实数据克隆完成“旧 → 新 → 回滚至旧（保留新路径期间新增写入）→ 再迁移到新”，逐 phase crash matrix 全部收敛，历史、索引与双方冲突内容可核对；
- **1A-3 通过**：指定断网、重放、Core 重启、模拟旧主机返网和 token 过期故障下注入后，无旧 epoch 写入或重复 event，pending / accepted / rejected / expired / needs_resolution 均可核对。

Gate 1A 只验证接管协议与防双活机制；从真实硬盘/S3恢复到新电脑、再让旧主机返网的灾难接管真人演练属于 Gate 1C，避免两个 Gate 重复交付同一闭环。

**Gate 1A 退出条件**：对版本锁定的跨模块 fixtures 与一份经用户批准、校验锁定的真实数据克隆完成“旧路径运行 → 试迁移 → 新路径读写 → 保留新增写入的回滚 → 再迁移”。Card 内容、User-truth 集合、Source/Anchor、operation log、历史和索引逐项核对；全部 crash matrix 收敛；客户端 pending/accepted/rejected 状态诚实；无双重正文权威、重复事件或旧 epoch 延迟写入。不得在唯一生产副本上做首次迁移演练。

#### Gate 1B — 基本操作与外部文件闭环

- 创建、打开、编辑、保存、标签、普通双链、搜索、移动、重命名和导入；
- 外部拖入 Markdown 原子补齐缺失 ID；重复 ID、无效 YAML、文件被删和同哈希导入不静默覆盖；同哈希只复用 Source/object blob，不自动合并 Card；
- 导入明确区分三种模式：复制进受管理 Vault、只读 KnowledgePackage、外部链接。默认受管理复制；外部链接只保存指纹和重新绑定信息，除非另有独立备份证明，否则不计入四副本恢复承诺；
- 从白板移除、删除卡片、回收站、30×24 小时恢复和永久删除确认；应用回收站是用户操作保证，备份保留是另一条灾难恢复政策；
- App/外部并发编辑保留双方；版本历史、Receipt、Undo/Redo、重启恢复和冲突提示可核查；
- 右键菜单和键盘语义与 Card / BoardItem 生命周期一致；
- 搜索覆盖标题、正文、YAML 开放字段、标签与路径，并提供过滤、片段和可重建索引；
- 原始 Vault、便携包、JSONL/CSV 和灾难备份四类导出边界清楚。

一个真实的小型验收纵切使用日记，但不建立日记专用数据库或页面：

- 用户每次记录生成一张独立普通 Card，只通过“日记”标签聚合；
- 用户直接写卡片时林埃不自动插话；
- 用户在主聊天明确委托整理时，林埃创建日记 Card、保留来源并给出简短回应；
- 首页的日/周/月聚合与观察模块不属于本 Gate。

**Gate 1B 退出条件**：用户能在真实 Vault 中完成一次自写日记、一次聊天整理日记、一次外部 Markdown 导入/编辑、一次删除恢复、一次并发冲突保全、一次完整搜索和一次重启后撤销；全过程无静默丢失、事实误升格或不可解释覆盖。

#### Gate 1C — 四副本灾难恢复

Gate 1C 可以由连续子 Goal 交付，但只有三段全部通过才算 Gate 变绿：

1. **1C-a — Manifest & Recoverable A/S3 Pipeline**：冻结全部权威根和外部根证明，接通硬盘 A 与 S3，完成 manifest/schema/hash、可见告警、staging restore 和失败不覆盖现有数据；
2. **1C-b — Offline & Immutable Recovery**：加入硬盘 B、S3 versioning + Object Lock/WORM 或等效不可变策略、最小权限上传/恢复凭据、纸质恢复卡、密钥轮换和随机历史版本恢复；
3. **1C-c — New Core Takeover Drill**：完成原主机不可用、新 Core 恢复与接管、全部旧 device token 失效、可信重新配对、旧主机返网仍被 fencing 的真人演练。

三个子 Gate 也必须分别验收；任何一次 manifest、恢复、凭据、密钥或 fencing 验证失败都保持对应子 Gate 为红并返修，不得把部分演练计为整体通过：

- **1C-a 通过**：硬盘 A 与 S3 都能生成并校验 manifest/schema/hash，从各自副本完成 staging restore；失败路径产生可见告警且不覆盖当前可用数据；
- **1C-b 通过**：硬盘 B 与随机 S3 历史版本均完成隔离恢复，不可变保留和最小权限经反向验证，纸质恢复卡与密钥轮换演练可独立完成；
- **1C-c 通过**：原主机不可用时新 Core 可恢复并接管，旧 device token 全部拒绝，可信设备重新配对成功，旧主机返网后仍不能形成双活或写入新 epoch。

1C-a 只是恢复管线的阶段证明，不解锁 Gate 2；过渡期可继续使用现有 `.memexdata` 手动导出/导入作为救援工具，但它不满足四副本、不可变备份或 RPO 承诺，也不能替代任一 1C Gate。

第一版采用四份副本：

1. 主电脑权威数据；
2. 常连接硬盘 A 的小时级备份；
3. 平时断开的硬盘 B，每周冷备，并尽量与主电脑和硬盘 A 分开存放；
4. 加密、不可变、版本化的 S3 异地备份。

备份清单必须明确覆盖 Vault、SQLite/operation log、受管理 Source objects、外部受管根或其独立备份证明、配置，以及恢复所需的密钥材料；不能只备份旧 `.memexdata`。

目标：

- 数据发生变化后，硬盘 A 与 S3 两份独立备份均须在 1 小时内完成 manifest/schema/hash 验证，才能声明 `RPO ≤ 1 小时`；产品显示最近成功时间、实际数据年龄、磁盘未挂载与网络离线状态，不能把任务已启动或过渡期 `RPO ≤ 24 小时` 当成最终达标；
- S3 使用 versioning 与 Object Lock/WORM 或等效不可变策略；备份凭据不能删除历史对象，`latest` 同步对象不充当备份库；
- 用户级灾难恢复在新电脑准备好后 `≤ 24 小时`；硬件采购/准备时间与应用恢复时间分开记录；
- 默认保留 72 个小时版本、30 个日版本、12 个月版本；硬盘 B 每周更新。该保留政策不替代应用回收站的 30×24 小时保证；永久删除进入不可变历史后只能等待保留到期，用户确认时必须可见；
- 任一副本失败必须有可见告警、最近成功时间和人工处置路径，不以任务已启动代替成功；
- 恢复先进入 staging，完成 manifest/hash/schema/来源根检查后原子切换；失败不得覆盖当前可用数据；
- 提供纸质恢复卡，密钥恢复不以密码管理器为前提，也不能把唯一密钥只放在主电脑或同一个 S3 bucket；
- 每月自动在隔离目录执行恢复测试；初次上线以及备份格式、数据库或权威模型重大变化后执行真人完整恢复演练。

**Gate 1C 退出条件**：从硬盘 A、硬盘 B 和随机一个 S3 历史版本分别完成隔离恢复；再以“原主机不可用 → 新 Core 接管 → 旧主机重新联网”完成真人演练。任一恢复、密钥或 fencing 验证失败都保持本 Gate 为红。

只有 Gate 1A、1B、1C 全部通过，才进入需求驱动纵线。

### Gate 2 — 首个需求驱动纵线：深圳教师招聘 Evidence Pilot

Gate 1 通过后，不继续抽象建设泛化内容平台；直接围绕“拿到深圳初中语文教师编制”验证第一条真实纵线。

#### 2A. 范围

- 只做采集 → SourceVersion → 原子 Evidence Claim → RecruitmentBatch / AssessmentEvent → 教材映射 → 档案与证据看板；
- 使用官方来源、用户在小红书官方 App 中人工发现并主动交付的第一手经验链接 / 截图 / 导出材料、其他可信考情来源和人工补充；小红书仍是重要证据来源，但 Here I Am 不自动搜索；
- `D:\textbook` 作为只读 `KnowledgePackage` 接入，不复制 2160 个节点为 Card，不重建稳定 node_id；
- 默认映射到可靠 section/subsection，只有原文明确时才下钻 concept；
- 招聘批次是统计去重单位，帖子数量只增加证据支持强度，不增加考试发生次数。
- `EvidenceClaim` 是引用 source/version/unit/anchor 的不可变结构化领域记录；需要在卡片库显示时，Evidence Card 只保存 `evidence_id` 和可读投影，不复制一份可独立编辑的 claim 真相。Knowledge、Strategy 与统计同样只引用 Evidence IDs。

#### 2B. 采集与样本

- 先对深圳市直属及各区最近两届开展轻量官方普查，只建立候选总体与覆盖/缺失清单：招聘主体、年份、批次标识、学科、公告 URL、可获取状态、考试结构线索和缺失原因；普查阶段不要求全文抽取。官方网站和明确允许自动访问的公开来源可以使用搜索矩阵；
- 小红书搜索矩阵只作为用户在官方 App 内的人工检索清单，不交给 Here I Am、MCP 或隐藏浏览器自动执行；
- Here I Am 负责从用户主动交付的分享文案中进行多链接本地提取、规范化、URL / note id 去重并进入 Link Inbox；捕获成功不等于解析或入库成功；
- 网络解析采用无登录态、单项、显式触发；评论只有在用户主动交付，或匿名公开页面直接提供时才处理。遇到登录门槛、验证码、风控或访问限制立即停止，转为请求截图、复制正文或人工摘录；
- 再按考试结构、招聘主体、年份、区域和学科差异选择 5–8 个最大差异深样本；不预先指定行政区或每主体帖子配额。每个深样本至少包含一个官方 `SourceVersion`；第一手经验按独立 URL / note id 去重，帖子数量不充当批次覆盖度；
- 连续两个按差异分层选择的深样本，不再产生新的高影响 `EvidenceClaim` 类型、`AssessmentEvent` 结构、教材映射规则或冲突结论时，可以报告“暂时饱和”；否则必须记录缺口和继续条件，由用户决定是否扩样；新官方规则会重新打开相应分层；
- Gate 2 Goal 在采集前必须声明用户人工选材数量、待解析数量、时间预算、OCR/PDF 与 `D:\textbook` 的复用边界和人工补录路径。多链接可以批量本地入队，但不批量并发访问小红书，不设置“多少条绝对安全”的伪阈值，不后台长跑、不自动重试；达到资源上限即停止并报告覆盖不完整。

#### 2C. Evidence 与输出

- 每条 Evidence 是可回到 SourceVersion、SourceUnit 和精确 Anchor 的具体陈述；Source 原文与 EvidenceClaim 分别承担来源权威和声明权威，普通 Card 不因展示 Evidence 就自动成为 User-truth；
- 保留 A/B/C/D 证据等级、抽取置信度、第一手、官方确认、审核状态和冲突组；
- `EvidenceClaim` 不原地改写真相；纠错以 supersede / retract 等新记录表达，并保留原 claim 与理由；
- 冲突证据全部保留，未解决冲突不进入确定性统计；
- 统计同时给出 batch frequency、source support、firsthand support、official support 和近期批次频率；
- 输出每个 Batch 的档案、整体证据看板、知识 × 考核矩阵、来源下钻、数据空白和可解释的候选重点；
- 白板不采用固定资料分区。林埃只需明确说明整理结果在哪里，并对生成、摆放和连线提供回执与整批撤销。

#### 2D. 明确不做

- 不生成 S/A/B/C 学习优先级、“必背知识”和每日计划；
- 不自动修改教材知识树或把可能映射强行挂到 concept；
- 不把 187 个未验证选项顺序的题页自动变成题库；
- 不一次抓全网，不以漂亮百分比掩盖样本偏差；
- 不恢复登录态小红书 MCP，不重新连接用户账号；
- 不自动搜索、翻页、展开评论或读取推荐 Feed；
- 不以降低频率、随机等待、UA / 指纹或模拟真人作为合规依据；
- 不把待解析链接提前创建成成功 Card / Source，也不让失败项伪装成已入库内容；
- 不在 Pilot 完成后自动进入下一阶段。

**退出条件**：端到端 Pilot 报告能够回答样本各自考什么、证据是否一致、哪些模块出现于多少真实批次、哪些材料可映射教材、哪些仍冲突，以及数据模型需要如何调整。用户还必须能用真实资料完成四个任务：比较两个招聘批次的考核差异、把一个候选重点追溯到精确来源、识别一个证据不足而不应行动的信息空白；以及把一组日常刷到的小红书分享文案快速入队，由系统本地提取并去重，在白板通过“解析下一条”逐项处理，关闭重开后队列与状态仍准确，无法访问的项目明确请求截图。该任务验证导入快捷性与状态诚实性，不考验爬虫吞吐量。记录完成时间、错误归因和是否改变下一步人工备考选择；完成后必须暂停，由用户真人评审。

### Gate 3 — Pilot 后重新选择，而不是自动续跑

用户评审 Gate 2 后，再根据当时最紧迫问题只选择一个下一 Goal：

- 扩展到深圳近 2–3 届主要招聘并形成频率矩阵；或
- 将成熟 Evidence 映射为学习、复习和考核闭环；或
- 优先进入试讲材料与训练；或
- 选择移动端统一卡片只读视图、主聊天/Core 同步或其他高频 companion 场景；或
- 处理当时出现的其他真实需求。

Roadmap 不提前承诺 Gate 3 的具体顺序。

---

## 5. 需求出现后启用的能力

### 5.1 学习与试讲

- 教材搜索结果是临时结果；放上白板时才创建稳定 Source Card，保留 package/node/chunk/page/anchor。
- AI 可生成“重点知识白板”，但教材结构重点与招聘 Evidence 提示分开呈现，不制造神秘总分。
- 每日学习计划是引用既有 Cards 的动态队列，不复制卡片或强制创建新白板。
- Practice Card 与 ReviewAttempt 分离；复习选择需解释用户固定、到期、薄弱、章节连续性和成熟 Evidence。
- 语音学习由 Here I Am StudySession 持有状态；实时语音模型只听说并调用受控工具，本地 KnowledgePackage 和 Cards 仍是知识来源。
- 试讲白板支持 PDF、Office、图片、音频、视频和网页的能力级预览；受管理复制为默认，大文件可外部链接，断连后进入重新绑定而不是删除。

### 5.2 用户主动发起的共读

- 导入 TXT/EPUB/PDF 后保留原件，并为某个确切 `SourceVersion` 确定性生成可重建 `ReadingPackage`：章节、段落、稳定 ID、offset/hash、页码或 EPUB spine 和全文索引。Package identity 至少包含 `source_version_id`、parser/deriver version 与 package hash；它不是第二原件或 Card 正文。
- 每轮只在用户允许的 spoiler 边界内按需读取原文；模型预训练知识不能充当书中证据。
- 一张普通书籍 Card 连接原件与 ReadingPackage；在白板上可从收起卡片展开为嵌入式阅读窗。局部阅读位置可以进入 BoardItem `viewState`，但全局阅读进度、正文、Highlight/Annotation 和 SourceVersion 关系不得进入 BoardItem。
- 纯划线只保存 Highlight + Anchor；写批注或明确摘录才创建 Excerpt Card。所有 Anchor 继续指向确切 SourceVersion 与稳定 selector，ReadingPackage 重建不能改变既有 Anchor 的解释；拖出阅读窗时在白板放置同一张卡，不重复生成。
- 思维导图继续使用普通 Cards、Markdown 双链、BoardEdges 和可撤销布局，不创建 Markmap 或特殊地图卡。
- 微信读书不恢复为核心依赖；未来最多提供显式、单向、可失败的导入 provider。

### 5.3 手机统一卡片视图

- 当桌面 Vault 与 Core Gate 稳定、Gate 2 已完成真人评审且用户把移动场景选为下一 Goal 后，手机“记录”页再接入完整统一卡片库；
- 手机允许查看电脑端全部卡片、显式创建和编辑，但仍通过 Core API，不直接持有第二权威 Vault；
- 手机旧卡片设计如何适配桌面能力需要单独 UI 设计，不阻塞当前桌面 Gate。

### 5.4 论文与通用写作

- 近期只复用来源卡、摘录、双链、白板和普通正文卡，不建立论文专用数据库；
- Here I Am 负责研究、论证、材料组织与草稿，Word 负责最终排版与提交；
- 普通“论文大纲”Markdown 卡用有序链接组稿的方案保留为后续候选；
- 脚注、参考文献样式、DOCX 编译与 Word 修改回收只在真实写作瓶颈出现时立项。

### 5.5 多端活动检测与保守睡眠守护

- 用户已明确提出这是高频 companion 需求；专项路线见 [`MULTI_DEVICE_ACTIVITY_ROADMAP.md`](MULTI_DEVICE_ACTIVITY_ROADMAP.md)。建立路线不等于当前活动 Goal 已切换，也不覆盖各工作流的独立验收；P4 与 Gate 1A-0 后续已经各自通过，MDA-1 的隔离例外与 MDA-2 未启动状态见第 8 节；
- 完整 Here I am 仍只安装在主 Android。Windows 使用轻探针，第二 Android 优先 Tasker/旁路探针，iPhone 在无自研 App 时只提供 Shortcuts 离散事件；各端不复制 Here I am 数据库；
- 首版必须先完成活动专用 write-only 凭据、事件/TTL/`unknown` 语义、设备撤销与隐私保留，再做 Windows + 主 Android 纵切；Tailscale 在线、App 前台心跳和单一心率均不得冒充用户清醒或已睡；
- 活动专用控制面仍受 Gate 1A 的权威 ADR、Core 接受边界和单写者/epoch/fencing 契约约束；并行设计不得先落生产 schema 绕过 Gate 1A-0/1A-3；
- 推断先 shadow，之后才按真人 Gate 逐级开放一次通知、短对话和未来可选来电。2026-06-30 已删除的高频催睡、无回复确认、锁机与罚款机制不得恢复。

---

## 6. 明确暂停与 Parking Lot

### 6.1 等待专题讨论，不进入近期实现

- Desktop 首页完整 dashboard：先盘点所有模块，再分别确定实时、日、周、月等时间尺度、来源、更新节奏和持久化；此前关于“今日总结/今日观察”、0:00 生成、临时保留和沉淀卡片都只是候选。
- 林埃自主预读大多数书籍、形成自己的划线/批注、注意模式和品味轮廓，并据此主动推荐。该系统必须等白板工具流程完成后单独讨论。
- 论文专用组稿、复杂脚注、DOCX 双向同步和 Word 替代。
- 白板范围或整板导出 PDF/图片；保留需求，不占当前 Gate。

### 6.2 明确后置

- 微信读书双向同步、登录 Cookie 字幕增强、本机 ASR 主路径、直播、视频下载和 DRM 内容；
- 泛化 Task Center、完整 Agent 树、自动项目经理和模型自行扩权；
- 在没有真实纵线需求时独立推进 P8 图片生成上板、P9 HTML 原生展示或 FlexNote 长尾；
- 固定白板资料分区、Markmap 特殊卡、知识树自动改写；
- iOS、手机新功能扩张和公开发布准备；
- 记忆云、圆柱大厅、坠落动画和高成本 3D 空间化；
- 自动支付、真实转账或默认设备控制。

除紧急安全、兼容或数据损坏修复外，重新启动暂停项必须满足：当前 Goal 已关闭、依赖 Gate 已绿、用户重新提升优先级，并先更新本 Roadmap。紧急事项若需插队，也必须由用户按协作协议显式取代当前 Goal。

---

## 7. 固定依赖与红灯

| 上游 Gate / 决策 | 解锁 | 红灯处理 |
|---|---|---|
| 当前 AI 工作台 Goal 真人通过 | Gate 1A-0：ADR、盘点与迁移 harness | 自动测试或 push 不能替代真人签字；1A-0 不切换运行权威 |
| Gate 1A-0 真人通过 | Gate 1A-1：中性 Card / User-truth 解耦 | schema、对象映射、RichText 数据流或事务协议未决时不得迁移 |
| Gate 1A-0 真人通过 + 个人数据中枢 ADR 用户确认（2026-10-05） | 生活数据领域（captures、规划、收支、经期、睡眠）的 i_core 领域框架与逐域迁移；只实现 1A-3 中 intent / outbox / 回执 / 按领域 cursor / 墓碑部分，epoch 与换宿主接管暂缓 | 不以 1A-1、1A-2 为前置（二者随白板搁置）；通用记忆卡迁移前另行决定；每域迁移须影子期零差异、冻结切换、用户授权 |
| Gate 1A-1 真人通过 | Gate 1A-2：可逆 Markdown Vault 切换 | 普通 Card 误升格、旧调用者破坏或双写都会阻断 |
| Gate 1A-2 真人通过 | Gate 1A-3：Core intent / epoch / fencing | 外部编辑、崩溃恢复或无损回滚未绿时不得接管权威 |
| Gate 1A 整体真人通过 | Gate 1B：基本操作与外部文件完整闭环 | 迁移未绿前维持旧读取路径，不形成双重权威 |
| Gate 1B 真人通过 | Gate 1C-a → 1C-b → 1C-c | 无法稳定写入、冲突保全或撤销时，不在其上建立备份承诺；1C-a/b 不提前解锁 Pilot |
| Gate 1A、1B、1C 全部真人通过 | 深圳教招 Evidence Pilot | 任何静默丢失、覆盖、双活或无法恢复都阻断需求纵线 |
| 单权威 Core 与幂等 API已绿，且 Gate 2 真人评审后用户选择移动场景 | 手机完整统一卡片视图 | 禁止 raw SQLite 共享与多主覆盖，也不得绕过 Pilot 后重新选择 |
| SourceVersion / Anchor / provenance | Evidence、阅读摘录、教材回源 | 无原文、无版本或无 Anchor 的判断不得伪装成确定证据 |
| 外部平台账号边界与 Link Inbox 状态诚实性 | 用户选材后的逐项解析与 Gate 2 Evidence Pilot | 任何登录态或隐藏 WebView discovery、自动搜索 / 翻页 / 评论 / 推荐 Feed、验证码或风控后继续绕过，以及待解析项提前写成 Card / Source，均为固定红灯 |
| Gate 2 教招 Evidence Pilot 真人评审 | Gate 3 中按需选择频率矩阵、学习/试讲、移动端 companion 或其他真实需求 | Pilot 完成后必须停止，不自动进入 Gate 3 的任何实现 |
| W4 匿名 Bilibili 字幕严格 Gate `0/18` | 依赖匿名字幕的能力 | 与字幕无关的卡片、Evidence、阅读和数据安全工作可继续 |

---

## 8. 已关闭的 Gate 1A-0 与当前 Goal

### Gate 1A-0 结论

正式 Gate 1A-0 已通过第八名全新独立 Sol 终审，未发现 P0/P1/P2；合同/harness 本地候选为 `8797adf84feca2610a9f348fcd040f7299d6ea4a`。2026-08-30，Lynx 对修复后 W0 的五条时间线明确回复“通过”，本 Goal 已关闭。它只冻结 Authority/identity/recovery/physical schema/Markdown/cross-medium 合同与纯合成确定性 harness；没有切换生产权威、生产 schema、设备或外部配置。

### 当前 Gate

UI-T、P4 与限定范围 P5 已通过。P6 最新 R7 的 v5 本机八项网络矩阵与完整回收实际通过（`5019bbd0`、exit 0、pending false；专项 `19/19`、自测 233、真实文件等待 22 断言），原同步负控 false 保留；真实账户请求 0，生产仍拒绝，账户/停止接线及 App/真人 Gate 仍待，P6 与 Goal 1 未通过。P6 的未提交代码继续由原主窗负责，不纳入本候选。

### MDA-1 与运行边界

MDA-2 A3-I Android原生接线最终`c0bf3d49`已通过W0并选择性本地集成：初交付因冻结store未释放ownership被拒，R1补齐无条件close、系统调用前窗口验证与MethodChannel精确形状。干净导出A3 Dart 16/16、Kotlin 12/12、A1 56/56、A2 30/30、wire/Core 20/20及完整App单元任务通过。源码保持默认关闭；真实UsageEvents、APK、手机、Doze/强停/重启、Keystore与BLE共存属于A3-D。见[A3-I验收](../development/activity/mda2/android/a3_review/c0bf3d49/W0_ACCEPTANCE.md)。

MDA-2 A2 Android纯Dart持久outbox最终`ae9bfea0`已通过W0并选择性本地集成：两份早期提交因owner接管竞态和清理遗留活锁被拒；最终干净导出A1 56/56、A2 30/30、双analyze与现有Core 20/20通过。此结果不含原生UsageEvents/Manifest、网络、真实Core、设备或真人Gate；A3另行规划。见[A2验收](../development/activity/mda2/android/a2_review/ae9bfea0/W0_ACCEPTANCE.md)。

MDA-2 W3 Windows采集与队列接线修订`af3cb576`通过主窗本地验收：干净候选44/44、W2兼容35/35、独立退出5/5与实际清理；限定源码已本地合入 `v3-lab@63acaaf8`，65路径/54份并行修改保护核对通过，见[实际收据](../development/activity/mda2/windows/w3_review/af3cb576/LOCAL_LANDING.md)；下一步规划Android接线。真实采集、生产端点/配对/自启、现役切换及Android/真人Gate仍待。见[W3验收](../development/activity/mda2/W3_ACCEPTANCE_REVIEW.md)。

2026-09-13：MDA-2 R3+M3 C3源码已本地合入 `v3-lab@a6f9cbae`，70路径、72份候选输入和54份并行修改保护已核对，见[实际合入收据](../development/activity/mda2/runtime/combined_c3/LOCAL_LANDING.md)。下一步按既定依赖回收其余采集工作包；未推送、部署或迁移真实库，现役切换和真实设备/一晚Gate尚未执行。以下准备与未合入描述仅为历史。

MDA-2 已按后续确认进入隔离工作包阶段；MDA-2 R3+M3 本地候选 C3 已完成换行固定与停止请求竞态修复；隔离回归及证据见 [C3交接](../development/activity/mda2/runtime/combined_c3/HANDOFF.md)。当前只形成源码合入准备，未提交/主线合入/部署，其他采集工作包与真人Gate独立。以下MDA-2未启动表述保留为此前快照；现役固定v4不变。

MDA-1 已在功能候选 `fbcbceb0` 上完成历史三 probe 合成审看，并按 Lynx 后续明确授权本地合入 `v3-lab`，代码基线 `8326f5c1`；组合验证与八文档收口见 [实际落地记录](../development/activity/mda1/MDA1_MAINLINE_COORDINATION_20260912.md)，初次候选验证见 [裁决](../development/activity/mda1/MDA1_INTEGRATION_VERDICT_20260912.md)。现役 iCore 仍使用固定旧 v4 运行包，源码合入没有切换生产权威或部署 schema 5。真实 collector、睡眠推断、受控介入和 MDA-2 均未启动。

### 下一正式 Goal 候选（尚未创建）

> **Gate 1A-1 — 中性 Card / User-truth 解耦：现在具备另行提案条件，但必须先由 Lynx 确认；本次未创建或实施。**

Gate 1A-0 只冻结第一个正式停止点，不承诺落地中性 Card schema、切换 Markdown 运行权威、完成 Core 接管、基本操作或四副本灾难恢复。`authority-preflight` 的材料只作输入，不能替代已完成的独立终审与真人 Gate。1A-1/1A-2/1A-3、Gate 1B 与 Gate 1C 仍须依次另行提案，不提前打包；MDA-1 的隔离阶段已完成，MDA-2 仍未启动。

---
## 9. 已完成交叉审核与持续自查清单

2026-08-26 的产品、架构和执行交叉审核已经完成，用户已确认将审计结论并入本版。以下问题继续作为每个相关 Goal 的硬自查；它们不是留给未来泛泛讨论的开放问题。第 1–4、10–12 项必须由 Gate 1A 的 ADR、fixtures 与连续性 Gate 给出证据，第 5–6 项由 Gate 1C 给出恢复证据，第 7–8、12–15 项还必须由 Gate 2 给出 Pilot 证据：

1. 中性 Card catalog、User-truth 状态和现有 MemoryCards 之间的迁移边界是否清楚？是否仍有把“所有卡片”误当 User-truth 的隐性耦合？
2. Markdown/YAML 作为 Card 正文权威，是否能无损覆盖现有 RichTextDocument、附件、中文 IME、版本和 Anchor？迁移与回滚是否充分？
3. 单权威 Core、客户端待上传队列和灾难接管之间是否仍存在隐含多主或 split-brain？
4. Card Markdown、原始 Source、操作日志和 SQLite 投影的事务边界是否会产生“文件已写但日志未写”或反向不一致？
5. 四份备份是否真正覆盖 Vault、SQLite 操作日志、Source、外部受管根、配置和密钥，而不是只备份旧 `.memexdata`？
6. `RPO ≤ 1 小时`、30 天删除恢复和 72/30/12 保留策略之间是否一致？恢复演练能否证明，而非只证明上传成功？
7. Teacher Recruitment 的 Source / Evidence / Batch / AssessmentEvent / Mapping 是否保持分层，同时避免形成与统一 Card/Source 相冲突的第二内容权威？
8. 全深圳轻量普查和最大差异深样本能否减少样本偏差？“模型饱和”的停止标准是否可操作？
9. 白板嵌入式阅读窗是否继续遵守 BoardItem 只存布局/局部视图、原文归 ReadingPackage/Source 的边界？
10. 当前活动 Goal 的产物有哪些可复用，哪些会被 Markdown Vault 迁移推翻？是否存在不必要返工？
11. 暂停首页、手机扩张、主动品味与论文组稿后，近期路线是否仍能形成可被用户每天真实使用的产品闭环？
12. 待解析 Capture / ImportCandidate / Link Inbox Item 是否被误写成 Source / Card，或在 Core 接受前触发了索引与下游事件？
13. 是否存在任何登录态、隐藏 WebView 或自动 discovery 回退，包括自动搜索、翻页、评论展开和推荐 Feed 读取？
14. 多链接入口是否只做本地提取、规范化、去重和入队，没有把批量收件偷换成批量网络访问？
15. 登录门槛、验证码、风控或匿名访问失败时，是否诚实请求截图、复制正文或人工摘录，而不是继续绕过？

任何一项没有可复核答案时，对应 Gate 保持红。后续修改权威 Roadmap、取消活动 Goal 或创建下一 Goal，仍需用户确认。

---

## 10. Roadmap 维护规则与待对齐文档

在以下时机更新本文：

- 一个阶段 Goal 完成真人验收；
- 产品优先级改变；
- 重大基线、平台事实或依赖被推翻；
- 交叉审核发现经用户确认的缺口；
- 专项 Roadmap 已无法解释真实工作。

普通 bug、单次 handoff 和单个 worker 进度只更新 Goal 状态表、`I_PROJECT_STATE.md` 或 DEVLOG，不重写总路线。

本次重排后，以下文档含有待后续 Goal/ADR 对齐的旧契约或旧优先级；在正式迁移前仍可作为当前实现说明，但不得覆盖本文方向：

- [`CROSS_DEVICE_I_WHITEBOARD_MVP_ROADMAP.md`](CROSS_DEVICE_I_WHITEBOARD_MVP_ROADMAP.md)：统一单权威 Core、灾难接管与手机开发优先级；
- [`MEMORY_DATA_SYNC_ACCEPTANCE.md`](../development/MEMORY_DATA_SYNC_ACCEPTANCE.md)：旧两电脑 `.memexdata` / last-writer-wins 验收，不再作为日常 Core 同步或客户端合并契约；
- [`WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`](../development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)：RichTextDocument → Markdown 权威迁移，并补充平台账号自动化、登录态 discovery 与反爬绕过禁令；
- [`whiteboard-ui-spine-contract.md`](../design/whiteboard-ui-spine-contract.md)：首页完成定义与白板内阅读窗；
- [`whiteboard-requirements.md`](../design/whiteboard-requirements.md)：首页、日记、论文导出与旧 Draft 优先级；
- [`teacher-recruitment/phase0/ARCHITECTURE.md`](../development/teacher-recruitment/phase0/ARCHITECTURE.md)：删除第 99 行“浏览器、WebSearch 或外置小红书 MCP 找链接”的现行建议；第 310 行起的 MCP 选择与真人试点章节整体改为历史试点、账号预警和退役原因；同时对齐 Evidence Pilot、样本选择与停止 Gate；
- [`teacher-recruitment/phase0/XHS_MCP_READONLY_PILOT.md`](../development/teacher-recruitment/phase0/XHS_MCP_READONLY_PILOT.md)：标记为“历史技术验证完成、产品路线失效，禁止重新连接用户账号”；保留实验结果，不再作为生产接入依据；
- [`WAVE1_LINK_IMPORT.md`](../development/whiteboard-workstreams/WAVE1_LINK_IMPORT.md)：从“多个链接选一个”升级为本地提取、URL / note id 去重并进入待解析 Link Inbox；
- [`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md) 与 [`DEVLOG.md`](../../DEVLOG.md)：**本次已同步**账号预警、登录态 discovery 退役、Link Inbox 边界和后续待对齐事项；
- [`BOOK_READER_TTS_ANNOTATION_PLAN.md`](BOOK_READER_TTS_ANNOTATION_PLAN.md)：ReadingPackage、摘录卡与主动阅读延期。

领域权威索引：

- 协作生命周期：[`COLLABORATION_EXECUTION_PROTOCOL.md`](../development/COLLABORATION_EXECUTION_PROTOCOL.md)
- Memory V3：[`MEMORY_V3_ROADMAP.md`](MEMORY_V3_ROADMAP.md)
- AI 工作台架构：[`AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md`](../development/AI_NATIVE_WORKBENCH_CODEX_INTEGRATION_ARCHITECTURE.md)
- 当前工作台执行路线：[`AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md`](../development/whiteboard-workstreams/AI_WORKBENCH_EXECUTION_ROADMAP_2026_08_23.md)
- 白板并行契约：[`WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md`](../development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)
- 跨工具连续性：[`LIN_AI_CROSS_TOOL_CONTINUITY.md`](LIN_AI_CROSS_TOOL_CONTINUITY.md)
- Codex Voice 连续性与 iCore 接入：[`CODEX_VOICE_ROADMAP.md`](CODEX_VOICE_ROADMAP.md)
- 多端活动检测与保守睡眠守护：[`MULTI_DEVICE_ACTIVITY_ROADMAP.md`](MULTI_DEVICE_ACTIVITY_ROADMAP.md)
- 当前项目态：[`I_PROJECT_STATE.md`](../development/I_PROJECT_STATE.md)
