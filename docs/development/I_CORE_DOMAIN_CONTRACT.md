# i_core 领域接口约定（W1 首阶段）

> **状态：接口已定稿（2026-10-05 用户确认），实现进行中。** 用户明确回复“确认约定，进入 W1 实现”。本文作为 W1 及下游假服务接口依据；实现、真实副本迁移和线上启用分别验收，不宣称服务已经上线。
>
> 设计依据：[正式 ADR](PERSONAL_DATA_HUB_ADR_20261005.md) §4、§6、§7.2、§11 和[总规划 W1](PERSONAL_DATA_HUB_PLAN_20261005.md)。正式 ADR 的已确认决定优先于旧 W6 草案；本文新增的字段、错误细分、协议常量和冲突裁决均是**本次接口工程选择，已随整份约定获用户确认**。
>
> 源码核对基线：`858497947912940903be12841c8f8026b6fe790f`（W0）；文档复核工作树随后由主窗快进至 happy 整合候选 `6771015178f9b456b38e307362f7bc1a9592fcb7`，补齐正式 ADR/规划。整枝候选随后经 PR #6 普通合入 `v3-lab@6508f1ab5ac2ed57155e95047942875f14fa0c47`，主线树与候选相同。核对文件：[store](../../tools/i_core/i_core_store.mjs)、[server](../../tools/i_core/i_core_server.mjs)、[README](../../tools/i_core/README.md)。实际文件名带 `i_core_` 前缀。既有仓库 schema 5、聊天及 activity 各自已有协议；本轮只读核实运行库为 schema 4；本文不是现役 API 说明。

## 1. 边界与词义

继承 [Authority Root ADR](data-authority/gate1a0/AUTHORITY_ROOT_AND_ACCEPTANCE_ADR.md) 和 [Outbox ADR](data-authority/gate1a0/OUTBOX_CURSOR_RETENTION_RECOVERY_ADR.md) 的核心约束：唯一 Core 接受者、原子回执、按领域 cursor、用户删除优先于审计完整性、旧副本不能复活墓碑。正式 ADR 已明确本批不实现宿主迁移、epoch 接管或新 fencing；这些能力仍为 reserved，不能拿 `core_instance_id` 冒充灾难恢复证明。现有聊天 worker lease 与 activity 防护保持原义。

- `intent` 是未接受请求，手机的待同步覆盖层仅本机可见，可供本机林埃使用，但始终标“未同步”。
- `accepted` 必须对应 Core 在一个事务内持久化的记录、操作元数据、回执和 change；网络成功、影子写入、本地乐观更新均不等于 accepted。
- `duplicate` 只证明复用了一个已有接受结果；不能再次递增 revision、分配 change 或触发副作用。
- `rejected / expired / needs_resolution` 是问题结果，没有 acceptance receipt、没有 canonical change。`submitting` 只属于客户端传输状态。
- W1 只实现通用引擎和合成示例；`captures`、规划、收支、经期、睡眠的业务字段、映射及生产启用归 W2/W7。本文列出它们的权限约束，未注册为可写业务领域。
- 第一批只传文字和 JSON 标量/结构；附件标 `local_only`，不上传字节、本地路径、base64 或可直接访问附件的凭据。W1 无对象库，无 activity 变更，无模型调用、回复、排期或下游业务执行。

## 2. 统一记录与操作账本

### 2.1 Record envelope

所有时间为 UTC RFC3339 字符串，精度毫秒；业务日期由领域 schema 定义，不作为系统排序或权限依据。整数字段限非负安全整数；revision 从 1 起。标识符为不透明字符串：新 `id` 使用 UUID，迁移旧 ID 原值保留，不重编号；命名空间是 `(domain,id)`。新 `op_id` 使用 UUID，与记录 ID 不同。

| 字段 | 约束 |
|---|---|
| `domain`, `schema_version` | 服务端注册的领域和业务 schema 版本；未知版本拒绝。与 Core DB schema 6、协议版本相互独立。 |
| `id`, `revision` | 稳定身份；revision 由 Core 为每次有效接受改动递增。客户端提交 revision 被拒。 |
| `data` | 完整当前业务状态；patch 仅修改注册字段，缺省表示不改，显式 null 只在字段允许时清空。 |
| `field_meta` | 每个注册字段/原子组 `{rev,actor,at,op_id}`；由 Core 写，不能由客户端注入。原子组共用同一次修改元数据。 |
| `created_at`, `updated_at` | Core 时间；首次接受创建和最近一次有效改动时间。重试、判重、ack 不更新时间。 |
| `deleted_at`, `deleted_by`, `merged_into` | 未删除时 null；删除主体为服务端 principal ID；合并指向同领域目标 ID。 |
| `body_state`, `purge_after` | `present / recoverable / purged`；删除正文隔离后为 recoverable，到期或永久删除为 purged。有效记录为 present。 |
| `origin` | Core 根据认证上下文填写 `{principal_id,device_id,created_op_id}`；创建后不允许普通 patch。 |
| `provenance` | `{source,source_refs,import_batch_id}`，source_refs 可用 sync_id/capture_id；原话等敏感值进入可清理正文，不作为永久审计元数据。 |
| `policy_version`, `core_instance_id` | 接受时的策略版本和当前单宿主 Core 身份。沿用已持久化 Core node identity，不额外产生第二身份。 |

墓碑的普通读取形状仅含 `domain,id,revision,deleted_at,merged_into,body_state,policy_version,core_instance_id`，没有 data、原话、field_meta 值、provenance 原文或恢复正文。恢复权限不会自动让普通读取返回删除正文。

### 2.2 Append-only 的精确范围

