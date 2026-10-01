# W0 — Wave 3 × W5 G2 集成交接

> 日期：2026-08-23
>
> 状态：动态 Gate 与 Windows 联合真人验收已通过；已合入 `v3-lab@dd479858`

## 1. 唯一候选

- Wave 3 真人验收记录：`codex/whiteboard-wave3-acceptance@01213198`；产品代码截止 `b4ced67f`。
- Wave 3 安全输入：`codex/whiteboard-wave3-final-integration@ae3644b5`。
- W0 G2 候选：`codex/whiteboard-w0-g2@992578f3`，工作树 `D:/memex/.worktrees/whiteboard-w0-g2`。
- W5 联合 staging 最终 HEAD：`codex/w5-g2-staging@dd479858`。
- 日常开发主线：`v3-lab@dd479858`；最新手机模型连通状态 UI 已保留，并在合入审计中修复其提交时的中文编码损坏。

## 2. 汇合方法

W0 没有直接 merge 两条并行 Wave 3 分支。顺序为：

1. 从 `v3-lab` 建立隔离分支并先合 `ae3644b5` 安全线；
2. 按产品提交顺序逐个移植 XHS、本地媒体、Bilibili、图片卡、视频片段、Dock 与编辑器修复；
3. 每个冲突做方法级并集，文档同时保留产品证据和安全证据；
4. 全量静态分析发现并修复 `saveRichText` 测试替身缺少 `preserveEmptyTitle` 的真实契约错位；
5. 在 G2 候选上按 P1 基础/加固 → P2 基础/加固 → P3 基础/加固重建 W5 staging。

## 3. 必须保留的不变量

- Repository v2 intent snapshot、长度/hash/容量/envelope 校验、未知 journal fail-safe 与真实路径 containment。
- canonical URL/ID 等价类和 objectRef 使用同一并发协调域；事务内复查，后到同 hash 不改写首个真相。
- 视频只保留一个 provider-neutral timed-text resolver；Bilibili 时间能力必须经过读取、no-op seek、回读后动态提升，并在换 BV、离页、刷新、video 替换或迟到结果时撤销。
- 标注卡原子创建；time-range 只接受整数毫秒；草稿/焦点/未完成区间安全恢复；错误只显示固定文案。
- 卡面、本地媒体、XHS evidence 与图片导入继续走统一 Repository/Object 生命周期；渲染不触网。
- P1 普通对话与白板动作分流；P2 搜索授权不能由模型自授；P3 仍是契约，不冒充 HTML renderer 或 Artifact Core 已实现。

## 4. 已完成验证

- G2 95 个变更 Dart 文件 direct-dart analyze：零问题。
- 集成审计修复后的 3 个相关文件定向 analyze：零问题。
- 关键修复守门：3/3。
- `git diff --check`：通过。
- W5 P1/P2/P3 新增范围（不含 PersonaChat）：零问题。
- `PersonaChatScreen`：G2 基线与 W5 staging 均为同一组 19 条既有 lint，无新增类别。
- W5 staging 关键修复守门：3/3；diff check：通过。

## 5. Gate 状态

- Repository / 视频 / 画布 / 媒体 Flutter 组合测试已真实执行并达到 269/269 通过。最初无法启动不是另一开发窗口占锁，而是受限执行环境不能写 Flutter SDK 的 cache lock；改用允许写入该缓存的执行方式后恢复正常。
- 合并后发现的 3 个失败均为旧测试未跟上真人验收后的界面契约：现已改为验证原位编辑无边框、无填充、无聚焦光晕，以及 Bilibili 不读取或保存登录态，并完成整套复测。
- 已在 `codex/w5-g2-staging` 构建包含本 G2 候选与 P1→P2→P3 的唯一 Windows Debug 联合包；用户已在同版确认桌面入口、普通回复、selection 动作、原地 reload 与后续分组交互。
- 同版选区动作真人测试曾触发 `flutter_windows.dll` 无障碍父节点访问冲突；staging 增加动作前跨帧释放 IME 与画布原地重载后，同一命令真人复测已正常完成。后续分组返修已补整组拖动，并在二次真人反馈后统一标题命中与 screen-space 布局：拖动不再叠加框选，缩放不压卡，长名省略，折叠控件同中线；完整白板 188/188，四项均已通过 Windows 真人复测。
- 当前合入范围未把 stop、Bridge 重启和跨进程连续性宣称为已验收；这些仍是 P1 后续韧性门禁，不回退本轮已通过的普通对话和白板动作。

## 6. 下一步与合并判断

1. P4/P5/P6 与 G3/Artifact Core 统一从 `v3-lab@dd479858` 派发，不再从旧 Wave 3 或 W5 staging 分叉。
2. P1 后续补 stop、Bridge 重启和跨进程连续性的专门韧性验收。
3. P3 继续保持契约态；完成 Artifact Core 与 renderer 前，不宣称 P7/P8/P9 已生产可用。

当前结论：**G2 与 P1/P2/P3 已进入主线，可以按联合路线图推进下一波；P3 契约不等于 P7/P8/P9 已生产可用。**
