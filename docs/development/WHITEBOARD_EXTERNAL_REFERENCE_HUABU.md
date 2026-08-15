# 外部参考借鉴：microsoft/Huabu（AI 画布协作）

> 日期：2026-08-15
> 来源：https://github.com/microsoft/Huabu （MIT，TypeScript monorepo，微软，活跃维护中）
> 定位：本文件是**借鉴分析**，不是需求或契约。冲突时以《白板并行开发总纲》与 `docs/design/whiteboard-*` 为准。
> 合规：Huabu 仓库内直接材料为 MIT，可借鉴其架构与设计决策。本项目为 Flutter，Huabu 为 React/Electron，**不存在直接复制代码的场景，只迁移架构思路**。借鉴思路不得高于本项目契约，不得复制其身份语义。

---

## 0. 它是什么，为什么值得看

Huabu（"画布"）= 微软的"**你和你的 agent 一起在无限画布上思考**"桌面应用。产品定位与本项目白板工作台高度重合：无限画布 + 卡片/节点 + AI agent 协作 + 跨会话持久化 + Electron 桌面端。技术栈是 React Flow + Zustand + Electron + pnpm workspace（monorepo：`apps/{web,server,desktop,docs}` + `packages/shared` + `agent-teams` + `external/{agenetes,agentlet}`）。

最大价值在 `docs/architecture/`（22 篇高质量架构文档）。以下按对本项目 W0–W5 的价值排序。

---

## 1. ⭐ 三层命令架构：UiIntent → Command → Execution（对标 W0 契约 + W1 画布 + W5 编排）

**这是最值得借鉴的一条**，直接回答本项目尚未解决的核心难题：**用户和林埃都要操作画布、还要能整体撤销/审计**。

Huabu 把画布变更拆成三层（`canvas-command-architecture.md`）：

| 层 | 职责 | 谁产生 | 关键规则 |
|---|---|---|---|
| **UiIntent** | 用户手势语义（依赖选择/剪贴板/viewport 等临时前端态） | 只有 Web/UI | **绝不共享给 agent**；只把歧义手势解析成显式操作数，不直接改状态；不拥有 undo 快照 |
| **Command** | 共享的、可 JSON 序列化的执行指令（唯一被执行器接受的类型） | Web 和 agent **收敛到同一套** | 不依赖任何 UI 态；用显式操作数（node/frame/edge id）；失败返回 `applied:false` 且**无副作用** |
| **Execution** | 批处理/事务边界：校验、**一次撤销快照**、action trace、副作用 | 执行器 | 一个逻辑动作可跨多条 command，合并成**单个 undo step**；服务端是唯一权威 |

数据流：
```
Web 手势  → UiIntent → resolver → CanvasExecution → executor
Agent 响应 → CanvasCommand[]        → CanvasExecution → executor
executor → 校验 → apply → trace → snapshot → effects
```

### 值得抄进本项目的具体决策

1. **agent 和用户走同一个执行器，只是 `source` 不同**（`ui`/`agent`/`system`）。服务端从不直接改状态。→ 本项目 W5 林埃编排产出的应该是 `WhiteboardOperation[]`，**走和用户点击同一条执行路径**，天然获得审计 + 整体撤销，而不是另造一套 AI 专用写路径。正好落地总纲第 2.4 节"林埃写操作必须可授权、可审计、可撤销"。
2. **创建时的选择语义分叉**：UI 创建的节点自动选中，**agent/系统创建的保留用户现有选择**（不抢焦点）。
3. **`editNodeId` 是 transient、绝不进 Command / 持久化 / delta**——所以"agent 执行、SSE 回放、delta 重放都无法打开编辑器或抢焦点"。这是防止 AI 操作干扰用户的精妙边界。
4. **ID 分配双路径**：UI 端前置 mint id（同批次可自引用）；**agent 端由服务器 `preAssignIds()` 分配，拒绝 agent 自造 id**，结果回显真实 id 供下一轮连线。解决"AI 批量建卡后如何连线"的经典难题。
5. **命令自带确定性领域行为**：`DELETE_NODES` 自动删除关联边；`CONNECT_NODES` 端点不是活节点时整条拒绝（不静默丢边）；`SET_NODE_PARENT` 拒绝非法父节点/环。→ 对应本项目 W0 契约里 `WhiteboardOperation` 的语义应内聚在执行器，而不是散落在 UI。

---

## 2. ⭐ Canvas Action Log：append-only JSONL 行为日志（对标 W5 + 记忆）

Huabu 把用户在画布上的每个动作存成 **append-only JSONL**（`<canvasId>/.history/events.jsonl`，每行 `{ts, RecentAction}`），给 agent 提供"超出内存小窗口的长期可查行为记录，用于意图推断"（`canvas-action-log.md`）。

**关键隐私边界（直接呼应总纲第 2.4）**：payload **只存 NodeRef（id/type/label），不存节点内容**——和内存里的 recentActions 同一条隐私线。**日志不直接喂聊天 agent，而是被"记忆策展器（memory curator）"消费。**

值得抄的工程细节：
- 写入用 1s autosave debounce 攒批 + agent 请求前立即 flush + `beforeunload` keepalive；
- **失败响应（4xx/5xx）不计数**；
- op-counter 达阈值（50）才触发一次记忆分析，触发即清零防重复。

