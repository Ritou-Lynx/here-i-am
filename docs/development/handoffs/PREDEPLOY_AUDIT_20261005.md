# 部署前只读调查（2026-10-05）

## 1. 结论和证据边界

本报告绑定 **正式净化谱系 v3-lab@8dde12b312ad83f7475df8bd99a359f1b2d782d6**，调查分支 `codex/predeploy-audit-20261005`。指定源码/报告目录为 `C:\HereIAm\predeploy-audit-20261005`，开工 Git status 为空，未切分支。调查时间约 **2026-10-05 22:59–23:15（Asia/Shanghai）**；时间戳字段保留毫秒原值，日志时间为 UTC。

结论：

1. 现役 Core 的 Node 进程真正指向固定包 `b3-v4-phone-transcripts-20261003`，不是调查分支源码。健康接口、原库只读一致快照均为 schema 4，健康 node_id 与该库一致。固定包全部 9 个库存文件 SHA256 与 manifest 一致。
2. 固定包的受限 Android transcript 接口和保护实现仍加载，外置 grant 与 72 条 historical replay 不可变绑定仍存在；这是实现和配置状态，不是近期客户端调用或 replay 例外命中的证明。当前基线没有对应 transcript 路由或 replay 保护执行代码。**保住 DB 行不等于保住授权和行为。**
3. W6 的 Android 来源 companion 数量仍为 **10**。7 条旧回复在一次短窗口连续入库，随后 3 条与用户消息交错；这强支持 B3 手机 backlog 补交及随后 transcript 上传的归因，但仍是推断。标准 `import_v3_chat` 的来源和时间不吻合。没有逐请求路由审计，不能排除未留下记录的本机维护调用，不能写成实机逐条证明；当前持续调用仍未知。
4. 当前基线已经包含 PR10 的 companion outbox/服务端手机能力；它走普通 chat/messages，**没有** B3 transcript/网页 notes 拉取接线。B3 手机源码 schema 为 **62**，当前基线 schema 为 **60**，没有 onDowngrade 实现。直接安装主线候选存在本地 DB 降版本与功能退化风险。
5. 本次 ADB 在普通视图及宿主权限下都返回 **0 台设备**。当前实机 versionName/versionCode、安装时间、base/split APK SHA256、当前开关及手机 import 回执均未验证。本机 APK 与历史 8770aa60 构建/安装记录哈希一致，不能冒称它现在仍安装在主力手机。
6. i_remember 旧账本仍只有 1 条 deleted/on_phone；手机消费者代码找到了，位于未进入本基线的 B3 分支。回执能证明账本曾被 ack，不能独立证明当时请求由哪一个硬件/哪段 App 代码发出。

本轮没有停启服务、改线上配置、升级库、装/启动手机 App、改开关、改源码、push、PR、合入 v3-lab 或改 DEVLOG/I_PROJECT_STATE。仅新增及验收修订本报告，并按用户授权提交本调查分支。真实正文、凭据、token、数据库及原始日志不进入报告或 Git。未派生子 Agent。

### 1.1 方法

- SQLite 原库用 Python `mode=ro`、`PRAGMA query_only=ON` 和读取事务打开，再用在线 backup API 备份到 **进程内 :memory:**。聚合与白名单列查询在一致内存副本中进行；关闭连接即释放，没有新增磁盘明文库。不是复制活跃 main/WAL。
- Core 快照 integrity_check=ok；8 张业务表（另有 sqlite_sequence）与 schema_version=4。未打开正文列做语义判断；backup 在本机内存复制完整页，输出只含结构/计数/指定元数据。
- 进程和计划任务先提取可允许的脚本/可执行文件路径、PID、时间；未输出原命令行、环境或秘密参数。
- 日志在本机解析并聚合；仅计数、时间、白名单工具/端点。近 30 天窗按 2026-09-05 至 2026-10-05 取证；可找到的现役 remote 诊断日志集中在 10/02–10/05。没有全量 30 天 HTTP 调用审计，缺日志均写“未发现调用”，不推断无人使用。
- 默认命令入口初期返回慢；显式 PowerShell 后可正常读取。曾运行 doctor 只读诊断，未修配置、更新或改变 Defender。受保护进程/授权文件读取使用了已授权的只读权限提升，没有自动审批拒绝。
- `i_bootstrap` 自动识别的是任务默认目录的 ephemeral 项目；没有拿它替代源码目录核验，也没有切换项目或写项目 closeout。按委派要求由主窗负责全局交接。

### 1.2 已阅读的背景

以本基线文件为准：[ADR](../PERSONAL_DATA_HUB_ADR_20261005.md)、[领域约定](../I_CORE_DOMAIN_CONTRACT.md)、[分派验收](DISPATCH_ACCEPTANCE_20261005.md)、[R01](W1_R01_REAL_COPY_VALIDATION_20261005.md)。分派验收第 23 行与 R01 第 20 行的 transcript/replay 缺口本次现场证实。

ADR §11 的手机回复入 Core、notes 迁入 Core、手机为唯一执行者等决定已经确认，不在本报告重新要求决定。ADR §2、§8.4 的“手机 replies/notes 尚无实现”描述只适用于当时仓库，不能当作现役 B3 事实；当前基线 PR10 也已经改变了部分源码事实。

## 2. 现役加载证据与源码差异

### 2.1 进程、入口和状态目录

| 对象 | 本次核实 |
|---|---|
| Core Node | PID 12064，父 PID 22704；创建 2026-10-05T02:49:29.867487Z；可执行文件为固定包 `runtime/node.exe`；脚本为该包 `tools/i_core/i_core_server.mjs` |
| Core wrapper / 任务 | PID 22704；`HereIAm-iCore` Running；指向 `D:\HereIAmRuntime\i-core\candidates\b3-v4-phone-transcripts-20261003\start_pinned_i_core.ps1` |
| Core 数据路径 | wrapper 的白名单 StateDirectory=`D:\memex\tools\i_core\.state`；启动器第 148–158 行设置 I_CORE_DATABASE/loopback 后启动；健康 node_id 与这里原库一致 |
| Core 监听 | 127.0.0.1:47841 → PID 12064；健康协议0.1、schema4；worker/jobs 特性未出现在健康 features |
| Remote MCP | PID 22260，父 PID 22648；创建 2026-10-05T02:49:22.380545Z；实际脚本 `C:\HereIAm\continuity-b0-b2-20261002\tools\i_remote_mcp\server.mjs` |
| Remote 监听 | 127.0.0.1:47860、47862 均归 PID 22260；47862 在现役 server.mjs:249–273、505–509 为 remember 手机 feed。旧的47862用途线索不作为当前状态，本次以端口所有者和现役代码为准 |
| Remote 任务 | `HereIAm-iRemoteMCP` Running；入口为上述运行副本 `.state/runtime/start-remote.ps1` |
| i Gateway | 活跃 Node 进程指向 `C:\Users\Lynx-DB\.i\runtime\i_mcp_server.mjs`；Codex配置也指向此文件。不是 D:\memex 当前修改中的网关源码 |

固定包 manifest SHA256=`117c584a7625029526d5f5e0d730dba5c0a9023a8ab32eb07d1900d2ec8a2d50`。声明 source_commit=`bbb8025d99fc0acaa846d58b4e5a94cef90f8756`、source_mode=v4-b3-backport、patch=`2d92a8d74828fa2513bf1a7cb5c4ab233e757f3a`、transcript patch=`05112dde34673018f30bb222d4a94ec505498a5e`。这些是发布清单的来源声明，不把旧私人谱系当成本次源码基线。

证据强度：进程路径 + wrapper 参数 + 任务动作 + 端口所有者 + 健康/DB节点一致 + 启动器的精确清单守卫 + 文件最后写入早于进程创建。未对进程内存里的模块字节做 dump；“磁盘哈希一致”与“进程路径绑定”分别记录。

