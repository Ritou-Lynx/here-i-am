# Wave 3 — 连续卡面与卡片库字体 handoff

> 分支：`codex/whiteboard-wave3-card-surface`
> 基线：`693050e9`

## 结果

- 普通线性 Note Card 在 BoardItem 内只挂载一个原生多行文本输入值；不再分别渲染标题与正文输入栏，也没有 InputDecoration、焦点框或编辑 chrome。
- 单一值的第一行在保存边界投影回 `Card.title`，第一个换行后的全部内容投影回现有 `RichTextDocument` / `Card.body`；没有修改 Card schema 或 Repository 身份。
- 现有线性 block 类型与合法 mark 随行索引保留，mark 范围按新行长度收窄；新增行写成 Paragraph。中文 IME composing 仍由同一个 Flutter EditableText 持有。
- 双击空白创建不再预填“未命名卡片”；真实 Note Card 建立并摆放后，同一卡面在下一帧明确请求输入焦点。
- 卡外点击与 Esc 继续保存后退出；失败仍保留编辑态。readonly、同 Card 多 BoardItem 的 itemId 编辑会话与 BoardItem 几何沿用现有契约。
- 左上角卡片库行名称及拖拽预览名称统一改走 `whiteboardUiTextStyle`，中文汇文明朝体、英文数字按白板 token 回退。

## 契约影响

- `Card.title / body`、`RichTextDocument`、`BoardItem / itemId` 与 Repository 保存接口保持兼容；未改 schema、依赖、生成文件、BoardEdge 或 FlexNote F 命令体系。
- 媒体、引用或含嵌套 children 的复杂 Note 不进入这条轻量线性投影，继续使用原复杂文档编辑 surface，避免卡面编辑静默压平资产与结构。

## 验证

- 新增纯投影测试：首行 / 多行 / 单行 / 空卡往返。
- Widget / 产品闭环覆盖：空白双击立即聚焦、单 TextField、无 decoration、IME composing、首行标题与余行正文保存、Esc、原 BoardItem 几何、readonly、同 Card 双摆放、卡片库字体与 Repository 重连。
- 定向四文件组：51/51 tests passed。
- 6 个实际源码 / 测试文件定向 analyze：`No issues found`。
- `git diff --check`：通过。

## 风险与真人验收

- 卡面为了保持单一原生选择 / IME 状态，只视觉区分第一行标题；块类型工具栏仍属于全屏富文本入口。
- Windows 真人重点：双击空白后直接中文输入、第一行回车进入正文、长文卡内滚动、卡外与 Esc 保存、同 Card 双摆放切换、卡片库中英文混排字体。
