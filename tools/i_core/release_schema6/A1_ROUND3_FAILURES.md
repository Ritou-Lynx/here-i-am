# A1 第 3 轮完整诊断失败清单

## 诊断检查点

沿用上一轮已启动的完整命令，等其退出后才开始本轮编辑。结果：544 tests，486 pass，54 fail，4 个既有 skip，退出码 1。54 个失败包括下面 51 个叶子失败及 3 个父测试失败。

```text
node --test --test-concurrency=1 tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs
```

| 文件:行:列 | 失败测试 | 关键错误 |
| --- | --- | --- |
| tools/i_core/release_schema6/backup_bundle.test.mjs:176:1 | Windows PS5.1 production backup child preserves binary frames across console encodings and failed start | TypeNotFound |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:14:1 | real unmanaged legacy MCP read model reproduces non-quiescent Core shutdown | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:29:1 | managed unchanged MCP starts after Core ready and request-opened reader permits clean shutdown and next login | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:43:1 | Core crash stops request-opened MCP tree before recovery replacement and restarts MCP against recovered database | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:58:1 | MCP bounded-stop timeout force-terminates owned real CLI before Core close in the shared 30s budget | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:67:1 | managed MCP configuration rejects altered source and forbidden Node environment before launching any Core | ERR_ASSERTION: actual=2, expected=0 |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:79:1 | real legacy MCP startup port conflict stays a failed session even when Core closes cleanly | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:62:1 | Windows hidden session hook: cancel shutdown creates fresh control; shutdown after writes confirms real clean close | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:89:1 | Windows login preparation is hash-bound, rejects dynamic production port and emits only least-privilege InteractiveToken XML | MissingMandatoryParameter |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:133:48 | launch | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:133:48 | worker | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:148:1 | Windows shutdown timeout kills only the owned tree and the next login recovers without a forged clean receipt | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:164:1 | Windows resident retries one owned Core death in the same login with a fresh control and real data readback | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | query | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | end | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | cancel | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | repeated | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | entry-failure | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | entry-failure-cancel-retry | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | exit-failure | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | timeout | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | final-publication-over-budget | ParameterArgumentValidationErrorEmptyStringNotAllowed |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | late-close-publication | ParameterArgumentValidationErrorEmptyStringNotAllowed |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | late-worker-no-core | ParameterArgumentValidationErrorEmptyStringNotAllowed |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:48:1 | MCP-only candidate chain preserves Core and all backup entries without database/key reads | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | Core configuration replacement | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | Core package replacement | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | Node path | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | data path | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | scope environment | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | extra redirect | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | flag | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | port | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | unknown field | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | missing source | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | backup shrink | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | backup policy | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | backup state | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | same task name | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | unexpected file | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:71:43 | source hardlink | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:78:1 | candidate manifest origin is restricted to the reviewed compatibility commit | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:86:1 | backup file ACL is explicit protected owner and SYSTEM only | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:92:1 | backup file ACL drift rejects finalization before proposal publication | mcp_switch_core_inventory |
| tools/i_core/release_schema6/maintenance_package_switch_registration.test.mjs:37:1 | real close and single Native forward feed fixed Prepare and same-schema RegisterOnly | UnexpectedToken |
| tools/i_core/release_schema6/maintenance_preflight_approval.test.mjs:9:1 | online approval: synthetic ACL144 exact inventory, strict source template, memory-only COM and exact XML | prepare_template_source_changed |
| tools/i_core/release_schema6/maintenance_session_close.test.mjs:19:31 | approved bound WM_CLOSE closes unchanged historical 47 hidden session, managed MCP and Core | ERR_ASSERTION: actual=1, expected=2 |
| tools/i_core/release_schema6/maintenance_session_close.test.mjs:19:31 | approved bound WM_CLOSE closes candidate 84 hidden session, managed MCP and Core | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/precutover_validate_copy.test.mjs:11:52 | real fixed-release precutover adapter: direct | manifest_contract_mismatch |
| tools/i_core/release_schema6/precutover_validate_copy.test.mjs:11:52 | real fixed-release precutover adapter: missing-grant | manifest_contract_mismatch |
| tools/i_core/release_schema6/precutover_validate_copy.test.mjs:11:52 | real fixed-release precutover adapter: cli | manifest_contract_mismatch |

父测试：`tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:132`、`tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:31`、`tools/i_core/release_schema6/maintenance_mcp_config_switch_bindings.test.mjs:52`；错误均来自其子测试。

## 本轮处理与待裁定

