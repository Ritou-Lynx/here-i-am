# P6 普通聊天入口接线与验收范围

2026-09-16 01:54 接续：78f6固定四规则实际只读缺席已证；38/39新包399pins通过且已实际启动，38预检完整0。固定入队文字已复制，原生工具连续检测手动输入，尚未粘贴发送或创建新任务；等待接手原窗口继续普通入口控制。冻结候选保持，旧36失败不改写，P6/Goal1未完成。详见[当前接续](P6_R7_PRODUCT_ACCEPTANCE_20260916.md)。

2026-09-16 当前：36普通enqueue/status成功，start安装阶段timeout/1223失败，未进入running或执行pause/resume；普通232事件及两个精确终态闭合，App/Node已精确失败收尾、原Witness4，无后继37。失败任务保留，78f6固定规则检查已准备并通过独审，尚未执行。详见[9月16日接续](P6_R7_PRODUCT_ACCEPTANCE_20260916.md)；下方为历史，P6/Goal1未完成。

2026-09-15 当前：c874/7574规则只读缺席已证，失败30精确收尾。32普通短聊零工具、固定任务唯一enqueue、两个provider终态及session closed已核，首App/Node原持柄正常退出各0。唯一33后继预检失败，未ready/无execution，App/Node已精确清理、原Witness4，pending任务保留；251b规则状态待固定只读检查。执行控制及成功同库恢复仍待，见[9月15日现场](P6_R7_PRODUCT_ACCEPTANCE_20260915.md)。下方9月14日状态为历史，生产默认拒绝不变，P6/Goal1未完成。

更新：2026-09-14 23:47。owned28真实普通短句因旧CLI被模型拒绝，匹配failed/closed、零工具调用及tasks[]已证；第一次App/Node正常关闭各0，后继29预检Windows确认未完成后失败。已精确清理29的App/Node，原Witness actual4不改写；c874规则只读检查未启动成功，仍unknown，诊断02已备。47831按既有重启授权改用现有新版CLI，原ChatGPT认证与47841保持；新版实际模型话轮待验。30/31新包399pins匹配但未启动，待人工弹窗操作时机后继续。普通入口、最终恢复及P6/Goal1未完成，详见[现场记录](P6_R7_PRODUCT_CANDIDATE_20260914.md)。下方旧状态及原 A–E 表为历史。默认生产文字队列仍关闭。

## 主控实施更新

- 新 `lib/p6_r7_product_main.dart` 装配独立 Store、真实桌面聊天组件、原 coordinator 和当前原话授权工厂。普通输入先持久化，再发送；无生产 DB 单例、同步 outbox、关系检索或额外产品工具。原发送 helper 只提取成可注入的共享接口，原 PersonaChatService 持久化行为保持。
- 普通会话由 App 自有 Node guardian 代理到固定47831，只持有本次精确 session/turn/tool-call；后台任务仍走原零工具 native 链。queue 调用串行；首次结果完成 Store 校验、witness 绑定和宿主注册后才返回模型；关闭拒绝尚未派发调用。
- 关窗依次关闭本次普通会话、队列和自有 host，等待原 monitor tails 后关闭 Store/client，再提交真实 app_closed。普通关闭回执包含完整六字段身份，unknown 不提升为成功；不会停止共享 Gateway。
- **首个普通入口候选仍只允许固定公开任务**：标题“公开文字验收”，目标“只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。”。输入确实通过普通聊天和动态工具传入，但 Store、scope hash、恢复校验仍固定该目标。初稿的“首轮支持任意目标”不适用；一项任务、一次后继保持。
- owned22/23 App异常退出恢复已经完成实际验收及独审，详见[恢复验收](P6_R7_OWNED_RECOVERY_20260914.md)。它不能代替新普通入口 Gate。
- 新 worktree `.worktrees/p6-r7-product` 基于 `389aa735`，按主目录当前所选字节逐文件记录来源，不称纯 HEAD。seed 为182 Dart文件/23 roots；仅在新候选的两个文件重绑定受信 Witness05 路径/哈希，旧冻结候选不变。
- 新候选 Node76/76（`26fdc8`）、App与相邻恢复191/191（`5e16a1`）、相关源码分析No issues（`496968`），均实际exit0。Witness05仅重绑定三个固定路径，原合成10/10及Core553 checks通过。构建前critical3/3通过；构建与bundle/hash另记，不继承旧App02。
- 离线依赖准备首次因缓存登记子目录缺失退出66（`efe921`）；补齐该子目录后第二次退出0（`5e3323`），lock未变。旧失败保留，不改写为成功。
- Windows构建实际exit0（`a763c0`）；App冻结209源/152bundle，24/25启动包399pins和24源Node闭包，Witness05真实配置构造器只读校验通过（`d84802`）。精确产物和未启动边界见[唯一候选](P6_R7_PRODUCT_CANDIDATE_20260914.md)。
- **实际接入阻点**：现场`674957`确认原47831 Node身份保持；`8fef40`健康正常，但普通模型入口未启用，`/auth`和`/capabilities`返回404。本次没有发起模型话轮或读取认证/历史/真实队列。已询问启用该入口并重启这个共享服务的具体授权，答复前仅准备候选和脚本。这不是因进入新阶段而重复审批。

