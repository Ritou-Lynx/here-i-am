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

## 同 Core 的 ChatGPT MCP 配置维护候选

`generate-mcp-config-switch.mjs` 与 `mcp-config-switch-bindings.mjs` 只允许同一48项Core/原配置路径和hash上的六文件MCP候选，追加唯一flag并保全旧链十项备份附件；不使用或放宽旧package-switch的MCP不变门控。生成器只写全新私有输出，目标backup文件显式owner+SYSTEM保护；实际XML仍由原固定PrepareOnly生成。

`register-mcp-config-switch-login.ps1 -RegisterOnly` 另需精确human approval、真实在线关闭终态、双锁/闭态树/原任务冻结/XML/双SDDL/父SD证据，仅CREATE新disabled任务。生成、合成注册、生产登记、启用及真人验收分别签收；缺现场证据不执行。详见[生成器交接](../../../docs/development/handoffs/CHATGPT_MCP_CONFIG_SWITCH_GENERATOR_20261009.md)、[登记交接](../../../docs/development/handoffs/CHATGPT_MCP_CONFIG_SWITCH_REGISTRATION_20261009.md)与[部署准备交接](../../../docs/development/handoffs/CHATGPT_MCP_DEPLOYMENT_PREPARATION_20261009.md)。

## 普通用户正常停服与登录任务切换（合同 A）

这两个维护入口不读取审批文件，不核生产 pin，不改运行时包。它们只在显式调用时操作指定的既有任务；导入脚本不会执行任务。请在普通用户会话中运行。真实部署由用户另行执行，合成 CI 通过不代表生产已切换。

```powershell
# 停服；无活会话时也检查 sidecar 与恢复锁，再返回 already_stopped。
& tools/i_core/maintenance/stop-schema6-session.ps1 -TaskName 'Existing-Login'
# 只读检查两任务的 login 哈希、同一数据根和恢复锁；不停止、不启停任务。
& tools/i_core/maintenance/switch-login-task.ps1 -FromTask 'Existing-Login' -ToTask 'Candidate-Login' -DryRun
# 先正常关闭，才切换任务。默认等待就绪 180 秒。
& tools/i_core/maintenance/switch-login-task.ps1 -FromTask 'Existing-Login' -ToTask 'Candidate-Login' -ReadyTimeoutSeconds 180
```

可选 `-PublicHealthUrl` 要求指定 HTTP(S) 地址返回 200；不跟随跳转。Core 与 MCP 的本机端口、全新会话的 ready/MCP 回执和任务状态也必须就绪。任务参数使用 `-LoginConfigurationPath` / `-LoginConfigurationSha256`；同时接受短名 `-ConfigurationPath` / `-ConfigurationSha256`，重复或缺失拒绝。任务读、启用、停用、启动与状态读取统一通过 `Invoke-Schema6TaskOperation`；测试只在自身进程替换其适配层。

关闭前以持有的进程句柄验证当前用户、系统 PowerShell 映像、进程创建时间与隐藏顶层窗口身份，随后只发 `WM_CLOSE`，最多等 35 秒。必须确认宿主退出 0、Core/会话/监督器正常关闭、每代 MCP 启停回执成对，以及状态目录没有 `i-core.sqlite-wal/-shm/-journal` 和 `s6-recovery-pending.json`。不强杀宿主，不删恢复锁或 sidecar，也不读取数据库正文。

closed_files 只扫描 STATE 顶层且不改文件：其他 sidecar 按序数排序，仅以文件名记录 `stop.closed_files_other_sidecars`；relay lock 独占打开失败（IOException）报告 `relay_lock_held`，未被占用时通过。
宿主窗口已消失时，最多等待进程退出 10 秒；新会话已有退出回执且无活会话时立即报告 `new_session_ended_before_ready`。ready 的任何失败均附 `;child_error_code=<值>`，取新会话最新控制代的 child 错误码；缺失为 `none`，非法或不可读为 `unreadable`。

每一步输出一行 `step` / `ok` / `detail` JSON，失败保留异常文本。退出码：0 成功（含 already_stopped / DryRun）；1 新任务失败后旧任务已恢复就绪；2 预检拒绝、关闭不干净、存在恢复锁或回滚失败，需人工检查。预检发现目标哈希错误时按第 1 步零变更拒绝，旧会话原样保留。切换后的漂移或启动失败才进入回滚；按预检缓存的控制根关闭新会话，不跟随漂移后的任务参数。新会话关闭不干净或出现恢复锁时，绝不启动旧任务。

