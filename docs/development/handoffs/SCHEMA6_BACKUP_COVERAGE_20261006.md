# Schema 6 九类备份覆盖清单（2026-10-06）

## 主窗执行后的状态

本页以下保留04:23–04:27 UTC只读调查时的历史found/pending清单。主窗随后实际完成**52文件、九类加密保全与真实只读Core恢复**，并补当前Tailscale serve状态和两服务失败恢复策略；所有6个数据库全部表一致。执行结果、外锚及仍缺的Tailscale机器身份见[真实恢复回执](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)，不能把下文历史“待复制”误作最终状态。

## 调查时结论与边界

本 worker 仅做授权目录的只读元数据调查，拥有本文件；基线 `codex/core-supervisor-ready-20261006@7e66311e4608bff1c828e9ae38f7b185cc221938`。开工发现的 release_schema6 七项外来修改不暂存、不修改。没有停启服务、修改现役配置/数据库、设备操作、创建真实数据副本或解密凭据。本清单不是实际备份 spec，也不是生产 clean-stop 或部署接受证据。

旧四输入加密备份实物和预期 SHA 已匹配；新九类完整备份尚待主窗执行。源码完整备份 23 项测试属于合成验证，不能把其通过算作用户真实数据九类已备份。参考 [源码备份实现交接](SCHEMA6_FULL_BACKUP_20261006.md) 与 [原四输入验收](POST_AUDIT_SOURCE_ACCEPTANCE_20261006.md)。

采集窗口约 2026-10-06 04:23–04:27 UTC，各文件逐次读取；现役服务仍运行，跨文件/跨数据库没有共同原子快照。SQLite 内容未查询；正文、配置值、token、密钥、原始 XML/日志未输出或入 Git。下表哈希是单个文件在本次读取时的字节哈希，不自动代表应用状态一致性或当前加载状态。

## 九类角色与追加组件

| role | 真实来源与本次状态 | 主窗后续要求 |
|---|---|---|
| database | Core `.state/i-core.sqlite` 已找到；main/WAL/SHM 普通文件哈希遇共享 IOException。旧四输入密文中有历史一致副本，不能算当前副本 | 活跃 writer 下用 SQLite 只读连接 online backup API 输出私有一致副本；不要直接复制 main/WAL 冒充一致 |
| release | 现役固定包 `b3-v4-phone-transcripts-20261003` 10 个文件已哈希（9 个库存文件加 manifest），尚未新备份 | 保存完整包与精确 manifest；逐项核其清单，不用当前源码替代现役字节 |
| configuration | SMTP 配置、MCP 启动入口、Cloudflared 配置及附加组件已找到待复制 | 稳定读取并记录捕获窗口；敏感运行脚本同样进入受保护密文 |
| task | `HereIAm-iCore`、`HereIAm-iRemoteMCP` 均 Running；任务 XML 仅在内存导出并计算 UTF-8 哈希，尚未保存 | 将精确任务 XML 作为独立制品；不能只保留任务名；另保存 Cloudflared/Tailscale 服务配置 |
| credentials | SMTP DPAPI clixml、OAuth JSON、frontend/phone-feed JSON、隧道凭据与证书已找到 | 稳定快照、保留恢复所需路径/用户上下文；不显示或复制明文进仓库 |
| domain_policy | i_memory 当前 policy、pending decisions 及旧 policy 备份已找到；schema6 新域现役启用配置未独立核实 | 保全实际 policy；缺省/禁用项需要真实配置依据，不可捏造 disabled 证据填角色 |
| transcript_grants | 外置 local-transcript-grants.json 已找到并哈希，待当前复制；既有验收曾核 1 条 | 保留当前凭据绑定；旧四输入密文里有历史副本但不替代当前 |
| replay_approvals | 外置 historical-replay-approvals.json 已找到并哈希，待当前复制；既有验收曾核外置/durable 各 72 | 外置原件与当前 Core 一致副本耐久账本都保留；本次未重读内容，不重报实时 72 一致 |
| recovery_custody | 旧密文、两份 DPAPI key 文件及加密迁移副本实物均已哈希；新 schema6 custody 只在源码合成夹具验证 | 保留原 DPAPI 用户/路径/熵上下文；备份用 key 与生产 activity recovery floor 的权威不同，旧 key 文件不能冒充新 floor |

