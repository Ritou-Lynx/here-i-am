# schema6 现场维护源码

本目录在固定 runtime 的47项库存之外。实际路径、owner SID、任务名、端口、原任务 XML/SDDL、候选 commit/manifest、批准 XML、配置和回执摘要均由本轮私有参数提供。仓库不保存现场配置、ACL快照、库、凭据、口令或正文。只提交源码及合成演练不构成进场授权。

## 入口

| 文件 | 作用 |
|---|---|
| enter-maintenance-window.ps1 / freeze-legacy-runtime.ps1 | 新窗口固定入口；保存/冻结旧任务、触发及重试 → 停MCP → PR16在线副本预检 → 停旧Core → 全件证明及至少65秒观察。内置退回仅覆盖冻结阶段。 |
| maintenance_window.ps1 | 每窗口CreateNew目录/entry.lock/回执；active-window.guard独占句柄串行化动作，不删除或截断旧证据。 |
| protect-approved-settings.ps1 | 独立获批单目录前置；方案SHA锚、3配置单链接/hash、原DACL耐久保存后只保护继承保留ACE，失败精确恢复；不处理144项、不碰任务/服务/库。 |
| acl-cutover-maintenance.ps1 | import-safe Audit/Apply/Rollback，仅owner/DACL/继承，精确库存、全项恢复及readback。 |
| owner-apply-runtime-permissions.ps1 | 同owner提升会话的显式wrapper，pin后加载ACL实现并复核回执；绿色UI不代替验收。 |
| owner_elevation_probe.ps1 | 仅新合成根的foreign-owner往返，不操作现场目标。 |
| prepare-production-login.mjs / .ps1 / prepare_live_guard.ps1 | 绑定本窗口冻结和全项ACL回执；固定PrepareOnly生成XML，逐字等于本人批准版本。 |
| register-approved-login.ps1 / register_task_primitives.ps1 / task_security_policy.ps1 | RegisterOnly，TASK_CREATE=2，真实COM回读，没有任务启动入口。 |
| precutover_validate_copy.mjs / online_preflight_input_guard.mjs | PR16只读在线复制和唯一的在线SHM例外。 |

使用Windows PowerShell 5.1和固定Node24.14.1。先从批准提交固定维护源码的完整依赖闭包，再在受保护私有根中pin源码/配置外锚；不能只复制入口或执行可变checkout。各入口的准确参数和字段见三个工作包交接。

本次计划入口名为enter-maintenance-window.ps1；预留新WindowId为cutover-retry-20261007-r02。本轮没有创建现场窗口。若该ID以后被使用，即使失败也改选下一个ID，不能删锁重跑。旧目录/entry.lock/回执/guard字节保留，已关闭句柄的旧guard不会挡新ID；同ID拒绝。后续阶段只重新取得guard，不重复进入entry。

~~~powershell
& $windowsPowerShell51 -NoProfile -ExecutionPolicy Bypass -File $entryPath -ConfigPath $freezeConfigPath -ExpectedConfigSha256 $freezeConfigSha256 -WindowId $newWindowId -Execute
~~~

ACL/Prepare/Register逐项签收；下一阶段配置在前一阶段真实回执生成后独立绑定，不编造未来SHA，不复用旧成功回执。freeze不是全流程执行器。

## 保持的门槛

在线判据：DB/WAL字节、大小、身份；journal存在性；SHM存在性/大小。诊断hash仍保存。仅在线比较忽略SHM/journal内容；冻结后的首次闭合和65秒观察仍严格核四件全字节，离线raw加密、strictClosedPath、NativeLease、plainPath和ACL不放宽。对新建空维护副本目录初始化私有ACL，不等于现役144项Apply。

ACL后出现pending或新增库存，保持writers与任务冻结，保留证据，不删pending/锁、不改144、不盲退。commitStarted、原库替换、生产head、新写入任一出现或无法排除，转向前修。只有确认尚未替换且精确库存成立，才按受审方案全项恢复owner/DACL并readback，再恢复旧运行链。不存在跨阶段“一键退回”。

