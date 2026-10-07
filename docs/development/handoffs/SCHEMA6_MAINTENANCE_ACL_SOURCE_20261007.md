# Schema 6 ACL 维护源码交接（2026-10-07）

## 范围与状态

本工作包将获准只读的 ACL、owner wrapper、native synthetic test、owner elevation probe 四份私人脚本迁为参数化受审源码。没有运行私人入口，没有读取真实 JSON / 快照 / 数据库 / 凭据，没有访问现役服务、任务或手机。未提交或推送，由主窗整合。

源码不含部署路径、用户 SID、原现场快照哈希或窗口锚。原现场清单数量与旧 owner 数量必须由下阶段私有配置明确传入；数量不是源码默认值。本次合成结果不能代替原现场全项恢复验收。

## 入口与配置合同

- `tools/i_core/maintenance/acl-cutover-maintenance.ps1`：只定义函数；导入不读取配置、不初始化 native、不启用特权、不操作目标。显式调用 `Invoke-AclMaintenance -ConfigPath <private-json> -ExpectedConfigSha256 <sha256> -Mode Audit|Apply|Rollback [-ConfirmFrozen]`。
- `owner-apply-runtime-permissions.ps1`：只定义 `Invoke-OwnerAclMaintenance -ScriptPath -ExpectedScriptSha256 -ConfigPath -ExpectedConfigSha256 -Mode Apply|Rollback -ConfirmFrozen`。由外层在已授权的全新同 owner 管理员 PowerShell 进程中调用。先持有受审脚本只读锁并验源，再验证完整回执；不显示可替代验收的绿色成功页，不发起 UAC，不自行启动现场任务。
- `owner_elevation_probe.ps1`：只定义 `Invoke-AclOwnerRoundtripProbe`。必须传入新的合成父目录、当前 owner、合成 foreign owner、native 源码路径与哈希；仅合成文件做特权往返和最终恢复。无默认现场路径。

ACL 配置格式 `schema6-acl-config-v1`，要求精确以下字段：

| 字段 | 要求 |
|---|---|
| `windowId`, `candidateSourceCommit`, `candidateManifestSha256` | 同一窗口、40 位 commit、64 位 manifest SHA256 |
| `maintenanceRoot`, `baseDirectory` | 私有 owner 目录；后者必须是前者的 `windows/<windowId>` |
| `ownerSid`, `roots` | 当前同 owner、非重叠绝对规范目标目录；拒绝盘根、reparse |
| `snapshotPath`, `snapshotSha256` | 原始 owner/DACL 快照与精确 SHA256；单次打开读取同一组字节并验哈希 |
| `expectedCount`, `expectedForeignOwnerCount` | 全项数量与相对目标 owner 的旧 owner 数量，均无默认 |
| `taskNames`, `ports` | 必须非空、精确的旧任务完整名称与监听端口集合 |
| `frozenReceiptPath`, `frozenReceiptSha256` | 先完成冻结，再生成此下阶段配置并 pin；不存在循环预批准 |
| `receiptPath` | 当前 `baseDirectory` 直属、尚不存在的回执文件；CreateNew 写入 |

每个快照项精确为 `path`, `directory`, `owner`, `sddl`。维护配置、快照、冻证、回执与维护根不得处于目标树内。执行者身份、私有目录 ACL、源/配置/快照锚失败均拒绝；Apply / Rollback 另需显式冻结确认、同 owner 管理员令牌及 `SeRestorePrivilege`，结束恢复原特权状态。

## 冻结与互斥

冻结凭证使用 `schema6-frozen-legacy-runtime-ready-v2`，同 `windowId` / commit / manifest / `windowDirectory`，有效期不超过 60 分钟，`passed`、`databaseReplaced:false`、`aclApplied:false` 为严格布尔，观察至少 65 秒。任务唯一、禁用、零触发器/重试/实例，`portsFree` 精确对应端口清单。

Apply / Rollback 不仅依赖凭证：现场通过 Scheduler COM 重读零实例、零触发器、零重试、Enabled=false、原 SDDL 与冻后任务 XML 哈希。`tasks[].frozenXmlSha256` 是 live `Task.Xml` 字符串 UTF-8 无 BOM 字节的 SHA256，覆盖 Actions / Principals / Settings 等漂移。每次关键检查还重读端口无监听。

