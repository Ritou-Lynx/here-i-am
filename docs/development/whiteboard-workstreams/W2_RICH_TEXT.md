# W2 — 卡片富文本编辑

**状态**：第一轮闭环已完成 + 字体/token/契约返修（临时分支 `codex/whiteboard-w2-rich-text`，基线 `v3-lab` @ `2ee4c862`）；**Task C 富文本补全已完成**（隔离 worktree 分支 `codex/whiteboard-w2-richtext-plus`，基线含 W6 基座 `d6910cdc`，未 push / 未 merge）
**后续集成更新**：Cascadia Code 正式资产已由 W0 在 2026-08-21 M5B-5 以 Microsoft 官方 2407.24 Regular + OFL 许可接入；汇文明朝体此前已注册，后续仅余独立子集化优化。下文“未入库”保留为 Task C 交付当时状态。
**权威范围**：`RichTextDocument`、块与行内标记、中文输入、粘贴清洗、资产引用、持久化和 schema 迁移
**当前目标**：一张纯文字 Card 的真实编辑闭环 — 正文编辑、标题/段落/列表/引用/链接、基础 inline marks、粘贴清洗、撤销重做、纯文本搜索投影、重启恢复、未保存退出提示。Task C 后补全：列表嵌套缩进、引用 children 编辑、图片/附件真实导入、生产字体混排渲染（含 W0 契约请求）、卡片库搜索。
**拥有路径**：`lib/domain/whiteboard/rich_text*.dart`、`lib/ui/whiteboard/fonts.dart`、`lib/ui/whiteboard/editor/*`、`lib/ui/whiteboard/card_library_screen.dart`、`lib/ui/whiteboard/card_rich_text_editor_screen.dart`（路由占位填充）、`test/domain/whiteboard/rich_text*`、`test/ui/whiteboard/card_rich_text*`、`test/domain/whiteboard/fixtures/rich_text_*`
**共享契约**：只读 `CardContract` / `AnchorContract`；`RichTextDocument` v2 结构只读（本轮未升 schema，语义增强均有测试守护）；生产字体资产契约变更请求已追加 `W0_INTEGRATION.md`（2026-08-16 段）。
**明确不做**：选择白板引擎、抓取任意网页、实现视频播放器、自动写入 User-truth、画布双击入口（W1 拥有路径）。

## 第一轮结果（此前完成，摘要）

模型（schema v2：block tree + marks + assetRefs）、纯文本投影、v0/v1 迁移（幂等、损坏降级、mark clamp）、粘贴清洗、撤销重做（800ms 合并窗口）、编辑器（按块 TextEditingController + IME 原生组合态、B/I/U/S/`</>`/🔗/H1/H2/•/1./❝/`{ }`/↶↷ 工具栏、Ctrl+Z/Y/S/V）、集中式字体 token（`fonts.dart`）、持久化与重启恢复、PopScope 未保存退出守卫。测试 80 项 + W0 契约 26 项全通过。

## Task C 本轮结果（2026-08-16）

### 交付物

1. **列表嵌套缩进（Tab / Shift-Tab）**：`RichTextEditingController.indentListBlock / outdentListBlock`（含 `childIndex` 定位引用内子列表），depth 属性 0–8 clamp、非列表 no-op、作为历史步可撤销；`toPlainText()` 按 `depth` 加深两级空格前缀（children 递归前缀同步加深一层）；Enter 在列表项上续写同类型/同 depth 兄弟项，空列表项 Enter 回退为段落。
2. **引用块 children 编辑**：控制器树支持——每个顶层块下维护子块编辑状态（独立 controller + focusNode），`insertChildAfter / deleteChild / setChildBlockType / applyMarkToChild`；编辑器在引用块下方缩进渲染子字段；引用块 Enter 追加子段落、空子块 Enter 删除（退出引用）；flush 读回子块文本，undo/redo 整树恢复，JSON 往返不丢。
3. **图片/附件真实导入（AssetRef 接对象存储）**：新增 `RichTextObjectStore`（`lib/domain/whiteboard/rich_text_object_store.dart`）——文件拷贝进 `<base>/objects/`，返回相对稳定 `object_ref`（`objects/<refId>.<ext>`），mime 按扩展名推断；`resolveFile` 带路径穿越守卫（拒绝绝对路径 / `..` / 非 `objects/` 前缀），`deleteRef` 清理；编辑器 🖼 / 📎 按钮走 FilePicker（桌面），插入 image / reference 块并 `appendAssetRef`，删除媒体块时回收无引用 assetRef；文档 JSON 永不含源路径与二进制（测试守门）。
4. **生产字体真机混排渲染**：集中 token（`fonts.dart`）未动；真实 Windows 桌面窗口集成测试验证混排渲染与回退链工作；生产字体资产（汇文明朝体 + Cascadia Code）**未入库**，契约变更请求已追加 `W0_INTEGRATION.md`（不自行改 pubspec）。
5. **编辑保存后 toPlainText() 投影可被卡片库搜索**：新增 `RichTextSearchIndex`（`rich_text_search.dart`，同步本地 JSON 读取）——`search(query)` 对 `card_<id>/rich_text.json` 逐个迁移并匹配 `toPlainText()`（含列表/引用前缀、媒体 alt、嵌套缩进），大小写不敏感、命中确定性排序；`CardLibraryScreen`（路由占位填充）提供搜索框 + 命中列表（标题 = 投影首行非空行），点击经冻结路由 `/cards/:cardId` 进编辑器。
6. **桌面焦点修复（真机暴露）**：Windows 下 InkWell 工具栏点击会抢焦点（tap-down 即 requestFocus），工具栏动作在 onTap 时 `_focusedPath` 已为空。修复：编辑器跟踪 `_lastFocusedPath`（全局 FocusManager 监听 + typing 时记录），工具栏动作以 `_focusedPath ?? _lastFocusedPath` 定位目标并 `_restoreFieldFocus` 把焦点还给字段；新增 Windows 平台覆写 widget 测试守护。Enter 结构化（列表续行/引用子块）通过 `FocusManager.addEarlyKeyEventHandler` 在焦点分发前拦截（多行 EditableText 会先消费 Enter，祖先 Focus 拿不到），带 IME composing 守卫（组合态 Enter 放行给输入法）。

