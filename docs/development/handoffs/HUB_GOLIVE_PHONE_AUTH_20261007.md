# 手机显式操作授权：候选协议与证据

## 范围

本候选补齐手机“发送记一下”和规划状态按钮的精确请求签名能力。它是 owner 配置的可信交互入口适配器，不是新的远程授权服务；不签发 bearer，不自动授予 scope，不修改领域 mode，不证明任何现役配置已启用。

Core 模块为 `tools/i_core/phone_ui_authorization.mjs`，通过既有 `domainVerifyAuthorization` 注入点使用。`DomainStore.actor` 额外向 verifier 传实际路由的 `domain`，已有 verifier 忽略此新增字段，旧接口保持兼容。正式宿主/会话启动器如何读取受保管配置仍由主窗口接续，不在此处修改启动器或 release 库存。

## 请求绑定

规范串使用现有 Core `canonicalJSON` / Dart `canonicalJson`，UTF-8，HMAC-SHA256；密钥为独立的随机 32 字节，仅在受信入口的安全存储和 owner 侧验证配置中保存。不能使用聊天 token、领域 token、模型给出的字符串或可枚举口令作签名密钥。

签名对象：

```json
{
  "protocol": "i-domain-ui-v1",
  "domain": "captures",
  "binding": {
    "core_instance_id": "<paired-core>",
    "principal_id": "<scoped-principal>",
    "credential_generation": 1,
    "installation_id": "<installation>"
  },
  "intent": "完整最终请求对象，仅移除 authorization_ref"
}
```

以上 intent 行是形状说明，不是可提交的请求。实际签名包含完整 op_id、record id、base_revision、actor、created_at/expires_at、schema、data/patch/provenance 和其他实际提供的字段；缺省与显式 null 保持不同。引用为 `uia1.<key_id>.<base64url-mac>`，不携正文或密钥。

Core 使用当前认证 principal、generation、installation 和配置中的 Core 身份重建对象；只接受 `user_direct + trusted_interactive`，只允许 `captures:create/patch/delete` 与 `plan_items:status`。手机新捕获必须为 phone_quick，capture patch 只改 text，规划状态只允许完成/放弃。scope、来源归属、字段约束、TTL、版本冲突和幂等仍由 Core 原引擎校验。

UI 必须先得到最终 intent，再在同一数据库事务中保存绑定的点击证据、签名和 outbox。签名后不得更改 base 或自动重签；未确认的前驱会使新签名动作明确待处理。重试发送同一已封存请求。签名不是任意模型请求的授权，也不提供 `user_via_agent` 的捷径。

## 已执行的合成证据

- 新增 7 项 Node 测试：固定跨端签名向量；篡改 op/id/base/正文/来源/时间/actor/Core；跨域及跨主体/代次/安装实例；未知 key、错误 key 配置；真实 DomainStore 单一回执、scope/到期/轮换拒绝；持久数据没有签名 secret。
- 与现有 domain_store、domain_http、personal_data_domains、notes importer 合并运行：115 tests / 115 pass / 0 fail / 0 skip。
- 首轮新增夹具缺 Core identity metadata 以及尚未填入固定向量，导致 3 个失败；补齐夹具后复跑上述完整组合通过，未放宽生产校验。
- 另在改动前复验 notes/adoption/personal domains/真实宿主合成 HTTP：36/36。两次重叠测试不相加声称独立覆盖。

## 尚未完成的生产链路

owner 密钥分发/轮换、独立领域凭据签发、正式宿主配置装配、手机 route 迁移与 47862 adoption/Gate仍需独立完成。网页 MCP 的本轮用户授权签发不属于这个手机签名方案，不能靠把 actor 改成 user_direct 绕过。

新的候选 `domain_access` 配对块仅为 App 能力声明；现有 Core pairing 不会自动发出它。重配旧聊天设备会影响既有 token/grant，不能把“重新配对”当作安全的自动部署步骤。实际上线应由主窗口确定独立领域授予与旧聊天身份保全流程。
