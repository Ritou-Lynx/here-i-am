# A1 预备 ADR 选项与待决问题

> 不是正式 ADR；没有选择任何选项，也不授权 schema、迁移或运行权威切换。

## 必须由正式 Gate 1A-0 决定的选项

| 议题 | 选项 A | 选项 B | 当前建议状态 |
|---|---|---|---|
| 中性 Card 物理承载 | 新建独立 Card catalog，再用关系表达 User-truth | 演进现有 `MemoryCards`，拆出强制 truth 语义 | 未选择；当前复用已造成普通 Card → `user_truth` 红灯。[tables.dart:962-965](../../../lib/data/memory_v3/db/tables.dart#L962-L965) |
| Card 正文 | Markdown/YAML envelope 为唯一 revision 真相，RichText 为确定性派生/兼容输入 | 保持 RichText 为正文权威，Markdown 仅导出 | Roadmap 已选择目标方向为前者，但只在正式切换 Gate 后生效。[PRODUCT_ROADMAP.md:104-110](../../companion-first/PRODUCT_ROADMAP.md#L104-L110) |
| 跨介质提交 | intent/journal + revision hash + startup recovery | 单独的 DB/file 先后写 | 后者不满足已确认要求；前者的日志位置、阶段、幂等与 rollback 仍未设计。[PRODUCT_ROADMAP.md:90-93](../../companion-first/PRODUCT_ROADMAP.md#L90-L93) |
| Anchor 表达 | 结构化 SourceVersion + selector/fingerprint 为权威，Card 只引用/展示 | Anchor 长期嵌入 Card presentation | 未选择；当前实现采用嵌入 presentation，正式 ADR 必须说明迁移与兼容。 |
| Evidence | 独立不可变 Claim，Card 仅可读投影 | Evidence Card 自身可编辑为唯一真相 | 目标契约支持前者；当前生产表尚不存在，故阻断实施。[PRODUCT_ROADMAP.md:271-291](../../companion-first/PRODUCT_ROADMAP.md#L271-L291) |
| TaskArtifact promotion | 明确 user authorization + Source/Version/Card 三者齐备 | task artifact 自动升格 | 前者已有 domain contract；后者违反任务隔离/显式授权边界。[generated_artifact.dart:162-203](../../../lib/domain/workbench_ai/artifacts/generated_artifact.dart#L162-L203) |

## 未决问题（必须留红）

- RichText 的 block、重叠 mark、asset、中文 IME、历史 revision 与 Anchor 的逐项无损/降级/阻断表。
- `memory_cards` 与 `whiteboard_card_extras` 的双表当前状态如何一次性迁移、回滚且不损失检索投影。
- Source object、Markdown、operation log、SQLite、FTS、Receipt 的 journal 格式、崩溃 phase 与恢复判定。
- 30 天应用回收站、备份保留、Source/Attachment 生命周期及真实可恢复验证。
- P4/P5/P6 各自未通过事实对 TaskArtifact、Undo、Memory/Task lane 读取边界的影响。
