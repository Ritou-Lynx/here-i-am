# Prepare 后现场链：已有证据、剩余门槛与提前验证（2026-10-07）

本页是独立只读审计与合成验证交接，不是新一次现场执行回执。基线 `ffbb0e89cddc6c910b95d528d5575ac153dcc9b8`，PR20 草稿。仅拥有本文件及忽略目录合成工件；未改 runtime、测试、CI、全局状态或现场清单，未 commit/push。

用户本轮给最后一次 Core 切换机会，截止 **北京时间 2026-10-09 18:00** 要完成四项真人 Gate；否则停止本轮推进，回上海再继续。截止不是数据库降级授权：若已经跨提交边界，或 pending 导致精确 ACL 库存漂移，不能为了截止强行退回旧 schema4。本文没有创建提醒或未来自动操作。

## 当前事实与证据优先级

- 以[settings 授权及 r02 实录](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)最后几节为最新现场事实。r02 本机**真实停过旧 MCP 和旧 Core**，并真实 Apply、恢复144项权限；不是所有链路都从未在本机执行。
- r02 正式 Prepare 在 `prepare_owner_rejected` 停止。该次 `acl-apply.json` 由提升进程创建，其 owner 是 Administrators；拒绝发生于实际 fixed Prepare 之前。没有成功 prepared XML/准备回执、注册回执；新任务从未注册/启动，fixed Start 未触碰原库，原库未迁移替换、head 未推进、四项真人 Gate 未做。
- 21:28:57 真实退回签收，21:31:20 独立复核旧任务原定义/SDDL、各1实例、完整树 Core 3/MCP 4、三端口与 schema4。它们是 **r02 时间窗证据**，本 worker 未重新读取实时任务/端口，也不把旧 PID 当现值。r02 已消费；不删锁或复用。
- [现场清单](SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)、[运行操作](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)、[本人单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)保留多个历史阶段。旧“Core未停”“未Apply”“模板省略Unified”“仅文档零停机”只属于当时阶段；当前模板显式 Unified=true。未来操作顺序参考清单，已执行事实以 r02 实录覆盖。

下表“真实”指本机生产现场；“合成”指隔离数据/任务/进程。Hosted Windows COM 是另一环境，不冒充本机生产注册。

## 整个实际链逐项对照