拟新增通用 `domain_ops` 逻辑账本，键为 `(principal_id,domain,op_id)`；不是为每个业务领域复制一套实现。不可变元数据记录 operation、目标 ID、基准版本、服务端 actor、Core 时间、策略版本、结果、receipt/problem ID 和正文引用。`domain_op_payloads` 单独保存 patch、旧值、冲突候选、授权原话等可清理内容。账本正文引用允许指向已清除数据；不把“只追加”解释成永久保存原文。

- `actor=user_direct/user_via_agent` **且 accepted、确有字段改动**的操作，才是有效 Core 用户修正；被拒、冲突、判重没有产生修正事实。历史查询必须同时筛结果与当前删除状态。重生成按有效 field_meta 和有效修正约束，不把历史被替代值重新覆盖当前值。
- payload 的删除/加密擦除写新的 purge 元数据事件；不改写旧操作决定、回执身份。清理范围包含旧 revision、操作正文、冲突副本、判重缓存、索引、feed/snapshot 缓存、可删除导出及临时文件。
- 为删除后仍能判断重试是否相同，元数据保留服务端密钥 HMAC 的 canonical request digest，不留明文 digest、原文、短文本可枚举 hash 或敏感去重键。密钥不写回执/日志；稳定保留必要校验能力，不声称密码学抹除后还能还原请求。
- 问题元数据和墓碑可长期保留最小 ID/版本/时间/原因；可清正文不得被响应回显、日志、审计导出或异常栈复制成永久第二份。

## 3. 主体、权限与 actor

### 3.1 Scope 检查发生在读取和幂等查找之前

新增 scoped principal 表保存 `principal_id`、token digest、凭据 generation、状态/到期、绑定设备和安装实例、允许 scopes、actor 能力、来源约束及字段权限。token 只在受控本机签发时展示一次；生产签发/轮换由独立授权本机管理流程完成，W1 不开放远程自助授予/提权接口。轮换立即使旧 generation 失效，不能靠旧 op_id 查询回执。新 token 保持 principal_id 时可以在新权限范围内查询自己的旧结果。

所有端点依次校验认证、generation/有效期、绑定、Core 身份、domain 注册状态、scope、对象/操作归属，再查结果和正文。拒绝时不返回存在性、正文、duplicate_of、最新记录或其他主体的回执。查无资源与无对象权限均为不泄露存在性的 `404 not_found`；无领域 scope 为 `403 scope_forbidden`。

Scope 形式为 `<domain>:<action>`。动作 `read/create/patch/status/delete/ack` 继承 ADR；本文提议显式增加 `restore/merge/purge`，不由 patch 隐式授予。`read` 允许本权限视图的 records、changes、snapshot 和消费 ack；**不**意味着 captures 处理结果的 `ack` 写权限。`GET ops/<op_id>` 只允许同一 principal，且当前仍拥有原操作对应 scope/来源约束；不会授予领域 read。

| 主体/情形 | 框架必须强制的边界 |
|---|---|
| 旧普通设备 token | 保留既有聊天读、用户追加、聊天 ack；没有任何新领域权限，也不自动授予手机 companion 例外。 |
| 经本机登记的手机 | 新领域按表显式授予；captures 编辑/删除按创建设备归属；规划读权限可覆盖三域，但状态写仅 `plan_items:status`。 |
| Codex planner | captures:read/ack，规划结构权限；无 chat、cycle 或 ledger 明细 read。 |
| organizer | 可获 captures:read/ack 和所处理业务域权限；只能写 dispositions.organizer。planner 只能写 dispositions.planner。 |
| 外部网页前端 | captures 新建/修改/删除受 principal 来源归属限制；当前 external-frontend 的聊天 feed/ack 禁止不因本契约解除。其他读取还要经过出站策略。 |
| 看板/规划的收支汇总 | 使用单独的只读 `ledger_summary` 权限域，后续实现受限固定周汇总；不得把 `ledger:read` 搭配客户端过滤作为替代。明细 ID、交易原话、任意钻取/查询都不可返回。W1 不实现该领域。 |
| 经期 | 仅显式授权手机主体；其余主体无 cycle scope，汇总、错误和跨域引用也不能旁路读取。 |

`plan:status` 是 ADR 的产品简称，协议里解析为 `plan_items:status`，不代表 wildcard。W2 应注册状态字段白名单 `status`，值仅“完成/不做了”对应的标准枚举；不能附带标题、截止、队列顺序、容量、提醒时间或跨域写入。W1 的合成例子以同样机制验证，业务枚举由 W2 定稿。

captures 的 `ack` 指**处理结果写入**：使用 ops 的 `kind=ack_capture`，只能提交认证 principal 绑定处理者的整组 `dispositions.<processor>`；不可改原话、来源、owner、另一个处理者，也不可凭 outputs 获得目标域权限。`POST /ack` 始终只确认同步 cursor，二者不会共用存储或权限语义。

### 3.2 actor 不是任意客户端声明

| actor / 等级 | Core 接受条件 |
|---|---|
| user_direct / 3 | 认证主体被登记为受信交互入口，具有相应字段权限，提交经该入口绑定的用户动作证据。自动化 worker token 无此能力。 |
| user_via_agent / 3 | 有受控入口验证的用户本轮明确授权引用，绑定当前 principal、操作/目标/字段；可用已接受的用户消息 sync_id，或离线交互入口保存的经绑定授权证据。只有 sync_id 字符串或消息存在不构成授权。 |
| import / 2 | 认证主体获指定来源/批次导入能力；不能顺带声称 user_direct。历史 userCorrected 回填仅由授权迁移映射单独证明，普通 API 不支持冒充回填。 |
| agent_inferred / 1 | 自动处理默认；来源/任务范围仍须允许。 |

