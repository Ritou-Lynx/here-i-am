# R03 首份写入后备份与实际还原（2026-10-08）

## 结果与边界

北京时间01:35:03，已批单文件 ACL 应用成功；01:35:48 本机与 T9 完整加密备份成功；01:38:11 第二次 T9 实际隔离还原以 exit 0 成功；01:39:58完整 Node 回执复核及现役健康核对通过。仅修改批准 daily-backup-config.json 的DACL；owner、字节和六批准锚不变，固定运行包47物理文件不变。没有停启服务、改任务/生产配置内容、装手机、换MCP或切上传器。

**Core切换仍未完成。** 手机、claude.ai本人答“稍后测试”；真实关机→开机→登录留今晚，关机前须让MCP实际处理过请求。手动任务启动不是登录触发Gate。10/09 18:00截止与只向前修边界不改；10/09晚备份仍是另一次任务，不能把今天这份提前记成明晚已执行。

## 源码与精确 CI

单文件维护入口源码提交：a8d1c696406141ad1290312f15b56193c4e70f74，同一草稿PR #20，不合并。

- [push完整CI](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37655645772)：8/8 job completed/success。
- [PR完整CI](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37655683451)：8/8 job completed/success。
- [PR Policy](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37655674804)：success。
- 主窗实取push TAP：维护63/63、生命周期及备份294/294，均0 fail/0 skip；新增PS5专项35合成断言。真实提升→普通Prepare/COM链及另一Windows用户口令还原job成功。
- 本机最终专项2/2；独审回执歧义已修，独审无剩余阻断。原37/37属于首版相邻回归，不与最终专项混称。
- helper Git/LF字节eed9bee835591cf95f2daa2fc00931f20e13f704253cfb05b70170f15f3980ac；Hosted checkout CRLF字节70bb6b3f84e7745393c3b7e05c7197bf3acd65d5a68d0fed2214c3818dec866b，实际核对仅换行差异。固定47未据此换包或重锚。
- 本机CI证据SHA256 ed8122bdd95f88102730c14877cbd5a01c6f072a43179d92f9d47d6916b93efe。下面只补现场文档；源码/运行字节没有后续修改，文档按现有CI paths-ignore处理。

## 已批 ACL 实施

目标为批准settings内daily-backup-config.json，单文件protected、仅本人/SYSTEM Allow FullControl。普通本人身份执行，无UAC/提权、无owner改写。

| 项目 | SHA256 |
|---|---|
| 内容，前后不变 | d33106d26cf4c6e7c7f54e007e84bda869c0ce9c7b75a1377d98b321e4387cb5 |
| 原Access SDDL | 0d36b0b74b4eae218cbdf0681514d2363bb721e548918d5742a1da525f71a841 |
| 已批准/实际Access SDDL | 6b61fec3e35b247c9b5a067721dee36b5851847d0ddd4ca5353d0e7b2394dd72 |
| 实际process completion，exit0/terminal completed | 28626a8cf1ae782153dee3ebe9434ce0da836b528543a9ef699c85576707c37e |
| 固定生产Assert/六锚/父DACL后验 | 00bfe137d2a9abe2653effe113a57e25e08b954af52496c7aa468bf626290698 |

同柄身份、single-link、owner/group、字节、原/拟DACL、第二读柄均通过；original快照保留。落盘result仅非终态checkpoint，成功依据真实exit0及终态stdout。本次未触发恢复。回执独立ID acl-repair-11fb0108b59f40deaf68f22dc24bcc58，旧窗口锁/回执不删不复用。后验固定Assert-BackupPrivateAcl接受。初始599条/506唯一路径审计的唯一FAIL已精确修复；其他项仍保留原时点证据，不伪称重扫了全部路径。

## 完整备份

使用原固定package的scheduler_once/Automatic入口，现有本人DPAPI密钥；独立manual128输入，不改生产daily或login内容。此次临时输入补当前不可变head/floor/adoption event、原raw加密保全、实际三任务XML及SDDL；自动工具增加归档context/capture-window，最终130文件。九类原覆盖包括Core、grant、72 replay审批、MCP OAuth/writeback/前端与手机令牌、i_memory policy/快照、隧道/Tailscale配置、保留手机库副本及恢复密钥/旧包/任务资料；不含Tailscale机器私钥，按既定选择换机重新登录。手机库为此前留存副本，本轮没有从手机新取库。清单中的funnel证书相关.key路径沿用原受审证书范围，未扩展到Tailscale节点机器身份状态；机器身份仍不备份。

