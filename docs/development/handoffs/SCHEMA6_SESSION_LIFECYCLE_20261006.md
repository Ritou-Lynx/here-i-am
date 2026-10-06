# 登录驻留与 Windows 关机会话候选（2026-10-06）

拥有路径：新 `lifecycle/session_window.ps1`、`login_schema6.ps1`、`prepare_login_schema6.ps1`、`session_lifecycle.test.mjs`、两个 test-only 消息/进程故障 helper，固定库存新增三条。未改原 start/runtime 子进程契约或生产 ACL；恢复功能依赖独立恢复工作包。无现役 Task 注册、服务启动、配置切换或真实关机。

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
- 新增30秒真实deadline演练通过按拥有Job+exe身份暂停合成Core；期望拥有树终止、无clean并下一login真实恢复。新增同host内杀Node→新control→数据HTTP读回。目前这两组需与恢复工作包整合后执行，不能先报通过。
- 共享 `test-fixture.mjs` 归恢复worker所有，本包不复制提交。完整8.3 CI修复验证见同目录 `SCHEMA6_CI_REPAIR_20261006.md`。

worker单次提交使用既有 SKIP_PROJECT_STATE=1，finally恢复；主窗负责最终库存、DEVLOG/当前态、整合回归及PR更新。未push。