### 2.2 固定包对基线的全部库存差异

下面比较**磁盘实际字节 SHA256**。ABSENT 表示此基线没有该路径；全部运行文件符合其 manifest，6 个共享源码文件都不同，3 个包专有文件不存在于仓库。

| 路径 | 固定包 SHA256 | 基线磁盘 SHA256 |
|---|---|---|
| `tools/i_core/i_core_server.mjs` | `9ac97b01711bc580861f5d3aa2308846dad7606f5d28b4ba02939db83c269d46` | `b6d2b19c43ffaaa246b1d7f9d968c6d29788626875954b5aa282f27a18b9017b` |
| `tools/i_core/i_core_store.mjs` | `acf2628af7c9188bcc127aa57387a39d60a80a82796b771f8fe920227e7bdc6a` | `2bf42b7f48e14461c98e950974d44613d2068aaff562a3dc147275a35131c54e` |
| `tools/i_core/shortcut_mail_relay.mjs` | `841756bb88cee7eb406e9dd682e8eb547dc3c144d7bb8c1e68659e3c55cf9185` | `6132c0e560bb7449d2eeb86a742d9c3cb2724d38126766f4849299e8a7eb4b27` |
| `tools/i_core/send_shortcut_mail.ps1` | `0766737642349896379d545a22ca974ef0933ef514261ab9079642fc35d70919` | `d7af35b5f26fe2946025c4c784958e7276b801e3d8a867c772dc36d9c223a3f2` |
| `tools/i_core/strict_smtp_tls_validation.ps1` | `395e1c810f186a4136ad8b16ee4734e32322a4ba8064508f034ee0f21b6812ed` | `6f763d6b586c3b4747e37b651740858e26a79ce917f89ec03910de9b758b52a0` |
| `tools/i_core/start_i_core_service.ps1` | `e39115cc96ff520e3fbf1beb638d6f04a1a72a53c0a00959fe7949d91c895724` | `94195203a9a5450cb1b7a3ef8cbe039c9d616b27e1ff709efdba82034667ab42` |
| `start_pinned_i_core.ps1` | `55ccaa5369687b3c3d9c888cc296b4d4ea16d8fdf3b0eb6dd8dbd97a3cf1b90f` | `ABSENT` |
| `verify_v4_state.mjs` | `cf7a1dadc6e5cc774aa8e3c4a869cd1eeeade9e4687d8a8b2be382dbb04dec37` | `ABSENT` |
| `runtime/node.exe` | `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f` | `ABSENT` |

### 2.3 调用者运行源码的关键哈希

以下也是实际磁盘字节；它们用于提醒 MCP 切换不能仅替换 Core：

| 相对路径 | 现役 SHA256 | 基线 SHA256 |
|---|---|---|
| `tools/i_remote_mcp/server.mjs` | `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6` | `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6` |
| `tools/i_remote_mcp/mcp.mjs` | `4bdd55dd3bd41e4ff0e16cdce08b2c58dce007d6fe6eaee51cc2110cdfc7d09b` | `d9004fe4f1a56f234105ea0275e06a47eb7e6c6f7cee0760402418f7b45ca8b6` |
| `tools/i_remote_mcp/writeback.mjs` | `f2aac48db1cf61a44a0c9b5b28087b90894f03396cd52830a4428532944bc52a` | `f2b0ca627075de62bff40240e6f0e445b938ea2735606d1c96216d83c7931a61` |
| `tools/i_memory/i_memory_read.mjs` | `cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28` | `27e39b74261af58e0c3aed81eb68636ad49835d242b7cefca701e2b4cbcfa0c4` |

i Gateway 现役 `i_voice_context.mjs` SHA256=`811c1582537e61f5d6b995dc8651eed8156317a73c1a60fb890d4aa35d7c9e7f`，基线=`9a3bd7c40cca2508b9983cdc8f489e328a3f810a38002695be8209a4d8d0bed1`；现役 `i_mcp_server.mjs`=`7c296ce7cef6098bf2404aaa9d5b7e6d3ca7fdcc892c6ce6171bc10a84eb6644`，基线=`2fc65b6569bd7d4d410ea02bc26de6fc40b216ea0aa23f0eeaaa51b4b1608782`。

## 3. transcript/replay 逐项调查

本节的 `R/server`、`R/store` 都指第2节**实际固定包**的 i_core_server.mjs/i_core_store.mjs；行号不是仓库同名文件的行号。外置文件在第2节状态目录中；没有公开 credential_sha256 或消息内容 digest。

### 3.1 路由、表和后台执行

本节分别列出实现/配置状态与客户端近期实际调用/命中证据；“已加载”不等于“已调用”，条目数不等于调用次数。客户端近期使用未被直接证实时，判定保留为“说不清”。

| 项 | 用途和接口 | 读写/执行 | 实现与配置状态 | 客户端近期调用/命中证据与判定 |
|---|---|---|---|---|
| transcript capability | GET /v1/core/chat/transcript-capabilities；仅当前认证 Android 查询本设备能力 | R/server:214–217；R/store:806–824；读 devices 和启动时的 grant map，不写业务表 | 接口实现仍加载；外置 grant 1条，device=962d78a6…、character=i、from_created_at_ms=1790956800000（上海10/03 00:00）；凭据绑定布尔核验=true | **说不清（接口仍提供，近期真实客户端调用未发现）**。没有近30天成功客户端调用的直接日志；维护脚本的未认证401检查不算授权客户端使用，不能说客户端现在正在轮询 |
| transcript submit | POST /v1/core/chat/transcripts；提交已生成的双方纯文字聊天，不生成回复 | R/server:219–223；R/store:826–857；读 devices、grant、chat_messages、core_metadata replay ledger；同事务写 chat_messages/change_events；普通已登记手机、主角色、日期下限、chat、无资产/附注、最多100条 | 接口与受限授权实现仍加载，可接受符合grant的已完成聊天；不是客户端调用证明 | **说不清（10条落库强支持B3路径的推断，当前持续调用未知）**。Android companion10条，最后 change_event=1791044513291；缺逐请求路由证据，route次数/最后HTTP调用未知。归因保留为推断，见§4 |
| 外置 transcript grants | 授权装载、限制设备/当前token/角色/日期；不授其他设备或网页端 | R/store:203–270、388–408；默认 local-transcript-grants.json；只在 Store构造读取，不是新业务表，不是自助远程授权 | 文件mtime=2026-10-03T15:23:32Z，早于现进程；条目1且凭据绑定匹配。代码在启动时读取；重配token会使旧grant失效，缺失默认关闭，非法文件fail closed | **说不清（授权配置仍加载，近期被客户端实际使用未知）**。1条grant是配置数量，不是调用次数；不能由文件存在或绑定匹配证明近期实际使用 |
| 普通聊天 historical replay | POST /v1/core/chat/messages 对已审批的旧用户行允许精确重放确认；返回duplicate，不重写历史 | R/store:895–917、1289–1385；读取core_metadata里的绑定；比对既有v3-history用户行和incoming/existing不可变digest；预留(device,sequence)冲突拒绝；transcript明确allowApprovedHistoricalReplay=false | 保护实现仍加载；静态代码在每次持久化事务读取durable ledger；72条绑定全部仍指向既有聊天行 | **说不清（保护实现仍提供，近期例外命中未知）**。72是绑定条目数，不能写成72次调用。过去30天12条手机user新增落库仅证明数据变化，不能据此确定请求路径或例外命中；duplicate不增加change_event且无last_used审计 |
| replay外置/耐久账本 | historical-replay-approvals.json + core_metadata.historical_replay_approvals_v1；启动合并，不允许同sync/sequence不同绑定 | R/store:40–190、388–408；外置file只读；启动时事务写core_metadata；每次请求读ledger；不是新表 | 外置72、ledger72；按sync_id排序后精确相同（原数组顺序不同）；均已有行。filemtime=2026-10-03T09:42:37Z。配置/耐久账本仍存在且加载代码保留合并与校验 | **说不清（配置存在，近期实际使用/命中未发现直接记录）**。条目数量不等于调用次数；metadata没有last_updated/last_used列，filemtime不能当成DB最后写入或最后使用时间 |
| 离线 importMessages | Store本机一次性历史导入入口，不暴露HTTP | R/store:921–943；允许companion，创建local-import来源；同事务写devices/chat_messages/change_events；基线import_v3_chat.mjs:98、115–128、200构造v3-history来源和historical_import附注 | 本机入口仍存在；最近一次历史来源末写入=1790950558335，source=v3-history-2d8a…；不是10条Android companion来源 | **仍有历史数据，当前执行说不清**。没有发现本轮或当前后台持续执行该导入器 |
| transcript/replay后台任务 | 固定包没有专用transcript_jobs/replay_jobs、scheduler或timer | 受控9文件库存、R/server无setInterval/setTimeout、Store只在启动/请求执行；相关旧worker表见下 | 未发现独立Core后台任务实现 | **没有独立后台任务可退役**。不能将手机前台30秒同步叫Core后台任务；客户端当前是否触发同步仍未知 |