请求 `actor` 只是声明，服务端按凭据能力和证据验证并持久化有效 actor；不匹配返回 `actor_not_authorized`，不静默降级或升权。服务器不能通过文本推断用户同意。可信客户端是受限信任边界，已被攻陷的用户入口不能由一个 JSON 字段解决；授权签发和证据适配器必须在代码验收中有拒绝测试。W1 合成夹具验证边界，未具备授权验证器的生产入口默认只能提交其已验证等级。`authorization_ref` 是该验证器可解析的短引用，绑定已持久化授权记录；新建这种记录不在通用 ops 里，不接受将任意请求正文当作授权证据。

## 4. 版本、冲突、删除与判重

### 4.1 原子修改与字段组

`create` 要求 base_revision=0、ID 从未存在；`patch/status/ack_capture` 要求 1 ≤ base_revision ≤ 当前 revision。未来基准拒绝 `invalid_base`。注册 schema 把相互关联字段组成不重叠原子组；组内任一字段被改视为整组变化，提交修改组须给全组值，缺失为 `incomplete_field_group`。未分组字段视为单字段组。

**顺序是锁定检查 → 基准检查 → 冲突矩阵**，因此“同版本直接接受”不能绕过用户修正锁。

| 当前目标组的状态 | 此次处理 |
|---|---|
| 最后有效修改为用户，来者为 import 或 agent_inferred | `rejected/user_locked`，即使 base 为最新；用户修改继续锁定整个组。这里将 import 也视为不得盖掉用户修正的低等级，属本次确认的细化。 |
| 本组 last_rev ≤ base_revision | 接受本组；无关组的新 revision 不制造冲突。 |
| 并发；来者等级高 | 接受新组值；被替代历史有 superseded 元数据，不删除审计身份。 |
| 并发；来者等级低 | `rejected/superseded`；没有 canonical change。 |
| 并发；双方等级 3 | `needs_resolution/user_conflict`，当前值保持；需新的明确用户解决 intent。 |
| 并发；双方等级相同且低于 3 | `rejected/stale_base`；执行者读取允许的最新版本后重算，使用新 op_id。 |

**提议按单 op 全收或全拒**：一个 op 内任意组失败，则所有组不变；问题列出有权限查看的冲突组。不产生混合成功的隐式部分 patch。相同值且所有规则通过时返回 `duplicate`，绑定当前有效记录的已有 acceptance receipt，`reason=no_change`，无新 revision/change；该请求有独立判定元数据。新用户确认若需要建立用户锁，应使用 `patch` 并声明 `confirm_fields`，限用户 actor，视为元数据有效变化而接受新 revision。

### 4.2 删除基准的冲突裁决（随接口确认）

正式 ADR §4.3.8 要求删除/恢复/合并旧基准冲突，§4.4 又要求“用户删除与 AI 修改并发时删除赢”。提议以窄例外消除歧义：

1. delete 基准等于当前版本，按权限接受；默认仅用户 actor 可删除，自动清理只能走有范围的内部执行器。
2. 用户 delete 基准落后时，仅当 Core 能证明 base 之后**所有中间操作都是 agent_inferred 的普通 patch**、目标始终存活且没有用户确认/结构操作，允许删除覆盖这些 AI patch。基准历史缺失、存在 import 或用户变更、delete/restore/merge、归属变化，一律 `needs_resolution/stale_delete`。不采用客户端时间较新作为证明。
3. AI 的 stale delete 一律 `rejected/stale_base`；合成权限专用夹具可验证，生产不因框架存在而获得自动删权。
4. restore、merge 和 purge 均严格要求最新基准，无上述例外。明确用户选择最新版本后以新 op_id 处理；旧冲突 op 保持原决定。

### 4.3 删除、恢复和正文清理

- 普通 delete 事务递增 revision、写墓碑/回执/change，并隔离正文。records 普通读取返回 `410 deleted_target` 附最小墓碑；changes/snapshot 只返回最小墓碑。任何 patch/status/处理 ack 均拒绝 deleted_target。
- 默认 `purge_after = deleted_at + 30 天`；`now < purge_after` 且 body_state=recoverable 才能 restore。到期边界 `now >= purge_after` 拒绝 `restore_window_expired`，不依赖后台 job 是否及时跑完。
- 来源为迁入 i_remember/claude_web 且声明即时策略的记录，以及用户 `permanent=true` 删除，接受事务中立即隔离并清除所有**在线可读**正文副本，设 body_state=purged；原始存储页/WAL/离线备份的物理回收单独追踪。不得把“读取已拒绝”说成所有磁盘比特已抹除。
- 恢复不是创建：保持原 ID，revision+1，清 deleted_at/deleted_by/merged_into，恢复有效 field_meta 及用户锁。合并来源不允许普通 restore，返回 `merge_restore_unsupported`，避免恢复引用拓扑产生歧义。
- 到期清理作为 Core 内部幂等 purge 操作递增 revision、发最小墓碑 change；元数据记录 job_id、范围、阶段、失败/重试与结果。已 purged 再跑无新 revision。原删除之后的新变更也不得重新带出旧 data。
- 外部 `kind=purge` 只允许已验证用户 actor、同时具有该目标 delete/purge 权限且最新基准的请求，目标必须已有墓碑。活记录返回 `409 purge_target_alive`，须先显式 `delete permanent=true`；不得从 purge 隐式删除。recoverable 墓碑的首次永久清理在接受事务内清在线正文、body_state=purged、revision+1、写无正文 receipt/change；Core 内部到期执行器有独立受控能力，不使用外部 token。
- 已 purged 墓碑的新 purge 在当前权限/基准检查后返回 `duplicate/already_purged`，绑定最后有效清理（或立即删除）的无正文 receipt，无新 revision/change；同 op 精确重试复用原结果。该结果只证明在线正文生命周期，不证明离线备份或存储页物理清理完成。frozen/off 下外部 purge 仍被门控，内部隐私维护继续。
- 墓碑 ID/revision 永久保留；旧 ID 的 create 始终 `id_exists`，任何旧正文、旧备份或旧 outbox 不能作为重新创建许可。
- 对已删目标重发旧 create/patch/merge 先拒绝 deleted_target，不能返回历史正文或借 duplicate 复活；查询旧 op 仍可得到无正文历史结果和 `target_state=deleted`。精确重发该目标的删除或 purge op 可以返回原无正文 receipt；新 purge 仅按上方墓碑清理规则处理，不再带出正文。
- 跨域派生删除不在源域事务里冒充完成：源删除事务只登记不含正文的 `cascade_pending` 引用；有独立目标域权限的执行器提交各自 intent，目标有用户改动则保留并待用户决定。源 receipt 只证明源删除，不证明 cascade。W1 不执行该业务流程。
- 新备份排除已删除正文；已有离线不可变备份不能保证即时清除，按版本化备份保留策略到期清理。恢复必须先核对最新可验证墓碑/删除账本，缺失则 needs_resolution；W1 不提供把备份激活为服务的捷径。