归档九个role计数（非把重叠业务类别强称九个文件）：

| role | 文件数 |
|---|---:|
| configuration | 86 |
| credentials | 8 |
| database | 1 |
| domain_policy | 3 |
| recovery_custody | 17 |
| release | 10 |
| replay_approvals | 1 |
| task | 3 |
| transcript_grants | 1 |

与用户关心组件对应的逻辑清单（只有路径名，无内容）：

- preserved/transcript-grants
- preserved/replay-approvals
- preserved/mcp-oauth.json
- preserved/mcp-core-frontend.json
- preserved/mcp-phone-feed.json
- components/mcp-writeback-sqlite.sqlite
- preserved/mcp-runtime-start-remote.ps1
- preserved/mcp-runtime-remote-launch.mjs
- preserved/tailscale-certificate-funnel.crt
- preserved/tailscale-certificate-funnel.key
- preserved/cloudflared-origin-cert
- preserved/i-memory-policy
- preserved/i-memory-policy-before-b3
- preserved/i-memory-pending-policy-decisions
- components/i-memory-sqlite.sqlite
- preserved/cloudflared-config
- preserved/cloudflared-tunnel-credentials
- components/i-memory-phone-snapshot-20261002.sqlite
- preserved/mcp-runtime-source-server.mjs
- preserved/mcp-runtime-source-mcp.mjs
- preserved/mcp-runtime-source-oauth.mjs
- preserved/mcp-runtime-source-writeback.mjs
- preserved/mcp-runtime-source-diagnostics.mjs
- preserved/i-memory-runtime-reader
- preserved/mcp-runtime-node
- tasks/HereIAm-iCore.xml
- tasks/HereIAm-iRemoteMCP.xml
- operations/tailscale-serve-status.json
- components/phone-retained-20261006.sqlite
- operations/Cloudflared-failure-policy.txt
- operations/Tailscale-failure-policy.txt
- candidate/settings/mcp.json
- candidate/settings/transcript-grants.json
- candidate/settings/replay-approvals.json
- candidate/release/tools/i_core/release_schema6/lifecycle/mcp_configuration.ps1
- candidate/mcp-source/tools/i_remote_mcp/server.mjs
- candidate/mcp-source/tools/i_remote_mcp/oauth.mjs
- candidate/mcp-source/tools/i_remote_mcp/diagnostics.mjs
- candidate/mcp-source/tools/i_remote_mcp/mcp.mjs
- candidate/mcp-source/tools/i_remote_mcp/writeback.mjs
- candidate/mcp-source/tools/i_memory/i_memory_read.mjs
- tasks/HereIAm-CoreSchema6-Session.xml
- tasks/HereIAm-iCore.current.sddl
- tasks/HereIAm-iRemoteMCP.current.sddl
- tasks/HereIAm-CoreSchema6-Session.current.sddl

本机job：manual-backups/first-postwrite-20261008-60f3e49a69d54de7a9ec750f23552578/bundles/daily-1791394523415-f750d895-7193-487e-9cef-634764a66a65。
T9：T:/HereIAmRecovery-20261007-1552e251/first-postwrite-20261008-60f3e49a69d54de7a9ec750f23552578/daily-1791394523415-a2cc57da-c9ba-4984-9709-c01ffef3bd74。
工件artifact/runtime.aes256gcm，两端均481348984字节，SHA256 c5b02e54cf100a8e5f910bc80afa17fba5509ea0250bbbc9a226cb8bcb7641a1。两端cipher/envelope/binding/receipt四文件逐一大小/hash一致，mirrored=true、mirrorPending=false；27.184秒。完成回执SHA256 5426f0e2baca6fb46b9a6d6119a1208dd97c6ea198c99dfe0b263ccbd8a8bbbd。独立manual配置SHA256 4c77031100f89c6291a5026a5141186bc316a46ddfd21b4650261762e27961a4。

## 从 T9 的真实还原

固定RestoreInspection从T9加密工件解密/提取到新的protected目录，真实Core以inspection_read_only在临时loopback端口启动，核对node_id、schema、设备、35表逐表行数/指纹；5条业务路由全部403，然后正常关闭，DB字节不变且无sidecars。不是只做hash，也不是启动恢复后的现役Core。原现役仍同node/schema6健康、端口持有进程不换。

