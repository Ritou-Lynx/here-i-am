# PR14 自动运行、口令备份与 CI 续作｜主窗验收（2026-10-06）

仅继续 `codex/core-deploy-readiness-20261006` 与同一草稿 [PR #14](https://github.com/Ritou-Lynx/here-i-am/pull/14)；base 为 `v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`。**此前 beed 源主窗整组和精确固定候选烟测已通过，1060 源两次真实跨 Windows 用户合成恢复也通过；收口发现生产备份输入编码缺陷，当前最小修复后必须重建固定候选并重新整组验收。** 最终交付提交的全部远端检查以同一 PR Checks 与正文回执登记，确认全绿后暂停审核。 验收完成后只推此分支、更新同一 PR、暂停等审核，不合并、不部署。

本轮所有运行证据来自合成环境。未读取/停启现役 Core、MCP、隧道，未打开原库，未改现役配置/计划任务，未操作手机；未实际关机/注销电脑，未注册登录任务、未在本机创建 Windows 用户。临时 CI 标准用户演练仅在一次性 hosted runner 上运行并清理。前轮九类 52 文件真实备份/恢复已由用户审核通过，本轮保留原证据，未重新访问或解密那些数据。

## 实现与主窗独立复核

| 工作包 | 结果与复核重点 | 工作包交接 |
|---|---|---|
| CI、登录与关机 | 规范合成 TEMP/独立 Node，CI-only 默认 owner；隐藏 HWND，认证 close、真实 Job/锁回执，新 control；备份失败隔离 | [CI](SCHEMA6_CI_REPAIR_20261006.md)、[会话](SCHEMA6_SESSION_LIFECYCLE_20261006.md) |
| 自动恢复与旧 v4 | 首次 SQLite 打开前四文件流式加密；副本回放/4→5→6；真实 native lease；独立 custody 与完整领域结果认证 | [恢复](SCHEMA6_AUTOMATIC_RECOVERY_20261006.md) |
| 电脑外备份 | scrypt/AES-GCM 口令包，原 DPAPI 不可用时真实只读恢复；每天/30天，可配置密文镜像，断开后补复制 | [备份](SCHEMA6_PORTABLE_AUTOBACKUP_20261006.md) |

工作包原提交：CI `99147eb11051e819ccd0cf6e21fe8b5f14416a74`；portable `50b891c0762bac2b03f2a85b59f7620e73aceb52`；恢复 `199f7d38`、`06a6a6c3aa9ba09658fce3a90177407404c2e86f`；会话 `ebff9556`、`28ae524b2b5f8e5de1064c0ed56719379a16459c`、`4b0e95824038fa40bbedf10d11fff3c348a17e01`。主窗固定已提交源码为 `beed93a3657ab59fbe033a435f471814d8895736`，后续文档收口不改该固定库存的字节。

主窗及独立只读复核发现并要求修复：残留 wx custody 锁会阻断后续启动；坏 JSON 异常可带出秘密；合法 re-pair 不应误报回退；仅 MAX/revision/裸 accepted metadata 不能证明正文前进；副本检查上下文不能取代生产 head；备份启动/worker 故障不应关闭健康 Core；hash 前必须持有拒写/拒删除句柄；原子 rename 发布者仍持 DELETE 句柄时旧控制读取会 error32。最后限定源码复核未发现新的明确缺陷，最终运行结果仍由主窗下表负责。

领域内部认证绑定完整目标行、namespace/domain/principal/op_id/request_digest/result；生产另核原 receipt_auth，公开 receipt 与 schema 列未改变。真实编辑、删除、purge/retention 仍可前进；未证明的旧候选未封存前进拒绝，需要向前核验，不用新的更大 MAX 掩盖旧历史回退。独立 current-head 不从备份重建；activity 仍关闭，未来活动保留历史裁剪不是本轮已验范围。

## CI 失败与修复证据

旧两次 Windows 为 96 tests / 89 fail：实际 8.3 TEMP `RUNNER~1` 与 elevated 默认 owner 令严格生产检查拒绝。仅夹具规范真实长路径、独立固定 Node copy；CI 测试进程修改自己的默认 owner 并 finally 恢复。生产 plainPath、ACL、reparse/hardlink 门控没有放宽。

白板唯一失败用例是 `compact_card_editor_test.dart` 的空标题/H1 保存：原测试固定等待 600ms 后就看关闭状态。改为实际 save Completer 屏障，验证阻塞时不关闭、释放后等待真正回执、重新打开 DB 检查标题/H1。主窗精确 5/5；worker 相邻 canvas 195/195。没有 skip、重试或改产品保存逻辑。

CI-only 已推 head `45bcab16a98c147efe4f05669dd92f1cb4728772` 的其他 9 checks 全过，两次 Schema6 Windows 则各为 99 tests / 92 pass / 2 fail / 5 cancel：路径/owner 错误全部消失，两项真实启动变为 `ETIMEDOUT`。输出未区分具体哪个 native probe，不冒称已精确定位到某一调用。测试文件原本并发启动多个 ACL/DPAPI/Job 子进程树，现将 Windows runner 改为 `--test-concurrency=1`，所有原测试、reporter 和退出码仍保留；不改生产 probe timeout。新增更多原生演练后 CI 总预算为 60 分钟，预算增加本身不当作修复。

失败 run：PR [37416932551](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37416932551)、push [37416927687](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37416927687)。私人 job 日志的 SHA256：PR `05954a7ed1e1c3ac32201a7e7d18b1bf80d023c0d125b5d349e48e25e5b91823`；push `b223ecdd7c2a9f90e69ab531e93b79df7f69cdc7151f809448a01ac061558ff2`。不把原日志放进仓库。

关闭发布读取冲突有确定性 native 实验：保留 rename 的 DELETE 句柄，旧 File.ReadAllText 必然共享冲突；新 reader 在同一只读句柄核验规范路径/单链接并读字节，允许 Read|Delete、仍拒写，原认证不变。伪造认证仍拒绝，并发只读仍兼容。其依据、首轮失败与修复在会话交接中；没有吞异常重试掩盖。


主窗首轮完整回归 source `9032b0e2`：602 tests / 600 pass / 1 fail / 0 cancel / 1既有环境限定skip，1,746,458.5835ms。唯一红灯是native rename测试夹具未完整清零UTF16缓冲区，文件名尾部混入未初始化字节；该helper不进入发行库存。最后补查也确定session启动回执reader有同一DELETE发布窗口，已保留路径/ACL/单链接/auth、共享Read|Delete并拒写。worker确定性2/2通过；主窗因此在最终source重新跑整组，而非过滤/重试原失败。旧TAP留在 `build/ci/pr14-automatic-final-root.tap`。

生产plainPath函数的SHA256为 `c347c0ced6e430f8819e3273bf88932e5f019f381edc91abc9e74aee5fbc3d7c`；与45bcab16逐字相同，protected_paths.ps1/ACL脚本也逐字相同。

新增跨用户CI夹具首轮 source `c6897280` 的两次执行均在账号准备后失败，回执 accountCreated=true/cleanupConfirmed=true（58,673/58,802ms总时长，含factory），未执行真实恢复。主窗与独立只读worker用 Windows PS5.1 纯内存复现：Add-LocalGroupMember 的 Member 类型为 LocalPrincipal[]；SecurityIdentifier→该数组必为 PSInvalidCastException，New-LocalUser 返回的 LocalUser 可赋值/转换。夹具改直接传 LocalUser，并验证恢复子进程实际token不含Administrators（含deny-only）且非管理员，未删标准用户门槛。第一轮没有原异常文本，不把全部账号后步骤猜成另一种网络超时。

修正后 source `1921b326` 两次已经通过账号准备/启动子进程，却在child连接pipe前拒绝；父回执 cross_user_pipe_connect，进程/账号清理确认。继续补child细阶段与受限异常诊断、显式非秘密环境传递；该轮未冒称跨用户成功。不打印原异常Message、口令或用户名称；本机仅元数据/纯内存转换，未调用账号动作。

第三轮 source `305e621d` 的两次执行已通过管道和 child 前置检查，但在 `cross_user_restore_report` 失败（106,183/109,344ms），且 cleanupConfirmed=false。原回执没有 child stderr 或分项清理结果，未确认具体原因，也未称真实恢复完成。现只在 CI 夹具添加异步 stderr 收集、长度/字段/确切错误类型白名单，以及 Job、child、账号、服务、token 的逐项清理回执。任意错误 Message、命令后缀与原 stderr 均不输出；native 失败只报整数 Win32 码。主窗复核补丁，生产库存/plainPath/ACL不变；实际跨 SID 恢复仍等待下一轮远端结果。

第四轮 source `e557473d` 两次的受限诊断均明确 child_restore_inspection 失败，清理各项全部确认（118,905/106,562ms）。新夹具仅保留已产生的 Node 固定阶段与错误码 SHA256，通过严格父端 parser 重建；不输出 stdout/stderr/Message。真实 8 字节合成失败链验证成功，非法字段/阶段/摘要拒绝。实际根因等待该证据，不把诊断补丁当成恢复成功。

第五轮 source `cfc8b011` 两次 Node 都到 restore，错误码摘要 `4881737c9b27e65fe2e8a2650af307d42887a48b93b5802358fffa11af0bb9fd` 对应 portable_authentication_failed。真实 PS5.1 纯合成进程实验证实 .NET Framework 的 StandardInput 文本流在 Start/AutoFlush 时可写入 BOM：48字节在UTF8/UTF16带BOM编码下变51/50。仅在启动期间临时设无BOM UTF8、finally立即恢复，实际两种编码均保持48字节，失败启动也恢复原编码；CI协议和回执现严格要求48。生产KDF/认证/还原API未改。该轮另有一次 seclogon 停止 native1052，实际发生状态未知，不忽略清理失败；正在补受限状态等待。真实跨SID成功仍以新CI为准。

第七轮 source `d9f66775`：PR [job112160988489](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37430777811/job/112160988489) 59,639ms、push [job112160898262](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37430770899/job/112160898262) 61,295ms，均在 secondary_logon_query、创建 child 前失败；服务观察与计时为0、账号回收及清理确认。主窗与 worker 各自在全新 PS5.1 进程只解析类型，确定未加载 System.ServiceProcess 时为 RuntimeException / HResult -2146233087 / TypeNotFound；显式加载后成功且可重复加载，未构造或查询任何本机服务。CI-only adapter 现按 hosted guard → 显式加载 → 创建对象的顺序执行。主窗重新执行实际 loader 的失败→成功回归、入口顺序、两脚本语法/native编译、18/18状态模拟、GuardOnly退出2及diff检查，均通过。既有两次不同 SID 真实还原证据保留，不替代此修复后的精确 head 远端全绿。
source `2c75e510` 的跨用户两轮继续通过（push85,574ms、PR127,420ms，原生服务回收实测Stopped），但Windows生命周期两轮失败：push [job112163883579](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37431689258/job/112163883579) 151tests/141pass/8fail/2cancel/0skip、2,637,425.9188ms；PR [job112163980608](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37431696243/job/112163980608) 151/141pass/7fail/3cancel/0skip、2,936,447.3172ms。其余11 checks全部成功。两轮相同10个标红用例；取消项是用例180s预算耗尽，未过滤或改成skip。

已确定首发在 raw inspection restore 的 `configuration.mjs protectedPath(parent,true)`：原10秒fresh PowerShell完整ACL断言超时、stdout/stderr空。随后六个lifecycle项在首次ready、构造Store前退出，尚未执行death或迁移；session首项也是第一次ready前失败，有限公开错误只表明runtime_operation_failed，不能统一冒称全部根因已定位。该用例前置Protect-NewDirectory已经以同cleanEnvironment执行过GetAcl/SetAcl，不能把单次预热当作既定修复。正在限定CI夹具补fresh进程分段计时与原10s实际protectedPath严格预检，失败则CI照常失败；生产检查/timeout/cleanEnvironment不改，未知启动时延仍等待精确证据。纯合成失败日志留在忽略目录，SHA：push `32a8221cbdeaaa6e57b7c11b725704b5969bfb3becc16d309e3fbc984bc9c31b`、PR `88206c9dae919cdef5fc2929eb935bc1200a7927eaebddd09258180cdd77cc8b`；不提交原输出、base64源码帧或控制nonce。

已集成[CI-only native分段预检](SCHEMA6_CI_NATIVE_PROBE_20261006.md)：每阶段独立PS5.1，保留原清理环境，最后仅调用一次原protectedPath(root,true)/10000ms；失败不运行完整套件。主窗在集成目录8/8针对测试通过（543.3311ms、0skip），另执行实际PS5.1驱动：no-op376ms、准备545、默认GetAcl365、默认完整断言451、系统模块对照429、最终原门控424、清理1ms，全部通过；独立只读复核无阻断。报告只含阶段/时间/有限码/数量，上传JSON与TAP；不改缓存、注册表、模块目录或生产库存，未声称云端根因或修复已确认。远端下一轮以分段证据和全部151项结果为准。

source 1cff9d08 的两轮预检实际失败并及时停止整套测试；[分段安全回执](SCHEMA6_CI_NATIVE_PROBE_VALIDATION_20261006.json)。push/PR no-op为208/233ms，默认GetAcl20,470/23,299ms、完整断言20,526/23,383ms，显式PSHOME对照296/313ms；原production门槛10,015/10,013ms超时。先前同环境准备和这轮多次独立调用均未把默认发现变快，不能称预热已修复。下一项限定一次性hosted CI的模块搜索作用域，保存/恢复Machine+User模块路径以及临时隔离强制AllUsers根，保持系统模块、原检查/门槛/全部用例不变；实际效果仍待下一精确head。1cff跨SID两次实际口令/只读Core恢复再过，push141,419ms、PR78,846ms，全部清理确认；本机现役和机器配置未触碰。

已集成[hosted CI模块搜索作用域](SCHEMA6_CI_MODULE_SCOPE_20261006.md)：先host guard，再保存两项registry raw值/类型/缺失状态，规范身份校验后暂移强制AllUsers根到所有搜索根之外，原位独占创建空根；finally只删身份匹配空目录并归位，各registry独立精确还原，任何清理失败CI失败。原环境/new PS/10s检查及全部151用例保持。本机只用纯callbacks、编译/AST和拒绝入口验证，14/14专项通过（2310.1204ms，含23种状态）；独立源码复核无阻断。本机未执行registry或全局目录适配器，真实scope和全套结果以本交付提交的PR Checks、安全module-scope/probe回执为准，尚未提前宣称全绿。

## 生产备份二进制输入编码边界

CI夹具此前修过BOM，主窗继续核实际生产Start-BackupChild，发现同一.NET Framework输入初始化行为。只从1060f192提取真实函数，未运行wrapper顶层：虚构88字节口令帧+18字节JSON，默认936收到106且所有偏移正确；UTF8带BOM收到109、Unicode带BOM收到108，固定帧头/长度/载荷偏移均错。没有读取DPAPI或真实口令/备份。

最小修复限定Process.Start期间暂用无BOM UTF8，finally立即恢复；二进制帧、BaseStream写入、KDF/认证/清零/路径与manifest门槛不改。新增真实PS5.1回归在旧source先红（普通key帧53字节应50），修后单项绿，覆盖三种原编码×普通key/portable帧，精确字节哈希及头/载荷、三种启动失败后恢复。独立源码复核无阻断；[工作包交接](SCHEMA6_BACKUP_BINARY_FRAME_20261006.md)记录38/38备份相邻专项通过（90,920.6968ms、0skip），worker原提交1ee96d1d已整合。接下来按新已提交source重建43库存和重跑主窗整组，旧beed回执仅作历史证据，不冒称库存仍逐字未变。

## 六类最终合成演练

| 情况 | 真实观测与下一启动要求 | 最终集成结果 |
|---|---|---|
| 正常关机消息/取消关机 | Query 立即答 TRUE，认证 close 后真父/child/guardian 退出、Job 空、锁可重开；取消关机或下次登录均使用新 control | 通过；原生 session case 149,152.5619ms，真实 clean/新 control/下一启动读回均断言 |
| 关机时 Core 正在写入 | 合成固定包在 BEGIN IMMEDIATE 后加限时测试屏障；Query 与真实 HMAC close 在事务未放行时已到达；放行后 HTTP 接受1条，下一真实 login 的 changes 读回同一 sync_id | 通过；同一 session case；query_during_open_core_transaction=true，accepted=1，next_start_http_readback=1 |
| hook 超时 | 按拥有 Job/exe 身份暂停合成 Core，30秒超时不造 clean；拥有树退出；下一 login 先加密保全并恢复 schema6 | 通过；141,672.1281ms；30秒超时后下一 login 自动保全并恢复 |
| 强杀 Node | 原生固定入口强杀 child 后 marker 非 clean，custody.lock 载体保留但系统锁释放；下次固定入口自动恢复。另有真实 Node 强杀 WAL：已提交回放、未提交回滚；同会话 resident 新 control 与 HTTP 读回 | 通过；原生 child 103,460.7224ms；同会话新 control/HTTP读回 109,673.3552ms；WAL已提交/未提交专项也通过 |
| 强杀 guardian | 原生 guardian death 后拥有树结束，没有伪 clean；下次固定入口 raw 保全/检查通过后正常运行 | 通过；109,651.5346ms；下一真实固定启动恢复；另 parent death 101,408.4671ms |
| 迁移中断 | adapter 故障注入在副本中断，原 DB/WAL/SHM/journal 摘要不变；下一原生固定入口对 precommit/commitStarted latch 均明确拒启，原件不改。前者可回旧 v4；开始替换后只做向前核验 | 通过；原生 next-start 39,083.6325ms；副本 fault injection/原件摘要未变，precommit/commitStarted明确阻断 |

“正在写入”的事务屏障只存在于独立 synthetic Git 的测试包，生产没有故障/暂停开关；不是实际 OS 关机或现役 Gate。原生迁移 next-start 部分模拟便携 fault injection 留下的 latch，不声称在真实迁移指令中强杀 OS。所有测试只给自建隐藏 HWND 发定向消息，不广播系统关机。

正常 SIGINT/SIGTERM 在成功关闭时可记 clean；Windows process.kill 是强制结束证据，不混作 POSIX 优雅信号实测。每次登录使用新空 control；既有 ready Core 异常死亡可在同一登录会话有限退避恢复，检查失败/短时间再次失败停止并报告原因，避免无限重试绕过 Gate。

## 电脑外恢复与仍有的现场限制

合成口令、独立 Node 与 pinned Windows wrapper 在原 DPAPI 目录不可用时真实恢复并启动只读 Core：核 node/schema/devices/全部用户表指纹与整库字节哈希；5条受限业务路由拒绝（含一条GET；SQL拒写另有独立测试）；退出 DB 字节不变。只解密或比较哈希不算此验收。完整口令备份专项14/14通过，最终主窗整组也覆盖并通过这些用例。

另一标准 Windows 用户的实际合成恢复已在一次性 hosted VM 完成两次：source `e1116f5e`；push [job112157590807](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37429716715/job/112157590807) 135,225ms，PR [job112157585768](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37429722424/job/112157585768) 133,300ms。仅口令、DPAPI未使用、SID确实不同且token非管理员；真实Core只读启动、5条受限路由拒绝、字节不变、无sidecar、清理全部确认。合成schema4为3张用户表/7行/1设备，全部用户表指纹与factory一致；不是现役schema4全量库或九类52真实文件的跨用户重验。[结构化回执](SCHEMA6_CROSS_USER_VALIDATION_20261006.json)只含计数、哈希、布尔与CI来源。

本机未创建账号，也未在另一台实体电脑实测；`crossMachineTested=false`。这两项与已经通过的不同Windows SID恢复分别报告。新机口令保管、原DPAPI凭据与生产recovery key的重新绑定限制见[电脑外恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)；检查恢复目录不能直接激活。CI临时服务清理补丁另见[状态机交接](SCHEMA6_CROSS_USER_SERVICE_CLEANUP_20261006.md)：主窗PS5.1独立编译/18种纯模拟全部通过，固定服务/不force/不级联，只有实测Stopped才成功；新的最终CI还必须覆盖该夹具。

Tailscale 机器私钥按用户决定排除，不是缺项；换机重新登录同 tailnet、释放/沿用原机器名，按原 Serve 协议/路径/端口恢复；手机用数字 IP 时更新 Core/47862 地址并重新核认证、cursor、单消费者。当前未执行重配。调试邮件允许先关闭，保全旧配置/凭据/journal，不自动重发。

旧 v4 首次接管与崩溃恢复同一机制：未来现场先冻结旧任务/结束绑定进程树，确认离线后首开前保全四文件，副本回放/迁移/检查，通过才替换。提交前原件不改；开始替换后留下中断锁存并向前检查。不存在另一个“不可重做阶段链”。MCP、手机、上传器与 captures 真机闭环仍有独立现场 Gate；47862 桥保持此前决定。

## beed 历史固定候选与回执

- 已提交 source/Core/wrapper 同一 SHA：`beed93a3657ab59fbe033a435f471814d8895736`。
- 固定候选：`C:\HereIAm\schema6-automatic-final-owned-20261006`；43项库存，manifest SHA256 `45d00ecdb113957ffdc5c65e2b90454611c83eb90cf6879c8cccfd1df1ea787a`；Node24.14.1 SHA `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`。
- 25个 Node 文件语法及16个 PowerShell 文件由目标 Windows PS5.1.26100.9444 parser通过。首次在已填充 build 目录调用 Protect-NewDirectory 被空目录门控正确拒绝；改走既有流程：先保护全新空目录，再逐项复制已验证库存、重新 verify，同一 manifest字节，不修改生产门控。
- 最终整组：603 tests / 602 pass / 0 fail / 0 cancel / 1既有环境限定skip，3 suites，1,024,765.3329ms（约17分05秒）。唯一skip为本机大小写不敏感目录不能表示两个大小写不同的文件；不新增skip，不过滤红灯。完整TAP SHA256 `6b47c82caf449aa9aa4725aaf4e82c4d24eeb3d051245e999049291b9b11f332`。
- 另一次对上述已组装固定候选的真实 loopback/认证停止/child+guardian+Job/锁烟测：通过，67,256ms；真实 loopback health、认证 stop、child/guardian 退出、Job 空、runtime lock 释放、发行字节未变。回执 `build/ci/pr14-final-candidate-smoke.json`，SHA256 `762ebe050d457db036fe9b9edf6890a23e9b95d3c863c1977c8eac8385384913`。
- 此前CI交付登记：截至1060仅CI夹具/交接变更，43库存与beed逐字一致；后发现生产输入边界，下一候选必须重新绑定新source。提交后再次比对并把 deliveryHead、manifest及结果写入忽略的 build/ci/pr14-delivery-inventory.json；最终精确 head 与全部 CI 回执在同一 PR 正文及 Checks 登记，历史 green 不替代本次。

最终主窗整组入口：`node --test --test-concurrency=2 tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs tools/i_core/*.test.mjs tools/i_remote_mcp/writeback.test.mjs tools/i_remote_mcp/writeback_e2e.test.mjs`。真实本机执行使用解析后的文件数组与双 reporter，主窗24逻辑CPU，文件并发2；小型Windows CI仍串行文件并发1。最终完整 TAP 仅保留在忽略的 `build/ci/pr14-automatic-final-root-2.tap`，交付其计数和 SHA；无真实正文/密钥/口令进入报告。

上线步骤与估算停机时间见[一页操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)，细节见[部署方案](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)、[运行说明](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)。本轮完成后暂停，等待审核，不继续生产切换。