| 阶段/顺序 | 本机真实执行状态及准确已有证据 | 本机尚可能出现的差异 | 失败停点、原件边界与退回/前修 | 可提前做的只读/合成验证 |
|---|---|---|---|---|
| 0. 新窗口重新绑定、冻结旧任务（Prepare 前置） | r02 已执行：两旧任务触发/重试冻结、完整树与外锚、65秒以上观察；冻结回执 `b1dccd26…45f64`。当前已恢复。 | 在线写入、PID/创建时间、conhost映像、任务父SD/ACL、盘符/USB可能变化；旧窗口已失效。 | 任一偏差在停机前拒绝。必须新ID、新完整只读演练；旧回执不可借用。 | 已有100711ms全套只读演练证据。本次仅核固定47库存、精确46 Git blob及OS/COM，未重做生产全套。 |
| 1. 先停旧 MCP、在线副本、再停旧 Core（Prepare 前置） | **r02 已真实执行**。21:14:54 MCP停止；21:15:12 Core停止，连续69525ms无重启，原四件关闭后严格核验。停止不是旧v4 clean-close。 | 任务停止不代表孤儿树/SQLite句柄退出；额外读库工具不属于已知MCP Job；系统进程可能有合法硬链接。 | 未证实全树/实例/端口/句柄退出就停。未跨提交边界且原库存/兼容schema4完整才按受审方案恢复旧链。 | 只读完整树/映像/端口与元数据可提前核；不能用合成关闭替代本机当次退出。此次未再启停。 |
| 2. ACL Apply → 正式 Prepare（当前阻断点） | Apply 144项/432条、16旧owner真实归正，随后Prepare拒绝；`acl-apply.json` SHA `eba07c80…df632`。实际 fixed Prepare 尚未调用。 | 提升writer和非提升consumer的owner/ACL语义不同；配置目录继承、逐路径身份与剩余冻结租期仍可拒绝。 | 保持严格owner检查。r02未出现pending/提交，故完整权限退回成功。不能改旧证据owner再重试；新维护源码/CI/新回执须重新闭合。 | 本 worker不修改writer、不UAC。本次固定模板AST→合成XML→本机内存COM通过；这不覆盖真实提升writer串联，不表示正式Prepare成功。 |
| 3. Prepare输出XML逐字比对与准备成功回执 | 生产尚未到达。批准XML `4bc64357…397e`，候选 `3b7e210b…147fa0`，login `28c5b700…e1e00`；六项完整锚见r02授权文档。 | 固定ValidateOnly会核本人owner/ACL、路径/单链接、MCP配置、备份/key/control、非零生产端口及配置hash；模板可用不证明所有路径均可用。 | 无真实准备回执、XML不同或冻结复核失败，不注册。只是内存模板生成时不能发成功生产回执。 | 本次运行固定包模板原构造片段，验证原设置/绑定与COM；0注册/启动/删除。未读真实配置正文/密钥。 |
| 4. 新任务 CREATE-only 注册、回读 | **新生产任务从未注册。** 旧本机禁用/无触发合成任务曾揭示Unified/P位差异；修订模板与双SDDL已批准。Hosted真COM通过只能作异机证据。 | 本机Scheduler规范化、父SD继承、权限、同名竞争、CREATE返回与落盘结果可能不同。NewTask内存成功不保证RegisterTask成功。 | RegisterOnly只CREATE=2，不Run；精确四节/SDDL/零实例/冻结重核全过才继续。失败若已返回本次对象，保留并尝试禁用；未返回对象则outcome unconfirmed，不能按名字删/禁竞争者。新任务未明确静止前不得恢复旧任务。 | 本机旧创建额度已用完，本次0新创建。可做内存COM/SDDL推导/父SD只读；再做本机真实合成CREATE需主窗取得明确新授权，不能自行增加。 |
| 5. 由获批任务进入交互式launcher、创建新session/control | 新schema6任务从未启动；fixedStart未触原库。已有本机隔离launcher烟测，非实际任务触发。 | InteractiveToken是否存在、任务会话/桌面、PS/.NET/WinForms、路径权限、端口占用与隐藏窗口创建均是本机集成点。 | 必须通过同一获批任务/launcher；不旁路手工开supervisor冒充。启动失败先辨识是否已产生pending/原件提交，再决定处置，不开第二实例。 | 本次固定session_window/owned_job在PS5成功编译；没有创建窗口/Job。历史隔离测试证明launcher组合，不能替代实际任务启动。 |
| 6. native离线lease、打开SQLite前raw加密保全 | r02只完成冻结及四件严格核验，**本轮固定Start/adoption的raw保全未执行**。历史九类真实备份/检查恢复存在，但不是这次离线原件保全。 | 未管理SQLite读者、文件链接/ACL、盘满、密钥/DPAPI、加密写入/Flush失败可能拒绝；只看端口空不够。 | 真实lease与原四件原始密文/认证摘要验证齐全前不打开SQLite原件。生产拒绝任意JSON lease。新pending即为停点，见下文库存规则。 | 本次raw四件加密/核验、篡改密文拒绝、任意JSON lease拒绝均通过。相关恢复用例替换了OS lease模块，不能声称本机原生独占已再次验证。 |
| 7. 隔离副本回放WAL、4→5→6、完整性/身份/授权校验 | r02前在线真实副本/隔离4→5→6通过，72 replay、1 grant，验证回执 `f65c2b49…fdc1`；**这不等于原址adoption**。 | 当前库/sidecar/授权/设备状态可能变化；真实库体量、权限、IO延迟与合成不同。 | 校验失败原四件保持；保留raw密文、pending、错误回执。不自行删除pending重新尝试。需满足精确库存与受审恢复条件，才可能退回旧链。 | 本次脏WAL legacy4迁移只在副本、identity保留、提交前注入失败原件不变、损坏原件被归档后拒绝均通过。 |
| 8. 短提交：commitStarted→移动sidecar→替换canonical DB→独立head | **生产从未执行。** 源码recovery_adapter明确顺序；本次仅合成替换后中断。 | sidecar移动、Windows文件替换、头写入/rename/Flush不是一个SQLite事务；可能卡在多文件间隙。 | **commitStarted=true、原库替换、head推进、新写入任一发生或无法排除，只向前修。** 保持writer停止，保全新原件/raw/head/回执，不恢复旧ACL后盲启v4、不删latch/倒退head。 | 本次替换后故障使下一次启动以`recovery_interrupted_review_required`拒绝；head不默默回退。旧完整库+旧floor被独立head拒绝。此证明拒绝机制，不提供自动回滚/自动续跑能力。 |
| 9. 新 Core schema6 ready、单实例与运行策略 | 生产未启动。既有固定候选合成Core smoke与整组通过，实际生产仍schema4。 | 原state/config/DPAPI、47841占用、node_id/设备、grant/replay、原锁与guardian结束状态可能拒绝。 | health=ready还须精确候选/身份/单实例和owner policy；只保留legacy_b3、reply jobs/activity关闭、邮件debug disabled。无ready按阶段回执处理，不能改配置/删锁放行。 | 固定47/46源码本次核验通过。合成恢复用例实际新开临时Core端口并正常关闭，非生产47841验收。 |
| 10. 会话在Core ready后启动同字节MCP及备份调度 | 生产新会话未运行。r02只恢复旧独立MCP任务。既有隔离MCP使用真实旧6模块、OAuth/initialize/i_recall证明曾开read model。 | MCP现有.state权限、真实账本/WAL、OAuth、监听47860/47862、隧道、外置USB/key与相对import可能失败；Job仅证明所属树。 | MCP失败粘滞，不允许Core数据安全关闭掩盖会话失败；恢复前先排空所属MCP。禁止恢复旧MCP独立启动造成双实例。备份/镜像失败分别记录，不冒充已镜像。 | 本次仅编译固定会话源码；历史组合烟测/两档规模是隔离证据。未读.state、凭据或真实账本；未调用公网。 |
| 11. 真实请求打开MCP read model，随后立即真人关机（Gate 1） | **本候选生产未执行。** r02没有让用户关机。历史合成WM消息验证非真人系统关机。 | OS关机预算、隐藏窗、Windows会话结束、杀进程、额外持柄与在途备份；系统仍可强制结束。 | 同一30秒预算：停派发→MCP树退出/句柄释放→备份排空→Core认证close。MCP最多3000ms grace后可force所属Job且如实标注；Core child/guardian exit0、Job空、无force、clean_closed、锁释放必须全齐。超时为recovery_required，不能以后恢复成功倒填本Gate通过。 | 本次未发WM消息/未关机。已有隔离真实MCP+WM+Job证据及10×/50×单样本，只降低风险、不保证这台机真实关机通过。 |
| 12. 真人开机登录后的自动任务→新control→Core/MCP恢复（Gate 2） | **未做本候选真实登录触发。** 隔离launcher重复启动不是AtLogon实测。 | 实际登录/用户会话、任务触发、开机IO、凭据解锁、网络就绪；ARSO可能先自动登录再锁屏，本机尚不确定。 | 新RunId/control、schema6 ready、单47841、备份调度、自动MCP与一次成功真实请求均需签收；不得手工启动冒充自动。出现恢复先清MCP，再查raw/head/pending，不盲重启。 | 可提前只读任务定义/OS版本；本次仅版本与COM元数据。未读/改ARSO策略；普通关机登录Gate不等于更新重启ARSO实验。 |
| 13. 正常手机聊天同步及outbox去重（Gate 3） | **新候选未做。** 旧手机快照/旧包证据不覆盖本次。 | 实际路由/token/连接、手机前台策略、待交队列、断续、accepted/去重与47862消费者。 | 用原sync_id/op_id保留队列；不得丢队列/跳cursor/加第二上传器。手机安装/改配置、PR10启用与47862退役不在此次范围。 | 只能用源码/合成协议证据预检；实际手机正常链路必须本人操作并给无正文耐久回执。 |
| 14. claude.ai真实公网写入（Gate 4） | **新候选未做。** metadata200、隧道ready、合成OAuth调用均不是此Gate。 | 公网会话、MCP session404需initialize、pending账本、客户端重试与网络可达可能不同。 | 必须真实客户端成功回执及Core耐久接受；waiting_for_retry/unavailable不算完成。必要重试沿原op_id，核pending完成，不重签token或重造消息绕过。 | 可只读元数据/协议合成；本worker未发真实消息。此Gate须本人执行授权写入，不能提前以健康接口替代。 |
| 15. 异常恢复/关机取消/以后日常备份（后续运行分支） | 新生产候选未经历。已有本机隔离异常Core/MCP/backup测试与异机CI；不等于本机生产断电演练。 | 断电时无终态回执、未确认ACK、磁盘满/USB离线、未管理reader、控制文件权限、启动中断。 | 先确认所属旧MCP树全退，再raw→副本→head校验；pending永远停给审查，不删除重试。新control重开，不复用token；backup_read_only不激活。镜像失败保留本机密文。 | 本次已验证已提交WAL保留/未提交事务不出现、独立head拒回退与中断阻断。OS lease由合成模块代替，未故意断电或停生产。 |

