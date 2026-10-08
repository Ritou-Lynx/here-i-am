# clean-close 修复与 schema6 同版本换包（2026-10-08）

当前：schema6 已上线运行；本人确认开机后手机与 claude.ai 均正常。clean-close 为唯一未通过项。本轮仅源码、隔离测试、只读诊断；没有换包或再次真人关机。最终源码CI、候选锚及逐项库存差异由本机候选审批材料和PR对应head结果签收；本文件不构成进场授权。

## 审阅后执行约束（2026-10-08）

用户批准clean-close修复方向，换包暂不批准。先merge v3-lab并在新head重跑完整CI；同时今晚执行本机/T9完整加密备份及真实隔离还原。10/09 20:00重复安排已取消。动态custody清单在捕获前后各check，最新九类逐项覆盖，不把旧文件数量、哈希一致或backup_completed当作还原通过。

还原通过前不进入下方换包第1步，不生成或写入新的生产配置。备份和CI均通过后再准备精确配置、Prepare/派生登记XML、双SDDL/父SD，连同新head、manifest、逐项运行差异和0–6步骤交最终审批。48项运行字节与旧c539候选逐字核对；若新head构建仅使manifest中的三个commit字段改变，也按新manifest重建候选并披露，不能宣称旧hash不变。

真人关机报告必须分列：①session-message入口是否到达（QUERY/END、PID/会话、window station/desktop）；②六终态是否齐全。关机后先读入口；一份都没有时，先依session-window及任务运行方式调查窗口收消息路径，不继续增加关闭流程复杂度。合成定向消息/测试通过不代表真实系统广播已到达或真人验收通过。

后续运行字节改动另开独立PR，不与预检、文档、ACL工作混在一起。本轮仅按用户指定在PR20完成merge与审批材料，仍不合入v3-lab、不换包。

## 1. 诊断和修复边界

旧基线 b71799706719b0e603124d108c2795caa0a98933 的实际 END handler 正常返回，session-close 已存在、内存 clean=true，但 session-exit 尚未发布；不泵 UI 并立即结束合成宿主后，exit 永久缺失。旧设计把必需回执留到 OnFormClosed，已证实存在竞态。它不能单独解释现场六份终态全部缺失；不把现场原因归为用户强制关机。

本机只读诊断另有本地报告，包含三项注册表值、快速启动可用性、42.889 秒系统时间窗、每组 raw 文件数量/大小/摘要核对范围、保留策略、空间和逐条已证实/待验证原因。该报告不含聊天正文或凭据，不进入公开源码。原系统设置和 raw 保留策略未改。raw 与每日备份的 30 天保留并非同一策略，raw 当前不会自动过期或裁剪。

修复：
- QUERY/END 一进入即同步创建唯一入口回执并 Flush(true)，记录本次 PID、Session、线程、window station 和 desktop。
- QUERY 及时答复，启动原有后台收尾；END 同步等候并发布必需 exit，之后的 UI Close 仅负责幂等清理。
- 同一 30 秒 wall stopwatch 覆盖入口、MCP 停止、备份收尾、Core 认证关闭与回执耐久发布，不扣除 QUERY→END 等待。
- final flush/rename 完成后再次核计时：超预算另发失败证据、宿主退出失败。exit 内 elapsed 明确采样在其自身 flush 前；验收还必须看真实宿主退出和外部总耗时。
- 终态封口与 session-close 最终 rename 串行；flush 不持该锁。晚到 worker 不能补发过时 clean 回执，不能把超时宿主改回成功。
- strictClosedPath、NativeLease、ACL/owner、plainPath、状态/配置单硬链接和 MCP 先停顺序均保留。

## 2. 验证结果

