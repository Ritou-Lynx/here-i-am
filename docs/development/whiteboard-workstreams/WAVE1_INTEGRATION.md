# Wave 1：真人反馈第一波集成交接

## 集成状态

- 集成分支：`codex/whiteboard-wave1-integration`
- 基线：`v3-lab@34c6070bb955e15c946c2904e709cfd943445215`
- 本轮保持 schema 60；没有修改 Card / Source / Anchor 共享身份，也没有新增第二套标签或导入存储。
- 主工作树同时存在 W5 真人验收窗口的未提交改动，因此本轮没有覆盖、stash 或合并主工作树；待其干净后再由集成窗口合入 `v3-lab`。

## 已完成闭环

1. Desktop `/`、`/cards`、`/whiteboard` 使用持久工作区壳和无页面级缩放的同级切换；返回首页不再重播手机开屏。Logo 使用已有墨绿色单色资产，侧栏与主体用低对比纸张渐隐连接，收起后不残留竖线。
2. 首页改为六块真实 Card / Source / Board 数据模块：30 天活动、卡片角色/媒介构成、上板比例、白板增长、最近白板、待整理卡片；无演示健康、账本或 W5 数据。
3. 卡片库把“卡片角色”和“媒介类型”拆成正交筛选；Note 与 Source Card 均可显式写入全局标签，正文中的 `#片段` 不会自动污染标签体系。
4. `/import` 统一网页与视频入口，接受纯 URL 或完整分享文案；多 URL 必须由用户选择。预览零写入，确认后仍通过唯一 `Source → SourceVersion → Card` 身份提交。YouTube 保留研读路径，Bilibili 诚实降级为 link-only。
5. 画布卡片四边可直接拖线，线创建后可改方向与标签；空白双击建立真实 Note Card。Note / Annotation / Reference / TaskArtifact 支持板内紧凑编辑，Source Card 始终打开现有来源消费页。
6. 画布可变操作有 UI、ViewModel、Adapter 多层只读守门；连线保存失败完整回滚；建卡/摆放失败做局部补偿且不清空旧撤销史；布局撤销/重做不会把 Repository 的最新卡片内容恢复成历史旧投影。

## 联合验收

- 完整 `test/whiteboard_canvas`：144/144。
- Desktop 路由、首页、工作区壳、链接导入与卡片库：65/65。
- Repository、分享文本解析、导入服务、标签字段与来源页：46/46。
- 合计 255/255；本轮 25 个实际变更 Dart 文件精确 analyze 零 issue；`git diff --check` 在提交前通过。
- 500 卡数据基准仍在既有门槛内；本轮没有宣称新的 Windows 真窗口视觉或 FPS 验收。

## 下一波，不在本轮冒充完成

- `BoardEdge` 仍是单个白板内的视觉布局关系，不是语义双链。下一波需要独立 `CardLink` / Backlink 契约、迁移、反链查询和 UI，再决定视觉线与语义关系如何互转。
- 小红书图片、图片 OCR、重要评论，以及普通网页原图，需要复用统一安全资产缓存并先明确 `object_ref`、评论证据和版本归属；禁止 UI 直接加载不可信远程图片。
- “上板”筛选文案按用户要求暂时保留，待真实使用后再命名。
- Bilibili / 小红书仍不声明公开稳定的可控播放、current time、seek 或平台字幕能力。

## 分流交接

- Desktop 外壳：首页与路由见 `WAVE1_DESKTOP_SHELL_HOME.md`。
- 标签与筛选见 `WAVE1_CARD_TAGS.md`。
- 分享文本与统一导入见 `WAVE1_LINK_IMPORT.md`。
- 画布交互与事务边界见 `W1_CANVAS_INTERACTION_REWORK.md`。
