# P6-R6 文本门网络结束责任交接

本包只新增 `tools/dev_agent_bridge/workbench_text_gate_transport.mjs`、同名 `.test.mjs` 与本交接。没有修改请求门、响应门、原有文件、索引或生产配置；未提交、未派生 worker、未连接外网 / 真实账号 / 设备 / 队列。所有网络测试只访问测试自身绑定的 127.0.0.1 随机端口。

## API

```javascript
const outputSseBuffer = await exchangeTextOnly(body, {
  model,
  upstreamUrl,
  headers: {},
  signal,
  timeoutMs: 10000,
  maxRequestBytes: 1024 * 1024,
  maxMessages: 128,
  maxInputBytes: 1024 * 1024,
  maxOutputBytes: 2 * 1024 * 1024,
  maxEvents: 4096,
});
```

导出函数 `exchangeTextOnly` 与 `TextGateTransportError`。返回值只有完整重建后的新 SSE Buffer；没有 partial 返回值、stream callback 或原始帧转发接口。`timeoutMs` 为正整数且最大 300000，其余 limits 为正安全整数且数值不超过 16 MiB；请求与响应的结构约束仍由各自 gate 执行。

## 固定目标、请求与结束条件

- 配置目标仅接受精确 `http://127.0.0.1:<port>/v1/responses`（端口 1–65535），或精确 `https://chatgpt.com/backend-api/codex/responses` 候选路径。拒绝 userinfo、query、hash、其他 host/origin/path 与 URL 规范化变体。没有默认目标，也不从 body / headers 选择目标。
- headers 只接受 host 显式传入的普通键值对象；白名单为 Bearer `authorization` 和 `chatgpt-account-id`，并检查字符与长度。Content-Type / Accept 由库固定。拒绝 Cookie、Host、Location、CRLF、重复大小写别名与其他 header；不读取环境凭据，不从 body 派生 header。
- 在发出 HTTP 请求前用固定输入请求门重建 body；上游 tools 为空、tool_choice=none、parallel_tool_calls=false，目录与隐藏 metadata 不被转发。无效请求、目标、header、limits 或预先 aborted signal 都不会触发 fetch。
- 使用 POST 与 `redirect: 'manual'`，任何非 2xx（含所有 3xx）立即拒绝并丢弃 body；不跟随 Location。只接受 text/event-stream 或 application/json，charset 若显式提供只允许 UTF-8。
- 按 reader.read 消费响应，只在其正常 `done=true` 后调用响应 gate.finish。`response.completed` 本身从不触发 finish；终态后追加未知 / 工具帧仍由 gate 拒绝全包。transport error、网络断连、外部取消与截止超时均拒绝且零返回。
- 截止时间用单调时钟，覆盖请求重建、网络、读取、finish；读取前后、finish 前后与清理后均检查截止时间 / signal。finally 清除计时器、移除外部 abort listener、中止自身 fetch、cancel / release reader 或丢弃未读取的响应 body。
- 错误只包含稳定 code，以及可选数字 httpStatus / gateCode；不携带原始 fetch error/cause、目标 URL、AbortSignal reason、auth 或正文。

正常 EOF 指 HTTP body reader 的正常结束；不把 TCP keepalive 连接随后何时关闭当作额外完成条件。对于以 chunked 响应写出 completed 后直接销毁 socket 的测试，reader 实际报错，交换拒绝。

## 验证与冻结

- `D:/Nodejs/node.exe --test tools/dev_agent_bridge/workbench_text_gate_transport.test.mjs`：**13/13 通过**。
- 与 `workbench_response_text_gate.test.mjs` 组合：**79/79 通过**，0 fail / cancelled / skipped；transport 测试同时经过输入请求门的实际重建。
- 实际 loopback HTTP 覆盖 SSE / JSON、completed 后延迟 EOF、追加 tool、socket destroy、不结束导致 timeout、外部取消、预取消零请求、HTTP 500、302 且重定向目标零请求、content-type 与大小限制、header/URL/body 越权以及工具请求拒绝。
- 测试只使用内存合成正文及合成 auth 字符串。请求门测试文件未作为输入复制到本工作树，本包不重复宣称它的独立测试结果。

| 文件 | SHA-256 |
|---|---|
| workbench_text_gate_transport.mjs | `B8BF7373DC767A910AA58BA7BF3AF00BCE0D266DA24F46479D2B087DA249C957` |
| workbench_text_gate_transport.test.mjs | `47684FB304B52C43F350375C3E9C128555A93008647AAE34DD56ED2D42AC2232` |
| 只读输入 workbench_request_text_gate.mjs | `2A477A238E87DAFC726D859FA58DB72C60B2C9AE3CDF66C035AE8EF5A001CB05` |
| 只读输入 workbench_response_text_gate.mjs | `7FC87E7478F3D94575DD817BC43616359D48716F5C1F3ED8AC371232D188308E` |

本包未调用官方候选 origin。真实认证/header、官方完整协议兼容、实际 Codex 两层 HTTP 合成探针与生产接线均由主控后续复核；本包不启用任何 profile，也不签发专用生产回执。已冻结，等待主控回收。
