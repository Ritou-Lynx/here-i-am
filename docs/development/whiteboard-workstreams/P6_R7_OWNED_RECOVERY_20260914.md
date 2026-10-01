# P6 独立见证与同库恢复验收

owned22/23 的 App 异常退出后同库恢复已实际通过并完成独立复核；连同14/15，关闭本页的正常与 App 死亡恢复缺口。P6 / Goal1 尚需普通桌面聊天入口接线及该新候选的实际验收，当前继续工程准备。生产 profile 保持拒绝；不操作真实队列、认证数据或现役服务。隔离候选基线为 `c5d7cbfe559eb517b3b1110f27e07dc8308d6442`；本地集成发生于 `v3-lab@be18b91a2882d4b86e300e5d10c819d4ca3da58b`。并行 A3 工作继续推进主目录，2026-09-14 本次复核为 `389aa735ca6003f3141d12f16c734c9a64441c47`、空 index。保留并行修改，本任务无提交推送。

## 当前候选与实际进展

普通聊天后续工程已完成独立构建与24/25封包，尚未启动；现场47831普通模型入口未启用，正在等待该共享服务启用重启的具体授权。新候选及191/191、76/76、本次程序哈希均见[普通聊天候选](P6_R7_PRODUCT_CANDIDATE_20260914.md)。下方App02/Witness04等是本页旧恢复验收的固定组合，不能与新候选混用。

