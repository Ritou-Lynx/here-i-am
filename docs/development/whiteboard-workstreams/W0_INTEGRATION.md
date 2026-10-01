# W0 — 共享契约与集成

**状态**：共享契约第一阶段与 Whiteboard Desktop UI-0 M0–M4 均已集成到 `v3-lab`；`cfe75ad` 已同步远端，M5B-1 导航返修、M5B-2 三视口 Windows 视觉验收、M5B-3 真人中文 IME、M5B-4 统一安全缩略图、M5B-5 Cascadia Code 正式资产与 M5B-6 引用感知缓存回收于 2026-08-21 本地完成、未 push
**权威范围**：共享领域类型、JSON fixture、跨模块契约测试、数据库迁移、依赖升级与最终集成
**当前目标**：维持 F0–F4 与统一身份契约，在唯一 `v3-lab` 上收口各 UI-0 隔离工作流、跨流冲突和平台路由边界。
**拥有路径**：共享契约、跨模块测试、最终集成与共享路由边界；功能工作流的页面内部实现仍归对应工作流。
**共享契约**：`CardContract`、`SourceContent`、`SourceVersion`、`Board`、`BoardItem`、`BoardGroup`、`GroupMember`、`BoardEdge`、`WhiteboardSnapshot`、`WhiteboardOperation`、`IngestionResult`、`RichTextDocument`、`PlayerAdapter`、`TimedTextTrack`、`AnchorContract`。
**明确不做**：第一阶段不做生产 UI、不接第三方引擎、不做数据库迁移、不实现具体抓取器或播放器。

## UI-0 W0 集成收口（2026-08-20）

- 远端校验因本机网络连接被重置而无法完成；用户明确授权以本地干净 `v3-lab` @ `fbb1fd3` 继续。该基线包含功能锚点 `a0e28893`，开工时没有未提交的跟踪文件。
- M2A 已作为 `381f938` + `14a3fbd` 集成；M2B 已作为 `99a4819` + `3f77add` 集成；M3 已作为 `89d462d` + `13542fc` 集成；M4 已作为 `2577b0d` 集成。M0 `88a6b5b` 与 M1 `cbb1308` 在本轮前已位于主线。
- M3 与 M2A 对 `BoardTargetPicker` 的重叠采用语义合并：保留最近 5 张 / 搜索全部 / 新建白板、外部持久化回调和全流程 single-flight，同时让画布弹层消费 M0 Desktop token；没有复制 Card、Board 或数据源。
- 六条冻结路由及 `boardId` / `cardId` / `sourceId` 参数保持不变，并由 W0 统一声明为桌面专属。Android / iOS 不构建 Lieflat Palm 业务页面，统一显示 Spring Rain 不可用面并可返回首页；普通非白板路由仍保持移动端透传。
- 集成未修改 Drift schema、迁移、Repository、domain、Card / Source / BoardItem / Anchor / Snapshot / PlayerAdapter 身份或语义，也未引入 HTML mock、localStorage 或第二套页面数据源。

### 集成验收

- Desktop、白板 UI、画布、数据、领域与路由统一集合：**628/628**。
- 六条桌面专属路由及原桌面路由回归：**11/11**；精确静态检查覆盖 33 个改动 Dart 文件，零 issue。
- 关键修复守门：**3/3**；Windows Debug 构建成功。
- Windows 画布真实窗口：悬浮入口、保存、退出、重开恢复通过；500 卡 91 帧，平均 build 22.899ms、raster 4.679ms。
- Windows 来源 / 视频真实产品链：WebView2 + YouTube 预览、播放、字幕、标注和重启恢复 **1/1**。

### 保留的后续项

- 统一安全缩略图已在 M5B-4 完成；UI 仍不得直连 metadata URL、本地绝对路径或未经完整性校验的 `object_ref`。
- UI-0 M0–M4 收口点 `cfe75ad` 已同步 `origin/v3-lab`；后续返修仍按每轮交接结果单独决定是否 push。

## UI-0 M5A 审计与 M5B-1 导航返修（2026-08-21）

