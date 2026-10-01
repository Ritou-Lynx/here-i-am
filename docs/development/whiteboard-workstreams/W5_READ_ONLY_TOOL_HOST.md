# W5-R3 — 只读 Here I am Whiteboard Tool Host 交接

> 状态：完成，待 W5 集成窗口接线
>
> 日期：2026-08-21
>
> 工作流：W5-R3 / Phase B 只读工作台基础

## 1. 本轮闭环

新增 provider-neutral 的 `WhiteboardAiReadToolHost`。调用方必须显式提交
`boardId`、`cardIds`、`sourceIds`；宿主只读复用
`UnifiedCardRepository` 与 `WhiteboardDriftStore`，返回有界、确定性、可 JSON
序列化的选择快照：

- Card 稳定 ID、类型、标题、`body_excerpt`、正文投影、标签及 Source 来源链；
- Source / SourceVersion 稳定 ID、媒体类型、origin、provider、当前版本与版本基本信息；
- 目标 Board 上所请求 Card 的 BoardItem、GroupMember、BoardGroup 与双端均在选择集内的 Edge；
- 结构化状态、问题和截断收据，不返回底层异常文本。

宿主不加载 RichText / Source object 文件，只读取 Drift 中已同步的正文投影，
因此不会触发文件恢复或把对象目录变成任意文件读取入口。

## 2. 安全与边界

- 默认上限：32 Cards、32 Sources、256 BoardItems、128 Groups、512
  GroupMembers、512 Edges、每 Source 20 个版本；正文默认 6000 runes。
- 每项配置都有不可突破的 hard ceiling，并在 `WhiteboardAiReadLimits` 构造时
  校验非负及 ceiling；调用方不能靠自定义配置扩大 Card / Source / body / Edge
  等信任边界。
- 单次响应默认 UTF-8 总预算 128 KiB、hard max 256 KiB。最终门按真实
  `jsonEncode` UTF-8 字节计量，优先收缩 Card 正文 / excerpt，再按稳定顺序裁剪
  关系和明细；超限响应固定为 `partial` 并带
  `serialized_output_utf8_bytes` 截断收据，不静默丢弃。
- 请求 ID 只接受受限稳定字符串；非法 ID 或越界数量在查询前以
  `invalid_request` 拒绝，响应不会回显不安全路径。
- 缺失与软删除 Card / Source / Board 均 fail closed；软删除 Edge 不输出；
  不可用对象不会经 BoardItem / Group / Edge 侧漏。
- 原始 `metadata`、Card `presentation`、BoardItem `viewState`、Group / Edge
  `style`、SourceVersion `objectRef` 永不进入响应；全部文本出口共用同一守门，
  Windows、UNC、Unix 与 `file://` 本地路径按整段 fail closed 脱敏，带空格路径
  不会残留后半段。
- 不暴露 Drift、裸 SQL、数据库文件、绝对路径或任意文件 API；无网络调用、
  无数据库写入、无 WhiteboardOperation。

`body_excerpt` 只是正文开头的确定性截取，不是 AI 生成的语义摘要；消费者不得
把它展示或解释为模型总结。

## 3. 拥有路径与契约影响

- `lib/data/whiteboard/ai_read_tools/whiteboard_ai_read_models.dart`
- `lib/data/whiteboard/ai_read_tools/whiteboard_ai_read_tool_host.dart`
- `test/data/whiteboard/ai_read_tools/whiteboard_ai_read_tool_host_test.dart`
- 本交接文件

未修改 `UnifiedCardRepository`、`WhiteboardDriftStore`、Card / Source / Board /
Snapshot / Operation 契约、schema、路由、UI、RuntimeAdapter 或 ContextEnvelope。

## 4. 验证

- `flutter test --no-pub test/data/whiteboard/ai_read_tools/whiteboard_ai_read_tool_host_test.dart`
  — 9/9 通过。
- `dart analyze lib/data/whiteboard/ai_read_tools test/data/whiteboard/ai_read_tools`
  — No issues found。
- 测试使用真实临时 SQLite `NativeDatabase`、真实 `AppDatabase`、
  `UnifiedCardRepository` 与 `WhiteboardDriftStore`，覆盖 Card + Source + Board
  关系、重复摆放、hard ceiling、12 张多字节 Unicode 卡的整体 UTF-8 预算、
  缺失 / 软删除、原始 metadata、带空格本地路径整段脱敏，并比较工具调用前后
  完整持久化投影，确认零写入。

## 5. 待集成事项

1. R2 的 RuntimeAdapter / Bridge 接线由 W5 集成窗口完成；本轮没有定义 MCP
   transport、tool name 或 provider 私有 payload。
2. ContextEnvelope 应只传显式选择 ID，再调用 `readSelection`；不得把整个白板
   或原始 metadata 预载入 Prompt。
3. 若未来需要 Source 正文，必须另立受限的 Source object 读取工具契约；不得在
   本宿主中直接接受 objectRef 或文件路径。
4. 本工作树未 commit / push。
