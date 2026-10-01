# MDA-1 并入 v3-lab：方案与独立验收交接

> 日期：2026-09-12。状态：方案已拟定，交新验收任务裁决；尚未制作合并候选、尚未并入主线。

> 这是最初移交方案的历史快照。隔离候选已完成组合验收，固定旧 v4 运行入口已获准切换且原聊天续用已获用户确认；最新共享文档融合与待确认的本地提交/合入范围见 [主线协调记录](MDA1_MAINLINE_COORDINATION_20260912.md)。当前仍未提交或并入 `v3-lab`，未部署 MDA schema 5。
> 来源任务：`01a04839-f159-71f1-8fd3-4e3b83ef9178`（睡眠与多端活动任务）。
> 用户本轮要求：生成最合理的合并方案，交给一个新窗口验收并决定执行方式。

## 1. 推荐决策

从重新确认的本地 `v3-lab` 建立干净集成工作树，优先采用保留双方历史的三方合并；在隔离工作树内解决冲突、补组合验证并形成可审候选。由新任务独立判断方案是否成立、采用哪种落地方式，以及主线发布条件是否已满足。

将结果分为三个状态分别签字：**方案通过 → 集成候选通过 → 已落入 v3-lab**。真实 iCore 服务升级、数据库迁移和设备安装是另外的运行时动作，不能随源码合并顺带发生。

当前已有依据足以开始候选准备，无须等待 P6 全部开发完成，也无须重开已通过的 MDA-0/MDA-1。最终更新主工作树时，必须解决实际重叠改动并取得短暂独占写入窗口；不要求先清空全仓所有无关修改。

## 2. 精确输入与证据等级

| 项目 | 本次读取结果 | 使用方式 |
|---|---|---|
| 本地目标 `v3-lab` | `bbb8025d99fc0acaa846d58b4e5a94cef90f8756` | 候选默认目标；执行时重新读取，不能静默使用旧 SHA |
| MDA-1 来源分支 | `codex/mda1-activity-core@44268fa91238bfde50363a1207120faee0a9f650` | 来源工作树 `.worktrees/mda1-activity-core`，本次源码 clean |
| 已验功能候选 | `fbcbceb0` | 后续三笔为验收/备份边界文档；准确性由 Git 复核 |
| 共同祖先 | `2edaf17a3f8bb733e6ac6f54024941267d7f32a4` | 三方 diff 起点 |
| 分叉规模 | 目标独有 26 提交，来源独有 55 提交；双方改动路径交集 19 个 | 不能把 55 提交全部称为纯 MDA 新功能 |
| 历史合成验证 | Node 207 pass + 1 既有 Windows skip；human harness 11/11；HTTP 26/26、213 requests；Android reader 15/15 + analyze；Gate 1A-0 Dart 27/27、CLI 202/202 | 仅对应原候选，新集成组合要复跑；不是多设备真机 Gate |
| 用户接受 | MDA-1 Goal 记载 2026-09-06 三 probe 合成审看通过，接受三项 P2 与只读备份边界 | 保留原验收事实，不自动扩展为部署验收 |

来源验收入口（从来源工作树读取，不能用主线旧状态页否认这些事实）：

- `docs/development/goals/GOAL-20260905-mda1-device-activity-core-control-plane.md`
- `docs/development/activity/mda1/CORE_CONTROL_PLANE_HANDOFF.md`
- `docs/development/activity/mda1/ANDROID_SUMMARY_CLIENT_HANDOFF.md`
- `docs/development/activity/mda1/FIXTURE_HTTP_RUNNER_HANDOFF.md`
- `docs/development/activity/mda1/SYNTHETIC_HUMAN_GATE_HANDOFF.md`
- `docs/development/goals/GOAL-20260830-gate1a0-authority-recovery.md`

MDA-0 已被用户接受带红灯收口；Gate 1A-0 已在隔离合同链验收，未切换生产权威。MDA-1 是用户批准的隔离并行例外。主线仍写“尚未创建”的部分是状态尚未汇合，不应据此要求重复立项或等待 P6 通过。

COROS 已于 9 月 10 日完成精确 APK 的零大缺口八小时 Gate，相关源码提交为目标 tip `bbb8025d`。无需为纯 Node/Dart 活动控制面合并重跑 BLE 整夜验收。该事实不消除三星强杀、耗电预算、睡眠判断等已后置项目。

## 3. 纳入范围和依赖

按三个逻辑包检查，而非逐一盲目 cherry-pick 全部 55 个提交：