- M5A 只读审计确认无 P0、无 F0–F4 / 统一身份 / 桌面专属路由回归；定位两个返回链 P1 和一个侧栏活动上下文 P2。
- `/cards → /import` 现在有来源栈时原路 `pop`，直接深链时回唯一卡片库，不再固定跳首页丢失筛选与滚动位置。
- `/cards/:cardId` 的加载、错误和真实编辑态现在共用生产退出回调：先执行未保存确认，取消停留，保存失败不放行；确认退出后有栈 `pop`、无栈回卡片库，不再弹空 GoRouter 最后一页。
- `/import` 在普通桌面壳中保持“卡片库”侧栏活动态；冻结路径、参数和路由表均未改变。
- 返修先补红测再实现：路由 14/14、导入与共享壳 23/23、富文本与未保存保护 39/39，共 **76/76**；7 个目标精确 analyze 零问题，关键修复守门 3/3，`git diff --check` 通过。
- 该阶段之后由 M5B-2 补齐三固定视口；真人中文 IME 与 Cascadia Code 正式资产仍保持独立批次，不与导航返修混合。

## UI-0 M5B-2 固定视口 Windows 视觉验收（2026-08-21）

- 新增 Windows 专用集成验收 `integration_test/whiteboard_ui0_fixed_viewport_windows_test.dart`：使用临时 Drift 数据库、统一 Repository、正式路由表和真实 `PersonaChatScreen`，不调用带后台服务的 `app.main()`，不写生产数据。
- 脚本不覆盖 `tester.view`，而是通过 Win32 `SetWindowPos` 调整 runner 内原生 Flutter 子窗口；本机 DPR 1.5 下实际逻辑视口逐一精确命中 **1440×900 / 1280×720 / 1024×768**。由于 150% 缩放下顶层框体会被物理屏幕最大宽度钳制，截图是完整 Windows engine 合成面，不包含操作系统标题栏，不把它误称为整窗外框截图。
- 每个视口覆盖首页默认、真实 primary 林埃展开态、白板索引、唯一卡片库、富文本编辑、链接导入、画布全部退场、画布导航展开、来源研读，共 **27 张**；截图输出到忽略的 `build/m5b2_screenshots/`，没有把验收数据或图片带入生产。
- 人工逐图复核：1440×900 与 1280×720 首页保持 4×2；1024×768 按契约折为 2 列纵向浏览；普通壳、沉浸壳、卡片网格、编辑器工具栏、导入列表、画布浮层、680–760px 阅读列和 400px 林埃覆盖面板均无裁切、重叠或皮肤渗漏。未发现需要修改生产 UI 的新缺陷。
- Windows 验收 **1/1**、脚本精确 analyze 零问题、关键修复守门 **3/3**、`git diff --check` 通过。启动视频插件在集成壳中诚实记录 `init()` 未实现，但不影响真实聊天输入栏出现和测试通过。
- M5B-3 已补齐真人中文 IME，M5B-4 已补齐统一安全缩略图，M5B-5 已补齐 Cascadia Code 正式资产；UI-0 M5 验收项全部闭环。

## UI-0 M5B-3 真人中文 IME 验收（2026-08-21）

- 新增可重复的 Windows 手工入口 `integration_test/whiteboard_manual_chinese_ime_windows.dart`：它以普通 Flutter 应用运行生产 `DesktopRouteWrapper` 与 `CardRichTextEditorScreen`，只连接系统临时目录中的 Drift 数据库和富文本对象目录，不读取或写入生产卡片。
- 真人使用 Windows 中文输入法完成候选选择、composing、中文与英文混合上屏；未出现丢字、重复、光标跳动或输入失焦。`Ctrl+S` 显示“已保存”；追加脏内容后点返回，选择“取消”仍停留原编辑页且内容保留；删除临时脏内容后再次保存。
- 点击“完成并校验”后，验收入口先卸载编辑器并关闭 SQLite，再以新的 `AppDatabase` / `UnifiedCardRepository` 打开同一临时文件；指定中文正文与 `CardDocumentState.available` 均恢复，应用输出 `MANUAL_CHINESE_IME_ACCEPTANCE=PASS` 后正常退出。
- 首版曾误用 `flutter test -d windows`，测试 binding 会截获真人鼠标事件并造成空白 / 不可交互体验；该入口已删除，正式保留版必须用 `flutter run -d windows -t integration_test/whiteboard_manual_chinese_ime_windows.dart`。
- 验收入口精确 analyze 零问题；启动前关键修复守门 **3/3**。未修改生产 UI、Repository、schema、路由签名、共享 token 或身份语义。