追加范围必须显式覆盖：MCP `.state` 中 OAuth（实物是 JSON）、writeback SQLite、frontend/手机 pull tokens；i_memory policy、数据库与快照；Cloudflared/Tailscale；手机数据库副本。单个源文件不得重复贴多个 role 填空。本 API `database` 为单例；MCP/i_memory/phone 等辅助数据库可封装为命名清晰的独立 `configuration` 制品，但应标识其组件/SQLite 语义，或后续扩展显式组件标记。本 worker 不改 API。`release` 会核 Core 旧包精确库存，MCP 运行源码依赖不能混入此 role 冒充旧包库存。

## 已存在的真实备份与缺口

- 旧四输入密文 `original-backup.aes256gcm` 为 37,069,379 字节，SHA256 `3b7f9102229dea7d57d13bbbe1c2fcd6430a20b420d9bdd669ed182bdba1429c`，与原验收吻合。原验收覆盖手机/Core/两份外置授权并曾完成 DPAPI 恢复后内存解密逐项验证；本轮只核实实物/哈希，没有重新解密或证明当前数据已包含。
- `original-backup.key.dpapi` 为 262 字节，SHA256 `cd6340ea085b811e46f60ba5c2839666664e46837ef23ce8f8b80152c5cccf74`；迁移备份另有 `core-backup.key.dpapi`，262 字节，SHA256 `b05e268dc9628c99d5d688055eee7b2c07f4451e387c38392369e4318b564e4c`。两者不可互相替代。仅找到 DPAPI blob 不能证明跨机器恢复。
- i_memory `policy-before-b3-20261003.json` 及 `v3-export/export-2026-10-02T16-43-19-893Z-ZkFPQ1/snapshot.sqlite` 是已有备份/快照，已哈希。后者 64,012,288 字节，属于 10/02 历史手机输入，不代表本轮手机状态。原 10/05 手机一致副本根据原验收清理了明文，仅保留四输入密文；本次没有读取或操作手机。
- `C:\ProgramData\Tailscale` 在现用户只读权限下拒绝访问。`LocalSystem.state` 精确路径查询报未找到，但父目录不能列出，故状态是不可核实，不能推断文件不存在。未提升 OS 身份、改 ACL 或输出机器私钥。现役 Tailscale/Cloudflared 服务均 Running/LocalSystem；服务进程可执行路径部分不可读。Funnel 证书文件只是已找到的历史副本，未证明与现役 serve 配置绑定；Tailscale 当前 serve/funnel 配置及机器私钥备份仍缺。
- Cloudflared 已找到 `C:\ProgramData\cloudflared\i-mcp\config.yml` 与 `i-mcp.json`；原账户 `.cloudflared/cert.pem` 也存在，但当前使用绑定未验证。未查询外部账户或网络控制台。
- 现役 MCP `.state` 普通沙箱读取被拒，随后获只读沙箱外访问后可列/hash；这是沙箱访问差异，不是数据不存在。`D:\memex\tools\i_memory` 本地路径不存在，实际入口引用的是 C 现役副本。

## 私有机器清单与处理规则

清单位置：`%TEMP%/hereiam-schema6-inventory-20261006/inventory.json`，48 项，SHA256 `e1fded2e61a038bea16015443aa0477183bbb2397a9a63be18b072c36c4bd551`。新目录使用当前用户与 SYSTEM 的受保护 ACL；JSON 仅含路径、role、name、hash、size、mtime、状态/错误类型，未含配置值或正文。清单里的 role 是建议分配，尚不是可执行备份 spec；其中 `scheduled-task:` 是来源标识而不是磁盘文件。

主窗应读取私有清单、创建受保护的真实快照/导出，重新计算实际输入 hash，再构造 spec。对在线 SQLite 用只读 backup API；对活跃 OAuth JSON/授权/policy 等用稳定文件读锁或可检验的前后 hash/mtime 捕获，不把直接复制活跃文件称为一致。静态文件读取不能推出与数据库同一事务。捕获期间保存各组件开始/结束时间、源到副本映射和独立验证结果；不能从本次只读保存推导生产 writer 已 clean-stop。

## 路径别名

- CORE = `D:\memex\tools\i_core\.state`
- REMOTE = `C:\HereIAm\continuity-b0-b2-20261002\tools\i_remote_mcp`
- MEMORY = `C:\HereIAm\continuity-b0-b2-20261002\tools\i_memory`
- OLD = `%TEMP%\hereiam-post-audit-private-20261006`
- RELEASE = `D:\HereIAmRuntime\i-core\candidates\b3-v4-phone-transcripts-20261003`

