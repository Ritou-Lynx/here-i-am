# Core 发布 R1：在线配对窗口与离线换包部署

日期：2026-10-12。基线：v3-lab `69d9eb0d`，已包含 #24/#21/#25/#26/#27。
上游：`RELAY_20261011_safe-switch-frontend-id.md` 中的“C 部署阻塞”。

## 审核发现（决定本次范围）

1. **Core 配置除了 `manifest_sha256` 以外一律不能改。**
   - 正常重启：`validatePrevious` 要求配置哈希与上次关闭一致。
   - 离线换包：`verifySwitchConfigurations` 去掉 `manifest_sha256` 后要求两端配置完全相同，否则 `switch_configuration_scope_changed`。
   - 换包配置生成器同样只允许 `manifest_sha256` 变化。
   - 结论：靠 `pairing_secret` 开配对窗口在 schema6 下不可能实现；即使做到，每配对一次就要换一次包，设计本身也不对。
2. **新包必须保持 48 项文件清单不变。** `verifySwitchRelease` 只接受历史 47 项或当前 `INVENTORY`，新增文件会让旧包或新包验不过，所以新逻辑只能放进已有文件。
3. **离线换包之后，A 的自动回滚是错的。** `switch-login-task.ps1` 失败时会启动旧任务，但状态已经标记为新包，旧包会拒绝启动。换包后的回退只能走反向换包（工具已有）。
4. **注销强杀（A0）的根因还没复现。**
   - 疑似带控制台的 powershell 宿主先被控制台关闭事件终止（0xC000013A）。子进程也带隐藏控制台，同样可能被提前终止。
   - 没有可复现的自动场景就改运行时，正是上一轮反复烧额度的模式。
   - 所以单独开一项限时调查（L），不阻塞 R1。注销和重启前，先用 A 的停服脚本。
5. **换包工具链从未在当前生产形态上跑过。**
   - 生产的备份配置经过 #24/C1 一类生成器改写；换包生成器要求 4 个附件逐一对应，例如 `reboundNonreleaseEntries.length===4`。
   - 先只读演练（R0），提前暴露阻塞，再写代码。

## 阶段

| 阶段 | 内容 | 谁做 | 生产影响 |
|---|---|---|---|
| R0 | 只读演练换包准备链 | Codex 本机 | 只读生产，只写新私有目录 |
| R1 | 在线配对窗口 + 换包后不回滚 + 修复 R0 阻塞 | Codex，CI 验证 | 无 |
| R2 | 关闭输入与登记配置生成器（10-13 复核新增） | Codex，CI 验证 | 无 |
| D1a | 构建新包、生成配置与 XML、C1 候选 dry-run | Codex 本机 | 只读生产，只写新私有目录 |
| D1b | 关闭 → 换包 → 登记 P → C1 登记 P′ → 切任务 → 配对 chatgpt_web | 用户在场 | 有，逐步同意 |
| L | 注销强杀复现（限时） | Codex，CI | 无 |

## R0 合同：只读演练

- 目标：用 v3-lab HEAD 构建一个演练包，对当前生产 login 跑换包配置生成器和 `preparePackageSwitch`，记录每一步的真实错误码。
- 禁止：登记或修改任务、停止或启动服务、写生产文件、改代码、修复任何发现。
- 预期：Core 在运行时 marker 不是 `clean_closed`，所以最后一步应以 `switch_clean_close_required` 结束。这一步之前的检查（两端配置、包验证、绑定）全部通过，才算 R0 通过。
- 输出：脱敏报告（路径用角色名代替，不含凭据和正文）。

### R0 第 1 次结果（10-13）

- 生产快照：运行包有 48 项，`source_commit` 为 `2c01de5b`；备份条目 configuration 101 条、task 4 条。
- 第 2 步被拒绝，错误码 `linked_path_rejected`：传入的 git.exe 硬链接数为 2。
  - 这是已知的输入问题，`CORE_SCHEMA6_RELEASE_20261006.md` 第 27 行已有记录，不是代码缺陷。
  - 应改用 Git 安装目录下的 `bin\git.exe`（`git --exec-path` 向上三级再进 `bin`），测试夹具也用这个路径。
- 第 3、4 步依赖第 2 步，还没执行。R0 需要换用正确的 git.exe 再跑一次。

### R0 第 2 次结果（10-13）

- 三项锚点不变。改用 `bin\git.exe`（硬链接数 1）后，打包和 verify 通过，48 项，新 manifest `8e4e8dc4…`。
- 第 3 步换包配置生成器通过：三份配置、备份附件重绑，父目录 ACL 合格。
- 第 4 步 `input_missing_or_aliased`：生成器只记录 prepared XML 的路径（`fixedPrepareExecuted:false`），任务 XML 本应由新包里的固定 `prepare_login_schema6.ps1 -PrepareOnly` 生成。
  - 这一步漏写在 R0 合同里，是合同缺口，不是代码缺陷。
- 第 3 次补上 3b：在新包里用固定 Prepare 生成 XML，输出路径取生成器 `static-inputs.json` 的 `preparedXml`。
  - Prepare 要求新包根目录是受保护目录（只有所有者可访问、不继承权限）。
  - 给演练自己创建的目录加这个保护是允许的；生产路径一律不碰。

### R0 第 3 次结果（10-13）

- 3b 固定 Prepare 退出码 2，只给出通用码 `configuration_or_release_rejected`。Prepare 和 login 的 catch 都会吞掉具体原因。
- 第 4 次改为逐项诊断：
  - 先直接运行 `start_schema6.ps1` 的验证模式，它会输出具体错误码；
  - 再用临时诊断脚本（放在演练目录，不进仓库），按 login `-ValidateOnly` 的顺序逐项检查。
