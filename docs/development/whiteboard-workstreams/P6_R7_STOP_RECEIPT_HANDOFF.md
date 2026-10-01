# P6 R7 专用文字停止回执账本

`workbench_text_stop_receipt.mjs` 是纯 Node、单生命周期账本。它仅接受宿主已解析并匹配的 start、interrupt-dispatched、`turn/completed`、child-close 与 proxy-drained 事实；没有可由 RPC body 传入的确认布尔值。

v2 receipt 绑定 local session、非空且最多 256 字符的 execution epoch（持久化 queue lease UUID 字符串，保持原值而不规范化）、provider thread、bridge-local turn 与唯一 provider turn。每个 provider 事实均核验该 epoch 与双 turn 映射。只有匹配 terminal 加两个本地关闭事实才可签发；`cancellation_confirmed` 还要求本次 interrupt 已派发且其序号早于 matching `interrupted` terminal。completed/failed、ACK、进程 close 与 prior terminal 均不构成取消成功。

无 turn 只允许显式 `start_not_dispatched` 后签发 `closed_without_turn`；start outcome unknown 始终拒绝 receipt。运行事实和签发路径均为 JavaScript 私有字段/方法，模块私有 WeakSet 品牌和深冻结防止普通对象或公开属性注入伪造回执。

本包未接入 Dart、adapter、profile 或真实 provider；调用者仍须把 host-owned event 解析与持久化接线单独实现。
