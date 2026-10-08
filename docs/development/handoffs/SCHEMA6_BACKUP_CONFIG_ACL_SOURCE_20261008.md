# Schema 6 backup config 单文件 ACL 源码交接

- 基线：`a1f5f70394e11f23d4f231e3483af2f7057c6b16`，分支 `codex/core-preflight-readonly-20261007`。
- 范围：源码与合成验证。未读取真实配置/密钥/数据库，未操作服务、任务或设备，未执行生产 ACL 修改，未 commit/push。
- 用户明确的目标是 protected、owner 保持本人、仅本人和 SYSTEM 的 Allow FullControl；不保留 Administrators ACE。固定生产检查保持不变。

## 新增文件

- `tools/i_core/maintenance/protect-backup-config-file.ps1`：独立维护入口。
- `tools/i_core/release_schema6/maintenance_backup_config_acl.test.mjs`：静态范围检查和 Windows PowerShell 5.1 合成测试入口。
- `tools/i_core/release_schema6/fixtures/maintenance_backup_config_acl.ps1`：仅合成数据、AST 函数加载故障注入，以及独立进程真实顶层 dispatch。

## 调用契约

所有参数必须由当前已审现场方案提供；仓库不保存真实路径、SID、配置正文或密钥。

| 参数 | 含义 |
|---|---|
| `Path` | 唯一目标文件的规范绝对路径 |
| `ExpectedContentSha256` | 原文件字节 SHA256，小写 64 位 |
| `ExpectedOwnerSid` | 已审批 owner SID，必须等于当前调用用户 |
| `ExpectedOriginalDaclSha256` | 原 Access SDDL 的 UTF-8 无 BOM SHA256 |
| `ExpectedProposedDaclSha256` | 新 protected 两主体 Access SDDL 的 UTF-8 无 BOM SHA256 |
| `ReceiptDirectory` | 新建且独立的回执目录；父目录须为本人所有且 protected private ACL |
| `ExpectedOwnedArtifactsSha256` | 已审 `owned_artifacts.ps1` 的字节 SHA256 |
| `Execute` | 显式执行开关；缺失时拒绝 |

入口从本人 SID 生成唯一允许的两主体 DACL，再比对拟议 SHA；不接受任意拟议 SDDL。原 DACL 的哈希口径是 `Access`，不是含 owner/group 的全 SDDL。

祖先链禁止 rename/delete；目标同一文件句柄以 read data、read attributes、READ_CONTROL、WRITE_DAC 打开，仅分享读取。读取和校验规范路径、非 reparse、单硬链接、volume/file ID、大小/写入时间、原字节 SHA、owner/group、原 DACL 后，保存并持有 durable `original.json`，随后再次核对目标。

唯一目标变更使用 `NtSetSecurityObject` 对原句柄提交 DACL-only，不请求 WRITE_OWNER，不读取/修改 SACL，不递归，不修改父目录。写后同柄核对精确 DACL、身份、大小、原字节和 SHA，再以独立只读句柄核对身份/DACL，执行与固定 `Assert-BackupPrivateAcl` 一致的要求。

变更开始后任一步失败，使用原句柄恢复原 DACL及继承保护状态，并读回验证。恢复失败保持 `rollbackVerified=false`、`requiresReviewedRecovery=true`，owner/bytes 的不变结论保留 unknown。回执失败也不放行。成功退出码 0；受控失败退出码 2。

`result.json` 永远是非终态检查点：`passed=null`、`terminal=false`、`phase=validated_requires_successful_exit`，不写成功终态或 completed 时间。它写出之后仍执行最终状态断言；任何写后异常仍精确恢复。只有终态 stdout 的 `passed=true`、`terminal=true`、`phase=completed` 与实际进程 exit 0 同时成立才是成功；主窗必须在外层独立持久化该 process completion。`failure.json` 与失败 stdout 表明该次失败及已验证/未验证的恢复状态，不能将残留 checkpoint 解释为通过。

回执经未改动的 owned-artifacts helper 原子新建、本人 owner、private ACL、flush/readback；只保存本机结构元数据，排除目标正文。`original.json` 在修改期间禁止写入、rename/delete。回执目录不复用。

## 实跑证据

本机 Windows PowerShell 5.1，Node 专项及相邻回归：

```text
node --test tools/i_core/release_schema6/maintenance_backup_config_acl.test.mjs tools/i_core/release_schema6/maintenance_settings_acl.test.mjs tools/i_core/release_schema6/maintenance_owned_artifacts.test.mjs tools/i_core/release_schema6/release.test.mjs
37 tests / 37 pass / 0 fail / 0 skip
```

- 首轮专项 2/2，PS5 fixture 32 条合成断言；上述联合 37/37 是首轮版本证据。独审回执语义修复后的专项重新实跑 2/2、35 条合成断言、0 skip，约 4.2 秒；入口 SHA256 `eed9bee835591cf95f2daa2fc00931f20e13f704253cfb05b70170f15f3980ac`。
- 合成继承 SYSTEM/Administrators/本人变为 protected 本人/SYSTEM；原固定 `key_custody.ps1` 的真实 `Assert-BackupPrivateAcl` 接受结果，原继承三主体被新入口的相同规则拒绝。
- 核对目标 identity/bytes/owner、父目录 DACL、旁边文件 DACL/bytes 不变；新回执 owner、快照内容及读回通过。
- 错 content hash、owner、原/拟 DACL hash、helper hash、硬链接、祖先 reparse、目录目标、非规范路径、已有回执、输出继承/foreign ACE、路径重叠、无 Execute 均在目标变更前拒绝。
- 写后故障精确恢复继承原 DACL；恢复故障保持 unknown；快照失败不改目标；成功回执写失败恢复；持柄期间目标和快照拒写/rename/delete；后加硬链接被拒绝或识别；真实顶层 dispatch 通过。
- 独审修复新增两例：真实 `result.json` 完成创建/readback 后 writer 抛错；`result.json` 写出后的最后一次 applied-state 断言抛错。两例均恢复原 DACL，失败回执确认恢复，残留 result 仍是 `passed=null/terminal=false`，不存在 `passed=true` 终态成功文件。成功路径同样断言检查点非终态、终态返回与 exit 0 完整。
- 相邻 owned-artifacts 20 条原生断言、settings ACL 37 条合成断言、release 固定检查均通过。
- 普通沙箱的 TEMP 祖先路径访问被 Windows 拒绝；经工具批准以不带沙箱的普通用户测试上下文运行以上纯合成测试。未扩大生产权限或修改生产保护。
- `INVENTORY.length === 47`；新增维护入口和 fixture 均不进入固定运行包。`owned_artifacts.ps1`、`key_custody.ps1`、`package.mjs` 和全部既有生产断言没有修改。

## CI 与后续边界

现有 `.github/workflows/ci.yml` 的完整 Windows job 使用 `release_schema6/*.test.mjs`；维护 Windows job 通过 `run_windows_tests.ps1 -MaintenanceOnly` 枚举 `maintenance_*.test.mjs`，自动纳入新测试，无需改 CI。非 Windows job 执行静态测试并显式 skip 原生部分。

主窗负责 diff/边界复核、统一 DEVLOG/当前态、提交/CI 及已获批生产执行。源码合成通过不代表生产已改、真实备份成功或隔离还原通过。生产保持原方案固定文件/哈希，执行时新建独立回执，任何偏差按既有停审规则处理。
