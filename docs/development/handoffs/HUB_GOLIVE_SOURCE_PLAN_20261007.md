# B 线：记一下与规划上线前源码准备

## 范围与基线

- 独立任务 `01a11502-ef12-7613-bb9c-60f2fddd6e5e`；分支 `codex/hub-golive-src-20261007`。
- 从正式净化仓库 fetch 后的 `origin/v3-lab@0a24cac2b7db812f34fb845325e27b77d16139dd` 开始；唯一远端 `Ritou-Lynx/here-i-am`。不引入私人 Git 谱系，不等待 A 线 PR16。
- 授权范围为源码、合成测试、提交、推送与草稿 PR；不合并、不部署、不启停现役、不读真实数据库/凭据、不安装手机、不注册任务。
- 主窗口拥有 release_schema6、maintenance、生命周期/会话启动器和现场清单。新版 MCP 库存及 hash 如有变化，只交接主窗口合入后处理。
- 上海时区：目标 10/09 前完成源码与测试；默认 10/17–18 上线，允许 P1 在 10/09 单独上线。10/09 中午仍未全部完成时优先交付完整 P1，并量化 P2/P3 剩余项。

## 分包与顺序

| 包 | 执行者与拥有路径 | 退出条件 | 当前状态 |
|---|---|---|---|
| P1-MCP | p1_mcp；tools/i_remote_mcp | i_remember → captures、scopes、聊天兼容；合成 API 与权限测试 | 100 项合成测试通过；受信网页授权 issuer 与正式 host 装配仍缺 |
| P1-App | p1_app；lib、test 的捕获路径 | W3 改版/删除保护、W4 真实 API、Organizer、47862 单消费者；widget/逻辑测试 | 候选接线与撤销守卫完成；52/131/74 分组通过，启动/回滚返修 37 项通过，主控最终组合 65 项通过，15 文件分析无问题；生产入口/Gate 未完 |
| P1-Import | B 线主控；tools/i_core/import_personal_notes* | 默认 dry-run、旧 ID/revision/墓碑、planner skipped、幂等 | 复用现有实现，相关 36 项合成测试通过 |
| P1-Handoff | B 线主控；本交接及独立上线清单 | 单上传器交接/退回方案与测试；每步授权和退回点 | 独立清单已提交；上传器 32 项通过，未启用切换 |
| P2 | P1-App 收口后独立提交 | 今日/本周、状态 outbox、离线副本、拒绝提示和闹钟；widget/逻辑测试 | 28 项专项通过；新增放弃冲突回退用例，最终组合覆盖；正式读写仍依赖显式 route 与 host |
| P3 | p3_planner；tools/life_planner | MCP 规划存储、capture 监视器；假 Codex 故障测试和上线手册 | 默认禁用候选完成；主控最终 25 项通过，状态转授权与 dot bridge 仍缺，真实一天 Gate 未执行 |
| 集成 | B 线主控；CI 与各包交接 | 审查 diff、专项回归、精确 head 的 CI 全绿、草稿 PR | 分包回收与独立复核完成；推送后记录最终 head CI。创建 PR 的 GitHub 连接器返回 403，隐藏网页入口超时，本机无 gh；交接预备 PR 正文，不冒称已创建 |

P1 的候选提交与清单独立交付，P2/P3 不作为 P1 上线依赖。当前 P1 尚未完整：正式 Core host、网页受信授权入口、手机授予及 route 迁移、47862 adoption/Gate 接线仍须关闭，详见 P1_RUNBOOK。共享 Git 索引、CI 配置、全局文档由主控串行处理；worker 不提交，不继续派生。

## 证据与边界

PR11/13 已有实现和历史证据仅用于定位；本候选需重跑相关专项。源码、自动测试、Windows CI 构建、安装和真人/设备 Gate 分开记录。旧桥保留到真正完成增改删闭环与来源 adoption；合成测试不代替该 Gate。

本窗口 bootstrap 为未注册 ephemeral 项目，不能声称已写入跨工具项目记忆。持久交接以本源码文件与草稿 PR 为准。需要用户本人或生产授权的项目仅列入交接，由主窗口统一联系。
