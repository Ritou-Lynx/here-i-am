# P6 R7 独立 App 候选：实现与部分实测

后续状态：2026-09-13已补启动前身份/错误观测，修正本轮外层输入接线并完成新组合零模型预检。原候选、失败及本页部分通过结论保留；当前待办见[启动诊断与生命周期进展](P6_R7_APP_LIFECYCLE_PROGRESS_20260913.md)。

2026-09-12。承接“继续下一步”，基线 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`。隔离工作树 `.worktrees/p6-r7-app-entry` / `codex/p6-r7-app-entry`，已将审阅后的 16 项文件集成到主目录，未提交或推送。此前 [HTTP/native 四场景](P6_R7_INFLIGHT_ACCEPTANCE_20260912.md) 的通过仅属于其各自冻结输入，不替代本页 App 证据。

## 当前结论

独立 Windows Flutter App 已实现、构建和实际运行。固定公开文字完成及**完成态任务在同一数据库重启后保留、未自动再执行**已验证；页面跳转和最小化只在完成后观察，不能证明运行中保持执行。取消场景未实际派发取消；运行中退出场景在启动阶段失败，尚未到达退出测试。

第三次任务的 native 退出码 4，原始清理状态仍为 pending。其余三个 owner（含无模型预检）均 native0、六项回收 true/pending false。本次 Node 测试服务已在精确身份核对后定向停用，端口关闭；随后针对同时间窗固定实例的独立只读检查实际 exit0，确认其四个规则标识当前全部缺席、owner/对应映像不活跃，没有删除操作。原失败、历史回收未确认和 Node 父子关联未知均保留。生产仍 `available=false/fail_closed=true`；P6、Goal1、生产及真人 Gate 未完成。

## 候选实现与边界

- 独立 `lib/p6_r7_candidate_main.dart`，只在 debug 和精确编译标记下接受候选参数。先核实 host、目录、准入文件及挑战响应，再打开测试数据库；不调用普通 main/router，不设置 AppDatabase 单例。
- 使用真实 `TaskRoomService`、`WorkbenchRuntimeTaskQueueTool.production`、执行控制器和根生命周期 owner。页面切换不销毁 owner；只有 `detached` 尝试关闭。显式动作由同一 inflight 栅栏串行化，固定 task_id 和候选会话作用域。
- 测试根目录仅接纳 `run-UUIDv4`，固定 `candidate.sqlite`，独占锁与双重身份记录。重启先以只读 SQLite 核对身份、schema 与唯一固定任务，再打开 Drift；不打开默认数据库。只有固定公开标题“公开文字验收”和目标 `Reply exactly: P6_R7_NATIVE_OK`。
- 独立 Node host 只监听随机 loopback 端口，排除 47831/47841，绑定冻结源闭包和 native 映像。真实无模型 start/close 预检成功后才发放准入；拒绝未授权路径、默认运行时、并发 owner 和不符合固定输入的续写。失败清理仍保留原 owner，不创建替代 owner。
- 准入挑战本身不证明进程身份；首个 App 启动前独立核对 host 的 PID、创建时间、映像和 listener。路径规范化是受信任本机启动者下的检查，不宣称可抵抗持有句柄之外的恶意 TOCTOU。
- 已生成部分文字的任务不能在该固定输入候选中继续；UI 在工具调用前拒绝，显式重试才清空旧结果。修复了独立审查发现的这项边界，并增加回归。

实现交接：[入口/UI](P6_R7_APP_CANDIDATE_ENTRY_HANDOFF.md)、[host](P6_R7_APP_CANDIDATE_HOST_HANDOFF.md)、[store](P6_R7_APP_CANDIDATE_STORE_TEST_HANDOFF.md)。[16项集成及原始文件指纹](../../../tmp/p6-r7-review/app-entry-integration-01.json)记录改动范围；未复制整个工作树，未覆盖既有 P6 和其他并行修改。

## 构建和本地验证

- Dart 专项及相邻回归 **81/81**，其中 store/UI 新增 **16** 项。最初相邻 task tool 测试使用旧基线夹具而失败两项；仅补入主目录当前夹具后通过，见[补充清单](../../../tmp/p6-r7-review/app-entry-seed-test-supplement-01.json)。
- Node candidate host/API **18/18**；这些使用假 native/provider 与真实本地 socket，不作为真实账户或 App Gate 证据。
- 候选及集成主目录相关路径静态分析均无问题；差异格式检查通过。每次 Flutter build 前运行三项 critical 检查并通过。
- 独立复核：16项集成文件与13项构建源输入在主目录/隔离目录均匹配，隔离候选153个bundle文件全部匹配。主目录另一个Debug bundle不是本次启动对象，不能用它代替隔离产物。
- Flutter 批处理入口本机失效；未修改 SDK。候选工作树用固定 Dart snapshot 启动 Flutter，并用工作树内的最小构建转接脚本替换对损坏批处理的调用。Windows 插件描述按候选包路径核对；本地 CMake 转接和生成的描述未集成到主目录。
- `sqlite3` 仅从开发依赖提升为运行依赖，锁定版本仍为 2.9.4；未升级版本。离线依赖步骤曾因 Pub active-roots 写入失败，构建通过另行记录，不把该次失败说成成功。

最终 debug 目标是 `lib/p6_r7_candidate_main.dart`，编译定义 `P6_R7_APP_CANDIDATE=local-fixed-public-v1` 和固定候选数据根。以下哈希均为 SHA-256：

| 输入/产物 | 哈希 |
| --- | --- |
| `memex.exe` | `4404D4CBEF8B444DF44DBA0288B9B964AA3A93D2B71734BA270ADAD269A457C9` |
| `kernel_blob.bin` | `420A4E9EE6C92FB586FFA99D5A17F39CE6F2A5E896A627DB09B86075FABF66D6` |
| [153文件构建清单](../../../tmp/p6-r7-review/app-entry-launch-01/candidate-build.json) | `83FBE538B7D477B820946EAD933DB1B216897E25D0ACB7D9BB82BC70C6B6EE12` |
| [host 源闭包清单](../../../tmp/p6-r7-review/app-entry-launch-01/closure.json) | `BAA0334BCEF26C4E9B04463D5796E7377C62C2FB58D20EFB3408C17CA903F2C1` |
| native v7 | `73CBE6277FD4BF5B92BDC3189E00EEE5CE78F208D6037D8D16A14DF9BDE4BC4E` |

准入包含本机能力密钥，不展示正文、不纳入文档。实际启动器固定 Node 映像、`--use-env-proxy`、上述闭包和既有专用认证；未读取或复制凭据，未改变账户或费用来源。

## 实际 App 观察

本轮 host launch_id `2c5e7e3d-b79f-4f31-86b9-905ea4fe318a`，原 PID59296、创建时间 `2026-09-12T22:38:08.8393117+08:00`，独立端口 44278。[追加式安全事件](../../../tmp/p6-r7-review/app-entry-launch-01/events.jsonl)保留完整顺序；各 owner 不能合并为一次运行。

| 场景 | 精确任务 / 实例 | 观察与判定 |
| --- | --- | --- |
| 无模型预检 | attempt `5aba2759-cdf6-495a-b85b-63f87ec10043` | 闭合无 turn 会话，upstream0、native0、六项回收 true。只证明预检。 |
| 固定文字完成 | task `a628c337-18cb-4842-b04e-7da2d809f818`；attempt `9dc81f8c-5801-4345-9094-b0cd427d3c82` | UI 与隔离 DB 均为 `P6_R7_NATIVE_OK`；匹配 provider turn `01a09611-f237-7ff2-aea6-da7609151970` 的 completed，native0、六项回收 true，upstream1。通过。 |
| 完成态重启 | 同上 task；App PID59164 退出后新 PID33684 | 同一 DB/候选准入/任务；重启后仍 completed，host owner 数仍 2，没有自动分派。仅完成态重启通过。 |
| 取消尝试 | task `1245af2f-4276-41f1-b8e9-1e20a942aeb4`；attempt `7033bb92-969c-4fed-9499-72563bbf97f6` | UI 曾显示运行中，但点击落下时任务已完成/布局已移动。DB 仅记录 start，没有 cancel；native 无 interrupt。实际是另一次正常完成，取消未验。 |
| 运行中退出尝试 | task `8c7ebed9-e616-4cf6-95b1-dc197fa8571e`；host owner3 | 启动阶段失败，无 ready/session/turn，upstream0，native4，cleanup_pending=true。UI“执行未能启动”，DB `runtime_start_failed`。没有到达运行中退出，不能判通过。 |

证据：[首次启动](../../../tmp/p6-r7-review/app-entry-launch-01/app-run-01.json)、[完成 UI](../../../tmp/p6-r7-review/app-entry-launch-01/ui-02-completed.json)、[完成后页面/最小化状态](../../../tmp/p6-r7-review/app-entry-launch-01/ui-03-navigation-restored.json)、[重启身份](../../../tmp/p6-r7-review/app-entry-launch-01/app-restart-01.json)、[重启 UI](../../../tmp/p6-r7-review/app-entry-launch-01/ui-04-restarted-completed.json)、[重启 DB](../../../tmp/p6-r7-review/app-entry-launch-01/db-observation-02-restart.json)、[取消前观察](../../../tmp/p6-r7-review/app-entry-launch-01/ui-05-observed-before-cancel.json)、[第三次失败 UI](../../../tmp/p6-r7-review/app-entry-launch-01/ui-06-start-failed.json)、[失败 DB](../../../tmp/p6-r7-review/app-entry-launch-01/db-observation-03-failed.json)。

重启后窗口曾不可见，UI 辅助树已经有 completed；通过窗口 Raise 恢复显示，不将此误判为 DB 挂起。运行中页面切换、后台、暂停/继续、取消、detached 和未完成任务重启仍需各自实测。

## 新启动失败与服务停用

host 对失败前未 ready 的 owner 没有记录 requested attempt_id、native owner PID 或具体 native failure code，不能凭时间窗补造完整父子链。[只读故障观察](../../../tmp/p6-r7-review/app-entry-launch-01/native-start-failure-observation.json)发现同时间窗唯一目录的 attempt 为 `d0d57b24-86bd-431f-890c-aedebad96cc9`，prepared/final 绑定一致，但与 Node owner3 的关联仍是**时间窗推断**。

该目录 prepared/final 没有 child，缺 install-ready、ack、receipt 等记录；final 的 Job/handles true，process/stdio/rules/helpers false，pending true。遵守冻结 v7 协议且元数据未被外部删除/替换时，缺 ready/ack 不能进入 Install；这仍不是实际 WFP 零残留证明，也不能据此确认 UAC 取消、助手退出或具体失败原因。没有运行恢复或删除操作。

host 的 graceful shutdown 因未知原生清理被拒，事件18为 `shutdown_unconfirmed`，HTTP listener 当时仍存在；这是 runtime 先关闭、listener 后关闭的顺序结果。此后独立核对四个 native owner 已有退出码、broker 全部 drained、候选 App/v7 映像均无进程，再比对 Node 的 PID、映像、创建时间和监听归属，只定向停止这个 Node。端口 44278 随后无 listener；原始失败和 pending 记录不改写，不生成正常 `closed.json`。

[停用记录](../../../tmp/p6-r7-review/app-entry-launch-01/host-retired-unconfirmed.json) SHA `32B4D8D030250F0B6DF9E608FA63D66314DA11C5A7BF3B5099714AE02FF0965D`。现役端口 47831/PID28396 与 47841/PID32704 的创建时间和监听归属在停用前后相同。该记录只证明定向服务停用，当时 WFP 状态未确认；后续规则缺席另由下节实际检查证明，不能回填进该停用记录。

### 后续精确只读检查：四个标识当前缺席

新建仅属于 `d0d57b24-86bd-431f-890c-aedebad96cc9` 的[检查计划](../../../tmp/p6-r7-review/app-entry-launch-01/APP_NATIVE_RULES_INSPECT_PLAN.md)，没有复用旧实例的实际入口。冻结 prepared/final/owner映像/CLI映像及 scope，持有规范路径和文件句柄，前后核对同用户目录ACL、owner创建时间及对应映像无活跃进程；只读事务查询三个 filter key 和一个 sublayer key。出现标识只记 present/unclassified，未知或关闭失败不能记缺席；没有 add/delete/commit/恢复入口。

主控和 worker 各 **2/2** 本地通过（2052纯断言、103托管断言），独立审阅无阻断。主控发现的5项目录清单与旧数量检查不一致已在运行前修复，并以真实5项临时目录及文件类型/reparse反例覆盖。prepared/final 哈希从原文件独立逐项比对，未输出私密字段。

[冻结构建](../../../tmp/p6-r7-review/app-entry-launch-01/app-native-rules-inspector-build.json) SHA `80A83177B5379F54C3C3D538A4BFCE75D9E83550AE684ECD11E706AFAE4FDD00`；检查器 exe SHA `144533C16FF7DA5226B8C8DDB959367BE4712D0A9FE6A571A4910EF972357DC9`。捕获脚本从预哈希至记录期间持有该文件只读句柄、禁止写/删除，前后匹配调用方哈希；该承诺限于受信任本机启动者模型，不是 Node 父子可信证明。

Windows 权限确认后，实际检查器 **exit0**：[结果](../../../tmp/p6-r7-review/app-entry-launch-01/app-native-rules-actual-01.json) SHA `BC139130F00B819D474B1661FC384B2687939A1132C858B1B0A937748C142C2B`，[实际退出采集](../../../tmp/p6-r7-review/app-entry-launch-01/app-native-rules-actual-01-capture.json) SHA `5F7A3EEBDF3F99696A146B6D6908F4E912D03422A7EB389E1E2A08301D8350C5`。三项filter查询完成且存在数0、sublayer不存在，前后owner/映像不活跃、文件/ACL核对、事务结束和资源关闭均true。0模型请求、0规则删除，无需对这四个标识执行删除。

这只证明该固定实例的四个标识在检查时缺席；不是全系统规则清单为空，也未检查未知原会话的Job。原native4、historical cleanup_pending、停止凭据未通过、Node父子关联未知仍保留，不把当前只读观察升级为原始任务成功。

## 下一步

本次新失败实例的精确只读规则检查已完成，没有发现该四个标识的遗留；不执行无目标删除，也不重跑已完成的旧恢复器。启动失败的具体阶段仍未确定，候选 host 还需补 ready 之前 requested attempt/owner身份的安全观测，以便下次失败不依赖时间窗关联。

下一阶段冻结新的启动输入，补运行中页面/后台、真实取消派发和匹配终态、退出回收及未完成任务重启；如果源码或产物变更，重新记录哈希和相应验证，不继承本轮通过。Windows 安全权限提示由用户手动处理；不使用电脑工具代点审批。