| 专项 | 结果及证据边界 |
|---|---|
| 真实生产 WndProc 的11场景 | 12/12，最终整组104.30秒；无 UI pump/OnFormClosed，覆盖进入回执、handler返回即终止、取消重试、发布失败、真实30秒、最终flush越界及晚到worker封口。 |
| 双端部署配置绑定 | 21/21，47.9秒；只读完整库存及配置/XML约束，提案仍未批准。 |
| 手动custody备份清单 | 7/7，63.88秒；大floor/未发布head保全及所有负例，不解密或认证MAC。 |
| 受绑定 WM_CLOSE | 旧47/新48共2/2，最终整组合计118.968秒；真实Core/login/managed MCP及四前置拒绝。外部关闭分别1301/1232ms，严格小于30000ms；整轮测试耗时不是单次关闭耗时。 |
| prepare→真实 Native 换包/断点 | 1/1，最终整组501.938秒；旧47→新48→旧47、双pending和正反终态断点、写后/省略proof拒退。包含最后rowid/Infinity增强。11次Native操作15550–16673ms，非现场停机承诺。 |
| 完整持久状态见证/反向保护 | 20/20，最终整组覆盖隐式rowid及Infinity/NULL区分。 |
| 同版本登记串联 | 本机3/3，89.200秒；真实旧47关闭→Native forward→固定Prepare→validator，forward15666ms。19个字段负例及marker/附件/active旧任务拒绝；真实COM CREATE由CI执行，本机没有创建任务。 |
| 主窗Windows整组 | 首次357项：352通过、3个提交构建夹具因旧HEAD缺新文件失败、2项权限专项跳过；总3363.331秒。3e68b0e4提交后3项复验全过26.443秒；另加登记3项，另库存gate新增1项通过，合计覆盖361项，末次状态359通过/2权限项留CI。 |
| identity夹具库存回归 | 5/5，1.881秒；实际执行纯PS库存gate，精确48通过，缺项/同计数错路径/重复/错报告计数拒绝。不在本机运行hosted提升链。 |
| 最终源码CI | 以PR #20对应最终head的Actions结果为准；签收结果写入本机候选审批材料，不能继承早先dba09d9c全绿。 |

第一次整组读取提交构建的3个夹具仍指向旧HEAD dba09d9c，新增 package_switch.mjs 未提交，因此正常拒绝；不是放宽生产检查的理由。原始失败日志保留；3e68b0e44b90bb4b02865b4ca574b7531715462e上三项复验3/3通过（26442.657ms），未改夹具或生产检查。新增登记测试在首次枚举之后加入，单独3/3运行，不冒称首次整组已经包含。

本机直接枚举全体 schema6 与 lifecycle 测试串行执行；仅限 GitHub 临时VM的包装入口在本机host guard正常拒绝、exit2且尚未启动测试，未伪造host变量、改注册表或模块目录。两个需要管理员/真实COM的opt-in专项在本机未获额外权限时按既有约束跳过，由hosted Windows强制实际执行。

首轮4beef838 CI 的维护双run均96/96、零失败/跳过，新增登记真实COM链已实际执行；identity独立job在Apply之前被夹具旧 files-ne47 拒绝。仅修 identity_assemble / identity_pipeline 及其回归：生产 verifyRelease 先验证真实48库存，再导出权威 INVENTORY；PS核精确路径、重复与计数。无生产校验或运行48字节变化；最终CI仍以最新head为准。

合成消息不等于真人关机通过；上线、开机后手机/claude.ai 已通过的状态也不撤销。

## 3. 新运行包与配置链

新固定库存为 48 项，在原47项上加入 package_switch.mjs；历史47项库存单独固定，绝不改旧包字节。候选只从正式 C 副本的已提交源码构建，源提交、manifest、完整库存摘要和逐项运行字节差异由本机 SCHEMA6_PACKAGE_APPROVAL_20261008.md 随候选交付，避免自引用提交/manifest哈希。

需要重建 Core manifest 锚 → 备份完整 release 库存 → MCP 可执行路径（仅 Node 路径需要时）→ login 路径/各文件 hash → 固定 Prepare XML。原 MCP 程序与全源码库存、参数、环境策略、DB、47860/47862、grace、单上传器 legacy_b3、关闭的 debug 邮件和密钥绑定保持。

