# A1 预备迁移矩阵（非正式 schema 决策）

状态词只表达预备处理类别，不授权实现：**保留**、**迁移**、**派生**、**只读兼容**、**降级保留**、**阻断**。

| 对象 | 预备类别 | 目标边界 / 不变量 | 当前证据 | 阻断或待决 |
|---|---|---|---|---|
| 白板 CardContract | 阻断 | 中性稳定 Card；不得因白板出现而成为 User-truth。 | 当前复用 `MemoryCards` 且明确写 `memoryScope='user_truth'`。[tables.dart:962-965](../../../lib/data/memory_v3/db/tables.dart#L962-L965) | 中性 catalog、truth relation、旧调用者兼容未决。 |
| Memory Card / User-truth | 迁移 | 保持显式 Record Organizer 写入与来源/结构字段；变为独立关系，不吞并普通 Card。 | 当前 `MemoryCards` + sources/fields。[tables.dart:25-98](../../../lib/data/memory_v3/db/tables.dart#L25-L98) | 防误升格、召回/更正连续性须 Gate 1A-1。 |
| SourceContent | 保留 | 原件身份、content hash、object ref；不塞入 Card 正文。 | `WhiteboardSources`。[tables.dart:1055-1079](../../../lib/data/memory_v3/db/tables.dart#L1055-L1079) | 媒体对象迁移与备份 manifest 未决。 |
| SourceVersion | 保留 | 不可变版本；Anchor 总指向精确版本。 | `WhiteboardSourceVersions`。[tables.dart:1081-1091](../../../lib/data/memory_v3/db/tables.dart#L1081-L1091) | version/object commit/recovery 未决。 |
| RichTextDocument | 只读兼容或降级保留 | 若 Markdown 切换通过，仅能从 revision 确定性重建/作为兼容输入，不能竞争正文权威。 | Roadmap 红线。[PRODUCT_ROADMAP.md:104-110](../../companion-first/PRODUCT_ROADMAP.md#L104-L110) | marks/assets/IME/历史映射未分类即阻断。 |
| Board / BoardItem | 保留 | BoardItem 仅布局和局部视图，删除不删 Card/Source。 | schema 与 delete 实现。[tables.dart:991-1008](../../../lib/data/memory_v3/db/tables.dart#L991-L1008) [whiteboard_drift_store.dart:113-145](../../../lib/data/whiteboard/whiteboard_drift_store.dart#L113-L145) | Board snapshot/operation 与 Card migration 原子性未决。 |
| Annotation / Anchor | 迁移 | Annotation 可继续是 Card；Anchor 保持结构化、可版本解释的引用。 | Card presentation 存 Anchor。[repository_video_annotation_store.dart:98-138](../../../lib/data/whiteboard/repository_video_annotation_store.dart#L98-L138) | 独立 Anchor storage、selector mapping、tombstone/re-anchor policy 未决。 |
| Dreaming Fragment/Episode/Saga | 降级保留 | 关系记忆保持独立，不能迁移成 User-truth 或普通 Card 的默认正文。 | 独立表族/状态。[tables.dart:130-160](../../../lib/data/memory_v3/db/tables.dart#L130-L160) | 是否展示为 Card、引用策略、备份/恢复矩阵未决。 |
| Evidence | 阻断 | Source 原文、不可变 Evidence Claim、展示 Card 三层分离。 | 仅有设计方案，无独立 Claim table。[ARCHITECTURE.md:137-165](../teacher-recruitment/phase0/ARCHITECTURE.md#L137-L165) | Gate 2 schema、supersede/retract、索引、恢复全未实现。 |
| TaskArtifact / TaskRoom | 降级保留 | task lane 独立；仅用户授权 promotion 才产生 Source/Version/Card。 | promotion 契约。[generated_artifact.dart:162-203](../../../lib/domain/workbench_ai/artifacts/generated_artifact.dart#L162-L203) | P6 生产入口未通过；archive/restore/backup policy 未决。 |

## 通用迁移闸门

1. 任一对象没有“旧身份 → 新/保留身份、正文/状态权威、引用与回滚”映射时，不能切换。
2. 任何跨 Markdown、Source、operation log、SQLite、FTS、Receipt 的迁移必须先选择单一 commit/recovery protocol；单文件原子替换不足以证明跨介质一致性。[PRODUCT_ROADMAP.md:90-92](../../companion-first/PRODUCT_ROADMAP.md#L90-L92)
3. 未分类 RichText blocks/marks/assets/Anchor、重复 ID、无效元数据、外部移动/删除、并发编辑都应进入 A2 golden corpus；本 A1 不生成 fixture。