- App02：173 源 / 153 构建文件，manifest `1033599d29dc84ffc24ef28eca889b63998c1fd48f184e1006b8a4167d260448`，exe `a8ec80eccc17bb07e6fa757c265845a2ecad0ad9ae663ead8908c5e0112009bc`。159/159、分析、critical 3/3、Debug 构建均实际退出 0；相对 App01 只升级 witness 固定引用，构建清单另包含 `native_assets.json`。
- Witness04：exe `7381f83666994d5835c1580c37afbf80a7556c5a1d516596e6f4b794c4af823e`，最终 10/10 合成场景、553 核心断言通过；actual/synthetic 固定分目录，原私有目录不接管、不放宽 ACL。独审通过。
- Node：39/39，21 源双入口闭包 `a749fe181ec1edcf8ff099e4d7d5db076ab456fb6aba7fbd8675bd2df16ac613`；协调 exchange 固定 10 秒，self/connect 仍 3 秒；额外 2 项同 addon 私有管道合成覆盖延迟 ACK 与超时后拒绝。启动诊断只输出有限阶段和 timeout/unknown。Addon02 保持前述固定哈希。
- owned12：到达 App/Node 注册后失败，witness 实际 4；App 正常关闭未确认，精确活句柄清理实际 -1，Node 原退出码/双 EOF 未知。3.239 秒仅支持协调超时推断，不确诊；[失败汇总](../../../tmp/p6-r7-review/app-lifecycle-owned-12/startup-failure-summary-v1.md) 保留原失败。
- owned14/15：同一 task `3a88357f-129d-44e8-9372-db4de8a56562` 实际 failed → retry → running → pause；仅一次本地失败、注入本身零远端派发、retry_count=1。正常关闭后只启动一个 successor，原暂停 task 投影完全相同、没有自动执行；显式 resume 后精确 2000 行/8892 字节/SHA `929ea644021b8159e97d4b2d3c28f917419420d9a51c4c82089785879bf45a00`。
- 14/15 收尾：前任 App23536/Node7548 原句柄独立实际 0；successor App46120 原句柄实际 0；witness 实际 0，43 条链、361 pins、五个 native owner 的实际 0/六项 true/pending=false 均核验。后继 Node996 没有另行导出的独立 held-exit 收据；其 Node0/双 EOF 依赖冻结 App 的严格退出代码，不能混同前任双句柄证据。进程监听全部清空、47831/47841 原身份保持。[独立复核](../../../tmp/p6-r7-review/app-lifecycle-owned-14/normal-recovery-independent-summary-v1.md)。
- owned16：运行中精确 App49384 单次异常退出，活句柄观察 -1；Node15976 只记录 stdin_end/shutdown_requested 后失去后续证据，witness 实际 4，拒绝恢复。native25632 自身 final 文件六项 true/pending=false，但 stdout 发出失败且实际退出未知，不能据此补成功；c557 四规则只读核查已准备，尚未执行。
- 已用同 Node 的真实父子管道合成复现 wrapper 未处理 EPIPE：原版停止于相同两条事件、退出 1；v4 只隔离 stdout 日志镜像，实际 stdin EOF 才启动关闭，8 项合成通过且独审通过。16 具体死因仍未取得原 Node stderr/held-exit，不能以复现覆盖历史。v4 generator `5007578382e000a625baffcc6202227d1b9006a33b9dc0504d0637a159dbca86`；旧 v3 与候选源码保持。
- owned18/19：新 dataset `4fb9c3f0-b339-47af-bfb8-3ce906cea4c0`、package `9e96fa082cd9bf38b58f530d366793f0bee5f6666a79b106409315f82acf62d7`；只读配置/启动前检查通过。18 预检遇系统确认，界面读取超时及重新激活失败，曾观察到 consent/LockApp 进程；已请求用户处理，没有代点。随后 native48836 实际4、固定分类 `task_helper_shell_execute_win32_1223`、cleanup_pending=true；这不证明用户主动拒绝。没有创建验收任务，19 未启动。2026-09-13 17:42 UTC 精确失败清理完成：本轮捕获的 App44772/Node36124 活句柄各单次终止，分别实际198；清理执行器实际0，不等于正常关闭。原 witness 实际4/外层1 已取得；两等待观察器退出1，未记成功。20条审计链尾保持，无admission/bind/claim/consume。17:44 UTC 只读快照确认固定测试进程及49741监听缺席、两个现役服务原身份保持。见[失败收尾](../../../tmp/p6-r7-review/app-lifecycle-owned-18/startup-failure-summary-v1.md)；477四规则当前态仍未知。
- c557/477 两份固定四规则只读检查在 2026-09-14 00:50 UTC 完成：用户解锁后，合并入口仅一次 RunAs，外层collector2076实际0，c557/477两个collector36136/48372和两个inspector均整数实际0；顺序执行，各自三filter与一个sublayer全部缺席，零删除，事务与资源完整关闭。57份独立证据/66次pin检查独审通过，采用[02版完整索引](../../../tmp/p6-r7-review/app-lifecycle-owned-18/c557-477-readonly-batch-01/independent-actual-audit-02.md)。c557历史native实际退出未知、477原失败/pending保留，不以当前规则缺席补历史成功。
- owned20/21 于 2026-09-14 00:51 UTC 启动新复验：dataset `3a753590-6d03-4586-b4f6-01b455bb8b99`、package `23889399ab7fd0c983318890bdf051f5fdcbda49b5f80ffc5beb9cadafe57efb`，同 App02/RB39/Witness04 与 v4 wrapper。361固定输入只读校验及新鲜进程前检通过。前任App15080/Node47460、witness49332，preflight native39008实际0/cleanup_pending=false。UI唯一创建并start任务 `1a438d1b-e680-49d2-bd1f-941c29a4fe01`，DB采到pending/starting后failed，epoch `afc95d50-3e83-4c3a-bd61-02f8dd5c05e4`、仅start/retry0/无session或turn/空结果。执行native36080在00:55 UTC实际4、`task_helper_shell_execute_win32_1223`、pendingtrue；曾观察consent进程，但不能证明用户看到或主动拒绝。未采到running、未写fault-ready、未进行task-bound异常关闭，21未启动。00:58唯一AltF4正常退出请求记录shutdown_unconfirmed；正在限定失败清理，3118固定四key只读检查尚待实际查询。
- 主目录本地集成：App 23 个拥有路径、Node 12 个路径精确合入，原内容已归档，其他并行修改/index 保留。主目录 App159/159及分析、Node200/200实际退出0；broker 默认 60 秒、裸 transport 默认 10 秒保持，180 秒仅在显式 candidate/successor host 的非预检调用注入。[集成独审](../../../tmp/p6-r7-review/integration-independent-review.md) 无 P1/P2，23/12 及映射到主目录的21依赖逐项一致。未重建主目录 App，不能把隔离候选实际结果当作主目录构建验收。