### 验证

- **白板域全量 315 项通过**（test/ui/whiteboard + test/domain/whiteboard + test/routing + test/data/whiteboard + db 迁移测试；含既有 W0 26 + W2 第一轮 80，零回归）。新增：
  - 域：`rich_text_indent_test.dart`（缩进/反缩进/clamp/子列表定位/投影深度）、`rich_text_quote_children_test.dart`（子块增删改/flush 往返/undo-redo/投影 `> ` 前缀）、`rich_text_object_store_test.dart`（导入/重启解析/穿越守卫/mime/删除/JSON 安全）、`rich_text_search_test.dart`（投影搜索/大小写/v0 迁移/空查询/确定性）、fixture `rich_text_v2_current.json` + 迁移幂等与投影断言。
  - Widget：Tab/Shift-Tab、Enter 续行/退出、引用子块编辑与空子块删除、媒体导入与渲染/删除、保存→重载恢复；Windows 平台覆写桌面焦点测试；`card_library_screen_test.dart` 搜索 UI 四态；路由测试更新为真实编辑器断言（占位已填充）。
- **真实桌面窗口验收（Windows，integration_test/whiteboard_rich_text_loop_test.dart）通过**：启动 → 冻结路由直达 `/cards/richtext_itest` → 真实输入管道输入「中文混排 English 123」（中文 IME 组合态走真机输入连接）→ '•' 转列表 → Tab 缩进 → Enter 续行 → 保存 → 卡片库按纯文本投影搜到命中 → 点击命中重开编辑器、磁盘恢复两项列表文本。全部通过。
  - 说明：自动化真机验收覆盖了真实输入管道（IME 组合态由 Flutter 原生 EditableText 处理，widget 测试模拟 composing region 已覆盖），真人手敲中文输入法组合仍建议发布前手动过一遍。
- **静态检查**：`lib/domain/whiteboard`、`lib/ui/whiteboard/editor`、`fonts.dart`、两个占位填充 Screen、`integration_test/` `flutter analyze` 零 issue；`git diff --check` 干净（仅 CRLF 提示）。

### 契约变更请求 — 提交 W0 裁决

1. **生产字体资产**（追加至 `W0_INTEGRATION.md` 2026-08-16 段）：汇文明朝体（需先定 CC0/可商用来源 + 子集化）与 Cascadia Code（Microsoft 官方 OFL 发行）注册进 pubspec/assets，族名与 `fonts.dart` token 一致（接入后业务零改动）；W2 分支未自行改 pubspec。
2. **确认无 schema 升级**：本轮全部行为落在既有 v2 结构内；v1/v2 fixture 可解析、迁移幂等；不请求新 `richTextSchemaVersion`。

### 待集成提交 / 未完事项