- 高可能原因：
  - 子进程继承了 `NODE_*`/`I_CORE_*` 环境变量；
  - 新包文件的所有者不是当前用户，例如提权会话创建，所有者成了 Administrators；
  - 传入的 `-ReleaseDirectory` 与 login 里的 `release_directory`、实际路径大小写不一致（这里用大小写敏感比较）。
- R1 附带项：在 Prepare 与 login 的 catch 中，把内部错误码写到 stderr。只输出错误码，不输出路径和值。

### R0 第 4 次结果（10-13）：通过

- 原因：终端继承了 `NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S`，`start_schema6.ps1:17` 因此拒绝（`inherited_runtime_environment_rejected`）。
  - 这项检查在 try 之外，所以没有输出 JSON 错误码。
  - 另外三类可能原因（大小写、所有者、受保护路径）都已排除，21 项全部 OK。
- 在新开的 PS 5.1 子进程里去掉该变量后：
  - 3b 通过，XML 已生成；
  - 第 4 步按预期以 `switch_clean_close_required` 结束。
  - 换包准备链在当前生产形态上验证通过，维护层没有阻塞。
- 对后续的要求：
  - D1 部署时，每一步都在去掉 `NODE_*`/`I_CORE_*` 的 PS 5.1 子进程中执行。
  - R1 附带改进：Prepare、login 的 catch 输出内部错误码；`start_schema6.ps1` 的环境检查放进 try。

## R1 合同：在线配对窗口

### 完成标准

- [ ] 新增维护入口 `tools/i_core/maintenance/open-pairing-window.ps1 -TaskName <name>`：
  - 用与 `stop-schema6-session.ps1` 相同的方法定位运行中会话的控制目录、run token 和 manifest；找不到会话就拒绝。
  - 用系统 CSPRNG 生成 64 位十六进制一次性配对码。
  - 在受保护的控制目录里原子写入两个文件：
    - `pair.code`：配对码；
    - `pair.request`：内容为 `HMAC(stop.key, token|manifest|pair|sha256(code)|expires_at_ms)` 和 `expires_at_ms`。有效期固定 10 分钟。
  - 配对码只在标准输出打印一次，不进命令行参数、日志或回执。
  - 已有未处理的请求时拒绝，不覆盖。
- [ ] `runtime_child.mjs`，在现有的 25ms 控制轮询里处理 `pair.request`：
  - 校验 HMAC、有效期和 `sha256(code)`；
  - 读入后立即删除 `pair.code` 和 `pair.request`；
  - 调用 `core.replacePairingCode(code)` 打开窗口；
  - 到期或首次成功配对后关闭窗口；
  - 在控制目录写 `pair-receipt-<n>.json`，只含状态、code 哈希前缀和时间。
  - **任何配对请求错误只写拒绝回执，绝不触发 `shutdown`。** 现有轮询遇到异常会关闭 Core，配对路径必须单独 try/catch。
- [ ] `i_core_server.mjs`：新增 `closePairingWindow()`，把 `pairingEndpointEnabled` 设为 false，`activePairingCode` 设为 null。到期由 runtime 调用。窗口关闭后 `/v1/core/devices/pair` 回到 403 `pairing_disabled`。
- [ ] `switch-login-task.ps1`：新增 `-NoRollback`。失败时停在原地，返回码 2，不启用、不启动旧任务，并在报告里写明“需要反向换包”。不加该参数时，行为与现在逐字节相同。
- [ ] 错误可诊断（R0 的教训）：
  - `prepare_login_schema6.ps1` 与 `login_schema6.ps1` 的 catch 改为输出 `schema6_login_prepare_rejected:<内部码>` 和 `schema6_login_rejected:<内部码>`。
  - 内部码只允许 `^[a-z0-9_]{1,64}$`，不符合时仍输出原通用码，不输出路径或值。
  - `start_schema6.ps1` 的继承环境检查移到 try 内，输出 JSON code，并附上被拒变量名（只给名字，不给值）。
  - 退出码和拒绝条件都不变。
- [ ] `INVENTORY`、配置格式、login/mcp 格式、MCP 源码都不变。

### 测试

- Linux：
  - 配对请求正确时窗口打开，并能配对一个 `frontend:chatgpt_web` 设备。
  - 以下情况都要拒绝，且 Core 仍在运行：错误 HMAC、过期、code 哈希不符、重放（同一请求第二次）、残留 `pair.code` 没有对应请求。
  - 到期后返回 403。
  - 进程命令行和日志里都不出现配对码。
- Windows CI：
  - 真实合成会话 → `open-pairing-window.ps1` → 用 `server.mjs pair-core --frontend chatgpt_web` 从标准输入读码完成配对。
  - 再用 stop 脚本正常关闭，断言 clean close、没有恢复锁。
  - 合成换包：从 v3-lab 基线包换到新包，再用 `-NoRollback` 切任务。
  - `INVENTORY` 名单与基线完全相同。

### 允许修改的路径

- `tools/i_core/release_schema6/lifecycle/runtime_child.mjs`
- `tools/i_core/release_schema6/lifecycle/prepare_login_schema6.ps1`、`login_schema6.ps1`、`start_schema6.ps1`（只改错误输出）
- `tools/i_core/i_core_server.mjs`
- `tools/i_core/maintenance/`（新入口、`switch-login-task.ps1`、R0 涉及的修复、README）
- `tools/i_core/test_fixtures/release_schema6/`，`tools/i_core/release_schema6/**/*.test.mjs`
- `tools/i_core/release_schema6/README.md`

### 禁止

