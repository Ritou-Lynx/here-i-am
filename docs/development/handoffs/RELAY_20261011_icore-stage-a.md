# iCore 切换阶段 A：接力合同（2026-10-11）

来源：[云端独立审查包](../icore-cloud-review-20261011/README.md)及其审查结论。分工：**Codex 在本机执行，云端只审不写**；用户只处理 `to-human`、`done` 和下面的“用户决定”。

阶段 A 拆成三份接力 PR（A1→A2→A3），按顺序串行。每份 PR 都走 [Agent Relay 协议](../../../tools/agent_relay/PROTOCOL.md)：第 1 轮执行，第 2–4 轮返修，第 4 轮仍不过就转人工。下一份 PR 的 base 必须包含上一份已审过的提交。

## 0. 止损规则（三份合同共用，优先于各轮指令）

- **生产保持暂停。** 不调用任何生产入口的 `-Execute`；不注册、启用或运行真实任务；不读写真实数据库、配置、凭据或 custody；不刷新审批窗口，也不复用旧 attempt。原执行窗口在北京时间 2026-10-11 23:50:48 自然过期，**不发起第四次调用**。
- **不重建审批或哈希链。** 不新建 consent/review/materialization 类材料，也不为了通过检查替换生产 pin。
- **连续失败就停。** 同一条验证命令连续两次失败，立即停止修改，按 `blocked` 回报失败的关键几行。不扩大范围去“顺便修”。
- **COM 只在 CI 上跑。** 本机验证不设置 `SCHEMA6_SYNTHETIC_TASK_TEST` / `SCHEMA6_SYNTHETIC_OWNER_PROBE`。真实 COM 的注册、删除测试只在 GitHub hosted runner 上运行。
- **回报写短。** `SUMMARY` 不超过 10 行，不写哈希长文和时间线。证据以 CI 结果为准。
- **不写本机信息。** 真实 SID、盘符卷标、磁盘序列号、端点域名和本机绝对路径一律不进仓库。

## 1. 用户决定（发 A3 第 1 轮前必须有答复）

| 编号 | 问题 | 推荐 | 影响 |
|---|---|---|---|
| D1 | 私有文件的允许 ACE 是“所有者 + SYSTEM”，还是“所有者 + SYSTEM + Administrators”？ | **允许 Administrators**。现有写入器 `owned_artifacts.ps1` 第 48 行和原生读租约本来就写入、接受它；只读检查改动最小；不需要重新改写已有私有文件的 ACL。 | 选严格两项：写入器要改，已有私有文件要在本机逐个重设 DACL，相当于又一次生产侧动作。 |
| D2 | 阶段 A–C 期间，要不要先恢复旧服务，让 Claude 能用？ | 由用户按需要决定，与阶段 A 无关 | 恢复后终端闪窗可能复现；切换前必须重新做停服、闭态检查。 |

## 2. 合同 A1：入库与错误可见

```markdown
<!-- relay:contract v1 -->
## 目标
把 r08 私有执行链纳入 git、生产 pin 外置到本机文件，并让入口和控制器在失败时输出可定位、已脱敏的阶段与错误码。
## 完成标准
- [ ] 以已公开、已脱敏的审查包快照 `snapshot/r08/` 为唯一来源（不读本机私有候选），把程序放回仓库原相对路径（去 .txt）：仓库没有的 31 个新建；与仓库不同的 8 个用快照版本覆盖（r08 是仓库版本的超集），相邻测试按需最小调整；与仓库相同的 43 个不动。
- [ ] 所有硬编码生产 pin 与脱敏占位（所有者 SID、T 盘卷与磁盘身份、数据库/head/marker/node 哈希、generation、窗口毫秒数、入口 bootstrap 哈希、ReviewFixture 路径、mcp.example.invalid 等）改为从一个 pin 文件读取；仓库只放合成示例 `tools/i_core/test_fixtures/release_schema6/activation_pins.example.json`，真实 pin 文件名加入 .gitignore。本阶段不创建真实 pin 文件（阶段 C 才填）。
- [ ] 入库源码和审查包快照（去 .txt 后缀）对比，除 pin 外置外没有其他逻辑变化；用 diff 统计在 SUMMARY 里说明。
- [ ] 入口的 catch 不再只输出 `continuous_activation_rejected`。改为单行 JSON：阶段名、错误码、脚本内行号、异常类型名。错误码只在匹配 `^[a-z0-9_]{3,64}$` 时原样输出，否则只输出类型名，绝不输出 Message、路径或配置值。控制器的 catch 把原始错误码与阶段写入 result 的 `failureStage` / `failureCode`，不再统一改写为 `activation_failed`。
- [ ] 新增合成测试：每个 throw 的错误码都能原样出现在输出里；构造含路径、SID 和非白名单 Message 的异常时，输出不含它们。
- [ ] 新测试命名为 `tools/i_core/release_schema6/maintenance_activation_*.test.mjs`，自动进入 Linux node、Windows 全量和 MaintenanceOnly 三个 CI 作业，不改 ci.yml；本 PR 的 CI 全绿。
## 允许修改的路径
- tools/i_core/maintenance/
- tools/i_core/release_schema6/
- tools/i_core/test_fixtures/release_schema6/
- .gitignore
## 不做 / 边界
- 见 docs/development/handoffs/RELAY_20261011_icore-stage-a.md 第 0 节止损规则。不改执行顺序和检查语义（那是 A2/A3 的事）。
## 验证命令
- 本机：node --test --test-concurrency=1 tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs
- Windows COM/ACL：以推送后 PR 的 CI 作业 `Schema6 Windows lifecycle and backup` 与 `Schema6 Windows maintenance acceptance` 为准，本机不设合成任务环境变量
## 需要真人的部分
- 无。
```

