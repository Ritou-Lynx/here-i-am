# 白板 UI 与脊柱数据契约 v0

> 状态：产品结构已确认，可作为 MVP 实施输入
> 日期：2026-08-14
> 上位产品决策：`docs/design/whiteboard-requirements.md`
> 视觉与验收规则：`docs/design/whiteboard-visual-rules.md`
> 实施与选型：`docs/development/WHITEBOARD_ENGINE_BAKEOFF_AND_VERTICAL_SLICE.md`
> 外部参考与许可审计：`docs/development/WHITEBOARD_EXTERNAL_REFERENCE_AUDIT.md`

## 1. 这份契约解决什么

这份文档固定白板 MVP 的两件事：

1. 用户看到的几个页面分别承担什么职责，如何切换；
2. 首页、卡片库、白板、阅读器以及未来图片 / 网页 / 视频视图共同依赖什么数据骨架。

它不是视觉稿，也不指定 Flutter、Web 或某个白板引擎。具体组件可以替换，但不得破坏本文的页面边界、稳定身份、归属、锚点和操作审计规则。

## 2. 不可破坏的产品原则

1. **首页不是白板**：首页是工作台摘要；进入白板后画布占满整个窗口。
2. **没有常驻顶栏和聊天侧栏**：导航、搜索、卡片库、工具与林埃对话均按需悬浮，可完全收起。
3. **只有一个卡片库**：书籍、图片、网页、批注等是筛选类型，不是多个“资料库”。
4. **白板是扁平组织层**：只有卡片、分组、连线和跨白板引用，不存在“白板卡片里再嵌白板”。
5. **卡片不等于消费视图**：白板上的书籍卡片只负责组织；点开后才进入阅读器。图片、网页、视频同理。
6. **源内容、卡片、白板摆放必须分离**：移动或删除一个白板中的摆放，不得改动源文件，也不得影响同一卡片在其他白板中的引用。
7. **锚点只描述位置，归属跟批注走**：同一个文字片段、图片区域或视频时段可以同时挂用户与林埃各自的批注。
8. **林埃操作先授权、会话内自由、全程可撤销**：授权范围外的写操作不得静默发生。
9. **手机与桌面同源，不是两套产品**：阅读、漫画、记忆、卡片、日程与任务使用同一份核心身份和数据；不同设备只改变呈现密度与输入方式，不复制内容实体。

## 3. 页面与导航契约

### 3.1 一级工作面

| 工作面 | 职责 | 明确不做 |
|---|---|---|
| 首页 | 显示观察面板、日程表、今日总结和继续工作入口 | 不承载自由画布，不伪装成一张白板 |
| 卡片库 | 全局搜索、筛选、预览、拖入白板 | 不再拆出“资料库”“收藏”等平行库 |
| 白板 | 空间组织、分组、连线、共同工作 | 不常驻导航栏、标签栏或聊天栏 |
| 阅读空间 | 统一呈现小说、漫画、文章与稍后阅读，续接手机阅读进度 | 不复制原件，不把每种媒介拆成孤岛 |
| 记忆空间 | 呈现 Memory Review、已确认 User-truth、修订与来源证据 | 不把任务日志或白板浏览历史自动当记忆 |
| 消费视图 | 阅读、观看、查看原件、生成锚点 | 不拥有白板布局，不各自发明锚点模型 |
| 任务中心 | 汇总后台任务状态、待决策数量和最近结果 | 不展示逐条运行日志 |
| 任务房间 | 围绕一个 `task_id` 保存目标、互动、授权、过程、决策和产物 | 不把完整过程倒灌关系主对话 |

### 3.2 首页

首页在一个桌面窗口高度内完成主要浏览，不依赖纵向长页面才能看懂全貌，但不再固定为三个大板块。它是可编排的模块网格：模块可以调整顺序和尺寸、折叠、暂时隐藏；首屏保持高信息密度，次要内容按需展开。

第一批模块：