→ 本项目 W5 有 `TaskArtifacts`/`TaskDecisions` 表，但**缺"用户画布行为流"这一层**。这套正好补上，且其"行为日志 → 记忆策展器 → 压缩进记忆"链路与总纲"任务房间保留完整过程、主聊天只接收压缩结果"完全同构。

---

## 3. ⭐ 三层记忆分层 + "LLM 自己决定写什么"（对标 W5 + Memory V3）

Huabu 记忆设计极其克制（`agent-memory.md`）：

| 层 | 范围 | 用户可见 | 上限 |
|---|---|---|---|
| Workspace | 跨画布（用户画像/风格偏好） | ✅ | **4KB / 80 行硬上限** |
| Canvas | 单画布（当前意图/小决定） | ❌ 隐藏 | 4KB / 80 行 |
| Skill | 跨画布（可复用配方） | ✅ | 无上限，但**创建门槛高** |

可借鉴：① 记忆**硬性小上限**（强制精炼，防膨胀）；② 整个机制**非阻塞，LLM 决定写什么**；③ 后台策展器用**便宜的 Utility Model**，不占主聊天模型。→ 对本项目 W5 `result_compressor` 和"写回 Memory V3"是现成参照。

---

## 4. 实时多 agent 同步：版本号 + dirty-node 过滤（对标 W1 + W5 未来 Phase 4）

Huabu 用 SSE + **服务端权威 op-log**，让"任意混合的 chat agent / question-node agent / ACP agent / headless caller 并发写入，所有打开的 tab 收敛"（`canvas-realtime-sync.md`）。核心并发原语：
- **`version` 单调递增**做并发控制；
- **dirty-node 过滤**：保证"进来的 agent 写入永远不会覆盖用户正在编辑的节点"；
- **Change Review 卡片**：每个 agent 变更带 label + 反向 delta + staleness 指纹，在聊天输入框上方渲染成 **Keep/Revert 卡**。

→ 本项目当前是单机 Flutter，但产品愿景含"林埃 + 多 Agent 并行"（W5 Phase 4）。这套 **dirty-node 过滤 + Keep/Revert 审查卡**是"AI 改了我的白板、我要能逐条 Keep/Revert"的成熟方案。**记入 W5 Phase 4 设计参考，现在不做。**

---

## 5. 语义缩放 LOD：节点按屏幕宽度切渲染档（对标 W1 性能）

本项目 W1 未完事项含"真实桌面渲染帧率 profile 待补"和 500 卡性能。Huabu 的 LOD 是直接答案（`canvas-zoom-rendering.md`）：
- **`nodeWidth × zoom` 对比 150px 屏幕宽度边界**决定 `full → minimal` 两档，**带 10px 迟滞**（full 缩到 140px 才收起，minimal 涨到 160px 才展开）防抖动；
- minimal 档用 $\sqrt{width×height}$ 选字号档（32/52/76px）；
- **只有 note/pdf/web 节点进 LOD 管线**，其他类型不参与（避免过度工程）；
- PDF 用 **6 页 LRU + 只挂载可见 viewport ±1 屏**，画布内存有界。

→ 本项目 W1 已做 viewport culling（只物化可见视口内的卡片）；LOD 是下一步（可见的卡也分档渲染）。W4 视频/PDF 节点尤其该抄"只挂载可见 ±1 屏 + LRU"。

---

## 6. 其他亮点（值得一看，非核心）

- **存储布局**：每个 Space 磁盘自包含目录，`space.json` + `nodes/<label>.md`（frontmatter+markdown body）+ `.artifacts/` + `.memory/`（AI 私有）+ `.history/`。→ 本项目 W1 现存整块 JSON，Huabu 的**一节点一 .md + 隐藏 .memory/.history 分离**利于 git 友好和外部 agent 读写，值得参考。
- **Structured Frame 布局求解器**：column/row/grid 三种结构化容器，edge 作为布局输入算 gutter，拖拽实时 reflow 预览且**预览绝不写进真实 store**（只在渲染边界折叠）。未来若做"自动网格/列布局"，是完整参照。
- **Agent Reachback (RFS)**：外部 agent 通过 canvas-scoped HTTP（download/upload/query/execute）访问画布，`/execute` 只接受 agent 允许的 CanvasCommand 子集。→ 本项目 W5"外部工具接入"的成熟协议参照。
- **指针路由架构**：单一 capture-phase 指针流 + 优先级 recognizer 仲裁（`node-drag` > `viewport-navigation` > `lasso/frame` …），一处解决"谁拥有这个指针"。→ 本项目若做触控/手写笔适配可参考；桌面鼠标场景可简化。
- **`.agents/skills/`**：Huabu 自己用一套 agent skills 开发（code-review-expert、vercel-react-best-practices 等 rule 文件），与 Hermes skills 体系同构。

---

## 7. 三条立即落地项（已写入 W6 并行提示词作为设计约束）

1. **三层命令架构** → W1（Task B）与 W5（Task A）的设计约束：林埃编排产出命令，走和用户同一执行器，白送审计 + 整体撤销。
2. **语义缩放 LOD** → W1（Task B）验收项：viewport culling 之上加"按 卡宽×缩放 分档渲染 + 迟滞"。
3. **Canvas Action Log** → W5（Task A）扩展范围：append-only 用户画布行为流（只存 NodeRef 不存内容），喂记忆策展器而非直接喂聊天。

本地已下载 9 篇 Huabu 架构文档至 `%LOCALAPPDATA%\Temp\huabu\` 供比对。
