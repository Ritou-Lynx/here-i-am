# P6-R6 响应文本门候选交接

## 范围与基线

本包只新增 `tools/dev_agent_bridge/workbench_response_text_gate.mjs`、同名 `.test.mjs` 与本交接。基线仍为 `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b` 加主控 overlay / 已冻结 R5 修复；未改任何现有文件、索引、profile、请求门或 probe。未提交、未读取凭据、未请求真实提供商、未运行 CLI / App / 手机 / 真实队列。

这是未生产接线的纯 Node 库候选。它只证明自己不会将未经完整验证的上游响应帧交给下游，不证明上游 hosted tool 已禁用、Codex 端到端工具隔离、所有真实提供商兼容或真人 Gate。

## API 与调用者责任

```javascript
import { createTextOnlyResponseGate } from './workbench_response_text_gate.mjs';
const gate = createTextOnlyResponseGate({ format: 'sse' }); // 或 'json'
gate.push(bufferOrUint8Array); // 复制输入；始终返回 undefined
// 必须等上游真实、正常 EOF；不能看见 response.completed 就提前调用。
const downstreamSseBuffer = gate.finish();
```

也导出 `WorkbenchResponseTextGate` 类与 `ResponseTextGateError`。`state` 只读，为 collecting / finished / failed；finish 只允许一次。任何失败均无输出返回，失败状态不可恢复，错误只带稳定 code，不附原始帧或上游文本。库不接受下游回调、不监听网络、不读取 auth、不执行工具。

调用者必须自行设置上游总时限 / 空闲时限、校验 HTTP 成功与正常 EOF，在 abort、断流或 transport error 时直接丢弃 gate；不能把一个已知前缀当作完整响应调用 finish。只允许使用成功返回的新 Buffer，不能转发原始 chunk、临时解析结果或失败前缀。请求侧 hosted-tool 拒绝仍由主控请求门负责。

## 严格合成子集

事件名字与核心类型依据：[官方 Responses streaming events](https://developers.openai.com/api/reference/resources/responses/streaming-events)。本轮已实际获取该页；仓库原合成 stop probe 的事件也作为本地输入参考。以下严格形状和顺序是本项目保守子集，不声称官方完整协议只有这些字段。

允许的 SSE 事件白名单：

- `response.created`、可选一次的 `response.in_progress`、唯一 `response.completed`。
- `response.output_item.added` / `response.output_item.done`。
- `response.content_part.added` / `response.content_part.done`。
- `response.output_text.delta` / `response.output_text.done`。

created 必须在前，completed 必须最后；它之后仅允许一个可选 `[DONE]` sentinel 和 SSE 注释 / 空白。事件名与 JSON type 必须相同；sequence_number 可全有或全无，有时必须为严格递增非负整数。items 按连续 output_index 登记，每个 added 必须有唯一对应 done，complete 的 output 必须与所有 done 一致。text delta 必须与 text done / content done / item done / complete 中的文本一致。content-part 和 text-done 事件可省略，但仍需要 text delta、item added/done、完整 complete。

Response 只允许 `id`、可选 `object`、`status`、`output`、可选且为 null 的 `error` / `incomplete_details`。`usage`、`model`、`metadata` 及其他额外字段目前全部拒绝；真实提供商完整响应通常超出本子集，**真实提供商兼容未验**。JSON 模式要求整个输入只有一个完整 completed Response 对象，同样使用严格 schema。

输出 item 仅接受 `message` / `reasoning`。message 必须 role=assistant、正确阶段 status、content 仅含 output_text 字符串；annotations / logprobs 若存在必须为空数组。reasoning 仅接受已知 summary_text / reasoning_text 结构和可选字符串 encrypted_content，校验后仅保留内部摘要用于比对 done / complete，生成输出时整项丢弃。reasoning 增量事件暂不接受。所有未知事件、item、content、字段以及工具项均拒绝；字符串中的工具样式 JSON 仍只是纯文本，不会被解释为调用。

## 重新生成与资源边界

成功时只从完整 Response 的 assistant output_text 生成新 SSE：created → 各 message 的 item added、content part added、text delta、text done、content part done、item done → completed。下游 id 以固定前缀和上游 response id 的 SHA-256 摘要重新生成，序号从 0 递增；不透传原始 id、reasoning、encrypted payload、未知字段或上游原始帧。

- 默认输入 1 MiB，输出 2 MiB，事件 4096；对应选项是 maxInputBytes / maxOutputBytes / maxEvents，必须为正安全整数且不超过 16 MiB 的数值上限。
- 固定最多 64 items，每个 item 最多 64 parts；每份 JSON 最多深度 32、节点 65536。
- 输入用定长有界 Buffer，避免大量小块的对象累计；UTF-8 严格解码，拒绝无效 / 截断多字节和未配对 Unicode surrogate。
- JSON 在 grammar 检查后增加有界重复 key 检查，包括 Unicode 转义的同名 key；SSE 仅接受 LF / CRLF、event/data 行与注释，未知 SSE 字段、未结束帧、重复或冲突信息均拒绝。
- 构造输出期间同样检查体积；即使最后才超限，也不会返回任何已构造前缀。

## 验证与冻结

`D:/Nodejs/node.exe --test tools/dev_agent_bridge/workbench_response_text_gate.test.mjs`：**66/66 通过**，0 fail / cancelled / skipped。所有用例均为内存数据，不启动进程或网络。

覆盖正常 text + reasoning、JSON、逐字节 CRLF / 多字节、多个 messages / parts、输出再次通过门、调用者修改原 chunk、文本中的 SSE 注入；10 类工具/未知 item 分别藏在 added / done / completed、混合文本工具、未知事件、缺 / 重复 / 冲突终态、重复 JSON key、bad JSON / UTF-8、缺形状、超限与零部分输出。

| 文件 | SHA-256 |
|---|---|
| workbench_response_text_gate.mjs | `7FC87E7478F3D94575DD817BC43616359D48716F5C1F3ED8AC371232D188308E` |
| workbench_response_text_gate.test.mjs | `D64A3F3CEA88C94035B64810198805952012822634469162B4166BD126790118` |

R5 client / adapter 冻结哈希保持原值。本包已停止写入；主控负责请求门组合、实际 Codex loopback 合成探针及最终复核。生产 `workbench_text_only_v1` 未被本包启用。
