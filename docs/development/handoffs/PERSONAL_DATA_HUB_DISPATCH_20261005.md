# 个人数据中枢首批派发表（2026-10-05）

输入：[总规划](../PERSONAL_DATA_HUB_PLAN_20261005.md)，来源 `claude/festive-ride-88vh1t@053000db48bfd19700a2ab583842d50d7744c151`。W0 起点为远端 `v3-lab@f605d501`，依次普通合并 wonderful-carson、b3-writeback、festive-ride；完整候选 `9b23d511fc28d588c3d1fe2c73014901e4824070`。WI/WL/W6 因独立，可先基于此候选交付；正式下游仍等 W0 合入。

| 工作包 | 执行者 | 分支 | 拥有路径 | 状态与下一步 |
|---|---|---|---|---|
| W0 | 主 Agent i | codex/w0-integrate | 整合冲突、全局交接、派发表 | 三条分支已整合；完整递归测试 325 过、42 红、1 跳；当前接口专项 316 过、1 跳、0 红；用户已授权上传及草稿 PR，CI 待运行 |
| WI | /root/wi_local_planner；Astra/high | codex/wi-local-planner | tools/life_planner/；handoffs/WI_LOCAL_PLANNER_20261005.md | 已交付并复核；12/12 合成测试；主窗首次本机空初始化通过，今日单待补充；真实排程待事项/容量 |
| WL | /root/wl_study_instructions；Luna/low | codex/wl-study-instructions | tools/siyuan_tutor/；handoffs/WL_STUDY_INSTRUCTIONS_20261005.md | 已交付并复核；学习块/结果接口、未学准入与只学习不测规则已闭合 |
| W6 | /root/w6_authority_draft；Astra/high | codex/w6-authority-draft | data-authority-preflight/W6_*_20261005.md | 草案已交付并复核链接/源码；17 项待用户确认，未启动迁移 |

所有工作目录在正式 C 盘源码区，独立 worktree。worker 不提交、不推送、不派生，只写自身 handoff；主窗复核并统一更新状态。三个独立包不进入 W0 整合 PR。D 盘私人旧谱系和本地 v3-lab 未改动。

## 依赖释放

- W0 合入 v3-lab 后派发 W1；W1 先只交 I_CORE_DOMAIN_CONTRACT.md，用户确认后才实现。
- W1 约定确认后 W3/W4/W5 同时接假服务；W1 实现后释放 W2。
- W2/W3 完成后释放 W8，W3/W4/W5 再接真服务。
- W1 完成且 W6 决定确认后，W7 按领域分别开工。
- 合入 v3-lab、生产 Core 停止/升级、真实数据迁移、主力手机安装仍按总规划分别确认。

## W0 限制

- 完整递归测试红灯涉及现有历史迁移/固定运行包：冻结基线 bbb8025d 的 Core 源码在净化谱系不可读取，Windows PowerShell Security 模块自动加载失败。上述目录相对 v3-lab 未改动。当前 API/MCP 测试单列复核，不能据此把完整测试说成全绿。
- 本机 remote MCP 目录 Git HEAD 为 2a27f7d7，含未提交改动。磁盘源码与候选相比，i_core_server.mjs、i_core_store.mjs、i_memory_read.mjs、mcp.mjs、writeback.mjs 五个文件哈希不同。只比对源码，未读数据库/凭据，未部署或重启；运行一致性尚未验收。
- 用户已在本聊天明确允许将 codex/w0-integrate 推送到 Ritou-Lynx/here-i-am 并创建草稿 PR 运行 CI。此前自动审批拒绝已由明确上传授权解决；正在执行，CI 待运行。合入 v3-lab、运行服务部署及真实数据操作仍须后续独立确认。

W0 详细证据与限制见[整合交接](W0_INTEGRATION_20261005.md)。
