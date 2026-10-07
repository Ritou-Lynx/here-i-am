# GOAL-20260824-ai-workbench-wave1 — AI 工作台基础能力波次

> 2026-10-02 暂停收尾：用户因整体计划调整暂停本 Goal。父 Goal 未正式关闭，接续入口见 [工作台暂停收尾](../whiteboard-workstreams/WORKBENCH_PAUSE_20261002.md)。

> 2026-10-01 暂停落点：用户要求到此暂停并合入主 worktree；主 `v3-lab@b2adc44b` 已包含本轮选择性集成源码，104/104 受控路径同哈希，候选分支同 HEAD、无待合并独有提交。源码与文档保留为未提交改动；生产启用评估及减弹窗改造尚未开始。见 [主 worktree 暂停交接](../whiteboard-workstreams/GOAL1_MAIN_WORKTREE_PAUSE_20261001.md)。

> 状态：本地验收完成（UI-T、P4、限定 P5 与 P6 的既定自动 / 真人 Gate 已按最终集成审计收口；生产长任务执行仍 fail-closed，commit / push / 发布均未执行。最终判定见 [2026-10-01 本地验收](../whiteboard-workstreams/GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md)。下方旧进度按各自日期视为历史快照。）
>
> 2026-10-01 同候选 P6 retry Gate 补齐：隔离普通 App `A8A3FF29…9A192C3` 的新公开任务 `b2b1680e…223f6` pending 后唯一 start；代理在真实 completed 终态交付时替换一次本地 error，持久态 failed/retry0 后仅 retry 一次，最终 completed/100%/retry1 且 1–2000 逐行结果精确。两次原生六项清理全 true、pending false，普通关窗、端口释放、数据库完整性通过。仅证明受控本地交付故障的重试路径，不等同真实 provider 故障；父 Goal 的跨包真人 Gate 与生产入口决策仍未完成。见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
> 2026-10-01 已确认启动后的本地故障复验：任务 `7a4aec55…b0034e` 精确入队并唯一条件 start，代理取得 turn 绑定后只注入一次本地 error；最终 blocked/0%、retry0、`runtime_connection_lost`，failed-only retry 条件不成立。原生六项清理全 true、pending false，App 普通关闭和服务收尾成功；这不构成 retry Gate。下一代理候选仅在真实 completed 终态后替换一次交付事件，模拟检查通过、未实跑。P6/父 Goal 仍开放，生产关闭。见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
> 2026-10-01 新单任务受控 503 复验：公开任务 `19bfcd63…59d53` 在 pending/未开始时只启动一次，代理仅对文字 turn POST 注入一次 503；持久态 blocked/0%、retry0、`runtime_start_outcome_unknown`，无结果。原生六项清理全 true、pending false、owner exit 0，但未知 start 不因 DELETE 200 变成已确认终态，应用普通关窗仍保留窗口。本批按异常即停，没有 retry/恢复/取消或新建；retry Gate 与父 Goal 仍不勾选，生产关闭。见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
>
> 2026-10-01 新两任务隔离批次：同一 App 哈希下，新原生 v2 的首条公开任务 `3f620d90…33bc4f` 已完成唯一条件启动、暂停、恢复、取消状态链，取消后终态保留；两次原生关闭回执六项全 true、pending false。第二条 `398e0363…5d13550` 在受控文字故障尚未触发前就启动失败，failed/0%、retry0；原生 final receipt 仍 `cleanup_pending=true`。按异常即停未 retry，用户处理系统确认后的精确四键只读检查均 absent、present_count=0；不回填原生 final receipt。故 retry Gate 与父 Goal 仍不勾选，生产不启用。见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
> 2026-10-01 执行器修复：固定 CLI 来源与每尝试工作根已移到有空间的 C 盘候选目录，原 pin 与第二版原生哈希核验通过。托管 2/2（712 断言）、self-test 95、相邻 Node 39/39；用户处理系统确认后零任务/零模型启动及原生六项清理实跑通过，`cleanup_pending=false`、上游请求 0。旧批次仍因启动失败停止，新的普通入口队列生命周期 Gate 尚未执行，父 Goal 不勾选。详见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
> 2026-10-01 后续批次状态：同一组合候选的首条新公开任务 `35976878…e5b044` 仅执行一次条件 start，启动前 failed/0%、retry0、无 session/turn/结果；按用户设定的异常停止条件，未继续 pause/resume/cancel、第二条 retry 场景或故障注入。失败尝试 CLI 复制截断且 D 盘当时几乎已满；随后 Codex 更新移除固定旧 CLI 路径。截断副本和明确作废的首包 kernel 已清除，验收包及结果保留。此批不构成生命周期 Gate；须先修复固定执行器来源和空间，再用新候选复验，父 Goal 不勾选。详见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
> 2026-10-01 最新组合候选：同一 Windows Debug exe SHA `A8A3FF29…9A192C3` 上，普通短聊零任务、唯一公开任务的 pending→唯一 start→completed/100% 与精确 1–2000 结果、六项原生关闭事实、正常及受控异常退出后重开、应用内 fresh status，以及首次关闭 503 保留窗口、第二次 200 成功退出均已实际通过。隔离 App/Bridge 已关闭。此 Gate 尚未覆盖该哈希的 pause/resume/cancel/retry 和其它包的真人路径；生产仍 fail-closed，父 Goal 完成定义不勾选。精确证据见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。下方同日更早记录为历史快照。
>
> 2026-10-01 跨包组合候选：产品接线已定向并入本地 `v3-lab`，普通入口/队列 53/53、Bridge 82/82、UI-T/P4/P5 组合 69/69 和关键检查 3/3 通过；修正隔离地址后的 Windows Debug exe SHA `A8A3FF29…9A192C3`，源码与包清单见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。新 App 与加载了候选关闭回执的 47832 Bridge 已启动，但输入工具未能发送短句；隔离库仍零任务、无原生清理回执。新哈希的真实短聊、队列全周期、异常退出和六项清理尚待 Gate，生产仍 fail-closed，完成定义不勾选。
>
> 2026-10-01 普通入口正向复验：同一 Debug App SHA `310FC91D…4252` 与隔离 47832 Bridge 的 180 秒适配器，新任务 `b85342a8-3d18-4877-85d9-fadfa974a41e` 标题/目标逐字匹配，pending 状态仅 start 一次后 completed/100%、retry0；唯一 8892 字符结果精确等于 1–2000 每行一数。首代正常关闭、同哈希继代重开后仍 completed/100%，结果哈希与唯一 start request 不变；两代 App 退出、原生 owner 进程 0、隔离端口释放。本次六项原生关闭回执未独立持久化，不能上升为完整清理证明。普通入口正向与完成态恢复窄 Gate 已通过，生产 profile 未切换；父 Goal 的跨包唯一集成候选、组合真人 Gate 仍待，不勾选整体完成定义。详见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。
>
> 2026-09-30 隔离普通入口续验：Debug Windows 候选已将偏好、SQLite、workspace、白板及日志全部导入新数据根，独立 Bridge 47832；最终 exe SHA `310FC91D…4252`。最终窗口短聊成功，唯一公开任务 `7f17962a-0912-46c4-ab36-e484ac4c757d` 标题/目标逐字一致，仍 `pending/0%`。任务创建后的 status→start 点击被自动审批审查拒绝，理由是原入队指令要求等待下一条明确授权；已向用户请求新授权，没有启动、重试或绕过。P6 同候选执行/清理/恢复与 Goal 真人 Gate 仍开放。详见 [普通入口续验](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。下方旧快照按原日期保留。
>
> 2026-09-30 接线候选：`codex/goal1-p6-product-wiring` 隔离 worktree 已补默认拒绝的受限文字执行工厂和普通 Windows 关窗关闭门控；Bridge 36/36、队列 69/69、桌面关闭/Coordinator 31/31、critical 3/3，普通 Windows Debug 编译 exit 0。精确源与产物哈希见 [接线记录](../whiteboard-workstreams/GOAL1_P6_PRODUCT_WIRING_20260930.md)。普通入口仍指向现有用户数据位置，未启动本候选或执行真实任务；须先完成独立数据装配，再做同候选现场 Gate。**P6 与 Goal 1 完成定义仍不勾选**，无 commit/push/发布。
>
> 2026-09-30 集成审计：run11 冻结源码的 UI-T/P4/P5 定向回归 69/69、当前 Bridge 受限 profile/候选适配器 27/27 通过。run11–14 是独立 Debug 入口；普通桌面入口虽注册队列工具，其 Bridge 执行 profile 仍固定 fail-closed。尚需受限能力的普通入口接线、唯一组合候选及受影响真人 Gate，详见 [最终集成审计](../whiteboard-workstreams/GOAL1_FINAL_INTEGRATION_AUDIT_20260930.md)。当前完成定义不因自动回归而勾选。
>
> 2026-09-30 最新：同一 App/Witness 原文件及哈希的 run14 补齐运行中 App 异常退出：首代 App 实际 -1、Node 受控 0，唯一继代保留同一任务 `blocked/interrupted/retry1/result0` 且未自动执行；只在显式恢复一次后得到唯一精确 1–2000 结果，继代关闭后持久完成态不变，五个 native owner 与 batch/Witness/runner 完整清理。见 [run14](../whiteboard-workstreams/P6_R7_RUN14_20260930.md)。这强化了 P6 **隔离入口 Gate**；生产 profile 仍拒绝，父 Goal 所需跨包唯一集成候选及组合真人 Gate 未完成，故本页完成定义暂不勾选。下方 9 月 29 日与旧状态是历史快照。
>
> 2026-09-29 最新：P6 同一 Windows Debug App 哈希的隔离真人入口已覆盖普通短聊零任务、enqueue/status/start、预设失败后唯一 retry 完成与唯一结果、pause/resume/cancel、完成态与取消态重启恢复及两代完整清理，见 [run11](../whiteboard-workstreams/P6_R7_RUN11_20260929.md) / [run13](../whiteboard-workstreams/P6_R7_RUN13_20260929.md)。这关闭的是 **P6 隔离候选生命周期验收范围**；生产 profile 仍 fail-closed，未对 UI-T/P4/P5 不同候选的真人 Gate 作同哈希继承，也未完成父 Goal 的唯一集成候选收口、提交或 push。下方旧 P6 阻断描述为历史快照。
>
> 验收主窗 task/thread ID：`01a032f2-4e1f-7da3-8cbf-08634de1914f`
>
> 创建日期：2026-08-24
>
> B0 基线：`v3-lab@f88537d72d08531252e2050784d71deba36a517f`
>
> 集成目标：`v3-lab`
>
> push / 发布：2026-08-26 用户已明确授权将当前候选与跨设备交接状态同步到 `origin/v3-lab`；该授权只覆盖本次同步，不自动授权后续返修 push、发布或下一 Goal

> 返修恢复源基线：`v3-lab@a4283804ac9f22ce2ce60b5a15a136a626f3c9dc`。恢复控制面提交完成后，三个返修 worker 必须从该新提交创建全新隔离 Worktree；旧 detached Worktree 只作历史证据，不直接续写。

## 目标

当前P6续作（2026-09-12）：v5本机八项网络事件矩阵与完整回收实际通过（5019bbd0、exit0、pendingfalse），原同步负控false保留；既有失败实例均已独立回查或清理。19/19、自测233、真实文件等待22断言与独立核对通过。此结果不等于真实CLI持续隔离或生产接线。真实账户请求0，生产拒绝，账户/停止接线及App/真人Gate仍待，P6与Goal1未通过。见[R7](../whiteboard-workstreams/P6_R7_EXECUTION_BOUNDARY_PLAN.md)。R6专用登录与固定真实回合仅为旧pin历史证据，见[R6](../whiteboard-workstreams/P6_R6_TEXT_GATE_PLAN.md#认证状态与当前剩余)。

从同一 B0 隔离交付 UI-T、P4-T1/T2、P5、P6，由 W0 验收主窗主动回收、审计、逐包选择性集成，形成唯一 Windows 候选；只有自动 Gate 和真人 Gate 全部满足后，本 Goal 才能完成。

W0 是验收主窗，不是 worker，不计入 worker 并发数。任一时刻最多运行 3 个 worker。

2026-08-26 用户明确确认恢复本 Goal，但本轮授权只覆盖 UI-T、P4、P6 的返修、隔离交付、主窗审计、逐包本地集成、组合自动验证与单一 Windows Debug 集成构建。P5 不派发；最终真人 Gate 不启动；W4 `0/18`、push 与发布继续阻塞。三包完成后，本 Goal 仍须回到阻塞态等待 P5 与完整真人验收，不得以本轮自动证据或集成构建宣称完成。

2026-08-26 用户再次明确要求继续推进真人验收。主窗复核发现 P5 历史交付只覆盖 Memory Card / User-truth 搜索测试，生产桌面 Runtime 尚未接入真实 Persona 与 Dreaming Episode / Fragment / Saga；同时本机不存在 `fad8b736` 的 exact 验收产物，当前 HEAD 已前进到 `9237270e`。因此本 Goal 从阻塞态恢复，先在隔离 Worktree 返修 P5；通过审计与组合 Gate 后重建一个新的唯一 Windows 候选，再启动完整真人 Gate。既有 `fad8b736` 自动证据继续保留为历史证据，不代表新候选。

## 进入条件

- [x] `v3-lab` 已包含 Phase 1 Runtime、受限搜索、Artifact Core 最小恢复执行器及既有 Windows 真人验收事实。
- [x] 协作协议、Roadmap、Goal 模板、项目状态和 DEVLOG 已固化为 B0 控制面提交。
- [x] 用户已确认本 Goal 方向及本页六项修订。
- [x] 用户最终授权派发。

## 完成定义

- [x] UI-T 在 `DesktopWorkspaceTheme` 补齐 `snackBarTheme`、`inputDecorationTheme`、`outlinedButtonTheme`、`filledButtonTheme`、`textButtonTheme`、`iconButtonTheme`、`dialogTheme`、`popupMenuTheme`。
- [x] UI-T 按 `docs/development/whiteboard-workstreams/COLOR_LEAK_HANDOFF.md` 的九项主题 / 泄漏覆盖路径逐项回归并留下证据；不得改成调用点逐个补色，不迁移手机视觉。
- [x] P4-T1/T2 完成创建卡片、编辑正文、标签、移动、缩放和移除摆放，并让人工入口与 Runtime 工具复用同一套 provider-neutral `DomainCommand` / `Receipt` / `Undo` 语义。
- [x] P4 通过退出画布或应用、重新打开后的持久恢复 Gate：对应 `DomainCommand`、`Receipt` 与可用 `Undo` 必须从持久层恢复并保持结果一致；仅进程内或 ViewModel 内恢复不算通过。2026-09-05 已同时通过冲突拒绝与同 token 重试恢复。
- [x] P5 将人格与长期关系 Memory V3 以只读 recall/context 接入桌面 Runtime，命中、空结果、失败和越权路径诚实；不得写 User-truth，不得自动生成记忆卡，不得由模型 payload 扩权。2026-09-06 按用户确认的“自动权限拦截 + 真人只读回复”组合口径通过，限定手机 Dreaming 只读来源，不扩大为全量跨端事实能力。
- [x] P6 支持 enqueue / pause / resume / cancel / retry / status，并通过重启后的诚实状态恢复；普通短 turn 不创建 TaskRoom，TaskArtifact 上板不在本 Goal 开放。2026-10-01 同一隔离普通入口候选补齐受控 failed→唯一 retry→completed、精确结果及六项清理；生产启用另作决定。
- [x] 四个 worker 包分别提供边界内 commit、定向测试、changed-file analyze、`git diff --check`、handoff 和未完事项。
- [x] W0 一次审计并集成一个工作包，完成组合回归、唯一 Windows Debug 构建和候选记录。
- [x] 真人完成 UI 九项覆盖路径、P4 通用卡片操作及持久 Undo、P5 只读权限、P6 队列恢复验收。UI-T/P4/限定 P5 保留既有已接受 Gate；P6 同候选普通入口完成新 Gate，跨包影响按最终审计做最小复核，不将白板和手机 Gate 冒称为新候选同哈希重跑。
- [x] Goal 状态页、项目状态、DEVLOG、Roadmap 与 i closeout 收口；既有 push 不替代真人 Gate，生产启用及后续 commit / push / 发布另按各自授权执行。

## 非完成范围

- W4 Bilibili 匿名字幕严格 Gate 维持 **FAIL / 0/18**，登记为非阻断红灯；本 Goal 不实现登录 Cookie、ASR、字幕 provider 修复，不得伪称通过。
- 不做 P4-T3/T4 的建白板、批量摆放、分组、连线、搜索整理扩展。
- 不做 P7 / P8 / P9、Artifact Core 生产 renderer / adapter、TaskArtifact 上板。
- 不扩张通用 Orchestrator / Agent 树，不把普通聊天包装成长任务。
- 不迁移 Android Companion 页面、信息架构或“春雨昼眠”视觉。
- 不因本 Goal 自动授权新增 push 或发布，不绕过真人 Gate。

## 派发与并发顺序

1. 本轮恢复控制面提交后，从同一新基线同时启动 `UI-T`、`P4`、`P6` 三个隔离返修 worker；旧 detached Worktree 不续写。
2. W0 保存各自 task/thread ID、host、分支、Worktree 和派发基线；同时运行的 worker 不超过 3 个。
3. P5 不派发，保持等待用户；UI-T / P4 / P6 拥有路径必须互不重叠，共享 schema、依赖和生成文件仍由 W0 裁决。
4. W0 主动等待和回收，不把 worker 返回等同于通过；一次只审计、集成一个工作包。
5. 三包集成后，只构建一个 Windows Debug 集成候选；本轮不组织最终真人验收，构建成功也不关闭 Goal。

## 历史工作包状态（2026-08-26 首轮真人失败）

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UI-T Theme Integrity | 独立 Codex 任务 + Worktree | `01a032ff-9ef7-7b80-a542-6476986ef270` | B0 `f88537d7` / 派发 `aa670c07` | detached / `C:/Users/ExampleUser/.codex/worktrees/8e63/here-i-am` | 已构建（真人失败，等待返修） | `05825ad199c546504876fe19703e429983d5f5a2` | `docs/development/whiteboard-workstreams/UI_T_THEME_INTEGRITY_HANDOFF.md` | diff 与 B0 源码八项主题入口已审计；集成 `c6c401d5` | 原 W0 `2/2`；返修新增真实 SnackBar overlay、聊天输入与编辑器对齐回归，相关组件 / 相邻测试 `106/106` | **失败**：SnackBar、聊天窄内框和回复期间编辑通过，但第三轮粘贴再次失效；Typeless / `Win + H` 无法输入；消息右键菜单仍泄漏白紫色主题 | 返回 UI-T 返修粘贴 / Windows 语音输入与聊天 Overlay 菜单主题，重建候选后重验 |
| P4-T1/T2 Domain Commands | 独立 Codex 任务 + Worktree | 初始 `01a032ff-9eec-7bb2-8214-071c317beba3` 上下文耗尽；首替 `01a03328-b5d1-74c2-9902-b3b223bdf89f` 停滞停止；当前 Sol `01a03341-4e64-7cb1-a4a4-c9d6c30a7ca6` | B0 `f88537d7` / 返修起点 `5ec47a94` | detached / `C:/Users/ExampleUser/.codex/worktrees/6b44/here-i-am` | 已构建（真人失败，等待返修） | `5ec47a94` + `86eec0bf`；本地集成 `3b85d1bc` + `0b700528` | `docs/development/whiteboard-workstreams/P4_T1_T2_DOMAIN_COMMAND_HANDOFF.md` | 六命令、统一 facade、真实 Drift action reader、hash conflict、幂等及 bounded Undo 审计通过 | W0 `24/24`；本机实验 Runtime 已开启，capabilities 11 项与 Codex 模型目录可读 | **失败**：退出并重开后无法恢复 Undo，未通过真实持久恢复 Gate | 返回 P4 修复退出 / 重开后的 DomainCommand、Receipt 与 Undo 恢复，再重建候选验收 |
| P5 Memory V3 Context | 独立 Codex 任务 + Worktree | `01a032ff-9f0e-7e91-a5cc-adedb4637148` | B0 `f88537d7` / 派发 `aa670c07` | detached / `C:/Users/ExampleUser/.codex/worktrees/9119/here-i-am` | 已构建（真人失败，等待返修） | `fc01c11789d1b26b88f5c80635fd45ade92692b4` + handoff `e477a326` | `docs/development/whiteboard-workstreams/P5_MEMORY_V3_CONTEXT_HANDOFF.md` | 生产注册、权限边界与新增测试已审计；W0 校正过期测试接线与确定性失败注入 | W0 `22/22`；本机实验 Runtime 已开启，capabilities 11 项与 Codex 模型目录可读 | **失败**：当前只读工作电脑本地数据库，未接入真实人格与长期关系 Memory V3 | 返回 P5 接入真实只读人格 / 长期关系上下文，并重验命中、空结果、失败与拒绝扩权 |
| P6 Long Task Queue | 独立 Codex 任务 + Worktree | `01a03311-bee4-7702-8ed1-df21ba9723fb` | B0 `f88537d7` / 派发 `fa511db5` | detached / `C:/Users/ExampleUser/.codex/worktrees/4529/here-i-am` | 已构建（真人失败，等待返修） | 初交 `722594a8` + `a77b5a96`；返修 `1dc8c33b` + `46f95b20` | `docs/development/whiteboard-workstreams/P6_LONG_TASK_QUEUE_HANDOFF.md` | 返修审计通过；集成 `52ada12b` / `7f305f63` / `77575613` / `731b6d04` | W0 TaskRoom + 普通聊天 `53/53`；本机实验 Runtime 已开启 | **失败 / 不可验收**：只有底层队列服务，没有生产 UI 或 Runtime 入口，真人无法触达生命周期与重启恢复 | 返回 P6 补生产可达入口，再重验 enqueue / pause / resume / cancel / retry / status 与重启恢复 |

固定状态枚举：`待派发 → 进行中 → 等待用户 → 已交付 → 已审计 → 已集成 → 已构建 → 真人通过`；终止状态为 `失败`、`取消`、`被取代`。

## 本轮返修工作包状态

| ID / 名称 | 执行方式 | task/thread ID | 基线 | 分支 / Worktree | 状态 | 交付 commit | handoff | 主窗审计 | 自动 Gate | 真人 Gate | 下一动作 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| UI-T Theme / Input Integrity | 子 Agent + 隔离 Worktree | `01a03d21-60e2-7801-9255-b03091c07836` (`/root/goal1_ui_t_repair`) | `7f7af225` | `codex/whiteboard-w0-goal1-uit-repair` / `D:/here-i-am/.goal-worktrees/goal1-uit-repair` | 真人通过 | `cbe09fd5` + `cc255ab4` + `fe62c6a7`；集成 `6209798c` + `93cef039` + `7e78a18a` | `docs/development/whiteboard-workstreams/UI_T_THEME_INTEGRITY_HANDOFF.md` | 通过；生产 host scope 与实际 toolbar Overlay 证据链经两轮返修；rollout 核对为 Terra medium | W0：单包 `12/12`；三包组合候选 `108/108`；changed-file analyze 无新增问题；diff check 通过 | 通过；系统粘贴、回复期间编辑、第三轮粘贴、`Win + H` 与右键菜单主题均成立。Typeless 2.3.1 完全未向 Flutter 输入框注入并提示复制转写，归档为 Flutter Windows UI Automation 上游兼容红灯，不伪称产品已支持 | 合并后候选已重建；UI-T 结论保留，进入 P4 |
| P4-T1/T2 Persistent Undo | 子 Agent + 隔离 Worktree；后由窄返修 Goal 单 W1 接管；R14–R20 使用独立 Sol high Worktree | 原 `/root/goal1_p4_repair`；返修 `/root/p4_reachability_worker`；R14 `01a04c96-d704-7462-95a7-8ee4495ea540`；R15 `01a04d25-9ba3-7f21-afae-dc481ba27b14`；R16 `01a04d7d-d383-79b2-a7ce-865f80761452`；R17 / R20 `01a04de1-94ba-7c63-b685-0e88301b9468`；R18 `01a05185-dbe9-7313-8e2c-d02fd40f051e`；R19 `01a052f1-da65-7ad2-8f44-15a9ead2d80f` | 原 `7f7af225`；返修 `69ddf56b`；R14 `7fa6cbb9`；R15 `884dcd80`；R16 `a36e5236`；R17 `66017099`；R18 `2edaf17a`；R19 `2ed4b015`；R20 `722a646d` | 历史 `D:/memex/.worktrees/p4-production-reachability-r1`；R14 `.../cf72/memex`；R15 `.../3c06/memex`；R16 `.../8ad3/memex`；R17 / R20 `.../8dd4/memex`；R18 `.../82ae/memex`；R19 `.../7757/memex` | 真人通过 | R19 候选 `722a646d` 真人两次零写失败；R20 worker `591caf3a + 3c6265c7`、handoff `cdf01946`、集成 `3674548b..03c2afd9`；最终候选 `e77045fa` | `docs/development/whiteboard-workstreams/P4_PRODUCTION_REACHABILITY_REPAIR_HANDOFF.md` | R20 两份复审无 P0/P1；最终 UI、DB、Receipt / Undo 与完整重启结果一致 | R20 主线 Runtime + coordinator `59/59`、production route `8/8`、critical `3/3`、analyze clean、diff check PASS；候选已指纹化 | 六命令、remove 只删 BoardItem、持久 Undo、冲突拒绝 / 可重试与重启稳定全部通过 | 进入 P5 真人 Gate |
| P5 Memory V3 Context | 子 Agent + 隔离 Worktree | `/root/goal1_p5_repair`；独立复审 `/root/p5_delivery_review` | `9237270e` | `codex/whiteboard-w0-goal1-p5-repair` / `D:/memex/.worktrees/goal1-p5-repair` | 通过（限定范围组合验收） | 交付 `8dfb95c8` → `51f4c3d6` → `bd2b0cd3` → `a404d212` → `72462d88` → `53b969b5`；集成 `bb12b279` → `d78c2453` → `0d5dc147` → `3bdfab62` → `29bb8b6f` → `dc34a0c9`；人格返修 `6b0e6d15 + 4ba05b11` | `docs/development/whiteboard-workstreams/P5_MEMORY_V3_CONTEXT_HANDOFF.md`；人格返修见下节 ；当前手机候选/收口见 `P5_PHONE_READONLY_INTEGRATION.md` | 通过；两轮安全复审关闭混合 provenance 漏验、召回文本伪造 host delimiter、Dreaming empty/unavailable 误报与空字符串 evidence 缺口；真实 Drift、权限和移动 Companion 兼容边界已复核 | worker 受影响组合 `76/76`；主窗最终交付独立组合 `121/121`、exact 候选九文件 Goal 组合 `112/112`；人格返修专项 `37/37` + 相邻 `49/49`、critical `3/3`、analyze 与 diff check 通过 | 2026-09-06 P5 通过：人格、单例历史基本相符、empty/到期 unavailable；权限为用户确认的 4/4 自动拒绝 + 真人只读回复，不称真人实际 tool 拒绝 | 进入同候选 P6 队列验收 |
| P6 Long Task Queue Reachability | 子 Agent + 隔离 Worktree | `01a03d22-2ce6-7e32-8f9f-d630760be614` (`/root/goal1_p6_repair`) | `7f7af225` | `codex/whiteboard-w0-goal1-p6-repair` / `D:/here-i-am/.goal-worktrees/goal1-p6-repair` | 部分通过，P6 返修待执行 | `21b74f42` + `5a160958` + `7885b5be`；集成 `c6fa8e0d` + `8324c782` + `97153013` | `docs/development/whiteboard-workstreams/P6_LONG_TASK_QUEUE_HANDOFF.md` | 历史队列状态机/会话 scope 自动审计保留；新审计发现缺真实执行器及用户指定 task_id 强绑定，不能视为完整执行生命周期或指定目标防扩权通过 | W0：queue/tool + TaskRoom `55/55`，production coordinator + 普通聊天 `30/30`，合计 `85/85`；三包组合候选 `108/108`；changed-file analyze 零问题；diff check 通过 | enqueue/pending、指定 ID status、App 重启后 pending 保留均通过；P6 整体未通过 | 返回现有 P6 包补指定目标绑定和真实执行器；修复后再验取消/执行生命周期/运行中重启 |

## Gate 与失败路由

### P5 本次人格返修（2026-09-05）

- 原 `e77045fa` 首轮回复暴露“宿主上下文没有给出关系标签”的实现视角，Lynx 判人格口吻不合格。初见日期已包含在固定身份提示中，因此不能据此认定 Dreaming 真实命中；P5 其余真人 Gate 尚待。
- 用户明确确认 writing block `48317` 的清洗稿并要求继续落地。只采用最后清洗版，不恢复长串跨端来源假设、余额常量、状态码禁语或权限流程到人格正文。
- 执行包 `P5-Persona`：子 Agent `/root/p5_persona_implementation`，Terra medium；基线 `455be35e114a6b34f30388938e3177abbc42009f`；分支 `codex/whiteboard-w0-p5-persona-cleanup`，Worktree `D:/memex/.worktrees/p5-persona-cleanup`；代码 `6b0e6d15`、证据 `4ba05b11` 已快速集成 `v3-lab`；状态 **人格口吻真人通过，提示词冻结**。
- 独立复审 `/root/p5_persona_review` 无 P0/P1；worker 专项 `37/37`、主窗 P4/P6/provenance 组合 `49/49`、changed-file analyze、关键守门 `3/3` 与 diff check 通过。原控制文档 staged blob 全部保持原值。
- 拥有路径：独立桌面 prompt、relationship context / coordinator 的最小接线、相关测试与 `docs/development/whiteboard-workstreams/P5_PERSONA_CLEANUP_HANDOFF.md`。主窗单独维护控制文档；P4 / P6 工具权限、数据 schema、手机端行为保持现状。
- 主窗已审计 commit / diff 与自动 Gate，并在干净隔离 Worktree 构建唯一新 Windows Debug 候选（196.2s）；构建后工作树仍干净。旧应用正常关闭，新候选按 exact 路径启动。先复验自然人格表达，再继续真实关系 recall / empty / unavailable / scope / 扩权拒绝；自动测试不能替代实际回复与 Lynx 的口吻判断。
- 主窗依既有 Computer Use 授权从真实浮动聊天界面发送两轮测试：身份 / 关系问句，以及对列举全名过于正式的普通质疑。两轮均正常完成并恢复可发送状态；回答未再次解释宿主上下文，第二轮承认过于正式且未转为情绪安抚，但仍复述身份 / 关系。该现场最初仅记 **Agent 代操作点验**，后续用户结论见下条。
- 2026-09-05 Lynx 对上述实际回复与残余生硬点明确确认“可以，就这样吧”：**P5 人格口吻通过，当前清洗稿不再调整**。该确认不扩大为 Dreaming 命中、空结果、失败、scope、只读拒绝或 P5 整体通过；不因主窗个人润色偏好继续返修，也不新增中文口吻复验前置条件。
- 输入工具的 Unicode 注入未落入 Flutter 输入框，第一次逐键输入又遇到中文 IME；主窗仅清除自己未发送的草稿并切换英文输入，核对完整问句后才发送。第二轮按英文问句回复英文，尚不能替代中文日常交流体验。第二轮 04:40:34–04:41:29 UTC 首次观测完整回复，约 55 秒是观测上界，不是精确模型耗时；Bridge 健康并不等价于实时 turn 状态。

### P5 真实 recall 前置核对（2026-09-05）

- 当前运行 App 路径、主线 HEAD 与 exe / kernel SHA-256 均重新核对为上文 exact `4ba05b11`，没有切换或重建候选；UI 仍显示已通过人格口吻的两轮回复。
- 仅读取当前桌面应用设置中的账户 / 角色字段，当前为 `白板工作台` / `i`。依据 `AppDatabase._openConnection` 与当前 drift_flutter 的 Windows Documents 解析定位唯一对应数据库；同目录没有第二份 `memex_local_*.sqlite`。Windows 文档目录有重定向，未复用猜测路径。
- SQLite 以 `mode=ro` + `PRAGMA query_only=ON` 查询：`persona_chat_messages=275`，其中 i / chat / 非 TaskRoom 为 `116`；`memory_fragments=0`、`memory_episodes=0`、`memory_sagas=0`。白板 `15`、Card `549` 与当前应用概况一致；未读取聊天正文，未 checkpoint、备份、导入或修改数据库。
- 生产接线为 `WorkbenchRelationshipContextAssembler.production(database: AppDatabase.instance)` → 当前本地 DB 的 Dreaming 查询；本入口未连接手机或 iCore 既有长期记忆。当前没有可审计的真实命中样本，固定 persona 与 recent-8 不能替代 Dreaming 证据。
- 子 Agent `/root/p5_persona_review` 完成代码只读核对：有效命中还必须满足 Episode / Saga → Fragment → i 主聊天的完整 provenance。Workbench 没有持久 recall trace；仅在获得 exact provider thread ID 且实际 App Server read 返回 input 时，才可能补本轮注入证据，不扫描其他 Codex 会话来猜测。
- **结论：真实命中 Gate 前置阻塞，不是产品空结果 Gate 通过。** 本次前置核对未发送新模型问句、未运行 batch / episode / saga 生成、未切账户、未读取手机或其他账户数据。Lynx 随后确认继续只读接入窄返修；不自行导入、同步、迁移或新建记忆，不新增人格规则。其余 P5 与 P6 保持待验。

### P5 既有来源接入审计（2026-09-05）

- 窄返修已获授权，主窗与 Terra medium 子 Agent `/root/p5_existing_memory_route_audit` 完成独立只读审计；报告：`docs/development/whiteboard-workstreams/P5_EXISTING_MEMORY_SOURCE_AUDIT.md`。
- iCore 实测在线（协议 `0.1` / schema `4`），当前只有聊天 change feed 等能力，没有 Memory V3 / Dreaming 读取接口。手机 Voice Gateway 通过一致快照读取近期聊天与 User-truth，尚未投影 Dreaming；也不能复用其 Voice session 或较宽的 active-character 过滤来替代 P5 边界。
- Lynx 已连接 `SM-S9110` 并暂停 App；2026-09-05 18:55:44 +08 只读一致快照检查通过：schema `60`，Fragment/Episode/Saga `1215/377/11`，严格有效状态与完整来源闭包资格 `1166/342/2`。临时 probe fixture `11/11` 保留，数量不代表特定 query 或 Runtime 命中；未查询/输出正文，快照已删除，手机 App 已重新打开。
- 来源前置条件已解除；主窗与 `/root/p5_live_readonly_seam` 确认现有手机运行中没有 Dreaming 读取端点。Lynx 随后明确同意新增手机只读查询、新 APK 与桌面 USB 按需接入，不导入桌面、不同步至 iCore、不生成记忆；新增范围已授权。
- 主窗从 exact `4ba05b11` 建立 `.worktrees/p5-phone-readonly` / `codex/whiteboard-w0-p5-phone-readonly`，按互斥文件派发手机服务（Astra high）、桌面接入与两端 UI（Terra medium）三包；详见来源审计的派发表。保持 persona 冻结；构建手机候选时保留主工作区已安装版本的未提交 BLE 修复，最终自动/真人 Gate 分别记录。
- 本轮未改生产代码、未安装、未创建端口转发、未改人格或重建候选；P5 真命中 Gate 尚未开始。

| Gate | 通过条件 | 失败返回 |
|---|---|---|
| UI-T 主题完整性 | 八个 ThemeData 子主题齐全，handoff 九项覆盖路径无桌面主题泄漏 | UI-T |
| P4 领域操作 | 人工 / Runtime 等价命令、receipt、冲突、幂等、整批撤销成立 | P4 |
| P4 持久恢复 | 退出 / 重开后 DomainCommand、Receipt、Undo 可恢复且状态一致 | P4；不得降级为“已完成但有已知限制” |
| P5 权限 | 命中 / 空结果 / 失败诚实，写入和 payload 扩权均被拒绝 | P5 |
| P6 队列 | 全生命周期与重启恢复成立，普通聊天不产生 TaskRoom | P6 |
| 组合候选 | 定向回归、changed-file analyze、组合回归、diff check、Windows Debug 构建通过 | 对应 worker；W0 不临时重做功能 |
| 真人验收 | 唯一候选按下节逐项通过 | 对应 worker 返修后重新集成 |

## 2026-09-07 P6-R3 执行隔离复核

用户要求继续，主控完成三组当前 CLI 配置追加实测与独立只读接口审计；全部仍有外层工具目录，未取得启用 text-only profile 的证据。Node 32/32，原拒绝门控、App/等待任务保留；详见 [隔离审计](../whiteboard-workstreams/P6_R3_EXECUTION_ISOLATION_AUDIT.md)。改走纯文本模型 API 涉及接入/可能的计费变化，待用户确认后再实施；未改执行后端、未构建或真人通过。

## 2026-09-06 P6-R2 返修派发

用户确认“派发吧”，在本 Goal 内从 `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b` 隔离派发；当前主窗 `01a03e4a-e594-7b32-b3da-25705b8e1eb5`。A 负责指定任务强绑定，B 负责真实事件驱动执行核心，C 只读审计完成后由 C2 补专用 Runtime profile 门控；完整路径、模型、接口和回收进度见 [P6-R2 计划](../whiteboard-workstreams/P6_R2_REPAIR_PLAN.md)。

2026-09-07 第一轮代码已本地集成，主控组合回归 122/122、Bridge 31/31、9 文件 analyze 通过，非新候选或真人通过。text-only 探针的初次“零工具”判定已因漏查 `input.additional_tools` 撤回；实际仍有工具，生产执行保持拒绝，不继承普通 Runtime、不启动原等待任务。本轮不构建/部署、不修改真实 DB、不 push；P6 及 Goal 1 未完成。

## 真人验收

- 2026-09-29 **P6 隔离候选生命周期入口通过，父 Goal 保持活动**：App SHA `7b324121…9f92` 的 run11 验同任务 pause/resume/cancel 与取消态重启恢复；完全同哈希 run13 验普通短聊零入队、唯一任务预设失败→唯一 retry→completed/100、精确 1–2000 唯一结果及完成态重启恢复。run12 槽位拒绝发生在 App 前、未产任务；run11 旧槽位已原样归档。两批成功运行的两代窗口、原生 owner、Witness 和 runner 均有实际退出与清理回执；隔离候选 Gate 不等于生产开闸或父 Goal 唯一集成候选 Gate。见 [run13](../whiteboard-workstreams/P6_R7_RUN13_20260929.md)；未提交、推送或发布。

- 2026-09-06 **P6 App 重启后 pending 保留通过，后续写入转返修**：App 新进程 `11748`（21:37:58 +08:00）替换上一轮 `28892`，原候选两项 SHA 一致；指定 ID 重查回显与只读 DB 均 pending/0/retry0，`updated_at=1788699879844`、队列元数据及产物/决策计数不变。此项只证明等待记录持久性，不覆盖运行中恢复。取消预审发现动作/会话授权未绑定用户指定 ID，暂缓写入真人 Gate；待现有 P6 包补目标绑定及真实执行器，不伪造状态或用实际误取消探测。返修尚未实施，父 Goal 不关闭。

- 2026-09-06 **P6 指定 ID 的 status 样例通过**：用户回复等待中、0%、重试 0；主窗只读 DB 核对同 ID 的相应字段、队列元数据及产物/决策计数与入队基线一致，updated_at 仍为 `1788699879844`；候选 exe/kernel 指纹一致。下一步正常退出重开后再查该 pending 任务，仅验证等待态持久性，不替代运行中恢复。执行器接线缺口仍待补，P6/父 Goal 未通过。

- 2026-09-06 **P6 首个 enqueue 样例通过，执行接线有缺口**：指定任务 `fc91503a-0e59-4f7f-a480-14215e67cb05` 在只读 DB 中为 pending/0、persona:i、workbench_runtime，产物/决策 0，与用户提供及 Computer Use 核对的回显一致。当前只有持久队列控制，没有消费该队列的真实执行器，不能据此推进/通过执行层暂停恢复、重试和运行中重启。先验同 ID status 与 pending 重启持久性，再补执行接线；不改 Goal 定义或伪造 running/failed。P6 与父 Goal 仍未通过。

- 2026-09-06 **P5 收口通过，进入 P6**：新有效手机会话中，用户提交限定手机记忆的写入请求，实际回复明确只有只读权限、未保存标记且未执行其他操作。Computer Use 核对同轮回执 available 4/6/0 与原候选 SHA 一致；配套 4/4 隔离拒绝测试按用户已确认组合口径判定权限通过，不称为真人实际 tool-call 拒绝。人格、单例历史基本相符、真实 empty 和自然到期 unavailable 证据保留边界；不新增 UserRhythm/全量时效 Gate。下一步同候选从 P6 enqueue/pending 开始，P6 与父 Goal 尚未通过。

- 2026-09-06 用户在主窗明确解释并询问组合验收方式后回复“继续”，确认权限 Gate 采用“自动验证底层拦截 + 真人确认只读回复”。既有四组隔离自动拒绝证据保留，不称为运行候选真人调用；真人尚需在有效手机只读会话中提出一条非私人记忆写入请求，确认如实未保存且不执行替代写入。当前会话已过期，USB 与转发正常，等用户手动重连后执行；不新增产品诊断入口，P5/P6 仍未通过。

- 2026-09-06 权限测试准备：相关源码/测试与 P5 候选 6/6 文本一致，四组隔离自动拒绝测试 4/4 通过；正常 UI 无法构造错配 scope 或未知写工具/自授 payload 请求，未取得这几项候选真人拒绝证据。主窗提出“自动测试证明底层拦截 + 真人确认只读回复”的组合方案，**待用户确认，尚不改变现有 Gate**；详见 `P5_PHONE_READONLY_INTEGRATION.md`。不新增产品诊断入口或重建候选，P5/P6 保持未通过。

- 2026-09-06 P5 手机真实空结果样例通过：用户单独发送纯小写随机标记，候选最近读取回执为 `phone_v3_live/empty`、Episode/Fragment/Saga `0/0/0`，采样 `2026-09-06T11:25:36.190868Z`，实际答复未编造经历。Computer Use 核对时授权已自然到期，最后查询与当前连接状态分开记录；exe/kernel 再核对与 P5 整合记录一致。继续 scope、写入与 payload 扩权拒绝，不扩大为 P5/P6 整体通过。

- **当前 P5/P6 实际验收候选**：persona 基线 `4ba05b11` 加已记录的手机只读接入源，`.worktrees/p5-phone-readonly/build/windows/x64/runner/Debug/memex.exe`；exe `bd7b06fe…` / kernel `28ed9bca…` 的完整 SHA 与双端 manifest 见 `P5_PHONE_READONLY_INTEGRATION.md`。2026-09-06 P5 已按限定来源与组合权限方式通过；沿用该候选进入 P6，不重建或继承不同产物 Gate。手机近期聊天、结构化事实与 UserRhythm 未接入，是否扩展另行决定。

- **历史人格口吻候选**：exact `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`；干净隔离构建产物 `.worktrees/p5-persona-cleanup/build/windows/x64/runner/Debug/memex.exe`，exe SHA-256 `9A5D118EE24B7111952D3DEE27CEBD443AE30CCE550D5C0F814F353C437E5B76`（1,166,336 bytes），kernel SHA-256 `3B15DD72B4EA46C6C125116E6AB87A4765A996EB90B55B44AFF7C7F5BFB279F8`（141,849,120 bytes）。该候选仅保留已获确认的人格口吻证据；手机真实 recall 使用上条 P5 接入候选，不再称此为当前唯一候选。
- **P4 已通过候选**：exact `v3-lab@e77045fafebdc6d19f7a00ae4b2eb98e452fd5f8`；exe SHA-256 `BE3BE7A7037327C735883998C430D02C6CC9373504202D773B76AFFFE0C11CB9`，kernel SHA-256 `0CCDAE9E95572A9A37B1AF21BA634D653BBBBE85DB680342B644E7387A1367C2`。P4 真人证据保留；该候选的 P5 首轮人格失败，不再用于后续 P5 复验。
- **上一唯一真人候选**：exact `v3-lab@1f77633a7f4d17d0601bee76a5c641966c9149b5`；正文与标签 Gate 通过后，移动在首次白板工具调用前超时且零写，候选已冻结，只保留失败证据。
- **上一失败候选**：`v3-lab@7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1` 的人工六类操作通过，但 Runtime create 首项暴露 unsafe ID、不可见 `(0,0)` 落点和快捷库幽灵 placement；exe `94F08DB2...A04E2787`、kernel `16C63D62...2475D81`，旧 PID `34688` 已停止，只保留失败证据。
- **更早失败候选**：`526db23840d68df99beec09b055cc61c653ebcd4` 因编辑态滚动条、Delete / Backspace 抢占和正常新卡 full editor 通知失败而作废；exe `01ECAE79...DD16`、kernel `E902EFE1...141F` 只保留失败证据。
- **更早失败候选产物**：`77949971` 的 `memex.exe` SHA-256 `830D10BB1485A496FC0476E52E17412FD49B08859669A0AA96E16CB797A5EB33`；`kernel_blob.bin` SHA-256 `EA4C172D11C9B46D465ECBA8F00E9BB0683B1008BF883355B271E77F9D74A10F`，只保留失败证据。
- **失败候选产物**：`30a73ce3` 的 exe `930CA889...E252B` / kernel `5E6E8DF1...9FB3` 与更旧 `53d2dc91` 一并只保留为失败证据。
- **失败候选历史自动证据**：Runtime `10/10`、原子恢复 `9/9`、production route + conversation `25/25`、Persona 真实发送 `1/1`、核心组合 `67/67`、相邻 `107/107`、关键守门 `3/3` 均曾通过，但真实 production route 的双击编辑视觉 / 标题与 active viewport 没有被覆盖，不能作为第八轮修复后的 Gate 证据。
- **UI-T 真人已用候选源码**：`v3-lab@45f4d94820ef142d0594d2c5e8d34e8d130a2279`；它包含 UI-T / P4 / P5 / P6 全部返修与当时控制状态。远端与本地后续提交合并后，该提交只保留为 UI-T 证据，不再是继续 P4 的当前候选。
- **UI-T 真人已用候选产物**：干净 detached 验收 Worktree 的 `build/windows/x64/runner/Debug/memex.exe`；exe SHA-256 `1CB91033582A4CEE7D2021B5F934CF9E00033E4A192CC72B6C88E5CFB5575EFA`，`kernel_blob.bin` SHA-256 `30615304FFDA9BAC38E19A3B7D1823CEA32D7EEEF4FA02EC21B64B0851D56BD7`。
- **该候选自动证据**：P5/P6/Companion 独立组合 `121/121`；exact 候选九文件 Goal 组合 `112/112`；关键守门 `3/3`；P5 changed-file analyze 无问题，diff check 通过；Windows Debug 构建成功。Bridge `/v1/health` 正常，experimental Runtime 11 项能力与 Codex 模型目录可读；该候选窗口已用于 UI-T 真人 Gate。
- 2026-08-27 UI-T 真人复验：真实系统剪贴板连续三轮、回复期间编辑、Windows `Win + H` 与消息右键菜单主题均通过。Typeless 2.3.1 在回复结束三秒后对全新短句仍完全不向输入框写入，并提示复制转写；没有出现闪现后被应用清除或自动发送。结合 Flutter 上游 [#182876](https://github.com/flutter/flutter/issues/182876) 的同类 Windows UI Automation / editable provider 缺口，判定为第三方无障碍直写与 Flutter Windows 的外部兼容限制。UI-T 按本 Goal 范围真人通过；该限制作为非阻断红灯保留，不得写成 Typeless 已受支持。
- 2026-08-27 阶段断点：用户在 UI-T 收口后暂停真人验收，以先审计并同步已经分叉的 `origin/v3-lab`。P4 尚未开始；同步、合并和候选复核完成前，不继续使用现有候选推进 P4/P5/P6，也不把本次暂停写成 Gate 失败。
- 2026-08-27 全局同步收口：`origin/v3-lab@53c9c46b` 的 Voice V3–V9 更新经路径、语义与授权边界审计后已本地合并；Gateway `87/87`、iCore `29/29`、通话生命周期 `14/14`、相关 analyze 与关键守门均通过。远端安装器未执行，未 push。由于当前 HEAD 已包含 `45f4d948` 之后的 iCore、通话与 Voice 更新，继续 P4 前须从合并后 HEAD 重建并复核唯一候选。
- 2026-08-28 P4 真人复验第 1 段：用户在可见候选中通过直接入口新建普通卡片，编辑内容并添加 `p4验收` 标签，随后完成移动与缩放；全程无卡顿。用户入口基础路径通过，尚未执行 Runtime、移除、退出 / 重开、Receipt、Undo 与冲突路径。
- 2026-08-28 P4 真人复验第 2 段：在白板真实打开且聚焦的前提下，用户两次从桌面聊天请求创建并调整卡片；第一轮错误尝试寻找浏览器工具后由用户中断，第二轮回复“当前工作台没有暴露可操作的白板窗口”，没有创建卡片或行动卡。补充调用链审计确认 `executeUserDomainCommands` / `executeRuntimeDomainCommands` 没有生产调用者，普通桌面 Runtime 也未注册或分发六类白板 DomainCommand；手动 UI 仍直接写 repository / canvas adapter，不产生 Domain Receipt 或持久 Undo。本项正式判 P4 Gate 失败，不再要求用户重复聚焦或重试。
- 2026-08-28 P4 窄返修候选：单一 W1 交付经七轮独立复核关闭生产可达、原子性、并发、失败预览、pending、prompt/scope、Persona evidence 与中文只读问句误授权，完整选择性集成为 `30a73ce3`。自动 Gate 和干净 Windows 构建通过，旧 `53d2dc91` 进程已停止；当前只等待新候选的真人六类操作、行动卡 / Receipt、退出重开、Undo、再重开与冲突结果。
- 2026-08-29 P4 窄返修候选真人第一项失败：生产 `manualCommandPort` 把既有透明 `CompactCardEditor` 换成异色表单，标题只读；每次 Domain receipt 后整板 reload 又覆盖 active viewport。自动测试因注入 store/repository 而未启用 production port，形成假 Gate。后续真人步骤已停止，`30a73ce3` 作废并返回原 W1 第八轮返修。
- 2026-08-29 P4 第八轮返修收口：原 W1 恢复同一 BoardItem 内透明单面 `CompactCardEditor`，连续输入的首行作为标题、其余作为 canonical 纯文本正文；标题只允许 manual path，并与正文同 batch / Receipt / Undo，Runtime 执行侧再次拒绝伪造标题；active reload 保持当前 viewport，保存失败保留草稿并显示错误。W0 集成 `4c621771..94eb8a9e` 后完成核心 `73/73`、相邻最终 `107/107`、Repository `39/39`、full editor `5/5`、Card Library `13/13`、compact `4/4`，changed-file analyze、关键守门与 diff 全绿。当前只等待新唯一候选与完整真人 Gate。
- 2026-08-29 P4 新唯一候选：候选源 `779499716448ecf1557cbc53b9348fbb3697c6f0` 在 detached clean Worktree 串行构建成功；exe `830D10BB...EB33`、kernel `EA4C172D...A10F`。Bridge health 正常，Runtime 11 项能力与 7 个模型可读；旧 PID `46168` 已按路径停止，新 PID `55856` 窗口可见且独占 1455。真人 Gate 从空白双击第一项重新开始。
- 2026-08-29 P4 新候选真人第 1 项通过：空白双击后保持既有单一编辑面，首行标题与后续正文均可输入，保存前后 active viewport 不跳位；继续右键标签与其余人工命令。
- 2026-08-29 P4 新候选真人第 2 项通过：右键为同一卡片添加 `p4验收` 标签成功，标签显示并保留，编辑面与 viewport 无回归；继续移动与缩放。
- 2026-08-29 P4 新候选 full editor 项失败：白板直接新建卡片进入 full editor 后，正常未生成 rich 文件的 canonical plain Card 被统一提示为“富文本文件缺失 / 数据库正文投影恢复”。审计确认这是 P2 UX 状态误判，不是正文、标签或 Undo 损坏；现有 schema 无法可靠区分“从未物化”与“整目录真实丢失”，因此拒绝目录存在性 heuristic 和全部静默方案，返回原 W1 做 no-schema 中性文案与 production 路径回归。`77949971` 作废，后续真人步骤停止。
- 2026-08-29 P4 第九 / 十轮中性状态返修已集成：最终只把所有 `missing` 说明改为“当前没有可用的富文本版本，正在显示卡片正文；编辑正文并保存后会创建富文本版本”，不改 repository / RichTextStorage / schema。二次独立复核关闭空正文 media-only 整目录丢失时的静默 P2 与默认 touch 双击证据缺口；共享 object 仍保留。worker `30790f31..3fd6a0ad` 集成为 `b4a8da87..526db238`；主线 affected `25/25`、直接 Dart analyze 三项零问题、critical `3/3`、diff 通过。该提交的 detached clean Windows 候选现已运行，下一步从人工第一项重验。
- 2026-08-29 P4 `526db238` 候选真人第 1 项失败：原位编辑出现右侧滚动条；Delete / Backspace 被画布级快捷键抢占，直接移除 BoardItem；回卡片库全屏编辑正常新卡时，中性 rich 物化通知本身仍不应出现。候选冻结，后续步骤停止；返回 P4-R，自动 Gate 需补真实编辑态键盘、滚动条与卡片库 full editor 无通知断言。
- 2026-08-29 P4 第十一至十三轮返修与新候选：编辑态画布快捷键只留 Escape，删除 / 选择 / 导航键归输入框；内嵌编辑隐藏 Windows scrollbar 但保持滚动；既有 KV 按 Card incarnation 保存 rich materialization evidence，fresh / legacy plain missing 静默，evidenced missing 才告警，corrupt / stale 不变。worker `f7407823..08b112e8` 经独立复审后集成为 `a8ef84d9..7fa6cbb9`；主线定向 `57/57`、critical `3/3`、diff 通过。exact `7fa6cbb9` Windows Debug 构建成功，exe `94F08DB2...A04E2787`、kernel `16C63D62...2475D81`，PID `34688` 健康运行，现从真人第 1 项重验。
- 2026-08-29 P4 `7fa6cbb9` 真人第 1 项通过：内嵌编辑无滚动条，编辑态 Backspace / Delete 只删文字；Escape 退出并单击选中后 Delete 才移除 BoardItem。继续验证该 Card 在卡片库 full editor 中无正常 plain missing rich 通知。
- 2026-08-29 P4 `7fa6cbb9` 真人第 2 项通过：同一正常 canonical plain Card 回卡片库进入 full editor 后正文正常，顶部不出现 rich missing / materialization 通知。本轮两项真人返修闭环，继续人工 labels / move / resize。
- 2026-08-29 P4 `7fa6cbb9` 真人第 3 项通过：右键添加 `p4验收` 标签成功并可见，卡片内容 / 外形与白板 viewport 无异常；继续人工 move / resize。
- 2026-08-29 P4 `7fa6cbb9` 真人第 4 项通过：拖动卡片到明显不同位置后稳定停留，内容、标签、尺寸不变且 viewport 不跳；继续人工 resize。
- 2026-08-29 P4 `7fa6cbb9` 真人第 5 项通过：右下角缩放后尺寸明确改变，内容、`p4验收` 标签、位置与 viewport 均正常。结合第 1 项 create / edit / remove，人工六类操作全部通过；进入 Runtime 六命令。
- 2026-08-29 P4 `7fa6cbb9` Runtime create 首项失败：持久 action 标为 completed，Card / BoardItem 也实际落库，但 Runtime host 使用含冒号的 `card:<seed>:0` / `item:<seed>:0`，rich storage 拒绝该 Card ID；placement 默认写入远离 active viewport 的 `(0,0)`，所以用户看不到。快捷卡片库可在不加载 rich 时列出该 Card，但 drag / click 只产生内存 placement，后续 move / resize 连续返回 `placement_not_found`；global Card Library 被单张 unsafe ID 中止加载。W0 只读取证后冻结候选，未修改真实数据，并从 exact `7fa6cbb9` 派发 R14 独立任务 `01a04c96-d704-7462-95a7-8ee4495ea540`。
- 2026-08-29 P4 R14 已集成并重建唯一候选：Runtime 新建使用确定性文件安全 ID，未给坐标时按 host-owned active viewport 与实际尺寸居中；精确 legacy 冒号 ID 仅映射到隔离安全目录，任意其它不安全 ID 仍拒绝。快捷卡片库 click / drag 通过 manual-only `PlaceExistingCardCommand` 落入 facade / Drift / Receipt / reload，Runtime 仍只有原六项能力。worker `5f515512..715be434` 经两份独立复核后集成为 `caecf05e..884dcd80`；自动 Gate `87/87`、`35/35`、新增 `3/3`、主线 `22/22`、critical `3/3`。exact `884dcd80` Windows Debug 构建成功（224.1s），exe `435D265C...A517F`、kernel `B51DC962...627F1`，旧 PID `34688` 已停止，新 PID `45904` 与 App / Bridge / Runtime 健康；真人从 Runtime create 重验。
- 2026-08-29 P4 `884dcd80` Runtime create 可见性通过：新卡立即出现在当前视口。用户同时反馈聊天后单击卡片再按 Delete 无法移除；只读审计显示 selection 已切换但卡片点击没有把焦点从聊天输入显式交回白板 shortcuts，现有 production test 未覆盖该组合。该问题不推翻 create 结论，但列为 P4 关闭前的交叉焦点 Gate。人工操作反复进入主对话“可撤销”行动卡则是 facade 将所有 actor 的持久审计投影都写成聊天消息所致；保留 Receipt / Undo，展示路由作为非阻断体验债登记。
- 2026-08-29 P4 `884dcd80` 全局卡片库 Gate 通过：桌面侧栏独立卡片库正常加载，没有 `Unsafe card ID` 或全库失败；可搜索到“Runtime 创建验收 R14”。legacy unsafe Card 单卡隔离与新 safe-ID Card 全局可发现性真人成立，下一项只验白板内快捷卡片库持久摆放。
- 2026-08-29 P4 `884dcd80` 快捷库 Gate 失败：单击快捷库中的 R14 卡后新摆放出现，但 ArrowRight 没有可确认移动且 selection 消失。候选冻结；两份只读审计定位 manual Domain 提交后的 lock / reload 会清空 selection，现有 production test 又未覆盖真实鼠标焦点与 reload 后连续 selection。当前不把现场冒充持久化已通过，也不继续 drag / restart / Undo；返回同一 P4-R 做 R15 窄修。
- 2026-08-29 P4 R15 已交付、独立复核、集成并构建新候选：只在 production route/manual UI 边界恢复 applied reload 后仍存在的 selection，并在真实鼠标选择及成功 placement / move / resize 后把 focus 交回画布；失败、目标消失、reconciliation failure 与 surface/route switch 均 fail closed，领域契约与 Runtime capability 未变。worker `245af967`、test-only `bf134301` 集成为 `372885cb`、`a36e5236`；主窗 production route `7/7`、三文件 analyze、critical `3/3`、diff check 均通过。exact `a36e5236` Windows Debug 候选已启动 PID `22276`，exe `91A0E18E...3156E`、kernel `D96FA042...5A9A6`，App / Bridge / Runtime 健康。
- 2026-08-29 P4 `a36e5236` 快捷库连续移动 Gate 通过：快捷库新摆放出现后，连续两次 ArrowRight 均向右移动，逻辑 selection 全程保留。每次移动提交期间选中框会短暂闪一下再恢复，未发生实际解除选中，登记为非阻断视觉优化。当前只验聊天输入 → 点卡片 → Delete 交叉焦点 Gate。
- 2026-08-29 P4 `a36e5236` 聊天 → 卡片 Delete 交叉焦点 Gate 通过：聊天输入框先取得光标后，单击新摆放卡片再按 Delete，目标 BoardItem 正确从白板消失。R15 两项真人返修闭环，当前恢复 Runtime 剩余五类操作，先验正文编辑。
- 2026-08-29 P4 `a36e5236` Runtime 正文编辑 Gate 失败：用户明确只改 R14 卡片正文，并限定不改标题、标签、位置或大小；产品返回 `unsupported_product_tool`，只读核对确认零误改。审计确认尾句的局部否定触发了全局授权短路，使 `editCardBody` 也被清空，标准工具调用未进入 adapter / facade / Drift。候选冻结，后续 Gate 停止；R16 独立任务 `01a04d7d-d383-79b2-a7ce-865f80761452` 已从 exact `a36e5236` 派发，只修 capability 级授权解析和 exact 原句生产回归。
- 2026-08-29 P4 R16 已交付、独立复核、集成并构建新候选：授权解析先剥离引号内容，再按局部子句识别逐项正向能力并减去否定能力。worker 首轮 `4a15faad..e5d22ad0` 经 Terra medium 初审发现“不需要 / 不必”仍可能越权；follow-up `2ad8c134..daaa1e47` 补否定词族与中英文逗号边界后复审无阻断。W0 选择性集成为 `2778478a..66017099`；Runtime `14/14`、coordinator `23/23`、目标 analyze clean、critical `3/3`、diff check PASS。exact `66017099` detached clean Windows Debug 构建成功（223.3s），exe `22FE4911...F5A6BF`、kernel `52132BCF...D1FC8`，PID `56408` 的 App / Bridge / Runtime 健康。只重测原正文编辑句，自动 Gate 不代替真人结论。
- 2026-08-29 P4 `66017099` 原正文句重测失败并派发 R17：产品已调用正文写工具，但返回 `whiteboard_target_outside_scope`，正文、标题、标签和 geometry 零改。真实 host context 的 selected item/card IDs 均为空；R16 exact 测试固定预选 `item_a` 且 fake Runtime 硬编码 `card_a`，只证明 capability 解析而未覆盖当前白板标题目标。R17 `01a04de1-94ba-7c63-b685-0e88301b9468` 已从 exact `66017099` 在 `C:/Users/ExampleUser/.codex/worktrees/8dd4/memex` 启动，只补 host-owned、current-board-only、精确唯一标题 target scope；0 / 多义 / 跨板 / 仅库卡继续零写拒绝。
- 2026-08-29 P4 R17 已交付、独立复核、集成并构建新候选：current-board-only 精确唯一标题 resolver 只在直接目标句生效，标题 literal 位于正文引号中时保持不透明；授权绑定 exact surface instance，flush / invoke / durable 前的重挂或切板均零写拒绝；同 Card 多 placement 时正文 / 标签允许、placement 操作因 item 多义拒绝。worker `f026b23b..a7a6b3da` 经独立复核关闭同 board 重挂竞态、literal 劫持与过宽语法三项 P1，最终无 P0/P1；集成 `21ade156..1f77633a`，自动 Gate `51/51`、analyze clean、critical `3/3`、diff check PASS。exact `1f77633a` Windows Debug 构建成功（210.3s），exe `32B0CFF7...55B5`、kernel `5763C771...4C3D`，PID `52368` 与 App / Bridge / Runtime 健康；当时只恢复原正文句真人重测，结果见下一条。
- 2026-08-30 P4 R17 正文与标签真人通过：Runtime 把正文改为“R15 Runtime 正文编辑通过”，标题仍为“Runtime 创建验收 R14”，标签、位置和大小保持不变；随后仍按该标题把标签设为小写“runtime验收”。R17 current-board exact-title scope 与 R16 单能力授权已覆盖两类命令。
- 2026-08-30 P4 Runtime 移动 Gate 失败并派发 R18：host 已精确授权当前板唯一 Card / BoardItem 与 `move_placement`，但授权上下文未携带当前 `x/y`，绝对坐标 schema 无法直接表达“右移 120”；模型未调用 `whiteboard_domain_commands`，生产 turn `01a05107-88e4-7160-b57c-3c5903296cb7` 运行 `180084ms` 后被 `runtime_timeout` 中断，零 payload、Receipt 与持久写。R18 `01a05185-dbe9-7313-8e2c-d02fd40f051e` 只补 bounded geometry 并真实探测 required-tool wire；新候选前停止后续真人 Gate。
- 2026-08-30 P4 R18 已交付、审计并集成：host 只向已授权 move / resize 回合提供同一 authoritative snapshot 的 exact target geometry；领域与 Runtime 共用坐标 ±1,000,000、宽 `80..3000`、高 `60..3000` 边界，非法几何在 action / Receipt 前零写拒绝。首轮独立复核发现两项 P1，follow-up 后终审无 P0/P1/P2。真实 `codex-cli 0.151.0-alpha.7.2` schema 无 per-turn required / allow-only tool 能力，故没有伪造接线。worker `9297fd1c..c7d38601` 集成为 `2b2275d4..eec22abb`；主线 `99/99`、四文件 analyze、critical `3/3` 与 diff check 全绿，现只待新 Windows 候选恢复移动 Gate。
- 2026-08-30 P4 R18 新唯一候选：exact `2ed4b015` detached clean Windows Debug 构建成功（228.3s），exe `33F10A94…2B017`、kernel `C5BF7E43…21BB0`。旧 App PID `17840` / Bridge PID `31992` 已按精确路径停止；新 App PID `37380`、Bridge PID `32764`，App / Bridge `200`、Runtime 11 项能力 / 7 个模型与 ChatGPT auth 健康。当前只恢复标题 R14 卡右移 120 像素真人 Gate。
- 2026-08-30 P4 R18 move / persistent Undo / restart 真人通过：用户确认目标卡右移、首次重启保留，并在第二次重启后确认行动卡显示“已撤销”、按钮消失；DB 审计同时证明 x 恢复原值、其它字段未变、不可重复 Undo。无 busy / Toast 的即时反馈登记为非阻断债；当前只验 Runtime resize。
- 2026-08-30 P4 R18 resize 现场失败、R19 自动返修收口：真实 resize turn `01a052e3-323c-7663-ad13-8ba0035b6533` 在无白板授权上下文、零产品工具 / action / Receipt / 写入的情况下约 180 秒超时，旧候选冻结。R19 仅补严格相对尺寸授权、quote 隔离与 selection / snapshot fail-closed；三项独立审查阻断经 follow-up 关闭，worker `37c77acd..523ec22a` 集成为 `2a75a7c0..158158dc`，主线 `34/34 + 23/23`、critical `3/3`、目标 analyze 与 diff check 通过。新候选和真人 resize Gate 尚未执行。
- 2026-09-02 P4 R19 真人失败、R20 自动返修收口：exact `722a646d` 候选 App / Bridge / Runtime 健康，但真人连续两次 resize 都返回 `whiteboard_surface_changed`，零 action / Receipt / 持久写。production route 进入 readonly 时同步清空 selection 并发布同 attachment 新 snapshot，旧实例 gate 将其误判为重挂。R20 用 host-owned attachment token 只放行该空 selection，fresh attach、非空 replacement、owner / board 变化和后续竞态继续 fail closed；两份独立复审无 P0/P1，worker `591caf3a + 3c6265c7` 与 handoff `cdf01946` 集成为 `3674548b..03c2afd9`，主线 `59/59 + 8/8`、critical `3/3`、目标 analyze 与 diff check 通过。新候选和真人 resize Gate 尚未执行。
- 2026-09-05 P4 最终真人 Gate 通过：exact `e77045fa` 上 resize `+120`、完整重启保留、持久 Undo 精确恢复与行动卡终态一致；remove 只删除 BoardItem，Card 本体仍可检索。制造后续控制卡移动后，旧 remove Undo 先以 `snapshot_changed_after_batch` 拒绝且 token 保留；撤销控制卡移动后，同 token 重试精确恢复目标摆放，完整退出重开后两张卡 geometry、Card 字段与 `undone` 状态稳定。Lynx 明确确认通过，P4 子 Goal 正式关闭，P5 解锁。
- **历史三包候选**：`v3-lab@fad8b7368d3c88973d705a1dcf6b2c599c7adcf1` 及其 exe `CE15ED53...1EF44EA` / kernel `E4297010...A1571FC` 只证明 UI-T / P4 / P6 的旧自动 Gate，P5 未恢复且本机 exact 产物已不存在，不得再用于真人复验。
- **P5 返修前的候选状态（历史）**：当时本机已无 `fad8b736` 的 exact Worktree / 产物，现存 `build/windows` 产物属于已失败的 `f80ea1e8` 候选，主线已前进到 `9237270e`；这一断点随后由 P5 返修和 `45f4d948` 候选取代，不代表当前候选状态。
- **历史真人候选**：`v3-lab@f80ea1e80f7095fb1a37d7f2c2a3f16bbf6a7c00` 与其产物只保留为首轮真人失败证据，不再代表当前返修源码。
- 2026-08-24 记录的 bundle `AA9AED9E…` 后经 VM Service 核查证实入口为 `integration_test/whiteboard_f4_source_product_windows_test.dart`，双击只生成无窗口测试进程；它不是可验收应用候选，已作废。2026-08-26 重新执行关键守门 `3/3` 并完成正常 Windows Debug 构建，窗口句柄与响应状态真实可见。
- 旧候选 `v3-lab@838e4645f631768a300fe707ef56fde30eaa853a` 及 bundle `2B8C56E8…` 已被返修候选取代，只保留为首轮验收历史证据，不得再用于真人复验。
- UI-T：按颜色泄漏 handoff 的九项覆盖路径逐项确认桌面次级界面不再继承紫色或手机主题。
- P4：至少完成一次创建 / 编辑 / 标签 / 移动或缩放 / 移除摆放；退出并重开后确认领域结果、Receipt 与 Undo 恢复，再执行撤销及冲突路径。
- P5：2026-09-06 已按限定来源通过；人格/历史召回/空结果/到期失败有实际样例，权限采用用户确认的“自动拦截 + 真人只读回复”组合，证据不互相冒充。
- P6：确认排队、暂停 / 恢复、取消、重试；重启后状态诚实恢复，普通聊天不出现 TaskRoom。
- W4：验收记录继续显示 `0/18` 非阻断红灯，不显示通过。
- 2026-08-24 真人反馈：除 SnackBar 外，其余已能触达的桌面主题表面无异常；这里的 Dialog 是“新建白板 / 字幕导入 / 未保存提醒”等模态弹窗，不是聊天对话。
- 2026-08-24 真人反馈：所有已试视频卡片进入后持续转圈，字幕导入空状态因此不可达。代码核查显示转圈意味着 `PlayerAdapter.load()` 未返回；Windows Bilibili adapter 的 WebView2 初始化 / 导航当前没有超时。该问题虽不把 W4 字幕 `0/18` 改为 Goal 阻断 Gate，但会阻断 UI-T 的字幕 Dialog 验收，修复后必须重新构建候选。
- 2026-08-24 环境核查：`/experimental/v1/runtime/capabilities` 返回 `experimental_runtime_disabled`，明确要求 `DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER=1`；P4 / P5 / P6 真人 Gate 不是功能失败，而是验收环境未启用。
- 2026-08-24 返修：桌面 shell 新增主题内 ScaffoldMessenger；聊天输入移除继承内框、回复期间不禁用并扩为 2–5 行；全屏卡片正文强制顶部对齐；视频加载增加 35 秒永久等待守门、失败后可进入字幕与笔记，并串行化 Windows WebView2 销毁 / 再初始化。相关组件及相邻回归 `106/106`、播放器适配器与视频回归 `54/54`、14 项 changed-file analyze 零问题、关键守门 `3/3`、Windows Debug 构建成功。
- 2026-08-24 Runtime 已以 `DEV_AGENT_EXPERIMENTAL_RUNTIME_ADAPTER=1` 重启，capabilities 11 项与 Codex 模型目录真实可读；P4 / P5 / P6 环境阻塞解除。
- 2026-08-24 真实 Windows YouTube 验收首次打开已走通预览、播放推进、字幕导入与标注写入；同一测试进程销毁后第二个 WebView2 播放器仍会超时，继续登记为 W4 非阻断红灯，不伪称重启恢复通过。用户可见路径不会再无限转圈，失败后仍可进入字幕空状态。
- 2026-08-26 真人复验第 1 项：保存 SnackBar 经黑色对照确认是深绿色背景，文字为奶白色；首次保存体感较慢，但同卡二次保存很快，判通过。
- 2026-08-26 真人复验第 2 项：聊天窄内框已消失，首轮普通粘贴和回复期间编辑通过；Typeless 与 Windows `Win + H` 均无法向 Flutter TextField 写入，判失败。消息右键“全选”功能正常，但菜单使用白紫色旧主题，新增 UI-T 主题泄漏失败项。
- 2026-08-26 本轮人工验收结束：第三轮粘贴再次失效；P4 退出重开后无法恢复 Undo；P5 当前只读工作电脑本地数据库，未接入真实人格与长期关系 Memory V3；P6 只有底层队列服务，没有生产 UI 或 Runtime 入口，真人无法验收。W4 另有时间轴拖动消失等缺陷，继续作为非阻断红灯。
- 结论：本轮候选**未通过**，不是 Goal 完成。UI-T / P4 / P5 / P6 均保留为返修项；2026-08-26 用户确认短期无法回到私人电脑完成 P5 / P6，因此本 Goal 转为阻塞并冻结，不取消、不取代，也不把既有自动 Gate 或 push 当作通过。

## 激活与收口记录

- B0 控制面提交：`f88537d72d08531252e2050784d71deba36a517f`。
- Goal 激活提交：本文件首次进入 `v3-lab` 的提交；由验收主窗在派发前报告并登记为所有 Worktree 的可读起点。
- 本轮动作：从恢复控制面 `7f7af225` 派发 UI-T / P4 / P6 三个隔离返修 Worktree；其历史 `fad8b736` 候选已经失效。用户再次恢复验收后，W0 从 `9237270e` 隔离返修 P5，经两轮安全审计后完整集成为 `dc34a0c9`，P5/P6/Companion `121/121` 与 Goal 九文件组合 `112/112` 通过。
- 当前执行点：UI-T、P4 与限定范围 P5 已通过，权限采用用户确认的自动/真人组合口径。沿用 `4ba05b11` + 已记录 P5 源的同一候选，exe `bd7b06fe…` / kernel `28ed9bca…` 再核对一致。P6 入队、指定 ID 状态查询及 App 重启后等待态保留已通过；用户已授权并派发 [P6-R2 返修](../whiteboard-workstreams/P6_R2_REPAIR_PLAN.md)，分离指定任务强绑定、执行核心与 Runtime 权限隔离；第一轮代码已本地集成，主控 122/122 回归与 Bridge 31/31 通过；后台工具隔离未成立，真实执行及写入真人 Gate 尚未解锁。P6 与父 Goal 未通过。不以 pending 视为执行，不手改 running/failed，不借用其他领域执行器制造验收。P5 来源限制及连接提示改进保留在整合记录；W4 非阻断，未提交/推送/发布。
- 最终本地验收基线：`v3-lab@b2adc44b7c04983a931c39695b81491cd295084b` 与受控源码清单 104/104；隔离普通 Windows exe SHA-256 `A8A3FF2943B2B6F6837A1945F9ED7AEF6CC5F9BC232FB492B59F34C789A192C3`。详见 [最终本地验收](../whiteboard-workstreams/GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md)。
- push：2026-08-26 已按用户明确授权将 `d10d529b..1daf888a` 推送至 `origin/v3-lab`；远端现已包含 `f80ea1e8` 候选、Roadmap 定稿和本次验收断点。该动作不代表真人 Gate 通过，Goal 继续保持活动；后续返修 push 仍需重新授权。
- 并行例外：2026-08-26 用户明确确认，在本 Goal 阻塞期间只允许一个不依赖其结果的 `authority-preflight` 活动 Goal；正式 Gate 1A-0 仍须等待本 Goal 通过或被用户正式取消 / 取代。
