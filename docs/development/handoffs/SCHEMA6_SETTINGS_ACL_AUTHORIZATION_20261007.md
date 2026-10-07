# 生产 settings 单目录 ACL 前置与有条件切换（2026-10-07）

## 本轮授权与当前状态

用户已明确授权额外的单目录 DACL 加固，先把真实执行入口和合成测试纳入 PR20、精确源码 CI 全绿，才可执行。源码已随 PR20 经CI通过，单目录加固和新只读重演均成功。按条件预授权进入r02后，正式Prepare因管理员生成的ACL回执owner不符拒绝；已完成全144项真实权限恢复和旧运行链恢复，暂停待审。下面初始计划保留，真实实录见末节。

唯一现役目标：

D:\HereIAmRuntime\i-core\maintenance\cutover-20261007-1552e251\task-approval-c9662439-3fb4b5c51a0f467cbd1ec3c1c18aee73\settings

这是生产配置目录，**不可清理、移动、改名**。本次仅关闭继承并保留所有既有 ACE 为显式规则，不改 owner/group/SACL、三份配置字节和子权限，不触原库、任务、服务。它不属于原 state/i_memory 的144项，不能悄悄扩大该清单。

| 外锚 | SHA256 |
|---|---|
| 原私有方案 | 11374854974b5994adc18e1afa35cf95eea56d57f074350db9f95c8017bf250d |
| 原目录 SDDL | 5533f773840e001c189ee3a054eaee09ec6d301fe3f8eb757b3cd582a2bd5de4 |
| 拟议目录 SDDL | f88d49ec29c276b95fcc0040af2fa319251d10f063a79c0699d54c9f667a6e25 |
| core.json | cc5f8a42f31a18b72d8dba28559d1a4a01300ea875e117d61e9928deb9f4722c |
| daily-backup-config.json | d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5 |
| login.json | 28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00 |

真实 SID、完整 SDDL 和配置内容只保留在私有方案及受保护回执，不入仓库。

## 执行及成功/恢复判据

执行入口为 `tools/i_core/maintenance/protect-approved-settings.ps1`。源码必须先经合成测试、独立复核及 PR20 CI，再从精确提交固定新的维护快照；不执行可变 checkout。参数给出原方案路径及其批准 SHA、全新回执目录与显式 Execute。不得复用旧锁、旧成功回执或原三个失败演练 ID。

执行前核方案、当前 owner、原完整 SDDL、恰好三份直接文件、plain 路径和实际句柄身份、单硬链接及各自 hash；从当前 ACL 在内存重算 SetAccessRuleProtection(true,true)，必须逐字等于原拟议 SDDL。先将原 ACL 和四项身份持久保存至新的受保护回执，再写目标目录的 DACL。仅请求 READ_CONTROL/WRITE_DAC，不请求 WRITE_OWNER，也不启用恢复权限或自行提权。

