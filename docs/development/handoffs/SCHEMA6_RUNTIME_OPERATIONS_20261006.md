# schema6 运行操作与故障边界（审核草案，2026-10-06）

本页给执行者 i 使用；本人版见 [一页上线操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)。本轮只读核验和文档准备造成的现役停机为 **0**，没有停启、冻结任务、修改配置/原库或操作手机。草稿 PR 不是部署批准。首次旧 v4 接管尚未实现，必须在任何现役停机之前阻断。

## 1. 当次现役清单

取证：2026-10-06 12:22–12:27（Asia/Shanghai），仅任务/服务白名单、进程路径/开始时间、文件哈希、端口和未认证探测；未输出完整命令行、配置正文、凭据或聊天。下列 PID 只为该窗口关联，执行时必须重新核实，不能据此终止未来进程。

| 对象 | 当次状态、入口与探测 |
|---|---|
| Core | 计划任务 `\HereIAm-iCore`：Running、Enabled；登录触发，失败重试5次、间隔1分钟，IgnoreNew；电池切换不停。wrapper PID22704 → Node PID12064，Node开始2026-10-05 10:49:29.867+08:00。`127.0.0.1:47841`归此Node；`GET /v1/core/health`=200、schema4、protocol0.1。 |
| Remote MCP | 计划任务 `\HereIAm-iRemoteMCP`：Running、Enabled；同为登录触发、重试5次/1分钟、IgnoreNew、电池切换不停。wrapper PID22648 → Node PID22260，Node开始2026-10-05 10:49:22.381+08:00。`127.0.0.1:47860`和`:47862`同属此Node；47860 `/.well-known/oauth-protected-resource`=200；47862 `/v1/remember/changes`未认证=401。 |
| Cloudflare | 服务名 `Cloudflared`，显示名 `Cloudflared agent`：Running、Auto，PID13608，开始2026-10-05 10:49:07.734+08:00；失败恢复延迟5/15/60秒，计数复位86400秒。进程本地监听`127.0.0.1:47864`，`GET /ready`=200。此结果不证明公网claude.ai端到端调用。 |

入口及当次SHA256（路径仅用于定位，不包含启动参数）：

| 文件 | SHA256 |
|---|---|
| `D:\HereIAmRuntime\i-core\candidates\b3-v4-phone-transcripts-20261003\start_pinned_i_core.ps1` | `55ccaa5369687b3c3d9c888cc296b4d4ea16d8fdf3b0eb6dd8dbd97a3cf1b90f` |
| 同包 `tools/i_core/i_core_server.mjs` | `9ac97b01711bc580861f5d3aa2308846dad7606f5d28b4ba02939db83c269d46` |
| `C:\HereIAm\continuity-b0-b2-20261002\tools\i_remote_mcp\.state\runtime\start-remote.ps1` | `7557cdedbef33dd3d53b6655baef542e576653f45127893ff482b50521600799` |
| 同MCP副本 `tools/i_remote_mcp/server.mjs` | `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6` |
| `D:\Nodejs\node.exe`（现役MCP） | `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f` |
| `C:\Program Files (x86)\cloudflared\cloudflared.exe` | `20b9638f685333d623798e733effbad2487093f15ba592f6c7752360ff3b7ab7` |

Core Node为旧包内`runtime/node.exe`。旧Core共享锁名为`shortcut-mail-relay.runtime.lock`；文件存在不等于持锁、文件删除不等于释放。本次没有试停、探占运行锁或读取原库。上述HTTP探测不写业务数据；最初访问两服务`/health`均404，随后按真实路由校正，不能把404当服务离线。Cloudflare没有同名计划任务；任务和服务不是同一种停启机制。

## 2. 获准后怎么停与启动（当前不执行）

先保存原任务XML、Enabled、登录触发、失败恢复、服务启动类型与恢复动作等精确配置，清点所有实际writer/reader、桥和旁路启动来源。以下操作由 i 按审核通过的现场清单执行，Lynx无需复制命令或接触密钥。