## 2026-09-14 本轮实际收尾

- owned20 的执行启动返回1223/native4，未进入运行或异常恢复注入。正常关窗未确认后，固定42条链尾已有released；第一版清理因只接受38条前缀而零动作拒绝，保留其失败。精确复核后第二版只对本轮活句柄的 App15080/Node47460 各一次终止，实际198/198；witness实际4/外层1。固定测试进程与监听随后缺席，现役两服务身份不变。[失败汇总](../../../tmp/p6-r7-review/app-lifecycle-owned-20/startup-failure-summary-v1.md) SHA `a18f48c06ca9768448f03b49b718f11ba87fb432f078847f80abe72cedde99d6`。这不是正常关闭或恢复成功；上节20/21段落保留启动阶段历史。
- 3118 四规则于01:06 UTC完成单独只读查询：collector18200/inspector实际0，四key全缺席、六项资源/事务事实true、零删除。52项断言/27份证据[独审通过](../../../tmp/p6-r7-review/app-lifecycle-owned-20/3118-rule-inspect/independent-actual-audit-v1.md)，JSON SHA `aa328962de2fae190051c37158a6c318d049130d83e7c2f8f05d2553e2e95be3`。连同c557/477，三个旧实例的规则当前态疑点关闭，历史native失败或unknown不改写。
- owned22/23 新package `f5de431ac1c070a79a09da7c58f70ddf3a09b97541d3fe663cfc9e7c54828af4`、dataset `55df17bd-c139-48b3-a911-c3ec6007fe27`，task `be7f9418-8956-4a31-9180-02a8c7986096`。保持同 App02/RB39/Witness04/v4。新鲜DB running投影后，01:14:49 UTC 对App23340活句柄仅一次故障终止，实际-1；witness原对象观察4294967295一致。没有杀Node/native/witness，也没有伪造首代app_closed或Store关闭。
- 原Node12640由witness持有对象记录实际0，原turn收到匹配interrupted终态；双退出链先于唯一后继启动，claim/consume各一次。后继同任务保持blocked/interrupted、actions=[start]、retry0及原epoch/session/turn，没有自动执行。UI显式resume后新epoch `ac812a13-7179-49ca-b66f-25029d636b2b`，最终completed/2000行/8892字节/上述标准SHA，actions仅[start,resume]。
- 后继App38788原对象实际0、witness实际0；四native owner均实际0/六项true/pendingfalse，两代外部身份对应。后继Node48116无独立导出的held-exit收据，依据限于local closed、App实际0及冻结App严格Node0/双EOF/资源关闭合同，不混同原Node独立见证。最终候选进程与六监听为0，47831/47841身份保持。
- [22/23独立复核](../../../tmp/p6-r7-review/app-lifecycle-owned-22/app-death-recovery-independent-summary-v1.md) 校验361 pins、173源/153bundle、21 host closure、37条原私有审计链和39项证据；VerifyOnly `03b17d` 与摘要生成 `19da34` 均实际0。JSON SHA `052e6a495009dffeab92d605c2b43360778cbe1dcadc031ebdb979224f608e91`。witness结果的actual_native:null不当作native证明；native结论来自逐owner证据。

## 早期冻结候选（历史）

- App：173 份源文件、152 份构建文件；组合测试 159/159、相关分析无问题、critical 3/3、Windows Debug 构建实际退出 0。冻结清单 SHA-256 `127ffb1fd8e3749ad5856f533ac075028c7725bc8ee12bf948201ea5562527a2`，exe `2e867bf2cf2f6ee13cf80e432a38b76c5858c88168db1626ce7951f2c7ca114e`。这些是本地验证，不能替代实际恢复。
- 独立 witness 03：exe `3c4ff0c087f19ea8a1858e05a029252af8cf597eaaed5f0ee43836d728d64840`；9/9 合成场景及 514 项核心断言通过。正常关闭和 App 死亡后的 Node 正常关闭分开记录，缺失独立证据时拒绝恢复。
- Node addon 02：`7a80151fa467f296237c03f0cfacdfbda5a5447712041799053174666f8756fc`，23/23 合成原生测试通过。持有真实活进程句柄后观察退出；不以 PID 缺席替代退出证明。取消后的内核 I/O join 不宣称具有绝对时限。
- Node 双入口：37/37 测试实际退出 0，21 份精确闭包 `ba2d7e2bdc64e97e7ba3233ad2b0772655a55d0cf514b5afb8b26a56513fbd72`；review `046cc75e5f313808c9c5f1282c025c9b5e793374efa2c78e46ac00ed1aa0a909`。隔离状态拒绝新的 attestation，不能继续显示旧 ready；独立复核通过。