### 4.4 幂等、语义判重与合并

canonical request 为严格校验后的完整语义字段（含 actor 声明/证据引用、base、timestamps、schema、op kind/data、reference_updates 全集合；不含传输 token）。使用稳定 JSON canonicalization，明确区分 null 与缺省，不改变原文 Unicode/空白。重复 op_id 同内容复用原结果，不同内容 `409 idempotency_conflict`；重试不得刷新 created_at/expires_at 或生成新 op_id。相同 ID 不同 op 的 create 返回 id_exists，不作为默认 upsert。

领域去重钩子只在权限允许的候选集合和未删除记录上工作。用户手工 user_direct 新建命中照收，回 `possible_duplicate`；organizer/工具/import 新建命中不新建，回 `duplicate_of` + 已有记录的 receipt。没有目标 read 权限时只返回允许的最小回执，不返回记录正文；无法安全披露目标身份时返回不含身份的 `needs_resolution/duplicate_restricted`，不能泄露另一主体的记录。

显式 merge 必须由用户 actor 发起，具备 source/target 的 merge、patch、delete 权限及可见性，限同领域；请求提供 source/target 最新 base revisions 和最终 target data，Core 不猜字段取舍。

- `reference_updates` 必须显式列出会被改写的其他同域有效记录 `{id,base_revision,patch}`；没有引用时传空数组。Core 从注册的引用索引验证集合完整、无重复、无循环；每个 patch 只能把声明的 source 引用改成 target，并满足字段组完整性，不能借 merge 改无关内容。
- 所有引用记录进入同一事务写集合：逐条校验当前对象可见性、patch/merge 与字段授权、用户授权证据覆盖的目标/字段、最新基准和用户锁规则。隐含改写未授权第三条记录被禁止；被锁字段只能由已验证用户 actor 明确覆盖。隐藏引用、缺失引用或并发基准使整单 `needs_resolution/reference_conflict`；请求本身合法、但验证后发现完整引用集合无法容纳于一个有界 op 时为 `409 needs_resolution/merge_too_large`。实际收到的请求体超过 MAX_OP_BYTES 始终先按 `413 payload_too_large` 预检拒绝，不存终态。均不返回受限引用 ID、数量或正文，不拆成部分成功。
- 接受事务原子更新 target、为 source 写 merged_into 墓碑并改引用。所有被有效改动的记录各自 revision+1、更新对应 field_meta、各发一条状态 change；一份 receipt.targets 与 change_sequences 绑定整个写集合，不能只绑定 source/target。派生引用索引仅为可重建投影，不形成另一权威记录。
- 跨域引用留 cascade_pending 后续逐域处理；不宣称跨域原子合并。迁移/未知引用完整性不能证明时拒绝，不能悄悄丢引用。

## 5. 协议及全部端点

### 5.1 通用结构

新增接口协议 `domain_protocol_version=1`；JSON 严格拒绝未知写字段。认证使用 Bearer；响应无 token/密钥。请求带 `core_instance_id`，必须等于已认证配对所得 Core 身份。新领域请求中的 `epoch/fencing_token` 只接受缺省/null，非空为 `unsupported_authority_feature`；receipt 明示 `authority_mode=single_host`、`epoch=null`。这是 W1 有限实现，不是完整 Gate 1A-3 接管能力。

POST ops 单次恰好一条 intent，无批量半成功。请求公共形状：

```json
{
  "domain_protocol_version": 1,
  "core_instance_id": "core-fixture",
  "op_id": "00000000-0000-4000-8000-000000000001",
  "schema_version": 1,
  "kind": "patch",
  "id": "record-fixture",
  "base_revision": 2,
  "created_at": "2026-10-05T00:00:00.000Z",
  "expires_at": "2026-12-04T00:00:00.000Z",
  "actor": "agent_inferred",
  "authorization_ref": null,
  "patch": { "title": "合成示例" }
}
```

所有示例均为合成值。kind 的互斥字段：create 用 `data,provenance`（均必填，无来源引用用空数组/空值）；patch 用 `patch,confirm_fields?`；status 用 `patch`；ack_capture 用 `processor,disposition`；delete 用 `permanent`（默认 false）；restore 无正文；purge 无正文；merge 用 `target_id,target_base_revision,target_data,reference_updates`。id 是 source；base_revision 对应 source。与 kind 无关字段一律 invalid_request。

结果统一 `{domain_protocol_version,domain,op_id,outcome,reason,receipt,problem,record?,duplicate_of?,possible_duplicate?}`。outcome 为 accepted/duplicate/rejected/expired/needs_resolution，receipt 与 problem 互斥；影子例外见 §7。`record` 仅在当前 read/归属/出站政策允许且未删时附带。write-only caller 不通过写回执获得 read 权限。