## 两条不能合并的退回边界

1. **r02 已证实的可退回范围**：新任务未注册、fixedStart未调用、没有pending/替换/head/newwrite，144项精确库存成立，原四件及外部授权、旧包/配置原样。原owner/DACL恢复/readback完成后，再恢复旧定义，按Core→MCP启动并真实复核。r02 rollback SHA `fb200c61…ae29a`、恢复前复核 `2fde3aa0…bdad1`、运行恢复 `b0526dee…21d0`。不得把这个成功范围外推至后续阶段。
2. **fixedStart以后，即使尚未替换也不保证可退回**：`s6-recovery-pending.json`、临时副本或marker可能使144项库存不再精确。现场清单已要求停写保全，记录新增路径/阶段并提出受审恢复方案，禁止直接Rollback、删除新增项、改变144常量或启动v4。源码把pending视为审查闩锁，不是可续跑状态机。只在完全排除提交且精确库存/恢复能力重新闭合后，才有受审退回路径；跨提交或无法排除则只向前修。

这也是截止约束的实现边界：在仍可安全退出时退出；已跨界时停止扩大动作，保全现场并向前处理安全状态，不能承诺到点恢复schema4。四项Gate没有全部签收，始终标“切换未完成”。

## 本次实际提前验证（均未操作现役）

