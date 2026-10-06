# schema6 运行操作与故障边界（审核草案，2026-10-06）

本页给执行者 i 使用；本人版见 [一页上线操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)。本轮只读核验和文档准备造成的现役停机为 **0**，没有停启、冻结任务、修改配置/原库或操作手机。草稿 PR 不是部署批准。本轮继续在 PR14 实现自动关机、登录恢复与旧 v4 副本接管；精确源码/演练结果以[本轮验收](SCHEMA6_AUTOMATIC_MAIN_ACCEPTANCE_20261006.md)为准，生产切换仍未获批准。

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
| 旧v4 Core | 冻结`HereIAm-iCore`任务的后续启动/失败重试，排除手动启动者。没有认证清停入口；须使用本轮副本接管机制并核精确进程/任务清单，获得现场批准后才停止任务及精确进程树。不得将Stop-ScheduledTask或kill称为clean close。 | 当次持柄身份/开始时间绑定的wrapper、Node及相关后代均退出，47841无旧监听，持续锁可被监督者独占且无其他SQLite句柄；旧包没有新guardian，不应索取不存在的guardian回执。任务停止不保证孤儿Node退出。 | 仅仍为完整兼容schema4、原状态/身份/授权文件未受迁移改变时，才可恢复已保全旧任务设置并启动原任务。旧wrapper先持锁、查端口、运行`verify_v4_state.mjs`，后者核8表形状、schema4且无activity元数据。仍需实测健康与功能，不能越过拒绝。 |
| 新schema6 Core | 先冻结其将来获准配置的启动任务；用固定包`lifecycle/request_stop.ps1`，绑定本次ControlDirectory、RunId、ManifestSha256，Action=close（stop同为认证动作）。密钥由脚本从受保护目录读取。 | `stop_requested`明确completion_confirmed=false。只有listener/store关闭、child真实exit0、guardian真实exit0、Job空、无强杀、最终marker=clean_closed、锁实际释放全部成立才完成。最长排空60秒；超时/强杀是recovery_required。 | 固定`start_schema6.ps1 -Start`，显式同包外锚、原址state、受保护配置和**每次新空control目录**；需固定生产端口（默认0只会随机分配）。正常重开只接受下节相同绑定，不用InitializeEmpty打开旧库。本轮新增交互式登录任务准备模板与隐藏驻留 launcher，自动创建新空 control；只生成 XML，不注册或改动现役任务。 |
| Remote MCP | 冻结`HereIAm-iRemoteMCP`，再停止任务及经当次绑定确认的子进程。源码server:516–518有SIGINT/SIGTERM关闭HTTP/phone feed/read model/ledger，但Windows任务终止不证明信号处理已完成，无同等认证clean receipt。迁移窗口须停它以释放Core读取句柄、暂停网页写回与remember消费者入口。 | wrapper/Node及后代退出，47860、47862均无该监听，相关DB句柄释放；保全writeback账本/日志侧文件。不能仅因47860关闭忽略47862。 | 恢复原动作与保护文件后启动原任务；核真实路径/哈希、两个端口、OAuth元数据/401边界。内存MCP session重建，旧session可收到404并需重新initialize；不应重配/吊销token作为普通重启步骤。 |
| Cloudflared | 它是隧道，不是Core writer。若现场范围包含关闭公网入口，先核服务是否还承载其他站点，保全并临时冻结Auto及失败恢复，再Stop-Service精确服务。只禁用开机启动不等于处理全部恢复来源。 | SCM=Stopped且当次cloudflared进程实际退出、47864旧监听消失；公网不可达的页面不是唯一证据。 | 恢复原Auto及5/15/60秒失败恢复设置，Start-Service；SCM Running、正确进程/哈希、47864/ready成功，再由公网客户端验证。启动隧道不等于MCP或Core可用。 |

重启顺序通常Core→MCP→Cloudflare；停止时先阻断客户端入口/暂停消费者再Core。确切集合与顺序由现场inventory决定，不能扩大到无关Tailscale、其他服务或手机。确认任务未重新拉起应覆盖其1分钟重试周期，并结合冻结设置/进程监视；有限观察不能证明没有未知外部启动者。

## 3. 正常关机、睡眠和意外断电

这是待审核候选的规则，**不表示现役旧 v4 已有这些能力**。Core 只在登录用户的交互式会话运行；每次登录创建新的 protected control，发行包、配置外锚与密钥绑定均先检查。