## UI-0 M5B-4 统一安全缩略图（2026-08-21）

- `SafeHttpClient` 新增不经过 UTF-8 的二进制响应面，继续复用既有 DNS pin、逐跳 SSRF / redirect、MIME、超时、重试和真实流式字节上限；没有新建第二个裸 HTTP 客户端。
- `SafeThumbnailResolver` 对输入执行 5 MiB、16 MP、8192 边长上限与 MIME / 实际 decoder 一致性检查；只取静态首帧，在独立 isolate 中完成方向烘焙、最大 1024px 缩放和 PNG 重编码，剥离原元数据后以 `objects/thumbnails/<sha256>.png` 原子落盘。缓存总量硬上限 128 MiB，损坏普通对象可从安全候选自愈；路径穿越、旧目录、哈希不符和 symlink 均不进入 UI。
- 不同候选的下载、解码、编码与写入默认全流程单并发；同一 SourceVersion / 候选 single-flight。卡片库只在 Grid / List builder 构建范围内排队，页面端单 worker；筛选换代清除旧队列，只允许一个已在途请求自然收束，不再遍历全库主动抓图。
- `UnifiedCardRepository` 是唯一解析入口：raw `og_image` / `thumbnail` 只作不可信候选，UI 只接收已验证的本地 `File`。可信 `thumbnail_ref`、version 与 candidate hash 仅写入原 Card 的 `presentation_json`，不改 `updatedAt`，不复制 Card / Source，不覆盖并发标题、正文或标签编辑；事务内同时复核当前 SourceVersion 与当前候选 hash，旧版本或同版本旧封面结果均不得回写、展示。
- 无 schema、迁移、依赖、生成文件、路由、domain、共享 token 或统一身份变更。安全网络、解析器、Repository、卡片库、链接导入和领域契约定向回归 **142/142**；精确 analyze 零问题；关键修复 **3/3**；Windows Debug 构建及三视口巡检 **1/1**。1440×900、1280×720、1024×768 三张卡片库截图均人工复核可信缩略图、70/30 比例与换列无溢出。
- 第一次复跑在第三次 Win32 resize 时 `GetFocus()` 瞬时返回 0；验收脚本改为缓存首次取得的 Flutter 子窗口句柄后复跑通过。截图仍只留在忽略的 `build/m5b2_screenshots/`，未进入生产资产。
- 128 MiB 引用感知孤儿回收已由 M5B-6 闭环；本阶段保留的行为是“活跃引用永不因年龄淘汰”，不是删除仍在使用对象的传统 LRU。

## UI-0 M5B-5 Cascadia Code 正式字体资产（2026-08-21）