acceptance receipt 为 `{receipt_id,core_instance_id,authority_mode,epoch,domain,accepted_op_id,principal_id,accepted_at,policy_version,targets:[{id,revision}],change_sequences,receipt_auth}`。receipt_auth 为服务端认证标签；不含正文或凭据。新 op 的语义 duplicate 外层 op_id 是新请求，receipt 的 accepted_op_id 保持原接受操作；不可伪装两次接受。change_sequences 是审计顺序，不是消费 cursor，不得据此 ack 或推进本地副本。

problem 为 `{problem_id,code,retryable,action,conflicting_groups?}`；授权可见时额外附最新 record。无接受事务不发 receipt。认证/协议/限流等预检失败可以只有 error，不能伪造已存 op 结果。

### 5.2 路由表

以下前缀均为 `/v1/core/domains/<domain>`；URL 单段标识符必须编码并严格校验。

| Method / path | 输入与权限 | 成功/边界返回 |
|---|---|---|
| `POST /ops` | §5.1 intent；kind 对应 scope/字段/actor 权限 | 首次 accepted 为 201；duplicate 为 200；冲突/拒绝/过期按 §5.3。记录、receipt、change、幂等结果同事务。 |
| `GET /ops/<op_id>` | 当前 principal 自己的 op；当前仍有相应 scope；query `core_instance_id` | 200 `{found:true,result,target_state}`，只回最小历史结果，不回提交正文；unknown 为 404 op_not_found。超时先查它，unknown 才按原 key 重试。别的 principal 不可查询。 |
| `GET /records/<id>` | domain:read + 对象来源约束；query `core_instance_id` | 200 `{record,policy_version}`；未知/无对象权 404；已删 410 + 最小 tombstone；不返回恢复正文。 |
| `GET /changes` | domain:read；query `core_instance_id,cursor,limit?` | 200 `{records,next_cursor,has_more,retained_watermark,policy_version}`；records 为完整最新状态/墓碑。cursor 缺失或失效返回 resync_required，不从最新跳过。 |
| `GET /snapshot` | domain:read；query `core_instance_id,snapshot_token?,page_token?,limit?` | 首次创建认证快照；每页 `{snapshot_id,records,page_digest,next_page_token,has_more,manifest}`。最后一页 manifest 附完整集合 digest 与 base_cursor，见 §6。 |
| `POST /ack` | domain:read + 绑定消费 installation；body `{domain_protocol_version,core_instance_id,cursor,snapshot_id?}` | 200 `{ack_cursor,advanced}`；单调确认已发给同消费者且认证的 cursor；重复/更旧 ack 不倒退；不能 ack 未发位置、别域或别安装 cursor。 |

GET 协议通过 `X-I-Core-Domain-Protocol: 1` 声明。分页 limit 默认 100、最大 500；超限为 invalid_request，不静默改变写入语义。API 不提供无 scope 的全领域列举、任意 SQL、聚合查询或全量审计正文下载。

### 5.3 错误与客户端处理

| HTTP / code | 持久结果/客户端动作 |
|---|---|
| 400 invalid_request / invalid_base / incomplete_field_group / unsupported_authority_feature | rejected；修正请求必须新 op_id。未通过语法预检者无持久结果。 |
| 401 unauthenticated / credential_expired | 不查账本；本地保留，待重新认证，不循环重发。 |
| 403 scope_forbidden / actor_not_authorized / origin_device_mismatch | rejected 或本地 needs_resolution；无存在性/内容回显，不自动换高权限 token。 |
| 409 idempotency_conflict / stale_base / user_locked / superseded / id_exists / purge_target_alive | 原请求终态问题；原记录不变。idempotency_conflict 不改原 key 的既有结果。 |
| 409 user_conflict / stale_delete / duplicate_restricted / reference_conflict / merge_too_large | needs_resolution；保留待处理；用户/授权执行者以新 intent 解决，不自动选择值。 |
| 409 resync_required | 读恢复流程，含无正文 reason、domain、Core identity、retained_watermark、snapshot 路由；不是写入已拒终态。 |
| 410 intent_expired / deleted_target / restore_window_expired | expired 或 rejected；查询原 op 可区分此前已接受与从未接受；不自动刷新期限或复活。 |
| 413 payload_too_large / batch_not_supported | 本地保留并提示，未接受；不能静默截断正文。 |
| 429 domain_capacity_exceeded；本地 outbox_full | 不写终态业务结果，pending 保留，用户处理容量；绝不挤掉旧 pending。 |
| 503 domain_off / domain_frozen / schema_not_ready | 可重试的传输/门控拒绝，未接受且不占终态 op_id；本地仍 pending。 |
| 5xx / timeout / connection_lost | 结果未知，保留原请求，先查 op 结果；不得假定未提交并生成新 key。 |

已有 accepted/terminal op 查询先通过权限与删除安全检查再返回历史结果；TTL 不能把已经接受的同一操作改成 expired。首次未接受请求才检查到期。领域冻结允许查询自己已有结果，故超时重试不被迫重新提交。

## 6. Cursor、快照、保留与 outbox 常量

### 6.1 状态型变更流

新 cursor 绑定 `(core_instance_id,domain,principal_id,credential_generation,installation_id,view_policy_version,sequence)`，服务端认证、客户端不解析；与 chat/activity cursor 不互用。权限缩小或 token generation 改变后重新建立受限 snapshot，旧 cursor 不可揭示被撤销内容。

每个有效状态变化有独立领域 sequence。读取在同一一致性读事务内取得 high watermark 和记录最新状态；按最新改变的 sequence 升序发状态（可合并中间 revision），不会把操作 patch 当事件给客户端重做。下一页从 next_cursor 继续；没有可见条目也可推进到该次安全扫描位置，不暴露其他权限视图的数据/计数。以 record revision 幂等应用，旧 revision 丢弃。同 ID 已有更高墓碑时旧有效状态不可覆盖。

