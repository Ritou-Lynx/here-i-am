# P6 R7 运行中取消与关闭等待修复

后续当前状态：[修复候选预检与清理诊断](P6_R7_PREFLIGHT_CLEANUP_20260913.md)。b966已实际只读确认四key缺席；修复候选的新零模型预检清理失败，App尚未打开。本篇其余结果及“尚未实跑”表述保留为此前冻结窗口的记录。

2026-09-13。用户明确回复“确认”，批准仅在隔离验收中改用 **“只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。”**。承接[上一轮启动诊断](P6_R7_APP_LIFECYCLE_PROGRESS_20260913.md)，不再把公开任务内容列为待决定。候选沿用精确基线 `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`；本轮主目录 `v3-lab@68307c9ea837f11dc82e148e8f51feff89b50fb6`，空索引、并行改动保留。

## 本轮结果

- 新数字任务只改隔离候选的 host、Dart config 与 ViewModel 三处固定值，逐字符相同；无工具、外部资料或真实队列。原短任务候选和历史证据保持。
- 首版 App 构建、83 项 Dart 与 15 项 host 专项通过。通过真实 App 按钮进入运行中并取消；同回合 `interrupted` 与原生完整回收成立，但 App 先超时并保持受阻，**App 取消体验验收未通过**。
- 定位为 Dart 将通用 25 秒控制截止用于完整关闭；本次严格回收约 43 秒，晚到响应不再写回。修复为独立有限 `closeTimeout=150s`，interrupt 仍为 25 秒，typed receipt、最终超时 unknown、lease CAS 保持。两文件已本地集成，87 项组合测试、相关分析及独立审查通过；修复后的实际 App 验收仍待。
- 第二个后台场景在启动阶段失败，捕获 `native_startup_timeout` 与 `task_helper_shell_execute_win32_1223`，无模型回合。原 native4 / cleanup pending 保留；没有运行中页面、后台或退出证据。当前四个规则 key 未实际查询，不宣称完整回收或无规则残留。
- 所有本轮 App 与原生进程均已退出；未确认关闭的 Node 经精确身份检查后定向停用。现役 47831/47841 的 PID、创建时间和监听归属不变。无本任务提交、推送、生产启用或手机安装。

## 首版候选和真实取消

工作树 `.worktrees/p6-r7-app-lifecycle`。固定[157项源文件和152项bundle](../../../tmp/p6-r7-review/app-lifecycle-running-01/candidate-build.json) SHA `fa7850e194806a2826d2b2d518e2851b5ce24f273cb18822d361952daf2e0bd8`。exe SHA `3ff792106a98d776bf51791a13f9b3b932b3d200737d63cec92469eed28385a6`；kernel SHA `e54e2a4e9556c17f8d5d1c0e41c8db53dc5fac894f5221e3da407d6194e30107`。

[18项 Node 闭包](../../../tmp/p6-r7-review/app-lifecycle-running-01/closure.json) SHA `cba2795bb62f2bb6e1dc112bc7dba96419df858a47c020865f58f494ce352b90`；[启动器清单](../../../tmp/p6-r7-review/app-lifecycle-running-01/launcher-build.json)固定 TTY、ready 前安全快照和独立身份观察。失败关闭不自动反复重试，无自动任务派发。原生仍为 v7 SHA `73cbe6277fd4bf5b92bdc3189e00eee5ce78f208d6037d8d16a14df9bde4bc4e`。

host launch `f09285d1-10aa-4d8c-a04d-b6553942c1c5`，Node49056，创建 `2026-09-13T01:16:09.9197171+08:00`，端口2106。owner0预检 `6cb5a9dd-4345-499f-bd57-89a636831c42` native0、六事实true，零模型。owner1实际取消的绑定如下：

| 绑定 | 实际值 |
|---|---|
| App PID / task | `35784` / `068203b3-72f5-4245-b989-655efe3375fa` |
| attempt / owner PID | `dfdd5a1e-6bb0-4cd5-913d-85fcd6ed88db` / `4544` |
| owner creation FILETIME | `134337074562107170` |
| local session | `1d48b0a0-c692-43a0-ae39-48d8af7a86ef` |
| execution epoch | `c58851b0-bd4b-416f-ae81-b9c97130affc` |
| provider thread | `01a096a6-ff64-7133-ac28-47bf193f126f` |
| local turn | `04542f16-5094-4c9c-a6db-4f1fb59c1b2b` |
| provider turn | `01a096a6-ffc1-7bd1-ab73-6d9e84a3230f` |

实际[App操作观察](../../../tmp/p6-r7-review/app-lifecycle-running-01/ui-actions-01.json)：01:25:33+08截图为运行中，01:25:42+08点击取消；[DB](../../../tmp/p6-r7-review/app-lifecycle-running-01/db-cancel-after-click-01.json)保留同 task 的取消请求。01:26:26+08，[安全事件](../../../tmp/p6-r7-review/app-lifecycle-running-01/events.jsonl) sequence14 给出同绑定回执：interrupt seq9，`interrupted` terminal seq11，取消确认true；native0，六项true/pendingfalse，broker drained。arm1/upstream1、response_released=false、rejected_requests1均原样记录；不推断 provider 运算量或声称 1–2000 输出完成。

原始 prepared/bound/final 与[独立身份观察](../../../tmp/p6-r7-review/app-lifecycle-running-01/native-identities.jsonl)相符，final SHA `f06a4a615b244a758302736261f22ad3f7ef21c687c27a4b0c264ae2f1b6056c`。App在此之前已写入 blocked/interrupted；再次点取消没有新增执行请求，不能把原生成功外推为 App 已显示取消成功。该 App随后由窗口关闭按钮自然 exit0。