1. **必要合同/fixture 前置**：Gate 1A-0 已验合同与纯合成 harness、窄 `.gitattributes`、MDA-0 的后续协议修订。保留来源与历史 Gate，不把合同纳入说成生产权威迁移。
2. **MDA-1 控制面**：`tools/i_core/activity_*`、human harness、`i_core_store.mjs`、`i_core_server.mjs` 及相关测试；Dart 只读 summary client 与测试；对应 handoff/Goal。
3. **共享入口与文档整合**：iCore README/生命周期、专题 Roadmap，以及全局状态/日志中的必要合并记录。

来源包含邮件提交 `86c7394f`，主线包含 `455be35e`。两者有相同工作来源，补丁未必逐字等价；必须逐路径比较并保留主线邮件修复，不能重复带入或用旧邮件版本覆盖。

最终目标相对 diff 应列出每个纳入文件的来源或冲突决策。排除 P6/白板 Runtime、真实队列、i Gateway、BLE/Manifest、路由/DI/UI 扩张、私密数据与临时构建产物。Dart summary client 继续未接 UI/采集器。MDA-2～5 不在本次范围。

## 4. 合并方式的选择

### 首选：在隔离工作树做三方合并

- 基于重新确认的目标 SHA，创建 `codex/` 前缀的集成分支。此处建议名称 `codex/mda1-v3-integration`；名称冲突时选新名称，不能移动既有分支。
- 使用精确来源 SHA，先生成无提交的合并候选，再进行语义修复。全局 Git 索引、主工作树和运行服务均不参与试合并。
- 保留必要 Gate 1A-0 依赖以及 MDA 完整历史，避免只拣一个最终功能提交漏掉此前安全修复。
- 验证到位后才记录集成结果；是否提交候选按新任务收到的授权处理，未提交时交付完整 diff 与指纹即可。

### 备选：选择性移植

仅当新任务证明全历史合并会引入无关变更、依赖不适宜进入主线，或无法合理维护历史时采用。必须提供“来源提交/文件 → 目标内容”的映射、必要依赖清单、主动排除项和原因。不可只从来源复制 `i_core_server.mjs` / `i_core_store.mjs` 整文件，也不能只搬 activity 文件而遗漏合同/fixture。

原地 merge、跨脏工作树 rebase、整文件 ours/theirs、为清理而 stash/reset 均不适合当前状态。单独 `update-ref` 并不能同步 checkout/index，不作为绕过主工作树保护的默认办法。

## 5. 四个已观测冲突的处理标准

2026-09-12 的三方文本预演出现下列四项；这是预演结果，新任务须在实际候选中再确认，不假设永远只有四项。

| 路径 | 合并原则 | 必须保留的断言 |
|---|---|---|
| `tools/i_core/i_core_server.mjs` | 逐块整合邮件与 activity 的认证、启动和关闭；核对 relay 所有权、store 关闭、retention timer、graceful shutdown、失败路径 | 邮件默认关闭和既有授权不变；probe 无 chat 权限；失败不假成功；只关闭本实例拥有资源 |
| `DEVLOG.md` | 保留双方历史，新增实际集成记录，避免丢主线较新的 P6/COROS 条目 | 原候选 Gate 与新集成 Gate 分列 |
| `docs/development/I_PROJECT_STATE.md` | 以主线最新 P6/COROS 事实为基础，增补 MDA 与已验合同状态 | 不退回旧 P4 进度；不把 MDA 合入等同端到端可用 |
| `docs/companion-first/PRODUCT_ROADMAP.md` | 汇合并行例外及依赖事实，保持 P6 既有状态 | Gate 1A-0 合同通过不等于全局生产迁移；MDA-2 未自动启动 |

另外检查：主目录未跟踪的 `MULTI_DEVICE_ACTIVITY_ROADMAP.md` 与来源版本不同；`mda0/REAL_DEVICE_GATE_RECORD.md` 有较新的未提交更新。分别逐段合并，不能丢弃原文件或用旧 COROS 红灯覆盖 9 月 10 日记录。

## 6. 运行时影响是最终落主线的前置检查

源码层已经发现不能忽略的兼容变化：

- `i_core_store.mjs` 构造函数默认 `activityEnabled=false`，仍调用 `#migrate()` 并构造 `ActivityControlPlane`；后者在非只读备份情形调用 `migrateActivitySchema()`。没有 admin secret 不等于没有数据库写入。
- 候选的 Core schema 常量为 5；普通旧库升级、健康检查和 path/identity 绑定均要重新确认。
- `backupDatabase()` 会把含 activity metadata 的副本标为 `backup_read_only`；正式副本只作 whole-Core 离线验证，不能直接作为可写聊天 Core 启动，即使 activity 未启用。
- activity 未启用但库中已有到期活动数据时，备份会以 `activity_retention_authority_required` 拒绝；不会越权清理后继续生成副本。兼容验证需要覆盖这种现有数据状态，不能只测空库。
- `start_i_core_service.ps1` 从脚本目录解析 `i_core_server.mjs`。若现有计划任务/服务指向主 checkout，源码落地后的下一次重启可能直接运行新版。还须核实任何守护进程、动态子进程或热加载是否消费同一路径。
- 当前 launcher 会清除 pairing/worker 等启用变量，但未清除 `I_CORE_ACTIVITY_ADMIN_SECRET`；server 主入口又会读取该变量。继承环境可能意外开启 activity。常驻入口应默认明确清除此启用值，并用合成环境证明继承值不能开启 activity；有意启用另走明确入口。新任务需把该窄兼容修补纳入候选评估，不读取真实 secret 值。

