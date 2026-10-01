# Wave 3 — 卡片原位编辑 handoff

> 分支：`codex/whiteboard-wave3-inline-edit`
> 基线：`57240fcc`

## 结果

- 普通卡双击后，标题与连续富文本直接替换原 `BoardItem` 卡面；位置、宽高、圆角与旋转保持不变。
- embedded surface 删除标题栏、关闭、保存、全屏按钮和编辑专用边框；内容被卡片圆角与原 rect 裁切，富文本区域在约束内自行滚动。
- 卡外点击与 Esc 进入同一自动保存退出路径；保存失败时不退出，避免静默丢内容。
- 编辑态隐藏 resize、rotate 与上下左右四个连线点；单击和拖动仍只作用于非编辑卡面。
- 编辑会话继续由 `itemId` 标识，同一 Card 的两个 BoardItem 不会同时进入编辑态；readonly 仍拒绝进入编辑。
- `CardRichTextEditor.inlineSurface` 是默认关闭的窄接口，仅为卡面嵌入去掉内部 focus 边框与 padding；其它全屏、工具栏与连续文档路径不变。
- 全屏入口保留在卡片右键菜单“展开查看”，产品闭环测试不再依赖已删除的 embedded 扩展按钮。

## 契约影响

- 未改 Card / BoardItem / Source / Anchor / Snapshot 语义、schema、依赖、edge snap、Desktop theme、W5 或生成文件。
- 存储仍调用 `UnifiedCardRepository.saveRichText`；连续文档、IME、undo/redo 仍复用 Wave 3 A 的 `CardRichTextEditor` / `RichTextEditingController`。

## 验证

- 先补失败 Widget 回归，再实现：原 rect 不变、无 chrome、编辑态隐藏八个操作点、拖动隔离、卡外退出、Esc 持久化、同 Card 双摆放按 itemId 隔离。
- 更新产品闭环回归，验证 embedded editor 为 `compact + inlineSurface`，全屏消费页从既有右键菜单进入。
- 定向 analyzer：5 个实现 / 测试文件，`No issues found`。
- `git diff --check`：通过（仅 Git 提示后续 LF→CRLF）。
- 两组定向 Flutter Widget 测试启动 30 秒零输出，按主窗口指令中止本窗口会话；同期孤儿 cmd 在精确清理前已自行退出，未终止任何未知进程。因此未伪报动态通过，需集成窗口统一直调 Flutter snapshot 复跑。

## 集成复跑

- `test/whiteboard_canvas/whiteboard_canvas_direct_interactions_test.dart`（16 个 Widget tests）
- `test/whiteboard_canvas/whiteboard_canvas_product_loop_test.dart`（4 个 Widget tests）
- Windows 真人验收重点：中文 IME composing 后卡外点击 / Esc 保存、内容超出卡片时内部滚动、旋转卡编辑几何、同 Card 双摆放切换。