| 情况 | 候选的下一步与阻断条件 |
|---|---|
| 正常关机/注销/重启 | 隐藏顶层窗口接收 WM_QUERYENDSESSION，登记 ShutdownBlockReason 并迅速返回；停止备份派发，关闭正在运行的备份 Job，然后发认证 request_stop close。WM_ENDSESSION 在有界预算内等实际 listener/store、child、guardian、Job、锁全部完成。超时不伪造 clean_closed，下次登录按异常恢复。 |
| 关机时正在写入 | 相同的认证关闭，SQLite 事务与关闭流程负责完成已接受写入；验证写入后下次新 control 重开数据仍在。不能只看 stop_requested 就认为完成。 |
| SIGINT/SIGTERM | 能真正关闭 listener/store 并封存独立 custody 时按正常关闭记账，不因信号本身一律记成 recovery_required。Win 强杀与可以处理的信号分开测试。 |
| 睡眠/唤醒 | 没有注销时保留原会话进程/Job/锁，唤醒不额外启动。纯睡眠 OS 行为本轮未实际改变电脑状态；若进程异常退出，下次受监督启动按异常规则。 |
| 没电、强杀 Node/guardian/父进程、蓝屏 | 可能无最后回执或留下 WAL/SHM/journal。下一次登录先持真实锁、排除 writer，再在任何 SQLite 打开前流式加密保全原始文件；副本正常打开回放 WAL，检查 integrity、独立 current-head、schema、身份与配置。通过则记录恢复事件、完成替换并启动，不要求每天人工解锁。 |
| 自动检查失败 | 完整性/绑定失败、custody 回退、迁移或提交中断等停止并记录无正文原因；原件/原始密文/独立 head 保留。Lynx 只需保持文件原样，把原因和回执编号交给 i。未知错误不通过删除锁/sidecar或重新签 baseline 修复。 |
| 关机被取消 | 若钩子已把 Core 关闭，会话仍有效时以新 control 重开；不沿用旧 token 或同时开两个实例。 |