prepare-package-switch.mjs 只读检查双端 Core/login/MCP/backup/task 文件，保留两端附件锚并验证新包完整 release 备份清单；只出 approved:false、deploymentReady:false 提案。四个文件的 hash、backupReleaseInventoryBound 或最近备份 not_due 都不能替代完整绑定和九类内容覆盖。受保护配置可能含 inline secret，校验不输出它，也不另读密钥/凭据文件或数据库。

精确 XML、注册输入 SDDL、继承后预期 SDDL、父 SD、owner SID、Prepare 回执、旧任务停用与新任务 CREATE/真实 COM 回读仍是独立人审/现场门。本轮没有生成真实生产新配置或注册任务；旧 task-approval…settings 仍是生产配置、不可清理。

同版本登记使用新增 register-package-switch-login.ps1 和 package-switch-registration.mjs；旧 register-approved-login.ps1 依赖首次 v4 冻结链，不得借用或伪造旧冻结回执。新入口钉住完整维护闭包与48项候选，在真实 runtime/custody 双锁及原库独占句柄下，仅绑定先前 Native 离线回执（nativeOfflineReceiptsBound:true、hmacRechecked:false），不冒称重新认证 MAC。原关闭 marker 精确字节、event 的 previousHead/DB/sourceMarker、目标 floor/head/marker 和固定 Prepare 均互绑。登记配置还须绑定换锚后实际生成的回执摘要，不能把当前提案说成已批准的生产登记输入。

CREATE 即 disabled：固定 Prepare 原 XML 与仅将 Settings.Enabled 改成 false 的 COM 派生登记 XML 分别钉 hash，humanApproval 明确 registrationDerivation 和独立登记 XML；全字段及双 SDDL/父 SD/有效权限回读后确认 instances=0。旧任务保留原 LogonTrigger、仅允许既已 disabled 且无实例。失败只禁用本次 CREATE 返回的新对象，不覆盖、删除或改变旧任务。启用/启动新任务是后续已批准现场步骤，不由 RegisterOnly 偷带。

运行库存变更预期为 7 个已有文件及 1 个新增文件，最终以候选和旧 manifest 的逐项比较为准：session_window 修复回执/终态；common、runtime_child、start_schema6、recovery_adapter 接入受认证的离线换包和断点保护；package 固定48项；README 更新说明；新增 package_switch 的双包与完整业务见证。Core 业务程序、MCP 程序、Node 字节不因本轮更换。

专项证据分层：配置串联使用真实旧/新 release 与固定 legacy MCP 源码，检查 Core/login/MCP/备份 release 库存和严格 XML 模板；非 release 凭据及 portable envelope 为合成占位锚，没有真实注册任务或还原备份。WM_CLOSE 专项实际运行旧/新 login、Core、managed MCP，未启动备份 worker，空 backup Job 仅按既有语义验证。整组中的备份/恢复与 COM 测试是各自独立合成证据，不把这些拼成生产部署已经就绪。

## 4. 待批准的换包顺序

