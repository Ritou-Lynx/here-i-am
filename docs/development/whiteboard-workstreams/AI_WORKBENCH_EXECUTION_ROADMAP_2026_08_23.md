# AI 工作台 × 白板执行路线（2026-08-23 冻结版）

> 状态：Phase 1 已本地合入 `v3-lab`；P4/P5/P6 可从该基线并行启动，W4 字幕严格 Gate 仍为红灯
> 唯一基线：`v3-lab`  
> 取代范围：取代旧路线中的“最近两步”和未开始波次顺序；既有数据、视觉和安全契约不变

## 1. 当前结论

当前产品已经具备：桌面林埃入口、普通 Codex 对话、进程内连续性、真实 stop / App Server 重启后 provider thread resume、生产 Runtime 受限搜索注册、当前选区读取、有限的分组连线与整批撤销、Artifact Core 最小恢复执行器、生成产物与 HTML 安全契约，以及白板 Card / Source / Board / Group / Edge / 视频研读底座。

当前尚未具备：Memory V3 人格上下文、通用卡片/白板工具、长期任务队列、Artifact Core 生产 repository adapter / renderer / 后台扫描、知识库生成、图片生成上板、HTML 原生展示。

两个新增调研的处理结论：

- **字幕抓取仍是独立 P0，但平台事实已改变。** 无 Cookie 安全 transport 与 resolver 已接入；18 个公开 BV 的匿名正轨仍为 0，其中 17 个诚实 `noTrack`、1 个 `accessRestricted`。不伪称严格 Gate 通过，也不因平台不暴露匿名轨而阻塞与字幕无依赖的 P4/P5/P6。
- **一起看视频进入 Parking Lot。** 保留研究成果，不进入本轮实现、不占开发窗口；重新启动必须至少满足字幕闭环稳定、任务队列可用且用户重新提升优先级。

## 2. 优先级与阶段

### Phase 0 — W0 冻结与干净基线（线性，当前窗口）

1. 对照代码复核两份调研，禁止按过时假设重复实现。
2. 冻结本路线、窗口所有权、Gate 和集成顺序。
3. 把调研、路线、项目状态与 DEVLOG 作为同一控制面提交到 `v3-lab`。
4. 从该提交创建隔离 worktree 窗口；功能窗口不得自行合并 `v3-lab`。

退出条件：路线文件已提交；现有无关 UI 调整不被纳入；后续窗口拥有路径互不重叠。

### Phase 1 — 解锁波次（首批并行）

| 优先级 | 工作包 | 目标闭环 | 依赖/限制 |
|---|---|---|---|
| P0 | W4 字幕真实闭环 | Bilibili BV → 匿名元数据/cid → 字幕轨 → bcc JSON → `TimedTextTrack` → 现有研读 UI；无字幕/权限/网络/解析失败诚实分类 | 不读取 WebView Cookie，不做 ASR，不碰 W7；先审计现有实现，禁止重复造 resolver |
| P0 | W0 Artifact Core 最小执行器 | 把 P3 的 `ContentBundlePlan` 从契约变成可验证的 staging、hash 校验、领域提交、binding、receipt、失败恢复执行链 | 共享契约与 Repository 由 W0 审核；不得顺手做 P7/P8/P9 UI |
| P1 | P2 Runtime 搜索接线 | 把既有 `WorkbenchSearchToolHost` 注册到桌面 Runtime，并由产品代码赋予 Card / Memory V3 / Project Memory 的只读授权 | 模型 payload 不能扩权；暂不开放聊天/任务产物未完成 scope |
| P1 | P1 韧性验收 | stop、Bridge 重启、provider thread resume、跨进程连续性的诚实降级与自动证据 | 不改白板命令或手机模型设置 |

并行关系：W4、搜索接线、P1 韧性可以并行；Artifact Core 由独立窗口实现，但共享语义变更必须先返回 W0，不得直接决定 schema。Flutter 全局构建和真人 Windows 进程仍串行。

#### 2026-08-24 Gate 结果

- Runtime 真实普通回复、active interrupt、App Server stop + 同 provider thread resume 全部通过。
- 真实模型连续调用 `search_workbench_content` 得到 1 条 Card 命中与 0 条空结果 trace；模型 payload 注入 `authorization` 扩权被 `invalid_search_request` 拒绝。
- Artifact Core 最小执行器、crash state machine 与恢复回归通过；生产 adapter / renderer 仍是后续 Gate。
- Windows 真人已通过逐条文字拖选 + `Ctrl+C`、真实选区分组连线与无中间改动的整批撤销。
- W4 严格匿名正轨 Gate 为 **FAIL (0/18)**；保留 noTrack/accessRestricted + SRT/VTT 后路，若要登录可见轨必须单开 Cookie/隐私 ADR。

结论：P4-T1/T2、P5、P6 可从同一新 `v3-lab` 基线并行开发；各自合入仍受下方对应依赖约束，不得把 W4 写成已通过。

### Phase 2 — 基础能力波次

满足对应 Gate 后启动：

1. **P4-T1/T2**：创建卡片、编辑正文、标签、移动、缩放、移除摆放；必须复用人工入口的 DomainCommand / Receipt / Undo。
2. **P5 Memory V3**：在搜索 Runtime 接线合入后，做人格与长期关系的只读 recall/context；不写 User-truth，不把普通聊天自动变成记忆卡。
3. **P6 队列 Core**：enqueue / pause / resume / cancel / retry / status；普通短 turn 不建 TaskRoom，TaskArtifact 上板继续等待 Artifact Core + P4-T1。