- **林埃观察**：若干有真实数据的图表 + 林埃的一条判断。点击图表进入对应生活产物或相关白板。
- **日程与待办**：任务与建议活动共存。任务可完成；点击资料型任务直接进入已经准备好上下文的白板或消费视图。
- **今日总结**：当天回顾、值得确认的 User-truth 候选和继续对话入口。
- **继续工作**：最近白板与活跃任务，不与“首页本身”混成同一种卡片。
- **继续阅读**：小说、漫画、文章和视频的最近进度，点击续接同一内容与位置。
- **待整理卡片**：刚从手机分享、桌面拖入或任务产物保存的内容，等待分类或放入白板。
- **记忆回顾**：最近新增、待确认或发生修订的 Memory Card / User-truth。
- **后台任务**：运行中、等待决定、失败和最近完成的任务摘要。

健康、财务、兴趣等生活产物以后以同样的模块协议加入，不改首页壳。首页的图表值、任务状态与内容数量必须来自真实或明确标注的演示数据；不放没有后续行为的装饰按钮。图表优先采用“结论先行、几秒读懂”的小图，不把复杂关系网络硬缩进首页卡片。

### 3.3 卡片库

卡片库只有一个入口，默认显示“全部卡片”。可组合筛选：

- 类型：书籍、文字、图片、网页、视频、音频、文件、批注；
- 归属空间：用户、林埃、共同；
- 标签、来源、创建时间、最近使用；
- 已在当前白板 / 未在当前白板。

主要行为：搜索、预览、打开原件、拖入当前白板、批量放入、查看出现在哪些白板。卡片库本身不承担空间排版。

从独立卡片库触发“放入白板”时必须先选择目标：轻量 Popover 提供最近白板、全部白板搜索和“新建白板”；处于某张白板上下文时可直接“放入当前白板”，并保留切换目标。确认后只创建新的 `BoardItem`，不复制 Card。原型若暂时只能写入最近白板，文案必须如实标注，不能省略目标语义。

统一 Card 身份不要求统一缩略条。媒体 Card 以原媒体预览为主体，元信息只占底部附属区；纯文字 Card 以正文预览为主体。类型可以拥有不同纵横比和内部构图，但筛选、选择、拖入与打开语义一致。

### 3.4 白板

进入白板后：

- 画布占满窗口；`Esc` 或明确的返回动作回到来源工作面；
- 左侧悬浮入口负责导航与卡片库；画布工具根据选择状态浮现；
- 右下或用户可移动位置保留林埃悬浮球；
- 面板打开时覆盖在画布之上，关闭后不留下兜底侧栏；
- 白板记住独立 viewport（中心、缩放）与用户上次选择，但 viewport 不是内容真相。

MVP 必须支持：

- 卡片拖放、移动、缩放、框选、多选；
- 框选建组、组名、折叠 / 展开、整组移动、解组；
- 卡片间有向或无向连线、可选标签；
- 同一卡片在多张白板出现；
- 双链 / `[[keyword]]` / `@mention` 形成跨白板引用；
- 打开卡片进入对应消费视图，再原位返回白板；
- 撤销 / 重做，以及林埃操作的可识别审计记录。

不进入第一条纵切面的能力：手绘笔迹、复杂自动布局、多人实时协作、递归白板、完整 Office 兼容。

#### 3.4.1 工作面辅助坞

播放器、阅读器和卡片详情可以调用同一个 `ContextDock` 壳：默认停靠右侧并保持主内容约 65%、辅助坞约 35%，可折叠，也可切到底部；窄屏自动下移。桌面使用可拖动 splitter 调整左右宽度或上下高度，并保存各工作面最近比例。它只承载当前工作面的字幕、标注、目录、批注、详情或筛选，不成为全局永久侧栏。关闭后主工作面回收全部空间，不保留兜底矩形。

### 3.5 林埃悬浮对话

