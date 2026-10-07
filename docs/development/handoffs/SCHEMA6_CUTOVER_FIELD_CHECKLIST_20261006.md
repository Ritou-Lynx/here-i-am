## 2026-10-08 r03最新现场停点（覆盖下方历史）

实际r03冻结、144项Apply、普通正式Prepare、CREATE严格回读和获批交互式任务启动已通过；原raw加密保全、副本4→5→6及原址替换完成，head generation1，schema6 Core与同会话同字节MCP健康。**原址替换/head已提交，只向前修，不盲退v4。**

首轮自动备份worker_failed，纯固定ACL断言证实daily-backup-config.json当前继承三ACE与其严格仅本人/SYSTEM规则不符。原144之外单文件DACL修复方案待用户另批，未实施；实际stderr未保留，不承诺修复后无其他拒绝。四真人Gate暂停，**切换未完成**；MCP开库前提请求及真人关机尚未执行。详见[r03实录](SCHEMA6_R03_EXECUTION_20261008.md)。生产settings不可清理，运行47/六批准锚不变；10/09晚T9完整加密备份/真实还原仍待。

> **2026-10-07 最后一次授权更新**：r02已消费且已完整退回；新正式窗口用r03，旧锁/回执不动。所有提升产物经统一本人owner持柄读回，新的必跑Hosted真实跨token串联CI通过后，先用全新只读ID完整演练。六批准hash/固定47/父SD未变且零失败才按已有条件授权进场。截止北京时间10/09 18:00须四真人Gate齐全，否则停止；pending库存漂移/提交边界不能盲退v4。晚间20:00独立T9完整加密备份+实际恢复核对已安排，实际完成另签收。见[最后一次执行约束](SCHEMA6_LAST_ATTEMPT_20261007.md)、[工件库存](SCHEMA6_ELEVATED_ARTIFACT_INVENTORY_20261007.md)、[Prepare后16阶段表](SCHEMA6_POST_PREPARE_GATES_20261007.md)。本注覆盖下文历史入口“r02未使用”等旧状态；生产settings不可清理。
## 2026-10-07 21:29（上海）最新结果：r02 Prepare 拒绝，已完整退回

单目录 settings 已按新授权加固成功，新只读演练零失败；六项批准外锚及实时父 SD 均未变，故按有条件预授权进入正式 r02。144项 Apply 成功后，正式 Prepare 在读取 ACL 回执时因 owner 为 Administrators 而非本人，报 `prepare_owner_rejected`。没有现场改 owner 重试。已真实恢复全144项原 owner/DACL/继承，复核原 raw 身份/字节、grant/replay、旧固定包和库存，再恢复旧任务原定义/权限，按 Core→MCP 启动并绑定完整树、schema4及三个端口。21:28:57退回签收通过。

