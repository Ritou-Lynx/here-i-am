# 登录驻留与 Windows 关机会话候选（2026-10-06）

拥有路径：新 `lifecycle/session_window.ps1`、`login_schema6.ps1`、`prepare_login_schema6.ps1`、`session_lifecycle.test.mjs`、test-only 消息/进程故障/共享发布 helper，固定库存新增三条。后续授权对 owned_job.ps1 做控制文件只读持柄共享兼容修复；未改原 start/runtime 认证契约或生产 ACL；恢复功能依赖独立恢复工作包。无现役 Task 注册、服务启动、配置切换或真实关机。

## 行为与边界

- 固定发行 manifest hash、全部文件字节、pinned Node、plain path、ACL gate 先通过；独立 `schema6-login-v1` 配置 SHA256 绑定发行、SID、Core 配置 SHA、状态根、control根、端口和可选 backup 配置 SHA。运行期间保留发行与配置只读持柄。
- 每次登录创建独立随机 session/control；先创建隐藏顶层 HWND 和 shutdown block reason，再启动 Core。Core 父 PowerShell 和 backup scheduler PowerShell 根均使用 CreateProcess suspended→assign kill-on-close Job→resume，覆盖后代。窗口从不显示或取焦点。
- WM_QUERYENDSESSION 立即答 TRUE 并异步禁止备份派发；当前备份最多5秒优雅结束，之后终止其拥有 Job 并确认空。Core 使用 launch PID/startticks/token/hash 绑定的 HMAC close。WM_ENDSESSION 最多等待30秒；检查真实父退出0、outer Job为空、child/guardian退出0、生产 supervisor/marker同run clean_closed及实际锁可重开。超时不写 clean 权威；拥有树退出回执单独记录。
- 关机取消后等待上一代完成，使用新 control 自动启动。普通 Core/guardian 退出时，只有上一代曾ready且父退出/Job为空，才在同一登录会话退避1秒做一次恢复启动；恢复后健康ready稳定30秒再恢复重试额度，启动检查失败/短时间第二次失败终止驻留，避免无限重试绕 Gate。
- 备份参数固定为 scheduler 的 ReleaseDirectory/ManifestSha256/KeyDirectory/ConfigPath/ConfigSha256，入口在 `release_schema6/scheduler_once_schema6.ps1`。未对未完成的备份声称成功。
- PrepareOnly 仅生成 XML；InteractiveToken、LeastPrivilege、LogonTrigger、IgnoreNew、PT0S、不因电池切换停机、无 Task retry。要求独立配置明确非零端口；合成 runtime 允许0，不占现役固定端口。生成不等于注册或启用。

## 已验证与仍待验证

- 新 C# 在目标 Windows PowerShell 5.1 编译通过。
- 首轮真实隐藏 HWND 定向演练已通过取消关机→新control重启→关闭，以及 PrepareOnly XML/端口/hash/拒绝覆盖两组。最初并发HTTP版本接受0条不能作为写入关机证据，已废弃并替换。
- 精确事务版两组通过（162358ms）：独立 synthetic Git 对 `i_core_store.mjs` 的 `#persistMessages` 仅加 `BEGIN IMMEDIATE` 后限时文件屏障，再由真实 prepareRelease 构建/校验固定包。实际事务屏障已进入时发送 query，观察真实 HMAC close 文件已发布且屏障未放行，再释放；必须HTTP接受1条。之后另一次真实 login 的 HTTP changes 读回同一sync id。该源差异仅为合成固定包 instrumentation，生产无开关，不是线上/真人 Gate。
- 与恢复功能 199f7d38 整合后原四组全过：`build/ci/session-final.tap` 4/4，0 fail/skip，370712ms。30秒真实deadline演练按拥有Job+exe身份暂停合成Core，确认拥有树退出、无clean，下一login实际恢复。相同host内杀Node后freshcontrol、HTTP changes读回同一数据通过（98169ms）。WM_CLOSE在forcedTimeout时必须让Form退出；该修正后timeout单项另过1/1（143987ms，`session-timeout-final.tap`）。
- 共享 `test-fixture.mjs` 归恢复worker所有，本包不复制提交。完整8.3 CI修复验证见同目录 `SCHEMA6_CI_REPAIR_20261006.md`。

worker单次提交使用既有 SKIP_PROJECT_STATE=1，finally恢复；主窗负责最终库存、DEVLOG/当前态、整合回归及PR更新。未push。

## 新入口二审收口

- login/prepare自包含plain path、祖先非reparse及现有owner/ACL门控；manifest及候选文件先打开FileShare.Read持柄，native确认单硬链接和最终规范路径，再核对SHA256。验证期间不允许写入/替换候选。未改原production protected_paths或Core门控。
- login、Core配置、backup配置JSON解析异常只输出固定拒绝码；prepare同样收口。嵌套验证器stdout/stderr由ProcessStartInfo异步私下捕获，避免Windows PS 5.1把Node ExperimentalWarning当NativeCommandError，并不转发解析上下文。session close仅允许显式固定reason，其余内部错误固定码；保留startup Gate与retry耗尽原因。
- backup启动异常单独处理并退避，构造中部分创建的进程/Job由持有者收口；worker真实退出且Job空后按ExitCode写backup_completed/backup_worker_failed。状态为独立原子JSON，只有固定status、success与next_attempt_utc；失败不关闭健康Core。磁盘不能写状态时不把失败状态伪称成功，也不为状态写失败关闭Core。
- malformed随机secret（login/core/backup三种）ValidateOnly与PrepareOnly专项已通过；备份launch/worker故障保持Core health200且均真实cleanclose，最终专项4/4（含嵌套父测试计数），0 fail/skip，136643ms；见 session-backup-isolation-final.tap。