Core快照（2026-10-05T15:01:58Z附近）结构与数量：

| 表 | 行数 | 与本题关系 |
|---|---:|---|
| core_metadata | 4 | schema_version/node_id/cursor_secret/replay ledger；后三者敏感值未输出 |
| devices | 7 | 设备认证与来源登记 |
| consumed_pairing_codes | 5 | 配对一次性码digest，未输出 |
| change_events | 6955 | chat.message.upsert，max序号6956；序号最大值不等于行数 |
| chat_messages | 6955 | Android companion10；其余来源单独统计，不冒充这10条 |
| worker_leases | 1 | 旧core-smoke companion_reply租约；expires_at_ms=1786642382674，已过期 |
| companion_reply_jobs | 0 | 没有任务样本 |
| companion_reply_shadow_runs | 0 | 没有任务样本 |

worker表不属于 transcript/replay 的新增任务。现役 launcher 清除未受控 I_CORE 环境变量，健康 features没有reply jobs；旧租约不证明当前worker在跑。

### 3.2 调用者和近30天证据

| 调用者 | 静态依据/接口 | 近30天可用证据 | 判断 |
|---|---|---|---|
| B3 手机 App | `C:\HereIAm\b3-writeback-local-20261003`；core_sync_client.dart:77/88；engine:80–108、250–254先capability，再backlog和submitTranscripts；Persona:353–394原子入companion队列；main.dart:1880–1920前台30秒/恢复同步 | 10条Android companion的写入窗10/03 23:25至10/04 00:21（上海）；历史激活receipt candidate8770aa60且grant启用；没有本次实机、route log或开关读取 | 现役Core提供此路径；10条落库强支持B3上传归因（推断），未证实逐请求路由；当前App实际持续调用未知 |
| i_remote_mcp | 现役writeback.mjs:298–309调用普通chat/messages，以frontend:claude_web身份；flush:469、chatTurn:536；不调用transcripts/capability | 现役MCP日志i_chat_turn成功151条，最后2026-10-05T08:36:59.024Z；ledger user79/assistant78全部committed，Core相同来源79/78；未发现transcript/replay接口直接调用 | **仍在用普通网页finished-turn链**；不是Android10条上传者。不能因其不走transcript认定transcript无人用 |
| i_continuity_gateway / Codex Voice | 现役 .i/runtime/i_voice_context.mjs:141–157选择ADB、600–625只读提取；581声明no_phone_or_memory_writes；现役两mjs无chat/transcripts/chat/messages的HTTP调用 | 已确认实际网关进程/配置来源；当前手机0连接；未找到该网关到transcript的调用代码/本次授权范围中的调用日志 | **未发现调用**。Voice里的“用户转录”不是这个Core transcript接口，不新增推断 |
| 计划任务 | 全部任务动作白名单扫描：仅HereIAm-iCore、HereIAm-iRemoteMCP与这些路径相关；动作都为服务启动入口 | 两任务Running，进程/端口绑定如§2；未发现计划任务直接执行transcript POST或定时replay导入 | 服务启动仍使用；独立定时上传**未发现调用** |
| 本机部署/恢复脚本 | 现役remote .state/runtime/complete-b3-full-phone-transcripts.ps1:196、deploy-b3-full-phone-transcripts.ps1:215做capability健康/未认证检查；activation receipt位于phone-transcripts-20261003-232314-877dae…/activation-receipt.json | receipt activated=true、candidate8770aa60、service05112dde、schema4、worker_features=false、unauthenticated capability401；创建2026-10-03T15:24:23Z | 已有维护检查证据；不是新companion POST证明。扫描这里的维护脚本未发现直接POST chat/transcripts |
| replay维护脚本 | D:/memex/tools/i_core/.state/b3-sync-conflict-diagnostic.py:202–207生成approved_replays；b3-core-replay-package.py:42/84保全/打包审批；R/store启动加载 | 文件/ledger72一致；mtime如§3.1；未发现最近一次逐条replay命中的日志 | 绑定仍重要；是否仍有待补交队列**说不清** |
| i_remember手机消费者 | B3 claude_web_note_feed_service.dart:104/150调用remember changes/ack；远端server.mjs:249–273、505–509 | MCP i_remember成功3条，最后2026-10-03T15:50:18.350Z；deleted note rev2/delivered2/card前缀见§5 | 有旧投递证据，当前活跃消费未知 |

日志限制：Core目录的i_core.log只有4行/300字节、server.log38行/1747字节，mtime均为8/14，早于近30天窗；没有近期transcript/replay调用审计。Remote 10/02–10/05四个JSONL分别66/434/235/141行，其中标准诊断没有这些完整路径；startup log的remember/changes出现16次只是启动提示，**不是16次拉取**。phone feed handler未接标准request diagnostics，notes表也没有delivered_at。报告不将0次路径字面出现解释成0次HTTP请求。

### 3.3 schema6处理选项和工作量

估计为**工程工作日**，假设一个熟悉代码的工程师、无新硬件/网络问题。依据为明确文件/接口/授权/队列数量和现有测试模块；不是执行承诺或已获部署授权。

| 项目 | 移植仓库/兼容选项（推荐） | 明确放弃选项 | 先导出留档选项 | 估计及依据 |
|---|---|---|---|---|
| transcript capability/submit + grants | **推荐过渡期移植到schema6候选**：保留现有设备/credential/角色/日期下限及纯文字约束；no reply job；与PR10普通路线共享同一持久化/幂等实现。手机完全切PR10并排空旧队列后另评估退役 | 必须先确认当前手机已切换、旧队列/补交覆盖、旧API客户端不再需要，并明确关闭；直接删除会让B3手机404/无法传回复 | 本机加密保全固定9文件、grant、manifest、旧消息身份/序列和手机队列元数据，导出不能替代执行链 | 2–4日：2路由+Store受限授权/归一化+旧/新能力互斥+移植专项/集成；含手机过渡验证约再1–2日 |
| 72条replay不可变绑定/保护 | **推荐移植执行保护并保留durable ledger**，恢复/普通重试/alias占用仍fail closed；不扩大审批 | 只有确认72条旧重试依赖已排空且可接受未来旧队列冲突后才明确退役；不能仅由无日志决定 | 本机加密保留72条外置/DB映射及来源身份，验证恢复后拒绝冲突与精确duplicate | 1–2日：parser/安全读文件/启动合并/事务保护，72条受控映射，至少重试/不同载荷/序列冲突/恢复场景 |
| B3手机notes拉取/Organizer | ADR已定迁Core captures。**推荐正式captures消费闭环验证前保留受限47862桥**；保留notes删除语义与原来源/import回执，切换时单一消费者 | 不能以活动notes0作为退役依据；新增记录仍会产生。直接放弃会中断已实现成卡/删除 | 本机加密保留note_id/revision/删除标记/feed_seq/delivered_revision/phone_card_id及手机来源回执；禁止复活已删正文 | 单纯代码保全/对齐1–2日；真正captures切换另2–4日，依赖W2/W3/W7端到端且不重复Organizer |
| schema4固定运行包/入口 | 审阅的新固定候选，绑定整套hash，按4→5→6来源链演练；外置授权与客户端能力一起验 | 不能直接将schema6库交旧v4启动器：守卫明确只接受4 | 新一致加密备份/恢复演练必须覆盖授权文件和新写入；本轮内存副本不作为部署备份 | 1–2日发布/回退演练，另实际服务/设备Gate；依据9文件库存、guard和已有R01边界 |

