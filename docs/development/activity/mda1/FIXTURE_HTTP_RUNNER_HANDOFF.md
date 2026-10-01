# MDA-1 fixture 真实 HTTP runner 交接

## 范围与入口

- 基线：`b0cb32bf297da5e3033689f9caf5e3c09409f778`，隔离分支 `codex/mda1-fixture-http-runner`。
- 首版 runner 提交：`e6e42b47636aa92d357a30196d2f8a6279659237`。主窗随后集成 R5/R5.1 静态合同至 `06bbe5ffc21f12283bf413386d608b9e7b1b53cc`；当前 runner 使用 `proposal_revision=5`。
- R5.2 最小返修基线为 clean `027fbfd7772c826b65d74bb39c013cdd1353ee3e`，仅补独立 guard 的 scalar 类型检查、测试和本交接；未改静态合同、fixture JSON 或 production Core。
- 入口：`node tools/i_core/activity_fixture_http_runner.mjs`；专项：`node --test tools/i_core/activity_fixture_http_runner.test.mjs`。
- 只新增 runner、专项测试、严格 test-only epoch setup 与本交接。没有更改 production Core、Flutter、设备接线或真实数据。
- 使用真实 `createICoreServer`、独立系统临时 SQLite、`127.0.0.1:0`。每 case 独立配对、读取、请求和 finally 清理；HTTP 使用独立连接，避免停服恢复后的旧连接复用。

## 证据与字段消费

- 首先复用 `loadFixtureSet` 的静态校验、原始隐私 lint；之后执行 runner 支持字段校验。manifest 声明元数据按已验证版本固定，额外 JSON、未知或惰性字段拒绝。
- runner 另有独立硬编码的 case/step expected leaf-shape 闭集，不从候选 fixture 推导，也不导入 static 的闭集。37 个 expected slot 和 6 个空 slot 的位置、根字段、HTTP/details/sequence 嵌套成员全部绑定；数组只允许声明位置的唯一 string 或非负安全 integer 标量，禁止对象子字段、错误类型和重复项。
- R5.2 为全部 scalar leaf 增加独立硬编码的类型表：string 必须非空、boolean 必须为布尔值、counter 必须为非负 safe integer；HTTP status、coverage counter、accepted_items 等不接受混型。只有声明的 HTTP/details/sequence 容器可以递归，scalar 的 null/object/array 注入直接拒绝。
- 事件直接复用 `materializeEvent` 与 `materializeAndQueue`；HTTP envelope 包含 materializer 的原始 UTF-8 bytes。已捕获事件重试复用相同 Buffer，不重建 event ID。
- 真实 server 的只读 request observer 核验每条请求的 loopback peer、精确 `X-Core-Protocol: 0.1` 和收到的 body bytes。observer 不改 handler、不产生模拟响应、不读取 store。
- case leaf ledger 分别消费 setup/capture、事件模板和 recipe、操作参数、core/limits 设置与每个 expected 值。capture/materialized ref 另做使用检查，未消费字段使 case fail；manifest case 按清单一次且仅一次执行。
- 字段消费不等于所有语义均由 HTTP 直接提供：下表和 P2 边界明确区分。

| Fixture 要求 | 真实 HTTP 验证 |
|---|---|
| accepted、错误码、details | ingest status、result status、error code；错误的 `event.field` 限定前缀与 fixture 的 field 同字段比较 |
| prefix 物化、旋转、exact retry | owner pair/rotate 的 prefix、generation；ingest event_id 逐字相同，重复 receipt 相同，旧凭据拒绝 |
| 1→3→2 | receipt 的 coverage、diagnostics、重算 through；reader summary 的 active→unknown→locked |
| 时钟、TTL、silence | 构造时注入测试时钟；后续时间变化仅在 listener 停止时设置；结果来自 ingest/summary |
| retention、旧 cursor | owner retention 后 reader changes 返回 resync_required/retention_gap；snapshot cursor 可读取空增量；原 event retry retained_out |
| acceptance_mutated/accepted_items | reader summary 与 changes 在请求前后完全相同；stale runtime 清理重启后无 accepted change |
| payload 允许字段 | 仅合成 heart-rate-quality case 用 owner HTTP admin/export 比较 payload keys；reader changes 不返回 raw payload 或内部 digest |
| 读写 scope、管理权升级 | 固定拒绝响应、错误响应无数据、reader 状态不变，probe 仍无 summary 权限 |
| 删除 lineage | `replacement_pair` 明确给出新身份和注册字段，owner HTTP逐字段配对并捕获新prefix/token；`capture_outbox_bytes_as`/`outbox_bytes_ref`选择同一已捕获Buffer，旧/新token各提交一次；随后从本地queue丢弃，不合成身份或改写prefix |

