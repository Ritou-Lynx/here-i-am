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

## 1. 用户决定（2026-10-11 已答复）

| 编号 | 问题 | 推荐 | 影响 |
|---|---|---|---|
| D1 | 私有文件的允许 ACE 是“所有者 + SYSTEM”，还是“所有者 + SYSTEM + Administrators”？ | **已定：允许 Administrators**（所有者 + SYSTEM + BA）。A3 以此统一。现有写入器 `owned_artifacts.ps1` 第 48 行和原生读租约本来就写入、接受它；只读检查改动最小；不需要重新改写已有私有文件的 ACL。 | 选严格两项：写入器要改，已有私有文件要在本机逐个重设 DACL，相当于又一次生产侧动作。 |
| D2 | 阶段 A–C 期间，要不要先恢复旧服务，让 Claude 能用？ | **已定：现在恢复**。只重新启用 10-08 起在用的那条登录任务并运行一次，不用 r08、不注册新任务、不消耗 attempt。旧服务运行会改变数据库和 head，r08 里写死的 pin 随之作废，阶段 C 由干跑重新生成。**2026-10-11 已恢复**：只运行该任务一次，Claude 调用成功、未见弹窗。阶段 C 前须按原流程停服并确认闭态。 | 恢复后终端闪窗可能复现；切换前必须重新做停服、闭态检查。 |

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

**A1 第 1 轮结果（PR #23，blocked）**：第 1 步按快照入库完成，测试未调整，Linux 与 4 个 Windows CI 作业失败。原因：r08 的 `package.mjs` 把 git 打包入口改成 `private_overlay_assembly_required`，改为“私有覆盖层 + 来源清单”打包，清单从 48 项扩到 85 项，并把本机私有配置 `transport-endpoints-r04.json` 列为包内文件；另有两处 r08 运行时变更（自动备份配置升到 v2 且要求动态清单策略；登录准备脚本新增证据绑定参数）使旧测试的期望失效。

**第 2 轮裁定**：允许修改包清单与来源闭包校验，但条件是：恢复从 git 提交打包，删除私有覆盖层打包方式（它与“候选代码进 git、CI 覆盖”直接矛盾）；清单保持逐项精确比对；本机配置不进包，改由 pin 文件提供。测试只允许更新期望清单、新参数签名和合成配置夹具，不删测试、不加 skip、不放宽运行时检查；引用旧提交的 47/48 项历史夹具不动。

**A1 第 2 轮结果（未推送，blocked）**：git 打包已恢复，清单 84 项（去掉 transport-endpoints）。卡在 Windows 专项 `production backup child preserves binary frames`：旧测试从包装脚本里抽出 `Start-BackupChild` 单独运行；r08 把这个函数改成依赖脚本作用域（`$PSScriptRoot`、manifest、子脚本哈希核对）并改用原生 `Schema6BackupJob` 直接写管道，抽出来就无法运行。

**第 3 轮裁定**：该测试改为直接加载 `lifecycle/backup_native.cs`，用 `Schema6BackupJob` 验证同样的 6 组字节与 3 组启动失败；另加一条源码断言，确认包装脚本的 `Start-BackupChild` 走 `Schema6BackupJob`、不再用 `ProcessStartInfo`。先跑完一次全量，拿到全部失败再一起修；本轮结束无论结果都推送，便于云端看真实 diff。

**A1 第 3 轮结果（899dd171，blocked）**：Linux/Windows 全量仍 31 失败；Windows 全量本机一次约 46 分钟。剩余 29 个叶子失败中 26 个来自 r08 把审批哈希与证据绑定写进运行时：`login_schema6.ps1`、`prepare_login_schema6.ps1` 新增 `EvidenceBinding*`/`ExpectedApprovalSha256`，`session_window.ps1` 构造器与备份协调器同样要求这些值。让它们变绿只能为测试伪造整条合成审批链，而阶段 D 正是要删掉“任务参数里嵌入的审批哈希”。

**改道（2026-10-11）**：PR #23 停在草稿、不合并，r08 仍以审查包快照为参考。改为：
- **A1b**：从 `v3-lab` 新开分支，只原样迁入 ChatGPT 的 MCP 配置切换路径（生成、绑定、登记、登记脚本、2 个测试、3 个夹具、维护 README 一节，共 10 个文件），运行时保持 48 项不变（与现役同一谱系）。云端已在 Linux 用 v3-lab 加这 10 个文件跑全量：0 失败。
- **A2'**（取代原 A2/A3）：在 v3-lab 运行时上重写精简激活控制器，落实干跑、attempt 后置、错误可见、ACL 统一为所有者 + SYSTEM + Administrators、任务语义比对，不在任务参数里嵌入审批哈希；r08 控制器只作参考。
- r08 的动态 custody 备份覆盖改动另开 PR，先把证据策略与审批哈希解耦，不阻塞 ChatGPT。