实际实现见[App入口](P6_R7_PRODUCT_APP_BOOTSTRAP_HANDOFF_20260914.md)、[聊天组件](P6_R7_PRODUCT_CHAT_SURFACE_HANDOFF_20260914.md)、[会话](P6_R7_PRODUCT_SESSION_HANDOFF_20260914.md)、[guardian](P6_R7_PRODUCT_CONVERSATION_GUARDIAN_HANDOFF_20260914.md)、[宿主组合](P6_R7_PRODUCT_HOST_INTEGRATION_REVIEW_20260914.md)、[固定transport](P6_R7_PRODUCT_GATEWAY_TRANSPORT_HANDOFF_20260914.md)、[Witness05](P6_R7_PRODUCT_WITNESS_PATH_REBIND_HANDOFF_20260914.md)、[封包](P6_R7_PRODUCT_PACKAGE_PREPARATION_HANDOFF_20260914.md)。未新增初稿中的空 host/recovery 包，未为此改全局 main/router/dependencies。

剩余工作是完成唯一候选构建/封包，在具体服务变更获授权后核对有限认证类型和能力，通过普通聊天验证无自动入队、明确入队/查询、合法执行控制和结果，并收齐新组合的普通会话终态及退出。动作矩阵按实际资格记录，不能伪造失败填retry，也不能将旧候选动作直接填为新入口通过。当前不称P6或Goal1完成。

## 当前事实与完成边界

- `lib/data/workbench_ai/workbench_conversation_coordinator.dart:115,185,695,727` 已注册生产 queue tool，并从当前用户原话取得授权、分派动态工具；不是“没有产品工具入口”。
- `lib/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart:41-78` 已按 TaskRoomService 实例缓存一个 execution，并注册 lifecycle owner。生产默认仍取 TaskRoomService.instance 和默认 Runtime client；不能只注入新的 endpoint，却让任务写入原服务。
- `lib/main.dart:561-568` 在 detached 后 unawaited 请求 close。`workbench_task_queue_lifecycle_owner.dart:35-38` 明确是 best effort，不是 native 终态或恢复许可；页面退出不等于任务取消。
- `tools/dev_agent_bridge/dev_agent_bridge.mjs:38` 构造普通 ExperimentalRuntimeApi，没有 textAdapterFactory；`experimental_runtime_api.mjs:208-213` 无 factory 时拒绝文字会话；`workbench_text_only_profile.mjs:8-30` 固定 available=false/fail_closed=true。普通 Codex adapter 的 start/resume 仍调用该拒绝门控。
- 独立候选入口 `lib/p6_r7_candidate_main.dart` 已有 App 所有的 Node、独立 witness、专属 Store、会话资源和原句柄关闭链。candidate configuration 明确限定 Debug、固定 admission/root/pins；它不是可直接用于任意生产目录的通用接口。
- App 23 路径 / Node 12 路径本地集成及 159/159、200/200保留各自源码证据；没有由此产生新主目录构建证据。当前构建准备由主控串行处理。
- owned14/15 正常 retry/recovery 和 owned22/23 App异常退出恢复均已有实际证据；新普通入口不继承这些候选的通过结论，也不机械重开未受影响的旧阶段。

