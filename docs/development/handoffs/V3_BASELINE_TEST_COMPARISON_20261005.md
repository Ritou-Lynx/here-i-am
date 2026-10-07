# v3-lab 与 W0 测试对照（2026-10-05）

## 基线与执行范围

- v3-lab：`f605d5017cbc0a8eb69983e00c25cd1bba08a0eb`。从正式净化仓库定向获取并核对远端后，在独立 `codex/v3-baseline-test-20261005` 工作树测试；既有本地 v3-lab 工作树仍为 bbdf41b6，未切换、pull 或合入。
- W0：`842a3e9ae5b4891f6904f8e88c1db3a880ec204f`，源码整合候选为 9b23d511，后续只有文档变化。使用此前已执行的 W0 日志，不重新改代码或断言。
- 两次本机递归执行均使用 Windows、Node v24.14.1、相同测试文件发现规则与 node --test；基线执行时间为 08:05:35–08:07:00 UTC，退出码 1。
- v3-lab 只有 tools/i_core，尚无 tools/i_memory、tools/i_remote_mcp；因此基线有 16 个测试文件，W0 有 23 个。没有把候选代码复制进基线来补目录。两边总数不同，失败按完整测试名逐项比较。

## 本机结果

| 执行 | tests | pass | fail | skip |
|---|---:|---:|---:|---:|
| v3-lab 首跑 | 260 | 216 | 43 | 1 |
| v3-lab 完整顺序复跑 | 260 | 217 | 42 | 1 |
| W0 递归套件 | 368 | 325 | 42 | 1 |
| v3-lab 额外快照用例隔离复跑 | 1 | 1 | 0 | 0 |

完整顺序复跑使用 --test-concurrency=1，08:23:29–08:26:50 UTC，退出码1；没有改变源码、依赖或断言。主窗再次逐项比较，顺序复跑的42个失败名与W0完全相同，双方独有失败均为0。

主窗独立解析首跑两种报告格式，比较全部失败名字：W0 的 42 个失败条目全部包含于基线 43 个，W0 独有失败数为 0；基线独有失败数为 1。Node 的失败统计包含一个因子测试失败而失败的父测试；42 不能称为 42 个末级叶子用例。

共有失败包括 M3 15 个、runtime_pin 6 个、runtime_upgrade/r3 20 个末级条目及 1 个失败父测试。错误签名为冻结 bbb8025d 提交没有 tools/i_core 源码，以及 Get-Acl 无法自动加载 Microsoft.PowerShell.Security（CouldNotAutoloadMatchingModule）。这些测试、fixtures 和运行包脚本两边无差异；Core 共有 67 个文件中 63 个字节相同，变化仅 README、i_core_server.mjs、i_core_store.mjs、i_core_server.test.mjs。

基线额外失败是 activity_control_plane.test.mjs 的 `direct recovery verification uses an isolated committed view for every accepted and rejected outcome`。断言在 real-WAL:unsupported-1 场景要求全局临时目录中没有新 activity-preflight 目录，却观察到另一个目录；该源码和测试相对 W0 没有变化。隔离复跑1/1通过；完整套件顺序复跑时此项也通过，原观测目录随后已不存在。结果支持并发目录观测干扰的推断，根因尚未专项确认。首跑43与顺序复跑42分别保留，不改报首跑或全绿。

原始测试日志留本机临时目录，未进入 Git 或 PR；合成测试自身生成的 M3 evidence 仅在隔离测试工作树。未部署或处理真实数据库。

## 完整 GitHub CI

基线也独立触发了相同 ci.yml，event=workflow_dispatch，ref=v3-lab，head=f605d501；[运行 37282048605](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37282048605)。基线与 W0 的 CI 配置、App 源码及 Flutter 测试相同。已完成，conclusion=success，四组全部通过：Flutter 全量2568过/20跳、白板/工作台专项、Bridge Node、Windows关键检查与构建、集成4/4和文件锁单测31/31。三个报告/截图产物元数据的head_sha均为f605d501。

W0 的[运行 37278961244](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37278961244)四组已通过。现有 CI 没有直接覆盖上述 Core/MCP 递归套件，两类证据分别记录。

## 用户最新决定与下一步

1. W0 收尾：42 项[逐项既有失败清单](W0_BASELINE_FAILURES_20261005.md)附入 PR；运行五源码按[更新交接](W0_RUNTIME_UPDATE_20261005.md)处理。用户明确将旧失败的修复移入独立任务，要求 W0 完成新增补丁验证后转 ready 并请求合入，不将原规划全过条件解释成已经满足。
2. 已新开独立 i_core 修复窗口，thread `01a10b3e-cb9f-7ed0-9476-a81cc05ffdd5`，基线 f605d501。逐项判断代码/测试/fixture 或环境根因，不新增跳过或屏蔽，不借此启动 W1。
3. W1 暂不派发，等数据中心方向明确；即使 W0 合入也不自动释放。WI/WL 已开的独立工作照常，W6 仍仅为决定草案。

原总规划中 W1 确认接口后再释放 W3/W4/W5、完成后释放 W2 等依赖保留为未来顺序；当前执行以用户本次决定为准。