不同项可重叠实施，不能简单把行中估计相加当排期；真实数据/服务切换/安装需独立方案和具体授权。选择集中于报告最后一节。

## 4. W6那10条手机来源回复

### 4.1 本次计数与清单

一致副本筛选：chat_messages JOIN devices（platform=android），sender=companion；全部10条message_type=chat、addenda_json为空数组，均在最近历史导入最大server_sequence **6777** 之后。与W6 count10的过滤口径相符。本次没有找到W6旧sync_id清单（W6当时只输出计数），所以只能核实**数量/来源口径相同**，不能断言旧10个ID逐条完全相同。

以下origin_device_id都为 `962d78a6-6db0-40e8-8e8e-2daf9fe18efb`（devices中登记Android；不是硬件独立证明）。sync_id只列12字符前缀。

| sync_id前缀 | created_at_ms | server_sequence | change_event.occurred_at_ms | origin_sequence |
|---|---:|---:|---:|---:|
| `e16fd4cf-8b6` | 1791027853318 | 6813 | 1791041104807 | 629 |
| `190c1a4f-c87` | 1791028614572 | 6814 | 1791041104809 | 630 |
| `6e3c5e7e-9f5` | 1791028719295 | 6815 | 1791041104810 | 631 |
| `7ebaf0b9-37d` | 1791029099847 | 6816 | 1791041104813 | 632 |
| `e0d186d3-62c` | 1791030960183 | 6817 | 1791041104814 | 633 |
| `24ab10d1-0f3` | 1791032526476 | 6818 | 1791041104815 | 634 |
| `7d4e311e-eca` | 1791033774872 | 6819 | 1791041104815 | 635 |
| `f0d4dee9-a54` | 1791041168549 | 6821 | 1791041169329 | 637 |
| `695e498d-94f` | 1791041473705 | 6823 | 1791041485097 | 639 |
| `8ca087db-7ca` | 1791044469429 | 6856 | 1791044513291 | 641 |

### 4.2 来源归因

- 标准import_v3_chat.mjs在第98/115/124行用来源hash生成 `v3-history-...`、origin_sequence=源本地ID，并写historical_import附注。本库两个local-import来源分别有2946/829条companion；最新导入最大seq6777、写入2026-10-02T15:35:58.335Z。10条的Android来源、空附注、seq6813–6856和10/03以后写入都不符合这条标准导入链，**排除标准导入器直接生成这10条的代码路径**。
- 前7条companion origin_sequence629–635，在2026-10-03T15:25:04.807–.815Z集中8毫秒落库，但客户端创建时间跨当天较早的多次聊天；这正符合B3 capability启用后enqueueLocalCompanionBacklog的时间过滤/补交。其前面同设备user622–628已较早入Core。
- 随后companion637/639/641与user636/638/640/642交错；不是一次性的全部导入。最后10条companion写入时间为10/04 00:21:53.291（上海）。该设备user643还在10/05 18:29:10.924（上海）落库，但没有新的companion落库；**不能据此推断之后没有回复、开关关闭或上传失败**。
- 固定包普通chat/messages只对external-frontend放companion（R/store:906–907）；当前Android没有这条例外。受限transcript能接受它，grant1条绑定该设备/i/10/03下限；旧worker表0jobs且租约过期，没有匹配的运行worker。
- **最有依据的推断：运行时补丁配合B3手机专用transcript上传；前7条符合backlog补交，后3条符合随后交错上传。** 支持它的有代码、grant、历史激活/安装证据和序列时间模式。DB/change_events没有accepted_route/request_id，也无HTTP请求审计，无法给这10条提供逐次路由收据。Store.importMessages允许本机传任意device ID（R/store:925–943），未登记的SQL/维护调用也无法仅由这些元数据绝对排除；扫描到的维护脚本未发现这类写入这10条的调用。这不是逐请求归因证明；截至原调查证据窗口，当前持续调用仍未知。没有读取正文作推断。

### 4.3 持续上传的代码能力与PR10重复风险

| 对照 | B3 8770aa60 | 本基线PR10 |
|---|---|---|
| 入队 | Persona:353–394纯文字companion自动原子入队；259–305授权backlog | Persona:247–260本机owner gate；263–299只有匹配device/character开关才入队 |
| 上传 | engine:74–108先user走messages，再companion走transcripts | engine:67–110读取chat sender，全部走messages |
| 服务端授权 | 外置local-transcript-grants绑定token/角色/日期 | store:1102–1140 schema6域能力domain_phone_capabilities；token绑定，普通配对声明不授予 |
| 默认/当前启用 | 代码依capability；本次server grant1有效，手机当前状态未知 | 当前基线只搜到configureCompanionOutbox定义，没有生产调用点；现役schema4没有domain_phone_capabilities，不能报PR10已启用 |
| 稳定身份 | 已有chat sync_id复用，队列origin_sequence写一次；counter=outbox.max_sequence.device；永久companion.enqueued.sync_id标记及server_sequence挡backlog重排 | addCharacterMessage一次生成chat sync_id，并给同一队列复用该ID；相同counter；没有B3永久backlog标记 |
| 发回复 | 上传已完成回复，不建Core reply job | 手机已完成回复上传，不带request_companion_reply字段；Core能力登记要求关闭/排空Core reply production |

**若两条上传路线同时消费同一个已有outbox行**，sync_id/origin_sequence/不可变字段相同，可能重复网络提交，Core共享的精确幂等返回duplicate，不应产生第二条聊天。但这只是“同一行/同一身份/同一完整载荷”的条件性结论，不是本次同开实测。schema6当前无transcript，不能直接同开；必须先移植并共享持久化规则。

若错误合并两套enqueue、给同一sync_id再次分配origin_sequence，或迁移丢失counter/永久marker/已接受序列，则可能immutable_message_conflict、origin_sequence_conflict或队列阻断；若新造sync_id，则可能成为第二条记录。B3和PR10对附注/普通chat筛选不同，不能悄悄剥离后冒称同载荷。推荐切换时只保留一个生产上传器，复用原队列身份，排空/对账后退役旧路；不重新生成UUID补交旧10条。

## 5. 主力手机、构建来源与i_remember消费

### 5.1 现场ADB结果与本地产物

本次ADB路径：`C:\Users\Lynx-DB\AppData\Local\Android\Sdk\platform-tools\adb.exe`。普通和宿主只读devices -l均0设备，没有install/push/run-as写入/启动App/连接新地址/切开关。

| 核验项 | 当前实机结果 | 独立本机/历史证据 |
|---|---|---|
| 主力设备选择 | **未验证：0连接**；Core有多个Android登记记录，不能据此挑硬件 | 活跃来源962d78a6…有近期写入/ack；只是登记身份。Gateway选择逻辑只有明确serial或恰好1台设备才通过（现役Voice:141–157、600–601） |
| versionName/versionCode | **未知** | 本地APK经aapt为1.0.30/113、包com.memexlab.hereiam.v3；output-metadata.json相符 |
| firstInstallTime/lastUpdateTime | **未知** | 历史10/03安装事件只能说明当时；不能代替当前dumpsys字段 |
| APK SHA256/多split | **未知**，没有pm path/split清单，不宣称单包 | 本地构建metadata为SINGLE，无split；不是当前手机split证明 |
| 当前安装源码 | **未知** | 本地候选与历史8770aa60匹配，见下；不能升级为当前实机事实 |