证据入口：[当前恢复验收](P6_R7_OWNED_RECOVERY_20260914.md)、[主接管](GOAL1_MAIN_ACCEPTANCE_HANDOFF.md)、[集成独审](../../../tmp/p6-r7-review/integration-independent-review.md)。早期 queue handoff 的缺执行器描述已经被当前代码取代；其指定任务、普通短聊天、最终真人 Gate 约束仍有效。

## 本轮采用的接线方向

先做“普通 UI/授权路径 + 独立数据与专用执行宿主”的显式验收配置。普通 release/default 启动继续使用原有关闭门控。独立配置必须由固定 bootstrap、编译候选与可信 admission 同时约束，不能用单个环境变量、任意 URL 或模型参数解锁。

普通对话 Runtime 与后台文字任务 Runtime 分开注入：前者继续使用现有已授权的对话路径，后者只连本次 App 所有的专用 host。不能把具备动态工具的普通 adapter 当作受限文字执行器；不能把现役 Bridge 全局替换为候选 host。普通对话的实际发送仍须在该轮受控入口 Gate 明确确认其既有 provider/费用来源，不在工程测试中自行发送。

第一轮数据方案必须在写码前审定：所有验收 TaskRoom 仅使用新建独立服务/数据库；普通 UI 可能打开的聊天、设置及其他服务，也必须由隔离配置显式供应受控数据或拒绝访问，不能留下 fallback 到个人库的单例。复用现有服务实现与普通 UI，不复制个人库。若现有依赖注入不能保证这一点，先交付注入缺口和最小改动，不能以候选按钮或 mock coordinator 代替普通入口通过。

## 工程包与接口

以下保留初稿拟议分包供追溯，实际更小的构造注入方案和首轮固定目标限制以上方实施更新为准。共享文件由主控顺序集成；冻结 App02、Node39、Witness04、addon02 和实际记录只读保留。原生 witness 如需适配新候选 pins/路径，另建独立候选并审最小差异，不修改冻结文件或放宽 guards。

