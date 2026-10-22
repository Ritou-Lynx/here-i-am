<!-- relay:contract v1 -->
## 目标
修两个维护工具问题，都来自 D1b 第 7 步（见 `RELAY_20261012_core-release-r1.md` 的“D1b 执行记录”）。

- **A1**：`stop-schema6-session.ps1` 的 `Assert-Schema6ClosedFiles` 会因为 STATE 顶层任意 `-wal/-shm/-journal` 报 `database_sidecars_present`。但启动闸门（`lifecycle/common.mjs` 的 `closedStateSnapshot`）已经把除 marker 和 relay lock 之外的 STATE 全部文件纳入状态树指纹。两边冲突的结果是：只要有旧 shortcut-mail 日志库的 sidecar，stop 就失败；如果去清理 sidecar，启动又会被拒。改为只拒绝 `i-core.sqlite` 的 sidecar 和被占用的 relay lock，其他 sidecar 记录在案，不判失败。这和 close 入口（`close-schema6-session.ps1:190` 只查 `i-core.sqlite`）的规则一致。
- **A2**：`Wait-Schema6LoginReady` 碰上新会话宿主正在退出时，`Schema6MaintenanceHost.Open` 抛出 `session_host_window_mismatch`，掩盖了真正的原因（当时 Core 子进程报的是 `recovery_required`）。改为：宿主正在退出时 `Open` 返回 null；新会话已经结束时尽快失败；失败信息附上新会话 `child.json` 的 `error_code`。

## 完成标准
**A1：`tools/i_core/maintenance/stop-schema6-session.ps1` 中的 `Assert-Schema6ClosedFiles`**
- [ ] `Assert-Schema6NoRecovery` 仍然最先执行，行为不变。
- [ ] 只有 `i-core.sqlite-wal`、`i-core.sqlite-shm`、`i-core.sqlite-journal` 中任一文件存在时，才抛 `database_sidecars_present`（错误码不变）。
- [ ] STATE 顶层其他名称以 `-wal/-shm/-journal` 结尾的文件不再导致失败。按文件名排序后，输出一行 `Write-Schema6Step 'stop.closed_files_other_sidecars' $true '<逗号分隔的文件名>'`，只写文件名，不写路径。没有这类文件时不输出这一行。
- [ ] `shortcut-mail-relay.runtime.lock` 存在且以 `FileShare.None` 打不开时，抛稳定错误码 `relay_lock_held`，不再透出 .NET 异常原文。lock 存在但没有被占用时通过。`Assert-Schema6PlainPath` 检查保留。
- [ ] 扫描范围仍然只是 STATE 顶层，不递归，也不删除、不改动任何文件。

**A2：`stop-schema6-session.ps1` 中的 `Schema6MaintenanceHost.Open`，以及 `switch-login-task.ps1` 中的 `Wait-Schema6LoginReady`**
- [ ] `Open`：如果窗口校验失败的原因是窗口已经不存在（`GetWindowThreadProcessId` 返回 0），就在进程句柄上最多等待 10000 ms。进程在这段时间内退出则返回 null；没有退出则仍然抛 `session_host_window_mismatch`。其他窗口不符的情况（pid 或线程不符、不是顶层窗口、窗口可见）照旧立即抛错。镜像、所有者、会话的校验和 PID 复用判断都不变。
- [ ] `Wait-Schema6LoginReady`：每轮循环中，如果某个新会话目录（不在 `PreviousSessions` 里）已经有 `session-exit.json`，并且该目录下没有 live session，就立即抛 `new_session_ended_before_ready`，不必等到 `ReadyTimeoutSeconds` 超时。
- [ ] 函数因为任何原因失败时（包括上一条、`new_session_ready_timeout`，以及循环中的其他异常），抛出的消息改为 `<原错误码>;child_error_code=<值>`。取值方法：在新会话目录中找最新的 `control-*` 目录，读其中的 `child.json` 的 `error_code`。没有新会话、没有 `child.json`、或者没有 `error_code` 时，值为 `none`。值不符合 `^[a-z0-9_]{1,64}$` 时，写 `unreadable`。读取本身出错不能掩盖原错误。
- [ ] 成功路径、回滚路径、`-NoRollback`、`-DryRun` 的行为不变。

**测试（合成数据，不碰真实任务）**
- [ ] 新建 `tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_closed_files.test.mjs`（加 PowerShell 夹具，按需要），覆盖以下情况：只有其他 sidecar 时通过并输出 `stop.closed_files_other_sidecars`；存在任一 `i-core.sqlite` sidecar 时报 `database_sidecars_present`；relay lock 被另一个句柄独占时报 `relay_lock_held`；lock 未被占用时通过；有 recovery pending 时报 `recovery_pending_manual_review_required`；断言运行前后 STATE 中的文件集合和哈希都没有变化。
- [ ] 新建 `tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_ready_exit.test.mjs`：
  - 原生测试：起一个合成进程，创建隐藏的顶层窗口，记下 pid 和 hwnd。用例一：销毁窗口后约 1 秒退出，`Open` 返回 null。用例二：销毁窗口后进程继续存活超过 10 秒，`Open` 抛 `session_host_window_mismatch`。窗口仍然有效时，`Open` 正常返回 lease。
  - 纯编排测试（沿用 `safe_switch_session.ps1` 的 mock 写法，或单独写夹具）：在临时 control_root 下造一个新会话目录，放入 `session-exit.json` 和 `control-*/child.json`（`error_code: recovery_required`）。用真实的 `Wait-Schema6LoginReady`，设 `TimeoutSeconds` 为 60，断言在 10 秒内抛出 `new_session_ended_before_ready;child_error_code=recovery_required`。另测：没有 child.json 时得到 `child_error_code=none`；error_code 含非法字符时得到 `unreadable`。