- 新增或删除包内文件。
- 改 `package.mjs` 和 `package_switch.mjs` 的校验规则。
- 改配置校验，改 `i_remote_mcp/`。
- 本机真实运行。

### 止损

同一检查在连续两个提交上失败，就停止并报告 `blocked`。同一 SHA 的 push 和 PR 两次运行，只算一次。

## R1 审核（10-13，PR #28，HEAD d47ab940）：通过

- 逐文件读了 19 个改动，全部在允许路径内。48 项 INVENTORY、冻结校验器、配置格式、`i_remote_mcp/` 都没动。
- 配对：
  - 请求 HMAC 绑定 token、manifest、`sha256(code)` 和到期时间，用 `timingSafeEqual` 比较；有效期不超过 10 分钟，带防重放。
  - 输入文件先删除，再开窗；首次配对成功即关窗。
  - 轮询异常不会走到 shutdown；回执里只有哈希前缀。
  - 配对码只出现在 stdout，不进日志或命令行。
- `-NoRollback`：不加时，还原后与基线逐字节一致，云端按 CRLF 复算的哈希等于测试常量。加上后，失败时原地停下并提示反向换包。
- 诊断：`start_schema6` 只报被拒的变量名，退出码保持 1；prepare 和 login 的错误码有白名单正则。
- 测试：
  - 云端 Linux 跑 55 项：27 过、27 跳（仅 Windows）、1 败。失败的是 byte-for-byte 那项：它按 CRLF 拼接，Linux 检出是 LF。CI 上只有 Windows 运行器跑它，所以不阻塞，归入下一次合同顺手修，做法是哈希前先统一换行。
  - CI Windows 日志确认真实会话的两项实跑通过：pair-core `chatgpt_web` 配对后 clean close；从 v3-lab 基线离线换包，再用 NoRollback 切任务。
- 结论：可以转 ready 并合并。

## 复核发现：D1 原顺序不可执行（10-13）

- `register-package-switch-login.ps1` 要求换包后才有的证据：`switchEvent`、`targetFloor`、`targetMarker`、offline 回执（package-switch-registration.mjs:43–52）。所以登记 P 只能放在离线换包之后，不能提前。
- 登记还要求原会话的关闭回执，格式是 `schema6-session-close-approved-v1`。这份回执只有 `close-schema6-session.ps1` 会产出，`stop-schema6-session.ps1` 不产出。所以 D1 停服必须用 close 入口。
- 登记配置约 30 个字段（SDDL、维护文件快照、旧任务 XML、派生 XML 等），仓库里只有测试夹具 `package_switch_registration.mjs:117` 拼过，生产没有生成器。停服期间手拼，正是上次失控的模式，所以先做 R2。

## R2 合同：关闭输入与登记配置生成器

### 完成标准

1. 新增 `tools/i_core/maintenance/generate-package-switch-evidence.mjs`，含两个子命令：
   - `close-input --task <现役任务> --out <新文件>`：只读，从唯一活会话派生 `schema6-session-close-approved-v1`。不加 `--approve` 时 `approved:false`。
   - `registration ...`：输入为批准计划、关闭输入与回执、offline control 目录、固定 Prepare 回执与 XML、旧/新任务名、维护快照目录、回执路径；输出登记配置和 human-approval 两个文件。写出前必须调用现有 `validatePackageSwitchRegistration` 通过。`--dry-run` 零写入，只打印摘要。
2. 输出只写全新私有路径，已存在就拒绝；不启动、不登记、不读密钥。
3. 改造夹具 `package_switch_registration.mjs`，手拼的配置改为调用生成器产出。Windows CI 用生成器产物实际跑通 `register-package-switch-login.ps1 -RegisterOnly`。另外补一个真实会话场景：`close-schema6-session` 用 `close-input` 产物完成关闭。
4. 顺手修 R1 遗留：`maintenance_safe_switch_r1_no_rollback.test.mjs` 的 byte-for-byte 测试，哈希前统一换行，在 Linux 检出下也要通过。
5. 维护 README 补 D1 用法。
6. 修 C1 的 task 条目选择（D1a 第 3 步发现，见下节）。`update-mcp-source.mjs:107` 改为按精确名 `tasks/HereIAm-CoreSchema6-Session.xml` 选择：非 `preserved/`、role 为 task、恰好 1 条，否则仍报 `backup_task_attachment_required`。其他 task 条目必须逐字节不变，由现有 `unrelated_backup_attachment_changed` 检查保证。测试夹具按生产形态构造：3 条非 preserved 的 task 条目，外加 1 条 `preserved/mcp-config-switch-source/` 条目，其中会话条目的 sha256 与文件内容不一致。覆盖以下情况：通过；会话条目 0 条或 2 条时拒绝；另两条 task 条目不变。现有 MCP 换源的 Windows 真实会话测试也要改用这一形态。

### 允许修改的路径

`tools/i_core/maintenance/update-mcp-source.mjs`（只改第 6 条涉及的选择逻辑）、`tools/i_core/maintenance/generate-package-switch-evidence.mjs`（新）、`tools/i_core/maintenance/README.md`、`tools/i_core/test_fixtures/release_schema6/` 下相关测试与夹具、`tools/i_core/release_schema6/maintenance_r2_*.test.mjs`（新）。

### 禁止

改 48 项 INVENTORY 内任何文件；改 `register-package-switch-login.ps1`、`package-switch-registration.mjs`、`close-schema6-session.ps1`、`prepare-package-switch.mjs` 的校验逻辑；放宽任何校验；本机真实运行。

### 止损

同 R1。

## R2 审核（10-14，PR #29，HEAD 94920c9c）：需补一轮 R2b