| 对象 | 冻结及停止 | 实际停止确认 | 启动与确认 |
|---|---|---|---|
| 旧v4 Core | 冻结`HereIAm-iCore`任务的后续启动/失败重试，排除手动启动者。没有认证清停入口；必须先完成另审的非优雅停止与原始日志保全/adoption工程，才可批准停止任务及精确进程树。不得将Stop-ScheduledTask或kill称为clean close。 | 当次持柄身份/开始时间绑定的wrapper、Node及相关后代均退出，47841无旧监听，持续锁可被监督者独占且无其他SQLite句柄；旧包没有新guardian，不应索取不存在的guardian回执。任务停止不保证孤儿Node退出。 | 仅仍为完整兼容schema4、原状态/身份/授权文件未受迁移改变时，才可恢复已保全旧任务设置并启动原任务。旧wrapper先持锁、查端口、运行`verify_v4_state.mjs`，后者核8表形状、schema4且无activity元数据。仍需实测健康与功能，不能越过拒绝。 |
| 新schema6 Core | 先冻结其将来获准配置的启动任务；用固定包`lifecycle/request_stop.ps1`，绑定本次ControlDirectory、RunId、ManifestSha256，Action=close（stop同为认证动作）。密钥由脚本从受保护目录读取。 | `stop_requested`明确completion_confirmed=false。只有listener/store关闭、child真实exit0、guardian真实exit0、Job空、无强杀、最终marker=clean_closed、锁实际释放全部成立才完成。最长排空60秒；超时/强杀是recovery_required。 | 固定`start_schema6.ps1 -Start`，显式同包外锚、原址state、受保护配置和**每次新空control目录**；需固定生产端口（默认0只会随机分配）。正常重开只接受下节相同绑定，不用InitializeEmpty打开旧库。当前没有已部署schema6计划任务，也没有自动创建新control目录的生产启动接线。 |
| Remote MCP | 冻结`HereIAm-iRemoteMCP`，再停止任务及经当次绑定确认的子进程。源码server:516–518有SIGINT/SIGTERM关闭HTTP/phone feed/read model/ledger，但Windows任务终止不证明信号处理已完成，无同等认证clean receipt。迁移窗口须停它以释放Core读取句柄、暂停网页写回与remember消费者入口。 | wrapper/Node及后代退出，47860、47862均无该监听，相关DB句柄释放；保全writeback账本/日志侧文件。不能仅因47860关闭忽略47862。 | 恢复原动作与保护文件后启动原任务；核真实路径/哈希、两个端口、OAuth元数据/401边界。内存MCP session重建，旧session可收到404并需重新initialize；不应重配/吊销token作为普通重启步骤。 |
| Cloudflared | 它是隧道，不是Core writer。若现场范围包含关闭公网入口，先核服务是否还承载其他站点，保全并临时冻结Auto及失败恢复，再Stop-Service精确服务。只禁用开机启动不等于处理全部恢复来源。 | SCM=Stopped且当次cloudflared进程实际退出、47864旧监听消失；公网不可达的页面不是唯一证据。 | 恢复原Auto及5/15/60秒失败恢复设置，Start-Service；SCM Running、正确进程/哈希、47864/ready成功，再由公网客户端验证。启动隧道不等于MCP或Core可用。 |

重启顺序通常Core→MCP→Cloudflare；停止时先阻断客户端入口/暂停消费者再Core。确切集合与顺序由现场inventory决定，不能扩大到无关Tailscale、其他服务或手机。确认任务未重新拉起应覆盖其1分钟重试周期，并结合冻结设置/进程监视；有限观察不能证明没有未知外部启动者。

## 3. 正常关机、睡眠和意外断电