| 包 | 拟拥有路径 | 具体实现与接口 | 验证和完成定义 |
|---|---|---|---|
| A：受控产品会话组合 | 新 `lib/data/workbench_ai/product/workbench_task_product_session.dart`、对应测试；协调修改 `workbench_runtime_task_queue_tool.dart` 和 `workbench_conversation_coordinator.dart` | `WorkbenchTaskProductSession` 显式持有 taskService、textRuntime、execution、lifecycleOwner、ownedHost、resources。普通 coordinator 使用注入的 queue tool；保持同 service 一个 execution。未提供受控会话时维持原 production() 行为。模型不能创建/替换该会话或指定数据目录/endpoint。 | 受控 service 与普通单例互不混用；重复工具调用共享 owner；无配置/无可信 admission 时零 host spawn、零独立队列执行。覆盖 exact task ID/scope、否定动作、短聊天零 enqueue 的现有关键回归，不重写队列状态机。 |
| B：应用关闭与资源持有 | 新 `lib/data/workbench_ai/product/workbench_task_product_close.dart`、对应测试；主控拥有 `lib/main.dart` 与现有窗口关闭入口的最小接线 | 用户关窗先封住新 queue 写入/新 turn，再等待 lifecycle/owned host 关闭，join 原 execution tails，随后 close Store/client，最后提交 app_closed 并退出。复用 `P6R7CandidateSessionResources`、owned host 和 witness 的严格语义；提取通用部分时保留候选回归。`close()` 返回 confirmed/unknown，幂等且 unknown 不提升为成功。 | 正常可拦截关闭必须 await；detached 仍只作为无法等待的兜底，不能提交成功证明。覆盖新 owner 与关窗竞态、pause/cancel 后残余 monitor、双 EOF/Node 实际退出缺失、Store/client close 失败。未完成时不发 app_closed，不先关 DB。页面退出和后台化继续不取消任务。 |
| C：专用宿主启动与能力投影 | 新 `tools/dev_agent_bridge/workbench_text_task_product_host.mjs`、对应测试；按需最小修改 `experimental_runtime_api.mjs`，现有 candidate/successor 两入口作为回归基线 | 共用既有 textAdapterFactory、native transport、broker 与 witness binding。只有固定启动器验证闭包、App/Node 身份、preflight/admission 后才能为本实例注入 factory。对外能力来自当前实例实际状态；失去 owner/witness、quarantine、closing 时立即拒绝新会话/turn/attestation。 | 默认 `dev_agent_bridge.mjs` 不注入 factory，普通 adapter/profile 仍拒绝。验证未绑定/错 pin/未知状态/迟 ACK 后无复活，受控关闭保留 DELETE/events 清理通道。默认 broker 60s、裸 transport 10s不改变；candidate 的180s不能无说明扩散为全局默认。 |
| D：数据恢复与可信启动包 | 新 `lib/data/workbench_ai/product/workbench_task_product_recovery.dart`、对应测试；新的独立 bootstrap/witness 封包目录由主控指定 | 将候选的 immutable origin 与 live admission 分离、BindOrigin、task/scope 绑定、claim/consume 单后继语义接入受控会话。只在核验可信存活 witness、原 authority 完整终态和同库完整性后开放 RW；独立数据服务负责恢复 interrupted 后等待。 | same path/UUID/source/native/origin 不可重写；claim 重放/跨库/缺 owner/Node crash/witness restart/未知退出一律冻结。仅支持已验的 normal 与 App 实际死亡+Node完整正常关闭；不新增任意代际、跨系统重启或“旧 PID 缺席即可恢复”。 |
| E：普通入口隔离装配 | 主控顺序拥有 `lib/main.dart`、`lib/config/dependencies.dart`、实际依赖入口；必要的 `lib/data/repositories/memex_router.dart` 最小注入；新测试专属配置文件 | 用明确 Debug 验收配置装配普通桌面聊天组件、同一 coordinator、同一授权 factory 和上述会话。不得借此改生产默认数据库定位或普通 provider。先列出全部可达 DB/service 单例，再给出逐项隔离或禁用映射。 | 无配置启动与现有行为一致；受控配置不访问真实 TaskRoom/聊天/记忆库、不自动启动后台服务或手机连接。产品任务目标来自当前授权输入，不再固定2000；普通目标经现有文字执行权限约束。 |

A/B/C/D 可在互斥新文件中准备，E 与共享文件、生成、构建必须串行。若依赖检查表明新增通用模块并不必要，采用更小的构造注入补丁；不得为了表格拆出空包装层。

## 不能原样移植的候选限制