| 步骤 | 动作与完成判据 | 失败处置 |
|---|---|---|
| 0 审批 | 批准本轮新包及维护入口，随后核准精确双端配置/计划、XML/双 SDDL/父 SD。确认 T9 为原 NTFS 介质、完整加密备份可实际还原。 | 任一锚或介质不符即停，不格式化、不冻现役。 |
| 1 准备 | 旧包、旧配置和旧任务导出原样留存；新配置写独立受保护正式目录。特别是新 daily-backup-config.json 必须保护性 DACL、本人 owner、仅本人和 SYSTEM 的 FullControl、单硬链接；不能继承目录里的 Administrators ACE。固定 PrepareOnly 逐字比对，不注册；并按既有全路径 ACL 审计核对全部新旧运行依赖，单独调用已验证的 Assert-BackupPrivateAcl 只读检查备份配置。只读全套通过后才停用旧登录任务，避免维护时再次登录启动。 | 未停会话时可恢复旧任务 enabled 状态，现役继续运行。 |
| 2 安全关闭 | 受绑定会话关闭入口持原进程 handle，核 PID/创建时间/owner/映像路径与 hash/实时 HWND；只对该窗发 WM_CLOSE。MCP 先停，随后认证关 Core；验完整六终态、原进程退出、Jobs 空、原库独占且无 sidecar。不得用 EndTask/强杀冒充 clean。 | 任何判据缺失即停在改锚之前。保留失败证据；通过原包正常恢复机制恢复服务，不能删除 raw/pending 或伪造 clean。 |
| 3 离线换锚 | 使用新包 start_schema6.ps1 的 package-switch 操作、批准计划 hash 和独立空 control。NativeLease 下核完整双包/双端附件/旧 marker+current-head，追加认证转换、floor、head，不迁移、不替换 SQLite。 | 未提交 head 的中断也保留 sentinel/pending，仅相同计划在租约下续行；不手删标记、不覆盖旧 head。 |
| 4 终态确认 | child/guardian 真退出、Jobs 空后 supervisor 发布目标 clean marker。先删 custody pending，state sentinel 最后删；两端正常启动均不能越过中途 sentinel。 | head 已推进或 marker 已提交时只按同一计划续行；不得恢复旧 current-head。 |
| 5 新会话 | 经新增同版本 RegisterOnly 创建新名字、disabled 的登录任务，严格回读分别批准的 Prepare/派生登记定义与双 SDDL；旧任务继续 disabled 且原触发器不变。回读及零实例通过后，才按另行批准的现场步骤启用/启动新任务。新 Core ready 后才启原程序 MCP；健康及只读检查成功后再开放真实业务写入。 | 尚无业务变更且完整见证仍相同：执行认证反向切换，追加更高 generation，然后恢复旧配置/任务并启旧包。仅复制回旧配置不是回退。 |
| 6 验收 | 手机上现有 App、claude.ai 写入；关机前先实际 MCP 请求，使其打开库。本人正常关机→开机→登录，核入口/六终态、自动启动、手机同步、claude.ai。 | 有真实业务写入后拒绝旧包回退，保留新包和证据向前修；clean-close 不通过时仍单列，不宣称切换验收完成。 |

关闭入口的外部计时从发送 WM_CLOSE 前开始，直到原宿主真正 exit 0，严格小于 30 秒；不含前置校验和退出后的证据/DB 验证。后者失败仍拒绝签收。整轮测试耗时不能当作现场停机预测；换包操作的单项合成耗时另列，30 秒关机预算不变。需要本人时统一叫人：介质确认、恢复口令安全窗口、精确 XML/SDDL 批准、管理员注册操作、真人关机/开机与两端测试。

## 5. 反向与断点保护

反向也是新认证事件和更高 custody generation，不能回写旧 floor/head。认证 head 全链重建当前包栈；返回历史祖先必须提交对应 forward 事件，省略 rollbackOf 仍拒绝。SQLite schema、全部表（含未知表）、可访问的隐式 rowid、元数据与持久 op 历史采用完整业务见证；无法完整枚举的虚表或被全部别名遮蔽的隐式 rowid 拒绝换包，不省略。合法新写入/删除/retention/schema 变化均拒绝旧包回退，改为向前修。该见证是完整持久状态比对，不声称能检测绕过应用且精确写入又还原全部历史的任意 SQL 攻击。

中断测试需包括 pending 后、head 后、目标 marker 后、custody pending 已删但 sentinel 仍在，正反两向分别验证旧/新真实包在 store 构造前拒启，并由同一计划在真实租约下续行。未授权操作、其他操作计划、附件漂移、历史改写、marker/head 不匹配均拒绝。

## 6. 本轮交付和下一次本人节点