- [ ] 两处旧版哈希钉子要更新：`tools/i_core/release_schema6/maintenance_r2_evidence.test.mjs` 和 `tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_r1_no_rollback.test.mjs` 中的 `ecffd302…`，是 R1 时期“不加 `-NoRollback` 时与旧版逐字节相同”的钉子。A2 有意改动了 `switch-login-task.ps1`，所以改为按同样的还原规则算出的新哈希。注释写明新基线是 A2 合同的提交。其余断言不改。在 SUMMARY 中贴出新旧哈希。
- [ ] 现有 `maintenance_safe_switch*.test.mjs`、`maintenance_mcp_source*.test.mjs`、`tools/i_core/release_schema6/maintenance_*.test.mjs` 全部通过。除了上一条的哈希，不修改任何已有断言。

## 允许修改的路径
- `tools/i_core/maintenance/stop-schema6-session.ps1`（只改 `Assert-Schema6ClosedFiles` 和 `Schema6MaintenanceHost.Open`）
- `tools/i_core/maintenance/switch-login-task.ps1`（只改 `Wait-Schema6LoginReady`，需要的话加一个读 child 错误码的辅助函数）
- `tools/i_core/maintenance/README.md`（只补充 closed_files 规则和 ready 失败的报告格式）
- `tools/i_core/test_fixtures/release_schema6/` 下新建的 `maintenance_safe_switch_closed_files*`、`maintenance_safe_switch_ready_exit*` 测试和夹具；`safe_switch_session.ps1`（只在复用 mock 时改）
- `tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_r1_no_rollback.test.mjs`、`tools/i_core/release_schema6/maintenance_r2_evidence.test.mjs`（只改哈希常量和对应注释）
- `docs/development/handoffs/RELAY_20261022_a1a2-closed-files-ready.md`（只由 Claude 改）

## 不做 / 边界
- 不改启动闸门（`lifecycle/common.mjs`、`runtime_child.mjs`）、close 入口、48 项 INVENTORY 内的文件，不换包。
- 不放宽 `i-core.sqlite` 的 sidecar 检查，不放宽 recovery、receipts 的校验，也不放宽任何身份校验（镜像、所有者、会话、PID 复用）。
- 不做 R1（shortcut-mail relay 关闭时 checkpoint）和 A3、A4。
- 不在本机读取或运行生产配置和计划任务。测试只用合成数据根、合成进程和合成任务适配器。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `node --test tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_closed_files.test.mjs tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_ready_exit.test.mjs`
- `node --test tools/i_core/test_fixtures/release_schema6/maintenance_safe_switch_r1_no_rollback.test.mjs tools/i_core/release_schema6/maintenance_r2_evidence.test.mjs`
- `./tools/i_core/test_fixtures/release_schema6/run_windows_tests.ps1 -MaintenanceOnly`（本机能跑就跑。真实 COM 用例由 CI 执行）
- `git status --short`（只出现允许修改的路径）
- Windows CI 的 `Schema6 Windows maintenance acceptance` 和 `Fixed runtime, recovery, backup and maintenance suites` 由 Claude 读日志判定。

## 需要真人的部分
- 合并由用户进行。
- 合并后在生产上使用：按 D1b 的做法，把 `tools/i_core` 按字节复制成 `<OUT>` 下的受保护副本，从副本运行。不换包，不改 STATE。是否以及何时换用新副本，由用户决定。

## 审核记录
- 第 1 轮：未执行。PR 描述开头不是合同标记（署名放在了最前），watcher 拒绝。描述已修正。
- 第 2 轮（3f5064a2）：done。逐条核对完成标准与允许路径，全部满足；云端复核哈希测试通过（新基线 `9756d2c9…`）。Windows CI 全绿，新增 closed_files 13 项、ready_exit 18 项全部通过。R1 换包后 NoRollback 的真实会话用例在一次 lifecycle 运行中返回 2，同提交另一次运行与重跑均通过，判为不稳定，原因未定位。
- 遗留：`safe_switch_session.ps1:86` 的诊断分支仍用 `-ceq 'new_session_process_not_live'`，新消息带 `;child_error_code=` 后缀后不会触发。只影响测试诊断输出，不影响判定，留待下次。
- 结论：通过，交用户合并。