## 实际运行记录

08/09 只完成准备，未启动；其 36 项版本闭包已被新候选取代，旧目录保留。

10/11 使用全新 dataset `8501113d-338d-4e83-8ddb-21bc0dc68b88`，package SHA `982fd1fde48a84569bc1e311015d85fb6921ab3bfd452dd76fa13b98f9d52a7c`。精确配置构造器只读校验全部 360 pins 通过（36a3f2），不启动 App、不打开数据库。新启动前进程检查通过（2c32ca），现役服务身份保持。

2026-09-13 16:13:04–05 UTC，真实 witness 启动返回 `owned_recovery_frozen`，实际退出码 4（841272）。当前未产生该 dataset 的 audit run 目录、数据库或 Node events；随后只读核对无本候选进程（694f98）。两只读观察器由所属会话 Ctrl+C 终止，退出码均 1（0e96e7、793176），不记为正常验收关闭。此次属于进入任务前的拒绝，不能算 failed retry 或恢复通过；正在定位启动前置校验。

原 360 项输入在修改前再次逐项匹配（07ef7e），[启动失败摘要](../../../tmp/p6-r7-review/app-lifecycle-owned-10/startup-failure-summary.json) SHA `f39009c06f752a275726ae6b9d911ddbc9cea21aa4f5f8f5af42878fbade6c4d`。普通执行环境的只读前置探针全部通过；换到与实际启动相同的执行环境后（735287），配置、核心构造、二次 pins、数据不存在及数据父目录原句柄验证仍通过，但原 `runs` 目录句柄和 ACL 读取失败，后者为 UnauthorizedAccess。由此确认实际与合成执行身份对旧私有审计目录的访问不同。该诊断不创建 App、目录、pipe 或数据库；不放宽或接管旧目录权限。

03 App 的 173 源 / 152 构建文件已逐项复制并核验到独立归档，archive SHA `7f06fe7b0e5e251ada71152634e42b0fb1f1068ef1699725a882629531e85abc`；37 项 Node 候选归档 SHA `e07b30be7cd5bc682ed2a739e7d4badeb400fbcbdda2d292a3c9f10e4ca09b9c`。正在准备 04，将实际审计与合成审计固定分目录，并增加有限阶段诊断。

## 剩余验收

1. owned22/23 已关闭 App 异常退出 → 原 Node 正常收束 → 同一存活 witness 单次恢复 → 不自动执行 → 显式继续的实际验收；不扩大到 Node 崩溃、witness 重启或跨系统重启恢复。
2. owned16 c557 与 owned18 477 固定四规则合并只读核查已完成，各四key缺席；缺少历史实际 native 退出证据的事实保持，不以当前规则缺席倒推旧成功。
3. 本地集成独立复核已通过；按[普通入口衔接方案](P6_R7_PRODUCT_WIRING_PLAN_20260914.md)继续最小依赖映射、接线、本地验证与新唯一候选。普通入口/最终真人 Gate 仍需各自明确证据。
4. 14/15 的 failed retry 和正常恢复已在本页当前候选下实测通过；旧 owned06/07 保留各自候选证据，不移用为 App 异常退出成功。

实际目标仍为公开数字任务；预期结果是 1–2000 以 LF 连接、无尾换行，共 8892 UTF-8 字节，SHA-256 `929ea644021b8159e97d4b2d3c28f917419420d9a51c4c82089785879bf45a00`。