首次外层 App 启动脚本使用 Hidden，产生一个无任务的隐藏实例；只读确认空任务库后定向停用，实际exit-1。改用可见交互窗口后才完成上述动作。电脑操作连接曾返回旧窗口缓存，重置并重新绑定当前窗口后继续。两者均不计入运行中 Gate。

## 第二个场景启动失败

App35052，task `664e3025-4a9b-479b-8d6d-f05909d921f3`；attempt `b96618b0-25d7-4812-bafe-3cd8dbfd36d3`，owner41336 / creation `134337078210469200`，broker37168，scope `62d11538-97e3-772f-f1d2-36c62cba5b40`。原始 prepared SHA `2a9b2a1a670694cb5913073ac095ef6a0114471bee08b2387ab3e3c47620fb3b`，final SHA `09a82a37e2424b36e3dc354cfa5dadfef9ac06a53cdf832053aee1e90e5cc089`。

prepared/final与observer绑定一致，started=false、child=null；无 install/cleanup 的 ready/ack/receipt，也无 spawning/bound/closed。`1223` 是 ShellExecuteExW 返回失败时捕获的原始错误，不能单独推断用户有意点击取消或 helper 从未执行任何代码；没有已接受安装证据，规则缺席仍须实际查询。

原native4，只报告Job/Handles=true，其余四项false、pendingtrue；host的verified六事实保持null。arm、parsed、admitted、upstream均0，broker drained，无session/turn/stop回执。[DB失败状态](../../../tmp/p6-r7-review/app-lifecycle-running-01/db-background-start-failed-01.json)与UI均未进入运行中。App自然exit0；host关闭返回未确认后，才按PID/创建时间/映像、原生及App均退出、broker排空定向停用。[停用记录](../../../tmp/p6-r7-review/app-lifecycle-running-01/host-retired-unconfirmed.json)不改写原始失败，也不声称进行了WFP查询或删除。

## 修复后候选已冻结，尚未实跑

修复后的 Windows Debug 已构建成功；每次构建前 critical 3/3 均通过。[新候选清单](../../../tmp/p6-r7-review/app-lifecycle-running-02/candidate-build.json)固定157项源文件、152项bundle，SHA `d46eba2db5b2ee88b0365e219c231e750e682446280da849d6a14febcc49c0f4`。exe SHA `09b8c3fb216f2c53bb4cc22c33e055b8890e9d49b2b395d6eb8c14d9e9baf567`，kernel SHA `0a0687ca2137dead9bb278e51c696f9e11c2ab75ceb30b9e63f4808f6754de43`。这些新指纹不继承首版 App 的实际取消结果。

[新启动材料](../../../tmp/p6-r7-review/app-lifecycle-running-02/launcher-build.json)已指向修复工作树；18项Node闭包SHA `e56ea781d0400f7b0349e438f76bb48ba0ceb2bdf384a8b366f68da3d6d5fe04`。可见App启动包装器SHA `b1f28e7aa7de05242a57aec7405424e7a83d1a85b870920003e9bf62d9dc0a38`，沿用UTF-8清单读取、启动前157/152校验及独立数据目录。未启动新host/native/App，未派发新任务。

b966的[固定只读检查计划](../../../tmp/p6-r7-review/app-lifecycle-running-01/b966-rule-inspect/PLAN.md)和[候选清单](../../../tmp/p6-r7-review/app-lifecycle-running-01/b966-rule-inspect/candidate-build.json)已准备。源码只改变旧模板中的目标绑定常量，2/2测试（2052项自测、104项托管断言）及编译通过；exe SHA `cfaf299798f1f1789be24634565db09fd0661dbb9836a7c6e62f1fb793f45c2c`。捕获包装器SHA `f3ca564e125e51f9e29808d43af9428ff102711fd890c21cb94471ac1742a017`，固定原始prepared/final与检查器指纹，只新增独立观察文件。只查询该实例三filter和一sublayer，不删除、恢复或改写原失败；尚未执行实际查询或触发新UAC。

## 修复与下一步

修复工作树 `.worktrees/p6-r7-close-receipt`。实现只增加独立关闭等待，未增加晚到写回回调；超过最终期限仍走原unknown/retained。测试使用真实typed client与内存HTTP适配器，覆盖延迟匹配回执、completed/wrong epoch拒绝、最终超时后晚旧回执不得覆盖新lease。主控87/87组合通过，独立审查无P1/P2。[两文件集成记录](../../../tmp/p6-r7-review/close-receipt-integration-01.json)保留主目录前后指纹；数字goal修改留在隔离候选，不更改主目录的旧固定测试内容。

后续先对 b966 的三filter及一sublayer做固定范围只读检查，再用修复后独立冻结候选重验取消UI、运行中导航/后台、退出回收及未完成任务重启。实际检查与新运行都需要用户手动完成Windows安全确认；本轮未自动操作安全窗口。生产仍 `available=false/fail_closed=true`；P6/Goal1/真人Gate未通过。普通生产客户端自身15秒receive截止未在本次候选修复中变更，将来生产接线须独立设计，不能继承本候选150秒路径的结果。

[收尾核对](../../../tmp/p6-r7-review/app-lifecycle-running-02/closeout-verification.json)逐项确认157源文件、152bundle、18闭包、两项主目录集成、三个goal及检查器七项输入一致，15个已有文档链接有效；新包装器目标与指纹一致。01:51+08的只读进程观察确认本次App/native/原Node身份和端口均不活跃，现役两服务原PID/创建时间及监听归属保持；未查询规则或操作进程。主线68307c9e、空索引，相关diff检查通过；只读检查和新候选实际运行均明确false。