本地候选APK：
`C:\HereIAm\b3-writeback-local-20261003\build\app\outputs\flutter-apk\app-hereiamv3-debug.apk`，
434177890字节，mtime=2026-10-03T14:23:14Z，
SHA256=`8b55be76011e8ea8ebba09a23316f7610c56bc25e2c6171846fd13ca4ab49b84`。
包名、version和hash本次重新读取。APK内部未找到匹配git/commit/build_info/version的文本来源文件，因此提交绑定来自历史构建记录，不是APK自带Git证书。

交叉依据：
- B3_LOCAL_ROLLOUT_20261003.md:149–168记录构建818.5秒、冻结源核对、8770aa60获准安装及当时实机hash匹配；§后文真人结果是旧候选边界，不冒称本次重测。
- 精确本机历史执行日志 `rollout-2026-10-03T13-21-58-01a10036-41fd-7390-9e54-d587eb6fb808.jsonl` 仅本地聚合tool output：第5081行（14:24:28.675Z）build success/exit0/818.5s；5088（14:24:47.869Z）候选hash一致/exit0；5116（14:27:34.150Z）提交8770aa60；5259（14:43:33.559Z）安装工具exit0/已批准APK hash；5906（15:25:59.911Z）当时安装后hash检查记录。未输出原日志或对话。
- 当前B3分支 `codex/b3-writeback-local-20261003` HEAD=`3a9336b122b2fda22ff65ed32d9cee263e8fc2da`；Git status为空；8770aa60→HEAD的lib/android/pubspec.yaml没有差异（随后主要为交接/服务工作）。源tree和构建历史相符。
- `D:\memex` 旧私人谱系HEAD=`b2adc44b7c04983a931c39695b81491cd295084b`且有大量已有修改（含Persona/main/pubspec/Gateway/活动等）。其APK产物mtime为9/05；本次不把它当作8770构建输入或源码分支，没有动这个脏工作区。

### 5.2 B3手机源码对当前基线的差异

**净化谱系按文件对照，不合并旧D历史。** 当前B3 HEAD对基线全树206项差异（A23/M83/D100），lib/android为重要部分，完整路径清单见附录A。这包括主线后来增加的hub文件在旧B3树中缺失，不能把所有D视作B3“主动删除的功能”。

| 重点 | 可核查差异/影响 |
|---|---|
| core_sync_client/protocol | B3新增transcript capability/submit及能力响应；基线只有普通chat提交。client:77/88、engine:80–108 |
| core_sync_engine/runtime/connection_store | B3按sender筛队列、纯文字backlog、cursor按coreNode分隔、失败sync触发合并及前台同步；基线PR10的sender从chat行恢复并提交普通route。不能直接覆盖整个同步文件 |
| persona_chat_service | B3sender字段/持久counter/永久marker/backlog、CreatedAt/ServerSequence；PR10另有owner gate，必须保留已接受队列ID与序列而非重建 |
| app_database/tables/generated | B3schema62，主线60；61加persona created_at_ms/server_sequence，62加outbox.sender；两源码没有onDowngrade。**安装前阻断项：确认手机真实schema并设计向前兼容迁移，不对真实库实验降级** |
| remember拉取与UI | B3新增4个notes文件、dependencies Provider、web_note_connection page/viewmodel、main前台30秒与resume；基线lib没有该消费者 |
| Record Organizer | B3新增replaceOrganizedCard/deleteCard的sourceKind/外部note来源处理；importer调用现有Agent后事务更新卡/来源/更正/import回执。基线另有captures consumer与reconciler，必须避免同记录双处理 |
| 聊天显示 | B3CreatedAt/ServerSequence排序及网页端来源标签/补充清理；装主线会失去这些B3处理，需按语义移植 |
| 主线hub/其他 | B3缺少主线personal_data_hub若干文件/capture_card_reconciler；不能把B3全树拿来替换主线，需选择性补丁 |

重点精确SHA256见附录B（Git blob对Git blob，另验B3磁盘一致，避免把CRLF转换混成语义差异）。

未提交/未推送分开记录：
- B3工作树/暂存区干净，无未提交源码差异。
- B3无upstream；本地remote refs没有包含HEAD，`rev-list HEAD --not --remotes`为26个commit，含8770aa60、05112dde、3069115d等。**“26”是本地缓存远端引用下的未收录数量；本次没fetch，不能声称已联网核对GitHub。** 当前基线不含相关lib路由/notes代码已直接核实。
- D私人工作树另有未提交改动；没有资格据此推断当前手机装的是这些改动，且未reset/stash/pull或改动它们。

### 5.3 W6的deleted/on_phone那条记录由谁拉取

本次writeback一致内存副本白名单元数据：
note_id前缀 `note_swWJ4AO`，revision=2，status=deleted，
created_at_ms=1791042484912（10/03 23:48:04.912上海），
updated_at_ms=1791042614221（23:50:14.221），
feed_seq=2，delivered_revision=2，phone_card_id前缀 `66789e8a-896`。
active0、waiting0、deleted/on_phone1，与W6数量一致。没有读取text/text_hash。

代码链：
1. 现役remote `server.mjs:249–273`在47862验证手机feed token后暴露GET changes/POST ack；`writeback.mjs:507、649`依delivered_revision计算on_phone并更新回执。此ack不含Android安装身份证明。
2. B3 `lib/data/memory_v3/notes/claude_web_note_feed_service.dart:91–175`从安全存储读baseUrl/token/cursor，GET `/v1/remember/changes`，调用importer.apply，再POST ack并持久cursor。只有成功本地apply后才ack。
3. `claude_web_note_importer.dart:25–26、57–138`以sourceKind=claude_web_note、sourceRef=noteId；通过RecordOrganizer处理创建/更新；deleted调用deleteCard；memory_card_operations写external_note_import且payload只含note ID/revision/op/card IDs。重复revision不重跑模型。
4. `lib/config/dependencies.dart:29–43`注入服务/OrganizerAgent；`main.dart:1880–1920`前台30秒/resume拉取；手动设置页也可触发。
5. 代码所在分支为 `codex/b3-writeback-local-20261003`，实现提交3069115d及随后8770aa60；不在当前v3-lab基线。现役Core固定包并不负责这条notes入卡。

**能够定位消费实现和历史绑定，但不能唯一证明这一个ack是这段App执行的。** 原账本未保存delivered_at/consumer package/install ID；本次手机未连，未读取手机memory_card_operations对应note前缀/卡前缀的import回执。已删除note和缺活跃样本也不能证明当前pull仍正常。历史部署/真人记录支持旧B3成卡/删除闭环，但本次不继承为新包Gate。

## 6. 部署风险表

