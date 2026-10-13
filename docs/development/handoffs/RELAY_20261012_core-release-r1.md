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
| D1 | 构建新包 → 换包 → C1 换 MCP → 切任务 → 配对 chatgpt_web | 用户在场 | 有，逐步同意 |
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
- [ ] R0 发现的阻塞：只修维护层（`tools/i_core/maintenance/`）。修法要按 R0 给出的错误码逐条说明。
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

## D1：部署顺序（用户在场，每步单独同意）

1. 从合并 R1 后的 v3-lab 构建新包，放到受保护的私有目录。
2. 用换包配置生成器生成新配置，再用新包里的固定 `prepare_login_schema6.ps1 -PrepareOnly` 生成任务 XML，最后用 `preparePackageSwitch` 生成计划。用户审阅后，把计划写成 `approved:true`。
3. `register-package-switch-login.ps1` 登记新任务 P（停用状态）。
4. C1：以 P 为 `--from-task` 生成并登记 P′（新 MCP，停用状态）。候选先复制到受保护目录，先 `--dry-run`。
5. 改真实读取策略，在 `auto_share_origins` 里加入 `chatgpt_web`。需要用户同意。
6. 用 `stop-schema6-session.ps1` 停当前会话，确认 clean close。
7. 运行 `start_schema6.ps1 -OfflineOperation package-switch` 完成离线换包。
8. `switch-login-task.ps1 -FromTask 当前 -ToTask P′ -NoRollback -PublicHealthUrl …`。
9. `open-pairing-window.ps1 -TaskName P′` → `pair-core --frontend chatgpt_web` → 用 stop 和 start 重启会话，让 MCP 加载新凭据。
10. 验收：开一个新的 ChatGPT 对话。ChatGPT 和 Claude 各发一轮，App 里来源分别显示。

## L：注销强杀复现（限时，另立合同）

- 只做 CI 复现：在 hosted Windows 上建立真实交互会话，例如本机回环 RDP，然后真实注销，断言会话宿主拿到 `WM_QUERYENDSESSION`。
- 两轮内拿不到可复现的场景就停，保留“注销前手动停服”的做法。
- 能复现后再定修复。候选修法：宿主启动时 `FreeConsole` 并用 `ShutdownBlockReasonCreate` 阻止关机；子进程改为 `DETACHED_PROCESS`。修复跟随再下一次换包。