Windows CI 的 maintenance 和全量套件均运行 `tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch.test.mjs`：真实合成会话正常停服、A→B、新任务预检错哈希零变更，以及 B 就绪后参数哈希漂移→干净停 B→恢复 A。另在 CI 的合成任务门控下运行 GUID 无触发器无害任务，验证真实 COM 适配层并绑定删除。本机不设置任何合成任务或 owner-probe 环境变量。

“未进入恢复”由真实回执核实：关闭前的 lifecycle 为 `clean_closed` 且无 sidecar，符合 `tools/i_core/release_schema6/automatic_recovery.mjs` 中 `needsStartupRecovery` 返回 false 的条件；`tools/i_core/release_schema6/lifecycle/runtime_child.mjs` 的 `recoveryNeeded` 分支据此不调用 `recoverAtStartup`。测试另核对 custody 的 `*.recovery.json` 事件集不增加（发布点在 `tools/i_core/release_schema6/recovery_adapter.mjs`）、恢复锁缺席及各代干净退出，防止把悄悄恢复当作切换成功。

## 只替换 MCP 六文件源码（合同 C1）

`update-mcp-source.mjs` 以指定的既有登录任务为起点，读取并核对 login、MCP、backup 配置哈希。候选使用 `chatgpt_candidate.mjs` 的目录结构（`manifest.json` 与 `runtime/`），六个文件名必须与现役 `source_files` 完全一致，`entry` 必须等于现役 `entrypoint`，每份源码核对 `result_sha256`。不限定候选提交号、变更文件数，也不添加或移除 ChatGPT 开关；如果旧库存仍带 `tools/` 前缀而候选没有，工具明确拒绝，不能偷偷改 entrypoint。

```powershell
# 以下是操作示例，真实执行需由用户在场另行授权。
node tools/i_core/maintenance/update-mcp-source.mjs --from-task Existing-Login --candidate build/mcp-candidate --out private/new-mcp-settings --new-task Candidate-Login --dry-run
node tools/i_core/maintenance/update-mcp-source.mjs --from-task Existing-Login --candidate build/mcp-candidate --out private/new-mcp-settings --new-task Candidate-Login
# 登记完成后仍是停用状态；切换沿用合同 A。
& tools/i_core/maintenance/switch-login-task.ps1 -FromTask Existing-Login -ToTask Candidate-Login -DryRun
& tools/i_core/maintenance/switch-login-task.ps1 -FromTask Existing-Login -ToTask Candidate-Login
```

更新工具只接受上面五个选项。候选和输出均拒绝与旧工作目录、状态、控制根相互包含。Windows 预检只读核对候选 runtime 根的受保护 DACL、所有者及全部子项；不替候选修复权限。输出必须全新，失败后保留已有产物，不复用或自动重试。`--dry-run` 完成配置、候选、备份映射、任务定义和 CREATE-only 前置校验，零文件写入、零任务登记。此步骤不做实际切换的就绪验收。

新 MCP 配置仅替换 `working_directory` / `source_files`；新 login 仅替换 MCP 和 backup 两对路径/哈希，其余 JSON 字节（含 BOM）保留。新增值中的非 ASCII 字符使用 JSON Unicode 转义，兼容冻结宿主按系统代码页读取配置。备份通过只导入的 `backupMapping` / `buildMcpSwitchBackup` 替换相关配置、任务与六份源码附件，循环模板摘要沿用既有规则，其他附件/策略不变。上次更新保留的附件原样保留，新保留项使用 `preserved/mcp-source-update/<摘要>/` 独立命名，避免与既有历史冲突。每份配置的字段差异写入私有 `field-diff.json`。

Windows 桥接脚本导入 `Get-Schema6LoginBinding`；使用 `owned_artifacts.ps1` 的原子新目录/私有文件原语写入五份产物，普通用户、SYSTEM、Administrators 的既有 ACL 契约不另造一套。旧任务定义克隆到新任务，仅替换 login 参数和停用设置，`TASK_CREATE=2` 拒绝覆盖；不启动新任务，不启停旧任务，新任务的权限回读复用既有 Convert-TaskSecurity，容纳 Scheduler 合并或补加冗余 allow ACE，额外主体、额外权限以及 owner/group/protected 变化仍拒绝；旧任务 XML 与原始 SDDL 前后严格一致。每步单行 JSON 输出 `step` / `ok` / `detail`，原异常保留，失败退出 2。登记失败不自动删除未知任务，也不自动重试。

