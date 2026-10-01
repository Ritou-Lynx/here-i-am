# Goal 1 最终集成缺口审计（2026-09-30）

> 2026-10-01 更新：本页记录的是接线前缺口与当时停止条件。后续组合接线、隔离普通入口真人 Gate 和最终受影响范围审计已经完成；当前判定见 [Goal 1 最终本地验收](GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md)。生产长任务执行仍默认关闭。

本次只审当前源码与既有隔离证据，没有启动现役 App/Bridge、历史队列或手机。工作区为 `v3-lab@b2adc44b7c04983a931c39695b81491cd295084b`，已有 76 个 tracked 改动；这些并行改动未清理或合并。P6 run11/13/14 使用同一 App SHA-256 `7b3241213fbcb3bf8ad089c935349682cec948422a4d4155ad2bfa1ac7791f92`，隔离入口生命周期与运行中异常恢复的实际结果见 [run14](P6_R7_RUN14_20260930.md)。UI-T、P4 和限定 P5 的已接受真人 Gate 仍按 [Goal 1](../goals/GOAL-20260824-ai-workbench-wave1.md) 保留，不把不同候选产物误写成同哈希验收。

## 当前接线事实

- P6 验收 App 由 `lib/p6_r7_product_main.dart` 独立 Debug 入口构建。源码明确声明普通应用不 import 此文件；该入口使用固定公开任务、独立数据目录、owned host 与 Witness。run14 证明的是这条受控入口的实际生命周期，不是普通安装入口已可执行队列。
- 普通桌面会话的 `WorkbenchConversationCoordinator.production` 已挂 `WorkbenchRuntimeTaskQueueTool.production()`，但其执行需要 `WorkbenchTextTaskRuntimeClient` 的 `workbench_text_only_v1` profile。Bridge 的 `workbench_text_only_profile.mjs` 当前固定 `available:false`、`fail_closed:true`，拒绝这类会话；没有生产执行/停止回执。当前源码测试 27/27 再次确认拒绝与候选适配器的边界，不能将这组测试替代真实普通入口 Gate。
- 验收入口仍含固定公开目标、一次任务绑定、专用启动/Witness 参数。按 [产品接线计划](P6_R7_PRODUCT_WIRING_PLAN_20260914.md)，这些是验收设施；产品 API 不得把固定数据集、模型可控失败开关或 native permit 暴露出去。首次产品候选可以明示一次并发与一次恢复的限额，但需要正常入口与实际所有权、关闭回执。

## 收口顺序与停止条件

1. **产品执行接线**：在隔离写入中把已验证的受限 host/stop/close 能力接到普通桌面入口，使用普通授权字段和目标文本；保留默认拒绝直到新候选验证。先证明授权前零分派、未知状态停止、后台工具不可用、退出/异常退出清理完整。不得直接把 Debug 开关当作生产开关。
2. **唯一组合候选**：核对 UI-T/P4/P5/P6 的源码来源、现有脏改动与受影响路径，定向回归并按构建前关键检查生成唯一 Windows Debug 产物，记录源和可执行文件哈希。旧 UI-T/P4/P5 已接受范围不机械重开；普通聊天/数据装配若受新接线影响，补针对性回归。
3. **同候选真实 Gate**：用新隔离数据在普通入口验短聊零任务、明确入队/查询、合法状态控制、正向唯一输出、失败/正常重启/运行中异常退出后的诚实恢复，以及原 owner 真实退出和完整清理；对受影响的 UI-T/P4/P5 路径做必要真人复核。任何失败按实际结果返修，不能继承 run14 的不同产物结论。
4. **项目收口**：由主验收窗审计 Gate，更新 Goal、项目状态、Roadmap、DEVLOG 和 i 交接。生产默认启用、commit/push/发布均与本地验收分开处理，按届时已有授权和明确决定执行。

本次在 run11 冻结源码定向运行六个 UI-T/P4/P5 组合测试，**69/69 通过**；覆盖主题、白板人工命令端口、Runtime DomainCommand、持久 Receipt/Undo、关系上下文与 Dreaming strict mode。首次用普通权限调用 `flutter.bat` 卡在启动且无 Dart 子进程，停止后定位为 SDK `D:\flutter\bin\cache\lockfile` 工作区外写入受限；按批准权限直接调用 SDK 快照，实际测试退出 0。当前 Bridge 的 profile/候选适配器专项 **27/27 通过**。这些是同一源码的自动回归，不能把 Debug 隔离入口变成普通入口真人 Gate。当前仍不满足 Goal 1 完成条件，也不能宣布生产队列可用。