## P2 证据边界

1. `person_projection_state` 不是 Core HTTP 字段。runner 只验证设备/来源 summary 与 fixture 兼容、HTTP 不提供 person projection、`sleep_inference=not_supported`，不声称计算了 person 状态。
2. `resource_lookup_performed=false` 和 `idempotency_lookup_after_revocation=false` 只能由 HTTP 观察固定拒绝、不同请求仍同样拒绝、无信息披露与接受状态不变。不能证明内部函数调用次序。
3. `epoch-synthetic-*` 和 fencing 数字是 fixture 的相对前置状态标签。公开 HTTP 没有 authority takeover 路由；test-only helper 在 listener 停止时使缓存 epoch 落后一步，真实 HTTP 断言 stale_authority_epoch，再正常关闭/重启检验没有接受事件。没有修改 durable epoch、commitment 或数据库行，也没有证明生产 authority 迁移。
4. 纯 runner guard 独立保证 expected 的位置、shape 和类型，不复制每个 expected 的具体值合同；具体 canonical 值由 HTTP 前先执行的 static validator 约束，随后执行 HTTP 期望断言。不能把纯 guard 的通过单独称为完整 fixture 语义验收。
5. 全部数据是 synthetic。结果不代表 Android/BLE/设备接入、睡眠推断、通知、真人 Gate 或完整产品验收。

## 隐私与失败清理

- admin secret、probe/reader token、prefix、receipt/cursor 与响应只留在内存和该 case 的临时 Core；报告只输出 canonical case 名、固定 check code、计数与固定 evidence boundaries。
- 不拼接原始异常、actual/expected、请求 URL、密钥、内部 digest 或 payload 到报告/失败消息。测试刻意注入私密字段、凭据字面值与携带秘密的异常，必须在网络前拒绝或得到去敏失败。
- finally 关闭 listener/store，再删除本调用创建且确认位于 system temp 的精确目录。测试使用 PID 范围的临时目录观察，覆盖启动后、中途异常、成功和确定性重跑。

## 验证状态

- 5 个 JSON、26 个 case 使用真实 HTTP。最小报告 status 为 `passed_with_evidence_boundaries`，保留上述 P2 边界。
- 精确计数：213 requests / 213 wire checks、30 个含 fixture event 的 submissions、4 次相同 Buffer 重用、43 steps、181 expectation leaves、1057 case leaves。submissions 不包括 scope/revoke 诊断用的空 events 请求；总 requests 包括全部诊断请求。
- deleted-lineage 单 case 锁定：11 requests、2 submissions、1 exact retry、4 steps、10 expectation leaves、60 case leaves。
- 独立 guard 测试直接绕开 static：37 slot parity；删除 129 root、68 HTTP、9 sequence、2 details 成员全部拒绝；14 类跨 case 副作用字段、嵌套字段、slot 移动和非标量/重复数组注入拒绝。端到端 mutation 同时要求 `rejected_before_http`、requests=0、hook=0。
- R5.2 直接遍历 37 个 slot 的全部 158 个实际 scalar leaves：88 string、27 boolean、43 counter（另识别 10 个既有数组 leaf），系统性执行 1393 次错误类型变异，全部由纯 guard 拒绝，不借助 static。覆盖空字符串、数值/布尔/字符串混型、null/object/array、负数、小数、越界整数、NaN/Infinity；保留 HTTP 前拒绝测试。
- R5.2 最终 runner 15/15 + static 19/19：34 tests，34 pass，0 fail/cancel/skip；约 108 秒。真实 26 cases / 213 requests、全部精确计数与既有隐私/清理/确定性检查通过；三个 `.mjs` 语法检查、`git diff --check` 通过。
- R5.1 最终 runner 14/14 + static 19/19：33 tests，33 pass，0 fail/cancel/skip；约 243 秒。上述 26 cases / 213 requests 和全部精确计数由该专项锁定通过；三个 `.mjs` 语法检查与 `git diff --check` 通过。
- R5.1 基线的 `node --test tools/i_core/*.test.mjs`：196 tests，195 pass，0 fail/cancel，1 个既有 Windows case-sensitive filesystem 用例 skip；约 452 秒。该 skip 不属于 fixture case、runner 专项或 static validator。R5.2 未改 production Core 或其他模块，因此只重跑 runner + static 专项，不把该历史全量结果冒充 R5.2 新全量执行。
- 本 worker 只写自己的交接；主窗负责全局 DEVLOG/项目状态整合。本次提交按已授权隔离 worker 例外临时设置 `SKIP_PROJECT_STATE=1`，提交后恢复环境变量。
