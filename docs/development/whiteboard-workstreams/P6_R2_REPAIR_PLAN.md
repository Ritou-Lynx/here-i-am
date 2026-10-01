# P6-R2 返修派发与集成计划

最新回收：2026-09-07 [P6-R4 行为验证](P6_R4_BEHAVIOR_VERIFICATION_PLAN.md) 两包已集成六个验证/交接文件，主控 Node 40/40。额外协作查询确可执行；正常中断有 terminal，超时/断线仍缺可靠停止证明。未修生产源、启用执行或切换 API，P6 未通过。

最新续作：2026-09-07 [P6-R3 隔离复核](P6_R3_EXECUTION_ISOLATION_AUDIT.md) 已完成三组追加探针与独立接口审计，均未达到既定隔离标准；Node 32/32，生产门控未放开。若改用专用纯文本 API，须先确认接入/费用来源，当前没有实施通道替换。

## 授权与基线

- 2026-09-06，用户确认“派发吧”，执行现有 `GOAL-20260824-ai-workbench-wave1` 的 P6 返修，不新建 Goal。
- 主窗 `/root`，当前 task `01a03e4a-e594-7b32-b3da-25705b8e1eb5`；开发基线 `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`，不 pull。
- 当前主工作区混合 staged/unstaged 与 P5 未提交源必须保留。三个写包从同一 commit 创建独立 Worktree，不吸收主工作区其他改动；集成时主窗逐文件复核 P5 overlay/测试差异。
- 用户已通过入队、指定任务 status、App 重启后 pending 保留；不是运行中恢复。原验收 App/候选指纹、手机会话与 synthetic pending 记录不动。
- 本轮执行既有范围内隔离实现、本地集成和列明验证；所有工作包保留未提交差异，不动主目录索引，不 push/发布，不写真实 DB、不运行真实任务、不扩展 P5、User-truth、通用 Orchestrator 或 TaskArtifact 上板。

## 工作包

| 工作包 | 执行者与模型 | 基线/Worktree | 拥有路径 | 状态与交付 |
|---|---|---|---|---|
| A 指定任务强绑定 | `/root/p6_r2_target_lock`，Terra medium | `4ba05b11`；`.worktrees/p6-r2-target-lock`；`codex/whiteboard-w0-p6-r2-target-lock` | queue host、现有 queue tool 专项测试、自身 `P6_R2_TARGET_LOCK_HANDOFF.md` | 已回收并集成；12 项 host 测试纳入主控 122/122，最终 host 两项 lint 由 B 按授权修正 |
| B 真实执行核心与接线 | `/root/p6_r2_execution`，Astra high | `4ba05b11`；`.worktrees/p6-r2-execution`；`codex/whiteboard-w0-p6-r2-execution` | execution contract/owner、TaskRoomService、Runtime client/queue wrapper、两份执行测试、自身 `P6_R2_EXECUTION_HANDOFF.md` | 七个源码/测试已回收并集成；现有 coordinator production factory 已接线，未改其源或 P5 测试；生产真实执行仍拒绝 |
| C Runtime 权限与终止语义预审 | `/root/p6_r2_runtime_boundary_audit`，Terra medium | 主线只读，不写 Worktree | Runtime client / Bridge adapter/API/tests 只读 | 审计完成：动态工具空列表不代表禁内建工具；interrupt 是请求接受。close 正常路径等待终止，但断线分支没有 provider 终止证据，不能普遍信任 void close |
| C2 Runtime text-only profile | `/root/p6_r2_runtime_profile`，Astra high | `4ba05b11`；`.worktrees/p6-r2-runtime-profile`；`codex/whiteboard-w0-p6-r2-runtime-profile` | Bridge 专用 profile、adapter/API 最小门控、隔离探针与 Node 测试、自身 `P6_R2_RUNTIME_PROFILE_HANDOFF.md` | 已回收并集成，主控 Node 31/31；探针完整目录仍有工具，初次“零工具”误判撤回。专用 profile 明确拒绝，不回落普通 Runtime |
| W0 集成与验收 | `/root`，当前 Astra | 主目录选择性集成，不重建候选 | 共享接口裁决、串行测试/集成、状态记录 | 第一轮代码回收完成：122/122 + Bridge 31/31，9 文件 analyze 零问题；真实隔离/真人 Gate 未通过 |

## 最小执行契约

