# A1 Authority Inventory Handoff

## 交付

- Goal / 工作包：`GOAL-20260826-authority-preflight` / A1。
- task/thread ID：`01a03c91-8bae-7491-a3b2-4cb20f4f8a92`。
- 验收主窗 task/thread ID：`01a03c7e-ceda-7351-9ed6-93c48e9c15d5`。
- Worktree：`C:\\Users\\ExampleUser\\.codex\\worktrees\\c493\\here-i-am`（detached HEAD，按派发允许）。
- 基线：`b0a71770eaa8128d1ee67d60331ce79c6ecc4835`（创建时的激活基线）。
- 内容提交：`89b6768070c6fdef3b1d0a5aea94d2e3d6050f5a`。

## 修改范围

仅 `docs/development/data-authority-preflight/`：

1. `A1_CURRENT_AUTHORITY_INVENTORY.md`：10 类对象的当前证据、权威、生命周期与未知项；
2. `A1_PRELIMINARY_MIGRATION_MATRIX.md`：预备处理类别与 Gate；
3. `A1_PRELIMINARY_ADR_OPTIONS.md`：不作决定的 ADR 选项；
4. 本 handoff。

## 真实支持范围与限制

- 已覆盖 Card、Memory Card/User-truth、SourceContent/SourceVersion、RichTextDocument、Board/BoardItem、Annotation/Anchor、Dreaming Fragment/Episode/Saga、Evidence、TaskArtifact/TaskRoom。
- 发现当前白板 Card 身份复用 `MemoryCards` 且设为 `user_truth`；仅记录为迁移红灯，未改代码。
- P4/P5/P6 均保留为 unresolved input；没有声称其通过。
- 未读真实用户数据、生产 SQLite/Vault/附件或备份；对象级恢复、备份与实际迁移成功率在无代码/权威契约时标注 `unknown`/`blocked`。

## 验证与下一步

- 已运行：`LINK_TARGETS_OK`；对象覆盖关键词无缺失；`git diff --check` 通过。
- A2 可只将本 A1 的“阻断/未决”转化为合成 fixture 与隔离 harness 的 failure classes；不得把预备类别当 schema 决策。
- W0 应审计引用行号、补齐可接受的 `unknown`，再决定是否允许 A2 以 A1 commit 为基线启动。