RegisterOnly先核任务不存在，再CREATE；竞态不会覆盖已有任务。真实COM逐项核Actions/Principals/Triggers/Settings/SDDL及零实例和旧任务冻结态。发现漂移拒绝；仅能禁用本次已确认创建的对象，不能按名称改不明对象。合成任务禁用、零触发、零实例、不执行动作，只删除nonce绑定的本次对象。

## 合成验证

Windows CI的schema6-windows job串行纳入maintenance_acl/window/register测试，显式必跑真实COM生命周期和foreign-owner特权探针，COM回执上传artifact。本机普通token未执行foreign-owner探针不能当通过；由临时hosted Windows VM实际执行。不改本机策略或现役ACL。Linux仅承担当平台可用的纯验证。

主窗验收及现场清单位于docs/development/handoffs；合并PR16与再次进场均需另行授权。

## 2026-10-07 任务安全修订

当前配置/审批采用v2、准备回执v3，registrationSddl与expectedRegisteredSddl分别锁定，parentSddlSha256及windows-file-oi-v1独立推导并前后重核。外SID只允许00120089纯读子集，所有其他权限包括执行均拒绝；只读主体逐项披露绑定本人批准。旧approvedSddl不再接受。固定Prepare模板显式Unified=true，须新包和本人最终XML/SDDL审批后再进场。详见docs/development/handoffs/SCHEMA6_TASK_SECURITY_REVISION_20261007.md。

## 2026-10-07 R02 后：只读演练优先

维护配置升级为 `schema6-maintenance-freeze-config-v3`，显式绑定 `formalWindowId`、两新模块及完整依赖哈希、独立 preflight 输入。入口只能选 `-Execute` 或 `-PreflightOnly` 其中之一。只读模式必须使用与正式ID不同的新ID，在 `rehearsals/windows/<ID>` 建立追加证据；共享主根的独占guard防止同时正式进场，但不创建/消费正式窗口。失败也保留演练ID和证据，不删锁复用。

全部现役改动前共用：候选47库存、USB NTFS/卷UUID/设备身份与两端密文哈希、九类备份/既有真实还原回执、旧任务XML/SDDL/完整进程树（含conhost）/端口、精确ACL144/16外owner、批准XML/双SDDL/父SD与本机COM内存兼容、固定Prepare纯模板逐字输出。只读模式还执行PR16在线副本预检，再核任务/完整进程树/DB文件身份/ACL/父SD及pins。它不停止/冻结任务或现役进程，不Apply、不注册、不写生产配置，不生成冻结/Apply/正式Prepare成功回执。

正式Prepare要求加固后的实际ACL，不能在加固前假装执行成功。演练使用固定候选manifest绑定并独立审阅哈希钉住的纯XML构造段，以及全部声明配置/待Apply库存检查；记录 `productionPrepareInvoked=false`、`productionPrepareStillRequiresAclApply=true`、`prepareTemplateBytesEqual=true`。生产Prepare及其冻结/ACL/NativeLease等门槛不变，现场仍必须真实执行。

仅进程映像使用 `process_image_binding.ps1`：PID、OS创建时间、实际完整路径、SHA256持柄绑定；系统路径由Windows API取得且必须TrustedInstaller owner，可有servicing硬链接。数据/配置/密钥/状态/回执/发行包（含候选Node）仍单硬链接。没有通用豁免标记。

演练CLI与正式入口相同参数，末尾使用 `-PreflightOnly`。演练全过后仍须本人另行授权正式进场。

## 单目录 settings 前置的最新授权

单目录入口先随 PR20 合成/CI 通过，执行时必须固定完整维护快照，参数 `-ProposalPath … -ExpectedProposalSha256 … -ReceiptDirectory … -Execute`；全新受保护回执目录不能在目标内，旧输出不复用。真实方案和 SDDL/SID 只在私有文件，源码无现场默认路径。此入口仅目录 DACL，不能代替正式冻结后的144项 owner/ACL Apply。

执行成功后新ID完整 PreflightOnly；用户当前已明确有条件预授权：全套零失败且全部原批准外锚不变才直接用 r02。任何现场失败或偏差停审；原先“演练后另请授权”是此前阶段历史。固定47运行文件/Core/MCP/会话启动器不随新增维护入口变化。详见 `docs/development/handoffs/SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md`。