Windows 的关机预算并非承诺：系统可以强制结束进程，隐藏应用尤其不能靠长时间阻塞保证安全。ShutdownBlockReason 用于说明保存原因并争取正常关闭机会，强制终止仍由下一次自动恢复兜底。依据 [WM_QUERYENDSESSION](https://learn.microsoft.com/en-us/windows/win32/shutdown/wm-queryendsession) 和[微软关机行为说明](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/mpc/application-shutdown-changes-in-windows-vista)。本轮只对合成会话 HWND 发送关机消息，并未真正关机、注销、睡眠或测试当前服务。

恢复在原 canonical 绑定下准备隔离副本，不给 backup_read_only 副本激活权限。验证 prefix 保护已封存的不可变操作历史及单调序号；正常领域编辑和同设备重新配对不能被误报为回退。它不能证明最后封存之后尚未留下独立证据的每一条客户端 ACK；仍须原 sync_id/op_id 幂等对账。

正常重开仍严格校验 manifest、显式配置/外置 grant/replay、用户 DPAPI、ACL、路径和单一上传器，生产 plainPath/链接检查未放宽。改配置/包需要受审转换，不借 crash recovery 自动批准新配置。`OfflineOperation verify|migrate|rollback` 不作为绕过异常检查的手动捷径。

## 4. 用户会看到什么

以下是源码行为，未现场断网/停机试验，也不代表现装手机当下连接和队列已经核验。

| 路径 | Core单独停机（MCP/其他依赖仍可用） | MCP或隧道停机 |
|---|---|---|
| B3手机聊天同步 | 本地已入库聊天及outbox保留，只有accepted响应才移除队列；传输错误提示核心离线、稍后补交。启动、消息写入、前台30秒、resume/手动触发再同步。认证/协议/冲突需处理原因，不能保证无限自动重试成功。模型回复、联网工具和新消息生成仍取决于各自依赖，不承诺全部离线可用。 | 直连Core聊天是否受影响取决于实际连接路由；本轮不读取手机配置。手机remember拉取47862会失败，不能因此跳cursor或假ack。 |
| claude.ai旧`i_chat_turn` | MCP先将本轮写入本机writeback账本，Core不可达返回core_status=unavailable、waiting_for_retry，下次chatTurn调用flush同一pending；不是独立后台定时补交。前提是MCP/账本及read model可正常使用，Core迁移时不能依赖仍开的read model。 | 新调用到不了MCP，没有本机ACK或新的本机缓冲证明；已耐久pending保留。claude.ai界面重试策略未测，不承诺自动重放；恢复后检查回执避免人为重造相同消息。 |
| 现役旧`i_remember` | 写MCP自己的notes账本，不依赖Core提交；waiting_for_phone表示待手机消费。47862可用且手机配置/Organizer依赖可用才有可能继续成卡。apply成功后才ack、再前进cursor；旧账本不等于新Core captures。 | MCP停机则网页新记忆请求和手机feed都失败；只有隧道停机时手机的Tailscale feed是否仍可达依实际路由，不能一并断言。此前note/revision与投递状态保留，不凭active=0退役桥。 |
| 新域`day_get` / Core版remember | 现役旧MCP源码未注册day_get。准备包中day_get读取Core域HTTP，无离线缓存/写回队列；传输异常返回transport_unknown/core_unavailable、retryable=true。读日条成功但标题读取失败会列item_title_issues。Core版remember写入失败/未知不能借旧notes账本宣称已记录，重试写操作必须保留同op_id。 | 工具不可达；没有已取得的成功回执就不声称获取了最新日单或写入成功。启用这些能力还需MCP配置/凭据/域权限与客户端Gate。 |

## 5. 退回与剩余现场 Gate

旧 v4 首接与异常恢复共用原始文件保全、隔离副本打开/迁移/校验、提交替换机制。获准现场操作时先冻结旧任务、结束绑定的进程树，不能将旧进程被终止伪装成 clean close；真实 offline lease 才能开始保全。

- **替换前**：原 DB/WAL/SHM/journal 未改，即使副本迁移中断也保留原件和加密保全。确认候选进程已停、原件仍是兼容 schema4 后可以重开旧 v4；不需要一条另行“不可重做”的 adoption 阶段链。
- **替换已开始或新 Core 已写入**：不盲目切回旧 v4。保全新文件/原始密文/回执并向前修复；数据库单文件替换与 sidecar/独立 head 之间有提交间隙，留下 pending 时必须明确人工审查，不能删除 latch 后假装成功。
- 库外 authenticated current-head 仍独立保持最新，不随旧 DB/marker/floor 一起倒退；既有5/6不能从目标自己再签一份 floor。只读还原目录不能启动为 live；无安全自动6→4。
- 固定入口关闭 Shortcut 调试邮件，仅发送/调试回执链返回 `shortcut_mail_disabled`；保留 SMTP 配置/DPAPI凭据/journal，不自动重发在途邮件。一般聊天/MCP/手机能力另验，不需要为 debug 邮件兼容阻塞本轮源码。
- 现场 Core 停启/迁移、登录任务注册、真实密码设置/外部复制目录、MCP切换、手机安装与客户端 Gate 仍各按确切授权执行。此次不操作其中任何一项。
- captures 真实新增/改版/删除和用户改卡保护未过，继续保留47862；每次只一个消费者。legacy_b3与PR10仍只一个上传器。
- Tailscale 机器私钥按 Lynx 决定不备份，不再列成待补缺口；换机重新登录同一 tailnet/机器名，服务与手机地址重配见[换机说明](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)。

详细源码与六类演练回执见[本轮验收](SCHEMA6_AUTOMATIC_MAIN_ACCEPTANCE_20261006.md)、[副本恢复](SCHEMA6_AUTOMATIC_RECOVERY_20261006.md)、[口令备份](SCHEMA6_PORTABLE_AUTOBACKUP_20261006.md)。没有第二账号/第二机器实测时明确记录，不用同用户子进程替代。

## 6. 可复核源码索引与worker交付

新准备树：`tools/i_core/release_schema6/lifecycle/{start_schema6.ps1,request_stop.ps1,runtime_child.mjs,common.mjs,owned_job.ps1,job_guardian.ps1}`；恢复`recovery_adapter.mjs`，完整备份`backup_bundle.mjs`；新版`tools/i_remote_mcp/domain_tools.mjs:66–145`。新增 `login_schema6.ps1`、`session_window.ps1`、`prepare_login_schema6.ps1`，原始流式保全/自动副本恢复与口令/每天备份固定工具一并入 manifest。原[生命周期交接](SCHEMA6_LIFECYCLE_20261006.md)、[恢复交接](SCHEMA6_RECOVERY_ADAPTER_20261006.md)记录上一轮历史；本轮新结论以自动运行交接为准。

现役源码：旧固定包`start_pinned_i_core.ps1:129–164`、`verify_v4_state.mjs`、`i_core_server.mjs:346–402`；MCP副本`writeback.mjs:293–317,468–604`、`mcp.mjs:306–346`、`server.mjs:249–273,484–518`。B3手机源码树`C:\HereIAm\b3-writeback-local-20261003`中`core_sync_engine.dart:72–145`、`core_sync_runtime_service.dart`、`main.dart:1880–1920`、`claude_web_note_feed_service.dart:91–175`；现装包绑定仅沿用`codex/predeploy-audit-20261005`的`PREDEPLOY_AUDIT_20261005.md`明确时间窗，不声称本轮重新查看手机。

本页保留上一轮现役只读取证时间窗；本轮不重新访问这些对象。主窗整合新源与文档、验证并更新同一PR，不合主线或部署。

主窗本轮[52项真实保全与恢复](SCHEMA6_REAL_BACKUP_RESTORE_20261006.md)已闭合；它是在线分别一致副本的检查恢复，不替代原址unclean首接工程与生产停启演练。