| 风险 | 证据 | 影响步骤 | 建议处理 | 是否需用户决定 |
|---|---|---|---|---|
| 替换Core丢失transcript能力/外置grant | §2/§3两路由在现役有、基线无；grant1、companion10 | Core升schema6、装新App、开启回复上传 | 移植受限过渡接口或先完成PR10客户端切换/排空，再单独退役 | 是：D1，具体过渡策略 |
| 丢失72条replay保护 | metadata/file72匹配且事务保护现役，基线无执行代码 | Core升schema6、旧outbox恢复 | 保留durable binding与执行拒绝规则；备份需含外置文件 | 是：D2，保留/退役及条件 |
| 手机DB62→主线60 | 两源码schemaVersion309、B3迁移1048–1058，无onDowngrade | 装新App | 必须核实当前实机schema；向前兼容升级，禁止试装降级 | 先工程修复/元数据确认；实机安装仍需具体批准 |
| notes47862消费者回退 | B3 notes/importer有；基线无；deleted ack1 | MCP切换、装新App | captures闭环完成前保留桥与回执；正式切换单一消费者 | 是：D3，过渡退役时点 |
| B3/PR10同时入队/身份重分配 | 同sync共有counter但B3有永久marker；路线/能力不同 | 开启回复上传、装新App | 单上传器、共享不可变身份、保留counter/marker；专项再验证 | 是：D1，切换方式；工程行为已受既有幂等合同约束 |
| 主力硬件/包/开关未知 | ADB0；仅本地hash与历史一致 | 装新App、开启回复上传 | 连接后只读核版本/安装时间/各split/hash/DB schema/队列元数据；不因10条认为当前开关开启 | 不把缺口当批准；实机Gate需完成 |
| MCP读写服务与仓库不同 | §2.3 mcp/writeback/i_memory hash不一致 | MCP切换 | 用当前运行policy/env/数据路径的白名单断言和候选对照，保留出站私密规则与历史边界；不整体覆盖 | 是：具体MCP切换候选另批 |
| v4启动守卫拒绝schema6 | manifest固定4、launcher/verify_v4_state；R01只副本 | Core升schema6 | 发布全套新固定候选+备份/外置授权恢复+4→5→6副本链+旧/新客户端矩阵 | 是：具体发布/停启/备份/升级另批 |
| no log被误读成unused | Core日志8/14、feed无request diagnostics、duplicate无last_used | 全部步骤 | 保留未知，补最小无正文审计或用授权设备Gate确认，不由缺日志直接删功能 | D1/D2/D3决策依据 |
| 用旧整库覆盖回退 | ADR/R01明确不能抹新域写入；本次没作部署备份 | Core升schema6及失败回退 | 冻结受影响域、保全新写入、优先前向修；整库恢复不在本调查授权 | 已定边界；执行方案仍另批 |

附录清单与验证说明后，所有新增部署选择集中在最后一节。报告不是可部署候选，也不是批准切换。

## 附录A. B3 HEAD对精确基线的全部文件差异

方向为 **基线 → B3 HEAD**，只含受控路径名和状态，不含diff正文。D表示该路径在旧B3树不存在，包含主线后续增加内容。