retained_watermark 定义为“已删除增量历史的最高 sequence”；cursor position 小于它必须 resync，相等可继续。水位只单调前移，并留旧/新值、policy_version、purge job/receipt 等最小审计；不能以全局 chat sequence 替代领域水位。

快照是受 scope/来源/出站策略过滤的当前完整副本，包含墓碑，排除删除正文；不是历史档案。manifest 绑定 snapshot_id、Core 身份、domain、安装/主体/generation、schema/policy 版本、截止时间、集合 digest、base watermark 和 base_cursor，使用服务端 HMAC 认证 opaque capability，经认证 TLS 传输并由 Core 校验；客户端核对绑定字段、期限与逐页/整体 digest，不把普通 digest 当服务器身份认证。

分页固定同一个 snapshot_id/read cut，不能每页读取漂移的实时表拼凑快照。快照生成后遇到删除/正文 purge 或权限收紧，所有可能保有旧正文的未完成快照失效并清理，后续页返回 resync_required；客户端丢弃暂存快照重新取。完整快照校验后，客户端一个事务替换该领域 canonical 副本、保存 manifest/base_cursor；**不清 outbox 和本机待同步覆盖层**，重叠 tombstone intent 转待解决。事务成功才 ack；崩溃、缺页、校验失败保留旧副本和 cursor，不报告同步完成。

### 6.2 版本化默认值

策略标识拟为 `domain-policy-v1`。60 天 intent TTL、7 天提醒已在正式 ADR 确认；其余精确值是本文本次确认的实现默认值，后续变更必须发布新策略版本，不能缩短既有请求已承诺期限。

| 常量 | 候选值与边界 |
|---|---|
| `USER_INTENT_TTL` | 60 × 24h；所有 W1 示例 actor 统一最大 60 天，业务自动任务未来可收紧。expires_at ≤ created_at+60d；Core now ≥ expires_at 为到期。 |
| `PENDING_REMINDER_AGE` | 7 × 24h；本机提示，不唤起模型、不发送外部消息、不推断用户状态。 |
| `CLIENT_FUTURE_SKEW` | 5 分钟；created_at 超过 Core now+5m 拒绝 invalid_request，不能靠未来时间延长 TTL。Core 用自身时钟判断 expiry。 |
| `OUTBOX_MAX_ITEMS/BYTES` | 每设备所有领域合计 5000 条或 50,000,000 字节先到为限；计未终态完整序列化请求，不含附件。终态元数据另有保留账本，不能占满后偷偷删除 pending。 |
| `MAX_OP_BYTES` | UTF-8 请求体 262,144 字节；一个请求一条 op，merge 也计整个请求。正文加 envelope 超限即拒。 |
| `PAGE_LIMIT/MAX_RESPONSE_BYTES` | 100/500 条；单页最多 2,097,152 字节，按条目边界分页；最大单条由 MAX_OP_BYTES 及领域记录上限 262,144 字节共同限制。 |
| `RETRY_BACKOFF` | 2s 起、翻倍、上限 5min、±20% jitter；仅临时可重试错误，遵守 Retry-After；返回前台可触发一次检查，不无限高频轮询。 |
| `FEED_MIN_RETENTION/ACTIVE_CONSUMER` | 增量至少 60 天；90 天内有成功 ack 的消费者视为活跃。超过 60 天且所有活跃消费者已 ack 才可常规清理；无活跃消费者可清理到 60 天边界。未知 ack 状态延缓。 |
| `SNAPSHOT_TTL` | 15 分钟；失效重建，不允许拼接两个快照。未完成快照不无限钉住保留水位。 |
| `DOMAIN_BODY_QUOTA/SNAPSHOT_QUOTA` | 每域在线可清正文总计 268,435,456 字节，每主体最多 4 个未完成快照；墓碑和最小审计元数据不被挤掉。到限返回 domain_capacity_exceeded，已过期快照可回收，未过期快照不可悄悄失效换空间。默认值已随接口确认，后续容量实测如需调整必须发布新策略版本。 |
| `DELETE_RESTORE_WINDOW` | 默认 30 × 24h；即时删除策略例外。 |
| `TERMINAL_PRIVATE_PAYLOAD_RETENTION` | rejected/expired/needs_resolution 正文至原 expires_at+30 天，或关联目标 purge/明确删除，以最早者为准；正文到期后保留无正文问题元数据，不假装仍能恢复候选。有效记录的已接受操作正文以该记录生命周期为上限。 |
| `OFFLINE_BACKUP_RETENTION` | 候选最长 30 天、加密本机保存、清理有回执；它不能修改既有 activity 的备份限制或原始证据期限。未接入此策略的既有备份不得宣称已经受管。 |

删除隐私清理优先于普通 feed 保留和慢客户端 ack：旧内容去掉，只留状态/墓碑；因此形成历史缺口时主动提升安全水位并返回 resync_required，而不是保留隐私正文等消费者。容量达到服务端限制时显式拒收新请求并保留现有状态，不以隐式截断 feed 换可用性。

客户端同记录串行：后一操作须以前一已接受 revision 为基准；不确定删除不得被后续修改越过。断网和崩溃不清 pending，提交超时先查结果。终态结果与 outbox 转终态同一事务，记录/state 与 cursor 同一事务；过期项目只能由用户明确决定生成新 intent，不能自动换 key 续命。

## 7. 领域开关与有限权限视图

配置状态由受控本机管理流程设置，普通领域 token 无权切换。影子专用主体额外声明 `<domain>:shadow_read` / `<domain>:shadow_write`；它们不蕴含生产 read/create/patch 等权限，生产 scope 也不能读取影子。每个域同时只有一个生产接受者；一次只切一个真实领域。W1 所有业务领域默认 off。

