# W1 R01：授权真实 schema4 一致副本 4→5→6 演练（2026-10-05）

## 验收范围和结果

用户先明确授权 schema5 本机副本验证；只读发现现役库 schema_version=4、八张旧业务表、没有 activity 后，用户再次明确批准“副本 4→5→6 演练”。现役库始终只读，服务持续运行。本轮成功验证的是**真实 schema4 一致快照派生的新空 activity schema5，再验证 5→6**；不伪称现役库原先为 schema5，也不覆盖已有真实 activity 历史的恢复场景。

[安全机器回执](W1_R01_REAL_COPY_VALIDATION_20261005.json)只含结构、校验布尔结论、候选源码 SHA 和本次演练标识，不含行内容、账号标识、库路径或密钥。

## 方法和实际检查

1. 在仓库外创建新私密目录，禁止路径链接，ACL 仅当前用户、SYSTEM、Administrators。Python SQLite mode=ro + query_only + 明确读取事务，用 backup API 获取包含提交 WAL 的一致快照；不直接复制正在运行的 main/wal 文件。源与快照在同一读截面比较八表 DDL、完整行哈希、sqlite_sequence、user_version，并通过 integrity / foreign-key 检查；结果相等。
2. 保留不动的 schema4 快照，只在独立派生文件调用本次候选 ICoreStore，显式 activityEnabled=false、activityAutoActivate=false、companionReplyJobsEnabled=false。不启动 HTTP、运行时 claim、自动任务或业务写入。
3. 4→5 后八表 DDL、原七张业务表完整行、旧序号、user_version 保持；core_metadata 精确只允许 schema_version 4→5 与新增 activity_schema_version=5，其余原键值全部保留，包括 node_id、cursor_secret 和已有 replay 元数据。新 activity 无业务行，runtime claim 为空且 fence/lease=0。
4. 在刚受控构造并证明为空的新谱系生成 recovery floor，关闭派生库、checkpoint/切 DELETE 日志、确认无 sidecar，再复制到不同路径的 candidate。floor 证明来自本次受控来源链，不从未知历史候选自身自举。descriptor 的停写证明只针对从未运行的派生文件，原 Core 没有被停止。
5. 调用正式 validateDomainMigrationCopy 适配器：候选仅读字节，fresh scratch 保留来源绑定且持久化两份 backup_read_only marker，独立 AES-256-GCM/HMAC 自动备份验证成功，同事务创建 12 张新领域表并完成 5→6；旧表/身份/来源绑定保全，candidate 字节未变，scratch 精确清理。
6. 本次自建三个明文库及临时复制回执已清理，剩余加密备份/独立 32 字节密钥仅保存在私密本机目录。备份 expiry 为 30 天，清理工具需 fresh owner apply，并非已配置自动清理计划；不声称物理抹除。主窗复核受限 ACL、无剩余明文库、原库仍为 schema4、原 Core/MCP 进程仍存活。

## 仍需独立验收

演练成功不授权升级线上库、切换源码、部署或安装手机。当前新 Store 保全数据库内 transcript/chat/replay 元数据，但没有现役固定 v4 包的全部 transcript/replay 执行功能；外置授权文件不在 DB 副本内。线上替换前须单独完成源码功能对齐、发布/回退及真实设备 Gate。已有真实 schema5 activity 历史未提供，本轮不声明其恢复验证完成。

本证据绑定机器回执的 13 份候选源码；未来合入 42 项修复后 W1 源码变化，应按最终组合重新绑定必要验证，不继承本轮哈希为新版本验收。