```text
D  .github/workflows/ci.yml
D  .github/workflows/ollama-live.yml
M  AGENTS.md
M  DEVLOG.md
M  android/.gitignore
M  android/build.gradle.kts
A  android/jni_build_staging.gradle
M  docs/companion-first/CORE_SYNC_DATA_INVENTORY.md
M  docs/companion-first/PRODUCT_ROADMAP.md
M  docs/design/whiteboard-visual-rules.md
A  docs/development/B3_LOCAL_ROLLOUT_20261003.md
A  docs/development/B3_NOTE_IMPORT_HANDOFF.md
M  docs/development/B3_WRITEBACK_DESIGN.md
M  docs/development/COLLABORATION_EXECUTION_PROTOCOL.md
D  docs/development/I_CORE_DOMAIN_CONTRACT.md
M  docs/development/I_PROJECT_STATE.md
D  docs/development/PERSONAL_DATA_HUB_ADR_20261005.md
D  docs/development/PERSONAL_DATA_HUB_PLAN_20261005.md
D  docs/development/QUICK_CAPTURE_DESIGN_20261005.md
D  docs/development/UNATTENDED_VERIFICATION.md
D  docs/development/data-authority-preflight/W6_AUTHORITY_DRAFT_HANDOFF_20261005.md
D  docs/development/data-authority-preflight/W6_DATA_AUTHORITY_DECISION_DRAFT_20261005.md
D  docs/development/data-authority/hub/GATE1A0_LIFE_DOMAINS_APPENDIX_20261005.md
M  docs/development/goals/GOAL-20260824-ai-workbench-wave1.md
D  docs/development/handoffs/DISPATCH_ACCEPTANCE_20261005.md
D  docs/development/handoffs/HAPPY_BRANCH_INTEGRATION_20261005.md
D  docs/development/handoffs/I_CORE_TEST_DEBT_20261005.md
D  docs/development/handoffs/I_CORE_TEST_DEBT_FIXTURE_WORKER_20261005.md
D  docs/development/handoffs/I_CORE_TEST_DEBT_MAIN_ACCEPTANCE_20261005.json
D  docs/development/handoffs/I_CORE_TEST_DEBT_MAIN_ACCEPTANCE_20261005.md
D  docs/development/handoffs/I_CORE_TEST_DEBT_MERGE_20261005.json
D  docs/development/handoffs/I_CORE_TEST_DEBT_VALIDATION_20261005.json
D  docs/development/handoffs/LEARNING_SYSTEM_AND_TOOLS_20261005.md
D  docs/development/handoffs/LIFE_PLAN_COORDINATION_20261005.md
D  docs/development/handoffs/MCP_ALIGNMENT_MAIN_TEST_VALIDATION_20261005.json
D  docs/development/handoffs/PERSONAL_DATA_HUB_DISPATCH_20261005.md
D  docs/development/handoffs/PERSONAL_DATA_HUB_DISPATCH_NEXT_20261005.md
D  docs/development/handoffs/PR9_PR10_CAPTURE_LIFECYCLE_20261005.md
D  docs/development/handoffs/PR9_PR10_REVIEW_FIXES_MAIN_ACCEPTANCE_20261005.md
D  docs/development/handoffs/PR9_PR10_REVIEW_FIXES_VALIDATION_20261005.json
D  docs/development/handoffs/PR9_PR10_USER_EDIT_FIX_20261005.md
D  docs/development/handoffs/TEACHER_EXAM_STUDY_PLAN_20261005.md
D  docs/development/handoffs/V3_BASELINE_TEST_COMPARISON_20261005.md
D  docs/development/handoffs/W0_BASELINE_FAILURES_20261005.json
D  docs/development/handoffs/W0_BASELINE_FAILURES_20261005.md
D  docs/development/handoffs/W0_INTEGRATION_20261005.md
D  docs/development/handoffs/W0_RUNTIME_SOURCE_HASHES_20261005.json
D  docs/development/handoffs/W0_RUNTIME_UPDATE_20261005.md
D  docs/development/handoffs/W1_COMBINED_MAIN_ACCEPTANCE_20261005.json
D  docs/development/handoffs/W1_COMBINED_MAIN_ACCEPTANCE_20261005.md
D  docs/development/handoffs/W1_COMBINED_R01_VALIDATION_20261005.json
D  docs/development/handoffs/W1_DOMAIN_IMPLEMENTATION_20261005.md
D  docs/development/handoffs/W1_DOMAIN_MERGE_20261005.json
D  docs/development/handoffs/W1_R01_REAL_COPY_VALIDATION_20261005.json
D  docs/development/handoffs/W1_R01_REAL_COPY_VALIDATION_20261005.md
D  docs/development/handoffs/W2_BUSINESS_DOMAINS_20261005.md
D  docs/development/handoffs/W2_ENGINE_HANDOFF_20261005.md
D  docs/development/handoffs/W2_MAIN_ACCEPTANCE_20261005.json
D  docs/development/handoffs/W2_MAIN_ACCEPTANCE_20261005.md
D  docs/development/handoffs/W7_FOUNDATION_MAIN_ACCEPTANCE_20261005.json
D  docs/development/handoffs/W7_FOUNDATION_MAIN_ACCEPTANCE_20261005.md
D  docs/development/handoffs/W7_PHONE_FOUNDATION_20261005.json
D  docs/development/handoffs/W7_PHONE_FOUNDATION_20261005.md
D  docs/development/whiteboard-workstreams/P6_OLLAMA_TEXT_TASKS_20261002.md
M  docs/development/whiteboard-workstreams/README.md
D  docs/development/whiteboard-workstreams/WORKBENCH_PAUSE_20261002.md
M  integration_test/whiteboard_interactions_loop_test.dart
M  lib/agent/built_in_tools/memory_v3_query_tool.dart
M  lib/agent/built_in_tools/memory_v3_update_card_tool.dart
M  lib/agent/skills/character_tools_factory.dart
M  lib/config/dependencies.dart
A  lib/data/memory_v3/notes/claude_web_note_feed_service.dart
A  lib/data/memory_v3/notes/claude_web_note_feed_storage.dart
A  lib/data/memory_v3/notes/claude_web_note_importer.dart
A  lib/data/memory_v3/notes/claude_web_note_models.dart
M  lib/data/memory_v3/retrieval/query_expander.dart
D  lib/data/memory_v3/services/capture_card_reconciler.dart
M  lib/data/memory_v3/services/record_organizer_service.dart
D  lib/data/personal_data_hub/capture_consumer.dart
D  lib/data/personal_data_hub/domain_http_transport.dart
D  lib/data/personal_data_hub/domain_protocol.dart
D  lib/data/personal_data_hub/domain_store.dart
D  lib/data/personal_data_hub/domain_sync_engine.dart
D  lib/data/personal_data_hub/personal_data_hub.dart
A  lib/data/services/persona_chat_order.dart
M  lib/data/services/persona_chat_service.dart
M  lib/data/services/persona_reply_sanitizer.dart
M  lib/data/services/sync/core_sync_client.dart
M  lib/data/services/sync/core_sync_engine.dart
M  lib/data/services/sync/core_sync_protocol.dart
M  lib/data/services/sync/core_sync_runtime_service.dart
M  lib/data/whiteboard/whiteboard_drift_store.dart
D  lib/data/workbench_ai/task_queue/ollama_text_task_gateway.dart
M  lib/data/workbench_ai/task_queue/workbench_runtime_task_queue_tool.dart
M  lib/data/workbench_ai/task_queue/workbench_task_queue_execution.dart
M  lib/data/workbench_ai/task_queue/workbench_task_queue_tool_host.dart
M  lib/data/workbench_ai/workbench_runtime_client.dart
M  lib/db/app_database.dart
M  lib/db/app_database.g.dart
M  lib/db/tables.dart
M  lib/main.dart
A  lib/ui/character/widgets/chat_message_source_label.dart
M  lib/ui/character/widgets/persona_chat_screen.dart
M  lib/ui/companion/view_models/schedule_view_model.dart
M  lib/ui/core/widgets/dicebear_avatar.dart
M  lib/ui/desktop/widgets/desktop_persona_chat_view.dart
M  lib/ui/main_screen/widgets/input_sheet.dart
A  lib/ui/settings/view_models/web_note_connection_viewmodel.dart
M  lib/ui/settings/widgets/early_update_settings_card.dart
M  lib/ui/settings/widgets/personal_center_detail_pages.dart
M  lib/ui/settings/widgets/personal_center_screen.dart
A  lib/ui/settings/widgets/web_note_connection_page.dart
M  lib/ui/whiteboard/editor/card_rich_text_editor.dart
M  scripts/install_hereiam_v3.ps1
D  test/acceptance/scripted_workbench_runtime.dart
D  test/acceptance/whiteboard_ai_acceptance_test.dart
M  test/agent/action_message_tools_test.dart
D  test/agent/built_in_tools/memory_v3_update_card_user_turn_test.dart
M  test/agent/companion_agent/sleep_companion_state_test.dart
M  test/agent/state_util_test.dart
A  test/data/memory_v3/notes/claude_web_note_feed_test.dart
M  test/data/memory_v3/services/record_organizer_service_test.dart
D  test/data/personal_data_hub/app_integration_test.dart
D  test/data/personal_data_hub/capture_lifecycle_test.dart
D  test/data/personal_data_hub/crash_worker.dart
D  test/data/personal_data_hub/domain_protocol_test.dart
D  test/data/personal_data_hub/domain_sync_test.dart
M  test/data/services/activity/mda2_android/file_activity_outbox_store_test.dart
M  test/data/services/persona_chat_service_test.dart
M  test/data/services/persona_reply_sanitizer_test.dart
M  test/data/services/sync/core_sync_client_test.dart
A  test/data/services/sync/core_sync_frontend_test.dart
A  test/data/services/sync/core_sync_runtime_service_test.dart
A  test/data/services/sync/core_sync_transcript_test.dart
M  test/data/whiteboard/ingestion/smoke_real_url_test.dart
M  test/data/whiteboard/whiteboard_drift_store_test.dart
D  test/data/workbench_ai/task_queue/ollama_live_test.dart
D  test/data/workbench_ai/task_queue/ollama_text_task_gateway_test.dart
A  test/db/b3_chat_order_migration_test.dart
A  test/db/b3_transcript_outbox_migration_test.dart
M  test/domain/models/location_context_config_test.dart
D  test/integration/personal_data_hub/client_core_interop.dart
A  test/ui/core/widgets/chat_message_source_label_test.dart
M  test/ui/desktop/desktop_task_result_presentation_test.dart
M  test/ui/main_screen/widgets/input_sheet_test.dart
M  test/ui/memory/widgets/memory_summary_card_v3_test.dart
M  test/ui/settings/location_context_settings_page_test.dart
A  test/ui/settings/web_note_connection_viewmodel_test.dart
M  test/ui/settings/widgets/backup_restore_page_test.dart
M  test/ui/settings/widgets/personal_center_screen_test.dart
A  test/ui/settings/widgets/web_note_connection_page_test.dart
M  test/ui/whiteboard/card_rich_text_editor_test.dart
M  test/whiteboard_canvas/compact_card_editor_test.dart
M  test/whiteboard_canvas/whiteboard_local_media_cards_test.dart
M  tools/i_core/README.md
M  tools/i_core/activity_control_plane.mjs
M  tools/i_core/activity_control_plane.test.mjs
D  tools/i_core/domain_adoption.test.mjs
D  tools/i_core/domain_companion.test.mjs
D  tools/i_core/domain_copy_validation.test.mjs
D  tools/i_core/domain_http.mjs
D  tools/i_core/domain_http.test.mjs
D  tools/i_core/domain_migrate.mjs
D  tools/i_core/domain_migrate.test.mjs
D  tools/i_core/domain_schema.mjs
D  tools/i_core/domain_schema.test.mjs
D  tools/i_core/domain_store.mjs
D  tools/i_core/domain_store.test.mjs
A  tools/i_core/historical_replay_approvals.test.mjs
M  tools/i_core/i_core_server.mjs
M  tools/i_core/i_core_server.test.mjs
M  tools/i_core/i_core_store.mjs
D  tools/i_core/import_local_plan.mjs
D  tools/i_core/import_local_plan.test.mjs
D  tools/i_core/import_personal_notes.mjs
D  tools/i_core/import_personal_notes.test.mjs
A  tools/i_core/local_transcript_grants.test.mjs
M  tools/i_core/migration_m3/migration.test.mjs
M  tools/i_core/migration_m3/supervision.mjs
M  tools/i_core/migration_m3/supervision.test.mjs
D  tools/i_core/personal_data_domains.mjs
D  tools/i_core/personal_data_domains.test.mjs
D  tools/i_core/personal_data_http.test.mjs
M  tools/i_core/runtime_pin/runtime_pin.test.mjs
M  tools/i_core/runtime_upgrade/r3/combination.test.mjs
M  tools/i_core/runtime_upgrade/r3/lifecycle.test.mjs
M  tools/i_core/runtime_upgrade/r3/package.mjs
M  tools/i_core/runtime_upgrade/r3/service.test.mjs
M  tools/i_core/runtime_upgrade/r3/start_schema5.ps1
M  tools/i_core/test_fixtures/migration_m3/lab.mjs
M  tools/i_core/test_fixtures/runtime_upgrade/r3/descendant_fixture.mjs
M  tools/i_core/test_fixtures/runtime_upgrade/r3/lab.mjs
D  tools/i_core/test_fixtures/schema4/README.md
D  tools/i_core/test_fixtures/schema4/runtime_pin_lab.mjs
D  tools/i_core/test_fixtures/schema4/synthetic_schema4.mjs
M  tools/i_memory/README.md
A  tools/i_remote_mcp/phone_transcript_e2e.test.mjs
D  tools/life_planner/DOT_PLAN_RULES.md
D  tools/life_planner/PLANNER_AGENTS.md
D  tools/life_planner/README.md
D  tools/life_planner/areas.md
D  tools/personal_data_hub/node_core_domain_fixture.mjs
D  tools/siyuan_tutor/README.md
D  tools/siyuan_tutor/STUDY_AGENTS.md
D  tools/siyuan_tutor/TUTOR_RULES.md
D  tools/siyuan_tutor/subjects.md
```