已通过的部分：
- C1 选择修复（update-mcp-source.mjs:107）正确；0 条、2 条会话条目和其他条目不变都有测试，Windows CI 已实际执行。
- R1 换行修复正确；云端 Linux 复跑 R2、C1 和 R1 相关测试，57 通过，28 跳过（仅限 Windows），0 失败。
- Windows CI 日志确认两项真实执行，不是跳过：“real close and single Native forward feed fixed Prepare and same-schema RegisterOnly”（94 秒），“real R2 generated close input and registration reject invalid evidence before publishing”（64 秒）。夹具已改为调用生成器。
- 执行方式偏离（多行 shell 写入）不影响结果，不阻塞。

阻塞合并的缺口：
1. 登记要求的 `--security` JSON 没有生产来源。夹具靠测试专用的 `package_switch_registration.ps1` 计算 SDDL，生产只能手拼。这与 R2 要消除的手拼模式相同。
2. 登记要求旧任务已停用、无实例，XML 快照与现场一致（register-package-switch-login.ps1:71–74）。D1b 原顺序里没有停用旧任务这一步，也没有生成旧任务快照的工具。
3. 生成器内部 PowerShell 出错时，统一报 `evidence_inspection_rejected`（generate-package-switch-evidence.mjs:93），真实错误码丢失。R0 曾因此多跑三轮；登记又发生在停服期间，必须能看到原因。

## R2b 合同：旧任务快照与错误码（同 PR #29，同分支）

### 完成标准

1. 生成器新增子命令 `old-task --task <旧任务> --xml-out <新文件> --security-out <新文件>`。只读，不停用任何任务。
   - 旧任务必须已停用且实例数为 0，否则报 `old_task_not_stopped`。
   - 写出 `$task.Xml` 原样快照。
   - 写出 security JSON：`oldTaskSddl` 和 `registrationSddl` 都取旧任务当前描述符；`parentSddlSha256`、`expectedRegisteredSddl`、`inheritedReadOnlyPrincipals` 用现有 `task_security_policy.ps1` 的函数计算，算法与夹具一致；`taskSecurityPolicyVersion` 取现值。`Assert-TaskAllowedRights` 不通过时拒绝。
   - 输出规则与其他子命令相同：全新私有路径，已存在就拒绝。
2. `registration` 的 `--old-task-xml` 和 `--security` 可直接使用上一步的产物。Windows CI 的真实登记场景改为由 `old-task` 产出这两项，不再用夹具计算。
3. 生成器内 PowerShell 的 catch：异常消息匹配 `^[a-z0-9_]{1,64}$` 时原样输出，否则仍输出 `evidence_inspection_rejected`。Node 端报错为 `evidence_inspection_rejected:<code>`。加一条测试，确认至少一个内部错误码（例如 `old_task_not_stopped`）能透出。
4. 补一个合成测试：旧任务事先已停用时，`switch-login-task -NoRollback` 仍能成功，且只启动新任务。可沿用 R1 的模拟 COM 夹具。
5. README 的 D1 用法改为下面更正后的 D1b 顺序。

### 允许修改的路径、禁止、止损

同 R2。另外允许修改 `tools/i_core/test_fixtures/release_schema6/` 下的 R1 NoRollback 测试和夹具，仅限第 4 条。

### R2b 修订 1（10-14，HEAD 87de4f1b 报合同冲突后）

第 1 条原写“`registrationSddl` 取旧任务当前描述符”，这是审核方的错误。现役任务的描述符 = 登记时的显式 ACE + 从任务文件夹继承的 ACE；冻结策略 `Get-TaskPolicyExpectedSecurity` 只接受显式 ACE 作为输入。改为：

- `oldTaskSddl`：旧任务当前描述符，原样保存（登记入口用它核对现场）。
- `registrationSddl`：从 `oldTaskSddl` 提取，保留 owner、group，只留没有 INHERITED 标志（0x10）的 DACL 条目，顺序不变，不含 SACL。显式条目带其他标志，或主体不是 owner/SYSTEM/Administrators，都直接拒绝，不过滤。
- 往返校验：`Get-TaskPolicyExpectedSecurity(registrationSddl, 当前父文件夹 SDDL, owner)` 经 `Convert-TaskSecurity` 后必须等于 `oldTaskSddl` 经 `Convert-TaskSecurity` 后的结果；不等就报 `old_task_security_not_derivable`。`expectedRegisteredSddl` 用这次推导的结果。
- 不改 `task_security_policy.ps1` 或任何冻结校验（选项“授权修改策略”不采纳）。
- 新增 `old-task ... --preview`：跳过“已停用、无实例”这一项，其余推导和往返校验照做，零写入，只打印各项 sha256 和 `oldTaskStopped`。D1a 新增第 5 步：对现役任务跑一次 `--preview`，把 SDDL 问题提前到停服前发现。
- 测试：任务文件夹带可继承 ACE 时通过；显式条目里有外部 SID 时被拒；父文件夹在快照后改变时报 `old_task_security_not_derivable` 或 `old_task_snapshot_changed`；`--preview` 零写入。
- XML 编码修复随本轮一起提交。止损计数沿用：87de4f1b 算第 1 个失败提交。
- “零写入”的定义（10-14 补充）：生成器自己不创建、不修改任何文件或目录，包括临时工件。PowerShell 5.1 宿主在 `%TEMP%` 中为策略探测短暂创建并删除的 `__PSScriptPolicyTest_*.ps1/.psm1` 不算违反。不得为消除它们而改 `TEMP`/`TMP`、关闭或绕过 AppLocker/WDAC/执行策略检查。测试断言范围：输出路径、输出父目录、维护目录、任务文件夹在前后一致，并且进程结束后 `%TEMP%` 中没有新残留文件；只有符合该名称模式、且结束时已不存在的文件，才可排除在比对之外。

