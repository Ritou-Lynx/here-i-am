# W5 — 林埃桌面 AI 工作台总控计划

> 日期：2026-08-22
>
> 状态：P1/P2/P3 已在唯一 G2 候选上重建 staging；当前 Gate 与 P4 分段关系以 `WAVE3_W5_INTEGRATED_ROADMAP.md` 为准
>
> 所有者：W5 集成 / 审核窗口

## 1. 产品目标

林埃悬浮对话是桌面端唯一自然语言入口。Codex 是首个 workbench Runtime，不是第二个人格，也不是一套独立于 Here I am 的任务中心。

最终能力包括：

1. 使用桌面 Codex 登录进行正常、连续、可恢复的对话，不依赖手机 Companion 模型配置。
2. 读取当前页面、选区、白板、卡片、Source、任务产物与经授权的 Memory V3 / Project Memory。
3. 搜索 Here I am 中所有允许当前会话访问的内容，并返回稳定对象引用、来源和权限域；不暴露裸 SQL。
4. 操作白板与卡片：创建、放置、移动、缩放、移除摆放、编辑正文、加减标签、建组、连线、搜索整理、撤销。
5. 执行一次性任务与真正的长期任务；长期任务支持排队、继续、暂停、取消、恢复、状态与产物，普通 turn 不创建 TaskRoom。
6. 收集外部信息并生成单张或多张综合卡片，自动创建白板、摆放、分组和连线，形成可追溯的内容知识库。
7. 生成图片，保存为稳定 Source / SourceVersion / Card / object ref，并直接在白板中安全呈现。
8. 生成 HTML，保存原始版本与经审核的运行 bundle，并在白板中以安全原生预览、聚焦交互方式查看。
9. 未来通过 Memory V3 保持人格连续性；普通任务日志、抓取内容与生成产物不因此自动写入 User-truth。

## 2. 冻结架构判断

- 不扩建独立 Task Center 首页、Planner / Executor 看板或 Codex 子 Agent 树镜像。
- Here I am 持有产品对话、对象身份、权限、审计、撤销与结果落地；Codex 负责推理、计划、工具选择和验证。
- 模型只调用受限领域工具，不直接访问 Drift、任意本地文件或手机模型配置。
- 同一产品 conversation 可绑定可恢复 Runtime thread；产品连续性不依赖单个 Codex thread 永久存在。
- 所有写入用稳定 ID、显式授权、幂等批次、receipt、冲突守卫与 inverse / undo。
- 生成内容先进入 staging，经 hash、类型、安全与预算校验后，才原子绑定 Source / Card / Board；失败不留半成品。
- HTML 卡面默认显示真实静态预览，只有当前聚焦内容启用交互 sandbox；不为 500 张卡常驻 500 个 WebView。

## 3. 当前事实基线

- W5 当前唯一真实产品动作是：读取当前白板选择，提交 group / edge 计划，显示行动卡，持久化并整批撤销。
- 普通桌面消息仍回落手机 Companion Runtime，因此“桌面 Codex 正常对话”尚未实现。
- RuntimeAdapter 已有 thread / turn / resume / steer / interrupt / approval / tool response / events 基础；Flutter 侧尚未把 session binding、resume 与持续对话接起来。
- 白板 Wave3 acceptance 分支已通过自动门禁，但仍处于 Windows 真人 debug，尚未合入 `v3-lab`。
- Memory V3、Project Memory、白板、聊天、TaskRoom 各自已有搜索能力，但没有统一、分权限的 workbench 搜索 facade。
- 当前手机图片生成只写聊天 base64；旧 HTML WebView 允许任意网络导航，二者都不能直接作为桌面白板产物实现。

## 4. 线性门槛

### G0 — W5 当前真人修复收口

把 3 分钟 fallback 窗口、选择完整划分、重开撤销与 conflict hash 修复形成单独基线；不得夹带后续功能。

### G1 — Wave3 白板真人通过

完成富文本、卡面原位编辑、边线 / 移动 / 缩放 / 撤销 / 重启、视频降级与字幕场景的真人验收；修复全部 P0 后复跑自动门禁。

### G2 — W0 一次性汇合

从最新、干净的 `v3-lab` 合入一次 `wave3-acceptance`，处理 `DEVLOG.md` / `I_PROJECT_STATE.md`，组合验证 Wave3 UI 与 W5 selection / flush / reload / undo，再把结果冻结为后续白板工具基线。

### G3 — 共享能力契约

W0 冻结以下 provider-neutral 契约后，写工具与生成能力才可大规模并行：

- `DomainToolDescriptor / DomainToolRegistry`
- `DomainOperationBatch / OperationReceipt / inverse / conflict guard`
- `SearchScope / SearchHitRef / provenance / permission lane`
- `GeneratedArtifact / ArtifactManifest / ArtifactBinding`
- `ContentBundlePlan`：Source、Card、Board、BoardItem、Group、Edge 的原子批次
- HTML sandbox capability / CSP / network / navigation / bridge 契约
- task artifact 到 Card / Source 的显式 promotion / binding

共享 schema、迁移、根依赖、Card / Source / Board / Anchor 身份只由 W0 修改。

## 5. 可并行工作流

### P1 — 桌面 Codex 正常对话与 Runtime 连续性

依赖：G0；不依赖 Wave3 UI。

