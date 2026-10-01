# W0 AI Workbench 首批集成交接

> 状态：首批集成已通过自动、真实 Runtime 与 Windows 真人 Gate，并已本地合入 `v3-lab`；不 push
> 日期：2026-08-24
> 分支：`codex/whiteboard-w0-ai-integration`
> 已同步基线：`v3-lab@318567b6`

## 集成范围与顺序

1. W4 字幕：`2468d90c` → `bc233513`
2. Artifact Executor：`9780f49f` → `7fe1d80d`
3. P1/P2：`69ab4301` → `401220e5`

原 P1 `516d319e` 已由联合候选替代，未重复应用。后续合入当日 `v3-lab@318567b6` 的 Android FGS 修复；仅 `DEVLOG.md` 与 `I_PROJECT_STATE.md` 冲突，W0 人工保留两边有效记录，代码零冲突。冷启动 prewarm 实验因真人体感更慢已显式 revert，不留在最终代码。

## 自动验证

- 最终组合回归 172/172；Bridge Node 回归 20/20；Bilibili/SRT/VTT 字幕专项 115/115。
- 本轮最后返修增加真实鼠标拖选 + `Ctrl+C` + 剪贴板内容测试；桌面聊天 8/8，白板 coordinator 命令路由/冲突撤销重试 2/2通过。
- 定向 analyze：集成相对 `v3-lab` 的 25 个 Dart 文件零问题；最后 4 个返修文件复验零问题。
- `scripts/verify_critical_fixes.ps1`：3/3 通过。
- `git diff --check`、冲突标记检查与最终工作树清洁检查通过。
- `flutter build windows --debug`：最终重建成功（153.3s），新产物在 Default desktop 可见且响应正常。

## Windows 启动 Gate 诊断

- 候选与 `v3-lab` 的 Windows runner、CMake、manifest、plugin registrant、`pubspec`、`main.dart` 与 Flutter metadata 一致，集成 diff 没有桌面启动改动。
- 首次从 Codex sandbox 读取 `MainWindowHandle` 与 `EnumWindows` 得到 0 / 空集合，是 observer desktop 隔离造成的假阴性：observer 位于 `CodexSandboxDesktop-*`，应用窗口位于同一 Session 1 的 `WinSta0\\Default`。
- 对同一候选 PID 从两个 desktop 连续采样：sandbox observer 报告 HWND 0；Default desktop observer 得到可见、响应正常的 `memex` 顶层 HWND。`v3-lab` 基线表现相同。
- 候选直接启动时约 1.5 秒出现可见 HWND；从仓库根目录启动结果相同，排除工作目录与 bundle 路径。`flutter run --use-application-binary=<absolute path>` 也已在 Default desktop 取得可见 HWND。
- AXTree / Flutter semantics 断言发生在 `q` 触发退出、widget tree 拆卸期间，基线与候选均可出现；它不是启动窗口缺失的证据。本轮不修改 runner、Flutter SDK 或语义树。

后续 Windows 真人 Gate 必须从 `Default` desktop 观察可见窗口，不能用 sandbox desktop 的 `MainWindowHandle` / `EnumWindows` 作为否定证据；进程停止仍只按本次启动的精确路径与 PID 执行。

## 普通对话、Runtime 与桌面复制 Gate

- 用户已在 Windows 候选中发送普通消息并收到正常回复，普通 Codex 对话主路径通过。
- 第一版只在整个 reverse `ListView` 外放 `SelectionArea`，静态测试虽通过，真人仍可被列表手势抢占。最终改为逐条消息/流式消息/行动卡独立 `SelectionArea`，并以真实拖选 + `Ctrl+C` 剪贴板断言守门；真人确认通过。
- 回复慢的审计确认当前链路不是终态整包显示：`agentMessage/delta` 经 Bridge `message_delta` 立即进入 Flutter streaming bubble，完整回复只在终态后落库；空事件轮询为 120ms，暖 Bridge health 约为毫秒级，普通回复不预先执行搜索。
- 当前最可能的秒级变量是首次 App Server / provider session 懒启动、Codex provider 首字时间，以及真实 provider 是否只在接近终态时发出大 delta。本轮没有通过缩短总 deadline、跳过持久化或安全检查做表面提速。
- Runtime 真实 Gate：普通回复 `W0_ORDINARY_OK`；active tool-call turn 中断后终态 `interrupted`；App Server stop 后以同一 provider thread 恢复并返回 `W0_RESUME_OK`。
- 搜索真实 Gate：Card adapter 命中 trace `candidate=1/returned=1`，空结果 trace `0/0`；注入 `authorization.project_memory.all_containers=true` 被 `invalid_search_request` 拒绝。

## 白板真人 Gate 与 Undo 边界

- 真人确认新旧卡片选区都能被受限工具读取，分组连线成功，无中间改动时整批撤销成功。
- 真人首次使用“整理当前选中卡片并连线”被误分流到普通对话；matcher 现覆盖“选中/所选 + 整理/分组 + 连线”，不再要求背固定口令。普通对话的任意白板上下文仍等待 P4/ContextEnvelope，未伪装完成。
- AI 撤销在检测到后续白板改动时仍 fail-closed，但冲突/暂时不可用不再销毁撤销 token；用户恢复后续改动后可重试。
- 已知限制：画布 `Ctrl+Z` 栈仍是 ViewModel 内存状态，退出画布并保存后无法跨 route 恢复移动；列入 P4 DomainCommand / Receipt / Undo 持久化，不宣称已完成。

## W4 平台 Gate

- 项目真实 resolver + 安全 transport 实测 18 个公开 BV：匿名正样本 0/18；17 `noTrack`，1 `accessRestricted` (62012)。
- 原始 API 正常返回 `code=0` 但 `subtitles=[]`；登录后 AI 字幕样本在匿名状态也为空。Cookie 不读取，签名 URL 不落盘，SRT/VTT 后路正常。
- 因此 W4 严格正向 Gate 未通过；它仅阻塞依赖匿名 Bilibili 自动字幕的工作，不阻塞 P4/P5/P6。

## 后续边界

Artifact Executor 仍是 provider-neutral core，没有生产 repository adapter、后台恢复扫描、图片/HTML provider、Canvas renderer 或 UI。Runtime binding 默认仍为 `processMemory`，不宣称跨应用持久化。

P4/P5/P6 可从当前本地 `v3-lab` 基线隔离并行开发。本交接不 push；W4 字幕、Artifact 生产 adapter、跨应用 Runtime binding 和跨 route Undo 仍按各自 Gate 诚实保留。
