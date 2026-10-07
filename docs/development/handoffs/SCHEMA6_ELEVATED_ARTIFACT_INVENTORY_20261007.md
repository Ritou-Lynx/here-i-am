# 提升进程产物 owner 交接清单（2026-10-07）

范围：`tools/i_core/maintenance/` 生产 writer、受其调用的固定运行包 writer、维护配置生成边界。仅源码与合成验证；本文件不表示已部署、切换或通过真人 Gate。r02 已消费，旧证据保持原样。

## 统一策略

新 `owned_artifacts.ps1` 只接受 canonical plain 路径和当前本人 SID。创建新文件/目录时提供显式私有安全描述符，再持真实句柄显式设置本人 owner 与 protected DACL；允许本人、SYSTEM、Administrators FullControl。父目录链保持 no-delete 句柄，文件验证 actual final path、非 reparse、单硬链接与文件身份。JSON 字节在 owner/DACL 验证之后才写。文件 Flush(true)，同柄逐字节读回，再新开只读句柄核同一身份、owner、ACL、字节。目录使用 NtCreateFile FILE_CREATE 原子取得新目录句柄，保持该句柄至第二读柄身份相同、owner/DACL读回完成，避免 CreateDirectory 后按路径重开的替换间隙。禁止复用已有产物，失败不返回成功。

本 helper 不改变 token，不申请 UAC，不启用 privilege，不放宽消费者本人 owner 限制，不递归修复旧产物。新建锁采用同一入口；已有锁只读取/验证 owner、ACL、实际身份，不改 owner、ACL 或内容。运行中的锁保持独占句柄，因此 entry.lock 的读回使用原句柄。

固定运行包 writer 的维护前置同时要求 TokenElevation=false、WindowsPrincipal 非管理员、TokenUser=配置本人 SID 且 TokenOwner=TokenUser；不是只检查组成员资格。Node adapter 无 owner 配置字段时取当前 TokenUser，并与固定 protected root owner 检查结合。

管理员写入后普通本人能否消费，由独立 Windows 跨 token 串联证明；本 helper 自身的重开读取仍是调用者 token，不冒充普通 token 证明。

## 完整生产者—消费者库存