**未完成切换，暂停待审。** 新任务不存在，候选从未启动，原库未迁移/替换，head未推进；四项真人Gate未执行。r02已消费，旧锁/回执全部保留，不得复用；下一轮须新的正式ID。单 settings 获批前置保留（f88d49ec…），生产 settings **不可清理**。完整证据和下一轮源码建议见[本轮授权及实录](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。以下旧阶段的“r02未使用/零停机/尚未加固”均仅为当时历史，不覆盖本节。

## 2026-10-07 新授权：单目录前置及有条件 r02（优先于历史记录）

用户已授权先将单目录 settings DACL 执行入口/测试纳入 PR20、CI 全绿后，仅关闭继承并保留既有ACE；加固成功后新ID完整只读重演，包含模板逐字、PR16在线副本和结束全套复核。全套零失败且 manifest/XML/双SDDL/父SD/login 原批准hash全部不变，可直接按预授权用r02执行④–⑥；任何现场失败或偏差就停审，不进场。实际管理员/U盘/口令/关机及手机、claude.ai节点仍叫本人。此刻尚未执行加固或新演练。[本轮精确门槛和恢复判据](SCHEMA6_SETTINGS_ACL_AUTHORIZATION_20261007.md)。下方“禁止改ACL/需另请进场”等为旧轮历史。

## 只读演练阻断，当前不得进场（2026-10-07）

维护源码62104abd/PR20 CI15绿，但最新只读演练因获批login父task-approval…\\settings仍继承ACL拒绝，固定生产Prepare同样要求protected；该目录不在原144项计划。本轮禁止改生产ACL，补齐方案未执行。精确目录/方案hash/回退及三次回执见[演练交接](SCHEMA6_READONLY_PREFLIGHT_20261007.md)。正式r02未用，旧Core/MCP schema4、零停机。先另审此目录前置处理并完整重演通过，才可另请正式进场授权；下文为历史阶段记录。

## R02 后更新：只读演练先行（2026-10-07）

正式r02仍未使用。新维护v3入口支持独立ID的PreflightOnly；先源码/CI全绿、固定维护闭包，再完整只读演练，全部通过后另请本人授权进场。候选47项及精确XML/双SDDL无变化时沿用。在线预检继续PR16判据：DB/WAL字节/大小/身份及journal存在性不变，SHM仅存在性/大小；离线raw保全和strictClosedPath等不变。详细检查和Prepare纯模板/生产Prepare区别见[本轮交接](SCHEMA6_READONLY_PREFLIGHT_20261007.md)。生产task-approval…\settings仍不可清理。

## 2026-10-07 r02本轮实录：已授权，冻结前因系统映像Pin停止

PR18已按本人授权合入v3-lab@ea388345；全部精确XML/双SDDL/父SD/manifest/login hash已批准并重核，合并源码与获批候选47项和维护快照22项相同。用户已确认NTFS T盘。现场只读核144项ACL/16外owner、两旧任务与基线一致；conhost系统双硬链接被受审Pin拒绝，未执行r02入口、未冻结或停服，人为停机0。详见[本轮现场记录](SCHEMA6_CUTOVER_EXECUTION_20261007_R02.md)。以下“尚未批准/未合并”是旧阶段历史。

**生产配置不可清理：** `D:\HereIAmRuntime\i-core\maintenance\cutover-20261007-1552e251\task-approval-c9662439-3fb4b5c51a0f467cbd1ec3c1c18aee73\settings` 是现役候选将引用的生产配置目录，内含login/core/daily配置，绝不是临时审阅缓存。当前不得清理、移动或改名；以后换包时再迁至正式配置目录，重新绑定路径/hash并审阅XML。本轮仍未启用新候选。

## 2026-10-07 当前任务模板与批准门槛（优先于下文历史锚）

本轮用户已接受显式Unified=true和非保护任务DACL方案，仅授权源码/CI/新候选；最终精确XML/SDDL尚须本人批准，未进场。旧XML SHA 7de2a122…和旧manifest不能放行新模板。新分支源码/候选及最终审批见[任务权限修订](SCHEMA6_TASK_SECURITY_REVISION_20261007.md)。新PR不得自动合并。

在④.1之前：核新候选47项、最终XML逐字hash、注册input/继承expected两份SDDL、父SD hash/算法及其他只读主体逐项明细；本人批准这些精确字节。当前本机预览没有其他主体，不可跳过重核。任何外SID写/执行/删除/WRITE_DAC/WRITE_OWNER权限均拒绝；父SD漂移即停止，不用actual反填expected。

④.8：维护配置/owner审批v2，准备回执v3；同guard及完整pin下准备前后核父SD，实际XML必须等于新批准XML，Unified明确true。④.9：仅CREATE input SDDL，COM严格比对expected SDDL及全部定义、最终权限；注册前后再核父SD，零实例、旧任务/raw/external门槛全部保留。ACL pending仍依下文保全再审，不删除锁或编造回执。

本机四次任务创建额度已用完；本轮仅COM NewTask内存，Hosted隔离VM真实往返不构成现场注册。此前r02窗口仍未使用，旧证据原样保留。获本人最终批准并满足新合并门槛后才可进入④–⑥；没有自动停服步骤。

# schema6 候选切换现场清单（下次窗口顺序，2026-10-07复核）

## 2026-10-07 最新增补：维护源码闭合，仍未进场

用户已审核通过PR16的SHM复现、在线窄修复和既有7项CI；本轮按新授权仅版本化维护入口、合成演练并推送。**合并PR16和重新进场仍需分别另行授权**，本轮不操作现役Core/MCP/隧道/原库/计划任务/手机。下方旧脚本摘要、窗口和回执属于历史证据，不作为新入口的执行参数。

本次入口为仓库 tools/i_core/maintenance/enter-maintenance-window.ps1；计划新WindowId为 cutover-retry-20261007-r02（尚未创建现场窗口）。现场使用批准提交的完整维护闭包，按参数传入私有配置路径/SHA、WindowId。所有锁和回执进入维护根/windows/新WindowId，CreateNew留存；上次目录、锁、回执和guard字节全部保留，不删除或复用。若r02曾被使用，改用新的ID。独占active-window.guard串行化冻结/ACL/注册，后续阶段不重复进入entry。

| 对应步骤 | 本轮更新的精确执行要求 |
|---|---|
| ④.1–④.4 | 使用参数化freeze及PR16的precutover_validate_copy.mjs --config。先核维护源码闭包、固定候选完整库存、Node及配置外锚；新空copy-validation目录才可初始化私有ACL。在线判据仅DB/WAL存在/大小/身份/字节，journal存在，SHM存在/大小；不得把rawStable说成四件全字节证明。停Core后的首次闭合和65秒观察仍严格检查四件全字节及冻结身份，不套在线例外。 |
| ④.5–④.7 | 使用版本化ACL/owner wrapper及新窗口配置/SHA。原144项/16外owner锚只作历史，现场重新核精确库存和同一快照；同SID管理员、SeRestore、本窗口冻结时效、COM任务定义/SDDL/零触发/重试/实例、空端口逐项确认。全项Apply/readback、全清单恢复保持。ACL回执明确raw_external_verified=false：它不读目标内容，必须由持同guard的外层核四件/外部文件内容及身份，不能仅凭ACL passed推进。 |
| ④.8 | 使用受锚的prepare-production-login入口，绑定本轮freeze和完整ACL逐项回执；独立Prepare在共享锁下重核冻结态，固定PrepareOnly产物必须逐字等于批准XML；只有prepared未registered/started才继续。 |
| ④.9 | register-approved-login.ps1 -ConfigurationPath 私有配置 -ExpectedConfigurationSha256 配置SHA -RegisterOnly。先确认不存在，再TASK_CREATE=2；真实COM四节/SDDL/零实例回读，旧任务及raw/external注册前后再核。没有启动入口。误配输出不能落到state/raw/不存在journal，成功或失败回执均只写本轮窗口直属路径。 |
| ⑤/⑥ | 延续既有Native raw保全/替换边界和MCP曾处理请求后的真人关机→开机四Gate。维护源码合成通过不代替现场任务、批准XML、生产Prepare或人机验收。 |

**ACL Apply之后出现pending的处理：**立即停止推进，保持两旧任务及新任务的触发/重试冻结；确认所有candidate/owned writer/reader退出并保留pending、原快照、所有回执、raw密文、head。先查是否有commitStarted、原库替换、head推进或新写入；任一出现或无法排除，只能向前修。即使尚未替换，只要pending令精确144项库存漂移，也不得直接Rollback、删除新项、改144常量、删锁或启动旧v4。报告新增路径/时间/ID前缀及所处阶段，提交受审恢复方案；在精确库存和恢复能力重新闭合以前保持停写。只有确认未替换且原库存仍精确成立，才执行已审全项owner/DACL恢复并真实readback，随后恢复旧定义和Core→同字节MCP。这是显式停止/保全/再审分支，不是已实现的跨阶段自动退回。

Register合成首轮发现Scheduler会改变省略的Unified设置及DACL protected位；生产检查保留严格拒绝。固定Prepare当前模板省略Unified（官方默认false），本机同版本合成曾出现注册后true。**进场前必须复核批准XML在目标Scheduler的语义兼容性；若不符，停在预备阶段，明确审阅必要XML/模板变更，不能停机后靠放宽检查继续。** 本轮没有读取生产XML或执行生产注册，不能据显式true的安全合成任务宣称生产XML已验证。详见维护注册交接。

工作包证据：[主窗验收](SCHEMA6_MAINTENANCE_SOURCE_ACCEPTANCE_20261007.md)、[冻结/新窗口](SCHEMA6_MAINTENANCE_WINDOW_20261007.md)、[ACL](SCHEMA6_MAINTENANCE_ACL_SOURCE_20261007.md)、[RegisterOnly](SCHEMA6_MAINTENANCE_REGISTER_20261007.md)。

2026-10-06原始编写说明：本页细化[本人操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)④–⑥，供未来获准窗口逐项执行。本轮仅读取仓库历史报告、候选源码与微软官方说明并编写清单；**没有合并、部署、停启服务、查询现役、读原库/真实备份、注册任务、改设置、重启或操作手机，现役停机为 0**。

2026-10-06编写基线：`codex/core-deploy-readiness-20261006@a608f8ad1761ca2dd2989ec5b654393dce70a2b2`。该提交不是未来部署提交；本页任何历史 PID、文件摘要或快照都不是本次执行授权。

## 2026-10-07增补：本轮只修订下次顺序

本增补以合并提交 `1552e251c18c4554d425a0051ea7452e4904bb40` 的固定源码、[现场执行记录](SCHEMA6_CUTOVER_EXECUTION_20261007.md)及四个指定私有维护脚本为依据，**没有查询或操作现役进程、任务、原库、真实ACL快照或手机**。首段及下方2026-10-06历史表仍是历史记录。本增补优先于旧清单的停机及退回顺序；[复核交接](SCHEMA6_ACL_SEQUENCE_REVIEW_20261007.md)列出脚本缺口。

既有现场记录：PR14已合并并重建固定包；本人已批准现场范围、最终审阅XML与管理员预检，外SID owner合成往返已过。上次仅冻结两旧任务、停止MCP，在线副本捕获因SHM hash变化被拒后已恢复；**Core未停、144项ACL未Apply、固定Prepare/新任务注册/原库替换/生产head均未发生**。这是历史报告，不代替新窗口核验。

本轮已在固定release三次独立空闲writer捕获及三次只读SELECT中证实SHM read-mark变化，DB/WAL字节、大小及身份不变；另有两组无存活writer对照。[复现报告](SCHEMA6_SHM_REPRODUCTION_20261007.md)与[源码修复](SCHEMA6_CUTOVER_EXECUTION_20261007.md)说明新在线判据及测试。只修在线比较，不采用“先停Core再复制”；新分支草稿PR仍待审核，不进入现场。此前执行记录末尾的停机复制设想不作为本轮执行顺序。现有私有helper及回执/锁都是上一尝试的单次工件，不能原样重跑、删锁清回执或伪造frozen证明来启动新轮。

## 开始④以前必须完成

按以下顺序逐项签收，任一未完成均继续原服务，不进入停机窗口：

1. **PR #14 已获授权并合入 `v3-lab`，固定候选来自 `1552e251c18c4554d425a0051ea7452e4904bb40`；新窗口复核该提交、固定包与外锚，若候选更换则重新审核及重建。** 不把本分支旧包或合并前 hash 当最终包。固定 Node 为 24.14.1；重新核包库存、源提交、manifest 外锚、配置绑定及该提交所需检查。`prepare` 只打包已提交 Git 树，不代表部署完成。打包产物先核完整库存，再新建并保护空候选release根、逐字复制库存与manifest、重新核hash/ACL；父目录受保护不代表候选根已关闭权限继承，不能对非空目录运行Protect-NewDirectory或放宽protected_root_required。
2. 核九类保全清单、原包/配置/任务恢复资料及恢复工具；历史 52 项和 6 库检查已通过只是既有证据，不能代替切换窗口的原始 DB/WAL/SHM/journal 保全。
3. **Lynx 本人安全输入恢复口令**，使用固定工具的 SecureString 提示和一次性内存管道；不经聊天、参数、环境变量、明文文件或日志。口令由本人独立保管在电脑外；密文、口令包、认证绑定回执配套保管并验证。
4. **Lynx 插入所选 U 盘后，先核目标卷文件系统和确切卷身份，只接受 NTFS。** FAT32、exFAT 或无法确认时停止镜像准备并明确提示：“该目标不是已确认的 NTFS，当前方案不能使用；格式化会清除盘内数据，请由你决定是否格式化或改用其他 NTFS 介质。”**i 不自行格式化，也不自动转换文件系统。** 本人决定不等于已授权格式化执行；只在明确的 NTFS 镜像准备授权后建立受保护目标目录，再配置/验证镜像。仅复制认证密文、口令包和绑定回执，拒绝裸库/正文；外盘缺席保留本机成功备份并报告镜像失败，不删未知文件。
5. 准备生产配置、独立 recovery key/current-head、backup key、control 根、MCP 会话配置和登录任务 XML；生产 prepare 必须提供 MCP 配置，缺失不得生成可上线候选。MCP 使用固定同字节源码快照和现有可变 `.state`，source/state 分离；核源码依赖与 Node 的完整 inventory/hash，保护源码快照和配置外锚，不能把可变账本/token 当成固定源码重建或覆盖。release/state/control/config/custody/backup 各有明确 canonical 路径与保护权限。生产端口固定 `47841`，不沿用默认随机端口 `0`。保持 `legacy_b3` 单上传器、reply jobs/activity 关闭、owner-managed 域策略。邮件 debug 关闭，保留 SMTP 配置/DPAPI/journal，不自动重发。
6. 现场④–⑥及最终审阅XML已有明确批准；本轮只准备修订，**不启动新的现场窗口**。下次执行须重新绑定候选source/manifest、现场路径、停启对象、退回界限及批准XML；只有范围或批准字节变化才补相应审批。旧MCP停用、触发/重试冻结及同字节纳入交互式会话按既有范围；手机安装/配置、PR10上传器与47862退役仍排除。生成XML不等于注册，实际UAC与真人动作仍交本人。

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

## ④ 新窗口冻结、ACL加固与固定Prepare（预计时间须重估）

以下是下次获准窗口的顺序。既有执行范围和未变的XML批准不重复索取；重新绑定当次输入与批准字节。实际UAC提升、必要口令输入和之后真人Gate仍须Lynx本人完成，不能以旧预检回执替代这次管理员令牌。

| 顺序 | 执行动作 | 完成判据／失败退回 |
|---|---|---|
| ④.1 | 重新核授权范围、候选/维护脚本hash、本人批准XML、NTFS介质身份、九类备份/认证恢复资料、原任务定义与原ACL清单。核当前writer/reader/旁路来源，重新绑定进程树、端口、文件集合和配置。 | 上次清单144项（Core60含7目录，i_memory84含15目录；Core有16项旧SID尾号1003 owner）只是基线。任何路径、数量、owner/DACL/继承或任务定义漂移先停并补受审快照/恢复方案，**不得套用旧ACL快照**、改常量或放宽门禁。备份hash不能替代真实恢复验证。 |
| ④.2 | 暂停已获准客户端入口/消费者；同时停用旧Core和旧MCP两任务，冻结登录触发与失败重试，保存原XML/Enabled/Settings/SDDL；随后只停止当前绑定的MCP任务实例和完整树，Core继续运行。 | 两旧任务确已禁用且触发/重试为零；MCP树/实例退出，47860/47862释放，未留下read model读者或旁路来源。Cloudflare仅按原授权范围处理，不扩大到Tailscale。 |
| ④.3 | Core仍在线时，执行已复现、审核并固定hash的只读一致副本预检，校验隔离迁移及exact72/grant/外置授权等绑定。 | 使用审核通过的新维护源码/配置且固定hash，DB/WAL存在/大小/身份/字节全不变、journal存在性不变、SHM存在性及大小不变；SHM/journal内容不参与在线比较，诊断hash仍留私有回执。rawStable只代表该在线policy通过，不是四件全字节不变或Native证明。本轮已合成验证、未执行现场；新入口与冻结helper依赖/回执路径须闭合，不能直接把旧CLI或锁重跑。失败按本节退回；不进入停Core/ACL。 |
| ④.4 | 在线预检通过后才停止当前绑定旧Core任务实例及完整树；复核两任务继续冻结、47841/47860/47862释放，观察至少65秒且无respawn。用文件操作记录冻结原DB/WAL/SHM/journal存在性、hash、file_id、size、mtime，闭合在线证据与冻结原件的对应关系。 | wrapper/Node/后代、实例和端口全部退出；未打开冻结原件的SQLite句柄。状态变化不能沿用在线副本放行。frozen证明要私有、绑定本轮/候选/验证器且尚未替换；它不是NativeLease，也不是旧v4 clean-close证明。 |
| ④.5 | **Apply前最后复核**：两root全144项inventory、owner/DACL/继承快照及快照hash、文件内容hash与file_id/size/mtime；私有维护根、frozen回执/当次树和端口无漂移；同SID管理员令牌及SeRestore恢复能力仍有效。 | 已审核ACL脚本SHA256 `0abde623fdbd0685cffecc59e89a4d84893eaa1bcd112562be681e7194a373a2`，旧快照锚 `6a1dc7433969db10f68af07657935f107c9a45479b670414f55bb6b6aed7ac40` 仅在当次仍匹配时有效。普通token不能可靠恢复外SID；如恢复能力失效，保持冻结并进入受审退回，不先改owner。 |
| ④.6 | 本人实际UAC后，以核hash的维护脚本 `-Mode Apply -ConfirmFrozen` 对两个root按parent→child加固，只改owner/DACL/继承。保护全部现有目录及文件；目录只保留本人、SYSTEM、Administrators的受保护可继承ACE，使未来新文件继承受限权限。 | 不改Group、SACL或内容。逐144项readback、inventory、file_id/size/mtime不变，外部只读hash复核内容不变，树/任务/端口仍冻结；未来新文件继承不意味着其DACL自动Protected。Apply失败恢复**全部144项**，不能只恢复已写项，父DACL传播会影响尚未处理child。 |
| ④.7 | 主控复核完整Apply回执及实际状态，包含144项唯一、完整、逐项成功、正确快照/脚本/本轮frozen绑定、无rollback/privilege恢复/回执落盘错误，并重核内容和metadata。 | `passed:true`或本人看见绿色窗口均不足以单独放行。未闭合完整回执，不运行Prepare、不注册、不Start；失败执行下方退回，恢复失败则保持writers停。 |
| ④.8 | ACL放行后才调用固定release的 `prepare_login_schema6.ps1 -PrepareOnly`，核实际产出的XML逐字节等于本人批准版本，记录hash及受保护配置外锚。 | 历史批准XML锚 `7de2a122a782c509cad3a89304bce5ba88e03c607583eb62a17d9b57ee183a05` 仅在候选/配置未改且实际XML同字节时有效。结果须prepared=true、registered=false、started=false；不同即停下重新交本人审阅，不注册旧审阅工件。 |
| ④.9 | 使用经独审的RegisterOnly路径，仅CREATE获批新任务 `HereIAm-CoreSchema6-Session`，回读Actions/Principals/Triggers/Settings及任务SDDL；确认旧任务继续冻结。注册后尚不运行，所有核验完成才从获批交互式会话Start进入⑤。 | 禁止CREATE_OR_UPDATE或覆盖同名任务。已有同名任务、回读不符、真实COM未核验均停；注册草稿的mock检查不是现场证明。不得先直接启动新Core再补注册。 |

### 替换前退回：先停写，再真实恢复权限，最后恢复旧运行链

1. 先核 `commitStarted`、原库replacement、生产head和新Core写入证据。任一出现，或无法排除，即转**保全并向前修复**，不恢复旧ACL后盲启旧v4、不降旧库、不删pending/latch。
2. 确认新candidate、获批新任务及其owned进程全部不再写入；若尚未注册/从未启动，用当次证据写明。保持旧两任务禁用、无触发/重试，三个端口空闲；已注册的新任务也须冻结，不能留下未来登录重启来源。仅“任务已停”或端口空不等于完整树退出。
3. 若ACL Apply曾开始（包括返回失败），以**同SID管理员且SeRestore可用**、核同一脚本hash、原快照和精确inventory后运行 `acl-cutover-maintenance.ps1 -Mode Rollback -ConfirmFrozen`；实际恢复全144项owner/DACL/继承并逐项readback，核rollback成功且file_id/size/mtime及文件hash安全。不以hash相同代替真正恢复；不称Group/SACL完整恢复。Apply内置自动restore也必须检查全144项restore及readback，失败不能当已恢复。
4. 任一库存、权限、内容、metadata或恢复能力核验失败，保持writers停、保留私有回执并报告精确原因，先补受审恢复方案。固定Start可能在replacement前创建pending等新项；此时硬钉144的Rollback会拒绝，**不得删新增项/pending、改144常量或忽略inventory_drift绕过**。
5. 只有恢复readback、原包完整hash、原库/sidecars原身份及schema4兼容边界全部可信后，按保全的原XML恢复两旧任务定义、触发、失败重试、Enabled及SDDL；先恢复旧Core并核schema4/单一树/47841，再恢复同字节旧MCP并核47860/47862与metadata健康。必要隧道仍按原范围。对已存活的精确旧Core只验证，不另启实例。
6. 逐项复核原Actions/Principals/Triggers/Settings及SDDL、任务实例/进程/端口和健康。未闭合就写“退回未完成”，保持无法确认安全的writers停；不凭网页可访问或摘要匹配声称恢复。

若在④.3即拒绝、Core仍运行且ACL从未Apply，记录“ACL未触及，无需恢复权限”，沿已审核冻结阶段回退分支恢复原任务和同字节MCP；不为执行上面Rollback而额外停Core。旧 `freeze-legacy-runtime.ps1` 内置退回只覆盖其冻结阶段catch，**不是ACL后的一键恢复入口**。新的全流程执行入口未闭合前，本节为可审核操作次序，不能声称已经实现自动退回。

## ⑤ 固定Start内的原raw保全、副本迁移与接管（预估 5–15 分钟）

| 顺序 | 执行动作 | 完成判据／失败退回 |
|---|---|---|
| ⑤.1 | ④.9注册及回读完成后，从获批交互式会话启动固定Start/adoption。固定实现先取得真实Native离线租约，在任何原库SQLite打开前流式加密保存原DB/WAL/SHM/journal并认证验证；再在隔离副本恢复已提交WAL及迁移4→5→6。在线副本及ACL/frozen回执均不能代替此处NativeLease/raw门禁。 | integrity 通过，node_id/设备/旧表消息身份与序号、grant、exact72 replay、配置绑定均匹配；单上传器/关闭策略保持。失败保留副本/密文与无正文回执；原件未替换且commitStarted/head/新写入均未出现时，按④的退回步骤及inventory限制判断，不能自动重启旧v4。 |
| ⑤.2 | checkpoint/关闭副本，再作 immutable 验证；核准备期间原 DB/sidecar 摘要不变、独立 custody/current-head 绑定正确。 | 所有检查通过才允许提交；缺失独立 authority 不从目标历史自签既有5/6 floor。不使用 InitializeEmpty 打开旧库，不激活 backup_read_only 副本。 |
| ⑤.3 | 进入短提交区：以固定实现保存 pending 证据，将原 sidecar 移入受保护暂存区，合并单库替换原 canonical 路径，推进独立 head。 | 提交回执闭合且没有未解决 pending。多文件/目录步骤不是同一个 SQLite 事务；**commitStarted、原库替换、推进head或新Core接受写入任一出现，就只向前修复；不能先恢复旧ACL再以旧v4/旧DB盲退。** 中断保持相关 writer 停止，保全新文件、raw 密文、head 和回执，向前修复；不删 latch/pending。 |
| ⑤.4 | 核已由④.9获批交互式任务调用的固定入口 `lifecycle/start_schema6.ps1 -Start`、外锚、原state、受保护配置、新空control和 `CorePort=47841`；记录RunId/ManifestSha256/ControlDirectory，不另开第二实例。 | `/v1/core/health` 显示真实 schema6、身份/设备/授权边界正确；只有预期进程监听。未 ready 按失败回执排查，不开旧 v4抢占，不通过删除锁绕过启动门控。 |

## ⑥ 客户端与交互式登录任务，立即真人关机验收（预估 10–20 分钟另加开关机时间）

| 顺序 | 执行动作 | 完成判据／失败退回 |
|---|---|---|
| ⑥.1 | 确认⑤已从④.9获批交互式任务进入；由新交互式会话在 Core ready 后启动已批准的 MCP 固定同字节源码快照，显式绑定现有 `.state`；必要隧道按范围恢复（Core→MCP→隧道），不恢复旧独立 MCP 任务；核新 Core 只有 `legacy_b3` 上传器，reply jobs/activity 关闭，邮件 debug 返回 `shortcut_mail_disabled`，不重发在途邮件。 | MCP 47860/47862、OAuth/401 边界和 Cloudflare `/ready` 按范围恢复。旧 MCP session 404 时重新 initialize，不据此重签凭据。captures 未通过仍用47862单消费者。 |
| ⑥.2 | 复核④.8–④.9已完成固定 `PrepareOnly`、批准XML逐字匹配及仅CREATE注册的回执，不重复注册；核 owner SID、AtLogon、InteractiveToken、LeastPrivilege、IgnoreNew、隐藏窗口、固定 manifest 与 launcher config 外锚、47841。沿用本人批准的精确任务名，旧启动来源继续冻结，避免双任务。 | 回读注册内容匹配已审 XML，任务不存用户密码、不设 SYSTEM/开机无人登录启动。新任务名、最终 XML/配置 hash 写现场回执。准备工具仅 `registered:false/started:false` 不代表任务已装。 |
| ⑥.3 | 复核获批任务已进入交互式launcher，真正挂上关机窗口和每日备份。每次启动使用新空control；发现直接supervisor旁路时停止验收，按精确候选的认证清停及受审接管方案处理。 | 候选由实际登录 launcher/任务接管且仅一实例，backup/MCP 配置及源码库存已绑定，MCP 由同一会话拥有的 Job/进程树管理；备份默认24小时/保留30天、NTFS镜像结果单列。不得直接对一个没有 launcher 的进程做关机 Gate 后宣称任务链通过。 |
| ⑥.4 | **先从 MCP 成功执行一次已授权的 `i_recall` 或 `i_chat_turn`，确认真实 read model 已打开 Core，再立即由 Lynx 正常关机 → 开机 → 登录。** 只访问 metadata/health 不满足已开库前提；保留成功调用的无正文回执。 i 不替本人点击关机，不通过合成 WM 消息替代真人动作。保留本次前后 RunId/control/时间线和精确候选哈希。 | 下列四项全部通过才写“切换完成”。任一失败保留候选/现场回执并写“未完成”；原件已替换则向前处理，不自动降回旧 v4。 |

四项必须全部签收：

- [ ] **正常关机阶段回执与 Core clean-close**：在同一个 **30 秒总预算**内停止备份派发，先确认会话拥有的 MCP Job/完整进程树退出和 owned tree 句柄释放，再结束活动备份 Job，最后请求 Core close。MCP 阶段须保留等待、退出方式、Job 空和句柄释放回执；Windows `CREATE_NO_WINDOW` 下不能依赖可靠投递 SIGTERM，当前方案只给不超过3000毫秒的有限 grace，必要时 force owned MCP Job。发生 force 必须明确记为 MCP 强制退出，不能写成 MCP graceful。随后 Core listener/store 关闭、Core child exit0、guardian exit0、Core Job 空、Core 无强杀、marker `clean_closed`、锁实际释放全部成立；MCP 的允许 force 不放宽这些 Core 清停判据。三个阶段共用30秒，不各领30秒。`stop_requested`、端口消失或仅任务停止不是完成；系统仍可能强终止。Core 超时进入 recovery_required，即使下次恢复成功也不能把本项改称 Core clean-close 通过。
- [ ] **自动启动**：本人开机登录后，获批交互式任务自动创建新 control/RunId，固定包/manifest/配置正确、schema6 ready、单一47841 listener；有 backup 调度回执；Core ready 后会话自动启动 MCP，47860/47862 绑定正确，并从 MCP 再成功执行一次已授权的 `i_recall` 或 `i_chat_turn`，证明新登录后的 read model/客户端链路可用。未手工启动来冒充自动启动。若出现自动恢复，核原始保全和独立 head 检查；失败先关闭会话拥有的 MCP 树并确认句柄释放，再按恢复门禁处理，文件原样保留；未管理的工具/脚本仍须排空/暂停。
- [ ] **手机同步**：本人使用正常聊天链路，核新消息及已保留 outbox 以原 sync_id/op_id 获 accepted 并去重，只有一个上传器；断续不能丢弃队列/跳 cursor。47862 原 remember 消费保持单一消费者；手机安装或换配置另需授权。既有手机快照不是本次设备证据。
- [ ] **claude.ai 写入**：本人从真实公网客户端作一次已授权写入，保留无正文回执和对应耐久接受证据；`waiting_for_retry`/unavailable 不算写入完成。必要重试沿用原身份/操作 ID，检查 writeback pending 完成，不能拿隧道 `/ready` 或 MCP metadata 成功代替端到端。

原2026-10-06预估服务不可用窗口约 **20–50分钟，另加真人开关机/登录和异常排查时间**。新增ACL逐项签收、恢复及65秒观察后，下次窗口须重新估算；旧区间不是实测承诺。本轮文档准备0停机。客户端健康恢复可能早于四项验收完成，但不能因此提前宣布切换完成。

## Windows 更新自动重启：登录含义与 ARSO 待验证

候选契约是“存在该用户交互式登录会话后运行”。未发生登录时不会由此 AtLogon 任务启动；它也不保证登录必须由本人在键盘完成。微软 [ARSO 说明](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/component-updates/winlogon-automatic-restart-sign-on--arso-)描述更新重启后可自动登录再锁屏；[登录选项说明](https://support.microsoft.com/en-us/accessibility/windows/use-a-screen-reader-to-navigate-sign-in-options-in-windows)列出“Use my sign-in info to automatically finish setting up after an update”（更新后使用我的登录信息自动完成设置），且可能受账户策略控制。

微软 [ILogonTrigger](https://learn.microsoft.com/en-us/windows/win32/api/taskschd/nn-taskschd-ilogontrigger)按用户登录触发；[InteractiveToken](https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype)要求已有交互式会话。**据这些机制推断，ARSO 可能在本人解锁前触发该 AtLogon 任务。官方资料未对本机版本/策略与本候选组合给出可直接替代实测的证明，因此本机行为标为不确定。** 当前未查询本机开关、策略、版本或任务日志，不宣称该选项已开/已关，也不更改它。不能把“锁屏”当成“尚未登录”。

未来另获“只读查询登录选项/有效策略与日志”的授权后，记录本机版本、开关及组织策略和任务 XML；再另获明确更新重启实验窗口，由本人进行。比较系统更新重启时间、自动登录会话时间、任务启动/候选 RunId 与本人实际解锁时间，判断任务是否提前启动；记录事件时间，不收集凭据或聊天正文。若用户要求严格等本人登录才启动，先据结果提出受审方案，不能仅凭模板声称已实现；任何 ARSO设置调整或触发规则改动另行授权。普通关机→登录四项 Gate 不替代更新重启 ARSO 实验。

## 待补的精确现场值与下一轮功能缺口

- 2026-10-07已在执行记录绑定合并提交、候选/manifest、配置、批准XML/任务名及NTFS备份目标；新窗口须逐项重核，不把历史批准工件等同于本轮已固定Prepare、已注册或已启动。
- 当前 PID/开始时间/句柄、当前 DB/sidecar 集合与摘要、实际任务/服务设置、全部 writer/reader/消费者、当前手机队列/配置、真实客户端结果须在授权窗口重新核验。当前已有报告未证明这些值仍有效。
- 已补读主窗提供的 `PREDEPLOY_AUDIT_20261005.md`；所需旧包、原库、任务与端口均有历史定位。新窗口待重核的是**当前**现场值及已生成候选的绑定，而非“未发现原库”或“旧包不存在”；历史手机绑定仍不替代本次真人 Gate。
- [口令备份恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)当前只提供 **inspection-only 只读还原**。从口令备份在新用户/新电脑新建现役 Core，仍缺新用户 DPAPI、新的独立 recovery key/current-head、canonical路径/配置绑定和网络/客户端 Gate 的受审转换；本轮不实现、不激活检查目录、不翻 backup 角色、不回退独立 head。Tailscale 机器私钥按本人决定不备份，换机重新登录和重配，不列作未获准读取的任务。

MCP 同字节快照的 server 必须保持 `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6`；不改旧 CLI 程序字节。生命周期依据见[只读源码审计](SCHEMA6_MCP_READER_AUDIT_20261006.md)，候选实测与精确回执统一由主窗填写[本轮 MCP 会话验收](SCHEMA6_MCP_SESSION_ACCEPTANCE_20261006.md)。本页的新增顺序是部署计划，不能当作现场已执行或新 CI 已通过的证据。

参考依据：[运行操作](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)、[部署手册](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)、[电脑外恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)、[历史真实恢复](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)。本清单是下一窗口操作顺序；本轮仅修订文档，ACL Apply与四项真人Gate均未执行。
