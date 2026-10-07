# Schema 6 maintenance freeze/window handoff — 2026-10-07

基线：PR16 工作树 `d4b71a92b38977acd3228197db95750239d7a5c5`。本 worker 未 commit、push、合并或运行现场维护。主窗统一集成 DEVLOG / I_PROJECT_STATE。

## 入口与锁

`enter-maintenance-window.ps1 -ConfigPath <私有JSON> -ExpectedConfigSha256 <64hex> -WindowId <新ID> -Execute` 固定调用 `freeze-legacy-runtime.ps1`，没有 callback、TestMode 或锁绕过。直接调用 freeze 也必须走相同窗口锁。

- 每个新 ID 在 `maintenanceRoot/windows/<WindowId>/` 创建 `entry.lock`、`phase-receipts/`，CreateNew 锁与回执全部保留。
- 旧版锁/回执仅留存，不作为本窗口输入，不删除/改写/复用。旧锁没有句柄时不妨碍新 ID。
- 同一个 WindowId 即使前次失败也拒绝重入。稳定 `active-window.guard` 使用 OpenOrCreate、FileShare.None，全程持有；既有字节保持。
- guard 的真实句柄核验单硬链接/非 reparse；调用 freeze 在配置owner边界内验证root与guard ACL。后续 ACL/Register 可使用 `Acquire-MaintenanceGuard`，不能重新 Open 窗口。

## 私有 freeze 配置

format 必须是 `schema6-maintenance-freeze-config-v2`，`windowId` 精确等于命令行。所有现场值留在私有 JSON。

| 字段 | 约束 |
|---|---|
| maintenanceRoot, ownerSid | 已有 canonical、非 reparse、私有 owner/DACL root；不修改其 ACL |
| candidateDirectory, candidateSourceCommit, candidateManifestSha256 | 固定候选完整库存；40hex Git commit / 64hex SHA256 |
| approvedXmlPath, approvedXmlSha256 | 新登录任务已审核 XML 文件pin；此冻结过程不注册它 |
| freezeScriptSha256, windowModuleSha256 | 外部配置hash锚定冻结脚本和窗口helper，dot-source前先pin |
| validatorSha256, onlineGuardSha256 | 本分支 `precutover_validate_copy.mjs` 与 online guard 源码pin |
| nodePath, nodeSha256, powershellSha256 | Node固定发布hash、v24.14.1；PowerShell是受信任Windows系统路径 |
| databasePath, approvalsPath, grantsPath | 现场既有源输入；绝不嵌入源码或提交真实值 |
| expectedExactBindings, expectedGrants | 副本预检计数期望；PR16 adapter自身仍固定exact_bindings=72 |
| coreHealthUrl | 127.0.0.1 HTTP、Core配置端口、固定 `/v1/core/health` |
| validatorTimeoutMs | 整数30000–300000；有界等待，退出/超时清理验证器已绑定进程树；清理未证实则fail closed |
| modulePins | `{path,sha256}` 数组，必须完整包含本分支 package.mjs、backup_bundle.mjs、activity_control_plane.mjs、inspection_read_only.mjs、maintenance/freeze_verify_candidate.mjs；validator与online guard另有专用pin |
| processImagePins | `{path,sha256}` 数组，覆盖系统PowerShell、验证器Node、两个任务Node和所有许可后代image |
| tasks.core / tasks.mcp | 各含 name、taskPath、ports、originalXmlPath、originalXmlSha256、originalSddl、nodePath/nodeSha256、serverPath/serverSha256、launcherPath/launcherSha256、manifestPath/manifestSha256 |

候选 manifest 的全部文件先持只读lease，再运行 `freeze_verify_candidate.mjs` 调真实 verifyRelease 检查固定库存、source commit、manifest和Node实际版本/hash；该helper不开库、不启动子进程。旧任务的私有XML与live Actions/Principals/Triggers/Settings/SDDL必须吻合。

## 顺序与证据

两旧任务禁用、移除trigger/retry → 绑定身份停 MCP → 本分支 PR16 adapter `--config` 在线只读捕获及独立副本验证 → 停 Core → 首次四件全hash严格闭合 → 至少65000ms无respawn、实例/端口占用，期间及末尾全部四件全字节/identity严比。