验证命令：`D:\Nodejs\node.exe --test --test-reporter=tap --test-reporter-destination=build/ci/session-final.tap tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs`；forcedTimeout后使用 `--test-name-pattern="shutdown timeout"`；二审后使用 `--test-name-pattern="login preparation|backup launch"` 生成 `session-review-fixes-final.tap`。C#目标Windows PowerShell5.1编译与Node语法检查通过。

## 关闭发布共享冲突的确定性根因

- 二审新备份worker失败演练先通过固定失败状态与Core health200，但随后的合法close触发 supervisor native_error32、child124；session正确不认clean。保存于 session-review-fixes-final.tap，未按重试掩盖。该轮仅malformed/Prepare与backup launch完成全通过，worker关闭失败保留。
- RequestClose只写关闭后的pending再File.Move，本次并未读取既有close。Windows rename在目标名可见时仍可持有DELETE权限句柄；旧 File.ReadAllText 使用FileShare.Read，与该发布句柄冲突。依据 [Microsoft官方Windows文件重命名说明](https://devblogs.microsoft.com/oldnewthing/20211022-00/?p=105822) 和确定性native复现。
- ReadOptionalControl改为单只读FileStream持柄并共享Read|Delete（仍拒写），核验单hardlink和最终canonical path，再读同一持柄字节供现有HMAC/token比较。不catch共享异常，不重试，不修改plainPath/ACL或认证条件。允许发布者完成rename，不接受伪造认证。
- probe_control_read_sharing.ps1 使用native SetFileInformationByHandle发布后故意保留DELETE句柄；旧reader确定error32，新reader正确读取认证字节，伪造值不匹配，另一个只读句柄并发兼容。helper首轮PowerShell反射参数包装错误已改为C#类型化调用，独立最终证明1/1，12862ms，session-sharing-proof-final.tap。备份两个完整close回归最终均通过，见下方最终命令。

- 后续fixture枚举曾只按backup-status前缀，误把原子写入的 .json.guid.pending 当正式回执读而出现EBUSY；修为同时要求 .json 后缀，只读取原子发布的目标。没有放宽pending独占写，也没有catch后重试来隐藏不完整文件。该失败保留在session-control-publish-final.tap（其中launch已完成cleanclose通过，reader helper首次反射包装失败另由专项修正通过）。

最终低并发专项命令：`D:\Nodejs\node.exe --test --test-concurrency=1 --test-name-pattern="control reader|backup launch" --test-reporter=tap --test-reporter-destination=build/ci/session-backup-isolation-final.tap tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs`。结果4/4，136643ms；launch 62129ms、worker 62260ms，均确认失败固定状态、未来retry时间、Core health200和真正cleanReceipt。该worker分支未集成portable scheduler，worker非零退出用缺少scheduler入口的真实PS失败；整合后同用例的空配置会被实际scheduler拒绝，需主窗完整库存复验。malformed/Prepare专项1/1（34945ms）包含login/core/backup三种随机secret不外泄。最终git diff --check通过。

## session ready / launch 原子发布同类竞争（最后窄验证）

- 基线为本worker 28ae524b。只在隔离分支使用受保护合成目录，dot-source编译C#并调用私有ReadProtected；未启动Core、窗口、服务、Task或手机操作。
- 复现日志 `build/ci/session-reader-sharing-repro.tap`：1项预期失败（13375ms），native rename已经使ready.json/launch.json可见且仍持DELETE句柄时，两项读取均false、session_sharing_violation=true；并发writer及hardlink原有拒绝均true。故Tick在File.Exists之后仍可能因发布者短暂DELETE句柄触发错误关闭。
- 生产最小修改仅ReadProtected的FileStream共享标志 Read→Read|Delete，仍FileAccess.Read、仍拒写；Protected的plain/祖先非链接/ACL、持柄单hardlink/finalcanonical、大小限制及认证逻辑全不变。没有吞共享异常或重试。
- test-only helper补充session私有reader类型化反射分支。最初fixture原生重命名结构未显式补UTF16终止零，出现launch.jsonl，已补分配并清零终止空间，再执行上述确定性红灯；初轮输出保存session-reader-sharing-before.tap，不当生产失败证据。
- 修复后 `build/ci/session-reader-sharing-final.tap`：2/2，0 fail/skip，25290ms。session ready_read/launch_read=true、session_sharing_violation=false，同时old_reader_sharing_violation/writer_rejected/hardlink_rejected=true；原owned control reader并发证明亦通过。
- 命令：`D:\Nodejs\node.exe --test --test-concurrency=1 --test-name-pattern="control reader|session protected reader" --test-reporter=tap --test-reporter-destination=build/ci/session-reader-sharing-final.tap tools/i_core/release_schema6/lifecycle/session_lifecycle.test.mjs`。git diff --check通过。未改主窗或shared其他文件，未push；此次提交仍仅用既有SKIP_PROJECT_STATE=1且finally恢复。