| 模式 | ops 与读行为 | 接受和恢复边界 |
|---|---|---|
| off | 不接收新 intent，不提供数据读取；认证后的请求为 domain_off。仅同主体最小旧 op 结果可查。 | 不改变手机原路径，无隐式启用。 |
| shadow | 仅授权影子导入/对账主体可写独立影子命名空间及读对账结果；普通 token 无 records/changes/snapshot/影子结果可见性。 | 写入返回 `202 {transport_state:shadow_staged,shadow_result_id}`，无 accepted/outcome、无 production receipt。专用影子 outbox 可记录 staged；用户 outbox 仍 pending，不能显示“已同步到权威”。 |
| frozen | 新写返回 domain_frozen、pending 保留；查询旧结果和读取最终副本允许，但继承冻结前可见性。 | 从 shadow 冻结仍仅对账可读；从 authoritative 冻结仍是既有权威只读。不因 frozen 暴露影子或切接受者。隐私隔离/到期 purge 内部维护继续，普通 restore/patch 不可写。 |
| authoritative | 通过全部检查才接受；按 scope 发当前记录/feed/snapshot。 | 从 shadow 进入必须经冻结、排空、最终对账、备份与授权切换；重新生成生产 snapshot/cursor，影子回执永不直接升级为接受凭证。 |

影子独立 ID 空间允许保留相同业务 ID，但不与 production op 幂等账本混用。`GET ops/<op_id>` 在影子凭据下只能查 `{transport_state:shadow_staged,shadow_result_id}`，普通主体查不到。切换时接受记录与新生产 receipt 由受控迁移操作生成，不给客户端自行改 mode 的通道。影子退回 off 不删除手机数据；权威切换后优先向前修，退回旧路径须另授权、逐域重建，不能整库恢复抹掉别域新写入。

## 8. 手机 companion 的唯一放宽

现有 `POST /v1/core/chat/messages` 路由及 chat schema/cursor 不改为 domain 接口。新增放宽只对**本机授权登记的手机设备**启用 `chat:append_companion`，不因客户端自报 platform 或 capability 生效：

1. origin_device_id 必须等于认证设备；character_id 必须等于 Core 登记的唯一主角色。
2. 携带 companion 的手机请求必须省略 `request_companion_reply` 字段，连 false 也拒绝；从生产手机执行配置发来的请求不能触发 Core reply job。Core 中手机唯一执行的角色禁止同时启用电脑自动回复发布。
3. companion 是手机已生成消息的同步，不调用模型、不建立待回复任务、不生成第二回复。同 sync_id 内容冲突、origin_sequence 唯一性、批次事务和旧聊天幂等规则保持。
4. 未授予例外的普通设备仍只能 append_user；持新领域令牌不代表能用 chat 端点。
5. external-frontend 继续要求 `frontend:<name>` 与 external-frontend platform 同时成立，不能切换设备角色、冒充其他 origin；保持现有 finished-turn 追加与 request_companion_reply=true 拒绝，并保持直接 chat changes/ack 403。出站策略读取由专门读取层处理，不借本契约开放原 feed。
6. 电脑 worker 保持 shadow；现有租约不因此授予生产 publish 权限。W1 不实现第二执行者接管。

## 9. Schema 5 → 6、恢复与宿主边界

候选新增表仅服务本协议：domain_registry、domain_records、domain_ops、domain_op_payloads、domain_receipts、domain_changes、domain_principals/scopes、domain_consumer_acks、domain_snapshots、domain_purge_jobs、domain_schema_migrations。具体 SQL 在代码阶段评审；不改已有 chat/activity 表布局或语义，仅事务更新 core_metadata.schema_version 为 6。用户修正不复制成新的竞争事实表。

迁移由显式离线入口执行；服务启动保留 schema 5 的既有聊天能力，新领域返回 schema_not_ready；不悄悄在常驻服务中升级。步骤为：证实全 Core 停写 → schema/完整性和已有 recovery 约束预检 → 自动创建独立加密离线备份及 manifest → 验证备份可读/完整、记录哈希 → 单一事务建表/索引并更新版本 → 完整性与旧表校验 → 才允许启动候选。任何失败不前移 schema marker；不覆盖现有备份、不读取日志正文作为迁移报告。

现有 whole-Core 备份是 backup_read_only 验证产物，**不能直接激活为可写 Core**；迁移预备份不得放宽其限制。无备份/失败/恢复地板不明时停止迁移。真实 schema 5 副本验证另行获用户授权，只用本机副本、只报告结构/计数与结果，不上传/提交真实数据。

回退分两种：尚无 schema 6 领域接受/影子/凭据/操作内容时，可在停服务后由离线检查器证明新表为空，再事务撤销新表和 schema marker；已产生新内容则禁止仅降版本或覆盖整库，先 frozen、保留数据、向前修。跨版本导出/逐域回建须有独立方案/副本演练/授权。恢复整库、搬路径、换机器、双 Core 或备份重新激活均不在 W1。

Core 路径实现使用跨平台 Node/SQLite API；沿用 `I_CORE_DATABASE`、`I_CORE_HOST`、`I_CORE_PORT`、`I_CORE_CERT`、`I_CORE_KEY`，备份目录由配置决定，不硬编码盘符/注册表/Windows 任务。环境变量可配置不等于授权公开监听；默认本机监听与已有 TLS 边界保持。

最小 `example` 域仅存在于显式合成测试配置，专用临时根/测试 principal，仅 example scope；正常服务默认不注册，无生产业务 schema、数据或令牌。不能用 example 绕过未开放 captures/ledger/cycle；真实业务每个另按 W2/W7 注册和授权。

## 10. 有限验收矩阵（W1 服务端候选已验证，客户端与真实副本边界另列）