| 情况 | 真实边界与人工处理 |
|---|---|
| Windows正常关机/重启 | 新wrapper没有SessionEnding/关机事件接线。SIGINT/SIGTERM也被runtime_child视为未经认证停止并带失败，不能推断点“关机”会生成clean_closed。停机前由 i 认证清停并等全部回执；否则即使Windows正常退出也可能成为unclean。旧v4无该入口，不能追认优雅停止。 |
| 睡眠后正常唤醒 | 纯睡眠通常暂停进程并保留Job/打开句柄，既不是清停也不是新启动；这是OS语义推断，本轮没有真实睡眠Gate。唤醒先核原父/child/guardian身份、锁、监听与健康。不能因网络短暂失联删除锁或再开第二实例。任何进程消失/异常状态转入恢复审查。 |
| 假唤醒、系统时间前跳 | 通用activity lease可因时钟跨度过期，不得仅凭“醒了”清claim。此固定候选明确activity=false、reply jobs=false，不能把其他active部署的过期claim场景冒充本候选实测，也不能因关闭activity就忽略已有残留claim：preflight仍要求runtime_id为空且lease_expires_at_ms=0。 |
| 没电、强制关机、蓝屏、父/guardian/child死亡 | 可能留下opening/running/recovery_required或sidecar，甚至来不及写失败marker。Job的kill-on-close能限制孤儿，不代表SQLite清停或回执必落盘。冻结重试，保留原DB与日志、control回执、当前独立custody/head；保持停机，待受审恢复流程。不能删marker/sidecar/claim、改role或伪造clean_closed。 |
| 下一次登录自动启动 | 当前两个旧任务是**登录触发**，不能称开机即启动；Cloudflared为Auto。旧v4仅在原schema4/包/配置/锁/端口等预检成立时可启动。新6未来即使接登录任务，也仅在上次真实clean_closed、原canonical路径/node、同manifest/配置/完整state摘要、独立custody当前head、DPAPI用户/ACL都匹配，无sidecar/claim、锁与端口可用，并生成新空control目录时可成功。沿用上次非空control会直接拒绝。 |

同新包普通重启还有环境注入/目录链接/额外发行文件等拒绝项。改包、改配置或外置grant/replay、增添state文件不是“重启一下”能解决的情况，需要受审转换路径。不存在已交付的通用repair/reset/自动恢复命令；`-OfflineOperation verify|migrate|rollback`仍要求可信supervisor谱系，不能替代unclean修复或旧v4首接。

## 4. 用户会看到什么

以下是源码行为，未现场断网/停机试验，也不代表现装手机当下连接和队列已经核验。

| 路径 | Core单独停机（MCP/其他依赖仍可用） | MCP或隧道停机 |
|---|---|---|
| B3手机聊天同步 | 本地已入库聊天及outbox保留，只有accepted响应才移除队列；传输错误提示核心离线、稍后补交。启动、消息写入、前台30秒、resume/手动触发再同步。认证/协议/冲突需处理原因，不能保证无限自动重试成功。模型回复、联网工具和新消息生成仍取决于各自依赖，不承诺全部离线可用。 | 直连Core聊天是否受影响取决于实际连接路由；本轮不读取手机配置。手机remember拉取47862会失败，不能因此跳cursor或假ack。 |
| claude.ai旧`i_chat_turn` | MCP先将本轮写入本机writeback账本，Core不可达返回core_status=unavailable、waiting_for_retry，下次chatTurn调用flush同一pending；不是独立后台定时补交。前提是MCP/账本及read model可正常使用，Core迁移时不能依赖仍开的read model。 | 新调用到不了MCP，没有本机ACK或新的本机缓冲证明；已耐久pending保留。claude.ai界面重试策略未测，不承诺自动重放；恢复后检查回执避免人为重造相同消息。 |
| 现役旧`i_remember` | 写MCP自己的notes账本，不依赖Core提交；waiting_for_phone表示待手机消费。47862可用且手机配置/Organizer依赖可用才有可能继续成卡。apply成功后才ack、再前进cursor；旧账本不等于新Core captures。 | MCP停机则网页新记忆请求和手机feed都失败；只有隧道停机时手机的Tailscale feed是否仍可达依实际路由，不能一并断言。此前note/revision与投递状态保留，不凭active=0退役桥。 |
| 新域`day_get` / Core版remember | 现役旧MCP源码未注册day_get。准备包中day_get读取Core域HTTP，无离线缓存/写回队列；传输异常返回transport_unknown/core_unavailable、retryable=true。读日条成功但标题读取失败会列item_title_issues。Core版remember写入失败/未知不能借旧notes账本宣称已记录，重试写操作必须保留同op_id。 | 工具不可达；没有已取得的成功回执就不声称获取了最新日单或写入成功。启用这些能力还需MCP配置/凭据/域权限与客户端Gate。 |

