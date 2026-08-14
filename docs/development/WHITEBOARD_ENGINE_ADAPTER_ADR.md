# ADR: 白板引擎适配器边界

> 状态：已冻结（W0 第一阶段）
> 日期：2026-08-15
> 决策者：W0 集成工作流
> 上位文档：`WHITEBOARD_ENGINE_BAKEOFF_AND_VERTICAL_SLICE.md`、`whiteboard-ui-spine-contract.md`

## 背景

白板桌面工作台需要一个画布引擎来处理拖放、缩放、框选、分组、连线、撤销重做和 500 卡性能。候选引擎有三类（AFFiNE 可复用部分、BlockSuite、tldraw + 自有编辑器），每种的内部数据模型不同。

如果让产品领域模型（Card / Source / Anchor / Board）直接服从某个引擎的私有文档树或 shape schema，会导致：

1. 卡片内容与白板布局耦合，无法分离；
2. 引擎升级或替换时产品数据被锁死；
3. 同一卡片无法跨白板出现而不复制内容；
4. 快照往返不保证无损，引擎私有 ID 污染产品身份。

## 决策

在产品领域模型与第三方白板引擎之间冻结一层 **适配器边界**：

```
产品领域 (WhiteboardSnapshot / Card / Source / Anchor / Board / ...)
    ↑                          ↑
  load(snapshot)           exportSnapshot()
    ↑                          ↑
    |     onOperation(op)      |
    | ←────────────────────────|
    |                          |
  引擎适配层 (EngineAdapter)     |
    ↓                          ↓
  第三方引擎 (tldraw / BlockSuite / AFFiNE 内部节点 / shape tree)
```

### 适配器必须实现的接口

每个候选引擎通过适配器层接触统一快照：

| 方法 | 职责 |
|---|---|
| `load(WhiteboardSnapshot)` | 从统一快照渲染画布 |
| `exportSnapshot()` | 导出回统一 WhiteboardSnapshot |
| `onOperation(WhiteboardOperation)` | 上报 place / move / resize / remove / group / ungroup / edge / viewport / undo |
| `setReadonly(bool)` | 支持只读检查 |
| `focusItem(itemId)` | 从搜索或消费视图返回时定位 |

### 不可破坏的边界规则

1. **引擎私有节点 ID 只能存在于适配器映射或可丢弃的 view state 中**，不能替代 `card_id / item_id / group_id / edge_id`。
2. **卡片内容不写进画布 JSON**。画布只保存 `BoardItem`（布局 + 局部视图状态）。
3. **删除 BoardItem 不删除 Card 或 Source**。适配器的 `exportSnapshot()` 必须保证卡片身份不变。
4. **快照往返无损**：`load(snapshot) → exportSnapshot()` 的结果与原 snapshot 在结构上等价（cards / boardItems / groups / groupMembers / edges / viewport 不丢失）。
5. **引擎升级不改变产品身份**。产品 `card_id / source_id / anchor_id` 是稳定字符串，与引擎版本无关。

## W1–W4 可依赖的入口

以下入口在 W0 第一阶段已冻结，后续工作流可直接消费：

| 入口 | 类型 | 路径 | 可用状态 |
|---|---|---|---|
| `WhiteboardSnapshot` | 数据类型 | `lib/domain/whiteboard/whiteboard_snapshot.dart` | ✅ 可序列化、可往返、可迁移 |
| `CardContract` | 数据类型 | `lib/domain/whiteboard/card_contract.dart` | ✅ 含 card_id / card_kind / source_id / tags / presentation |
| `SourceContent` / `SourceVersion` | 数据类型 | `lib/domain/whiteboard/source_content.dart` | ✅ 含 version_id / content_hash / object_ref |
| `Board` / `BoardItem` / `BoardGroup` / `GroupMember` / `BoardEdge` | 数据类型 | `lib/domain/whiteboard/board.dart` | ✅ 布局与内容分离 |
| `AnchorContract` | 数据类型 | `lib/domain/whiteboard/anchor_contract.dart` | ✅ 绑定 source_id + source_version_id |
| `WhiteboardOperation` | 数据类型 | `lib/domain/whiteboard/whiteboard_snapshot.dart` | ✅ 追加式审计日志 |
| `IngestionResult` | 数据类型 | `lib/domain/whiteboard/ingestion_result.dart` | ✅ canonical_url / provider / capability / status |
| `RichTextDocument` | 数据类型 | `lib/domain/whiteboard/rich_text_document.dart` | ✅ 最小外壳（block tree + marks + 纯文本投影） |
| `TimedTextTrack` / `TimedTextCue` | 数据类型 | `lib/domain/whiteboard/player_adapter.dart` | ✅ track_id / language / cues / reliability |
| `PlayerAdapter` | 抽象接口 | `lib/domain/whiteboard/player_adapter.dart` | ✅ load / play / pause / seek / timeEvents / capability |
| `PlayerCapability` | 能力声明 | `lib/domain/whiteboard/player_adapter.dart` | ✅ isPlaybackStudyCapable 硬门槛 |
| `validateSnapshotIntegrity()` | 验证工具 | `lib/domain/whiteboard/snapshot_integrity.dart` | ✅ 引用完整性 + 空 ID 检查 |
| `loadSnapshot()` / `migrateFromV0()` | 迁移工具 | `lib/domain/whiteboard/snapshot_integrity.dart` | ✅ schema_version 0 → 1 |
| JSON fixture | 测试数据 | `test/domain/whiteboard/fixtures/` | ✅ normal / empty / orphaned / old_schema / invalid |
| 契约测试 | 测试 | `test/domain/whiteboard/whiteboard_contracts_test.dart` | ✅ 26 tests passing |