| 产物/范围 | 生产者与 token | 消费者 | owner 与闭合策略 |
|---|---|---|---|
| ACL Audit / Apply / Rollback `config.receiptPath`，包括失败和回滚状态 JSON | `Invoke-AclMaintenance`；Audit 普通本人，Apply/Rollback 同本人管理员 | owner wrapper、普通 Prepare、独立恢复核验 | `Write-OwnedArtifactBytes`；新必填 helper SHA256 外锚，持源码句柄至全部收尾完成 |
| `maintenanceRoot/active-window.guard` | `Acquire-AclMaintenanceGuard` 或 `Acquire-MaintenanceGuard`；可管理员/普通本人 | 所有阶段维护互斥 | 不存在时 `New-OwnedArtifactFile`；已存在只验证本人 owner/私有 ACL/单链接/final path，不改旧锁 |
| `windows/`、`windows/<fresh-id>/`、`phase-receipts/` | `Open-MaintenanceWindow`；可管理员/普通本人 | Freeze/Prepare/注册/人工核验 | 原子 FreshDirectory，创建时私有 SD、持柄 SetOwner 与读回；已有 windows 目录不修复 |
| 新窗口 `entry.lock` | `Open-MaintenanceWindow` | 窗口去重/运行持锁 | fresh owner-fixed FileStream；写入窗口 ID，Flush 与同柄 owner/ACL/字节读回；绝不删锁/复用 ID |
| `rehearsals/`、`copy-validation/`、`prepare-template/` | Freeze 主进程；现在强制普通本人 | 子进程、后续读回 | `New-OwnedArtifactDirectory`；拒绝旧ID/产物复用 |
| `phase-receipts/NNN-*.json` 全部阶段日志，包括 stop、rollback、failed、finished | Freeze 的 `Receipt`→`WriteNew`；普通本人 | 独立复核/后续阶段 | 全部统一 `Write-OwnedArtifactBytes` |
| `copy-validation-config.json` | Freeze `WriteNew`；普通本人 | Node precutover adapter | 统一 writer；hash 后持续 pin |
| `preflight-only-receipt.json`、`frozen-legacy-runtime-ready.json` | Freeze `WriteNew`；普通本人 | 主窗及 ACL/Prepare | 统一 writer；成功仅在写入/真实读回完成后返回 |
| `validator.stdout.txt`、`validator.stderr.txt` | 普通 Freeze 父进程收集并写入；不是管理员子进程自身落盘 | 故障调查 | 统一 writer；不把父进程重定向日志误列为管理员产物 |
| `preparedReceiptPath` | standalone Prepare；强制普通本人 | 注册 verifier/后续签收 | 原局部 SetOwner 逻辑改为统一 writer；持完整源码闭包 pin |
| `registrationReceiptPath` 成功或失败 | RegisterOnly；可同本人管理员 | 普通核验/后续签收 | 统一 writer；失败返回非零，已创建任务保持既有禁用失败策略 |
| settings 新回执目录、`original.json`、`result.json`、`failure.json` | `Invoke-SettingsProtection`；普通或同本人管理员 | 原材料持续持柄、恢复、主窗普通读者 | 新目录和所有 JSON 统一 helper；helper SHA256 必填并持柄验证；仅新证据可写 owner，目标 settings 仍只写 DACL |
| 普通只读模板 `prepare-template/login-task.xml` | exact 固定模板 scriptblock | 普通预检与逐字 approved XML 比较 | 模板执行前显式拒绝管理员；继续固定模板 CreateNew，不改批准 XML 字节 |
| 固定 Prepare `outputXmlPath` | 固定 runtime `prepare_login_schema6.ps1` 子进程 | 普通 Prepare pin、注册 | maintenance PS 和 JS 写入口均拒绝管理员；保持固定47 runtime字节；验证 XML 原批准 hash 与普通 owner |
| `source-schema4.sqlite`、可能临时 capture 文件、`preflight-schema5.sqlite` 与 SQLite 临时 sidecars | Node adapter 调用固定捕获/迁移/预检；强制普通本人 | 隔离 validator | precutover adapter 在任何新产物之前拒绝管理员，使用已私有新目录；保留原 NativeLease/strictClosedPath/单链接/字节验证 |
| `copy-validation/approvals.json`、`grants.json` | 同上，普通 Node COPYFILE_EXCL | 隔离 preflight | 同普通 token 前置；独立 source/copy hash，禁止管理员 writer 路径 |
| `capture-baseline.json`、`anchored-preflight-config.json`、`precutover-validation-receipt.json`、`precutover-validation-rejected.json` | 同上，普通 Node wx | Freeze 普通本人/独立复核 | 同普通 token 前置、私有目录、fresh only；无管理员遗留产物归还路径 |
| 正式 ACL/rollback/login/freeze JSON、review approval、snapshot、维护源码闭包及 manifest | 本目录没有现场生成入口；主窗 fresh 私有配置生成器 | 对应受审入口 | 主窗将新产物接入统一 writer/owner readback并加helper外锚；不得现场修旧r02回执 |
| 固定 runtime 的 session/config/state/pending/head/备份输出 | 固定批准 LeastPrivilege 运行链，非本轮维护源码writer | runtime/MCP/普通本人 | 固定47不变；只有普通本人入口可调用相关固定 writer。若需要管理员调用，当前拒绝，不临时改47或递归改owner |

## 只读模块与合成例外

`acl_receipt.mjs`、`maintenance_outputs.mjs`、`freeze_verify_candidate.mjs`、`online_preflight_input_guard.mjs`、`prepare_live_guard.ps1`、`process_image_binding.ps1`、`task_security_policy.ps1`、`register_task_primitives.ps1` 不自行写文件。后者的 Scheduler COM 动作是单独受审任务权限，不是文件 artifact owner 修复目标。`enter-maintenance-window.ps1` 是持柄调度入口，无独立文件写入。`preflight_approval_checks.ps1` 的 ACL audit 只读、不产 audit receipt；唯一写物是上述纯模板 XML。