新增纯 Node 测试使用临时合成文件和内存任务适配器，本机只运行这份文件：

```text
node --test tools/i_core/test_fixtures/release_schema6/maintenance_mcp_source.test.mjs
```

Windows maintenance 与 lifecycle/backup 套件额外运行 `maintenance_mcp_source_windows.test.mjs`，证明合成任务登记为停用、参数正确、旧任务未变、同名拒绝及清理；真实合成会话从 A 经生成/登记切到 B，核对就绪、无恢复事件和干净关闭。这些检查不代表生产部署或备份已成功。

## R1 online pairing window and offline switch

Use a Windows PowerShell 5.1 child with inherited `NODE_*` and `I_CORE_*` variables removed. `open-pairing-window.ps1 -TaskName <name>` reads the existing bound live session and never registers, starts or stops a task. It prints one 64-character code on stdout only. Supply that code to the existing `server.mjs pair-core --frontend chatgpt_web` through stdin; do not place it in arguments, environment, transcripts or logs.

The protected control channel authenticates the code hash and a fixed ten-minute deadline with the session stop key. An exclusive, fully written reservation bridges atomic file publication. A valid request is deleted before opening the window; a consumed or expired window closes, and malformed, replayed or abandoned requests only produce redacted pairing receipts. A failed receipt never shuts down Core. No configuration or release inventory format changes.

After an offline package switch, use `switch-login-task.ps1 -NoRollback`: failures stop in place with exit 2 and `reverse_package_switch_required`. Recovery requires an explicitly reviewed reverse package switch. Omitting the switch preserves the existing rollback path and reports.

Prepare/login errors retain their existing prefix and expose only lowercase ASCII codes of 1–64 characters; other exceptions retain the generic rejection. The start validator reports rejected environment variable names, never values, and preserves its existing exit codes.

R1 verification uses pure local protocol tests and hosted Linux/Windows synthetic integration tests. Passing CI is source-candidate evidence, not production deployment or pairing authorization.

## R2：D1 关闭输入与换包登记证据

`close-schema6-session.ps1` 拒绝时在 stderr 输出 `approved_session_close_rejected:<reason>`，退出码仍为 2。两个 `register-*-switch-login.ps1` 的失败 stdout JSON 保留原 `code`，增加 `reason`；Node 登记校验器的失败 JSON 同样增加 `reason`。这些内部码只允许 1–64 位小写 ASCII 字母、数字和下划线，其他异常统一为 `unclassified`，不输出异常原文。校验器非零退出时，登记入口的 `reason` 为 `registration_proof_rejected`，另以 `validatorReason` 转交校验器的内部码（读不到为 `none`，非法为 `unclassified`）。私有登记回执同步记录这些失败字段；成功输出和回执不增加这些字段。

`generate-package-switch-configurations.mjs` 在 Windows 上为新生成的 backup 配置单独设置受保护的文件 ACL：当前用户为所有者，禁止继承，仅当前用户与 SYSTEM 的显式 Allow FullControl。写入后立即按登记入口的 backup ACL 规则复核，失败报 `configuration_generation_backup_acl_rejected` 并保留候选输出。ACL 操作不改变配置内容和哈希；非 Windows 跳过此步骤。

`generate-package-switch-evidence.mjs` 只准备证据，不关闭会话、不登记或启动任务，也不读取密钥。以下命令用于 D1a/D1b；真实关闭、离线换包、登记和切换仍按用户在场的逐步授权执行。所有路径必须是绝对规范路径，输出父目录须预先为当前用户所有、禁止继承的私有目录（仅当前用户、SYSTEM、Administrators）；输出文件和后续回执路径必须全新，已有文件拒绝覆盖。Windows 使用固定 Node 与清除 `NODE_*` / `I_CORE_*` 后的 PowerShell 5.1 子进程；普通检查使用私有 `.ps1` 和 `-File`。生成器固定 UTF-8 读取请求及输出 XML，避免系统代码页改变原始内容。

D1a 第 5 步在停服前对现役任务预览安全策略：

```powershell
node $generator old-task --task $activeTask --preview
```