因此新任务需完成一个只读运行拓扑检查，只记录可执行文件/脚本路径、任务状态与版本关联，不输出环境 secret、命令行凭据或读取真实数据库内容。不能因当前进程仍在运行就推断未来重启安全。

裁决分支：

1. **真实运行入口与 checkout 已隔离**：可继续源码候选评审；源码落地后仍保持既有运行版本，部署另计。
2. **真实运行入口跟随 checkout，或无法证明隔离**：可继续完成隔离候选，但正式更新主 checkout 前必须形成已验证的运行兼容方案。可选择明确且测试过的默认休眠/迁移开关、稳定版本运行入口，或另行授权的迁移窗口。
3. 修改部署路径、默认迁移/备份语义或配置属于实质方案修订：先给出具体影响、可审补丁与合成验证；不能用“没有配置 admin secret”替代证明，不能为赶合并删除安全校验。

本次授权不包含真实数据迁移、真实服务重启、配置/凭据改动、邮件发送、Tailscale/防火墙修改或设备安装。必要内部候选工作可继续，真实运行变更留到对应授权成立后执行。

## 7. 主工作树与并行任务保护

本次观察有五份文件已经 staged，且其中多个同时有 unstaged 更新：DEVLOG、总 Roadmap、项目状态、Goal 1 和旧 P4 Goal。另有 P6、Gateway、手机只读等工作在进行。目录总数只作快照，不作为门槛。

- 开始前记录目标 HEAD、来源 HEAD、相关 staged blob OID、相关 working-tree 文件指纹和 untracked 路径碰撞；不要把私密内容写入报告。当前五份 staged 内容属于用户既有工作。
- 候选阶段不动主目录索引、分支、设备、后台服务；测试仅用独立临时数据和随机 loopback 端口。
- 原任务和其他 worker 可继续拥有自己的文件。最终只协调目标 ref、真实冲突文件和共享索引的短暂串行窗口；新任务是本次集成的唯一写入责任方。
- 主线若前进，刷新输入，计算新增提交的相交路径。只对受影响部分重整合/重验，不能把基于旧 HEAD 的候选强推到新主线。
- 原 MDA 来源与主线已分叉，二者不能直接快进。先在隔离树形成包含当前目标作为祖先的、已经验证的 merge/transplant 候选；目标未再前进且没有重叠 dirty 阻碍时，最终才可能将主线快进到这个候选。普通 Git 操作必须完整保留无关 staged/unstaged 工作；存在实际重叠则先与其拥有者收口，不使用“自动备份后强覆盖”。若提出临时索引重建等特殊方式，须分别证明 HEAD/index/worktree 各层结果和恢复路径，独立审核后才采用。
- 新增方案/报告文件也在保护清单中；本方案留在主目录未跟踪路径供新任务读取，不能因新工作树没有它就重新造一份不一致的方案。

## 8. 最小充分验证

| 验证组 | 必须证明什么 | 执行边界 |
|---|---|---|
| 来源与范围 | 双方必要历史保留，邮件无降级，排除路径未被更改；无秘密/真实日志/产物入 diff | 精确目标/来源/候选指纹，diff check |
| iCore + 邮件 + activity | 原 API 与 auth、批量原子性、双幂等、撤销、cursor/resync、unknown/TTL、retention 均保持；邮件发送全用 mock | 完整 `tools/i_core/*.test.mjs` 组合；消除继承的真实启用环境，仅用合成库 |
| 新冲突回归 | startup/listen 失败、relay 自有/外部所有权、关闭异常、重复关闭、graceful shutdown、retention timer 停止 | 复用已有覆盖，缺失的实质交互才加测试 |
| 默认模式兼容 | 无 activity admin 时的旧库启动/迁移、副本角色、聊天/邮件健康与权限；launcher 继承合成 admin 值也不能意外启用；启用模式和休眠模式不能混称 | 旧 schema 合成 fixture 与临时副本，拒绝使用真实数据库；按承诺核查 schema 与内容不变量，不能仅比较 WAL 文件整体 hash |
| HTTP + 三 probe | fixture 所有 case 与期望字段被消费；Core 重启降为 unknown；撤销旧 token 被拒；teardown 真正完成 | HTTP runner + human harness；若 full Node 已覆盖，不重复计数；独立 CLI 报告需可复核 |
| Dart reader | 严格只读，未知值保守处理，无 UI/DI/collector 接线 | reader 专项测试与相关路径 analyze |
| Gate 1A-0 | fixture 字节稳定、合同依赖未损坏 | 相关 Dart 测试/CLI；沿用已验证内容须出示等价性与新环境理由 |
| 主线保全 | 候选未引入 P6/白板/BLE 等变更；最终落地前后无关 staged/unstaged 内容及语义保持 | 独立 diff 复核、主线/索引指纹比对；禁止用全量重测代替范围检查 |