执行时间：2026-10-07 北京时间约21:44–21:46。当前Windows **25H2 / 26200.9457**，64位Windows PowerShell **5.1.26100.9444**，CLR **4.0.30319.42000**，Task Scheduler HighestVersion **65542**。

| 检查 | 实际结果 | 明确未证明的部分 |
|---|---|---|
| 当前批准候选库存 | manifest `3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0`；47/47实际hash与size一致，46/46精确基线Git blob一致。无runtime修改。 | 未重新核生产配置/批准XML/双SDDL/父SD五个外锚，六锚完整核验仍归新窗口。 |
| 固定模板AST提取→合成XML→本机NewTask内存COM | 通过；原设置/绑定/Unified=true保持；taskCreates=0、taskStarts=0、taskDeletes=0。另一次checkout模板内存验证同样通过。 | 没执行Prepare bootstrap/live guard，没有真实RegisterTask，没有证明本机最终任务安全描述符回读。 |
| 固定session_window、owned_job内存编译 | 原字节在PS5 Add-Type成功，两个类型存在。sessionWindowCreated=false、jobCreated=false。 | 不证明窗口已挂钩、用户会话能启动Job、任务触发有效或操作系统关机能clean-close。 |
| 隔离恢复聚焦用例 | 既有automatic_recovery.test.mjs中选定 **9/9通过，0失败/取消/跳过，11287.2568ms**。未改测试。 | 未跑整组、未替代原生lease/生产ACL/实际登录/真人四Gate。 |