`--preview` 只跳过“已停用且无实例”这一项检查，仍执行完整安全推导、往返校验与快照复核。它不要求输出路径；即使传入 `--xml-out` / `--security-out` 也不写入或覆盖。标准输出仅含 XML、security、原始/显式/预期 SDDL、父描述符、只读主体清单的 SHA256，以及 `oldTaskStopped`。生成器自己不创建或修改任何文件、目录，包括临时工件；预览用 `-EncodedCommand` 传递固定仓库检查代码，请求 JSON 通过 UTF-8 标准输入传递，不把请求值拼入代码。

零写入验收比较输出路径、输出父目录、维护目录及任务文件夹的前后状态，并检查进程结束后 `%TEMP%` 无新残留文件。唯一例外是 PowerShell 5.1 宿主为系统策略探测短暂创建、删除的 `__PSScriptPolicyTest_*.ps1/.psm1`：只有名称符合且结束时已不存在的文件可排除。不会为消除这些探测而改变 `TEMP`/`TMP`，或关闭、绕过 AppLocker、WDAC、执行策略检查。

先定位现役任务的唯一活会话，生成默认未批准的关闭输入。生成器复用 `Get-Schema6LoginBinding` / `Get-Schema6LiveSessions`，绑定宿主、窗口、当前控制代和维护快照哈希。`--maintenance-directory` 指向将实际执行 close 的维护目录，`--receipt` 是该入口将写出的全新回执；省略时分别使用生成器目录和 `<out>.receipt.json`。

```powershell
node $generator close-input --task $activeTask --out $closeDraft --maintenance-directory $closeMaintenance --receipt $closeReceipt
# 审阅后，明确批准并用另一个全新输出重新生成；不要复用草稿路径。
node $generator close-input --task $activeTask --out $approvedCloseInput --maintenance-directory $closeMaintenance --receipt $closeReceipt --approve
# 用户同意关闭后，原入口使用生成器产物；此时才会发送 WM_CLOSE。
& $closeScript -ConfigurationPath $approvedCloseInput -ConfigurationSha256 $approvedCloseInputSha256
```

关闭成功后先保存原始 clean-close marker 快照。第 **1b** 步由用户单独同意停用旧任务，再运行只读 `old-task`，取得后续登记使用的原样 XML 和 security JSON：

```powershell
# 仅在用户已批准真实 D1b 第 1b 步、且已确认 clean close 后执行。
. $stopScript
Invoke-Schema6TaskOperation -TaskName $activeTask -Operation Disable
node $generator old-task --task $activeTask --xml-out $oldTaskXml --security-out $reviewedSecurity
```

`old-task` 本身不停止、不停用、不登记或启动任务。普通生成时，旧任务未停用或实例数不为零，以 `evidence_inspection_rejected:old_task_not_stopped` 拒绝，输出文件不创建。它原样保存 `$task.Xml` 和当前 `oldTaskSddl`；`registrationSddl` 保留 owner/group，仅按原顺序提取不带 INHERITED（0x10）的 DACL 条目，不含 SACL。显式条目带其他标志或主体不是 owner/SYSTEM/Administrators 时直接拒绝，不会过滤掉问题条目；完整旧描述符也须通过 `Assert-TaskAllowedRights`。

父描述符哈希、预期 SDDL 和继承只读主体由既有 `task_security_policy.ps1` 函数计算。用提取的显式 SDDL 与当前父文件夹推导出的预期结果，经现有 `Convert-TaskSecurity` 后必须与完整旧描述符一致，否则报 `evidence_inspection_rejected:old_task_security_not_derivable`；父文件夹或旧任务在快照后改变则拒绝。普通生成的两个输出均须是全新私有路径，不能复用旧快照。

随后才能运行 `preparePackageSwitch`、人工批准计划、新包固定离线 package-switch。登记只能在离线换包完成后进行；`stop-schema6-session.ps1` 的返回结果不能代替 close 的批准输入与关闭回执。固定 `prepare_login_schema6.ps1 -PrepareOnly` 的真实回执和 XML 也必须保留。

`registration` 从这些实际证据派生配置及 human-approval 文件。维护快照须含当前 48 项库存中除 `runtime/node.exe` 外的文件，以及既有登记入口的八份维护依赖。`--old-task-xml` 与 `--security` 直接使用第 1b 步 `old-task` 的两个产物，审阅后原样传入，不再手拼 XML 或安全字段。旧任务须继续保持停用和零实例；实际登记入口会再次核对当前 XML、SDDL 与父安全描述符。

