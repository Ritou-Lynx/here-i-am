# 个人数据中枢首批派发表（2026-10-05）

输入：[总规划](../PERSONAL_DATA_HUB_PLAN_20261005.md)，来源 `claude/festive-ride-88vh1t@053000db48bfd19700a2ab583842d50d7744c151`。W0 起点为远端 `v3-lab@f605d501`，依次普通合并 wonderful-carson、b3-writeback、festive-ride；完整候选 `9b23d511fc28d588c3d1fe2c73014901e4824070`。WI/WL/W6 因独立，可先基于此候选交付；正式下游仍等 W0 合入。

| 工作包 | 执行者 | 分支 | 拥有路径 | 状态与下一步 |
|---|---|---|---|---|
| W0 | 主 Agent i | codex/w0-integrate | 整合冲突、运行源码补齐与全局交接 | 三条分支整合后保存三处已提交本地补丁；本轮当前接口 344 过/0 红/1 跳，递归 353 过/42 既有红/1 跳；[PR #5](https://github.com/Ritou-Lynx/here-i-am/pull/5)新候选 CI 以 Checks 为准，完成后转 ready 并请求合入 |
| WI | /root/wi_local_planner；Astra/high | codex/wi-local-planner | tools/life_planner/；handoffs/WI_LOCAL_PLANNER_20261005.md | 已交付并复核；12/12 合成测试；主窗首次本机空初始化通过，今日单待补充；真实排程待事项/容量 |
| WL | /root/wl_study_instructions；Luna/low | codex/wl-study-instructions | tools/siyuan_tutor/；handoffs/WL_STUDY_INSTRUCTIONS_20261005.md | 已交付并复核；学习块/结果接口、未学准入与只学习不测规则已闭合 |
| W6 | /root/w6_authority_draft；Astra/high | codex/w6-authority-draft | data-authority-preflight/W6_*_20261005.md | 草案已交付并复核链接/源码；17 项待用户确认，未启动迁移 |

新增独立任务：i_core 42 项旧失败修复，thread `01a10b3e-cb9f-7ed0-9476-a81cc05ffdd5` / host local，分支 `codex/i-core-test-debt-20261005`，基线 `f605d5017cbc0a8eb69983e00c25cd1bba08a0eb`。以[逐项清单](W0_BASELINE_FAILURES_20261005.md)为输入，逐条区分代码缺陷/测试过时/fixture 或环境问题，不跳过、不屏蔽；只交自身 diff 与 `I_CORE_TEST_DEBT_20261005.md`，当前未授权提交或部署。

所有工作目录在正式 C 盘源码区，独立 worktree。worker 不提交、不推送、不派生，只写自身 handoff；主窗复核并统一更新状态。三个独立包不进入 W0 整合 PR。D 盘私人旧谱系和本地 v3-lab 未改动。

## 依赖释放

- 2026-10-05 用户最新决定：W1 暂不派发，等数据中心方向明确后再由用户释放；W0 合入不自动启动 W1。原规划的接口约定与后续领域依赖保留，但不执行。
- W1 约定确认后 W3/W4/W5 同时接假服务；W1 实现后释放 W2。
- W2/W3 完成后释放 W8，W3/W4/W5 再接真服务。
- W1 完成且 W6 决定确认后，W7 按领域分别开工。
- 合入 v3-lab、生产 Core 停止/升级、真实数据迁移、主力手机安装仍按总规划分别确认。

## W0 限制与收尾边界

- 42 项完整递归失败在 v3-lab 与本轮补齐后 W0 中逐项相同，新增为 0；[完整清单](W0_BASELINE_FAILURES_20261005.md)注明 41 终端条目和 1 父汇总，不报全绿。用户要求另开窗口逐项修复，不跳过、不屏蔽。
- 运行五处差异归属已查明并处理源码：两 Core 旧版待部署更新，三处正式通用补丁已收入分支。详见[运行更新交接](W0_RUNTIME_UPDATE_20261005.md)。实际进程加载版本、部署和真实跨端验收尚未执行。
- 用户授权补齐 W0 并转 ready；合入 v3-lab 仍待最终确认，部署/真实数据操作另行授权。新候选 CI 绑定其准确 head，不继承原候选结果。

W0 详细证据与限制见[整合交接](W0_INTEGRATION_20261005.md)。

## W0 收尾的最新决定

用户明确要求将 42 项既有失败在 PR 逐项说明，并另开窗口修复，不能误报递归全绿。五处运行源码差异已归属：两处 Core 旧版待合入后更新，三处已提交通用补丁已选择性保存到 W0，详见[差异与更新步骤](W0_RUNTIME_UPDATE_20261005.md)。W0 完成对应验证与最新候选 CI 后改为 ready，再请求合入；不自动合并或部署。WI/WL 的现有独立交付与后续验证照常，W1 明确暂缓。