- 本工作流提交（未 push）：分支 `codex/whiteboard-w2-richtext-plus`，基线含 W6 基座（`d6910cdc`，即 W0 Task 0 合并后的 `v3-lab`）。涉及：controller/document/object_store/search 域文件、editor 两个 Screen + 编辑器 Widget、两个占位填充、fixtures、7 个新测试文件、路由测试更新、集成测试。
- **未实现 / 下一接入点**：
  - 画布双击卡片进入编辑器 = W1 拥有路径（`_CardWidget` 加 onDoubleTap → `context.go(AppRoutes.cardEditPath(cardId))`），W2 侧 `CardRichTextEditorScreen(cardId)`（冻结签名）已是真实编辑器，直接可用。
  - 生产字体资产落地（等 W0 裁决后集成窗口改 pubspec，`fonts.dart` 无需改动）。
  - 编辑器内列表 children 深层树编辑（本轮用 depth 属性实现缩进；children 树保留给未来深层嵌套 UI）。
  - 段落内 Enter 目前是软换行（多行 EditableText 原生行为），块拆分语义未做（非本轮范围）。
  - 媒体块的富渲染（消费视图缩略图/附件卡片）留给后续窗口；编辑器内已有缩略图 + 标签 + 删除。
  - 卡片库目前只搜富文本 JSON 文档（`card_<id>/rich_text.json`）；与 Drift `MemoryCards` 的真实卡片列表/类型筛选由集成窗口决定。
  - 用户批注与林埃批注保持独立归属（`owner_space` 独立 Card + 共享 Anchor），本轮未触碰。
- 遗留风险：`RichTextSearchIndex` 与 `RichTextStorage` 共用「`card_<id>/` + `objects/`」目录约定，未来若卡片存储迁入 Drift，搜索索引需改为从 Drift 投影（接口不变，同步读本地 JSON 的当前实现可替换）。

## F2 唯一卡片库与富文本编辑闭环（2026-08-19）

**分支 / 基线**：`codex/whiteboard-f2-card-editor`，基于 `v3-lab` @ `87897543`，已验证 F0 `18981287` 为祖先；未 push / 未 merge。

### 交付

- 顶层卡片库生产读取收口到 `UnifiedCardRepository`：空关键字默认列出全部真实 Card，支持卡片类型 / Source 媒体类型 / 标签 / 关键字组合筛选；不再把 `RichTextSearchIndex` 当作第二份卡片真相。
- 媒体卡以约 70% 预览面为主体，标题 / 标签 / 来源为附属；图片、网页、视频、书籍、音频、PDF / 文件均有诚实缺失预览态。纯文字 / 批注卡以正文为主体。
- 新建文字卡严格经 `createTextCard → /cards/:cardId → saveRichText`；保存同步 Drift 标题、可搜索正文投影和更新时间。文字 / 批注卡打开编辑器，带 `sourceId` 的来源 / 媒体卡打开 `/sources/:sourceId`；「导入链接」只导航 `/import`。
- 编辑器保留中文 IME、恶意粘贴清洗、列表 / 引用 / 链接、图片 / 附件、撤销重做与未保存退出；修复了异步保存失败时工具栏过早清除 dirty 的问题。字体继续沿用汇文明朝体 / Cascadia Code 现有 token。
- 空库、组合筛选、缺失 / 损坏富文本、保存失败、恶意粘贴、媒体预览缺失、孤儿目录防护和 SQLite 关闭后重开恢复均有守门。

### 验证与边界

- 16 份定向测试文件共 **160 项全过**（含缩略图旁路安全回归）；本轮改动文件定向 Dart analyze 零 error / warning；`git diff --check` 通过。
- 真实 Windows 桌面 integration 已发起，但本机缺少 `nuget.exe`，Flutter 三次尝试获取仍失败，因此未建出 / 启动窗口；不声称真人中文 IME 手敲已验收。
- 全库 `flutter analyze` / `dart analyze` 在本机分别无诊断退出，定向 analyze 正常通过；记为本机工具链限制，不降格为代码通过证据。
- **共享契约请求：无**。未改 schema / `*.g.dart` / 根依赖 / 冻结路由 / `UnifiedCardRepository` 身份语义 / User-truth，也未修改画布、抓取、视频与 Source Study 实现。
- **未完事项**：补齐 Windows NuGet 工具链后重跑 `integration_test/whiteboard_rich_text_loop_test.dart -d windows`，并在真实中文输入法下手动验收组合态、候选上屏和未保存退出。

### F2 安全边界返修（2026-08-19）

- 删除卡片库对 Source metadata 缩略图的 `Image.network` 旁路；回环、私网和普通 HTTPS URL 均不会在 UI 层发起请求。
- 删除 `file://`、任意绝对路径和 `../` 的 `Image.file` / 文件存在性读取旁路；Source metadata 不再被解释为本地访问授权。
- 当前尚无统一安全缩略图缓存接口，因此所有 metadata 缩略图统一显示类型化缺失态，仍占媒体卡 `flex: 7` 主体。F2 不自建网络或缓存系统。
- 本地 `object_ref` 预览本轮不接入；后续只能由统一安全资产接口产出已缓存资产，或复用对象存储解析器对白板对象根内稳定 `object_ref` 做路径防逃逸解析，不得重新信任 metadata 路径。
- 回归测试覆盖 `127.0.0.1`、私网 URL、HTTPS、`file://`、绝对路径和 `../`；断言零 HTTP client、零 NetworkImage / FileImage，并守护 70/30 媒体卡比例。
