# MDA-1 主线协调与本地提交审查

> 当前结论：**Lynx 已明确授权，MDA-1 源码与八份重叠文档已本地合入 v3-lab；现役仍固定 v4，未部署 schema 5。**

## 实际落地（2026-09-12）

| 提交 | 实际内容 |
|---|---|
| `06b2c68e074695cebf5833c0d543d8ebc969e04a` | 隔离候选 A；68 路径；双父为原目标 bbb8025d 与来源 44268fa9 |
| `42beaa96bd489e6af841b243b10e49c7a086823d` | 主目录 B；只含获准八文档，明确收口原五份 staged；两个 Goal 的原 working 内容保持 |
| `8326f5c1507a1bc235058161b77b649ae2719392` | 合并 C；双父为 A、B；最终 70 路径；主目录已正常 ff-only 到 C |

C 按原 hook 要求只补了一条真实提交中间状态，未改功能；本次后续文档提交将该中间状态对齐为已经落地。全部提交使用原项目状态检查，没有 reset/stash/强覆盖、独立 update-ref、跳 hook 或 push。

独立范围复核、路径/blob 断言及正常 Git 演练通过。原组合覆盖的 32 个源码/fixture/运行工具保持已测指纹；快进前后另外 41 个 dirty 文件全部 SHA 一致，P6 源码未进入本次提交。独立前后运行检查显示固定 release、manifest/Node 哈希、任务、PID 32704/父 40532、单一 47841 listener 与 health 均未变；没有打开真实 DB 或切换 schema。

实际提交、保护与运行证据在本任务工作树 `tmp/mda1-mainline-execution-20260912/` 的 commit-a/b/c、main-landed、runtime-before/after 与最终验收记录。原审查清单和合成演练保留在 `tmp/mda1-mainline-coordination-20260912/`；其待授权/未提交状态是历史输入，不是当前结论。P6 新返修结果仍由原负责人在释放共享窗口后补入，MDA 不提前登记其 Gate。

## 以下为提交前审查记录（历史）

> 2026-09-12；责任任务 `01a0917d-17fa-7bf3-a282-fd4c551d93b2`。
> 状态：共享文件归属已协调，隔离融合版本及提交路径清单已备好；本轮未修改主目录文件、索引、分支或运行配置。

## 已经成立的边界

- 原 MDA 组合候选通过情况见 [裁决](MDA1_INTEGRATION_VERDICT_20260912.md)。它仍是未提交的隔离合并，目标 `bbb8025d99fc0acaa846d58b4e5a94cef90f8756`，第二父项 `44268fa91238bfde50363a1207120faee0a9f650`。
- 固定旧 v4 包已经切换；[运行记录](ICORE_V4_RUNTIME_PIN_SWITCH_20260912.md) 包含实际 schema 4、身份保持与退出/启动证据。Lynx 只确认切换后原手机聊天可承接前文，不据此声称请求必经 iCore、全量历史同步或长期记忆全链路通过。
- 此次源码合入方案不切换该固定运行包，不迁移真实库，不启动 MDA-2，不操作 P6 进程、账户、设备或队列。
- P6-R7 v5 本机八项矩阵通过，生产仍关闭，P6 / Goal 1 未通过。P6 源码与专项证据不随本 MDA 候选交付。

## 归属与窗口

主目录负责人任务为 `01a07b2e-1717-7582-8555-909389a9c03e`（Here I Am｜Goal 1 主验收接管｜P6 返修与验收）。负责人直接确认三全局文档的 P6-R7 v5 段为当前保留版本；其新的 R7 执行器/停止返修尚未写入三文档，不能提前登记通过。

负责人给出五份共享文档及 Git 索引的短暂串行窗口，同时继续独占源码和专项 handoff。该答复明确没有新增 P6 commit/push 授权。原五份 staged 是历史 P4/P6/Goal1 收口内容；其中较早的删除/回退不能单独替代各文件最新 working 内容。

本轮只制作隔离融合版本，不消费主目录原索引。结束审查时释放窗口；真正执行前重新协调窗口，并逐项核对 HEAD、原 staged blob 和八份 working 指纹。任一变化都只重整合受影响部分，不能沿用旧快照覆盖。

## 八份重叠文档的具体处理