- 收起态只显示悬浮球及必要状态：空闲、处理中、等待决定、失败；
- 展开态是覆盖层，包含消息与输入框，保留轻量承载面，不追求完全无衬底的气泡镂空；
- 关系主对话只接收任务的发起、关键决定和结果摘要；
- 点击任务状态进入任务中心或具体任务房间；
- 当前页面、当前白板、当前选择可以作为临时环境上下文，但不会因此自动写入长期记忆。

### 3.6 任务产物展示

产物按“能否内嵌预览”路由，而不是全部塞进一种 Tab：

| 产物 | 默认呈现 |
|---|---|
| HTML / 小型 Web UI | 安全预览面，可在独立窗口打开 |
| 图片 / 音视频 | 媒体预览面，可放入卡片库或白板 |
| 文档 / PDF | 对应阅读视图 |
| Diff / 测试报告 / 日志 | 任务房间的结构化产物面板 |
| 外部工具专属状态 | 摘要 + 深链到工具；房间保留返回结果与引用 |

产物预览面可以像临时页签一样打开，但页签只是窗口管理方式，不是数据归属方式。产物始终属于 `task_id`，是否另存为卡片由用户明确选择。

### 3.7 跨端同源内容空间

桌面不是手机功能的镜像截图，而是同一内容域的宽屏工作面：

- 手机负责随身捕获、聊天、轻量阅读、提醒与快速确认；
- 桌面负责高密度浏览、并排阅读、白板组织、批量整理和深度任务；
- 两端共同引用同一个 `source_id / card_id / anchor_id / memory_id / task_id`；
- 手机读到漫画第 32 话、小说第 8 章或视频 12:30，桌面继续时恢复同一内容位置；
- 桌面在阅读器里生成的划线、批注和白板引用，手机端按能力显示，不另建副本。

独立空间并不意味着独立数据库。阅读空间、记忆空间、卡片库和白板都是同一脊柱的不同查询与操作面。任何内容可以从专属空间进入消费视图，也可以作为卡片出现在白板；专属空间本身不被塞进白板卡片。

### 3.8 在线视频采集与消费

在线视频统一走 `VideoResolver` provider 适配，不为每个平台建立一套卡片模型。第一批支持：

1. 小红书短视频；
2. 哔哩哔哩在线视频；
3. YouTube 在线视频。

统一链路：

```text
分享 / 粘贴链接
  → 识别 provider 与 canonical id
  → 解析公开元数据和可用播放方式
  → 建立 SourceContent + VideoSourceProfile
  → 进入卡片库“视频”筛选
  → 在线播放器消费
  → 时间段 Anchor + 双方批注
```

视频能力的主目标不是“把文件解析或下载下来”，而是把平台视频统一成可研究、可批注的在线内容。正式支持一个 provider 的硬门槛是：播放器能够读取当前位置与总时长、程序化跳转到稳定时间点；字幕轨带时间码；点击字幕会跳转播放器，播放进度也会反向高亮当前字幕；由播放器或字幕建立的点 / 时间段 Anchor 能跨重启恢复。

桌面研读 UI 固定为左右双面：左侧是 provider 允许的嵌入播放器，右侧是字幕时间线与已建标注。右侧 Palm 深绿时间码触发 `PlayerAdapter.seekTo(start_ms)`；每段旁的同色小方块创建草稿 Annotation Card，并预填 `source_id / source_version_id / start_ms / end_ms / transcript_segment_id`。保存后卡片留在同一字幕段下方并计入白板 / 卡片库，取消则不产生 Anchor。进入此视图时主导航默认收起为 0px，只留打开把手。

能力分三级，界面必须明确当前达到哪一级：

- **链接级**：保存规范链接、标题、作者、封面、平台身份；
- **研读播放级**：使用平台允许的嵌入播放器或在线播放地址观看，并同时具备双向时间轴跳转、带时间码字幕和稳定时间 Anchor；只有能达到这一层的平台实现才算正式支持；
- **本地化级**：仅当平台规则、内容授权与技术条件允许时保存媒体副本、转写文稿和离线索引。