### R2b 第 2 轮审核（10-15，HEAD 6a593a58）

- 唯一失败是测试断言问题，不是生成器问题。CI 日志：`maintenance_r2_old_task.test.mjs:144` 期望字面 `O:S-1-5-21-…-500…`，实际为 `O:LA…`。CI 的 runneradmin 是本机 RID 500 账户，`GetSddlForm` 会把它缩写成 `LA`。第 146 行（`expectedRegisteredSddl`）修好第 144 行后会以同样原因失败。
- 生产校验都用 `Convert-TaskSecurity` 做语义比较，不受影响。真实继承权限下的 RegisterOnly、preview、外部 SID 拒绝、父目录变化拒绝、NoRollback 预停用等场景均已在 Windows CI 通过。
- 止损判定：止损按“同一测试名或同一错误码”计，不按 job 计。上一提交的失败是 SDDL 合同冲突和 XML 编码，本次是另一个测试，所以未触发止损。Codex 停下是保守做法，没有问题。
- 授权第 3 轮，只改 `maintenance_r2_old_task.test.mjs`：在 `policyFixture()` 中，先把 `explicit` 和 `explicit+inherited` 经 `[Security.AccessControl.RawSecurityDescriptor]::new(x).GetSddlForm('All')` 规范化，再继续使用字面比较。不得改为模糊或语义比较，不得改生成器。这一提交上任何 R2b 测试失败即停。

### R2b 第 3 轮（10-15）：本机 TEMP 噪声，以 CI 为准

- 规范化改动本机通过。唯一失败是 preview 测试的 TEMP 监测：一个改动前就存在、名称不在白名单内的 `.tmp` 文件在监测窗口内被删除。
- 判定：这不是生成器造成的。测试监测的是共享的用户 `%TEMP%`，开发机上其他进程（Codex、浏览器等）随时会增删文件；同一测试在 6a593a58 的干净 CI runner 上已经通过。本轮改动只涉及 `policyFixture()`，与这条测试的路径无关。
- 处理：不改测试，不放宽 TEMP 断言。按原样提交那一个文件并推送，以 CI 为准。这条 TEMP 测试在开发机上只作参考，权威结果以 hosted runner 为准。CI 中任何 R2b 测试失败即停。

### R2b 审核（10-15，PR #29，HEAD 010988b8，审核方 Claude Code）：通过

- diff：`git diff 6a593a58..010988b8` 只改 `maintenance_r2_old_task.test.mjs`（+2/−1）。`policyFixture()` 中 `explicit` 与 `explicit+inherited` 先经 `GetSddlForm('All')` 规范化；原第 144、146 行仍为字面 `assert.equal`。生成器未动。
- PR 全量（v3-lab...HEAD）12 个文件，全部在 R2/R2b 允许路径内；48 项 INVENTORY、冻结校验器、`i_remote_mcp/` 未动。
- CI：push 与 PR 两次运行各 9/9 全绿。
  - 维护 job：391 项，0 失败；7 项跳过均为 Linux 配对测试。
  - 生命周期 job：655 项，0 失败；7 项跳过同上。
  - 两个 job 中 R2b 各项均为 ✔：inherited round-trip、preview TEMP（只出现已消失的 `__PSScriptPolicyTest_*`）、外部 SID 拒绝、父目录变化拒绝、preview 只跳过停用检查、NoRollback 预停用；真实会话 RegisterOnly ✔（91–102 秒，诊断 `roundTripEqual:true`）。
- 云端 Linux 复跑 R2/R2b 两个测试文件：18 项，8 过，10 跳（仅 Windows），0 失败。
- 第三视角补查：生产路径比较 owner 均用 `.Owner.Value` 或 `Convert-TaskSecurity`，不按字面解析 SDDL，所以 `LA` 一类缩写只影响测试字面比较，不影响生产。
- 止损：未触发。
- 结论：可以转 ready，由用户合并 #29。
- Codex 第 3 轮报告（10-15）与上述核对一致：同一 SHA、单文件、两次运行计数相同，无偏离。

### 流程改进（10-15）

- Codex 回合以“推送 + 报告”结束，不在本机等待 CI；CI 由审核方直接读 job 日志核对。
- 仅以 hosted runner 为准的测试（如 preview TEMP 监测），在提示词中事先列明，不在回合中临时改合同。
- 交接方式：源码工作（含 L、后续返修、收尾文档）改走 GitHub relay（`tools/agent_relay/PROTOCOL.md`），Claude 与 Codex 在 PR 评论里直接交接，用户只合并。生产操作（D1a 收尾、D1b）不走 relay：watcher 以 `--sandbox workspace-write` 运行，不能提权；协议“永不”条款排除生产执行；结果会公开贴到 PR。这两段仍由用户转贴，D1b 本来就需要用户在场。

## D1a 结果（10-13 至 10-14）

- 第 0–2 步通过，三项锚点前后一致。新包 manifest `4e003c0b…`（48 项）；候选 login `e8bdf4fe…`；准备 XML `bc94778d…`；MCP 候选 manifest `f7d4872f…`。
- 第 3 步：C1 dry-run 被拒，错误码 `backup_task_attachment_required`。
  - 生产备份和候选备份都有 3 条非 preserved 的 task 条目：`tasks/HereIAm-iCore.xml`、`tasks/HereIAm-iRemoteMCP.xml`、`tasks/HereIAm-CoreSchema6-Session.xml`，外加 1 条 `preserved/mcp-config-switch-source/` 条目。
  - C1 要求恰好 1 条，但测试夹具里只有 1 条，所以 CI 没发现。已并入 R2 第 6 条。
  - 会话条目的 sha256 与文件内容不一致，这是循环模板哈希，按设计保留原声明值。在线备份对非 release 条目会重新计算哈希（automatic_backup.mjs:39），所以不影响备份。