- 只从 Microsoft 官方 `microsoft/cascadia-code` release `v2407.24` 获取 `ttf/static/CascadiaCode-Regular.ttf`；官方 ZIP SHA-256 为 `E67A68EE3386DB63F48B9054BD196EA752BC6A4EBB4DF35ADCE6733DA50C8474`，提取后的原始 TTF SHA-256 为 `C33EF522CDFEFF99907FB54F3E97152BB18BFB9B56EC2FEF4D4CEEC51C8974A4`。
- 只打包 598,060-byte 静态 Regular；不引入其它字重、Italic、Powerline、Nerd Font、OTF、WOFF2 或可变字体。Windows `PrivateFontCollection` 验证内部 family 为 `Cascadia Code`，与 `richTextCodeFamily` 及 pubspec 注册名精确一致；修正了旧注释示例缺少空格、实际不会命中 token 的问题。
- 同一官方 tag 的 SIL OFL 1.1 `LICENSE` 以 `CascadiaCode-OFL.txt` 随包分发；自动守门从 `rootBundle` 同时读取 TTF 与许可，固定文件长度、魔数、SHA-256、Reserved Font Name 和 pubspec family / asset 路径。
- 字体资产与富文本混排测试 **27/27**，精确 analyze 零问题，关键修复 **3/3**；真实 Windows 三视口 UI smoke **1/1**，1440×900 / 1280×720 / 1024×768 三张富文本截图人工复核无裁切或布局漂移，正式 Windows Debug 构建成功。产物 `FontManifest.json` 含 `Cascadia Code`，产物 TTF / OFL 与源码资产各自 SHA-256 完全一致。
- 未改业务页面、字体 token、手机 Spring Rain、schema、Repository、路由、domain、依赖或生成文件。汇文明朝体当前 24.9 MB 全量文件的子集化仍是独立包体优化，不影响本轮 Cascadia / UI-0 验收完成。

## UI-0 M5B-6 引用感知缩略图缓存回收（2026-08-21）

- `SafeThumbnailResolver` 仍以 128 MiB 为硬上限；仅在新对象将超限时启动清扫，按最旧优先删除严格 `sha256.png` 命名、超过 24 小时保护期且未被任何 Card / Source 投影引用的内容寻址对象。正常未超限写入不查询数据库、不触发删除。
- `UnifiedCardRepository` 从现有 `presentation_json` / `metadata_json` 汇总 `thumbnail_ref`，并包含软删除卡片，保证可恢复对象仍受保护；没有新增表、列、迁移或第二套引用数据源。生产 bootstrap 将这一只读引用提供器注入既有 resolver。
- 引用读取、JSON 解析或目录信任检查失败时一律 fail-closed：不删文件并让当前新缩略图诚实降级。清扫准备后、每次删除前再次读取引用集合；近期原子写入有 24 小时交接保护，避免 resolver 写盘与 Repository 投影之间的窗口被回收。
- 这不是会删除活跃缩略图的传统容量 LRU：被引用对象无论多旧都保留。若 128 MiB 全部由真实活跃引用占满，新缩略图仍安全缺图；未来只有确有产品需求时才讨论扩大配额或让用户显式清理。
- 新增活跃引用保护、最旧孤儿回收、投影交接保护、引用扫描失败与清扫期并发引用测试；解析器 + Repository 定向 **30/30**，安全网络 / 数据 / UI / 领域完整回归 **147/147**，5 个目标精确 analyze 零问题，关键修复 **3/3**，`git diff --check` 与 Windows Debug 构建通过。无 UI、字体、schema、路由、domain、依赖或生成文件变更。

## 结果 / 验证

- 26 项 Dart 测试全部通过（序列化往返、ID 引用完整性、删除语义、向后兼容、Anchor、IngestionResult、RichTextDocument、TimedTextTrack、PlayerCapability、WhiteboardOperation）。
- `dart analyze lib/domain/whiteboard/ test/domain/whiteboard/` 零 issue。
- 5 份版本化 JSON fixture：`normal_snapshot.json`、`empty_snapshot.json`、`orphaned_anchor_snapshot.json`、`old_schema_v0.json`、`invalid_dangling_refs.json`。
- 引擎适配器边界 ADR 已冻结，列出 W1–W4 可依赖的入口和接入方法。
- 共享类型零依赖：不 import MemexRouter、CardCache、Drift 或任何 UI 代码；仅使用 `dart:math`。

## 已交付文件

### 共享类型（`lib/domain/whiteboard/`）

