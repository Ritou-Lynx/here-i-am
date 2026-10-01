# 白板 W0–W4 Session 启动提示词

这些是首轮纵切模板；续作先读当前 Goal / handoff 的更窄范围，不重复已完成的 W0 或首轮选型。首次实现依次使用已验收的 W0 基础，再从工作包记录的精确 v3-lab commit 创建 W1–W4 隔离 Worktree。模型路由统一见根 AGENTS.md。以下段落保留各线独有的目标与 Gate。

## 提示词 1：W0 共享契约第一阶段

```text
你现在负责 Here I am 白板并行开发的 W0「共享契约第一阶段」。这次指令明确授权你在隔离 worktree 的临时分支上实现、验证并提交本工作流，但不要 push、不要合并到 v3-lab。

开始前：
1. 读取根 AGENTS.md、完整白板总纲 docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md 及 docs/development/whiteboard-workstreams/W0_INTEGRATION.md；按总纲第 1 节加载本轮相关共享类型、fixture 与领域章节。
2. 确认这是独立 worktree，基线取任务指定的精确 v3-lab commit，分支名使用 codex/whiteboard-w0-contracts。若当前目录承载其他修改，按已授权的隔离方式创建 Worktree；基线有实质歧义才询问，不得 reset、stash、清理或覆盖他人改动。
3. 按总纲第 6 节给一次简短边界声明，再开始修改。

本轮只完成 W0 基础，不承担以后所有集成：
- 盘点现有 desktop/whiteboard_mvp/src/model.mjs 与测试，只把它当行为证据，不把 DOM / localStorage 格式升格为生产真相。
- 在符合现有 Flutter 架构且不依赖 MemexRouter、CardCache 或 UI 的独立领域目录中，建立最小共享类型：稳定字符串 ID；SourceContent / SourceVersion；CardContract；Board / BoardItem / BoardGroup / GroupMember / BoardEdge；AnchorContract；WhiteboardSnapshot / WhiteboardOperation；IngestionResult；RichTextDocument 的最小外壳；TimedTextTrack；PlayerAdapter 的能力接口。
- 清楚区分 Card 内容与 BoardItem 布局；删除 BoardItem 不删除 Card / Source；Anchor 必须绑定 source_id + source_version_id；引擎私有 ID 只能存在 adapter 映射。
- 建立版本化 JSON fixture：正常样例、空状态、失效 Anchor、旧 schema 迁移样例、非法输入样例；补充序列化往返、ID 引用完整性、删除语义和向后兼容测试。
- 写一份短 ADR，冻结产品领域模型与第三方白板引擎之间的 adapter 边界，并列出 W1–W4 可依赖的入口。
- 不做数据库迁移、不加第三方依赖、不做生产 UI、不选择最终白板引擎、不实现具体抓取器 / 编辑器 / 播放器。

完成标准：针对性 Dart 测试通过；对修改范围做 analyze；fixture 可被 W1–W4 独立消费；更新 W0_INTEGRATION.md handoff，由集成主窗合入后统一更新项目状态与 DEVLOG；列出仍待决定的字段，不用猜测填满。验证完成后提交到当前临时分支，提交信息聚焦 W0 contracts；不要 push 或 merge。最终回复给出提交号、测试结果、共享契约清单、后续四条线的接入方法和未完事项。
```
## 提示词 2：W1 白板画布与交互

```text
你现在负责 Here I am 白板并行开发的 W1「白板画布与交互」。这次指令明确授权你在隔离 worktree 的临时分支上实现、验证并提交本工作流，但不要 push、不要合并到 v3-lab。

开始前：
1. 读取根 AGENTS.md、完整白板总纲 docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md 及 docs/development/whiteboard-workstreams/W1_CANVAS.md；按总纲第 1 节加载本轮相关共享类型、fixture 与领域章节。
2. 确认这是独立 worktree，基线取任务指定、已包含 W0 共享契约的精确 v3-lab commit，分支名使用 codex/whiteboard-w1-canvas。如果看不到 W0 的共享类型和 fixture，停止实现并告诉我，不得自己另建一套 Card / Board / Anchor。
3. 确认没有带入其他工作树的未提交改动；不得 reset、stash、清理或覆盖。按总纲第 6 节给一次边界声明。

本轮目标是完成第一条真实画布闭环：
- 按引擎赛马文档对候选方案做可复现 spike，以 W0 的 WhiteboardSnapshot / WhiteboardOperation 为唯一产品真相；第三方节点、文档树和 ID 全部封装在 adapter 内。
- 至少实现：打开一个真实 Board、渲染现有 Card 预览、单选 / 框选 / 多选、拖动、缩放、层级、删除摆放、viewport 平移缩放、撤销重做、保存并在重启后恢复。
- 卡片内容不能复制进画布私有 JSON；同一 Card 可以出现多个 BoardItem；删除 BoardItem 不得删除 Card。
- 做 500 张卡片的基础性能验证，并覆盖空白板、损坏快照、失效 Card 引用和恢复失败状态。
- 如果必须新增引擎依赖或修改共享契约，只提交清楚的 W0 变更提案；可在隔离 spike 中验证，但不得直接把依赖或私有 schema 写入生产根配置。
- 保持全屏白板无常驻顶栏；视觉严格复用已冻结规范，不重新设计首页、卡片库、富文本或视频区。

明确不做：富文本内部编辑、普通链接抓取、视频 provider / 字幕、自动写入 User-truth。

完成标准：adapter / 操作 / 快照测试通过；真实桌面窗口验证核心操作与重启恢复；记录性能数据；更新 W1_CANVAS.md handoff，由集成主窗合入后统一更新项目状态与 DEVLOG。验证完成后提交当前临时分支，不 push、不 merge。最终回复给出提交号、选型证据、已完成闭环、测试 / 性能结果、契约变更提案和未完事项。
```

