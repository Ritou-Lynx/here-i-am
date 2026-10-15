<!-- relay:contract v1 -->
## 目标
在 GitHub hosted Windows 上用真实交互会话 + 真实注销复现 A0（会话宿主 powershell 在窗口消息处理前被终止，退出码 0xC000013A），并对照一个候选修法变体，得到可重复的自动证据。只做复现，不改运行时。

背景：主合同 `RELAY_20261012_core-release-r1.md` 的“L”节与“审核发现”第 4 条。现役会话由登录触发的计划任务启动：交互令牌、`powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File <login 脚本>`；宿主带控制台（隐藏），隐藏顶层窗口接收 WM_QUERYENDSESSION/WM_ENDSESSION（见 `tools/i_core/release_schema6/lifecycle/session_window.ps1`）。现有 CI 只直接投递窗口消息，从未经历真实注销。hosted runner 默认没有可用的交互会话（R1 期间已见交互令牌任务起不来）。

## 完成标准
- [ ] 新增独立 workflow `.github/workflows/logoff-repro.yml`：`workflow_dispatch` + `pull_request`（base `v3-lab`，paths 仅限本合同允许路径），`runs-on: windows-latest`，`timeout-minutes` ≤ 30，`permissions: contents: read`。不加入、不修改 `ci.yml`，不成为必需检查。
- [ ] 会话建立：创建一次性本地标准用户（随机密码，只存在于该 job 内存/环境变量，不打印），开启 RDP，经回环（如 127.0.0.2）建立该用户的真实交互会话。客户端优先用系统自带 `mstsc` + `cmdkey`；不可行时可用固定版本、校验 sha256 的第三方客户端。先打印诊断：runner 进程会话号、`query session` 输出（脱敏用户名可保留测试用户名）。
- [ ] 探针按生产形状启动：为测试用户注册 LogonTrigger、交互令牌计划任务，动作与上面生产命令行形状一致（同样的 powershell 参数），`-File` 指向探针脚本。至少两个变体，各自独立计划任务、独立证据目录：
  - A（现状）：宿主保持控制台；建隐藏顶层窗口（WinForms），收到 WM_QUERYENDSESSION/WM_ENDSESSION 时同步写入并 flush 一行 JSON（含消息名、wParam/lParam、单调时间）；`SetConsoleCtrlHandler` 记录 CTRL_LOGOFF_EVENT/CTRL_CLOSE_EVENT（同样同步落盘）；用 CREATE_NO_WINDOW 启动一个 node 子进程，子进程记录自己收到的信号/退出；就绪后写 ready 文件。
  - B（候选修法）：同 A，但宿主启动后先 `FreeConsole`，再建窗口，并在 QUERYENDSESSION 中调用 `ShutdownBlockReasonCreate`；子进程用 DETACHED_PROCESS。
- [ ] 两个变体都写出 ready 后，对该会话执行真实注销（`logoff <会话号>`，或在会话内 `shutdown /l`；两者都试时分别记录），等待会话消失（有上限）。
- [ ] 收集证据并在 job 日志和 `$GITHUB_STEP_SUMMARY` 输出一份 JSON 结论，每个变体：是否收到 QUERYENDSESSION、ENDSESSION、CTRL_LOGOFF；宿主退出码（任务 LastTaskResult 或探针自报），是否为 0xC000013A（3221225786）；子进程是否先于窗口消息被终止；时间线。上传证据目录为 artifact。
- [ ] job 结论规则：证据完整收集即为成功（不管复现与否），并在结论里写 `reproduced: true|false`；只有基础设施无法建立交互会话时才失败，并在结论里写明卡在哪一步。
- [ ] 全部探针与辅助脚本放在 `tools/i_core/test_fixtures/release_schema6/logoff_repro/`；PS 脚本能被 PowerShell 5.1 解析器无错误解析。

## 允许修改的路径
- `.github/workflows/logoff-repro.yml`（新）
- `tools/i_core/test_fixtures/release_schema6/logoff_repro/`（新）
- `docs/development/handoffs/RELAY_20261015_l-logoff-repro.md`（只由 Claude 改）

## 不做 / 边界
- **绝不在本机运行任何探针、注销、建用户、开 RDP、注册计划任务的脚本**：这些只在 hosted runner 上运行。本机只做语法解析检查。
- 不改 48 项 INVENTORY 内任何文件（含 `session_window.ps1`、`login_schema6.ps1`、`runtime_child.mjs`），不改 `ci.yml`、其他 workflow、维护工具。
- 不碰真实数据、账户、令牌；测试用户密码不进日志、artifact、提交。
- 不下载未固定版本或未校验哈希的二进制。
- 止损：L 合同限 2 轮（第 1 轮实现 + 第 2 轮返修）。两轮内拿不到可复现场景就停，保留“注销前手动停服”。同一错误在连续两个提交上出现即 blocked。

## 验证命令
- PowerShell 5.1 解析检查（对目录内每个 `.ps1`）：`powershell -NoProfile -Command "$e=$null;[void][System.Management.Automation.Language.Parser]::ParseFile('<文件>',[ref]$null,[ref]$e);if($e){$e;exit 1}"`（可写成 `.ps1` 后 `-File` 运行）
- 若有 `.mjs`：`node --check <文件>`
- `git status --short`（只出现允许路径）

## 需要真人的部分
- 无。合并与是否据结果开修复合同由用户决定。
