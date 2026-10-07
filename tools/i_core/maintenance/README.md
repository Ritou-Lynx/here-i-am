# schema6 现场维护源码

本目录在固定 runtime 的47项库存之外。实际路径、owner SID、任务名、端口、原任务 XML/SDDL、候选 commit/manifest、批准 XML、配置和回执摘要均由本轮私有参数提供。仓库不保存现场配置、ACL快照、库、凭据、口令或正文。只提交源码及合成演练不构成进场授权。

## 入口

| 文件 | 作用 |
|---|---|
| enter-maintenance-window.ps1 / freeze-legacy-runtime.ps1 | 新窗口固定入口；保存/冻结旧任务、触发及重试 → 停MCP → PR16在线副本预检 → 停旧Core → 全件证明及至少65秒观察。内置退回仅覆盖冻结阶段。 |
| maintenance_window.ps1 | 每窗口CreateNew目录/entry.lock/回执；active-window.guard独占句柄串行化动作，不删除或截断旧证据。 |
| acl-cutover-maintenance.ps1 | import-safe Audit/Apply/Rollback，仅owner/DACL/继承，精确库存、全项恢复及readback。 |
| owner-apply-runtime-permissions.ps1 | 同owner提升会话的显式wrapper，pin后加载ACL实现并复核回执；绿色UI不代替验收。 |
| owner_elevation_probe.ps1 | 仅新合成根的foreign-owner往返，不操作现场目标。 |
| prepare-production-login.mjs / .ps1 / prepare_live_guard.ps1 | 绑定本窗口冻结和全项ACL回执；固定PrepareOnly生成XML，逐字等于本人批准版本。 |
| register-approved-login.ps1 / register_task_primitives.ps1 | RegisterOnly，TASK_CREATE=2，真实COM回读，没有任务启动入口。 |
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
