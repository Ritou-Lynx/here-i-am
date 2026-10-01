# Wave 3 A — 连续富文本与块类型 handoff

> 分支：`codex/whiteboard-wave3-a-richtext`
> 基线：`65735eef`（产品修复基线 `fe598eec`）

## 结果

- Paragraph / H1–H6 线性文档改为单一原生 `EditableText` 值；内部仍按 `RichTextBlock` 序列化。
- 跨段光标、Backspace / Delete 合并、Shift / 拖选、Ctrl+A 与中文 IME 由同一个 Flutter 文本输入状态处理，不再由每块独立输入框模拟。
- 常驻 Palm 绿块边框已移除；连续面只保留透明静态边界与灰阶 Focus 边界。
- 工具栏提供正文及 H1–H6；标题可恢复正文并清除 `level`；块元数据随保存 / 重启恢复。
- `CardRichTextEditor(compact: true, showToolbar: false, readOnly: ...)` 是 B 可嵌入的紧凑 surface，不含画布手势或布局语义。

## 契约影响

- 未改 `RichTextDocument` schema、Card / Source / Anchor / Snapshot、数据库、依赖或生成文件。
- `RichTextEditingController.replaceContinuousBlocks` 只把单一编辑值镜像回现有块文档；存储、历史、迁移与纯文本投影仍复用原契约。

## 验证

- 定向 analyzer（使用主工作区现成 package graph，只把 `memex` root 指向本隔离 worktree）：5 个改动 / 新增文件，`No issues found`。
- `git diff --check`：通过（仅 Git 提示后续 LF→CRLF）。
- 新增领域测试：连续块替换、撤销重做、序列化、H1/H6/Paragraph 保存重启。
- 新增 Widget 测试：单编辑值、跨块替换、Ctrl+A、中文 composing、H1→H6→正文、无绿色常驻框、紧凑只读嵌入。
- Flutter 全局锁被其他 Wave 3 窗口占用；`flutter test --no-pub` 等待约两分钟无输出后仅中止本窗口命令，未杀其他进程。隔离 worktree 又无法创建 `.dart_tool`（ACL 拒绝），因此本分支未伪报 Widget / Flutter test 运行通过。

## 真实支持与未完事项

- 本提交完整覆盖 Wave 3 真人场景中的 Paragraph / H1–H6 连续文档；列表、引用、代码、媒体或嵌套 children 仍保留旧兼容 surface，尚未承诺它们之间的跨块连续拖选。
- 行内 mark 在跨段选择时逐块写回；已有 mark 的任意文本编辑仍沿用旧控制器的 range clamp 语义，未在本提交重做 mark diff/shift 算法。
- 集成窗口需在 Flutter 锁释放后运行本 handoff 对应两组定向测试与原 `card_rich_text_editor_test.dart`，再做 Windows 真实输入法 / 鼠标拖选验收。

## 待集成提交

- 见本分支最新单一提交。

## Follow-up：连续输入撤销 / 重做

- 集成审计发现首提交的连续镜像只更新 `_doc`、未写入历史栈；现已让每次镜像调用现有 `RichTextDocumentHistory.commit(coalesce: true)`。
- 800ms 内的连续字符仍只保留编辑前快照，不会每字符生成独立撤销步；redo 恢复合并后的最终输入。
- 新增领域测试覆盖三次快速输入一次撤回 / 恢复，Widget 测试覆盖普通连续输入后的 Ctrl+Z / Ctrl+Y；原 IME 测试追加 `canUndo` 断言并继续验证 composing range 不被镜像提交清除。

## Follow-up：集成动态回归

- 历史栈不压入与当前文档结构相同的显式 checkpoint，但 `coalesce: false` 仍建立下一次编辑的合并边界；既避免“第一次撤销无变化”的重复快照，也保留第一版→第二版的分步撤销。
- 连续 surface 在工具栏夺焦前保存最后一个原生 selection，链接 / mark / 块类型操作使用该 selection；不再回退到已隐藏的 legacy block FocusNode。
- Paragraph 从连续 surface 转为 list / quote / code 后，焦点明确交还新建的 legacy block field，保证 Desktop 的 Tab / Enter 结构操作继续生效。
- 回归覆盖 identical checkpoint、工具栏 undo/redo、连续 selection 链接，以及 Paragraph→list 后的焦点恢复。