**A1 第 1 轮指令要点**：先入库，再外置 pin，最后改 catch。三步分三个本地检查点，每步跑一次验证。

## 3. 合同 A2：先只读后消耗、干跑模式、先改任务再切包

```markdown
<!-- relay:contract v1 -->
## 目标
让 attempt 只在第一个真实写操作前消耗；提供不消耗 attempt 的干跑模式；把禁用状态下的任务更新移到包切换之前。
## 完成标准
- [ ] 当前控制器第 297–333 行的全部只读检查（COM 前置、主体/动作、调用者、磁盘卷、端口、进程、MCP/发布清单）移到 attempt 目录创建、消耗标记之前。
- [ ] 控制器新增 `-Mode DryRun`：执行全部只读检查，在第一个写操作前返回 `{format,mode:'DryRun',passed,failureStage,failureCode,reads:[...]}`。不创建 attempt、不写文件、不调用 RegisterTaskDefinition/Run/start_schema6。入口相应支持 `-DryRun`，无需审批文件。
- [ ] `RegisterTaskDefinition`（保持 disabled）及其回读，移到 package switch 之前。回读失败时任务仍为 disabled，包也没有切换，并在 result 里注明 `packageSwitchAttempted=false`。
- [ ] 第 437 行 `Run` 之后的 `State-ne4` 不再立即判失败：在有界时间内轮询实例或会话，再判断；Run 预算仍为 1，认领记录仍先于 Run 落盘。
- [ ] 合成测试：(a) 干跑全程零写入（用文件系统快照对比）；(b) 任一只读检查失败时 attempt 未消耗；(c) 任务回读失败时没有发生包切换；(d) 总 Run 调用次数始终 ≤1。
- [ ] 本 PR 的 CI 全绿。
## 允许修改的路径
- tools/i_core/release_schema6/lifecycle/
- tools/i_core/test_fixtures/release_schema6/
- tools/i_core/release_schema6/*.test.mjs
## 不做 / 边界
- 见 docs/development/handoffs/RELAY_20261011_icore-stage-a.md 第 0 节止损规则。不删除非提权身份、数据库独占锁、head/generation 检查、唯一 Run 预算、P3/P4 和失败收容。
## 验证命令
- 本机：node --test --test-concurrency=1 tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs
- Windows COM/ACL：以推送后 PR 的 CI 作业 `Schema6 Windows lifecycle and backup` 与 `Schema6 Windows maintenance acceptance` 为准，本机不设合成任务环境变量
## 需要真人的部分
- 无。
```

## 4. 合同 A3：统一 ACL、语义比对任务、按实际读依赖生成前置