- 第 4 步：`messages.auto_share_origins` 位于 MCP `environment.I_MEMORY_POLICY` 指向的策略文件，生产和候选用的是同一个文件。
  - 两份备份模板都钉了这个文件的哈希（entries[15]）。按上面同样的规则，这只是声明值，不会阻止在线备份。
  - login、Core、MCP 配置都没有钉它的内容哈希。所以 D1b 改策略文件不会牵动配置链，但要在改前、改后各记一次该文件的哈希作为证据。
- R2 合并后，用现役任务作为 `--from-task` 重跑 D1a 第 3 步 dry-run。

## D1a 收尾合同（10-15，#29 合并后执行）

- 范围：只做 D1a 第 3 步（以现役任务为 `--from-task` 的 C1 `--dry-run`）和第 5 步（对现役任务 `old-task --preview`）。工具取自合并 #29 后的 v3-lab 干净检出。
- 复用：#29 未改 48 项 INVENTORY 和 `i_remote_mcp/`，D1a 已构建的新包（`4e003c0b…`）和 MCP 候选（`f7d4872f…`）继续有效；执行前复核候选 manifest 哈希。
- 零写入：两步都不创建 `--out` 和任何输出文件；候选目录、D1a 私有目录、任务文件夹前后快照一致；任务数量与状态不变。preview 的 TEMP 例外同“R2b 修订 1”。
- 三项锚点在开始前、结束后各复核一次。
- 禁止：停服、停用、登记、启动任何任务；改生产文件；被拒后自行修改重试。
- 预期：C1 dry-run 通过；preview 输出各项 sha256，`oldTaskStopped:false`。任何拒绝都只报错误码并停下。
- 回合以报告结束，不等 CI。

## D1：部署顺序（更正版）

**D1a 准备**：不停服，与 R2 并行。

1. 从合并 R1 后的 v3-lab 构建新包，放到受保护私有目录；核对 48 项。
2. 运行换包配置生成器，再运行新包固定 `prepare_login_schema6.ps1 -PrepareOnly`，生成 XML。
3. 用 `chatgpt_candidate.mjs` 构建 MCP 候选，复制到受保护目录。以现役任务为 `--from-task` 跑 C1 `--dry-run`，只验候选形状；零写入。
4. 只读定位 `auto_share_origins` 所在文件，报告它是否被任何配置或备份哈希钉住。
5. R2b 合并后：对现役任务跑 `old-task --preview`，确认 SDDL 可推导（零写入）。

**D1b 切换**：用户在场，每步单独同意；在 R2 合并后进行。

1. `close-input` 生成关闭输入；用户批准后，用 `close-schema6-session.ps1` 关闭现役，确认 clean close。从这里开始停服。随后复制原始 clean-close marker 快照。
   - 1b. dot-source `stop-schema6-session.ps1`，调用 `Invoke-Schema6TaskOperation 现役 Disable` 停用旧任务；再用生成器 `old-task` 产出旧任务 XML 快照和 security JSON（R2b）。
2. `preparePackageSwitch` 生成计划；用户审阅，写入 `approved:true`。
3. 新包 `start_schema6.ps1 -OfflineOperation package-switch` 完成离线换包。
4. `registration` 使用第 1b 步的两项产物，先 `--dry-run`，再生成；`register-package-switch-login.ps1 -RegisterOnly` 登记停用任务 P。
5. C1：以 P 为 `--from-task`，先 `--dry-run`，再登记 P′（停用）。
6. 按 D1a 第 4 步结论修改读取策略，加入 `chatgpt_web`。需要用户同意。
7. 先跑 `switch-login-task.ps1 -FromTask 现役 -ToTask P′ -DryRun`，再加 `-NoRollback` 实切。服务到此恢复。
8. `open-pairing-window.ps1 -TaskName P′` → `pair-core --frontend chatgpt_web` → 用 stop 和 start 重启会话，让 MCP 加载新凭据。
9. 验收：开一个新的 ChatGPT 对话。ChatGPT 和 Claude 各写一轮，App 里来源分别显示。

第 1b 至第 2 步失败时，可以重新启用并启动旧任务。第 3 步之后，失败一律不起旧任务，按反向换包处理。所有 PS 入口都在去掉 `NODE_*` 和 `I_CORE_*` 的 PS 5.1 子进程中运行。

## L：注销强杀复现（限时，另立合同）

- 只做 CI 复现：在 hosted Windows 上建立真实交互会话，例如本机回环 RDP，然后真实注销，断言会话宿主拿到 `WM_QUERYENDSESSION`。
- 两轮内拿不到可复现的场景就停，保留“注销前手动停服”的做法。
- 能复现后再定修复。候选修法：宿主启动时 `FreeConsole` 并用 `ShutdownBlockReasonCreate` 阻止关机；子进程改为 `DETACHED_PROCESS`。修复跟随再下一次换包。

### L 结果（10-15，relay PR #30，2 轮已用完）：停下，待用户决定

