# 林埃核心 API v0 契约

> 协议版本：`0.1`
> 传输：Tailscale HTTPS + JSON UTF-8
> 权威节点：私人电脑

## 1. 总体语义

- API base path：`/v1/core`。
- 客户端通过一次性 pairing code 注册，之后使用 device token。
- 普通客户端只能提交用户消息；角色回复、Memory V3 和 Check-in 只由核心产生。
- 所有消息使用客户端生成的 `sync_id` 幂等。重复提交同一内容返回 `duplicate`；同一 `sync_id` 携带不同内容返回 HTTP 409。
- 服务端接受消息后分配单调递增的 `server_sequence`。跨设备显示顺序以此为准，不以客户端时钟为准。
- 同一设备离线消息使用持久化 `origin_sequence` 保持设备内顺序。
- 增量 cursor 是不透明字符串，客户端不得解析或自行构造。
- 消息正文不可原地改写。撤回、删除和编辑后续都以新 change event 表达。

## 2. 认证

除健康检查和配对外，请求头包含：

```http
Authorization: Bearer <device_token>
X-Core-Protocol: 0.1
```

Tailscale 是网络边界，device token 是应用边界。token 只保存在设备安全存储中，不进入配置同步、日志或白板数据。

## 3. 端点

### `GET /v1/core/health`

返回节点身份、协议版本、数据库 schema、服务器时间和能力列表。客户端必须确认 `role=authority`，不能把只读副本误当核心。

### `POST /v1/core/devices/pair`

请求：设备安装 ID、显示名、平台、客户端版本、一次性 pairing code 和能力列表。

响应：device token、初始 cursor、核心 node ID 与协议版本。相同安装 ID 再次配对会轮换 token，不创建第二个逻辑设备。配对码仅可成功使用一次；其哈希在设备注册事务中持久化，服务重启后也不能复用。

### `POST /v1/core/chat/messages`

一次提交 1–100 条离线或在线用户消息。每条包含：

- `sync_id`
- `origin_device_id`
- `origin_sequence`
- `character_id`
- `sender=user`
- `content`
- `created_at_ms`
- `message_type`
- 可选 `asset_refs` 与 `addenda`

响应逐条返回 `accepted` 或 `duplicate`，以及核心分配的 `server_sequence`。提交响应不返回同步 cursor；客户端只有在成功持久化 `GET /changes` 的结果后才能推进自己的 cursor，避免跳过其他设备同时产生的事件。

### `GET /v1/core/changes?cursor=<opaque>&limit=100`

返回 cursor 之后的 change events：

```json
{
  "events": [],
  "next_cursor": "opaque",
  "has_more": false
}
```

首轮 change kind：

- `chat.message.upsert`

后续可增加 `memory.*`、`checkin.*`、`asset.*`、`whiteboard.*`。旧客户端遇到未知 kind 必须忽略内容但仍推进 cursor，避免永久卡住。

### `POST /v1/core/devices/ack`

设备确认已持久化到本地的 cursor。ack 用于监控、清理与换机恢复，不控制 change feed 是否可再次读取；重复 ack 幂等。

## 4. 消息顺序与离线合并

1. 设备本地为每条待发消息生成 UUID `sync_id`。
2. 设备维护严格递增的 `origin_sequence`，写入 outbox 与消息必须在同一事务完成。
3. 核心按到达事务分配 `server_sequence`，同一提交批次按 `origin_sequence` 排序。
4. UI 首次发送可 optimistic 显示；收到 change 后用 `sync_id` 合并，不复制气泡。
5. 客户端时钟只用于展示原始发生时间，不能决定合并先后。

## 5. 幂等与冲突

| 情况 | 结果 |
|---|---|
| 新 `sync_id` | 写入并返回 `accepted` |
| 已存在且规范化内容完全一致 | 不重写，返回 `duplicate` 和原 sequence |
| 已存在但正文、发送者、角色或来源设备不同 | HTTP 409 `immutable_message_conflict` |
| `origin_sequence` 在同一设备重复指向不同 `sync_id` | HTTP 409 `origin_sequence_conflict` |
| 批次超过限制 | HTTP 413 `batch_too_large` |

网络超时后客户端必须用原 `sync_id` 重试，禁止生成新 ID。

## 6. 错误格式

所有非 2xx 响应使用：

```json
{
  "error": {
    "code": "immutable_message_conflict",
    "message": "human readable summary",
    "retryable": false,
    "details": {}
  }
}
```

只有 `retryable=true` 才自动退避重试。401、409 和协议不兼容必须停止重试并提示用户。

## 7. v0 不包含

- 二进制上传与下载；首轮消息仅允许无附件或引用已存在 asset。
- WebSocket 实时推送；客户端先用短轮询，协议稳定后增加事件流。
- Memory V3 表级读写接口。
- 多核心选主与公共互联网暴露。
- 白板节点、权限和媒体锚点接口。

## 8. Dart 对应模型

客户端与未来核心服务共享的 JSON 语义由 `lib/data/services/sync/core_sync_protocol.dart` 固化；测试覆盖 snake_case 序列化、往返解析、未知 change kind 前向兼容和必填字段拒绝。