入口使用已有 Windows 文件系统 API SetFileSecurityW，只设置 DACL/保护位；微软明确说明目录安全变更不会传播给子项。该 API 已标记 obsolete，仍列有 Windows 支持；在本次严格“单目录、不写 child ACL”的窄维护场景保留它，以实际 Native 合成往返和子 SDDL 逐字核验约束。路径调用期间持目标及全部祖先 no-delete 句柄，前后核同一原句柄身份。没有使用不适用于文件系统的 SetKernelObjectSecurity，也不采用普通 SetSecurityInfo 的默认继承传播。[微软 SetFileSecurityW](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-setfilesecurityw)、[SetSecurityInfo](https://learn.microsoft.com/en-us/windows/win32/api/aclapi/nf-aclapi-setsecurityinfo)。

成功须目录 protected、owner/group 和既有权限不变、实际 SDDL 等于原拟议、三个文件 ACL/身份/hash 不变，原 DACL 及终态回执已耐久落盘。失败如已开始 DACL 写入，就恢复原目录 DACL并核四项原 ACL/身份及三文件 hash；恢复不能闭合则明确失败，不能记录成功。此入口没有启停服务、注册任务或 SQLite 动作；如实际需要管理员权限，由主窗叫本人。

## 新只读演练与正式 r02 门槛

加固成功后，使用新的只读 ID 完整执行 v3 PreflightOnly：候选47项、USB/九类备份与已有真实还原、旧任务/完整进程树/端口、144项 ACL/16旧 owner、XML/双 SDDL/父 SD 和 COM 内存兼容、固定 Prepare 纯模板逐字输出、PR16 在线副本及隔离校验、结束全套复核。在线仅忽略 SHM 内容；DB/WAL 字节/大小/身份、journal 存在性、SHM 存在性/大小仍严格，离线 raw/strictClosedPath/NativeLease 不变。

用户已给**有条件预授权**：全套演练零失败且下列批准外锚全部不变，才可直接用未消费的 cutover-retry-20261007-r02 执行已批准④–⑥。旧文档“另请授权”保留为历史，不覆盖本次明确预授权。出现任何现场失败、偏差或需要修改批准内容，停下交审核，不进入正式现场。

| 必须不变的批准工件 | SHA256 |
|---|---|
| 候选 manifest | 3b7e210b21a7626041680fb9e41615dd06ef5df7d818997e347dfab170147fa0 |
| 最终 XML | 4bc643571073b726fad4cc781785129a27a6c9b4a669ef9df1a621c5cebb397e |
| 注册输入 SDDL 文件 | 50398e9fe2ff2b2cbf62ee4ed31b703ddc21aff6339a0595963e2cb859915feb |
| 继承预期 SDDL 文件 | 9d1a0c172a55d1ac6ee5a8a831793abde4cd6b7252258329688283f3bc593580 |
| 父 SD 文件 | 330eb3abb433de72e6efae43075cd7440976dae310f7d55da2717626b38b880d |
| login.json | 28c5b700b98815b57b57e4cc9430f16ee8ef5ba8bdc3a1a08f854873965e1e00 |

本轮新增维护入口在固定47运行文件之外；Core/MCP/会话启动器及候选库存没有因此改字节，不重新标记 manifest 的来源提交。口令、U盘确认、实际管理员操作、关机→开机及手机/claude.ai 真人步骤继续叫本人。正式前段失败按既定退回；原库替换、head推进或新写入开始后只向前修。

手机安装/改配置、PR10启用、47862退役、MCP程序更换均不在授权内。B线PR19已独立完成源码并暂停，不进入本轮固定包。

## 源码复核及本机验证（进场前证据）

两项独立复核问题已修：不适用的 kernel-object API 换为上述文件 API；失败时未证实的 owner/child ACL/字节状态记 null，完整最终或恢复复核通过才记不变。原 original.json 耐久写入后立即保持只读、拒写/删句柄并重核 SHA，到 finally 才释放。合成专测2/2、37断言通过：成功、拒绝条件、真实 rollback、rollback API失败、child ACL漂移、原恢复材料写失败零mutation、成功回执写失败实际rollback、根rename拒绝、硬链接拒绝或检测、恢复材料写拒绝。主窗整组与CI在完成后追加。

同 owner 的 ACL 并发变更不可能由数据共享句柄完全排他，采用漂移检测/恢复/停审；不宣称绝对阻止 hardlink 创建。现场签收必须同时满足进程退出0、最终返回 passed、完整 result.json 逐字段一致、没有 failure.json，及独立 owner/SDDL/三配置 hash/ACL复核。写回执失败可能留下不完整 result 文件，单看它不能放行。旧方案/原DACL/所有失败证据保留。

主窗维护整组54项：52通过、0失败、2特权opt-in未执行，41.733秒；新入口2项和37原生断言均实际执行。两项opt-in由既有Hosted Windows门禁强制执行，CI未全绿前不加固。

## 精确源码及 CI 已先通过

源码 `dd39129c04d37e4670214289d819a020a2f04c44`（PR20），两次完整CI及policy共15项全绿，随后才执行现场动作。push [37621421832](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37621421832)、PR [37621426478](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37621426478)、policy [37621423631](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37621423631)。两次Hosted维护各54/54、完整Windows各285/285，均0失败、0跳过；本机维护52过、2特权opt-in未跑，不拿它代替Hosted特权证据。

从该提交固定25项完整维护闭包，manifest SHA256 `1ec4817b3a1a199a5587c9e716d5e7cacac76f19fb264b32ef581499d885e2f9`；Git原始LF版settings执行入口 SHA256 `ce0aecbeb89f6ff517304ef182c3cef677d4eb0fe298f8712b8b12a6447540df`。维护快照与固定47项runtime分开，全部47项实际hash/size和46个Git源码blob均相同；未重建、未改变Core/MCP/会话启动器字节或获批XML/SDDL/login。

## 单目录真实加固：通过

新回执位于私有 `rehearsal-inputs-dd39129c-d4becd66c1b8/settings-acl-d4becd66c1b8/`。普通本人token已有目录WRITE_DAC，故该单目录动作没有请求UAC。执行入口进程exit0、最终passed、result.json逐字段一致，无failure.json，并独立复核：

- 根目录protected、实际完整SDDL SHA256严格等于f88d49ec…；owner不变。
- 恰好三文件单硬链接/实际身份/hash/子DACL均不变，原DACL先耐久保存并持续持柄。
- original.json SHA256 `0134a47a0dae1560a668f84d1e1397a02b5326dc74591e1c4ae01dc419b44b69`；result.json SHA256 `8b5997756ff3355eedf41c5293497cf176f9b22a6d43218adac39260033ad015`。
- 无服务/任务/原库动作。此项独立获批前置在后来r02退回后保留；最终再次核SDDL=f88d49ec…、login=28c5b700…，不属于144项回滚范围。

## 新只读演练：全套通过

ID `readonly-20261007-d4becd66c1b8`，100711ms，exit0、passed，结束全套复核完成；回执SHA256 `c8c351dd4bf5616e854557647baa74dd6e86bca55f5f8bddd7b1caeff7b4d21e`。

候选47项、NTFS USB身份/九类备份及已有真实还原、旧任务/完整进程树（含系统conhost）/端口、144项ACL/16旧owner、XML/双SDDL/实际父SD和本机COM内存兼容均通过。固定Prepare纯模板逐字相同，`productionPrepareInvoked=false`、`productionPrepareStillRequiresAclApply=true`，没有把纯模板证明当真实Prepare。PR16在线副本及隔离4→5→6校验通过：72条replay绑定、1个grant保留；validation receipt SHA256 `f65c2b491957baa78e985521431b5e412e30882616aa3e66c0512c049e33fdc1`。旧任务/进程树结束复核未变，liveMutationPerformed=false、formalEntryConsumed=false。旧三个失败只读ID及证据均保留。

随后六批准hash及实时Scheduler父SD再次重核一致，settings protected，正式r02尚未使用，满足本人有条件预授权。本人明确答复“在电脑前，现在继续”；后续管理员答复曾误选，主窗只读查实际成功回执并暂停确认，本人再明确“最后一条误选，继续切换”。没有把未答复当授权。

## 正式 r02：Prepare拒绝，未启动候选

正式窗口 `cutover-retry-20261007-r02` 于21:13:47（以下均上海时间）进入，完整重复修改前预检，通过后冻结两旧任务/触发/重试。先停MCP，PR16在线副本通过，再停Core；原四件全字节/身份关闭后严格核验，连续观察69525ms无重启。21:16:22生成30分钟冻结回执：

| 证据 | SHA256 |
|---|---|
| formal freeze config | cf6b85db0820e8fc48c1fb30baed547455ad50f3dc59ec51b8a5e397e2adeaa5 |
| frozen-legacy-runtime-ready.json | b1dccd26f0163ac8a45a2c7bb3e9c2344013042fa0e0dc7da1995d7447b45f64 |
| formal ACL config | 7e76ba351074139672c47e134d1d1b74c653712e6b1ee36fced213b56f6f8b35 |
| acl-apply.json | eba07c8035ec4000ccc9157fcd5ab42d98d3708529a8040de7dc66e4ab5df632 |
| formal login config | 93c51b392d217dd5978c74c7ad5fcea0cbf95c8d814d3ede23fd130b08299621 |

本人处理真实UAC，同SIDPS5.1只持柄pin/import受审owner wrapper并显式调用；不是直接-File空跑。Apply 21:17:31–21:17:49，提升进程exit0、受审wrapper passed；144项各baseline/apply/readback共432条、16旧owner归正，独立读取所有实际owner/DACL、原raw身份/hash、grant/replay、冻结任务/空端口均通过。主窗独立复核曾误写audit动作名及假设external有path字段，修为真实baseline_comparison、从锚定freeze config取外部路径后重新只读核全套通过；这两次检查器错误没有任何生产mutation，未重做Apply或放宽检查。

正式 `prepare-production-login.ps1` exit2，固定错误码 `prepare_owner_rejected`。没有生成prepared XML、Prepare成功回执或registration receipt；新任务从未注册/启动。主窗按失败规则停止，没有临场改owner后重试。

**根因已独立只读确认：** 31个Prepare相关路径只有 `r02/acl-apply.json` owner不符，实际为内置Administrators，当前本人SID与配置owner一致。源头 `acl-cutover-maintenance.ps1` 在提升进程以普通CreateNew写回执，未显式设owner；`prepare-production-login.ps1` pin ACL回执调用 `prepare_live_guard.ps1`，后者正确拒绝非本人owner。这次拒绝早于实际fixed Prepare调用，该控制流没有state/pending/commit/head写入。不能把Apply功能成功当后续消费回执已兼容。

## 真实退回：权限、原件、任务、运行链均闭合

保持旧writers冻结，以全新Rollback参数/回执执行同源受审wrapper，本人再次处理真实UAC。全过程未注册新任务、未调用固定Start/adoption；在恢复旧服务之前核144精确库存、原raw存在性/单链接/身份/size/hash、外部grant/replay、原包9库存文件+manifest以及launcher/node/source外锚，确认没有替换/提交/head/newwrite边界。

| 退回证据 | SHA256 |
|---|---|
| formal rollback config | 9597cd630c444f016792da45bcb22c31994fb4ccd427e7b3f258788a05c4d8cd |
| acl-rollback.json | fb200c613ea25c5c2288dba07ddc2746bb9b059d46dbb2c99624e25ef87ae29a |
| rollback-prestart-verification.json | 2fde3aa0422fae1818671366ad8812c67fe9e1df0398cb9c843d6a4786abdad1 |
| legacy-task-definitions-restored.json | fab6da7d524506349d0e52334752d2cea54efeb856f8ddbfbe4e06c0fba1d33c |
| legacy-runtime-restored.json | b0526dee1ab317576ce545fc1704630c59ba79b442438caacf7b710a467321d0 |

Rollback提升进程exit0、passed、rollback_verified=true，144项实际恢复/readback，432行含baseline/restore/restore_readback；独立逐项与原owner/DACL/保护继承比较一致。没有声称恢复Group/SACL（本次也未更改）。

按受审freeze退回模式COM flags60先恢复两原定义为禁用，使用受审Task primitives严格回读四段/原SDDL、零实例。之后依Core→MCP分别Enabled/Run；实际完整PID/创建时间/映像路径/hash树分别3和4进程，任务各1实例，Core schema4、47841归原Core，47860/47862归同一旧MCP，OAuth metadata200；两任务原Actions/Principals/Triggers/Settings和SDDL恢复。21:28:57签收完成，新schema6任务不存在。没有启动第二实例或更换MCP程序。

21:31:20由独立worker再次只读签收：原XML四段/SDDL均相同，两旧任务Enabled/Running各1实例，完整树分别3/4项，映像路径/hash/PID创建时间通过，三个端口仅127.0.0.1监听，Core schema4，新schema6任务经包含隐藏任务的枚举确认不存在。这不代替手机同步或公网真实写入验收。

MCP原进程停止完成21:14:54，旧MCP新进程创建21:28:50（约13分57秒进程间隔）；Core原进程停止完成21:15:12，旧Core新进程创建21:28:42（约13分29秒）。这些为进程间隔，最后整体metadata/完整树签收21:28:57，不宣称精确外部请求不可用时长。恢复后旧服务允许按原逻辑正常写库；“raw不变”证明指恢复启动前，不声称在线库此后仍冻结。

## 当前边界及下一轮待审（本轮不修）

- **本轮未切换，已退回旧schema4运行链，暂停待审。** 未改手机、PR10开关、47862桥、隧道、调试邮件/新登录生产配置；新Core未部署，四项关机/登录/手机/claude.ai真人Gate未执行。
- 单settings获批前置保留；144项返回旧owner/DACL；旧Core/MCP任务原定义/触发/重试/权限/Enabled恢复。U盘和全部旧新回执、锁、snapshot保留，生产settings不可清理。
- r02已消费，不得删锁/回执后复用。下一轮须新正式ID及新的完整只读演练，不将本次新演练绿灯跨现场状态继承。
- 建议下一轮只在受审ACL回执writer中，于输出任何JSON字节前显式将新文件owner固定为config.ownerSid（持新文件句柄）；重核实际owner/允许ACE/身份再写入并Flush，失败仍拒绝。Apply和Rollback均覆盖。**不放宽Prepare的本人owner检查，不现场修旧证据owner，不变更Core/MCP/runtime库存。**
- 必补Windows真实ACL writer→非提升Prepare消费者的串联测试，覆盖提升默认owner为Administrators、正确同owner成功、错误owner仍拒绝、回执owner固定失败/写失败不能放行；不能仅用手工构造的合格fixture代替实际writer。受审源码/CI、完整维护快照和新演练通过后再交审核决定后续进场，当前未实施。
- B独立PR19 `cf2f6d57d58626a7cbf03904625c809e0f034842` 源码完成且此前三套CI核绿，暂停待审；16项未来运行变化不进入A固定47候选，本轮无B代码/部署动作。