闭环：普通桌面消息 → Codex App Server → 流式回复 → PersonaChatMessages；关闭面板或 Runtime 重启后可由产品 conversation 恢复 binding；支持停止、重试和诚实错误。普通消息不再打开手机模型配置。

拥有路径：`lib/domain/workbench_ai/`、`lib/data/workbench_ai/`、`tools/dev_agent_bridge/`、对应测试；最终 UI 接线待 G2 后复核。

### P2 — 统一只读搜索与 Context Envelope

依赖：G0；接口先行，不改 Memory / Card 身份。

闭环：Codex 可按 scope 搜索白板 Card / Source、Memory V3、Project Memory、聊天与任务产物；每个 hit 带稳定引用、snippet、来源、权限域与 trace。默认只注入身份、最近消息、当前 surface 和 tool manifest，其余按需取回。

拥有路径：新的 workbench search facade / adapter、Context Envelope assembler、测试；不改 User-truth 写入规则。

### P3 — 生成产物与批次操作 ADR / 契约

依赖：G0；代码落地等待 G2 / G3。

闭环：用 fixture 证明同一授权可描述多 Source / Card / Board / Item / Group / Edge 与 image / HTML artifact，支持幂等、部分失败恢复、来源追溯和整批撤销。

拥有路径：W0 domain contract、fixture、跨契约测试、ADR；不先做 renderer 或 schema 迁移。

### P4 — 基础白板与卡片工具

依赖：G2 + G3。

按独立纵切实现：创建文本卡并放板 → 编辑正文 / 标签 → 移动 / 缩放 / 移除摆放 → 建板 / 批量摆放 → 分组 / 连线 / 搜索整理。每条都必须含授权、审计、重启恢复与批次撤销。

### P5 — Memory V3 人格连续性

依赖：P1 + P2。

先只读召回并保留依据；身份 Prompt 与项目 / 生活记忆按意图、权限和 scope 注入。普通工作台操作不写 User-truth；用户明确“记录”时才进入 Record Organizer。

### P6 — 长期任务队列

依赖：P1 + G3。

复用现有 TaskRoom / TaskArtifact / TaskDecision，只让真正关闭面板后仍运行、需排队或跨设备恢复的任务进入；支持 enqueue / pause / resume / cancel / retry / status。普通对话与短操作不建 TaskRoom。

### P7 — 内容知识库生成

依赖：P2 + P4 + G3。

安全采集来源 → Source / Version → 来源卡与综合卡分离 → 自动建板 / 摆放 / 分组 / 连线 → 一批提交 / 撤销。每张综合卡都能回溯依据，视觉连线不能替代来源绑定。

### P8 — 图片生成并上板

依赖：P4 + G3。

Desktop provider adapter → bytes 校验 → 内容寻址原图 → image Source / Version / Card → 缩略图 / LOD → BoardItem。失败无半卡，撤销软删除实体并延迟 GC 对象。

### P9 — HTML 生成并原生查看

依赖：P4 + G3。

生成 bundle → 静态审核 / 能力判定 → content-addressed web Source / Version / Card → 安全卡面预览 / 聚焦交互 sandbox → 重启恢复 / 撤销。默认离线、`default-src 'none'`，禁 `file://`、任意 localhost、未授权外网、弹窗、下载和宽泛 bridge。

## 6. 实施波次与合并顺序

### Wave A — 当前即可启动

1. P1 Runtime continuity / 普通 Codex 对话。
2. P2 统一只读搜索接口与 Context Envelope。
3. P3 生成产物、批次与 HTML 安全契约草案。

三条使用隔离 worktree，不改正在 debug 的 Wave3 UI；P1 / P2 可以交付代码与测试，P3 在 G2 前只交付 ADR、fixture 与契约变更请求。

### Wave B — Wave3 与 W5 汇合后

1. W0 落 G3。
2. P4 按最小纵切扩展基础操作。
3. P5 Memory V3 只读人格连续性。
4. P6 长期任务队列。

### Wave C — 基础工具稳定后

P7、P8、P9 三条隔离并行；W0 负责共享契约和最终合并，W1 只负责画布节点宿主 / LOD，W2 负责综合文字卡，W3 负责外部采集，W5 负责 Runtime / 权限 / 审计 / 批次。

## 7. 每条工作流的统一验收

- 正常、空、失败、权限拒绝、取消、超限与重试状态。
- 模型无直接数据库、任意文件、手机模型配置或未授权网络访问。
- stable ID、幂等、事务 / journal、来源与产品审计齐全。
- 撤销不覆盖用户后续修改；重启后对象、布局、预览和任务状态一致。
- 真实 Windows 入口验收，不只跑 fake Runtime 或静态 HTML。
- 500 卡、LOD、输入焦点和 WebView 数量不回归。
- 生成 / 抓取 / 任务过程不自动进入 User-truth。
- handoff、目标测试、组合回归、`I_PROJECT_STATE.md`、`DEVLOG.md` 与 i closeout 完整。

## 8. 当前总控决策

**现在不合并 W5 与 Wave3，也不让它们永久分开。**

Wave3 继续完成真人 debug；W5 先从稳定的产品 / Runtime 契约推进 Wave A。两边在 G2 由 W0 一次性汇合并做组合真人复测。此后所有直接操作白板、图片节点和 HTML renderer 的任务都从汇合后的新基线派发。