## 附录B. 手机重点源码哈希

此表比较双方提交的原始Git blob。B3本机磁盘与其HEAD blob是否相同另列。哈希不是App已加载这些源码的证明。

| 文件 | 基线 blob SHA256 | B3 HEAD blob SHA256 | B3磁盘=HEAD |
|---|---|---|---|
| `lib/data/services/sync/core_sync_client.dart` | `f3a1f4df41f73dcbbb64e32598a6be57042986c60f9f80df01286ed85cb12d57` | `a1b3396620b960cb0359c1a0e1d775f33a077302ee3744b99ecd581f61ca37e2` | false |
| `lib/data/services/sync/core_sync_engine.dart` | `db91306b44281b6064e0f5e09f21364e7f104228b6418e7a25536c7b3760b813` | `b1a0ace62a8ad766464a2a4b362f954f679740e7e84d2ae2c0a84197c39ba400` | false |
| `lib/data/services/sync/core_sync_protocol.dart` | `dfa99dbcf3e6823ce8c460f5cd16aecdbb4f26460fe1c157a4b4d913cf093e2e` | `4741e0f0b9d4038956044bc1236109259c095143631f4b70c3dd8b4e083e9f15` | true |
| `lib/data/services/sync/core_sync_runtime_service.dart` | `4db5523af4aca5c58da1a26ae526f3074cdce7d55f37c94fed95e65017d83ab6` | `c56b4de226d77cf63f4ee6d636b9c5df5d720fc73fd7f54b9c49885d98123622` | false |
| `lib/data/services/sync/core_sync_connection_store.dart` | `ddd518bcd5b1f9f718599e71570b294455a1fb76c49831cab7c24d63cf1786c1` | `ddd518bcd5b1f9f718599e71570b294455a1fb76c49831cab7c24d63cf1786c1` | false |
| `lib/data/services/persona_chat_service.dart` | `e3b788b6e1b4ccd3a8d5af5b867f4397efac46b938d5f61392a0a00b452443cf` | `61eefce530e731fbe10aa0d3476705fbd989f3a81d1f1533903c1ee9c23a59dc` | true |
| `lib/data/memory_v3/services/record_organizer_service.dart` | `01402c76d608b7a75fa2a4226a544e9791e0c45a2b02adb5f429351d35712863` | `05a2a4af907540cefed8cf80d98be8362a8ba86f24522372c9a387d74939bf26` | false |
| `lib/db/app_database.dart` | `2427c1d0b745b1c463b093828549cc5f74e52d2e65bce19742702393ceffe959` | `ea6d8c9e2cadc8f89b10cee92ee0323ebe6e70d979713eea91b302c5ffc9c75f` | true |
| `lib/db/tables.dart` | `c2819ea4967da7baec817d23174f86d60e7198b3d1f74809ae4ff492f720704b` | `f640b5512a877977907b29e331219e7639fe0042ea361741b2189597860377da` | true |
| `lib/main.dart` | `ff4d64bb7365c4e28aea55acb059c702fc8147d143961edc6873bb961ab7371c` | `736f156fbd6d949347ed5af4004a4f34de0638f077f69d567ad63b028c817f53` | true |
| `lib/config/dependencies.dart` | `bfeb28d9cdd6a7fac2c67af75d0056d2473ed7e8dd19a29611a367398ba1e50b` | `1e4a30c80536f1d680583ba5ac8a00ed692501fdc0bdc7fb33c77d5ff5ead104` | false |

## 7. 本报告验证和提交边界

验收返修仅收紧§1、§3、§4的证据措辞，未重读线上服务、数据库、日志或手机；原调查时点和元数据不前移。

- 纯文档调查未运行App/Core逻辑测试、构建或设备Gate。运行的检查为分支/HEAD/status、磁盘/清单哈希、只读一致副本完整性、白名单结构/数量/身份序列、进程/任务/端口/健康绑定、ADB连接列表、本地APK元数据/哈希以及文档引用/空白检查。
- 只有本报告可暂存/提交；提交前再核本分支与精确基线、暂存文件清单及diff --check。没有push/PR或全局状态更新。
- 项目hook要求全局I_PROJECT_STATE。按用户已给的隔离worker例外，提交时一次性进程环境 `SKIP_PROJECT_STATE=1`，在finally恢复原环境；不修改/禁用hook、不把全局状态写进报告提交。具体提交结果以最终Git commit回执为准。
- 本报告不含真实内容、token、凭据、原始日志/库；历史执行日志仅本机白名单聚合。未写长期记忆；没有声称ephemeral bootstrap已保存交接。
- 未核实项：当前实机包/安装时间/split与hash、真实手机DB版本/队列/开关/import回执；每条transcript HTTP request与replay duplicate次数/最后命中；旧W6十ID一一对应；实时公网/手机网络及所有客户端行为；当前有效policy/env全字段；schema6新发布及恢复。分别是证据缺口，不是“已不用”。

## 8. 集中需要用户决定的部署事项

以下只涉及本次发现的**具体过渡/发布选择**。ADR已定的手机回复入Core、notes迁Core、手机唯一执行者等无需重新确认。本轮没有执行这些选择。

| ID | 需要决定 | 推荐 | 其他可选及条件 |
|---|---|---|---|
| D1 | 从B3 transcript切PR10时是否保留受限兼容接口，以及单一上传器切换顺序 | 先把受限transcript/grant移植到schema6审阅候选；新手机保留B3已有schema/来源/队列与notes能力，实际切PR10时明确关闭旧生产上传器，排空对账后再退役旧API | 若选择直接退役，先证明当前手机已切PR10、旧pending/backlog无遗漏、身份与序列不重造；在缺实机证据时不能直接采用 |
| D2 | 72条historical replay绑定是否继续保留执行保护 | 保留DB ledger+外置映射+精确duplicate/alias拒绝行为；导出加密留档作恢复输入 | 明确放弃需接受旧队列重试冲突，先核待补交队列及恢复场景；无调用日志不够。仅导出不替代在线保护 |
| D3 | 旧remember 47862桥何时退役 | 按已定ADR迁captures，但正式Core→手机Organizer增改删/删除即时清正文/来源回执闭环验过之前保留现役桥；切换后单一消费者 | 提前关闭会让新网页记录失去现有成卡路径。active0不能作为退役依据；如明确接受功能中断，要记录暂停范围 |
| D4 | 后续具体发布候选及分别授权范围 | 工程补齐上述缺口、获得可审查源码/包/备份恢复方案后，分别批准MCP切换、Core停启及4→5→6升级、主力手机安装/上传能力配置 | 本报告提交本身没有这些权限；当前手机0连接，不能替代实机候选身份绑定。不得用旧整库覆盖回退抹去新接受数据 |

建议下一步可先完成不碰线上状态的工程对齐候选与测试矩阵；主力手机连接后补只读身份/DB版本/队列元数据，再给出精确发布包和逐项授权范围。本报告不替用户选择，也不自动合入v3-lab。