`owner_elevation_probe.ps1` 故意在全新合成夹具中切换 owner 并恢复，以测试 Windows 能力；不生成可接受生产回执、不用于生产消费。未把它改为掩盖错误 owner 的 fixture。

## 新源码绑定契约

- `Invoke-AclMaintenance` / `Invoke-OwnerAclMaintenance`：新增必填 `ExpectedOwnedArtifactsSha256`。先持完整祖先链及真实文件句柄，核 final path、单链接、双柄同一身份并 hash 同柄字节，仅从这些已锚定字节构造脚本块执行；Apply/Rollback/Audit 所有结果均遵守。
- Freeze：`modulePins` 必须唯一包含 `owned_artifacts.ps1`，执行前 RequiredPin。管理员进程在创建窗口/冻结/启动 validator 前拒绝。
- Prepare/Register：`maintenanceFiles` 完整闭包必须包含 helper，PS 与 JS required list 均检查；注册只验证模式允许管理员，实际 Prepare 写模式拒绝管理员。
- Settings：脚本和函数新增必填 `ExpectedOwnedArtifactsSha256`，在任何现场目标 DACL 修改或新回执前持柄核 helper。
- 直接调用 Node adapter/API 不构成新的已授权现场入口；正式执行必须由受审 Freeze/Prepare入口提供完整source pin闭包。直接使用 `maintenance_window.ps1` 或 `preflight_approval_checks.ps1` 的受审调用方必须同时锚定其 sibling helper；它不代表来源未验证的新公共现场入口。

## 本 worker 合成证据与尚待证据

- 全部维护 PS1 经 Windows PowerShell 5.1 Parser 解析通过；两个改动 MJS 的 `node --check` 通过。
- 全新 TEMP、普通本人 PowerShell5.1：独审两项修复后重新执行，13/13 断言通过。含目录 owner、文件protected/字节读回、真实 `Open-PreparePin` 消费、新文件重复拒绝且不变、错误owner零产物、硬链接拒绝、窗口owner、guard互斥/重新获取、已用窗口ID拒绝、已有目录拒绝且原SDDL不变。
- 初次在受限sandbox尝试父路径native句柄被拒；脱sandbox后同本人普通token完成。脱sandbox不是UAC，结果明确 `ordinaryOwner=true`，没有宣称管理员→普通串联已完成。
- 两项独立只读审查问题已关闭：原子 NtCreateFile 新目录句柄及同ID读回；ACL helper完整祖先/source原生租约和hash同bytes执行。该复核不代替跨token测试。
- 跨token管理员 writer→普通 Prepare/注册消费者、owner固定失败/写失败、CI强制证据由独立pipeline worker交付，不能由上述13项替代。
- 未访问真实库、凭据、任务、服务或手机，未执行真实权限修改、Core切换、构建、commit/push。全局DEVLOG/I_PROJECT_STATE与现场fresh快照/配置由主窗统一集成。

## 可提交native回归与独审补闭合

新增maintenance_owned_artifacts.test.mjs/对应PS fixture，自动接入既有Windows维护glob；20/20真实native断言、0跳过。覆盖owner/protected ACL/字节、原子目录身份、旧目录碰撞不改SDDL、文件重复不改字节、错误owner零产物、硬链接/旧window/guard、实际token分类、helper错hash及链接source拒绝。父链Open现在带FILE_LIST_DIRECTORY，不再只凭metadata share标志断言不可rename；ACL loader使用专用OpenSourceDirectory，原144项target Open权限保持。独审另行在新TEMP实跑两类来源/工件父目录持柄Move拒绝、释放后Move成功，均通过。主窗最终57项55过0失败2本机特权未跑，79.491秒，真实双token仍待Hosted。