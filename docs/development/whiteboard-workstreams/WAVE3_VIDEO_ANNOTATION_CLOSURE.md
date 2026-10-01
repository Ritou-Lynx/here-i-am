# Wave 3 — Desktop 视频标注与链接动作闭环 handoff

> 分支：`codex/whiteboard-wave3-video-annotation-closure`
> 基线：`693050e9cb509d90feb1c5b8b2bb6dd909e324c4`
> 状态：隔离实现与定向验证完成，待主窗口审计 / 集成 / Windows 真人验收

## 1. 本轮闭环

1. 点标注与区间标注不再靠 `start_ms == end_ms` 反推类型。区间流程显式
   保持 `is_point=false`；开始 / 结束点击均直接读取 `PlayerAdapter` 的权威
   当前位置，避免 native player 时间事件稍滞后时把区间错误保存成一点。
2. 时间 Anchor 仍只要求播放器可读当前位置，不读取字幕。无字幕播放器可以
   建点与区间，区间编辑头明确展示 `start–end`，保存后保留完整毫秒边界。
3. 视频标注编辑改为一个连续多行内容面：首行在保存时投影为 `Card.title`，
   其余原样投影为 `Card.body`。字幕 cue 可把“原文引用”插入同一文档；用户
   可编辑或整段删除。文本面无 InputBorder、focus outline 或 filled 背景，
   不再呈现为大输入框。保留引用段时同时投影到 `Anchor.quote`，删除后为 null。
4. 链接导入的研读级视频不再“保存并进入研读”。“保存”只提交 Source / Card
   并留在当前导入上下文；成功后另显示“打开视频研读”，只有显式点击才导航。

## 2. 数据兼容与边界

- 未修改数据库 schema、生成文件、`AnchorContract`、`CardContract`、
  `AnnotationCreationRequest` 或 Repository 写入顺序。
- 既有 Annotation Card 仍保存 `title / body`；Anchor 仍保存相同的
  `start_ms / end_ms / is_point / quote`。连续编辑面只是 UI 到既有字段的投影。
- `Card.body` 会保留用户文档中的“原文引用”段，`Anchor.quote` 同时保存该段
  的纯引用文本，用于既有锚点证据；这是兼容性重复，不是第二套笔记数据。
- 未改字幕抓取、登录态、provider 解析、卡片库、BoardEdge、F 菜单 / 批量 /
  手绘、W5、依赖或 `*.g.dart`。

## 3. 自动化证据

- `video_study_widget_test.dart`：19 条通过。覆盖无字幕点 / 区间、静默时间
  事件播放器仍读取真实起止、区间重启恢复、点击标注回跳 start、单一输入面、
  cue 引用自动插入 / 编辑 / 删除。
- `link_import_screen_test.dart`：21 条通过。研读级 YouTube 保存后仍留在导入页，
  Source / Card 已持久化；显式点击“打开视频研读”后才导航。
- `repository_video_annotation_store_test.dart`：2 条通过。数据库关闭 / 重开后
  区间仍为 `10000–14000` 且 `is_point=false`。
- 合计 42 条定向动态测试通过。
- 生产 4 文件与测试 3 文件分别执行 direct Dart analyze：均 `No issues found`。
- `git diff --check`：通过（Windows CRLF 转换提示，无 whitespace error）。

## 4. 风险与真人验收

1. 自动化用“当前位置可读但 timeEvents 静默”的 adapter 覆盖真实播放器事件
   滞后；仍需 Windows YouTube 实播中拖到两个不同位置，确认界面显示完整区间、
   重启后卡片回跳起点。
2. 单一 TextField 的第一行 / 正文投影已锁测，但这不是富文本块编辑器；当前
   保留纯文本换行与“原文引用”标记，未新增 schema 或私有文档格式。
3. `Anchor.quote` 只读取“原文引用”标记之后至文档末尾的文本；当前自动插入
   始终把引用放在末尾。若未来允许引用后继续写正文，应先定义显式引用边界，
   不能静默扩大 quote。
4. 第一次全量 Flutter analyze 遇到本机工具子进程空转，已仅终止本次命令确认
   启动的进程；随后更窄的 direct analyze 与三组动态测试均完成通过。

## 5. 集成

- 本文件所在隔离提交即集成来源；准确 commit hash 由主窗口从 cherry-pick
  来源记录。本工作树不负责集成、Windows 构建或 push。