## 提示词 3：W2 卡片富文本编辑

```text
你现在负责 Here I am 白板并行开发的 W2「卡片富文本编辑」。这次指令明确授权你在隔离 worktree 的临时分支上实现、验证并提交本工作流，但不要 push、不要合并到 v3-lab。

开始前：
1. 读取根 AGENTS.md、完整白板总纲 docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md 及 docs/development/whiteboard-workstreams/W2_RICH_TEXT.md；按总纲第 1 节加载本轮相关共享类型、fixture 与领域章节。
2. 确认这是独立 worktree，基线取任务指定、已包含 W0 契约与 fixture 的精确 v3-lab commit，分支名使用 codex/whiteboard-w2-rich-text。缺少 W0 的 CardContract / RichTextDocument / AnchorContract 时停止，不得另建平行模型。
3. 先检查仓库已有编辑能力和依赖，保留用户改动；不得 reset、stash 或大范围重写。按总纲第 6 节给一次边界声明。

本轮目标是完成一张纯文字 Card 的真实编辑闭环：
- 以 W0 RichTextDocument 为可迁移、可序列化的稳定模型，实现正文编辑、标题 / 段落 / 列表 / 引用 / 链接、基础 inline marks、粘贴清洗、撤销重做、纯文本搜索投影和重启恢复。
- 中文输入法组合态必须正确；中文使用汇文明朝体，英文、数字和代码使用 Cascadia Code；混排和缺字状态要验证。
- 富文本只属于 Card 内容或 Source 派生内容，不得包含白板 x / y / size。媒体 Card 仍以媒体为主体，编辑器不能把所有媒体压成窄条。
- 图片 / 附件只保存稳定 asset reference，不把临时路径或大块二进制塞进文档 JSON。
- 批注归属保持独立：用户批注与林埃批注不能互相覆盖；需要定位原文时只使用共享 AnchorContract。
- 覆盖空文档、恶意粘贴 / 不安全链接、旧 schema 迁移、损坏文档降级和未保存退出提示。
- 如果需要新增编辑器依赖或修改共享 schema，先形成 W0 变更提案；不得静默改根依赖或领域语义。

明确不做：选择白板引擎、抓取网页、实现视频播放、自动提升为 User-truth。

完成标准：模型 / 迁移 / 粘贴清洗测试通过；真实 Flutter 桌面编辑、中文 IME、保存与重启恢复验收；更新 W2_RICH_TEXT.md handoff，由集成主窗合入后统一更新项目状态与 DEVLOG。验证完成后提交当前临时分支，不 push、不 merge。最终回复给出提交号、支持的文档能力、测试结果、依赖 / 契约提案和未完事项。
```

## 提示词 4：W3 普通链接抓取