每次动作在 `maintenanceRoot/active-window.guard` 以 OpenOrCreate / FileShare.None 持有锁直到回执落盘，不重开一次性 `entry.lock`，不截断旧锁字节。从真实 handle 检查 guard 单硬链接/reparse 状态；目标和祖先持柄禁止改名/删除，目标元数据前后核对。

**ACL 仍不读取目标文件内容，`raw_external_verified:false`。** 该组件的 `passed` 只证明本次 Owner / DACL / 继承与元数据范围。继续准备/注册/启动前，外层必须持同一维护锁重新核完整 `rawAfter` / `external` 内容、manifest 与其他切换条件；不得凭 ACL 回执自动推进。生产 NativeLease、plainPath、严格离线 SHM 策略均未修改。

## 全项与失败恢复

Apply 必须逐项基线匹配、逐项设置私有 Owner / DACL、最终再逐项读回。Rollback 按父先子后恢复每项原 Owner / DACL / 继承，再统一读回每项；Group 与 SACL 不设置，也不声称恢复。

Apply 失败后，仅在冻结、精确库存与全部元数据仍一致时尝试全项恢复。恢复不完整或检查失败标明 `requires_reviewed_recovery`。如果 Start 或其他写者产生 pending 等新文件，精确库存会拒绝；**不得删除 pending、补入清单、忽略新增项或放宽门禁来制造成功回退。** 保全已有冻证、原快照、失败回执、pending 与新增对象，外层停止新的写操作并维持停用条件，记录漂移供单独受审恢复方案决定。ACL 脚本自身不停止服务、不删除文件、不自动恢复旧任务。

## 回执消费者

回执格式 `schema6-acl-maintenance-v2`：绑定 `windowId/candidateSourceCommit/candidateManifestSha256/configSha256/freezeSha256/snapshot_sha256` 与全部数量。Apply 每路径必须有且仅有 `baseline_comparison`、`apply_owner_dacl`、`apply_readback` 三条成功项；起止与逐项时间落在当前明确的动作时间窗。

纯函数 `acl_receipt.mjs::validateAclApplyReceipt(receipt, expected)` 的 `expected` 包含上述六个锚、完整 `paths` 数组、`expectedForeignOwnerCount`、`notBeforeUtc/notAfterUtc`。字段 `freezeSha256` 来源于私有配置的 `frozenReceiptSha256`。拒绝 passed-only、旧窗口/候选/配置/冻结锚、缺项、重复项、路径替换、字符串布尔、错误数量与失败特权恢复。该校验器不是签名系统；调用者还须从可信私有配置获取锚、验回执文件哈希，并拒绝重放。返回 `humanAcceptance:false`。

## 验证证据与尚未通过的 Gate

专项：`node --test tools/i_core/release_schema6/maintenance_acl.test.mjs`。最近本机结果 **24 项：23 通过、0 失败、1 未执行**。

- 迁入原生合成演练：两个新树、8 项，私有 ACL Apply、全项 Owner/DACL/继承恢复、父项传播中断后的全项恢复、文件哈希/组/元数据不变；新增 pending 库存漂移后拒绝回退并保留文件。
- 完整 Audit 调用与实际独占锁：锁原字节保留、并发拒绝、guard 硬链接拒绝、精确库存漂移拒绝；任务/监听访问在夹具中显式禁止。
- import-safe、锚哈希、伪造 passed-only、旧窗口、过期冻证、任务定义/SDDL/启用/触发器/重试/实例漂移与重复任务拒绝；完整 Apply 回执的负向场景。
- 普通沙箱拒绝了新合成目录的 owner 设置；获准范围内仅将本专项在沙箱外运行后通过。没有因此降低生产 ACL 检查。
- 当前本机进程无管理员令牌，**foreign-owner + SeRestorePrivilege 往返未执行，不能以 native 8 项替代。** 独立 Windows CI fixture 已接入；`SCHEMA6_SYNTHETIC_OWNER_PROBE=1` 时缺少管理员令牌必须失败，不能 skip。CI 必须实际完成异 owner 赋值及原 Owner/DACL 恢复，输出不含真实 SID 的结构化诊断，才可关闭该 Gate。本次未发起 UAC。

未运行真实 Apply/Rollback、未重新冻结或注册现场任务，未迁移库、部署或安装。最终 CI 结果与外层 raw/external 守卫由主窗整合验证。