**A1b 结果（PR #24，d84b52e6，done）**：云端复核：起点 3ce7aacc；只改 10 个文件 +879/-0；与 12e5da9a 字节一致；17/17 检查通过，Windows 全量 544/0/0。代码与 PR #22 相同，#24 取代 #22。PR #21（ChatGPT 兼容的 MCP 服务改动，f90058f2）云端复核：仅开关 `I_REMOTE_MCP_CHATGPT_ENABLED=1` 时才放行 `https://chatgpt.com` 来源和固定回调，Linux 127/127 通过，10-09 CI 19/19 通过。

**新路线下 ChatGPT 的最短路径**：Core 运行包不换，只把 MCP 配置换成带开关的六文件候选（#21 生成）＋新登录任务（#24 登记）。10-09 已登记过 `HereIAm-iCoreSchema6-chatgpt-20261009-f90058f2`，并于 10-09 19:12 运行过；随后出现公网 502、每 1–3 分钟闪窗，任务被停。云端推测：登录会话起不来（MCP 失败等）→ 任务按失败重试每分钟重启 → 每次启动闪一下 PowerShell 窗口。这是推测，需本机只读诊断 R1 证实后，再写 A2'（精简切换脚本：只读核对 → 关闭当前会话 → 停旧任务、启新任务 → Run 一次 → 健康检查 → 失败自动切回旧任务）。原 A2/A3 的干跑、attempt 后置、错误可见、ACL 统一、任务语义比对并入 A2'。

**R1 只读诊断结果（2026-10-11，done）与更正**：两条登录任务 XML 只差 login.json 路径与哈希，程序、LogonType、RunLevel、Hidden、重试、实例策略、时限、触发器全同；chatgpt 引用链文件齐全、哈希无漂移。10-09 只有 1 个 chatgpt 会话：19:12:48 起，约 366 秒后 `clean_closed`（close_requested），MCP 有启动回执、按关闭流程强停（124，非失败）。今天 17:59 起 cleanclose 只有 1 个会话。**上面“失败重试每分钟重启”的推测被否定。** 502 与“MCP/Core 不在运行”一致（会话关闭后无进程即 502，入场时也已是 502），10-09 当晚诊断日志未覆盖，不能再细分。闪窗不是 chatgpt 任务造成（只跑过一次 6 分钟）；现有候选是 10-07 起每 3 分钟以 PowerShell 运行的 `HereIAm-AgentRelay` 任务（计划任务启动 powershell 即使 `-WindowStyle Hidden` 也常闪一下），未证实。

**改为不写代码的切换试运行（S1，需用户在场授权）**：登录任务触发器为登录（type 9），会话窗口处理注销消息并干净关闭。故切换=两条任务只启用 chatgpt 一条 → 注销再登录 → 核对端口、公网 discovery、ChatGPT 连接、Claude 仍可用、有无闪窗；回滚=反向启用 cleanclose → 注销再登录（即今天已验证的恢复路径）。不生成审批/关闭输入、不改包、不动数据库。A2' 推迟到 S1 后按实际需要再定，可能不再需要。中继 watcher 当前不用（手工交接），建议先停用以排除闪窗候选。

**S1 实测（2026-10-11 北京时间 23:40–01:18，用户在场逐步执行）**：停用 AgentRelay 与 cleanclose、启用 chatgpt 后注销再登录。① 注销强制结束 cleanclose 会话（0xC000013A），库留 wal/shm；② 登录触发 chatgpt：Core 进入自动崩溃恢复，23:43:39 写恢复锁存，23:44:06 因 `offline_probe_failed` 中断（登录高峰期，探针 15 秒时限内未完成，推测），`commitStarted=false`、无 s6-copy 残留，原库未替换；③ 手动重跑被锁存拦下（`recovery_interrupted_review_required`）；④ 确认无占用后把锁存移到用户目录留档（未删），再 Start 一次：自动恢复完成，47841/47860 监听，公网 discovery 200，ChatGPT 连接器 OAuth 连接成功。待核：Claude 是否仍可用、观察闪窗。**教训**：注销不是安全停服，切换前须先走正常关闭；登录期自启程序多时恢复探针可能超时，Start 前应等系统空闲；Start 任务时会闪一次 PowerShell 窗口。

**S1 后续（同日）**：Claude、ChatGPT、Here I Am 三端都能看到消息；停用 AgentRelay 后约 30 分钟无闪窗，闪窗来源基本锁定为该每 3 分钟启动的 PowerShell 任务。新问题：ChatGPT 写回的消息来源仍标 `claude_web`。原因：MCP 写回身份写死为单一前端设备 `frontend:claude_web`（`tools/i_remote_mcp/writeback.mjs` 第 8–10 行，配对名“claude.ai 网页端”；`i_chat_turn` 描述也写死），不区分 OAuth 客户端；Core 本身接受任意 `frontend:<name>`（`tools/i_core/i_core_store.mjs` 第 38 行）。修复与部署见下一合同，部署前须先有安全停服流程（注销会强杀会话）。

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
