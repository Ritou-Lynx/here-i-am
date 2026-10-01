# P6 R7 Product Host Binding 交接

新增 `workbench_product_host_binding.mjs` 仅把可信 root 构造的 transport、普通会话 guardian 与单一 TaskRoom 绑定组合起来。它不监听端口、不访问网络、不启动产品，也不改现有 candidate/successor host。

- `WorkbenchProductHostBinding` 使用私有 `WeakSet` 品牌；普通调用者不能以对象形状伪造 binding。
- `readWorkbenchProductRequest(req)` 是根 HTTP 接缝的严格解码器：只消费最多 64KiB 的 `IncomingMessage` / AsyncIterable，严格 UTF-8 解码 JSON；非空 body 要求 `application/json`（可带 UTF-8 charset），超限、abort 或非法 JSON 只抛固定拒绝码，不记录 raw 请求。
- `/p6/r7/product/task` 只接受一次固定 scope hash 的 UUID task 与非空、最多 4000 字符 goal。同内容重放幂等，换 task、scope 或 goal 一律拒绝；回执和 snapshot 只留 task/scope/goal SHA。
- 普通 runtime 路由只转发 guardian 已支持的 start/read/turn/interrupt/tool-result/DELETE；不开放 resume、steer、approval、URL、认证或命令面。所有 request/body/query 形状在进入 guardian 前收紧。
- `permitsTextSession` 与 `permitsTextInput` 只认绑定 task、UUID epoch、`isolated_text_only` 和 Dart 执行器的固定输入格式；partial text 前缀后必须有真实保存文本。关闭先同步封住 task/text/新普通 dispatch，再调用 guardian close；未知 close 返回 503。

验证：`node --test tools/dev_agent_bridge/workbench_product_host_binding.test.mjs`，exit 0、7/7。测试使用纯 fake transport，覆盖单 task 重放/换绑、输入前缀、普通 guardian runtime wire、路由字段与 body 上限、严格 request reader 与关闭后拒绝；不发生真实网络或 host 启动。日志为 `tmp/p6-r7-review/product-session-01/product-host-binding-test.log`。