- 按第 3 轮裁定，二进制帧测试直接加载仓库原生类，保留 6 组字节和 3 组启动失败，另加源码绑定断言。专项检查 2 pass、0 fail。
- 修正上一轮关闭脚本清单编辑引入的语法损坏；恢复 git 函数结构及 84/48/47 精确清单，AST 解析错误为 0。未改 ACL 逻辑。
- MCP Core 文件数期望从旧 48 改为当前清单长度；发布校验仍逐项核对清单及每个文件。
- Prepare 合成调用补齐三个新增参数；不创建这些参数所指向的绑定或审批文件。
- 登录与会话成功场景依赖新增证据策略、绑定和审批链；本轮不生成这类材料，交云端裁定合成验证方案。
- shutdown 探针依赖旧构造器，以及动态 ScriptBlock 的脚本根路径；这超出本轮明确允许的 Prepare 参数签名调整，未修改。
- `prepare_template_source_changed` 来自生产模板锁定常量与 r08 新签名不一致；不自行重建模板哈希材料。
- precutover 的 3 个用例按 HEAD 打包；诊断时 HEAD 仍为旧覆盖层版本，而工作树已恢复 git 打包，造成包内旧验证器拒绝。保留该历史来源方式，由本轮推送后的 CI 复核。

## 提交边界

保留上一轮 12 文件改动，只推送任务分支。本合同允许路径不含全局状态文档；提交沿用已有 SKIP_PROJECT_STATE 单次例外，随后恢复进程环境，不改 hook 或全局配置。后续完整验证和 CI 结果见本轮固定格式回报。

## 修复后完整验证

545 tests，510 pass，31 fail，4 个既有 skip，0 cancelled，退出码 1；耗时 2748766.4513 ms。31 个失败包含下面 29 个叶子失败以及 session_lifecycle、shutdown_receipts 两个父测试失败。最终二进制管道专项复核为 2 pass、0 fail。

| 文件:行:列 | 失败测试 | 关键错误 |
| --- | --- | --- |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:14:1 | real unmanaged legacy MCP read model reproduces non-quiescent Core shutdown | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:29:1 | managed unchanged MCP starts after Core ready and request-opened reader permits clean shutdown and next login | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:43:1 | Core crash stops request-opened MCP tree before recovery replacement and restarts MCP against recovered database | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:58:1 | MCP bounded-stop timeout force-terminates owned real CLI before Core close in the shared 30s budget | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:67:1 | managed MCP configuration rejects altered source and forbidden Node environment before launching any Core | ERR_ASSERTION |
| tools/i_core/release_schema6/lifecycle/mcp_session_lifecycle.test.mjs:79:1 | real legacy MCP startup port conflict stays a failed session even when Core closes cleanly | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:62:1 | Windows hidden session hook: cancel shutdown creates fresh control; shutdown after writes confirms real clean close | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:89:1 | Windows login preparation is hash-bound, rejects dynamic production port and emits only least-privilege InteractiveToken XML | schema6_login_prepare_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:133:48 | launch | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:133:48 | worker | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:148:1 | Windows shutdown timeout kills only the owned tree and the next login recovers without a forged clean receipt | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs:164:1 | Windows resident retries one owned Core death in the same login with a fresh control and real data readback | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | query | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | end | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | cancel | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | repeated | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | entry-failure | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | entry-failure-cancel-retry | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | exit-failure | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | timeout | MissingMethodException |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | final-publication-over-budget | ParameterArgumentValidationErrorEmptyStringNotAllowed |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | late-close-publication | ParameterArgumentValidationErrorEmptyStringNotAllowed |
| tools/i_core/release_schema6/lifecycle/shutdown_receipts.test.mjs:32:217 | late-worker-no-core | ParameterArgumentValidationErrorEmptyStringNotAllowed |
| tools/i_core/release_schema6/maintenance_package_switch_registration.test.mjs:37:1 | real close and single Native forward feed fixed Prepare and same-schema RegisterOnly | MissingMandatoryParameter |
| tools/i_core/release_schema6/maintenance_preflight_approval.test.mjs:9:1 | online approval: synthetic ACL144 exact inventory, strict source template, memory-only COM and exact XML | prepare_template_source_changed |
| tools/i_core/release_schema6/maintenance_session_close.test.mjs:19:31 | approved bound WM_CLOSE closes candidate 84 hidden session, managed MCP and Core | schema6_login_rejected:configuration_or_release_rejected |
| tools/i_core/release_schema6/precutover_validate_copy.test.mjs:11:52 | real fixed-release precutover adapter: direct | manifest_contract_mismatch |
| tools/i_core/release_schema6/precutover_validate_copy.test.mjs:11:52 | real fixed-release precutover adapter: missing-grant | manifest_contract_mismatch |
| tools/i_core/release_schema6/precutover_validate_copy.test.mjs:11:52 | real fixed-release precutover adapter: cli | manifest_contract_mismatch |

两次完整命令连续失败后按合同第 0 节停止代码修改，以 wip 提交推送。注册夹具在旧语法卡点消除后暴露 `tools/i_core/test_fixtures/release_schema6/package_switch_registration.mjs:90` 缺少三个 Prepare 参数；留待下一轮裁定，未再修改。未进入 pin 外置或错误可见性。CI 按新提交等待并只报告，不在本轮修复。