字幕来源优先级固定为：平台官方 / 创作者提供的字幕 → 用户导入 SRT / VTT → 仅在媒体权利允许时生成 ASR 字幕。若没有合法可取得的字幕，也没有用户导入，内容仍可停留在链接级并标记“需要字幕”，不得以虚构字幕冒充研读播放级。

YouTube 默认使用“官方元数据 + 官方嵌入播放”，不下载、缓存或分离音视频；只有字幕可合法取得、用户导入，或用户有权让本机转写时，才进入研读播放级。哔哩哔哩默认使用官方外链播放器；直接媒体解析与离线保存不作为基础能力。小红书优先采用用户手动触发的单链接解析，匿名公开解析失败时明确失败，不静默借用登录态；是否启用已登录 WebView 作为显式授权的兼容路径，另做设置与风险说明。

## 4. 脊柱实体

所有跨设备实体使用全局稳定字符串 ID；本机整数只允许作为缓存索引。时间统一存 UTC，删除默认软删除或追加删除操作。

### 4.1 `SourceContent`：源内容

代表真正被阅读、观看或引用的原件。

| 字段 | 含义 |
|---|---|
| `source_id` | 稳定身份 |
| `media_type` | `text / book / pdf / image / web / video / audio / file` |
| `title` | 展示标题 |
| `owner_space` | `user / i / shared` |
| `origin` | 导入、分享、抓取、生成或外部连接来源 |
| `provider / canonical_id` | 外部平台与平台内稳定身份；本地原件可空 |
| `mime_type` | 原件格式 |
| `current_version_id` | 当前内容版本 |
| `content_hash` | 内容寻址与去重依据 |
| `object_ref` | 核心对象存储引用，不是某台设备的绝对路径 |
| `metadata_json` | 作者、封面、时长、章节等媒介元数据 |
| `created_at / updated_at / deleted_at` | 生命周期 |

`SourceVersion` 保存不可变版本：`version_id`、`source_id`、`content_hash`、`object_ref`、`created_at`、解析器版本。锚点必须指向具体版本，不能只指向“最新内容”。

在线视频额外挂 `VideoSourceProfile`：`source_id`、`provider`、`canonical_id`、`canonical_url`、`playback_mode`（embed / remote_stream / local_file）、`embed_url`、`duration_ms`、`thumbnail_ref`、`seek_capability`、`timeline_status`、`default_transcript_track_id`、`resolver_version`、`resolved_at`、`availability_status` 与 `rights_policy`。平台临时播放地址属于可刷新缓存，不作为 SourceContent 身份。

字幕与播放地址分离建模。`TranscriptTrack` 至少包含 `track_id`、`source_id`、`source_version_id`、`source_kind`（platform / creator / user_import / asr）、`language`、`format`、`segments_ref`、`track_version`、`generated_at` 与 `rights_policy`；每个 `TranscriptSegment` 至少包含 `segment_id`、`start_ms`、`end_ms`、`text`，可选 `speaker` 与 `confidence`。Anchor 指向稳定的 source / version / start_ms / end_ms，不指向会过期的 embed URL。

### 4.2 `Card`：统一组织单元

| 字段 | 含义 |
|---|---|
| `card_id` | 稳定身份 |
| `card_kind` | `source / note / annotation / task_artifact / reference` |
| `source_id` | 可空；源卡片指向原件 |
| `owner_space` | 卡片归属 |
| `title / body` | 卡片自身内容；源卡片的正文不复制原件全文 |
| `presentation_json` | 封面、摘要密度、颜色等展示偏好 |
| `created_by` | `user / i / system` |
| `created_at / updated_at / deleted_at` | 生命周期 |

卡片没有 `x / y / width / height`。这些属于具体白板里的摆放。

### 4.3 `Board`、`BoardItem`、`BoardGroup`、`BoardEdge`

`Board`：`board_id`、名称、归属空间、创建者、创建 / 更新时间、删除时间。

`BoardItem`：一张卡在某张白板上的一次出现。

