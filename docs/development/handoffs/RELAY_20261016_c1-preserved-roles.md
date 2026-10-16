<!-- relay:contract v1 -->
## 目标
修复 C1（`update-mcp-source.mjs`）在生产形态备份模板上误报 `inventory_role_missing`：当某些必需角色只存在于 `preserved/` 历史条目中时，C1 仍能生成通过完整校验的新模板，历史条目逐字节不变。

背景（D1a 收尾第 2 次，只读诊断）：生产 `specTemplate` 完整校验通过；但 `credentials`、`domain_policy`、`transcript_grants`、`replay_approvals` 四种角色的活动条目数为 0，只出现在 `preserved/` 下其他分组中（不是 `preserved/mcp-config-switch-source/`）。`backupUpdate` 先去掉全部 `preserved/` 条目得到 view，再调用 `buildMcpSwitchBackup(view,map)`；后者末尾的 `f.validate` 只检查 view，因此报错。完整模板在 `backupUpdate` 末尾本来就会再次校验。

## 完成标准
- [ ] `tools/i_core/maintenance/mcp-config-switch-bindings.mjs`：把 `buildMcpSwitchBackup` 拆成两个导出函数：
  - `mapMcpSwitchBackup(original,map)`：原函数体全部保留（包括 `backup_preserved_collision`、`backup_attachment`、`backup_source_hash` 检查），只去掉末尾的 `f.validate`；
  - `buildMcpSwitchBackup(original,map)`：等于 `mapMcpSwitchBackup` 之后再 `f.validate`。
  对现有调用方（`generate-mcp-config-switch.mjs`、`validateMcpConfigSwitch`），返回值、错误码和顺序完全不变。
- [ ] `tools/i_core/maintenance/update-mcp-source.mjs` 的 `backupUpdate`：对 view 改调 `mapMcpSwitchBackup`。合并历史条目后，对完整 `next.specTemplate` 的 `f.validate`（已有）保持为最终校验。其余逻辑（按索引替换、`preserved/mcp-source-update/<tag>/` 命名、`backup_history_changed`、`unrelated_backup_attachment_changed`）不变。
- [ ] 测试，在 `tools/i_core/test_fixtures/release_schema6/maintenance_mcp_source.test.mjs` 中新增生产形态用例：`credentials`、`domain_policy`、`transcript_grants`、`replay_approvals` 只出现在 `preserved/<其他分组>/` 下（活动条目中没有），另有若干 `preserved/mcp-config-switch-source/` 条目（configuration 和 task），`recovery_custody` 活动区和保留区都有。断言：
  - `--dry-run` 通过；非 dry-run 生成的 backup 配置能通过完整 `validate`；
  - 所有原 `preserved/` 条目逐字节不变；
  - 负例：某角色在完整模板中也不存在时，仍报 `inventory_role_missing`（由第一次 `f.validate` 报出）。
- [ ] `maintenance_mcp_source_windows.test.mjs` 的真实会话夹具改为同样的形态（至少把上面 4 种角色移到 `preserved/` 下），Windows CI 实际执行通过。
- [ ] 现有 `maintenance_mcp_config_switch_bindings.test.mjs`、`maintenance_mcp_config_switch_registration.test.mjs`、`maintenance_mcp_source*.test.mjs` 全部通过，不修改已有断言。

## 允许修改的路径
- `tools/i_core/maintenance/mcp-config-switch-bindings.mjs`（只做上述拆分）
- `tools/i_core/maintenance/update-mcp-source.mjs`（只改 `backupUpdate` 的那一处调用和 import）
- `tools/i_core/test_fixtures/release_schema6/maintenance_mcp_source.test.mjs`、`maintenance_mcp_source_windows.test.mjs`
- `docs/development/handoffs/RELAY_20261016_c1-preserved-roles.md`（只由 Claude 改）

## 不做 / 边界
- 不改 48 项 INVENTORY 内文件，不改 `backup_bundle.mjs` 的 `validate`，不放宽任何校验，不改其他维护入口。
- 不在本机读取或运行生产配置和任务；测试只用合成数据根。
- 止损：同一测试名或同一错误码在连续两个提交上失败即 blocked；最多 3 轮。

## 验证命令
- `node --test tools/i_core/test_fixtures/release_schema6/maintenance_mcp_source.test.mjs`
- `node --test tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs tools/i_core/release_schema6/maintenance_mcp_config_switch_registration.test.mjs`
- `git status --short`（只出现允许路径）
- Windows 真实会话测试由 CI 执行，Claude 读日志判定。

## 需要真人的部分
- 合并由用户进行。合并后，D1a 收尾（C1 dry-run 和 old-task preview）由用户转贴执行。
