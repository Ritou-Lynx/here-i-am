# P6 R7 Product Gateway Transport 交接

`workbench_product_gateway_transport.mjs` 新增受控 ordinary runtime transport 工厂。生产出口固定为 `http://127.0.0.1:47831`，并以 Node `http` 直连、`agent:false` 调用；没有 proxy、redirect、URL 参数、环境读取或认证头入口。

工厂只接受 ConversationGuardian 的 `/experimental/v1/runtime` session create、events、turn、interrupt、tool-call reply、session DELETE 路径。resume、steer、approval、auth 和任意外部 URL 都在连接前拒绝。

请求上限 1MiB（兼容 guardian 最大 tool reply），响应上限 4MiB（兼容 1,000-event bounded read），严格 JSON content type、UTF-8、JSON。deadline 按操作有界：session create、turn 与 tool reply 35 秒，覆盖 `CodexAppServerClient` 的 30 秒请求上限；events 15 秒，DELETE 20 秒。非法 HTTP header、非 2xx、socket、超时及编码失败都会主动 destroy request/response 并只暴露固定 `product_gateway_transport_rejected` 或 `product_gateway_transport_unavailable` code，不保留 raw request/response。

验证：`node --test tools/dev_agent_bridge/workbench_product_gateway_transport.test.mjs`，exit 0、3/3。测试以随机本机合成 HTTP server 和 request 注入复核固定 production options，并验证 malformed header 与 never-end body 在拒绝后 socket 实际关闭；不连接 47831/47841、没有真实 Gateway 或网络调用。日志为 `tmp/p6-r7-review/product-session-01/product-gateway-transport-test.log`。
