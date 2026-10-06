# schema6 候选切换现场清单（待授权，2026-10-06）

本页细化[本人操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)④–⑥，供未来获准窗口逐项执行。本轮仅读取仓库历史报告、候选源码与微软官方说明并编写清单；**没有合并、部署、停启服务、查询现役、读原库/真实备份、注册任务、改设置、重启或操作手机，现役停机为 0**。

编写基线：`codex/core-deploy-readiness-20261006@a608f8ad1761ca2dd2989ec5b654393dce70a2b2`。该提交不是未来部署提交；本页任何历史 PID、文件摘要或快照都不是本次执行授权。

## 开始④以前必须完成

按以下顺序逐项签收，任一未完成均继续原服务，不进入停机窗口：

1. **另获 PR #14 合并授权 → 合入 `v3-lab` → 记录合并后的完整提交 → 从该提交重新生成固定候选。** 不把本分支旧包或合并前 hash 当最终包。固定 Node 为 24.14.1；重新核包库存、源提交、manifest 外锚、配置绑定及该提交所需检查。`prepare` 只打包已提交 Git 树，不代表部署完成。
2. 核九类保全清单、原包/配置/任务恢复资料及恢复工具；历史 52 项和 6 库检查已通过只是既有证据，不能代替切换窗口的原始 DB/WAL/SHM/journal 保全。
3. **Lynx 本人安全输入恢复口令**，使用固定工具的 SecureString 提示和一次性内存管道；不经聊天、参数、环境变量、明文文件或日志。口令由本人独立保管在电脑外；密文、口令包、认证绑定回执配套保管并验证。
4. **Lynx 插入所选 U 盘后，先核目标卷文件系统和确切卷身份，只接受 NTFS。** FAT32、exFAT 或无法确认时停止镜像准备并明确提示：“该目标不是已确认的 NTFS，当前方案不能使用；格式化会清除盘内数据，请由你决定是否格式化或改用其他 NTFS 介质。”**i 不自行格式化，也不自动转换文件系统。** 本人决定不等于已授权格式化执行；只在明确的 NTFS 镜像准备授权后建立受保护目标目录，再配置/验证镜像。仅复制认证密文、口令包和绑定回执，拒绝裸库/正文；外盘缺席保留本机成功备份并报告镜像失败，不删未知文件。
5. 准备生产配置、独立 recovery key/current-head、backup key、control 根和登录任务 XML；release/state/control/config/custody/backup 各有明确 canonical 路径与保护权限。生产端口固定 `47841`，不沿用默认随机端口 `0`。保持 `legacy_b3` 单上传器、reply jobs/activity 关闭、owner-managed 域策略。邮件 debug 关闭，保留 SMTP 配置/DPAPI/journal，不自动重发。
6. 将新候选 source/manifest、现场路径、停启对象、回退界限、停机窗口和真人关机验收交 Lynx 审核，**另获现场切换授权后才执行④**。MCP 更换、手机安装/配置及任务注册各按精确范围授权；本页本身不授权任何动作。本人须明确批准安装交互式登录任务；生成 XML 不等于注册。

镜像介质已确定为 **U 盘**，具体卷身份/目标目录待现场填写。第4项 NTFS 人读提示属于执行者的**现场预检流程**，不是已实现的文件系统专属错误码。源码 `tools/i_core/release_schema6/automatic_backup.mjs` 的 mirror catch 实际返回 `mirrored:false`、`mirrorPending:true`、`mirrorError:'mirror_copy_unavailable_or_rejected'`；ACL/路径保护仍严格。该通用错误本身不能分辨 FAT32/exFAT、外盘断开或权限拒绝；先根据预检证据解释再处理，不能把仅有 ACL gate 宣称为生产代码明确只允许 NTFS。

## 历史定位表：现场必须重新绑定

下表来自[运行操作报告](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)2026-10-06 **12:22–12:27 Asia/Shanghai**，原库路径来自[九类清单](SCHEMA6_BACKUP_COVERAGE_20261006.md)同日 **04:23–04:27 UTC（12:23–12:27 上海）**。没有重新访问这些文件或进程。