- 第 1 轮未执行：本机 watcher 找不到 codex（`spawn codex ENOENT`），属环境问题，不计轮数。已修：VBS 启动器 PATH 加入当前 codex 目录；计划任务改为 `conhost --headless` 包装，不闪窗。codex 目录名随版本变化，以后还会失效，另立小合同让 watcher 自己解析 codex 路径。
- 第 2 轮（f7aa188）：在 `enable_loopback_rdp` 报 `ArgumentException`，原因是对已存在的注册表键用了 `New-Item -Force`。
- 第 3 轮（1bebda7）：注册表、防火墙、RDP 监听、计划任务都通过。等了 5 分钟仍没有测试用户的交互会话，说明 mstsc 回环建不起会话。失败记录处有一个 StrictMode 小 bug，导致没有输出结论。
- 已确认：hosted runner 在 console 会话 2（Active），TermService 运行中，rdp-tcp 处于监听。
- 结论：A0 既没有复现，也没有被否定。保留“注销前手动停服”；D1b 停服本来就用 close 入口。
- 选项：1）L 到此为止（推荐），PR #30 保持 draft；2）用户明确同意后追加 1 轮，改用固定版本、校验 sha256 的 FreeRDP 命令行客户端。
- 用户决定（10-15）：L 到此为止。PR #30 保持 draft，不合并；以后重启时一并修 StrictMode 失败记录 bug。注销或重启前继续先手动停服。

### D1a 收尾第 1 次（10-16）：前快照阶段中止，零写入

- 基线 `fa652c29` 一致，worktree 干净；三项锚点前后一致；MCP 候选 `f7d4872f` 六文件校验通过，DACL 和所有者未变。
- 中止原因：Codex 自写的前快照脚本对 `Get-ScheduledTask` 返回的 CIM 对象调用了 `GetInstances()`（`MethodNotFound`）。仓库工具没有问题，第 3、5 步都还没执行。
- 处理：实例数改用 COM `Schedule.Service` 读取（`GetTask(...).GetInstances(0).Count`），从前快照处续跑。不计入止损。

### D1a 收尾第 2 次（10-16）：C1 dry-run 被拒，错误码 `inventory_role_missing`；零写入

- 前快照、零写入检查和三项锚点都通过；第 5 步按停止规则没有执行。
- 代码定位：`update-mcp-source.mjs` 的 `backupUpdate` 先去掉全部 `preserved/` 条目，再把剩余条目交给 `buildMcpSwitchBackup`，后者内部调用 `f.validate` 检查。`validate` 要求 9 种角色都至少有一条。如果生产模板中某种角色只出现在 `preserved/` 条目里，就会在这一步被拒。生产模板本身在此之前已通过 `f.validate`。CI 夹具的 `preserved/` 只有 1 条 task，覆盖不到这种情况。
- 下一步：先只读诊断各角色在活动和 `preserved/` 条目中的数量，确认推测后再开代码合同修复（走 relay）。

### C1 preserved-only 角色修复审核（10-16，relay PR #31，HEAD 3f871e76）：通过

- 诊断确认：生产模板共 177 条，其中活动条目 128 条、preserved 49 条；`credentials`、`domain_policy`、`transcript_grants`、`replay_approvals` 4 种角色只出现在 preserved 中。完整模板校验 ok，只看活动条目时报 `inventory_role_missing`。
- 修复：拆出 `mapMcpSwitchBackup`，`backupUpdate` 改调它；完整模板的最终校验仍保留。没有放宽任何校验。
- 验证：云端 Linux 跑 88 项，79 过、0 失败、9 项因仅限 Windows 而跳过；CI 9/9 ×2 全绿；新增 3 项用例 ✔；Windows 真实会话 C1 测试实际执行并 ✔。
- 一轮完成，等用户合并。合并后重跑 D1a 收尾（同 10-16 的提示词，基线改为 #31 的合并提交）。

### D1a 收尾第 3 次（10-16，基线 `302a62c0`）：通过，D1a 完成

- 三项锚点前后一致；MCP 候选 `f7d4872f` 未变；前后快照（私有目录、任务列表、COM 实例数、任务文件夹 SDDL）一致。
- 第 3 步 C1 `dry_run_passed`，零写入。field-diff 只涉及允许的字段：MCP 为 `source_files`、`working_directory`；backup 为 `specTemplate.entries`；login 为 mcp/backup 两对路径和哈希。
- 第 5 步 old-task preview 通过，`oldTaskStopped:false`。摘要前 8 位：xml `6aae1345`、security `538b42e8`、oldTaskSddl `c97927ee`、registrationSddl `f39a0cea`、expectedRegisteredSddl `4a5b6ba6`、parentSddl `330eb3ab`、inheritedReadOnlyPrincipals `37517e5f`。D1b 第 1b 步生成的 security JSON 应与这些值一致（停用会改变 XML 中的 Enabled，所以 xml 哈希可以不同）。
- TEMP：只看到两个已消失的策略探测文件；其余变化来自开发机共享 TEMP 的噪声，按约定不判失败。扫描有 4 处错误，覆盖不完整。生成器零写入以 hosted CI 为准（R2b 已验证）。
- 下一步：D1b，用户在场，每步单独同意；开始前暂停 relay watcher。

## D1b 执行记录

### 第 0 步（10-17）：通过，未停服

- 接力任务 HereIAm-AgentRelay 已从 Ready 改为 Disabled；Action 和触发器不变。
- 工具基线为 `302a62c0`（第一次 fetch 遇 TLS 握手失败，重试成功），专用 detached worktree 干净，8 个入口齐全。
- 三项锚点不变。新包 `4e003c0b` 自身 verify 48 项通过，source_commit 为 `6a063386`；`6a063386..302a62c0` 在 48 个 INVENTORY 路径上的 diff 为空。候选 login `e8bdf4fe`、准备 XML `bc94778d`、MCP `f7d4872f` 的哈希和 ACL 不变。
- 读取策略文件改前哈希 `3ecf6202`。没有待处理的控制请求，没有正在运行的备份。D1b 私有输出父目录已建立。