### W1 接入方法

1. 创建引擎适配器实现 `load / exportSnapshot / onOperation / setReadonly / focusItem`；
2. 引擎私有节点 ID 保存在适配器内部的 `Map<String, String>` 映射（引擎 ID ↔ 产品 item_id）；
3. 使用 `test/domain/whiteboard/fixtures/normal_snapshot.json` 作为统一测试画板；
4. 快照往返用 `validateSnapshotIntegrity()` 检查；
5. 不修改共享类型——需要变更时提交「契约变更请求」到 W0 handoff。

### W2 接入方法

1. `RichTextDocument` 是最小外壳，W2 在此基础上实现完整 block tree、marks、粘贴清洗、IME 和迁移；
2. 批注卡是 `card_kind=annotation` 的 `CardContract`，通过 `AnchorContract` 绑定位置；
3. 用户批注与林埃批注是独立 Card（不同 `owner_space`），共享同一 `anchor_id`；
4. 修改 `RichTextDocument` schema 时增加 `schema_version` 和迁移函数。

### W3 接入方法

1. 抓取器只输出 `IngestionResult`，应用层决定是否建 Card；
2. `IngestionResult.canonicalUrl` 是去重依据，同一 canonical URL 的重复导入优先形成新 `SourceVersion`；
3. `IngestionResult.status` 覆盖 ok / partial / failed / needs_auth / unsupported；
4. 修改 `IngestionResult` 字段时提交「契约变更请求」。

### W4 接入方法

1. 每个 provider 实现一个 `PlayerAdapter` 子类，声明 `PlayerCapability`；
2. 只有 `PlayerCapability.isPlaybackStudyCapable == true` 时才算「正式支持」；
3. `TimedTextTrack.reliability == unavailable` 时 UI 必须显示「需要字幕」；
4. Anchor 指向 `source_id + source_version_id + start_ms + end_ms`，不指向 embed URL；
5. `PlayerAdapter.timeEvents` 驱动字幕反向高亮。

## 仍待决定的字段

以下字段在 W0 第一阶段**未填满**，留待对应工作流明确后由 W0 集成更新：

| 字段 / 能力 | 待决项 | 归属工作流 |
|---|---|---|
| `RichTextDocument` block tree 完整类型 | 当前只有 8 种 BlockType 最小枚举，缺 block attrs、nested children 完整规则、asset ref 格式 | W2 |
| `RichTextDocument` 迁移函数 | 只有 schema_version 常量，缺旧版 → 新版的迁移实现 | W2 |
| `AnchorContract.positionSpec` 各 position_kind 的标准 schema | 当前是 `Map<String, dynamic>`，缺 text_range / image_region / time_range / web_snapshot_range 的结构化验证 | W2 / W4 |
| `PlayerAdapter` 具体实现 | 抽象接口已冻结，缺 bilibili / youtube / xiaohongshu 具体实现 | W4 |
| `TimedTextTrack.segmentsRef` 存储格式 | 当前是 `String?`，缺 segments 对象存储与 cue 列表的引用关系 | W4 |
| `BoardOperation.inverse` 逆操作格式 | 当前是 `Map<String, dynamic>?`，缺每种 operation_kind 的标准 inverse schema | W1 |
| `BoardAuthorization` 授权模型 | spine-contract 定义了字段，W0 第一阶段未实现类型 | W1 |
| `AnnotationBinding` 批注绑定类型 | spine-contract 定义了字段，W0 第一阶段未实现类型 | W2 |
| `VideoSourceProfile` 视频源附加 profile | spine-contract 定义了字段，W0 第一阶段未实现类型 | W4 |
| `TranscriptTrack` / `TranscriptSegment` 完整类型 | `TimedTextTrack` 已含 cue 列表，但 spine-contract 的 track / segment 分离模型未完全实现 | W4 |
| 数据库迁移 | 不在第一阶段范围 | W0 后续 |

## 后果

- W1–W4 可以并行开发，各自消费已冻结的共享类型和 fixture；
- 引擎赛马时所有候选面对相同统一快照，结果可比；
- 引擎替换不导致产品数据迁移（适配器层吸收差异）；
- 任何工作流需要变更共享契约时，必须走「契约变更请求」流程，由 W0 集成更新。