测试按最终组合执行一次；返修后按影响复跑。只因为 MDA 代码合并不构建 APK、不刷新现有 App 候选、不重跑 COROS 整夜 Gate；若后续确需 Flutter build，遵守 critical-fixes 前置与 hereIAmV3 限制。

历史三 probe 用户验收有效；合并产生的是新组合证据。若只做等价整合，不需要用户重复演一遍相同合成操作；若修改原验收所依赖的产品/恢复语义，必须明确哪些验收结论需要更新。

## 9. 已知限制与失败去向

原候选保留三项 P2：删除后最小身份元数据尚未随一天 raw 完全擦除；同步 deep preflight/health 无性能 Gate；listen 失败内部清理可能导致 close 子字段偏乐观但整体失败。whole-Core 备份不可写激活另为已接受的能力限制。

这些在原隔离 Goal 中非阻断，不自动代表生产升级也无风险。若默认主线行为或新组合使风险扩大，由新任务重新定级；不得为了“清零”无条件扩成新的大开发，也不得照抄非阻断标签忽略实际影响。

- 合并冲突/组合测试失败：回集成工作树返修，原主线保持可用。
- 发现权限越界、邮件可能发送、恢复误判或真实配置被继承：停止该验证入口，先修隔离，再恢复合成验证。
- 只剩主线写入窗口或运行路径确认未满足：完整交付候选、验证和精确剩余条件，独立工作继续到可审停点。
- 主线源码回退与数据库回退分开。代码 revert 不证明 schema/数据可逆；现有 activity rollback 仅允许空活动域且需 authority，已有 principal/event/receipt 时不能承诺自动降级。未经部署本次不用操作真实库。已经部署的场景需单独验证恢复方案。
- 不删除旧候选工作树，不清理他人临时目录，不在失败时 reset 主工作区。

## 10. 新验收任务的交付

先阅读本方案、当前主目录 AGENTS/协作协议及来源 Goal，复核其在自己工作树中的版本差异。新任务若由应用默认分支建工作树，必须先确认实际起点；需要时另建从本地 `v3-lab` 精确 SHA 出发的集成树，不能把默认分支误当目标。

请交付以下内容，并自行决定需要哪些 worker：

1. 对本方案的“采用 / 修订后采用 / 退回”结论及具体证据；不要只回复“等待用户批准方案”。
2. 选定的合并方式、精确基线、来源清单、文件所有权和运行时影响裁决。
3. 若准备候选：可复核的 commit 或 diff/指纹、四项冲突决策、测试结果、剩余条件及独立复核结论。
4. 分别说明方案、候选、主线和真实运行状态。本轮要求是生成方案并移交验收/执行方式裁决，未直接要求修改主线；方案通过本身不授予实际合入权限。新任务完成可审候选后，若仍没有收到后续合入授权，再一次性提出精确候选、具体主线动作与影响；不要在起步阶段重复求许可。

本方案不是新的功能 Goal。原 MDA-1 的完成状态保持；新任务可直接用集成计划推进审查和可逆候选工作。push、发布、真实部署以及 MDA-2～5 未获本次授权。

## 11. 交接登记

- 新任务创建请求已受理：`client-new-thread:74f2188e-8c1d-4f70-81d0-de0c37a77947`，host `local`，使用项目 worktree 模式。请求标题为「MDA-1 并入 v3-lab｜方案验收与集成裁决」。当前仅返回创建标识，尚未取得真实 thread ID / 初次接管回执；不得将该 client ID 传给要求 thread ID 的工具。
- 初始消息已包含本方案绝对路径、精确双方基线、用户本轮要求及启动/迁移/备份检查点；新任务就绪后接收完整委托。来源任务未重复创建第二个任务。
- 本任务验证：Git 基线复读、代码默认迁移/备份路径审计、方案相对引用和 diff 检查；不冒充合并后组合测试。
- 方案正文是新任务的输入；新任务可以基于新证据修订，并保存裁决理由。
