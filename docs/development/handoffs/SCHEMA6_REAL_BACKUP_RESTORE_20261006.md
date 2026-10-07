# 九类真实保全与隔离恢复演练（2026-10-06）

> 后续审核决定（2026-10-06）：Lynx 已通过本页此前备份/恢复/退回证据。Tailscale 机器私钥明确不备份，换机重新登录、沿用机器名，不再列为待补项；当前 Serve/隧道配置保全证据不变。原“DPAPI仅同用户、旧v4首次接管/关机/自启尚缺、每天手动停止”是上一轮设计快照，本轮口令备份与自动副本恢复续作见[新验收](SCHEMA6_AUTOMATIC_MAIN_ACCEPTANCE_20261006.md)及[换机说明](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)。本轮不重新读取现役/真实备份。


## 结论

**最终52项、九类角色已加密保全并实际还原。** 还原后通过固定候选的真实 `createICoreServer({mode:"inspection_read_only"})` 在随机回环端口启动，健康明确为inspection-only，5类业务/配对/写路由拒绝；关闭后库字节/文件身份无变化、无sidecar。另独立只读核对6个SQLite的全部表（包含sqlite_sequence）及52项文件，全部一致。现役服务、线上配置、原库和手机安装均未改变。

各活跃库分别采用mode=ro连接的SQLite backup API；普通文件以前后hash/size/mtime检查稳定副本。不是共同原子快照、不是原始断电日志保全，也不证明生产writer已停。手机是前轮已保留的一致副本，本轮从认证旧密文重新提取；没有重新ADB采集，不称实时手机状态。

## 九类逐项覆盖

| role | 文件数 | 已保全内容／限制 |
|---|---:|---|
| database | 1 | 当前Core一致副本（schema4）；只读SQLite backup API，包含已提交WAL数据，未直接复制活跃main/WAL。 |
| release | 10 | 现役固定v4完整10文件：manifest、启动器、verify脚本、Node、Core/store/relay及PowerShell依赖。 |
| configuration | 20 | SMTP配置/一致journal；MCP writeback一致账本、2个启动文件、5个运行模块及Node；i_memory一致库、10/02快照、前轮手机schema62副本；Cloudflared配置、两服务启动配置/失败恢复策略、Tailscale serve状态JSON。 |
| task | 2 | HereIAm-iCore和HereIAm-iRemoteMCP的实际XML导出，未导入/改变任务。 |
| credentials | 8 | MCP .state 的OAuth、frontend token、phone-feed pull token；SMTP DPAPI clixml；Cloudflared tunnel credential/origin cert；历史Funnel cert/key。 |
| domain_policy | 3 | i_memory当前policy、pending decisions、before-B3 policy快照。 |
| transcript_grants | 1 | 外置grant完整字节；本次1条。对应设备凭据也保留在Core devices。 |
| replay_approvals | 1 | 外置72条完整批准；Core耐久metadata内72条也保留，逐条精确绑定一致。 |
| recovery_custody | 6 | 旧四输入密文、两份原DPAPI blob、旧加密迁移备份+manifest；新增私有copy initial_schema4 context。后者不构成现役first-adoption或activity floor。 |

## 实物、外锚与实际恢复

受保护私有根为 `C:\HereIAm\private-runtime-preservation-20261006`；仅当前用户与SYSTEM。以下都是路径和摘要，仓库中不保存数据库、配置值、正文、令牌、密钥或原XML。DPAPI仅在内存管道送入已验证固定Node。

- 最终密文：`complete-encrypted-bundle/runtime.aes256gcm`，373346290字节，SHA256 `b21a9f3e3f9ae5bba1a5c718251c69187d41003d1219115a244acd76d3645257`。
- 最终清单spec SHA256 `ca9adb431e7d41ef0d702fb1e302ca014c8ee764fa5ea55c3694eb7ca2d47447`；认证inventory SHA256 `7bde360f5c63bdafb33777d2d407b8adb390419430c7829437931b4bdf263c54`。
- key custody：`backup-key/runtime-backup.dpapi`，CurrentUser/path/purpose绑定，和密文目录分开；本机同用户实际解锁成功，不代表跨机器恢复。
- 实际恢复目录：`complete-restored-inspection`（演练成功后已安全清理明文，密文与DPAPI可再在全新目录还原）；所有文件按`role/name`新建，不向spec原source_path写入；带inspection marker，普通Core live入口拒绝。
- Create、认证提取、真实只读Core监听、关闭后复核均使用34文件固定候选，source `eb51153becc8f7c3b8c33bd9939b80c6eba7c132`、manifest `62e0b60b6e10387433aebafadbcd5364e6ebeec7c084b68f0844be5018645daf`。
- Core内置语义指纹 `6c9adfdf040fd94a5d116cb99ed091778362d7c215d39a91f0348a8553800422`；node_id前缀 `9d634309`，完整node hash `4e69f21dc984232a59847d5045d4aa296c2786e9b42bde4013be815ff4599527`；schema4，设备7。其用户表指纹不含sqlite_sequence，独立全部表核验已补含它，整库字节SHA同时覆盖全部页面。
- 全组件回执：`complete-all-components-restore-receipt.json`，SHA256 `5f7b576032fb99191172fb5286dbbd5868ec987f29aa7d92bcc50612d4e674c9`；完成UTC 2026-10-06T04:36:52.559432+00:00。