本轮完成源码、专项/整组/CI、候选后推送 PR #20 并暂停。新候选改变运行字节与 manifest，旧包/旧 XML 的批准不能继承；合并、换包和真实关机需按新精确材料批准后再约。当前不改手机、MCP 程序、上传器或退役 47862。

10/09 20:00 已有一次完整加密备份安排：现役全部九类和动态 custody 全链→本机/T9→真实隔离还原及只读 Core 核对，不以 hash 比对代替。需要口令或介质时叫本人；安排不是已完成。若当时换包处于关键提交段，先等事务闭合再备份并明确迟延。换电脑建立新现役仍是独立已知缺口。

## 7. 手动完整备份与自动调度的边界

本轮新增 prepare-custody-backup-inventory.mjs，仅供已授权的手动备份准备：保留原九类清单及独立 inspection context，显式钉住当前 head，纳入全部 head/floor/recovery/package-switch 历史。有效但未发布的归档 head 也保全并计数，不把它提升为权威 head。pending、未知文件、缺引用、坏摘要、宽 ACL、路径/单硬链接异常均拒绝；原 custody.lock 不作持久数据备份。

准备时双读目录和每个文件，捕获前、捕获全部九类之后各执行一次 check，钉住同一准备文件 SHA256；任一次 vector 变化，本次产物只能留证，不签收完整备份。生成器不解密、不认证 MAC，也不承诺跨组件原子性、外部 raw/计划引用正文完整或可激活现役；这些仍由实际捕获/还原检查和范围清单核实。该工具只自动扩展 custody 目录；raw 保全、grant、72 条 replay 审批、MCP .state、i_memory、隧道/Serve、手机库副本等仍须按最新九类清单逐项枚举，不沿用过时文件数量。

当前自动调度仍读取静态 specTemplate，新增 custody 历史不会自动扩展进去；此为既有独立缺口，本轮未改运行调度或批准配置。10/09 晚、换包前和换包后手动备份均须使用最新九类清单及上述动态历史工具，并做真实隔离还原。不能把自动 backup_completed、清单生成成功或 hash 相等代替完整还原核对。

手动入口（均为新隔离输出；变量由审批材料填写）：

    node tools/i_core/maintenance/prepare-custody-backup-inventory.mjs prepare --spec <nine-role-spec.json> --custody-directory <protected-custody> --expected-head-sha256 <current-head-hash> --output <fresh-prepared.json>
    node tools/i_core/maintenance/prepare-custody-backup-inventory.mjs check --prepared <fresh-prepared.json> --prepared-sha256 <prepared-file-hash>

第二条须在实际捕获前后分别调用。备份/还原本身继续使用既有固定工具，密码只在安全窗口输入，不进命令行、聊天或日志。

同版本换包入口的参数：

    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <approved-maintenance>/close-schema6-session.ps1 -ConfigurationPath <approved-close.json> -ConfigurationSha256 <close-config-hash>
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <new-release>/tools/i_core/release_schema6/lifecycle/start_schema6.ps1 -ManifestSha256 <new-manifest-hash> -Start -StateDirectory <state> -ControlDirectory <fresh-control> -ConfigurationFile <new-core.json> -OfflineOperation package-switch -PackageSwitchPlan <approved-plan.json> -PackageSwitchSha256 <plan-file-hash>
    powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File <approved-maintenance>/register-package-switch-login.ps1 -ConfigurationPath <approved-registration.json> -ExpectedConfigurationSha256 <registration-file-hash> -RegisterOnly

关闭入口只允许精确旧47/新48库存；旧47本身没有 exit.manifest_sha256，仅这一缺失可由整包、原进程/HWND 和其他完整 manifest 回执绑定替代，显式报告 legacyExitManifestAbsent。字段存在但不符仍拒绝，新48必须包含正确字段。该入口既不发送系统关机消息，也不强杀 Core，不能代替下一次真人关机验收。