把下面命令保存到 `.ps1`，先在末尾加 `--dry-run` 检查，再去掉该开关生成：

```powershell
node $generator registration `
  --switch-plan $approvedPlan --close-input $approvedCloseInput --close-receipt $closeReceipt `
  --offline-control $offlineControl --prepare-receipt $fixedPrepareReceipt --prepared-xml $fixedPreparedXml `
  --old-task-name $activeTask --task-name $newTask --old-task-xml $oldTaskXml `
  --maintenance-snapshot $maintenanceSnapshot --original-marker-snapshot $originalMarkerSnapshot `
  --security $reviewedSecurity --out $registrationConfig --human-approval-out $humanApproval `
  --registration-xml-out $disabledXml --receipt $registrationReceipt
```

`--dry-run` 零文件与目录写入，检查现有绑定及冻结的 `validateSwitchRegistrationEvidence`，只打印脱敏摘要。摘要明确保留 `registrationValidatorPending:true`、`disabledXmlDerivationPending:true` 和 Windows 私有输出 ACL 待检查状态；它不宣称完成全量登记校验。实际生成用 Scheduler 的只读 `NewTask` 序列化仅禁用设置的 XML，暂存批准证据，调用原 `validatePackageSwitchRegistration` 通过后才发布 human-approval 和登记配置；配置发布前再次校验最终引用。它不会执行 `RegisterOnly`。

生成器内部 PowerShell 只透出匹配 `^[a-z0-9_]{1,64}$` 的异常码；其余异常统一为 `evidence_inspection_rejected`。Node/CLI 报告 `evidence_inspection_rejected:<code>`，不包含路径、参数值或原始异常正文。

D1b 更正顺序如下。用户在场，每一步单独同意；必须先合并 R2/R2b，才能执行真实切换：

| 步骤 | 动作 |
|---|---|
| 1 | `close-input` 生成关闭输入；审阅批准后用 `close-schema6-session.ps1` 关闭现役，确认 clean close，保存原始 clean-close marker 快照。从这里开始停服。 |
| 1b | dot-source `stop-schema6-session.ps1`，用 `Invoke-Schema6TaskOperation -TaskName ... -Operation Disable` 停用旧任务；再用 `old-task` 生成旧任务 XML 和 security JSON。 |
| 2 | `preparePackageSwitch` 生成计划；用户审阅后写入 `approved:true`。 |
| 3 | 新包 `start_schema6.ps1 -OfflineOperation package-switch` 完成离线换包。 |
| 4 | `registration` 使用第 1b 步产物，先 `--dry-run`，再生成；用真实配置 SHA 调用 `register-package-switch-login.ps1 -RegisterOnly`，登记停用任务 P。 |
| 5 | C1 以 P 为 `--from-task`，先 `--dry-run`，再登记停用任务 P′。 |
| 6 | 按 D1a 第 4 步结论修改读取策略，加入 `chatgpt_web`；需用户同意，并记录策略文件改前、改后哈希。 |
| 7 | 先运行 `switch-login-task.ps1 -FromTask 现役 -ToTask P′ -DryRun`，再加 `-NoRollback` 实切。旧任务已停用的状态受合成测试覆盖；只启动新任务。服务到此恢复。 |
| 8 | `open-pairing-window.ps1 -TaskName P′` → `pair-core --frontend chatgpt_web` → stop/start 重启会话，让 MCP 加载新凭据。 |
| 9 | 新开 ChatGPT 对话验收；ChatGPT 与 Claude 各写一轮，App 中来源分别显示。 |

第 1b 至第 2 步失败时，可以重新启用并启动旧任务。第 3 步之后，失败一律不起旧任务，按经审阅的反向换包处理。以上全部是部署用法，本轮只交付源码和 CI 验证，不执行本机真实操作。

C1 现在只选择非 `preserved/`、`role: task`、精确名 `tasks/HereIAm-CoreSchema6-Session.xml` 的唯一条目。其他任务与历史条目保持原样，循环模板声明哈希沿用既有规则。合成夹具与 Windows 会话测试均覆盖三条现役 task 加一条 preserved task 的形态。R2 本机仅静态/纯合成验证，真实关闭、离线换包和生成产物的 RegisterOnly 验证由 hosted Windows CI 执行。