- `item_id`、`board_id`、`card_id`；
- `x / y / width / height / rotation / z_index`；
- 展开状态、局部展示模式等 `view_state_json`。

同一 `card_id` 可以对应多个 `BoardItem`，甚至在同一白板出现多次；它们共享卡片内容，但拥有各自布局。

`BoardGroup`：`group_id`、`board_id`、名称、样式、折叠状态。成员关系由显式 `BoardGroupMember(group_id, item_id, order)` 保存，不能只靠“坐标刚好落在框里”推断。

`BoardEdge`：

- `edge_id`、`board_id`；
- `from_item_id / to_item_id`；
- `direction`、`semantic_type`、`label`、`style_json`；
- `created_by` 与生命周期字段。

跨白板关系不直接连两个画布坐标，而是连接 `card_id` 或创建 `reference` 卡片；打开时再定位目标白板与对应 `BoardItem`。

### 4.4 `Anchor`：无归属的位置

| 字段 | 含义 |
|---|---|
| `anchor_id` | 稳定身份 |
| `source_id / source_version_id` | 指向明确原件版本 |
| `position_kind` | `text_range / page_region / image_region / time_range / web_snapshot_range` |
| `position_spec_json` | 各消费视图填写的稳定位置描述 |
| `quote / prefix / suffix` | 重定位证据，可空 |
| `fingerprint` | 内容或局部指纹 |
| `status` | `exact / reanchored / orphaned` |
| `created_at` | 创建时间 |

`Anchor` 不含 `owner_space`、作者或批注正文。

位置规范最低要求：

- 文本：章节稳定 ID + Unicode 字符区间 + quote / 前后文 + 版本；
- PDF：页稳定 ID + 文本区间或归一化矩形；
- 图片：原图版本 + 0–1 归一化矩形 / 多边形；
- 视频 / 音频：毫秒时间段 + 前后内容指纹；
- 网页：不可变快照版本 + 正文节点路径 / 字符区间 + quote 上下文。

### 4.5 `AnnotationBinding`：批注卡挂到锚点

批注本身是一张 `card_kind=annotation` 的 `Card`。绑定表只表达“这张批注卡指向哪里”：

- `binding_id`、`annotation_card_id`、`anchor_id`；
- `annotation_type`、`sentiment`、`intensity` 等轻量元数据；
- 创建 / 删除时间。

这样同一个 `anchor_id` 可挂多张不同归属的批注卡。纯划线也建一张空正文批注卡，但不得自动当作用户观点或 User-truth。

### 4.6 操作、授权与撤销

`BoardOperation` 使用追加式审计：

- `operation_id`、`board_id`、`actor`、`operation_kind`；
- `target_ids`、`payload_json`、`inverse_json`；
- `authorization_id`（用户直接操作可空）；
- `undo_of`、`created_at`。

`BoardAuthorization` 保存一次性或有期限授权：

- `authorization_id`、`board_id`、`grantee=i`；
- 允许的操作、目标范围、开始 / 到期时间；
- `one_shot / session / long_lived`；
- 撤销时间。

林埃的每次写操作必须落到有效授权，林埃空间内依据空间规则可使用预设授权；所有操作仍可撤销。

## 5. 任务房间只与白板脊柱相接，不混入其中

任务房间另有稳定 `task_id`，继续沿用并包住现有 Dev Room 的 project / session / run / event / approval / artifact 数据。第一版适配规则：

- 一个 `task_id` 可关联多个执行 session 与 run；
- `DevAgentSession.id` 不能再承担产品层 task 身份；
- `DevAgentArtifact` 通过引用加入任务房间，用户明确“收入卡片库”后才创建 `Card`；
- 任务房间可引用 `board_id / card_id / source_id`，白板实体不反向保存完整运行日志；
- 任务结晶保存 `task_id`、目标、关键决定、纠正、依据、结果与来源引用；注入主聊天、提升 Project Memory、提升 User-truth 是三个独立动作。

具体 task schema 等 coding 界面定稿后单独落文档，不阻塞白板纵切面。