候选尚未提交；主窗以基线 commit、源码 SHA-256、测试名称和实际结果保存本机证据，见 [实现交接](handoffs/W1_DOMAIN_IMPLEMENTATION_20261005.md)。W1 已运行服务端合成专项；A18 的客户端原子替换和 A20 的客户端 A/B/E/F 阶段属于 W4，当前为 partial，未实现或验收。合成通过不代表真实数据迁移/手机/部署完成。只对本范围做专项与必要相邻回归，不以无限扩大测试替代判定。

| ID | 输入/故障 | 可判定的期望 |
|---|---|---|
| A01 | 当前版本 patch；未来基准；不同字段并发 | 正常一次 revision；未来基准拒；无关字段均保留。 |
| A02 | 同组金额/币种类合成字段并发、缺半组 | 整组裁决；缺项拒；不产生混合金额。 |
| A03 | 用户/import/AI 各等级两两并发；两用户；两 AI | 严格符合 §4.1；冲突记录零改动、无 ghost receipt。 |
| A04 | AI/import 基于最新版本改用户锁；伪造 actor/sync_id | user_locked 或 actor_not_authorized；不能改值/锁。 |
| A05 | 多组请求其中一组冲突；confirm_fields 同值用户确认 | 前者全部不变；后者建立用户锁并且只加一次 revision。 |
| A06 | 同 op 同内容、不同内容；同 ID 新 op 创建；删除后重放 | 同回执零重复；不同内容 conflict；墓碑不可复活；不回旧正文。 |
| A07 | Core 提交后丢响应，查 op；不同主体查 op；token 轮换 | 查到唯一结果；无权查不到；旧 token 在 lookup 前拒绝。 |
| A08 | 用户 stale delete 中间仅 AI patch／含 import／含用户修改 | 窄例外删除胜；后两项 needs_resolution；严格绑定基准历史。 |
| A09 | 删后 patch；29 天 restore；30 天临界恢复；即时永久删 | patch 拒；合法恢复同 ID；临界拒；立即无在线正文与审计副本。 |
| A10 | 普通删除到期 purge、job 重跑、外部 purge 活记录/恢复期墓碑/已purged、旧 snapshot/page/feed | 活记录拒；墓碑限用户+双scope+最新base；有效清理一次revision，重跑零改动；正文全范围不可读，旧快照失效。 |
| A11 | AI/import 去重；user_direct 重复；不可见重复候选 | 不再创建；手动照收+提示；不泄露受限目标。 |
| A12 | merge 基准陈旧/跨域/第三条引用未授权或并发/隐藏或缺失引用/有效合并 | 不安全集合整单拒且不泄露；有效全写集合逐条revision/change并进入同一receipt；引用客户端能收到更新。 |
| A13 | status 夹带标题；planner ack 改原话/organizer 分支 | 全拒，原文与另一处理者不变；合法不同处理者并发互不覆盖。 |
| A14 | 旧聊天 token、新领域 token、summary-only、非手机 cycle | 权限分离；summary 不可读 ledger records/feed/snapshot/ops；经期无越权。 |
| A15 | off→shadow→frozen→authoritative，各角色逐路由探测 | 各状态按 §7；影子内容和结果不泄露；影子没有 production accepted。 |
| A16 | 跨域/损坏/缺失/旧 generation cursor，低于/等于水位 | 前者 resync；水位相等可增量；不默默跳到最新。 |
| A17 | 分页期间并发写/删除；乱序与重复状态；ack 未发位置 | 同快照一致或明确失效；revision 幂等；非法 ack 不前移。 |
| A18 | snapshot 缺页/digest 损坏/到期/替换事务崩溃 | 旧副本+cursor 保留；outbox 不丢；完整认证后原子替换并 ack。 |
| A19 | 60 天边界/未来时间/7 天未同步；5000 条/50MB/超大单条 | expired 边界正确；不续命；提醒无外部副作用；容量拒新保旧。 |
| A20 | A–F 排队/预检/接受/响应/终态保存/投影六处崩溃 | 只出现完整旧态或完整新态；无丢 pending、ghost accepted 或 cursor 超前。 |
| A21 | 授权手机 companion 正常/错 origin/非主角色/带 reply 字段 | 正常持久化一次；三种异常拒；reply job 增量为零。 |
| A22 | external-frontend 冒充普通设备、读 chat feed/ack、触发 reply | 既有拒绝不退化；普通未授权设备仍不能写 companion。 |
| A23 | schema 5 合成库升级/备份失败/中途故障/重启；空与非空回退 | 旧表不变；失败不前移；重启耐久；空可受控回退、非空禁止降级。 |
| A24 | 缺删除账本的旧备份恢复；example scope 请求业务域 | 恢复停 needs_resolution；业务域不可访问，无绕过授权。 |
| R01 | 经另外授权的真实 schema 5 本机副本验证 | 单独记录迁移/完整性结果与限制；本阶段未授权、未执行。 |

## 11. 本次确认项与交接

用户已确认这份**接口约定**，无需再次确认正式 ADR 的二十项决定。本次工程选择：

1. §4.1 的单 op 原子裁决、import 也不得覆盖用户锁、同值 no-op 与 confirm_fields。
2. §4.2 的用户 stale delete 窄例外；按该窄例外实现用户删除优先，无法证明时进入待解决。
3. §3 的新增 restore/merge/purge scope、ledger_summary 独立权限域、actor 授权证据验证边界；merge 全写集合与外部 purge 状态规则亦按 §4 确认；具体业务授权仍由 W2/W7 完成。
4. §6 的精确容量、保留/备份、cursor/snapshot 及认证默认值；§7 的 shadow_staged 与生产 accepted 分离。

当前协议已定稿，主窗已进入代码实现并另写派发/状态交接。此前独立文档审核补齐 merge 引用写集合、外部 purge 与错误优先级；实现验收矩阵、真实本机副本验证和部署仍须各自证据。未因接口确认自动读取真实库、迁移线上状态、签发生产令牌或变更服务。