```text
你现在负责 Here I am 白板并行开发的 W3「普通链接抓取与内容入库」。这次指令明确授权你在隔离 worktree 的临时分支上实现、验证并提交本工作流，但不要 push、不要合并到 v3-lab。

开始前：
1. 读取根 AGENTS.md、完整白板总纲 docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md 及 docs/development/whiteboard-workstreams/W3_LINK_INGESTION.md；按总纲第 1 节加载本轮相关共享类型、fixture 与领域章节。
2. 确认这是独立 worktree，基线取任务指定、已包含 W0 契约与 fixture 的精确 v3-lab commit，分支名使用 codex/whiteboard-w3-link-ingestion。缺少 IngestionResult / SourceContent / SourceVersion / CardContract 时停止，不得另建平行模型。
3. 检查现有网络服务和依赖；参考 kankan-shoucang 前先核对许可证、依赖和平台边界，不可直接整仓搬代码。按总纲第 6 节给一次边界声明。

本轮目标是完成一个普通公开网页链接从输入到可恢复 Card 的真实闭环：
- 实现 URL 规范化、重定向后的 canonical URL、provider / 内容类型识别、标题 / 描述 / Open Graph 图片和可用正文提取，以及 SourceContent + SourceVersion + IngestionResult 输出。
- 由应用层明确确认后创建或更新 Card；抓取器本身不得直接写白板布局或 User-truth。
- 同一 canonical URL 重复导入时复用 Source 或形成新 SourceVersion，不得静默复制多张 Card；保留原 URL、抓取时间、解析器版本、权限 / 失败原因。
- 安全边界必须覆盖 http/https scheme、localhost / 私网 / 元数据地址阻断、DNS / 重定向复查、超时、最大响应体、MIME 类型和重试上限。
- 用固定 HTML fixture 覆盖 Open Graph、正文、无标题、重定向、重复导入、超大响应、错误 MIME 和解析失败；再做一个合规的真实公开 URL smoke test，但测试不能依赖网络才可通过。
- 小红书普通笔记可以作为后续 provider 证据，但本轮不做视频下载、去水印、登录绕过或脆弱的私有接口依赖。
- 若需要新依赖、数据库迁移或共享字段，先提交 W0 变更提案，不得擅自修改共享层。

明确不做：视频下载 / 播放器、白板交互、富文本编辑器内部状态、自动写入 User-truth。

完成标准：canonicalization、安全请求、解析、去重和版本化测试通过；真实输入、失败提示、创建 Card 与重启恢复验收；更新 W3_LINK_INGESTION.md handoff，由集成主窗合入后统一更新项目状态与 DEVLOG。验证完成后提交当前临时分支，不 push、不 merge。最终回复给出提交号、支持范围、安全限制、测试结果、契约提案和未完事项。
```

## 提示词 5：W4 视频、字幕与时间标注

```text
你现在负责 Here I am 白板并行开发的 W4「视频、字幕与时间 Anchor」。这次指令明确授权你在隔离 worktree 的临时分支上实现、验证并提交本工作流，但不要 push、不要合并到 v3-lab。

开始前：
1. 读取根 AGENTS.md、完整白板总纲 docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md 及 docs/development/whiteboard-workstreams/W4_VIDEO.md；按总纲第 1 节加载本轮相关共享类型、fixture 与领域章节。
2. 确认这是独立 worktree，基线取任务指定、已包含 W0 契约与 fixture 的精确 v3-lab commit，分支名使用 codex/whiteboard-w4-video。缺少 PlayerAdapter / TimedTextTrack / AnchorContract / CardContract 时停止，不得另建视频专用 Card 身份或卡片库。
3. 先核对小红书、哔哩哔哩、YouTube 当前可合规使用的官方 / 公开播放器和字幕能力；不凭印象承诺。按总纲第 6 节声明边界和第一个 provider。

本轮目标是让一个真实 provider 完成“在线播放—字幕双向同步—时间标注—重启恢复”闭环：
- 先做三平台能力矩阵，再选择最有把握满足硬门槛的一个 provider 实现；平台能力不同必须通过 PlayerAdapter capability 明示，不在 UI 中假装一致。
- 硬门槛：真实在线播放；可读 current / duration；可 seek；字幕 cue 点击跳转；播放进度反向高亮字幕；创建点 / 区间 Anchor；保存独立 Annotation Card；重启后恢复并重新定位。
- 字幕优先平台 / 创作者提供，其次用户导入 SRT / VTT；仅在内容权利允许时做本机 ASR。没有可靠字幕时显示“需要字幕”，不得伪造完整支持。
- 视频始终是主体；字幕 / 标注使用可收起、可右侧或底部停靠的 ContextDock，默认约 65:35，比例可拖动并保存。不要新增全局永久右侧栏。
- 时间码和标注动作使用已冻结的 Palm 视觉，不恢复独立蓝色；遵守汇文明朝体 / Cascadia Code 规则。
- 覆盖无字幕、字幕延迟 / 损坏、provider 不支持 seek、网络失败、登录 / 权限受限、失效 source version 和 Anchor 重新解析状态。
- 不得绕过 DRM、登录、付费和平台限制，不得无授权下载或去水印，不把逐条播放事件写入主聊天或 User-truth。
- 如三个平台都无法合法满足完整硬门槛，不要伪装成功：完成 PlayerAdapter + 本地 fixture provider 的契约验证，明确列出平台阻塞证据和下一种合法方案。

明确不做：普通网页抓取、另建视频卡片库、修改白板引擎、自动写入 User-truth。

完成标准：adapter、字幕解析、双向同步、Anchor 创建 / 恢复测试通过；真实桌面窗口完成 provider 闭环或明确的合规阻塞证明；更新 W4_VIDEO.md handoff，由集成主窗合入后统一更新项目状态与 DEVLOG。验证完成后提交当前临时分支，不 push、不 merge。最终回复给出提交号、provider 能力矩阵、真实验收结果、受限状态、契约提案和未完事项。
```