1. 固定数字按钮、单 task UI、固定 dataset/scope、localFailurePlan 和预设输出 SHA 是验收设施，不是产品 API。产品工具继续接收既有受限业务字段；不新增模型可控的失败开关、native 身份、permit 或授权字段。固定公开数字任务仍可作为 Gate 输入，但不是代码内硬编码的唯一工作。
2. Witness04 的首代 admission、一次 task 绑定、单 successor 和正常关闭合同是已验证边界。第一产品候选仍可明确限制一项并发验收任务和一次恢复；不能悄然宣称支持多个生产任务/无限恢复。需要多任务支持时单独审 owner/task 集合契约，不能删字段绕过绑定。
3. App异常退出路径不得把缺失 app_closed、Store.close、Dio.close 写成 true。只采用原 held App 实际死亡、Node 有序 unexpected stdin EOF、所有登记 owner 完整终态、Node held0 的独立闭包；同库 integrity_check 只能证明一致性，不能证明 freshness 或旧 authority 已死。
4. 原 Node 正常关闭含显式 shutdown 标记；意外 EOF 才进入 App quarantine。stdout 镜像失败不授予 EOF/恢复权限。native 的 spawn 后 live capture 不称原 CreateProcess 返回句柄。
5. 当前受控 bootstrap 的私有 ACL、路径和身份 pins 不是部署安装方案。新候选路径变化必须生成新闭包和可信 pins；不复制旧 permit、不改 marker、不接管私有审计目录。

## 分步交付与 Gate

1. **方案审查**：主控确认普通入口与独立数据的完整依赖映射、A–E 最小路径和接口；明确哪些冻结模块直接复用、哪些必须产生新候选。此步不启用生产、不构建“看似可用”的空壳。
2. **实现与本地验证**：每包提交精确 diff、相关回归、changed-file analyze 和默认关闭证据。fake/synthetic 只验证指定合同；不能被记录为实际普通入口、真实模型或恢复通过。旧测试已经通过的部分仅在受影响时重跑。
3. **整合与唯一构建**：主控核对分支/HEAD/已有 dirty，保存来源清单，串行跑受影响组合与每次 build 前 critical 检查；生成唯一 Windows 候选的源、exe/bundle、host/native/addon/witness/bootstrap pins。当前进行的主目录源码构建如早于本方案接线，只能证明那个源码组合可构建，不能替代未来接线后的唯一 Gate 候选。
4. **受控普通入口实际 Gate**：仍用全新独立数据和固定允许目录、端口与启动包；走普通桌面聊天→当前原话授权→动态 queue tool→真实受限执行器。依次验证明确 enqueue/status、合法 start/pause/resume/cancel/retry、运行中重启后可见 interrupted/等待、无自动执行、显式继续。固定公开数字输入用于核结果。实际故障只按当轮精确包执行；没有资格的状态不能伪造后再“验”转换。最终可由既有自动拒绝测试加实际合法动作组成证据，不通过真实其他任务构造越权反例。
5. **关闭与独审**：对新候选记录目标、scope、动作/实际终态、源与产物哈希、退出和资源证据；确认短普通聊天未创建 TaskRoom。旧 UI-T/P4/P5 已接受的范围不机械重开；若接线触及其普通聊天/数据装配，做针对受影响路径的回归。主控据新候选实际证据判断 P6 Gate 是否满足，最后统一更新 Goal/项目状态。

第4步是新的受控普通入口实际验收，不能用14/15或22/23的独立候选结果直接填通过。可先完成前三步，形成具体可审产物，再进入已有授权覆盖的实际步骤；任何新增真实数据或服务切换需由主控明确识别，不能混入封包。

## 本轮明确不执行

- 不查询、启动、取消或重试历史真实任务 `fc91503a-0e59-4f7f-a480-14215e67cb05`，不扫描真实队列。
- 不替换、停止或重启现役 App/Bridge，不占用它们的端口，不启用默认生产 profile。
- 不改 provider、认证方式、费用来源，不重新登录，不读/复制 auth 或个人数据库；不安装、推送或发布。
- 不增加 TaskArtifact 上板、Agent树、普通聊天自动排队、多任务调度或无限恢复。

这些边界不妨碍现在完成候选接线、受影响本地验证、独立审查与构建准备；它们避免将工程产物误称为真实队列/默认生产已经启用。