**未扩大PR16例外**：仅在线before/after comparator可忽略SHM字节。停Core后第一次 FrozenFiles 仍要求 DB/WAL/SHM/journal 对 online rawAfter 的存在性、size和SHA256严格一致；随后保持native文件identity与全部字节。若实际正常停止造成SHM差异，保守拒绝，留待单独审核，不能重新生成宽松基线。

本窗口新建空 `copy-validation/` 使用候选已完整校验并pin的 `protected_paths.ps1 / Protect-NewDirectory` 保护新工件ACL，以满足PR16输出根要求；该调用不触及父目录或现役Core/i_memory ACL计划，亦非Apply/Prepare/注册/启动候选。

失败恢复只针对两旧任务：原定义先恢复为disabled，保留SDDL；核pins/DB身份/外部资料/进程树无漂移后按Core→MCP启用与恢复，漂移或未能证明验证器树退出时不盲启。所有phase receipts只写私有窗口。

## ready v2 契约

固定输出 `<windowDirectory>/frozen-legacy-runtime-ready.json`，format=`schema6-frozen-legacy-runtime-ready-v2`，30分钟有效。

包含 windowId、windowDirectory、candidateSourceCommit、candidateManifestSha256、configurationSha256、createdUtc/expiresUtc、passed=true、databaseReplaced=false、aclApplied=false、schemaMigrationPerformed=false、observationMs>=65000、approvedXmlSha256、validatorSha256、validationReceiptPath/validationReceiptSha256、copyConfigurationPath/copyConfigurationSha256、rawAfter、external、portsFree、bindings、phaseReceiptsDirectory。

`tasks[]`：name、taskPath、originalXmlSha256、originalSddl、**frozenXmlSha256**（实时Task.Xml的UTF8无BOM字节SHA256）、disabled=true、triggers=0、retries=0、instances=0。后续组件配置使用 frozenReceiptPath / frozenReceiptSha256，另行申请stable guard并现场复核，不凭passed独自进场。

## 验证边界

`node --test tools/i_core/release_schema6/maintenance_window.test.mjs`：3/3通过。

- 真实跨进程guard独占、同ID/中断ID/遍历拒绝、新窗口可进入、旧锁/旧回执/guard字节不变、硬链接guard拒绝。
- 通过AST只取实际源码函数，在临时合成DB/WAL/SHM/journal上逐一翻转字节并验证拒绝；首次SHM漂移、sidecar消失也拒绝。
- 仅启动fixture自己持有的临时PowerShell进程，错误启动时间绑定拒绝结束，正确句柄绑定可结束。
- PowerShell AST语法检查通过；生产入口未执行，真实COM旧任务冻结/恢复、65秒现场观察、实际私有配置、最终设备Gate均未验证。

未改固定runtime库存文件。当前无真实任务/数据库/凭据/快照/现场值进入此handoff或源码；原私有脚本只读用于迁移。

## 独立复核后的补强

- entry 对配置先canonical/reparse检查，再持只读且禁止写删的FileStream；从同句柄计算SHA256、解析JSON、读取Owner/DACL。对待执行freeze源码也先持柄再hash，直到执行返回才释放。合成测试已证明此期间写入/删除被拒。
- Rollback的“definitions restored disabled”只在真实COM回读后成立：通过 `NewTask(0)` 载入原定义并设置 `Settings.Enabled=false` 形成规范化期望，核恢复后的Actions/Principals/Triggers/Settings、Enabled与SDDL。原XML省略Enabled时也由COM补缺省值，不误判为不能恢复。此COM分支现场未执行，补强是源码证据。
- validator的进程采样不是任意恶意fork/逃逸进程树的通用证明。范围限定已pin的固定调用链：captureConsistentSqlite通过同一个Node进程内DatabaseSync/backup读取原库；adapter的直接PowerShell子进程只做Assert-ProtectedPath，不产生孙进程。任何已观察图像/身份漂移或无法证实退出都维持fail closed，不宣称恢复完成。
- freeze/window当前允许1–80位ID，后阶段ACL最低8位；实际配置应使用共同的8–80位字母数字/下划线/连字符。该输入范围统一可由主窗集成处理。
