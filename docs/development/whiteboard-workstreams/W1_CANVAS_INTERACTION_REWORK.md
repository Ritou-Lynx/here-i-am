# W1 画布基础交互返修交接

## 本轮边界

- 基线：`v3-lab@ab066866365621ea336f2c05a0dadd3671922a62`
- 临时分支：`codex/whiteboard-wave1-canvas-interactions`
- 只修画布交互、窄路由接线、compact editor 与对应测试。
- 没有新增 CardLink / Backlink，没有修改 schema、共享路由、卡片库或 W5。`BoardEdge` 仍只是白板布局线，不冒充语义双链。

## 完成的产品闭环

1. 选中或悬停卡片显示四向连接锚点；从锚点拖到另一卡片即创建默认无向、无标签 `BoardEdge`。空白落点、自环和未知端点被拒绝；偏移画布容器使用统一局部坐标，连线会跟随卡片。
2. 新线创建后自动选中，下方轻量浮层修改方向和标签，保存后可从快照恢复。旧“选两卡再连接”仅保留为键盘/无障碍备用入口。
3. 空白画布双击通过 `UnifiedCardRepository.createTextCard` 建立唯一真实 Note Card，再放入当前 Board。无限画布保留负坐标，不再把新卡钳到原点。布局保存失败会恢复原快照并软删新 Card，不留 BoardItem。
4. Note、Annotation、Reference、TaskArtifact 双击打开板内 compact editor，复用同一 `RichTextDocument` / Repository；中文 IME、Ctrl+S、marks、块类型和 asset refs 保留。Source Card 双击或右键主动作始终进入现有来源消费页，避免来源摘要被误当作用户备注编辑。
5. 右键短按打开卡片/画布菜单；移动超过 5 px 则转为右键平移，松开不误弹菜单。卡片、分组交互会清除待定空白双击，避免“空白→卡片/分组→空白”误建卡。
6. 第二轮交叉审计后，可变操作增加 UI / ViewModel / Adapter 多层只读守门；连线更新与删除等待持久化，失败时回滚内存、undo 与 operation log；建卡/摆放失败只回滚本次逻辑动作，soft-delete 补偿失败提供可见重试；页面退出期间完成的建卡也会进入补偿。
7. ViewModel 维护 Repository 的当前 Card 内容投影；布局 undo / redo / cancel 恢复历史布局后会叠加最新内容，不能把已保存的标题、正文或预览回退成历史快照。

## 验证

- 新 direct-interactions：13/13 通过。
- 旧 product-loop：5/5 通过；旧 interactions：26/26 通过。
- `test/whiteboard_canvas` 在工作流返修分支 144/144，通过；汇入 Wave 1 集成分支后再次 144/144 通过。
- 集成态 500 卡数据性能：cold load 6.5 ms，JSON 往返 16.5 ms，批移 100 卡 3.0 ms，框选 2.9 ms，1000 卡加载 0.7 ms。真实 Repository 500 卡查询 13 ms。
- Widget culling / LOD 回归通过；测试环境不声称真实桌面 FPS。

## 诚实未完与集成注意

- 语义双链/反链索引完全不在本轮；需后续独立 CardLink/Backlink 契约与迁移。
- 建 Card 和保存 Board 跨 Repository/快照，当前不是单一数据库事务。已做本次逻辑动作回滚 + Card soft delete 补偿；补偿失败不会隐藏，会保留可见的“重试清理”动作，但没有为此新增持久化队列表。
- compact editor 是轻量入口，复杂块能完整保存，但更广的块级操作仍应在显式“展开编辑”页完成。
