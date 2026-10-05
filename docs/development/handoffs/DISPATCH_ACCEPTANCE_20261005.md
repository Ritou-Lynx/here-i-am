# 分派窗口主窗验收（2026-10-05）

> 历史分派/单包验收记录。后续更新：42修复已由PR #7普通合入；W1最终组合507过/0红/1既有跳、格式后领域专项111/111及最终13源码副本链通过，见[当前组合验收](W1_COMBINED_MAIN_ACCEPTANCE_20261005.md)。下方“尚未提交/未组合”仅指当时证据窗口。


## 结论

所有已交付窗口已做本轮主窗复核；验收层级如下。窗口完成、源码候选验收、合入和线上 Gate 分开记录，当前候选均未因此自动提交/推送/合入或部署。

| 包 | 主窗本轮证据 | 已验收范围 | 待完成 |
|---|---|---|---|
| i_core 42 项旧失败 | 原修复副本16文件独立260过/0红/1既有跳；当前v3-lab@6508移植同套262过/0红/1既有跳，W0两项frontend负例保留；原默认/串行日志与16源码SHA核对 | 原42条（41叶子+1父汇总）逐项修复，无新增skip/屏蔽，源码候选通过 | 42候选提交/集成；W1新模块静态依赖加入合成pin夹具后组合复验；不声称缺失旧binary已运行 |
| W6 | 四域字段/authority/来源/删除映射对照源码，36本地链接/25源码锚有效；active→待办和手机白名单文案修正 | 文档映射候选及原已授权有界聚合报告 | 正式业务schema/迁移/持续手机companion上传、活跃i_remember消费、加载/网络/物理设备Gate |
| MCP 对齐 | 17源码备份和23候选文件hash/manifest/inventory验证；主窗独立125/125；worker报告9/9固定Core适配和2/2frontend作为补充，主窗未重跑这两组 | 源码差异保全、精确W0候选和可复核切换方案；EOL比对/精确blob的文案已修正 | effective env/policy/数据路径实际核实、单独MCP切换授权、停启/状态一致备份/切换与线上验收；固定Core transcript/replay功能单独保全 |
| WI | local_plan.mjs SHA BAD24067C0A256352450BC83A1FB21EBD778BB2E5FB1CF59E9727AB4872F57F4 与既有候选一致，主窗独立12/12；核既有本机空初始化交接 | 过渡期本机规划工具与模板源码 | 提交/整合；真实条目、dot/自动监视器/实际排期尚未验收 |
| WL | 主窗复核四处Markdown diff及占位链接：先学→背→测、配额、旧unknown/不会与未学约束 | 指令模板候选 | 提交/整合；思源真实写入、实际教学/录音及学习效果尚未验收 |
| W1/R01 | 既有新增111/111及相邻344过/0红/1既有跳；用户追加授权后的[真实4→5→6一致副本演练](W1_R01_REAL_COPY_VALIDATION_20261005.md)通过 | 本次13源码候选和授权派生副本范围 | 42修复后组合验证、提交/集成；已有真实activity历史/现役功能/客户端/线上升级另验 |

## 关键限定

W6 74卡/92账本的差额18不等于重复/漏记数；10条登记Android来源companion不等于持续自动上传；i_remember活动0、删除on_phone1不证明当前活跃消费。保留原观察范围，本轮没有重读这些真实内容或扩大聚合范围。

MCP候选尚未切到线上。实际固定Core v4包含仓库缺少的transcript/replay功能；本轮R01保全的是DB行/元数据，外置授权和代码功能没有被演练替代。schema5授权及追加副本链授权不等于MCP停启、运行库升级或发布授权。

42修复采用公开synthetic schema4，不再要求已丢失的历史Git对象；生产固定源码guard仍在。W1与42各自有限候选通过，尚未组合；后续先保留42修复，再为W1测试夹具补domain_http/domain_store/domain_schema库存，不能整体覆盖W0现有测试或更改生产pin来源。

## 输入与复核后的文档

工作副本位置仅用于定位源码候选，不能当运行目录；完整路径以本机任务工区为准：

- 42修复验收：core42-acceptance-20261005/docs/development/handoffs/I_CORE_TEST_DEBT_MAIN_ACCEPTANCE_20261005.md。
- W6：w6-mapping-audit-20261005/docs/development/handoffs/W6_MAPPING_AUDIT_20261005.md；task map更新SHA d900f0c941166e1a48390102842aa3af7bfa6fe56bbb020eddeebccd1d73a0bb。
- MCP：mcp-align-20261005/docs/development/handoffs/MCP_RUNTIME_ALIGNMENT_20261005.md；更新SHA 2fb6ccdd7121fe79e28360b29e569072552fbf7f5f6558bd4d7a766be2e645c4。
- WI：wi-local-planner-20261005/docs/development/handoffs/WI_LOCAL_PLANNER_20261005.md。
- WL：wl-study-instructions-20261005/docs/development/handoffs/WL_STUDY_INSTRUCTIONS_20261005.md。

## 下一步顺序

1. 先将通过主窗复测的42修复候选按提交/合入授权集成v3-lab，建立清楚基线。
2. W1在此基线上组合：补合成pin依赖库存，复验完整递归i_core/相邻MCP权限边界及变更后的副本候选，形成可审查PR。当前R01报告不继承给变更后的源码哈希。
3. W1源码集成后W2实现captures、plan_items、plan_weeks、plan_days。已定稿接口允许W7-0通用outbox/本地副本和W4/W5假实现并行；W3先完成MCP源码对齐的实际切换前检查，再用fake Core开发，W2完成后接真服务。
4. W7-收支/经期/睡眠正式迁移需W1和W6完成；W8依赖W2/W3。真实库升级、MCP切换、手机安装分别按具体发布方案和授权执行。