| 文件 | 内容 |
|---|---|
| `whiteboard_contracts.dart` | barrel export |
| `whiteboard_ids.dart` | `StableId`、`tryStableId` |
| `source_content.dart` | `SourceContent`、`SourceVersion`、`SourceMediaType`、`OwnerSpace`、`SourceOrigin` |
| `card_contract.dart` | `CardContract`、`CardKind`、`CardCreatedBy` |
| `board.dart` | `Board`、`BoardItem`、`BoardGroup`、`GroupMember`、`BoardEdge`、`EdgeDirection`、`BoardViewport` |
| `anchor_contract.dart` | `AnchorContract`、`PositionKind`、`AnchorStatus` |
| `whiteboard_snapshot.dart` | `WhiteboardSnapshot`、`WhiteboardOperation`、`OperationKind`、`OperationActor` |
| `ingestion_result.dart` | `IngestionResult`、`IngestionStatus`、`VideoCapabilityLevel` |
| `rich_text_document.dart` | `RichTextDocument`、`RichTextBlock`、`RichTextMark`、`BlockType`、`MarkType` |
| `player_adapter.dart` | `PlayerAdapter`（抽象）、`PlayerCapability`、`TimedTextTrack`、`TimedTextCue`、`TimedTextSourceKind`、`TimedTextReliability`、`PlayerTimeEvent` |
| `snapshot_integrity.dart` | `validateSnapshotIntegrity()`、`loadSnapshot()`、`migrateFromV0()` |

### 测试与 fixture（`test/domain/whiteboard/`）

| 文件 | 内容 |
|---|---|
| `whiteboard_contracts_test.dart` | 26 项契约测试 |
| `fixtures/normal_snapshot.json` | 3 sources、4 versions、5 cards、2 boards、5 items、1 group、2 members、1 edge |
| `fixtures/empty_snapshot.json` | 空状态 |
| `fixtures/orphaned_anchor_snapshot.json` | 3 个 source version（v1→v2→v3），2 个不同归属批注卡 |
| `fixtures/old_schema_v0.json` | desktop MVP camelCase 格式（schema_version=0） |
| `fixtures/invalid_dangling_refs.json` | 空 ID、悬空 board/card/group/item/edge 引用 |

### 文档

| 文件 | 内容 |
|---|---|
| `docs/development/WHITEBOARD_ENGINE_ADAPTER_ADR.md` | 引擎适配器边界 ADR + W1–W4 接入方法 + 待决字段 |

## 集成记录

- 分支：`codex/whiteboard-w0-contracts`
- 基线：`v3-lab` @ `e3184a76`
- 提交号：`14e29328`
- `v3-lab` 已快进到该提交；工作树原有未提交内容已恢复且无冲突
- 尚未 push

## 未完事项

- `BoardAuthorization` 授权模型类型未实现（spine-contract 定义了字段）
- `AnnotationBinding` 批注绑定类型未实现
- `VideoSourceProfile` 视频源附加 profile 未实现
- `TranscriptTrack` / `TranscriptSegment` 完整分离模型未实现
- `AnchorContract.positionSpec` 各 position_kind 的结构化验证未实现
- `BoardOperation.inverse` 各 operation_kind 的标准 inverse schema 未实现
- `RichTextDocument` 完整 block tree 和迁移函数未实现（W2 范围）
- 数据库迁移不在第一阶段范围
- 引擎赛马 ADR（选型）不在第一阶段范围

## 契约变更请求入口

W1–W4 如需变更共享契约，在本文件追加「契约变更请求」段落，由 W0 集成工作流评审。

---

## 契约变更请求（W6 生产集成基座，2026-08-15）

### 1. Card 身份落地：MemoryCards + WhiteboardCardExtras

W6 按集成指令把 `CardContract` 身份落地为 **MemoryCards（`memory_scope='user_truth'`、`type='note'`）+ `WhiteboardCardExtras`**（card_kind / source_id / owner_space / body / tags / presentation / created_by / updated_at / deleted_at），不新增独立 whiteboard_cards 表（W3 曾建议独立表，以 W6 任务指示为准）。

- 影响：MemoryCards 的全局消费者（Memory Review、recall、Dreaming 候选）会看到白板卡。白板卡由用户显式创建（显式建 Card / 导入确认），符合 User-truth 写入契约；如需隔离，在查询服务层按 scope 过滤即可，**不涉及本迁移**。
- 兼容：`WhiteboardCardExtras.source_id` 软引用支持"来源→卡片"检索，不写 FK。

### 2. ViewModel 接线位置：路由加载壳持有 Drift store

