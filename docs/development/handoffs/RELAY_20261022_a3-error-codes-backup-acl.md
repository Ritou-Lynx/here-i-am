<!-- relay:contract v1 -->
# A3 合同：close/register 透出内部错误码，换包生成器产出受保护的 backup 配置

## 目标
两个都来自 D1b（见 `RELAY_20261012_core-release-r1.md` 第 1 步和第 4 步）：

- **错误码**：`close-schema6-session.ps1` 的 catch 只输出 `approved_session_close_rejected`；`register-package-switch-login.ps1`、`register-mcp-config-switch-login.ps1` 和它们调用的 Node 校验器只输出 `*_registration_rejected`。D1b 两次都只能靠只读复现才找到真正原因（`protected_acl_required`、`backup_acl_rejected`）。改成和 `login_schema6.ps1`、`open-pairing-window.ps1` 一样：公开码不变，追加经过白名单校验的内部码。
- **backup ACL**：`generate-package-switch-configurations.mjs` 写出的 `settings/daily-backup-config.json` 只继承父目录 ACL，登记时 `Assert-BackupPrivateAcl` 要求“禁止继承、所有者为当前用户、只有当前用户和 SYSTEM 的显式 FullControl”，因而报 `backup_acl_rejected`。D1b 靠手动复制 ACL 绕过。改为生成器直接产出满足该检查的文件。
- 顺带：`test_fixtures/release_schema6/safe_switch_session.ps1:86` 仍用 `-ceq 'new_session_process_not_live'` 全等匹配。A2 之后消息带 `;child_error_code=` 后缀，诊断分支永远进不去。

## 完成标准
**错误码（统一规则）**：取 `$_.Exception.Message`（Node 侧取 `error.code ?? error.message`），用 `-cmatch '\A[a-z0-9_]{1,64}\z'`（Node 用 `/^[a-z0-9_]{1,64}$/`）校验；不符合时写 `unclassified`。只输出码，不输出路径、SID、值或异常原文。
- [ ] `close-schema6-session.ps1`：stderr 改为 `approved_session_close_rejected:<code>`，退出码仍为 2。
- [ ] `register-package-switch-login.ps1`、`register-mcp-config-switch-login.ps1`：stdout JSON 的 `code` 不变，新增字段 `reason`（成功时不出现）；私有回执中 `$report` 同样记录 `reason`。校验器非零退出时 `reason` 仍为 `registration_proof_rejected`，另从校验器 stdout JSON 读出它的 `reason`，过同一白名单后记为 `validatorReason`（读不到为 `none`）。
- [ ] `package-switch-registration.mjs`、`mcp-config-switch-registration.mjs`：catch 输出的 JSON 增加 `reason`，其余字段不变。
- [ ] 成功路径的输出、退出码和回执其他字段不变。

**backup ACL：`generate-package-switch-configurations.mjs`**
- [ ] `writeNew(bp, backup)` 之后、计算 `backup_configuration_sha256` 之前，把该文件设为：禁止继承、所有者为当前用户、只有当前用户和 SYSTEM 的显式 Allow FullControl。实现可复用 `backup_bundle.mjs` 的 `protect` 写法（文件版），不新增依赖。
- [ ] 设置后立即按 `Assert-BackupPrivateAcl` 的同一规则复核，不通过则报 `configuration_generation_backup_acl_rejected`，保留已生成的候选输出（与现有失败语义一致）。
- [ ] 文件内容和哈希不变；`core.json`、`login.json`、prepared XML 的处理不变。非 Windows 平台跳过 ACL 步骤（与现有 `protect` 行为一致）。
- [ ] 只读检查 `update-mcp-source.mjs` 是否有同样缺口，结论写进 SUMMARY，本合同不改它。

**诊断匹配**
- [ ] `safe_switch_session.ps1:86` 改为按 `;` 前的码匹配（`($msg -split ';',2)[0] -ceq 'new_session_process_not_live'`），其他不变。

**测试（合成数据）**
- [ ] 新建 `tools/i_core/test_fixtures/release_schema6/maintenance_error_codes.test.mjs`：
  - close：造一个会在入口内抛出已知码的合成输入（例如 `protected_acl_required` 或配置哈希不符），断言 stderr 为 `approved_session_close_rejected:<该码>`；异常消息含路径时断言为 `unclassified`。
  - register（两个入口各一例）：用现有 `package_switch_registration.mjs` 夹具，让新侧 backup 配置不受保护，断言 stdout `code` 不变、`reason` 为 `backup_acl_rejected`。
  - Node 校验器：给一个坏输入，断言 `reason` 透出且符合白名单。
- [ ] 在 `release_schema6/maintenance_package_switch_bindings.test.mjs` 增加 Windows 用例：生成器产出的 backup 配置通过与 `Assert-BackupPrivateAcl` 相同的检查；继承 ACL 的父目录下也成立。
- [ ] `package_switch_registration.mjs` 夹具第 70–72 行对 backup 手动设 ACL 的步骤保留（它也覆盖旧侧），不改。
- [ ] 现有 `maintenance_*.test.mjs`（`release_schema6/` 与 `test_fixtures/release_schema6/`）全部通过。如有哈希钉子因改动这些文件而失效，只改常量和注释，SUMMARY 列出新旧值。其他断言不改。

## 允许修改的路径
- `tools/i_core/maintenance/close-schema6-session.ps1`（只改末尾 catch）
- `tools/i_core/maintenance/register-package-switch-login.ps1`、`register-mcp-config-switch-login.ps1`（只改 catch、最终输出和 `Invoke-SwitchRegistrationValidator`）
- `tools/i_core/maintenance/package-switch-registration.mjs`、`mcp-config-switch-registration.mjs`（只改 CLI catch）
- `tools/i_core/maintenance/generate-package-switch-configurations.mjs`（只加 backup 文件 ACL 与复核）
- `tools/i_core/maintenance/README.md`（只补错误输出格式和 backup ACL 说明）
- `tools/i_core/test_fixtures/release_schema6/safe_switch_session.ps1`（只改第 86 行附近匹配）
- 新建 `tools/i_core/test_fixtures/release_schema6/maintenance_error_codes*`；`tools/i_core/release_schema6/maintenance_package_switch_bindings.test.mjs`（只新增用例）
- `docs/development/handoffs/RELAY_20261022_a3-error-codes-backup-acl.md`（只由 Claude 改）

## 不做 / 边界
- 不改公开错误码和退出码，不放宽任何检查（ACL、身份、哈希钉子、INVENTORY）。
- 不改 48 项 INVENTORY 内的文件，不换包，不改启动闸门。
- 不做 A4、R1；不处理 R1 NoRollback 用例偶发返回 2（只在 SUMMARY 记录本轮 CI 是否复现）。
- 不在本机读取或运行生产配置和计划任务。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `node --test tools/i_core/test_fixtures/release_schema6/maintenance_error_codes.test.mjs tools/i_core/release_schema6/maintenance_package_switch_bindings.test.mjs`
- `node --test tools/i_core/release_schema6/maintenance_*.test.mjs`
- `./tools/i_core/test_fixtures/release_schema6/run_windows_tests.ps1 -MaintenanceOnly`（本机能跑就跑）
- `git status --short`（只出现允许修改的路径）
- Windows CI 的 maintenance 相关 job 由 Claude 读日志判定。

## 需要真人的部分
- 合并由用户进行。
- 生产上使用同 A1+A2：复制成 `<OUT>` 下受保护的工具副本再运行；何时换用由用户决定。
