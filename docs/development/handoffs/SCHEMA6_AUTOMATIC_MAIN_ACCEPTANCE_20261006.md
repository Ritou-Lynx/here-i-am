# PR14 自动运行、口令备份与 CI 续作｜主窗验收（2026-10-06）

仅继续 `codex/core-deploy-readiness-20261006` 与同一草稿 [PR #14](https://github.com/Ritou-Lynx/here-i-am/pull/14)；base 为 `v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`。**主窗最终整组与精确固定候选烟测已通过；真实跨用户 CI 与最终远端提交检查尚待回执。** 验收完成后只推此分支、更新同一 PR、暂停等审核，不合并、不部署。

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

合成口令、独立 Node 与 pinned Windows wrapper 在原 DPAPI 目录不可用时真实恢复并启动只读 Core：核 node/schema/devices/全部表指纹；5类业务写/配对拒绝；退出 DB 字节不变。只解密或比较哈希不算此验收。完整口令备份专项14/14通过，最终主窗整组也覆盖并通过这些用例。

没有已获准的第二 Windows 用户登录或第二台机器环境；本轮未创建账户，**未完成真实跨 Windows 用户/异机实测**。新机步骤、恢复口令保管、原 DPAPI 凭据与生产 recovery key 的重新绑定限制见[电脑外恢复](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)。检查恢复目录不能直接激活为现役库。

Tailscale 机器私钥按用户决定排除，不是缺项；换机重新登录同 tailnet、释放/沿用原机器名，按原 Serve 协议/路径/端口恢复；手机用数字 IP 时更新 Core/47862 地址并重新核认证、cursor、单消费者。当前未执行重配。调试邮件允许先关闭，保全旧配置/凭据/journal，不自动重发。

旧 v4 首次接管与崩溃恢复同一机制：未来现场先冻结旧任务/结束绑定进程树，确认离线后首开前保全四文件，副本回放/迁移/检查，通过才替换。提交前原件不改；开始替换后留下中断锁存并向前检查。不存在另一个“不可重做阶段链”。MCP、手机、上传器与 captures 真机闭环仍有独立现场 Gate；47862 桥保持此前决定。

## 主窗最终固定候选与回执

- 已提交 source/Core/wrapper 同一 SHA：`beed93a3657ab59fbe033a435f471814d8895736`。
- 固定候选：`C:\HereIAm\schema6-automatic-final-owned-20261006`；43项库存，manifest SHA256 `45d00ecdb113957ffdc5c65e2b90454611c83eb90cf6879c8cccfd1df1ea787a`；Node24.14.1 SHA `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`。
- 25个 Node 文件语法及16个 PowerShell 文件由目标 Windows PS5.1.26100.9444 parser通过。首次在已填充 build 目录调用 Protect-NewDirectory 被空目录门控正确拒绝；改走既有流程：先保护全新空目录，再逐项复制已验证库存、重新 verify，同一 manifest字节，不修改生产门控。
- 最终整组：603 tests / 602 pass / 0 fail / 0 cancel / 1既有环境限定skip，3 suites，1,024,765.3329ms（约17分05秒）。唯一skip为本机大小写不敏感目录不能表示两个大小写不同的文件；不新增skip，不过滤红灯。完整TAP SHA256 `6b47c82caf449aa9aa4725aaf4e82c4d24eeb3d051245e999049291b9b11f332`。
- 另一次对上述已组装固定候选的真实 loopback/认证停止/child+guardian+Job/锁烟测：通过，67,256ms；真实 loopback health、认证 stop、child/guardian 退出、Job 空、runtime lock 释放、发行字节未变。回执 `build/ci/pr14-final-candidate-smoke.json`，SHA256 `762ebe050d457db036fe9b9edf6890a23e9b95d3c863c1977c8eac8385384913`。
- 最终交付 head 与库存字节比对：FINAL_DELIVERY_PENDING；最终精确 head 的 CI 回执以同一 PR Checks 和 PR 正文登记，历史 green 不替代本次。

最终主窗整组入口：`node --test --test-concurrency=2 tools/i_core/release_schema6/*.test.mjs tools/i_core/release_schema6/lifecycle/*.test.mjs tools/i_core/*.test.mjs tools/i_remote_mcp/writeback.test.mjs tools/i_remote_mcp/writeback_e2e.test.mjs`。真实本机执行使用解析后的文件数组与双 reporter，主窗24逻辑CPU，文件并发2；小型Windows CI仍串行文件并发1。最终完整 TAP 仅保留在忽略的 `build/ci/pr14-automatic-final-root-2.tap`，交付其计数和 SHA；无真实正文/密钥/口令进入报告。

上线步骤与估算停机时间见[一页操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)，细节见[部署方案](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)、[运行说明](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)。本轮完成后暂停，等待审核，不继续生产切换。