这三条可以并行开发，但合并顺序固定为：搜索接线 → P5；Artifact Core → P4 生产写入；P1 韧性 → P6 的 Runtime 恢复验收。

P4 必须同时收口一个已知 Undo 限制：当前画布 `Ctrl+Z` 历史只在当前 ViewModel 内，退出画布后会丢失；跨退出的 DomainCommand / Receipt / Undo 持久化不得宣称已完成。

### Phase 3 — 内容生成波次

1. **P4-T3/T4**：建白板、批量摆放、分组、连线、搜索整理。
2. **P7 内容知识库**：采集与来源追踪、生成多卡、建板、建组、连线；只调用 W3 ingestion facade，不自建抓取器。
3. **P8 图片生成上板**：provider、bytes 校验、Artifact Core 提交、图片卡渲染。
4. **P9 HTML 原生展示**：HTML scanner、离线 runtime bundle、CSP/sandbox、聚焦时交互渲染。

P7/P8/P9 可以并行完成各自 provider/validator/scanner，但任何“直接上板”都等待 Artifact Core 与对应 P4 命令完成。

### Phase Later — 明确后置

- W7 一起看视频、Spoiler Gate、模型共同观看会话。
- 本机 ASR 主路径、直播、感官输入、视频代理/下载、DRM 内容。
- FlexNote 长尾、导出、手绘和高级双链按各自路线继续，不反向阻塞上述 AI 基础能力。

## 3. 字幕工作包的现实矩阵

| 能力 | 当前状态 | 本轮动作 |
|---|---|---|
| Bilibili URL / BV 识别与 Source 入库 | 已有 | 回归保护 |
| Windows 顶层页播放与时间桥 | 已有，依赖运行时握手 | 不改语义，真人回归 |
| `TimedTextTrack` / cue / SRT / VTT | 已有 | 复用 |
| 平台统一 resolver | 已有 | 复用 |
| Bilibili 自动字幕 transport | **已实现**无 Cookie 安全 transport / redirect / size budget | 保留，不扩展 Cookie |
| 匿名无字幕、AI 字幕不可见、地区/权限失败 | 18 个真实 BV：17 noTrack / 1 accessRestricted | 平台红灯，诚实降级 |
| 登录 Cookie 增强 | 未实现 | 本轮禁止；若匿名路径确实不足，另提安全 ADR |
| 小红书自动字幕 | 不支持 | 保持诚实降级 |

字幕本轮最小成功定义不变：至少一个公开 BV 在不登录、不读取 Cookie 的条件下加载真实 cue；一个无字幕或受限 BV 返回准确失败；关闭重开研读页不写入签名 URL；SRT/VTT 后路不回归。截至 2026-08-24，第一项仍未成立。

## 4. 固定 Gate 与集成顺序

每个窗口必须提交：实现 commit、定向测试、changed-file analyze、`git diff --check`、handoff、未完事项。W0 不接受“能编译”作为功能完成。

集成顺序：

1. 审核窗口的边界与 diff；共享 schema/依赖/生成文件变更先停下裁决。
2. 选择性合入一个功能提交，处理状态文档，不自动合并窗口的 DEVLOG 冲突。
3. 跑该包专项 + 白板/Codex 组合回归。
4. 构建唯一 Windows 候选；同时只运行一个 `memex.exe`。
5. 需要平台事实的包进行真人验收；失败回原窗口返修，不在 W0 临时打补丁掩盖。
6. 通过后发布新的唯一 `v3-lab` 基线，再开启受它依赖的下一波。

## 5. 首批窗口所有权

### W4-S 字幕窗口

- 拥有：`lib/domain/whiteboard/video/` 中字幕 transport/resolver 的窄增量、对应测试、W4 handoff。
- 只读：播放器 bridge、LinkIngestor、Canvas、Repository/schema。
- 禁止：Cookie UI、WebView profile、ASR、W7、视频下载。

### W0-A Artifact Core 窗口

- 拥有：新的 Artifact executor/store adapter/recovery 测试与独立 handoff。
- 只读：P3 契约、现有 Repository；若需改共享语义，先提交变更请求。
- 禁止：P7/P8/P9 provider、Canvas renderer、schema migration。

### P2-R 搜索接线窗口

- 拥有：workbench Runtime 的搜索工具注册、产品授权组装、对应测试与 handoff。
- 只读：Memory V3 / Project Memory 核心与 P2 搜索契约。
- 禁止：Memory 写入、裸 SQL、聊天/TaskArtifact 未完成 scope 的伪实现。

### P1-R 韧性窗口

- 拥有：conversation coordinator / Runtime binding 的 stop、resume、Bridge restart 与恢复测试。
- 禁止：白板 UI/命令、手机模型设置、Memory V3。

## 6. 总控工作方式

“Go 模式”在本路线中表示：路线冻结后直接创建可见 Codex 开发窗口并立即运行，不等待逐项口头确认。每个窗口使用隔离 worktree；W0 只做排程、边界裁决、diff 审核、选择性集成和真人 Gate。新窗口不再派生子 Agent，不直接 push，不自行修改总路线。