W6 未改 `WhiteboardCanvasViewModel`（W1 拥有路径），生产默认 Drift 接线在 `WhiteboardCanvasRouteScreen`：构造 VM 并把 `onSaveRequested` 接到 `WhiteboardDriftStore`。W1 交互窗口无需为此改 VM。

### 3. 目标板 updated_at 归一化

保存时目标板行 `updated_at` 取 snapshot 的 `updatedAt`（文件 store 的"保存时点"语义）；非目标板保留实体值。Board 实体时间戳与 snapshot 时间戳一致时快照可字节级往返。

### 4. 白板快照视口落 Board 行

`WhiteboardSnapshot.viewport` 在 Drift 中存于目标板行（center_x / center_y / zoom 三列），与"视口是设备体验态"契约一致（不参与撤销/内容真相）。

---

## 契约变更请求（W2 富文本补全，2026-08-16）

### 1. 生产字体资产接入（pubspec + assets，由集成窗口统一处理）

> 2026-08-21 W0 处理结果：Cascadia Code 已在 M5B-5 以官方 2407.24 Regular + OFL 许可完成接入并验证；汇文明朝体此前已注册，后续只保留独立子集化优化。本契约请求不再阻塞。

W2 Task C 轮（`codex/whiteboard-w2-richtext-plus`）混排渲染已在真实桌面窗口通过（Windows 系统回退链），但**生产字体资产仍未入库**，本请求交集成窗口裁决并在恰当时机统一改 pubspec：

- **需求**：中文正文 → 汇文明朝体（族名 `HuiwenMincho`，已在 `lib/ui/whiteboard/fonts.dart` 固定）；英文、数字、时间码、代码 → Cascadia Code（Microsoft 官方发行，OFL 许可）。
- **约束**：来源与许可均可验证；不从未知字体站下载；不用霞鹜文楷（LXGW WenKai）等其它字体冒充；注册族名与 `fonts.dart` 现有 token 一致，接入后业务代码零改动。
- **建议路径**：Cascadia Code 用 GitHub microsoft/cascadia-code 官方 release；汇文明朝体先定 CC0/可商用来源 + 子集化（覆盖常用 CJK + 本项目字面量）再入 assets。
- **影响**：`pubspec.yaml` 新增两个字体族注册；`fonts.dart` 回退链不动；无 schema 变更、无迁移。W2 分支未自行改 pubspec。

### 2. 确认：RichTextDocument 本轮未升级 schema

列表 depth 缩进、引用 children 编辑、对象存储 AssetRef 闭环全部落在既有 v2 结构内；v1/v2 fixture 可解析、迁移幂等；不请求新 `richTextSchemaVersion`。

---

## 契约变更请求（W4 桌面播放器路线，2026-08-16）

### 1. 桌面播放器路线定稿：Web IFrame 为当前路线（B），native WebView（A）需要新依赖

- ADR 全文：`docs/development/WHITEBOARD_DESKTOP_PLAYER_ADR.md`。
- **W4 本轮实现路线 B（Flutter Web + 官方 YouTube IFrame API，零新依赖）**，真实桌面在线播放闭环已验收；`PlayerCapability` 结构与语义不动。
- **请 W0 评审的依赖提案（路线 A）**：为 Windows 原生内嵌播放器引入 `webview_windows`（或维护状态更佳的等价包，如 `desktop_webview_window`）。影响面：`pubspec.yaml` 新增依赖 + `windows/` 平台构建配置（WebView2 运行时）；W0 批准并合入后，W4 再实现 Windows 原生 adapter（UI / VM / 服务层与路线无关，可复用）。
- 本机环境观察（供 A 评审参考）：YouTube 流量需经系统代理；`api/timedtext` 端点对非浏览器 TLS 指纹返回 200 空 body（bot-block），native HTTP 拉字幕的实现策略需在 A 落地时一并评估（优先走浏览器内核内请求或复用 IFrame 上下文）。
- 兼容：A 落地不改变共享契约；C（外部播放器降级）维持为 Bilibili / 小红书现行 link-only 行为。