## 5. 退回与剩余缺口

**“新Core没有聊天新增”不等于“库未变”。** 4→5→6迁移、genesis/custody写入、设备/序号/权限/游标变化本身都算改变。

- 尚未执行恢复/迁移/新Core写入：保全原始source DB及其WAL/SHM/journal、完整旧包、配置、任务、grant/replay、凭据、MCP账本和关闭状态；确认仍兼容schema4后，才讨论恢复原任务。保留失败候选和回执，不覆盖原source。旧v4的副本预检只是启动守卫，不是完整恢复与ACK保全证明。
- 已进入原址恢复或任何迁移/新写入：保持受影响writer停机，保全新接受数据和各阶段证据，优先前向修复。新6空domain的6→5受限回退不等于退回v4；旧v4明确拒绝新增activity表/元数据。没有已实现的安全6→4操作。
- 不把backup_read_only改live，不恢复整库抹去新数据，不回退库外current-head，不用旧DB+旧marker+旧floor套装重获资格。
- 必须先补：旧v4非优雅首接adoption；SQLite打开前原始DB/所有实际sidecar流式加密保全；原址恢复/checkpoint证据；库外不可回退阶段链及各阶段中断恢复；完整运行inventory及恢复验证。普通backup bundle拒绝sidecar，不能拿它冒充原始日志恢复备份。
- 还需生产任务封装（新空control/同用户DPAPI/配置绑定）、真实旧库副本/授权行为验证、精确候选测试/审核、Core停启迁移现场决定、MCP与手机各自切换Gate。手机schema62兼容和captures增改删/用户改卡保护未实机验收前，保留47862与单一消费者；legacy_b3和PR10不得双上传。
- 用户允许先禁用Shortcut调试邮件；将此选择绑定候选配置与备份清单，仅暂停该调试邮件链。固定入口的发送与回执查询返回HTTP503/`shortcut_mail_disabled`；SMTP配置、DPAPI凭据与journal均已保全，不自动重发在途邮件。不能由relay=false推断一般通讯、手机聊天、MCP或所有通知已兼容。

详细首接方案见[部署runbook](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)；本页不重复签发部署授权。

## 6. 可复核源码索引与worker交付

新准备树：`tools/i_core/release_schema6/lifecycle/{start_schema6.ps1,request_stop.ps1,runtime_child.mjs,common.mjs,owned_job.ps1,job_guardian.ps1}`；恢复`recovery_adapter.mjs`，完整备份`backup_bundle.mjs`；新版`tools/i_remote_mcp/domain_tools.mjs:66–145`。对应[生命周期交接](SCHEMA6_LIFECYCLE_20261006.md)、[恢复交接](SCHEMA6_RECOVERY_ADAPTER_20261006.md)。

现役源码：旧固定包`start_pinned_i_core.ps1:129–164`、`verify_v4_state.mjs`、`i_core_server.mjs:346–402`；MCP副本`writeback.mjs:293–317,468–604`、`mcp.mjs:306–346`、`server.mjs:249–273,484–518`。B3手机源码树`C:\HereIAm\b3-writeback-local-20261003`中`core_sync_engine.dart:72–145`、`core_sync_runtime_service.dart`、`main.dart:1880–1920`、`claude_web_note_feed_service.dart:91–175`；现装包绑定仅沿用`codex/predeploy-audit-20261005`的`PREDEPLOY_AUDIT_20261005.md`明确时间窗，不声称本轮重新查看手机。

worker仅新增本页与本人操作单；复用recovery工作树，原有未跟踪backup/lifecycle依赖不暂存，不改全局状态/源代码。仅文档链接、事实对照与diff空白检查，无构建、生产动作或push。提交按已授权隔离worker例外临时设置SKIP_PROJECT_STATE=1并finally恢复；最终全局状态、精确提交测试及PR由主窗整合。

主窗本轮[52项真实保全与恢复](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)已闭合；它是在线分别一致副本的检查恢复，不替代原址unclean首接工程与生产停启演练。