| 对象 | 历史精确定位与状态 | 现场核验要求 |
|---|---|---|
| 旧 Core 包 | `D:\HereIAmRuntime\i-core\candidates\b3-v4-phone-transcripts-20261003`；入口 `start_pinned_i_core.ps1`；Node 为包内 `runtime\node.exe` | 完整 10 文件库存、manifest 与入口/Node 摘要重新绑定；不能仅看目录名。 |
| Core 任务/端口 | `\HereIAm-iCore`；AtLogon、Enabled/Running、IgnoreNew，失败重试 5 次/间隔 1 分钟，电池不停；`127.0.0.1:47841` | 保存原 XML/Enabled/重试设置；核当次 wrapper/Node/后代的路径、PID、开始时间、句柄身份和端口归属。 |
| 原 Core 数据 | `D:\memex\tools\i_core\.state\i-core.sqlite`；同目录 `i-core.sqlite-wal`、`i-core.sqlite-shm`、可能存在的 `i-core.sqlite-journal`；锁名 `shortcut-mail-relay.runtime.lock` | 原 canonical 路径不变；journal 是否存在现场记录；原始文件在任何 SQLite 打开前保全。锁文件存在/删除都不证明持锁/释放。 |
| 外置授权 | 同 state 下 `local-transcript-grants.json`、`historical-replay-approvals.json`；历史 1 grant、外置与耐久各 72 replay | 保留完整绑定；现场重新核设备/授权/72 项逐条对应，不把历史计数当现值。 |
| Remote MCP | `\HereIAm-iRemoteMCP`；与 Core 相同登录/重试/IgnoreNew/电池策略；入口 `C:\HereIAm\continuity-b0-b2-20261002\tools\i_remote_mcp\.state\runtime\start-remote.ps1`；Node `D:\Nodejs\node.exe` | 保全 `.state` 的 OAuth、frontend/phone-feed token、writeback 账本及运行入口；不打印凭据，不在普通重启中吊销/重签 token。 |
| MCP 端口 | `127.0.0.1:47860`、`:47862` 同属 MCP Node；OAuth metadata 曾 200、remember changes 未认证曾 401 | 两端口一并核对。47862 保留，captures 真机增改删/用户改卡保护未过不得退役；仅一个消费者。 |
| Cloudflare | 服务名 `Cloudflared`，显示名 `Cloudflared agent`；Auto；失败恢复 5/15/60 秒，复位 86400 秒；`C:\Program Files (x86)\cloudflared\cloudflared.exe`；本地 `127.0.0.1:47864` `/ready` 曾 200 | 它是隧道，非 Core writer。只有范围明确包含它且核无其他站点受影响才冻结/停止；保全并恢复精确服务设置，不扩大到 Tailscale。 |

历史入口 SHA256：旧 Core 启动器 `55ccaa5369687b3c3d9c888cc296b4d4ea16d8fdf3b0eb6dd8dbd97a3cf1b90f`，Core server `9ac97b01711bc580861f5d3aa2308846dad7606f5d28b4ba02939db83c269d46`；MCP 启动器 `7557cdedbef33dd3d53b6655baef542e576653f45127893ff482b50521600799`，MCP server `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6`；MCP Node `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`；Cloudflared `20b9638f685333d623798e733effbad2487093f15ba592f6c7752360ff3b7ab7`。这些均仅属于上述历史窗口。

历史关联：Core wrapper **22704 → Node 12064**（Node 开始 2026-10-05 10:49:29.867+08:00）；MCP **22648 → 22260**（10:49:22.381+08:00）；Cloudflared **13608**（10:49:07.734+08:00）。**禁止凭本页 PID 停任何进程，必须现场重新绑定当前 PID、开始时间、路径/哈希及任务关系后才操作。**