```markdown
<!-- relay:contract v1 -->
## 目标
消除同一文件存在多套 ACL 规则、预测字节比对任务、前置清单与实际读取集合不一致这三类契约缺陷。
## 完成标准
- [ ] 私有文件 ACL 只剩一个判定函数（按用户决定 D1 的允许 ACE 集合），控制器第 102–104 行、owned_artifacts、evidence-native、backup_owned_artifacts、protected_paths 全部调用它或与它共用常量；用测试断言写入器产出的文件能通过这个判定。
- [ ] 任务比对改为归一化语义比较：SID 归一后的身份、LogonType、RunLevel、Action（路径、参数、工作目录）、Enabled/Hidden、触发器集合、归一化 SDDL（按 ACE 集合比较）。替换第 282/284/289/290/306 行的字节或字符串相等；raw XML 与导出的字节哈希只作为记录，不作为门槛。
- [ ] 在现有 `schema6-maintenance-windows` CI 作业里用真实 COM 注册一个 disabled 合成任务：语义比较接受真实回读；分别篡改身份、LogonType、RunLevel、动作参数、Enabled、触发器、SDDL 的 ACE 时，各自被拒绝。报告里记录 raw Xml、Definition.XmlText 与 Export-ScheduledTask 三者是否逐字节相等（仅作信息）。
- [ ] 前置检查清单由控制器的统一读取函数自动登记生成：执行路径打开的每个文件都必须先出现在干跑的 `reads` 里，否则直接 throw `undeclared_read`；测试断言干跑 reads 与执行到第一个写操作前的实际读取集合相等。
- [ ] 本 PR 的 CI 全绿。
## 允许修改的路径
- tools/i_core/maintenance/
- tools/i_core/release_schema6/lifecycle/
- tools/i_core/test_fixtures/release_schema6/
- tools/i_core/release_schema6/*.test.mjs
- .github/workflows/ci.yml（只允许在 schema6-maintenance-windows 作业内增加步骤）
## 不做 / 边界
- 见 docs/development/handoffs/RELAY_20261011_icore-stage-a.md 第 0 节止损规则。不放宽身份比较：不同 SID、非法身份仍须拒绝。
## 验证命令
- 本机：node --test --test-concurrency=1 tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs
- Windows COM/ACL：以推送后 PR 的 CI 作业 `Schema6 Windows lifecycle and backup` 与 `Schema6 Windows maintenance acceptance` 为准，本机不设合成任务环境变量
## 需要真人的部分
- D1 答复。
```

## 5. 阶段 B–E 进入条件（不在本合同内执行）

| 阶段 | 进入条件 | 完成标准 |
|---|---|---|
| B 真实 Windows 彩排 | A1–A3 合入任务分支且 CI 全绿 | 一次性 Windows 环境中，新建的**标准用户**以非提权身份，在合成数据根上走完注册→导出→启用→Run→P3；可无限重跑。hosted runner 默认提权，必须另建标准用户执行。 |
| C 本机只读干跑 | B 通过 | 主力机上 `-DryRun` 连续两次 `passed=true`，`reads` 无未声明项；不消耗 attempt。 |
| D 生产一次 | C 通过，且用户批准“候选提交 SHA + 时间窗口” | 其余 pin 由机器在干跑时生成、执行时复核；保留非提权、独占锁、head/generation、唯一 Run、备份恢复证据、失败收容。删除 consent/review/materialization/final review 四层、启动器自身哈希，以及任务参数里嵌入的审批哈希。 |
| E 接入与验收 | D 成功 | ChatGPT 兼容分支（`f90058f2`）单独 PR；Claude/ChatGPT 连接验收；正常关机→登录的真人验收（L4）。 |

## 6. 发起方式

**当前采用手动交接**：用户把云端给出的每轮提示词贴进一个**新的** Codex 会话；Codex 在 `codex/` 分支提交、推送并开 draft PR（不加 `agent-relay` 标签，避免 watcher 重复接单）；用户把 Codex 的固定格式回报贴回云端会话，云端读真实 diff 与 CI 后给出下一轮提示词。

以下为改用 watcher 时的做法。watcher 只认 `codex/`、`claude/` 分支，以及仓库所有者本人发的指令评论。因此每份合同由用户（或有该账户权限的云端会话）完成以下四步：

1. 从最新审查分支建 `codex/icore-stage-a1-20261011`；
2. 开 draft PR，base 为 `v3-lab`，描述最前面放上面的合同块，加标签 `agent-relay`；
3. 发 `<!-- relay:to-codex round=1 -->` 评论，正文引用本节对应的“第 1 轮指令要点”；
4. Codex 回帖后在 PR 上 @Copilot 唤起审核。审核方读真实 diff，并在云端复跑 Node 测试。