1. A 从当轮用户原话绑定明确目标；写操作缺失/冲突目标拒绝。显式目标的只读查询同样不能改读另一项，泛状态查询可保留受限 latest 只读路径。不通过模型 payload 自授权。
2. enqueue 永远只入队；已有 pending 不自动启动。执行需新的明确 start 指令/宿主授权，不把“开始一个长任务”猜成对旧任务开工。
3. B 用隔离 Runtime session 执行有限文本任务，结果依据真实 provider turn/events；不能用计时器模拟运行/失败。后台与 persona 普通聊天隔离，不自动生成卡片、记忆或外部动作。
4. 持久化 claim/epoch/phase 与请求幂等信息；迟到事件不得覆盖暂停、取消或新一轮执行。状态/结果更新必须匹配当轮 execution owner。
5. 暂停/取消等待实际终止确认，不能以 interrupt accepted 就声称完成；控制结果未知时诚实 blocked/interrupted。恢复可从保存上下文重新运行无外部副作用的文本任务，但必须明确恢复方式，不伪称原 turn 无缝续跑。
6. resume/retry 必须实际调度；重试次数及上限持久化。App/Bridge 重启后标 interrupted、可恢复，不自动执行旧任务；起步中的 claim 同样须诚实恢复。
7. 当前 Bridge 无确定性 text-only 成功路径；`dynamicTools=[]` 不能当作 shell/文件/网络禁用。核对实际 CLI 0.153.4 schema 和官方配置后，C2 的临时 home/空工作目录/本地假 provider 探针发现顶层虽无 tools，嵌套 `input.additional_tools` 仍有执行/技能/协作工具；初次“零工具”结论撤回，需递归目录与正控验证。固定 `workbench_text_only_v1` 当前返回 `unsupported_capability`，不启动 session 或回落普通 Runtime。后续启用必须验证完整工具隔离及 provider 终止回执，不改全局/真实用户配置或复制认证资料。

## 验证与回收

- A：合成同 scope A/B、错 ID、漏 ID、多 ID、跨 scope、否定写、未授权动作/payload、status 只读；正确目标操作不改另一条。
- B：fake gateway + 隔离 Drift 的真实 owner 调度、终止确认、迟到事件 fence、重复调用、失败/重试上限、进程恢复；生产 composition 必须调用同一 owner。
- SDK 共用串行并显式交接；新 Worktree 必要时仅离线恢复依赖配置，不升级依赖。B 核心/service 初轮 62/62 与 changed-file analyze 通过，A/B 新增交叉修正待组合验证。最终主窗跑受影响普通聊天/P6/P5 回归。
- 实现包交付后主控二审实际 diff；按 service/controller、host、client/wrapper 与 Bridge 的依赖统一选择性集成，保留预存 P5 测试差异。本轮不构建/重启验收 App；真实 text-only 隔离缺口消除、自动 Gate 通过后才准备新候选，build 前必跑 critical guard。
- 新候选的受影响真人 Gate 重新取得证据；不继承旧产物的完整通过结论。P6/Goal 1 保持未通过。

## W0 最终回收（2026-09-07）

- 三个写包均未提交，由主控通过逐路径差异选择性集成；主分支/HEAD 仍为上述 `v3-lab@4ba05b11`。未 stage、commit、pull、push 或操作真实 App/DB。
- 本地主控单次七文件 Flutter 回归 **122/122**：执行核心 20、专用 text client 9、queue host 12、旧 client 2、TaskRoomService 45、普通聊天/coordinator 26、关系/只读上下文 8。采用内存/临时 Drift 与假 provider/本地合成 HTTP；不是实际模型执行或真人 Gate。
- 主控 Node 四文件组合 **31/31**；九个本轮 Dart 源码/测试 `dart analyze` 无问题，`git diff --check` 通过。Dart 9/9 与 B 最终冻结文本一致，B 包含 A 最终 host/test 依赖及授权的两项 lint 修正。
- 既有 coordinator 测试的 198+/4- P5 差异保留且通过回归；普通 Runtime 仍按原路径工作。旧 P5 App/手机连接/等待任务未操作，没有生成或安装新候选。
- **未完成项**：生产无工具隔离仍不成立，真实开始/暂停/恢复/取消/重试与运行中重启不能宣称通过。后续先确定可证明的受限执行通道及真实 terminal receipt，再启用 profile、构建新候选并恢复对应真人 Gate；不为绕过此缺口复制认证资料、更换计费来源或放宽权限。