首轮固定Node已经发布完整inspection回执，但主窗外围脚本误用了PowerShell自动变量Matches存放文件比较行，后续正则覆盖成整数键Hashtable，保存外层JSON时失败。保留首轮目录restored-T9-1affd647a7c2408a8dc6a6b6df83c955；没有伪造该次外层exit记录。仅改外围变量名，在全新restored-T9-d7c4b26245a84623b393ee06f964187b重做完整还原，实际exit0，19.940秒；两份Node DB/hash/data指纹一致，原目录未删除。

还发现原固定PS包装器stdout使用默认JSON depth，深层tables/idPrefixes会转字符串。本轮读取Node直接写出的完整.inspection-ready.json并交叉核对；没有改运行字节。此为后续报告序列化源码修复项，不是归档或DB数据丢失。最终外层进程回执SHA256 61cca4bbda85858fb49d66fef1e83a5138afcc6489c382d221da51f21ef21263；完整Node后验6153a30088e40731a3354d25d52482194b21cbbd3617d1d44d63f6bcf0914cd5。

schema=6；node前缀9d634309；设备7（只核对计数/前缀/指纹）；chat_messages/change_events各7062。
DB字节SHA256 3a80539527d4ce9c6c3ca706c791bee6b58861b9fd26fec42fa24fb854c3fb9f。
总data指纹eb6b4dec953e6253b5316b2bb109425df7b1c4ef8c5f11b8e8efdf4be3278465，与portable binding一致。

| 表 | 行数 | SHA256 |
|---|---:|---|
| activity_audit | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_changes | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_credentials | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_deletion_receipts | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_event_tombstones | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_events | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_metadata | 13 | 0bb9ac2032b5f6438b7587b5d8adf0c1bd05adb5065b61d17ecbb90536734436 |
| activity_principals | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_probe_state | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_projections | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_rate_limits | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_reader_acks | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_replay_lineage_floors | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| activity_runtime_claim | 1 | 798ae0723de12cb5edc18ae9bc92cc2ed6990f972666273e53e65d48ed417ffa |
| activity_schema_migrations | 1 | 735e66966c60d6ce66c6ac36fbf28e9650b344a739377230d8159bc9fdfa31e3 |
| change_events | 7062 | 4b1b2503073901048ddbed308aa8cd8ac9a4d9584fd9204e0f6a6043f2fc2bdc |
| chat_messages | 7062 | 7043c4c01c7dbbbcf59f3114d06240a6ab0dc2dd01cdca637f13e6927d6d60f5 |
| companion_reply_jobs | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| companion_reply_shadow_runs | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| consumed_pairing_codes | 5 | ec3b275d910d04edd5c518af1119c811eaf31b134aa5e588bbad83c53ddadd29 |
| core_metadata | 5 | d3e7769f55f32174306348e82a2fd5324eb20da1764568c5148ec5b6831d9a60 |
| devices | 7 | 6a86a1cc836d5392581edf5258be1bdf72a0d0b85ef90d0f0dfec7b823aa1fd4 |
| domain_changes | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_consumer_acks | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_op_payloads | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_ops | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_phone_capabilities | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_principals | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_purge_jobs | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_receipts | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_records | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_registry | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| domain_schema_migrations | 1 | 38cf66672e074599d88c8c68f648fca36e1530bc8234dbb16061edd8f0bb5632 |
| domain_snapshots | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| worker_leases | 1 | f993bee65b2a771400bf8cca409317280898f5a8e2bc70ed6c77612b90e20720 |

## 待办

- 手机同步、claude.ai写入及今晚真实关机→登录四项Gate未完成；先让MCP处理实际请求，再关机。不以备份/CI代替。
- 定时调度的下一轮尚未观察；本次是同一固定工具的手动Automatic调用，不能改写旧worker_failed历史或称调度已自动重试。
- 原生产daily静态清单不随head演进自动收集独立证明，也不自动导出新任务定义；本次manual已补齐当前链。后续有界动态恢复链/任务导出及固定PS JSON深度修复需单独源码审查；涉及47字节须另审候选，不在本轮偷偷更新。见[路径审计第7节](SCHEMA6_RUNTIME_PATH_ACL_AUDIT_20261008.md)。
- 本次用本人DPAPI实际还原；不宣称当前工件已做另一用户口令实还原或可直接激活新现役。换机重绑新DPAPI、独立恢复密钥/current-head/配置路径仍为已知下一轮缺口。
- 生产task-approval/settings中的login配置不可清理，未来换包再迁正式目录。P1/B不集成到本运行包，手机/新版MCP/上传器/47862切换授权不扩展。