### 第 1 步（10-17）：clean close 完成，开始停服

- 第 1 次关闭被拒，报 `approved_session_close_rejected`，服务未受影响。只读诊断确认原因：worktree 中的 close 脚本和 process_image_binding 两个文件 ACL 含 Users、Authenticated Users，未通过 `Assert-BootstrapPath`（`protected_acl_required`）。close 入口的 catch 吞掉了内部错误码，与 R0 是同一类问题；记为后续改进项，不在本次修改。
- 处理：把 `tools/i_core` 按字节复制到 `<OUT>\tools-302a62c0`（208 个文件，继承受保护 ACL）。校验三项全部通过：`git hash-object --path` 与 302a62c0 的 blob 一致；副本与 worktree 逐字节一致；worktree 干净。D1b 后续步骤都从这份副本运行。首次校验误用原始 blob 字节比较（autocrlf 导致必然不一致），已更正。
- 生成器在 `%TEMP%\schema6-evidence-*` 中的私有临时目录属于既定行为，允许使用；每次运行前后核对无残留。只有 `--preview` 要求零写入。
- 关闭：approved-2 `6a6cb404`；退出码 0，`closed=true`、`wmCloseOnly=true`，用时 12.5 秒。回执 `012b5d3f`，marker 为 clean_closed，锁已释放，进程和端口都已退出。现役任务状态 Ready、启用、实例数 0。原始 marker 快照 `e830854d`。
- 停服开始：北京时间 2026-10-17 23:29:57。

### 第 1b 步（10-17 至 10-21）：通过

- 旧任务已停用：Disabled、实例数 0；任务及任务文件夹 SDDL 前后一致。
- old-task 证据：5 项 SDDL 摘要和 security `538b42e8` 与 D1a preview 完全一致；xml `e3ab9c1a`，与 preview 的差异只有 `Settings/Enabled`（还原该项后恢复 `6aae1345`）；`oldTaskStopped:true`。
- 本步有两次 Codex 自写启动脚本出错（PS 5.1 不支持 `StandardInputEncoding`；首次只读比较漏掉了 Enabled 元素可省略的情况），都已修正后重做，生成器未重试。
- 截至 10-21，服务从 10-17 23:29 起一直停着。第 3 步之前仍可回退：重新启用旧任务并启动即可。

### 第 2、3 步（10-21）：计划已批准，离线换包完成（此后不可简单回退）

- 计划 prepared `4050d6ce`，operationId `d1b-99b67db08bf1c98e`；from 为 `aef68af0`/`6eff3291`，to 为 `4e003c0b`/`f5c3318d`；新侧 artifacts：login `e8bdf4fe`、backup `98d9239d`、mcp `8b90dd40`（两侧相同）、task `bc94778d`；7 项 binding 全部为 true。用户批准后生成批准版 `1e135c37`（与 prepared 相比只有 approved 不同）。
- 第一次在 offline-control 处停下：继承 ACL 不满足 `-Root` 的受保护根要求。只对这个空目录复制了 `<OUT>` 的 ACL 后通过。
- 新包 start_schema6 `-OfflineOperation package-switch` 退出码 0：child `package_switch_completed`，custody generation 18；marker clean_closed，manifest `4e003c0b`、配置 `f5c3318d`、文件 `a91b97e1`；head `05c0fb1d`；锁已释放，无 sidecar，未启动任何进程或任务。
- 完成时间：北京时间 2026-10-21 23:37:04。此后出问题只能走反向换包。

### 第 4 步（10-21 至 10-22）：P 已登记（停用）

- P = `HereIAm-iCoreSchema6-d1a-20261013-6a063386`。
- 固定 Prepare 回执沿用 D1a 的 `215c6c40`，XML 为 `bc94778d`。登记配置 `fbac42a7`，human-approval `879c1e48`，停用 XML `4cf3d435`。
- 第一次登记被拒（`package_switch_registration_rejected`，入口吞掉了内部码）。只读复现第 1–126 行检查：129 项中只有 1 项失败，即第 64 行 `backup_acl_rejected`，原因是新侧备份配置 `98d9239d` 没有禁止继承。该检查只允许当前用户和 SYSTEM，并且要求显式 FullControl。
- 修正：把旧侧 `3d198572` 的 ACL 复制到新侧这一个文件，内容哈希不变。
- 第二次登记退出码 0，状态码 `package_switch_registered_only`：P Disabled，实例数 0，started=false，旧任务未变，数据库未变。回执 `e6a5daa9`；P 的 Definition XML `afd60d9f` 与回执一致。
- 后续改进项：close、register 两个入口都应透出内部错误码；D1a 的换包配置生成器应直接产出受保护的 backup 配置。

### 第 5 步（10-22）：P′ 已登记（停用）

- P′ = `HereIAm-iCoreSchema6-d1a-mcp-20261013-6a063386`。dry-run 与正式运行退出码均为 0，结果为 `registered_disabled`。
- field-diff 与 D1a 演练一致：MCP 变更 source_files、working_directory；backup 变更 specTemplate.entries；login 变更 mcp/backup 两对路径和哈希。
- c1-out 中各文件哈希：mcp `c282597a`、backup `fab3df5c`、login `d49f6010`、task xml `9d2b4170`、field-diff `9b9340c8`。五个文件均为 owned artifact ACL（受保护；当前用户、SYSTEM、Administrators 显式 FullControl）。
- P′ 为 Disabled、实例数 0，Definition XML `86a0da8d`，login 指向 c1-out。P、旧任务、marker、head 均未变。