| 项目相对路径 | 拟进入本地文档收口提交的内容 |
|---|---|
| `DEVLOG.md` | 主目录最新 P6 历史完整保留，融入 MDA、旧 v4 切换与用户有限续用确认 |
| `docs/development/I_PROJECT_STATE.md` | 保留最新 P6/COROS 当前态；MDA 只留一个最新入口，旧准备/切换前状态明确归为历史 |
| `docs/companion-first/PRODUCT_ROADMAP.md` | 保留 P6 / Goal1 未通过；汇合已接受的 Gate1A-0 / MDA 隔离链，修正仍称尚未创建的现态 |
| `docs/development/goals/GOAL-20260824-ai-workbench-wave1.md` | 使用主目录当前 working 内容，不自行改变 P6/Goal1 判定 |
| `docs/development/goals/GOAL-20260828-p4-production-reachability-repair.md` | 使用主目录当前 working 内容，保留已经结束的 P4 验收，不恢复旧 staged 待验快照 |
| `docs/development/activity/mda0/REAL_DEVICE_GATE_RECORD.md` | 完整保留主目录 C-12/C-13，再保留候选 C-14 与已冻结 structured replay 契约 |
| `docs/companion-first/MULTI_DEVICE_ACTIVITY_ROADMAP.md` | 采用已验 MDA 来源及当前 COROS 事实，保留 1 天 raw 产品合同和 BLE 现状差距 |
| `docs/development/activity/mda1/MDA1_V3_LAB_INTEGRATION_PLAN_20260912.md` | 原主目录与候选内容一致；只新增历史快照与当前入口说明 |

前三份和两个 Goal 构成原五份 staged；硬件记录是额外 unstaged 重叠；末两份是 untracked 同名碰撞。所有其余 P6 源码仍保持未提交，不把文档提交叫作 P6 功能集成。

## 待一次性确认的正常 Git 顺序

授权范围是 **隔离候选本地提交、上表八文档本地收口提交，以及正常合入本地 `v3-lab`**。不含 push/发布。原五份 staged 会被上表明确的最终 working 版本收口；这一步必须在确认范围中明说，不能以 MDA 授权默默代交 P6 文档。

1. 在隔离工作树完成现有 pending merge，提交 MDA、固定 v4 工具、三文档融合及本审查记录，得到 A。只纳入审查清单路径，排除 `tmp`、固定运行二进制、真实数据与配置；保持来源第二父项。
2. 在主目录写入上表审核版本；两个 Goal 的 working 字节原样保留。确认索引仍只有原五份文档后，仅 stage 上表八路径并正常提交为 B。不得带入其他 staged 或 P6 源文件；发现新的 staged 路径立即停止，重新协调。
3. 在隔离工作树正常合并 B。A/B 的六份 MDA 相关文档内容应相同，另外两个 Goal 从 B 单边进入，得到 C；若实际有冲突，先在隔离区解决并复核。
4. 核对 `C - B` 与主目录其余 dirty/untracked 路径无交集，确认共享窗口仍有效、HEAD 仍为 B 后，在主目录正常 `--ff-only` 到 C。
5. 检查最终 HEAD、索引和其余工作树指纹，确认运行包 manifest/任务入口未变并释放窗口。运行检查只验证已有固定版本，不重启服务或发送消息。

不使用 reset、stash、强覆盖、单独 update-ref 或临时重建主索引。A、B、C 是待执行角色名，目前都不存在，不能当成已经提交的 hash。

独立流程审计确认上述正常 Git 顺序可保留其余未暂存工作。执行时以 staged blob 核对 A/B 六份重叠文档，而不是用 CRLF 可能不同的工作区字节推断；B 提交前索引精确为八路径，提交后索引应空，`B^..B` 差异精确为八路径。A 的完整白名单为 68 路径，B 为八路径，最终 C 相对原目标共 70 路径；两个 Goal 只从 B 进入。任何额外 staged 路径、父项漂移或冲突都重新审查，不自动带过。

## 可复核材料与限制

本工作树 `tmp/mda1-mainline-coordination-20260912/` 保存八文件输入快照、原 staged blob、融合提案、预览差异及保护检查；最终清单在候选内容之外生成，避免自引用。旧 `tmp/mda1-integration-20260912/` 原 tree/patch 保持冻结，后续融合有独立清单，不能继续把旧 tree 当最终全部内容。

本轮修改仅为文档整合；MDA 功能与 runtime-pin 源文件必须逐一证明仍与已测字节相同。此前 MDA 组合和 runtime-pin 6/6 的结果只用于对应未变源码；不以文档审查或模拟 Git 演练代替真实主线合入、运行升级或新的真人 Gate。