补充依据为另一个仓库工作副本中的既有报告 `C:\HereIAm\predeploy-audit-20261005\docs\development\handoffs\PREDEPLOY_AUDIT_20261005.md`（也可从 Git ref `codex/predeploy-audit-20261005` 的同相对路径复核，本基线未带入该文件）。其 Core 取证窗口是 **2026-10-05 22:59–23:15 上海**，旧包 manifest SHA256 `117c584a7625029526d5f5e0d730dba5c0a9023a8ab32eb07d1900d2ec8a2d50`，旧包 Node SHA256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`；仅作历史对照，不更新前述现役绑定。

该报告手机补验窗口为 **2026-10-06 00:54–00:57 上海**：包 `com.memexlab.hereiam.v3`，版本 `1.0.30 / 113`，APK SHA256 `8b55be76011e8ea8ebba09a23316f7610c56bc25e2c6171846fd13ca4ab49b84`，交叉绑定 B3 构建提交 `8770aa6048daa78ed192212022ca2c2ff92bb394`；手机 main 文件头为62，未做一致 SQL 版本/迁移验证。该证据不证明当前连接、token、队列、capability或持续同步；本页不访问 APK、手机或数据。保持现装 B3 能力，本次 Core 切换不隐含重装手机或切 PR10 上传器授权。

## ④ 停旧 Core、保全原件（预估 5–15 分钟）

| 顺序 | 执行动作 | 完成判据／失败退回 |
|---|---|---|
| ④.1 | 在获准窗口记录开始时间、授权范围和当次 inventory；保存旧任务 XML、Enabled/失败重试、受影响服务设置及客户端队列基线。核所有实际 writer/reader、旁路启动者和消费者。 | 精确进程/端口/路径均有当前绑定。发现不在清单中的依赖或无法排除 writer：停止切换，保持原服务，先补范围。 |
| ④.2 | 先暂停客户端写入口/消费者；冻结 MCP 的触发/重试并停当次绑定任务和进程树。若批准停隧道，先冻结其 Auto/失败恢复再停精确服务。 | MCP wrapper/Node/后代退出，47860/47862 不再由旧进程监听，read model/账本句柄释放。Cloudflare 若在范围内须 SCM Stopped、进程退出、47864 旧监听消失。任务“停止”或网页离线不足以通过。 |
| ④.3 | 冻结旧 Core 任务触发和失败重试、排除手动启动来源，再停止当次绑定旧 Core 任务及进程树。 | wrapper/Node/后代真实退出，47841 旧监听消失；观察覆盖历史 1 分钟重试周期并复核冻结设置。旧 v4 没有认证清停，不写 clean-close 成功，不索取不存在的 guardian 回执。 |
| ④.4 | 由固定候选监督者/离线租约取得真实独占锁，确认无其他 SQLite 句柄；在任何 SQLite 打开前流式加密保存原 DB/WAL/SHM/journal，认证归档并记录原文件集合摘要。 | 有真实 OS 离线证明和认证 raw 保全回执；原件保留，原始 sidecar 不删。持锁/保全失败：不打开/迁移 SQLite；保全失败回执。若所有候选 writer 已停且原状态仍完整兼容 schema4，可按原设置重启旧 Core→MCP→必要隧道并验证。 |

## ⑤ 副本迁移、验证后接管（预估 5–15 分钟）

| 顺序 | 执行动作 | 完成判据／失败退回 |
|---|---|---|
| ⑤.1 | 由同一固定包在隔离副本正常打开 SQLite，恢复已提交 WAL，迁移 4→5→6。始终持真实离线控制，不直接在原件尝试迁移。 | integrity 通过，node_id/设备/旧表消息身份与序号、grant、exact72 replay、配置绑定均匹配；单上传器/关闭策略保持。失败保留副本/密文与无正文回执；原件未替换可按④.4退回。 |
| ⑤.2 | checkpoint/关闭副本，再作 immutable 验证；核准备期间原 DB/sidecar 摘要不变、独立 custody/current-head 绑定正确。 | 所有检查通过才允许提交；缺失独立 authority 不从目标历史自签既有5/6 floor。不使用 InitializeEmpty 打开旧库，不激活 backup_read_only 副本。 |
| ⑤.3 | 进入短提交区：以固定实现保存 pending 证据，将原 sidecar 移入受保护暂存区，合并单库替换原 canonical 路径，推进独立 head。 | 提交回执闭合且没有未解决 pending。多文件/目录步骤不是同一个 SQLite 事务；**一旦开始替换、推进 head 或新 Core 接受写入，不再以旧 v4/旧 DB 覆盖退回。** 中断保持相关 writer 停止，保全新文件、raw 密文、head 和回执，向前修复；不删 latch/pending。 |
| ⑤.4 | 用固定入口 `lifecycle/start_schema6.ps1 -Start`、外锚、原 state、受保护配置、新空 control 和 `CorePort=47841` 启动候选；记录 RunId/ManifestSha256/ControlDirectory。 | `/v1/core/health` 显示真实 schema6、身份/设备/授权边界正确；只有预期进程监听。未 ready 按失败回执排查，不开旧 v4抢占，不通过删除锁绕过启动门控。 |

## ⑥ 客户端与交互式登录任务，立即真人关机验收（预估 10–20 分钟另加开关机时间）

| 顺序 | 执行动作 | 完成判据／失败退回 |
|---|---|---|
| ⑥.1 | 恢复已批准的 MCP、必要隧道（Core→MCP→隧道）；核新 Core 只有 `legacy_b3` 上传器，reply jobs/activity 关闭，邮件 debug 返回 `shortcut_mail_disabled`，不重发在途邮件。 | MCP 47860/47862、OAuth/401 边界和 Cloudflare `/ready` 按范围恢复。旧 MCP session 404 时重新 initialize，不据此重签凭据。captures 未通过仍用47862单消费者。 |
| ⑥.2 | 准备并审阅 `prepare_login_schema6.ps1 -PrepareOnly` 的 XML；核 owner SID、AtLogon、InteractiveToken、LeastPrivilege、IgnoreNew、隐藏窗口、固定 manifest 与 launcher config 外锚、47841。**Lynx 批准后才注册**精确任务名，旧启动来源继续冻结，避免双任务。 | 回读注册内容匹配已审 XML，任务不存用户密码、不设 SYSTEM/开机无人登录启动。新任务名、最终 XML/配置 hash 写现场回执。准备工具仅 `registered:false/started:false` 不代表任务已装。 |
| ⑥.3 | 若⑤.4为直接 supervisor 启动，先走认证 close 并等完整清停，再从获批任务进入交互式 launcher，确保真正挂上关机窗口和每日备份。每次启动使用新空 control。 | 候选由实际登录 launcher/任务接管且仅一实例，backup 配置已绑定、默认24小时/保留30天、NTFS镜像结果单列。不得直接对一个没有 launcher 的进程做关机 Gate 后宣称任务链通过。 |
| ⑥.4 | **切换后立即由 Lynx 正常关机 → 开机 → 登录。** i 不替本人点击关机，不通过合成 WM 消息替代真人动作。保留本次前后 RunId/control/时间线和精确候选哈希。 | 下列四项全部通过才写“切换完成”。任一失败保留候选/现场回执并写“未完成”；原件已替换则向前处理，不自动降回旧 v4。 |

四项必须全部签收：

- [ ] **正常关机 clean-close 回执**：旧会话 listener/store 关闭、child exit0、guardian exit0、Job 空、无强杀、marker `clean_closed`、锁实际释放全部成立。`stop_requested` 或端口消失不是完成；认证排空上限与 Windows 会话关机总预算不同，候选 README 记总预算30秒，系统仍可能强终止。若超时进入 recovery_required，即使下次恢复成功也不能把本项改称 clean-close 通过。
- [ ] **自动启动**：本人开机登录后，获批交互式任务自动创建新 control/RunId，固定包/manifest/配置正确、schema6 ready、单一47841 listener；有 backup 调度回执。未手工启动来冒充自动启动。若出现自动恢复，核原始保全和独立 head 检查；失败保持文件原样。
- [ ] **手机同步**：本人使用正常聊天链路，核新消息及已保留 outbox 以原 sync_id/op_id 获 accepted 并去重，只有一个上传器；断续不能丢弃队列/跳 cursor。47862 原 remember 消费保持单一消费者；手机安装或换配置另需授权。既有手机快照不是本次设备证据。
- [ ] **claude.ai 写入**：本人从真实公网客户端作一次已授权写入，保留无正文回执和对应耐久接受证据；`waiting_for_retry`/unavailable 不算写入完成。必要重试沿用原身份/操作 ID，检查 writeback pending 完成，不能拿隧道 `/ready` 或 MCP metadata 成功代替端到端。

预计服务不可用窗口合计约 **20–50 分钟，另加真人开关机/登录和异常排查时间**；这是规划范围，不是实测承诺。准备阶段0停机。客户端健康恢复可能早于四项验收完成，但不能因此提前宣布切换完成。

## Windows 更新自动重启：登录含义与 ARSO 待验证

候选契约是“存在该用户交互式登录会话后运行”。未发生登录时不会由此 AtLogon 任务启动；它也不保证登录必须由本人在键盘完成。微软 [ARSO 说明](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/winlogon-automatic-restart-sign-on--arso-)描述更新重启后可自动登录再锁屏；[登录选项说明](https://support.microsoft.com/en-us/accessibility/windows/use-a-screen-reader-to-navigate-sign-in-options-in-windows)列出“Use my sign-in info to automatically finish setting up after an update”（更新后使用我的登录信息自动完成设置），且可能受账户策略控制。

微软 [ILogonTrigger](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nn-taskschd-ilogontrigger)按用户登录触发；[InteractiveToken](https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype)要求已有交互式会话。**据这些机制推断，ARSO 可能在本人解锁前触发该 AtLogon 任务。官方资料未对本机版本/策略与本候选组合给出可直接替代实测的证明，因此本机行为标为不确定。** 当前未查询本机开关、策略、版本或任务日志，不宣称该选项已开/已关，也不更改它。不能把“锁屏”当成“尚未登录”。

未来另获“只读查询登录选项/有效策略与日志”的授权后，记录本机版本、开关及组织策略和任务 XML；再另获明确更新重启实验窗口，由本人进行。比较系统更新重启时间、自动登录会话时间、任务启动/候选 RunId 与本人实际解锁时间，判断任务是否提前启动；记录事件时间，不收集凭据或聊天正文。若用户要求严格等本人登录才启动，先据结果提出受审方案，不能仅凭模板声称已实现；任何 ARSO设置调整或触发规则改动另行授权。普通关机→登录四项 Gate 不替代更新重启 ARSO 实验。

## 待补的精确现场值与下一轮功能缺口

- 合并后的 source commit、重新构建候选目录/manifest 外锚、最终 Core/login/backup 配置路径与 hash、新任务注册名/XML hash、control/custody/key/备份目录、U盘卷身份和镜像目标都尚未现场选定；不是用旧演练值填空。
- 当前 PID/开始时间/句柄、当前 DB/sidecar 集合与摘要、实际任务/服务设置、全部 writer/reader/消费者、当前手机队列/配置、真实客户端结果须在授权窗口重新核验。当前已有报告未证明这些值仍有效。
- 已补读主窗提供的 `PREDEPLOY_AUDIT_20261005.md`；所需旧包、原库、任务与端口均有历史定位。未取得的是**当前**现场值与合并后候选值，而非“未发现原库”或“旧包不存在”；历史手机绑定仍不替代本次真人 Gate。
- [口令备份恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)当前只提供 **inspection-only 只读还原**。从口令备份在新用户/新电脑新建现役 Core，仍缺新用户 DPAPI、新的独立 recovery key/current-head、canonical路径/配置绑定和网络/客户端 Gate 的受审转换；本轮不实现、不激活检查目录、不翻 backup 角色、不回退独立 head。Tailscale 机器私钥按本人决定不备份，换机重新登录和重配，不列作未获准读取的任务。

参考依据：[运行操作](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)、[部署手册](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)、[电脑外恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)、[历史真实恢复](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)。本清单是待授权现场步骤；所有勾选项仍未执行。