9项具体覆盖：任意JSON lease被生产拒绝；raw DB/WAL/SHM/journal精确加密验证及篡改拒绝；已提交WAL恢复（无未提交事务）；已提交WAL恢复且未提交事务不出现；legacy4脏WAL仅在副本迁移并保持identity；副本迁移提交前中断原件不变/下次拒绝；损坏原件先归档后拒绝；旧完整库/旧floor被独立head拒绝；原库原子替换后中断阻止下次登录且head未倒退。测试使用全新临时合成库及随机回环端口，只有所属合成writer被结束；测试加载独立模块时将OS lease替换为专用syntheticLease，所以只能证明恢复算法、顺序、原件保全与拒绝语义。

固定候选定位经历一次历史路径纠正：最初按旧执行文档读取1552e251旧包，hash不等于本轮批准锚即停止；主窗给出当前task-security-c9662439包后才完成47项复核。**这是旧路径选择错误，不是批准候选hash漂移**，未运行旧包helper或重写任何包。受限worker token最初无法读保护目录/写C副本；仅通过工具沙箱许可执行上述已授权只读/合成动作，没有RunAs、Windows UAC、任务注册或ACL Apply。

匿名回执在忽略目录 `build/ci/post-prepare-gates-5512f21ad9ef415db0c7034e9d8a4c3d/`：

| 文件 | SHA256 |
|---|---|
| runtime-inventory.json | 0e7b6d36a56c96d688efbfa532c7743d370ca0f78ec7b4e23488163927ff718b |
| fixed-template-result.json | 73802f123491c50de4529e121d0ddbeb00b98cd7bb3c17b096a6763ca095a3fa |
| host-memory-probe.json | 0a60f6159dca0b7932a95ee2e81cb1465a96cb268d782fe84eb8c1179fd9fc64 |
| synthetic-recovery.tap | 8dc184fb76cf4dcd8876576cca79ac832e5e86526a3abe4cadf0bcd9f55695bc |

## 复核入口与尚需主窗动作

源码：[Prepare模板](../../../tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1)、[实际注册入口](../../../tools/i_core/maintenance/register-approved-login.ps1)、[任务原语](../../../tools/i_core/maintenance/register_task_primitives.ps1)、[登录入口](../../../tools/i_core/release_schema6/lifecycle/login_schema6.ps1)、[会话关闭](../../../tools/i_core/release_schema6/lifecycle/session_window.ps1)、[副本与提交](../../../tools/i_core/release_schema6/recovery_adapter.mjs)、[自动恢复门禁](../../../tools/i_core/release_schema6/automatic_recovery.mjs)。历史隔离原生MCP/关机/重启证据见[MCP会话验收](SCHEMA6_MCP_SESSION_ACCEPTANCE_20261006.md)；Scheduler差异及新固定模板见[任务权限修订](SCHEMA6_TASK_SECURITY_REVISION_20261007.md)，CREATE失败行为见[维护注册交接](SCHEMA6_MAINTENANCE_REGISTER_20261007.md)。

当前未发现必须改变47项runtime的新增差异；本次预验证也没有排除全部现场风险。新的维护writer修复、实际提升writer→非提升Prepare串联、CI、全套新只读演练、正式新WindowId、真实注册/任务启动及四Gate均由主窗继续逐项签收。本worker没有新的本机合成任务CREATE授权；如要补该证据，先交主窗取得明确授权，不能用Hosted结果自动放行。