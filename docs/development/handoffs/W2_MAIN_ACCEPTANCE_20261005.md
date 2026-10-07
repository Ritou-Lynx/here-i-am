# W2 主窗源码验收（2026-10-05）

基线为 W1 合并 `dc29fd5e1ed8694bf301929bf011cf53bbce16e3`；[PR #8](https://github.com/Ritou-Lynx/here-i-am/pull/8) 的五类精确 head 检查全通过，合并树等于已测 head 树，见 [W1 合并回执](W1_DOMAIN_MERGE_20261005.json)。42 既有失败修复已通过 [PR #7](https://github.com/Ritou-Lynx/here-i-am/pull/7) 普通合入。原 worker 工作副本和现役库保留。

本包实现 captures、plan_items、plan_weeks、plan_days 的严格业务字段、权限及处理者输入版本，提供默认 dry-run 的本机 notes/WI 导入。业务注册仍显式且默认 off；ICoreStore/server 只传递受控 hooks/adoption verifier。公开 HTTP 不开放 legacy adoption，不自动注册业务、升级库或签发凭据。

## 主窗验证与源码绑定

- 最终全递归包含 **Core、Memory、remote MCP、continuity gateway 四个根目录，42 个测试文件、654 项：653 通过、0 失败、1 原有 Windows 大小写文件系统跳过**；135 条源码前后字节一致。测试仅合成或专用临时库。
- 业务专项 31/31、引擎与 adoption 77/77；主窗新增真实 createICoreServer HTTP 专项通过，覆盖默认 off、用户证据、手机仅改完成/放弃、服务端派生完成时间、本机保留旧 revision、拒远程 adoption，以及重启缺 hooks 时该域 503/旧健康接口正常。
- 完整回归后只补现有 R3 断言的失败消息，打印合成 guardian/witness 结果；原 `parent_exit_observed === true`、Job 为空和退出码断言全部保留。随后父级及 CREATED/DUPLICATED/PUBLISHED **4/4 再通过**。完整回归属于补消息前的字节；产品源码未变，诊断变更有原文重建证明，不能把两次运行冒称同一字节的完整运行。
- [机器回执](W2_MAIN_ACCEPTANCE_20261005.json) 包含各运行日志摘要哈希、13 个当前源/测试原始字节哈希、135 路径守卫结论及诊断变更证明；Git staging 规范化 blob 与原始字节分别绑定，不冒称二者完全相同。

## 保留的首轮失败

首轮包含 Core/Memory/continuity gateway **34 文件、570 项：567 通过、2 失败、1 原有跳过**；其中一个 CREATED 叶子及其父级失败，未包含 remote MCP。原 TAP 哈希保留，不被后续通过覆盖。

该时刻 R3 service.test/owned_job 与 W1 字节相同，独立 witness 确认父、guardian、子孙已退出，Job active=0、子孙 exit=137、原合成数据库字节不变。失败发生在 guardian 的 `parent_exit_observed`；原日志未打印具体 reason 且夹具已清理，无法恢复唯一触发分支。既有实现存在清理前零等待采样与最终 witness 观察的时间窗口，但不能据此断言原故障已被唯一解释或已修复。此次只补诊断，不改生产 guardian，不弱化断言、不新增 skip。

## 集成决定与剩余范围

准予有限源码整合；业务启用和上线尚未验收。字段/hook/adoption 边界见 [引擎交接](W2_ENGINE_HANDOFF_20261005.md)、[业务与导入交接](W2_BUSINESS_DOMAINS_20261005.md)。

现役仍为固定 schema4 transcript/replay 版本。W1 授权副本链只证明数据库保全；切换前仍需保全并验证现役功能、外置政策和凭据。真实 notes/规划未导入：旧传输 delivered_revision/card_id 与 WI processed_receipts 留在不变只读源，不被虚构为目标处理完成；周/日 Markdown、学习引用及旧 receipt 映射未决时报告 mapping_required/partial，CLI 非零退出。

下一步可并行实施 W3 领域 MCP、W4 捕获入口、W5 今日/本周 UI，基于已验合同和本包合成 Core；W3 部署前先完成运行源码/配置对齐检查。W7 手机基础独立验收，逐域权威迁移、七天影子对账、回滚演练、真机及服务切换 Gate 继续单列。
