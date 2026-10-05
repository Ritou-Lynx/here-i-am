# W0 整合与收尾交接（2026-10-05）

## 输入、整合与源码补齐

- 起点为远端 v3-lab `f605d5017cbc0a8eb69983e00c25cd1bba08a0eb`；本地主工作树未切换或合入。
- 按序普通合并 wonderful-carson `4a33f95d71c61d2d7c1de80984047ca2c80a8eef` → b3-writeback `445d665ee58e682e1dc41a96d90fb05d656bc10a` → festive-ride `053000db48bfd19700a2ab583842d50d7744c151`。merge 为 ed7b1fa3、24c78812、9b23d511；原完整源码候选为 `9b23d511fc28d588c3d1fe2c73014901e4824070`。
- 最初冲突仅 DEVLOG / I_PROJECT_STATE，保留各线记录。原已上传候选为 `842a3e9ae5b4891f6904f8e88c1db3a880ec204f`，后续本轮选择性补齐运行源码差异，不再把当前分支描述为仅文档变化。
- 三处运行改动已归属正式 C 谱系并保存：2004d3b8 的 MCP phase/安全去重，6ab0278a + 05112dde 的显式 Android 出站读取。三文件精确等于 3a9336b1 对应 blob。两处旧 Core 源码未反向覆盖，保留 W0 前端权限保护。详见[差异与合入后更新步骤](W0_RUNTIME_UPDATE_20261005.md)、[五源码哈希](W0_RUNTIME_SOURCE_HASHES_20261005.json)。
- 只带入对应合成测试及协议说明，未引入额外 Core transcript/replay 特性、W1 schema、真实 policy、凭据或数据库。WI/WL/W6 独立 diff 不在本 PR。

## 测试与既有失败边界

| 候选/执行 | tests | pass | fail | skip |
|---|---:|---:|---:|---:|
| 原 W0 顶层 16 文件 | 317 | 316 | 0 | 1 |
| 原 W0 递归 23 文件 | 368 | 325 | 42 | 1 |
| v3-lab 首次默认并发 | 260 | 216 | 43 | 1 |
| v3-lab 完整串行复跑 | 260 | 217 | 42 | 1 |
| 本轮补齐后顶层 18 文件 | 345 | 344 | 0 | 1 |
| 本轮补齐后递归 25 文件 | 396 | 353 | 42 | 1 |

Node v24.14.1 / Windows；本轮递归使用 --test-concurrency=1，不改断言、测试选择或跳过条件。当前专项覆盖相似事实修正、重复短句完整轮次、精确尾部重试、不可变 pending 重送、v1 账本升级、设备序号/平台/私密边界及 OAuth MCP 组合。

42 条既有失败在 v3-lab 串行基线和原 W0 中的完整名称集合双向一致；本轮补丁复测也与基线的 42 条失败名称逐项一致，新增失败为 0。不是本次合并引入，且不是新增源码补丁造成。完整清单：[42 项说明](W0_BASELINE_FAILURES_20261005.md)、[机器可读 JSON](W0_BASELINE_FAILURES_20261005.json)。其中 41 条终端失败与 1 条失败父测试汇总，不能称作 42 个独立叶测试。诊断线索为脱敏历史缺失旧冻结 Core fixture，以及 Windows PowerShell Security 模块加载失败；修复窗口逐项核验，不能统一归为过时测试。

基线首跑多出的快照目录观察断言，在单条和完整串行中均通过；不改报首跑 43 统计。原有 1 skip 来自 Windows 文件系统不能表示大小写不同的两个目录条目，未新增 skip。原始合成日志留本机，不进入 Git/PR。详见[基线对照](V3_BASELINE_TEST_COMPARISON_20261005.md)。

## GitHub CI 证据

- 原 W0 `842a3e9a`：[37278961244](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37278961244) 四组全部通过。
- 独立 v3-lab `f605d501`：[37282048605](https://github.com/Ritou-Lynx/here-i-am/actions/runs/37282048605) 四组全部通过。
- 两次既有 CI 都记录 Flutter 全量 2568 过/20 跳，白板/工作台与 Bridge 通过，Windows 关键检查、Debug 构建、集成 4/4 和文件锁 31/31。它们不冒充本轮新源码候选的验证。
- 本轮补丁候选上传后重新跑相同 CI；最终 head SHA、运行链接及每组结果在[PR #5](https://github.com/Ritou-Lynx/here-i-am/pull/5)的描述与 Checks 回执登记。现有 CI 不直接运行 Core/memory/MCP 目录，因此上述本机测试证据独立保留。
- 仓库 shadow 规则因改动规模标 HIGH RISK，仅供审阅，不是忽略验收的授权。本轮不本机构建或安装 App。

## 用户最新决定与执行状态

- 用户要求 W0 写清旧失败清单、保存运行差异、完成验证后把 PR 改 ready，并再请求合入。用户将 42 项旧失败移到独立修复窗口，允许 W0 按上述旧失败边界收尾；这不表示原规划全绿条件已满足，也不表示旧失败已修好。
- 独立修复任务 thread `01a10b3e-cb9f-7ed0-9476-a81cc05ffdd5` / host local，分支 `codex/i-core-test-debt-20261005`，精确基线 f605d501；逐项判断代码/测试/fixture 或环境问题，不跳过、不屏蔽，不碰 W0 与生产服务。
- W1 暂不派发，待数据中心方向明确后由用户释放；W0 合入不自动开始 W1。WI/WL 现有独立工作继续，W6 保留决定草案。
- 合入 v3-lab 尚需用户最终确认；运行副本实际更新、停止/重启服务、真实数据操作和手机安装未执行。五处源码差异的处理已完成，进程实际加载版本和部署/真人验收仍以之后独立回执为准。

[首批派发表](PERSONAL_DATA_HUB_DISPATCH_20261005.md)保留工作包归属与后续依赖。