## 6. 与现有实现的迁移关系

### 6.1 小说划线批注

现有 `BookAnnotations` 同时保存书籍位置、quote、上下文、样式与 note。迁移时：

1. `bookId + 章节内容 fingerprint` 映射到 `SourceContent / SourceVersion`；
2. 字符区间、quote、prefix、suffix 映射到 `Anchor`；
3. 样式与 note 映射到用户归属的 annotation `Card`；
4. `AnnotationBinding` 连接二者；
5. 迁移完成前保持双读兼容，不立即删除旧表。

现有规则继续有效：纯划线不自动进入 Memory V3，显式提升才进入 User-truth。

### 6.2 Dev Room

现有 `DevProjects / DevAgentSessions / DevAgentRuns / DevAgentEvents / DevAgentApprovals / DevAgentArtifacts` 继续负责执行过程。新增 task 外壳时采用适配和迁移，不把这些表改造成白板表，也不把运行日志复制为卡片正文。

## 7. 跨设备与权威边界

- 核心保存权威实体与追加式 change events；客户端保存按需缓存和 viewport 等设备体验状态。
- 原件二进制进入按内容哈希寻址的对象存储；数据库只保存 `object_ref`。
- 缩略图、全文索引、embedding、自动布局结果是可重建投影，不是同步真相。
- 白板内容操作按稳定 ID 同步；拖动中的每一帧不入 change feed，只提交节流后的最终布局操作。
- 冲突不能依赖设备时钟裁决。首版对不同实体合并；同一实体的并发编辑以服务端顺序 + 可审计修订处理。
- viewport、面板开合、鼠标悬停等设备状态不跨设备强同步。

## 8. 领域操作契约

具体 HTTP / IPC 形式以后决定，领域层至少暴露：

- `createBoard / renameBoard / archiveBoard`
- `searchCards(filters, query)`
- `importSource / createNoteCard / createReferenceCard`
- `placeCard / moveItems / resizeItem / removeBoardItem`
- `groupItems / updateGroup / ungroupItems`
- `connectItems / updateEdge / removeEdge`
- `openSource / createAnchor / createAnnotation`
- `resolveExternalUrl / refreshVideoPlayback / openVideoAtAnchor`
- `grantBoardAuthorization / revokeBoardAuthorization`
- `applyIOperations / undoOperation / redoOperation`
- `listCardAppearances / openCrossBoardReference`
- `saveTaskArtifactAsCard`

UI 不得绕过这些领域操作直接修改引擎私有 JSON 并把它当成唯一事实。

## 9. MVP 契约验收

达到以下条件才算白板脊柱成立：

1. 同一书籍原件只存一份，可作为同一卡片出现在两张白板；
2. 删除其中一个 `BoardItem` 不删除卡片或原件；
3. 用户与林埃能在同一文字锚点留下两张独立归属的批注；
4. 原件升级后锚点明确显示 exact、reanchored 或 orphaned，不静默漂移；
5. 白板重开后卡片、分组、连线、层级和 viewport 正确恢复；
6. 林埃未获授权不能改用户白板，获本次授权后可连续整理并一键撤销；
7. 卡片库只存在一套，类型筛选不会产生重复原件；
8. 任务产物不会自动污染关系主聊天或长期记忆。
9. 同一阅读或视频内容可在手机与桌面续接，不生成第二份源内容或批注。
10. 三类视频链接均先形成稳定 provider 身份；解析或播放失败不会丢失原链接，也不会越权切换到登录态或下载模式。

## 10. 暂不阻塞 MVP 的开放项

- 白板渲染引擎最终选择；
- 文本源改版后的自动重定位阈值与人工修复界面；
- 复杂组嵌套是否永远禁止，还是后续只允许一层视觉组；
- coding 任务房间的最终页面细节和多工具切换体验；
- 多人协作、公开分享与服务端部署形态。

这些问题可以继续试验，但不得推翻第 2 节原则或让各消费视图各自复制一套数据模型。