初版50项真实还原已通过，后补两服务failure policy导出，最终52项完整Create/RestoreInspection与全组件核验重跑成功。第一次还原调用误用了不存在的artifactPath回执字段，参数绑定阶段拒绝、未创建还原目录；修正为固定密文路径后执行成功，没有改验证器或外锚。

## 每个数据库的完整表核验

| 组件 | schema／user_version | 表数（含内部表） | 全部表指纹 |
|---|---:|---:|---|
| `data/core.sqlite` | 4 | 9 | `80fd0a587045371eb5d67f01e5f0b3c481ce7965b3a4508984736fe52d602d80` |
| `components/smtp-journal-sqlite.sqlite` | 0 | 1 | `12c63c4c9a8c800938d54b83ac78724b619255158fa70ca58930438e5ef73021` |
| `components/mcp-writeback-sqlite.sqlite` | 0 | 4 | `5e63fd181bdae60df4fce132dc883e6f177c41f4d78662719fbf1e6f1647b282` |
| `components/i-memory-sqlite.sqlite` | 0 | 8 | `d105f733028b09688517f23ae9bf92c2c0b26b5082dfc466be370674180dd0e3` |
| `components/i-memory-phone-snapshot-20261002.sqlite` | 60 | 140 | `b275d945ab4840976677fea0059d7a56ca5dfdcda75973934e9fd0aee4f375f1` |
| `components/phone-retained-20261006.sqlite` | 62 | 140 | `8d552ab974778b53d405d8e22d8db751ddf0f14b83b147a1d156a2e8c8608994` |

上表每个库均在input一致副本与密文实际提取库间比较schema、每表行数/列摘要/全部行类型化摘要，duplicates保留；所有字节也对比认证SHA。MCP账本、SMTP journal、i_memory、两手机快照只做隔离SQLite核验，未启动其服务/任务或在手机恢复。

### Core逐表结果

| 表 | 行数 | 全行指纹 |
|---|---:|---|
| `change_events` | 6967 | `b9d23d9128682df64b51ee4071166b1545809ebb9d848cac3e6b58bd8905113b` |
| `chat_messages` | 6967 | `9b29acb45b252af43bd783925340325e31ed13bd5965ce95f9c14bf4f129d9ab` |
| `companion_reply_jobs` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `companion_reply_shadow_runs` | 0 | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `consumed_pairing_codes` | 5 | `d6f72ad53ff60ee62300611102329ff53ff9b49e29aaa5fa22f016a8a57b88a4` |
| `core_metadata` | 4 | `dc669db90832e92ed75064a535630e6cf8a4a283726c8a13fc36de9090eaf872` |
| `devices` | 7 | `440efd55ad75d08ac0681e687365e9b04cbd6d6a93a3bfa88abf0bf728b875f1` |
| `sqlite_sequence` | 1 | `866289f8cb1d65ed5d2a2cbc35f25ff5afb1df0bd89feae0a0048194958bcb82` |
| `worker_leases` | 1 | `d1746ac61c5d3c4ffe89cd876403070bd265b947a0442ed6447d4bbf386e6691` |

## 演练明文清理

最终密文与DPAPI保管可用、52项认证和6库逐表比对完成后，主窗仅删除本轮新建的 `inputs`、初版与最终 inspection 目录。每个绝对目标先确认仍在私有根内且无reparse/link；没有删除原库、源配置、旧四输入密文或旧备份。私有根保留最终及初版密文、DPAPI、spec、指纹/汇总/清理回执。清理UTC为2026-10-06T04:39:01.0935548Z，现存目录不再含这些演练明文；本页启动/逐表核验记录来自清理前真实执行。

## 仍缺什么

1. **Tailscale机器身份/私钥未备份**：`C:\ProgramData\Tailscale`拒读，精确state路径不可核实，不是“不存在”。没有提升OS身份或修改其ACL。本轮已补当前serve状态JSON、服务配置/恢复策略，历史Funnel cert/key仅保留，不证明与现役配置绑定。无法把此清单宣称为异机完整Tailscale恢复方案；切换前需另取允许方式保全系统身份，或明确接受重新登录/重新配置的影响。
2. **DPAPI跨机/跨用户恢复未验证**：本次确实以原用户在本机解锁并恢复；Windows用户/profile自身备份不在九类API中。未来异机恢复需单独保管Windows/DPAPI上下文，不能只搬blob。
3. **现役原始DB/WAL/SHM/hot-journal与unclean首接未实现**：一致副本保留已提交数据，但不替代在停止后、任何SQLite打开前保全原始文件集及受审恢复。原始日志不是被删除或忽略；活跃读备份不据此授权迁移/退回。
4. **生产activity recovery floor/最新head尚未产生**：现役仍schema4。私有copy context仅绑定检查副本，已有5/6不得用它自签floor；新监督者首次接管、崩溃恢复、生产自启/Windows关机仍待源码Gate。
5. **手机时效**：保全前轮schema62一致副本与10/02历史schema60快照；最新设备变化及安装身份/账号恢复未重新核实。停机窗口前需对账最终手机状态，不能把历史快照混作新库。

## 审核入口

- [九类来源逐项元数据](SCHEMA6_BACKUP_COVERAGE_20261006.md)（worker调查时的found/pending状态，当前执行状态以本页为准）。
- [停启、电源事件与退回](SCHEMA6_RUNTIME_OPERATIONS_20261006.md)。
- [给Lynx的一页操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)。
- [主窗源码/固定候选验收](SCHEMA6_READINESS_SOURCE_ACCEPTANCE_20261006.md)。

本轮仅准备远端草稿PR后暂停审核，不合v3-lab、不部署、不装手机。