## 逐项元数据

下表“待快照”不等于已备份；共享锁受阻者仅有文件元数据。完整 UTC mtime 与机器可读状态保留于上述私有清单。

| name / 来源 | role | bytes | SHA256 | 状态 |
|---|---|---:|---|---|
| `core-live-main` / `CORE\i-core.sqlite` | database | 10330112 | `未取得（共享锁）` | found_hash_blocked_sharing_requires_sqlite_backup |
| `i-core.sqlite-wal` / `CORE\i-core.sqlite-wal` | configuration | 4136512 | `未取得（共享锁）` | found_hash_blocked_sharing_requires_sqlite_backup |
| `i-core.sqlite-shm` / `CORE\i-core.sqlite-shm` | configuration | 32768 | `未取得（共享锁）` | found_hash_blocked_sharing_requires_sqlite_backup |
| `transcript-grants` / `CORE\local-transcript-grants.json` | transcript_grants | 273 | `31edb663bc907df2a2d4501296508b0efb431d3234600657b1b80caae2ac2a42` | found_pending_stable_copy |
| `replay-approvals` / `CORE\historical-replay-approvals.json` | replay_approvals | 21185 | `de0dab298fdc56d8c34c05f5e059e4a4cbea6f9aa60f61415583d93b4ba916fe` | found_pending_stable_copy |
| `smtp-relay-configuration` / `CORE\shortcut-mail-relay.json` | configuration | 674 | `a053826e3e1722cde84055d7ce77b90a21ce5d211a572cbf1b49a44573b1f175` | found_pending_stable_copy |
| `smtp-dpapi-credential` / `CORE\shortcut-mail-smtp.credential.clixml` | credentials | 1862 | `5cc2b8eb21f54d378208b4450b171798ecad328f546c7014990f9634028c2a73` | found_pending_stable_copy |
| `smtp-journal-sqlite` / `CORE\shortcut-mail-journal.sqlite` | configuration | 4096 | `2fb9e76bc8b8bb820a77e21342abe7b079f687749503315e13c0cf95106675e0` | live_requires_sqlite_backup |
| `mcp-oauth.json` / `REMOTE\.state\oauth.json` | credentials | 9916 | `f00c69e72a3e3d825281386f39bac60c1d64a764b83f8d931a8d46ce04de516f` | found_pending_stable_copy |
| `mcp-core-frontend.json` / `REMOTE\.state\core-frontend.json` | credentials | 207 | `34549aec6936b991b8f6bd5c2a1fa0e41aeaa8b48c5b3ddb269df02b549197d3` | found_pending_stable_copy |
| `mcp-phone-feed.json` / `REMOTE\.state\phone-feed.json` | credentials | 132 | `45e9495f962cd7221136cddad2f24bab0eba696866d3f318831fe08fc74d0fd0` | found_pending_stable_copy |
| `mcp-writeback-sqlite` / `REMOTE\.state\writeback.sqlite` | configuration | 167936 | `未取得（共享锁）` | found_hash_blocked_sharing_requires_sqlite_backup |
| `mcp-runtime-start-remote.ps1` / `REMOTE\.state\runtime\start-remote.ps1` | configuration | 1300 | `7557cdedbef33dd3d53b6655baef542e576653f45127893ff482b50521600799` | found_pending_stable_copy |
| `mcp-runtime-remote-launch.mjs` / `REMOTE\.state\runtime\remote-launch.mjs` | configuration | 8831 | `351070bd09caaa5ab5b7780ab91a4c75c9baaf824eb117fef13fb286ed8b5ec7` | found_pending_stable_copy |
| `tailscale-certificate-funnel.crt` / `REMOTE\.state\tailscale-cert-check\funnel.crt` | credentials | 4829 | `3c355e89b5a72969d3ab9fd0fa13b463b84641111f8e4a37c89147d172ef0437` | historical_copy_current_use_unverified |
| `tailscale-certificate-funnel.key` / `REMOTE\.state\tailscale-cert-check\funnel.key` | credentials | 227 | `0467da376825f76a51f8833392c27a4863193d15d83bd64bcdddadc1ea03d4f3` | historical_copy_current_use_unverified |
| `cloudflared-origin-cert` / `C:\Users\Lynx-DB\.cloudflared\cert.pem` | credentials | 282 | `ab0d2888af7f57bf9a6edd29867ea56c30f44b378f0dbb644f3bb784593df517` | found_current_use_unverified |
| `i-memory-policy` / `MEMORY\.state\policy.json` | domain_policy | 806441 | `3ecf62026c4f2f80e2be7591ad0031164cfdb2eb6632d50e467111d337d9537f` | found_pending_stable_copy |
| `i-memory-policy-before-b3` / `MEMORY\.state\backups\policy-before-b3-20261003.json` | domain_policy | 806036 | `3b9d02e797d4753be798c2845ca1d749593e6ef357c5d3d75f718b381d1dcf17` | existing_backup_hash_verified |
| `i-memory-pending-policy-decisions` / `MEMORY\.state\policy-decisions.pending.json` | domain_policy | 503 | `afb0591c7df404d95e6491cce8e5ec58dd8a914e9ddd9b7f4e95ba062c0fc2e3` | found_pending_stable_copy |
| `i-memory-sqlite` / `MEMORY\.state\i-memory.sqlite` | configuration | 831488 | `820cf94eaf47940726bbc10609723c33f8832f507a8a82696417bc9582259149` | requires_sqlite_backup_or_stability_proof |
| `original-backup.aes256gcm` / `OLD\original-backup.aes256gcm` | recovery_custody | 37069379 | `3b7f9102229dea7d57d13bbbe1c2fcd6430a20b420d9bdd669ed182bdba1429c` | existing_backup_hash_verified |
| `original-backup.key.dpapi` / `OLD\original-backup.key.dpapi` | recovery_custody | 262 | `cd6340ea085b811e46f60ba5c2839666664e46837ef23ce8f8b80152c5cccf74` | existing_backup_hash_verified |
| `core-backup.key.dpapi` / `OLD\core-backup.key.dpapi` | recovery_custody | 262 | `b05e268dc9628c99d5d688055eee7b2c07f4451e387c38392369e4318b564e4c` | existing_backup_hash_verified |
| `ae4cf1b2-5870-42be-a1dd-358539927f34.manifest.json` / `OLD\core-encrypted-backups\ae4cf1b2-5870-42be-a1dd-358539927f34.manifest.json` | recovery_custody | 719 | `2cb2c96ac1694702f63712e51f51bfcfa2187dcd4aecd90ef3638d78deda8ab1` | existing_backup_hash_verified |
| `ae4cf1b2-5870-42be-a1dd-358539927f34.sqlite.aes256gcm` / `OLD\core-encrypted-backups\ae4cf1b2-5870-42be-a1dd-358539927f34.sqlite.aes256gcm` | recovery_custody | 10731556 | `0a326d19c9242a05d211df3e5c0e4357b73888593ce1c03f753588068245904f` | existing_backup_hash_verified |
| `manifest.json` / `RELEASE\manifest.json` | release | 2988 | `117c584a7625029526d5f5e0d730dba5c0a9023a8ab32eb07d1900d2ec8a2d50` | found_pending_stable_copy |
| `start_pinned_i_core.ps1` / `RELEASE\start_pinned_i_core.ps1` | release | 8460 | `55ccaa5369687b3c3d9c888cc296b4d4ea16d8fdf3b0eb6dd8dbd97a3cf1b90f` | found_pending_stable_copy |
| `verify_v4_state.mjs` / `RELEASE\verify_v4_state.mjs` | release | 4015 | `cf7a1dadc6e5cc774aa8e3c4a869cd1eeeade9e4687d8a8b2be382dbb04dec37` | found_pending_stable_copy |
| `runtime\node.exe` / `RELEASE\runtime\node.exe` | release | 91426304 | `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f` | found_pending_stable_copy |
| `tools\i_core\i_core_server.mjs` / `RELEASE\tools\i_core\i_core_server.mjs` | release | 15592 | `9ac97b01711bc580861f5d3aa2308846dad7606f5d28b4ba02939db83c269d46` | found_pending_stable_copy |
| `tools\i_core\i_core_store.mjs` / `RELEASE\tools\i_core\i_core_store.mjs` | release | 57471 | `acf2628af7c9188bcc127aa57387a39d60a80a82796b771f8fe920227e7bdc6a` | found_pending_stable_copy |
| `tools\i_core\send_shortcut_mail.ps1` / `RELEASE\tools\i_core\send_shortcut_mail.ps1` | release | 15003 | `0766737642349896379d545a22ca974ef0933ef514261ab9079642fc35d70919` | found_pending_stable_copy |
| `tools\i_core\shortcut_mail_relay.mjs` / `RELEASE\tools\i_core\shortcut_mail_relay.mjs` | release | 18170 | `841756bb88cee7eb406e9dd682e8eb547dc3c144d7bb8c1e68659e3c55cf9185` | found_pending_stable_copy |
| `tools\i_core\start_i_core_service.ps1` / `RELEASE\tools\i_core\start_i_core_service.ps1` | release | 3123 | `e39115cc96ff520e3fbf1beb638d6f04a1a72a53c0a00959fe7949d91c895724` | found_pending_stable_copy |
| `tools\i_core\strict_smtp_tls_validation.ps1` / `RELEASE\tools\i_core\strict_smtp_tls_validation.ps1` | release | 29384 | `395e1c810f186a4136ad8b16ee4734e32322a4ba8064508f034ee0f21b6812ed` | found_pending_stable_copy |
| `HereIAm-iCore` / `scheduled-task:\HereIAm-iCore` | task | 1978 | `483ea2bb0245ffd2da71c3568b0dd1a88eb312668b5ecec6d2612668146c188a` | in_memory_export_hash_only_pending_actual_backup |
| `HereIAm-iRemoteMCP` / `scheduled-task:\HereIAm-iRemoteMCP` | task | 1800 | `078ac9c0e580f031dd5376ab7e4374d9f1986d464a80078bed7782aaa9fb1b6b` | in_memory_export_hash_only_pending_actual_backup |
| `cloudflared-config` / `C:\ProgramData\cloudflared\i-mcp\config.yml` | configuration | 321 | `4590c4aa951c51ec930afd2436d3fc733c8cfd5a450c35f3097df50a79579aae` | found_pending_stable_copy |
| `cloudflared-tunnel-credentials` / `C:\ProgramData\cloudflared\i-mcp\i-mcp.json` | credentials | 175 | `c131f85d2d005982f6d209edd11305675fed47a4f35aa5f45ee73ea4daeeeffa` | found_pending_stable_copy |
| `i-memory-phone-snapshot-20261002` / `MEMORY\.state\v3-export\export-2026-10-02T16-43-19-893Z-ZkFPQ1\snapshot.sqlite` | configuration | 64012288 | `0626d320215b39d43ee27569fed7e8a6dcc54b2699d0fd9140c8c0c52cd592c5` | existing_snapshot_hash_verified_not_current_phone |
| `mcp-runtime-source-server.mjs` / `REMOTE\server.mjs` | configuration | 22374 | `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6` | found_pending_stable_copy_component_archive |
| `mcp-runtime-source-mcp.mjs` / `REMOTE\mcp.mjs` | configuration | 20159 | `4bdd55dd3bd41e4ff0e16cdce08b2c58dce007d6fe6eaee51cc2110cdfc7d09b` | found_pending_stable_copy_component_archive |
| `mcp-runtime-source-oauth.mjs` / `REMOTE\oauth.mjs` | configuration | 19860 | `53dda48003b8b0b7da27c7a10895f31863398e1c42fe5e5ed017608f129755b5` | found_pending_stable_copy_component_archive |
| `mcp-runtime-source-writeback.mjs` / `REMOTE\writeback.mjs` | configuration | 29165 | `f2aac48db1cf61a44a0c9b5b28087b90894f03396cd52830a4428532944bc52a` | found_pending_stable_copy_component_archive |
| `mcp-runtime-source-diagnostics.mjs` / `REMOTE\diagnostics.mjs` | configuration | 5030 | `b60230926d0fa8cbcf2cbfefa5667656190507d828fc953605837d8f04e5b4f7` | found_pending_stable_copy_component_archive |
| `i-memory-runtime-reader` / `MEMORY\i_memory_read.mjs` | configuration | 21378 | `cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28` | found_pending_stable_copy_component_archive |
| `mcp-runtime-node` / `D:\Nodejs\node.exe` | configuration | 91426304 | `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f` | found_pending_stable_copy_component_archive |

## 验证与提交

仅做路径/实物/hash/权限元数据核验和文档 diff 检查，不运行 App 构建或把旧测试重新算作真实恢复证据。按隔离 worker 例外，提交仅此文档，一次性 SKIP_PROJECT_STATE=1 并在 finally 恢复环境；全局 DEVLOG / I_PROJECT_STATE 与最终 closeout 由主窗整合。未 push。
