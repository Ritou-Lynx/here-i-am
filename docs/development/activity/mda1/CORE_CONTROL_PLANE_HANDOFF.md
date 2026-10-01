# MDA-1 M1-P1 Core 控制面 handoff

> 工作包：M1-P1 `device.activity.v1` Core 协议、认证、事件、投影、保留与恢复边界
>
> 分支：`codex/mda1-core-control-plane-w1`
>
> 精确基线：`1a65d3f35296a50f40b8540ea9a163583c156118`
>
> 范围：仅 iCore activity 域；未启动真实 Core、未配置真实凭据/网络、未连接设备、未实现 collector、睡眠推断或触达。

首候选 `c6ad35e7` 及后续 `59ddb517`、`25a28113`、`622133c1`、`23283fe8`、`cae0b720`、`83534bb2`、`e62d8498`、`540c24c7` 先后被主窗以 stale pre-auth、cursor 洞、migration/health 假绿、secret 跨域、authority/backup、clean clone、跨 retention replay、隐私、legacy v4 洗白、非 current history 删行、permission latch 和持久 authority JSON/registration 篡改反例退回。本 follow-up 不改写历史，最终采用 O(probes) structured event-id lineage，移除当前协议的逐事件永久 replay barrier，并关闭自动 retention、backup verification-only、runtime invariant、path binding、任何非空 legacy activity 自动升级及晚到的 history/source-health/authority-row 反例。

## 1. 存储、迁移与 readiness

### 第六轮窄返修：25bca0c2 → direct recovery 全程隔离验证

- 精确基线 `25bca0c238372da66110c1508b3919b8c7fa5fd2`。本轮仅改 store、Activity 测试与本 handoff；未改 server、控制面、prefix retirement、watermark、协议或 runner，storage schema 5 / integrity version 4 不变。
- 内部 `withReadOnlyActivitySnapshot` 统一文件捕获、前后 fingerprint、sidecar-free immutable view 与带 sidecar 的 system-temp 完整副本。commitment preflight 与导出的 `verifyActivityRecoveryCandidate` 都只在该视图内完成全部查询；不再在安全分类后重新 SQLite-open 源 sidecar view。成功返回与异常路径均关闭视图、清理临时副本并复核源四文件。
- direct verifier 新增 5 种 DELETE/clean WAL/real WAL/missing SHM/hot journal × 10 种 valid/invalid floor/stale floor/tampered floor/tampered candidate/五种 unsupported commitment，共 50 组完整结果验证。每组检查源 main/-journal/-wal/-shm 的存在性、长度与全部 bytes 不变，并检查临时副本无遗留；成功仍仅 `activation_authorized=false`。另覆盖 14 组 orphan sidecar 直接调用；main 与侧文件全缺失时显式返回 `recovery_lineage_unverified`，四文件零创建，而新库 preflight 仍允许继续。
- 沿用整库副本/散列开销与 retained-history deep audit 性能 P2；本轮只关闭 verification-only 的源文件副作用，不声称性能 Gate 或恢复激活权限。提交按隔离 worker 规则一次性使用 `SKIP_PROJECT_STATE=1`，由主窗统一集成共享状态。

### 第五轮窄返修：9e0d4af8 → 孤立侧文件与 server 最早启动分类

- 精确基线 `9e0d4af85d0e342d56b6d6ff0d6e4f9e05d014d3`。本轮仅改 store、server、Activity 测试与本 handoff；不改 `activity_control_plane.mjs`、prefix retirement、watermark、协议或 runner。storage schema 5 / integrity version 4 不变。
- main 不存在但任一 `-wal/-shm/-journal` 存在时，无论侧文件为空或含残留 bytes，都在任何 SQLite open、目录/新库初始化前以 `core_metadata_invariant_failed` 拒绝；不把缺失身份当作全新 authority。7 种非空侧文件组合 × 空/非空内容 × store/server × active/dormant × 普通/recovery 共 112 个入口检查保持四文件存在性和 bytes 不变。
- 导出安全 commitment/文件分类器，并在 `createICoreServer` 的 secret separation、recovery verifier 等所有源 SQLite 打开之前调用；`ICoreStore` 同样在 recovery verifier 之前调用。5 种 unsupported commitment（1/2/3/999/缺失）× DELETE/clean WAL/real WAL/missing SHM/hot journal × store/server × active/dormant × 普通/recovery 共 200 个入口检查保持源四文件存在性、长度与 SHA-256 不变。沿用第四轮稳定副本分类策略，不以忽略 WAL 的 main view 代替 committed view。

### 第四轮返修：1a88e691 → integrity-v4 / 前缀退休上下文与只读启动检查

- 精确返修基线 `1a88e691102295754cfa8733819345a38cd735ff`；该被退回候选已关闭 `8ea87d8` 的 event 后服务端时钟回拨与全入口深审计缺口，但仍遗漏 restart 后合法乱序 gap、partial retention 时 clock 前驱消失，以及 unsupported v5 的 DELETE-journal 启动零写。未改协议 fixture、26-case runner 或全局状态；主窗独立澄清 privacy-maximum/prefix-closure 文档。
- storage/Core schema 仍为 `5`，必需 `integrity_commitment_version=4` 与 `server_time_floor_ms`，root 使用显式 `integrity-v4` 域；probe_state 新增闭集 `retired_context_json` 并由 root 绑定。旧 integrity 1/2、保留未知值 3、缺失或其他未知版本的 v5 候选（包括空库）均拒绝 `activity_integrity_upgrade_unsupported`，不自动洗白被退回候选。新库与 canonical virgin v1–v4 升级原子初始化 version 4 / floor 0 / 空 retired context；非空 legacy 升级仍拒绝。
- commitment 版本检查早于源库 RW open、PRAGMA WAL 与 Core migration。完全无 `-wal/-shm/-journal` 的稳定 main 用实测的 immutable URI 只读分类；任一 sidecar 存在则复制 main + 全部存在侧文件到 system temp，比较源文件前后存在性、长度、SHA-256，SQLite 仅在副本恢复/分类，最后清理副本。不忽略 WAL committed view；不稳定状态 fail closed。覆盖 DELETE/WAL、main 有效而 WAL 无效及反向、缺 SHM、hot journal，拒绝路径源四文件不创建/删除/改字节。该启动检查有整库复制/散列成本，不是性能优化。
- 每条 accepted change 的 HMAC 绑定完整 canonical change、原 raw event（含 receipt、credential generation、时间、设备/probe）和 receipt observation；生命周期 change 同样签名并按六种 Activity kind / payload 关系闭集校验。单条 change 签名算法未改变，root 算法版本显式升级。内部签名不进入 changes wire payload；HTTP 回执字段与确定性重试保持下述既有契约。
- 所有 authority preflight 现在执行 deep audit，首次失败锁存在当前 runtime；summary/snapshot/append/changes/recovery/export/retention、认证和生命周期等入口无需先 health 就能拒绝。检查发生在续租前，并在 writer transaction 内再检查；失败不更新 lease、floor、审计或事件。health 即使 Core identity 已红，也触发 activity 锁存。`allowRetentionRecovery` 只绕过实际 retention 执行故障，不绕过任何 integrity failure；推进超过 24h 也不能删坏证据洗白。即使人工修回 canonical 字节，当前 runtime 仍关闭；只允许修复后的合法 clean restart 重新验证。显式 close 仍可释放自身 claim，这不是数据面恢复或自动修复。
- O(probes/credentials) root 保留 probe_state、projection、deletion receipt、watermark/snapshot 与时间下界承诺；active probe 必须恰有 state + projection，live event 必须绑定 received 时有效的 credential generation。deep preflight 暂按 retained history 全审计，普通 append/ack/lease 也承担该成本；**这是明确接受的性能 P2，不是普通写入性能 Gate**。root/seal helper 自身仍不扫完整 event/change 表，时钟下界通过 metadata 主键读取，不做历史 MAX；不能据此声称整条写路径 O(probes)。
- 所有服务端接收、生命周期、审计、retention 和 runtime/lease 时间使用同一 `max(Core now, committed floor)`；floor 与 root 同事务推进，retention 删除历史后仍保留，lease 到期值只向前。`pair t=1000000 → accept t=1000100 → clock=1000099 → rotate/revoke/delete-probe/delete-device → clean restart` 四类均保持 canonical ready。输入与派生时间必须为非负 safe integer，floor 为 24h 派生时间留出安全空间；overflow 在 mutation 前拒绝。summary/snapshot 的服务端 freshness 时间同样不倒退。不改客户端 signal time，不把服务端归一冒充设备健康。
- 深审计前置揭出的既有 writer/validator 不一致同步闭合：gap heal 根据真实 sequence coverage 判断；permission latch 在物化 projection 中保留其闭集 reason，并保留后续真实 clock fault；restart 仅将 active credential projection 标成 restart gap，不覆盖 revoked 状态。
- 新接受事件后的 projection 按仍保留的 immutable logical history 与退休前缀上下文重新协调；不能继承 restart 的 `unknown` clock 去冒充新的 coverage gap。`[3] → restart → 1 → 2` 与 `[1,4] → restart → 2 → 3` 均可正常接受、保持 deep ready 并恢复最后逻辑事件状态。
- 每条 accepted change 新增内部、签名认证且不可变的 `acceptance_clock_prior_signal_at_ms`，证明接收当刻已观察到的低序号 non-future max；从 changes wire payload 剥离，不进入 HTTP receipt。它随既有 accepted change 一同退休，不增加永久逐事件表。原 raw、clock_health、receipt 与 observation 不重写。logical clock 则由退休前缀 max + 当前 raw 重算，因此迟到低序号在前缀闭包中早删后，保留事件可同时保持原 acceptance healthy 与当前 logical regression。
- 永久退休上下文为每 probe 一个固定大小闭集摘要：`max_signal_at_ms`、`permission_status` 与 `source_health`。clock max 排除 future-skew；permission unavailable/pending 作为 logical reducer 种子，明确恢复后仍需健康具体证据。source_health 仅是已退休前缀的闭集诊断摘要，不能代替已删除 raw 声称当前 active/locked；没有可用 evidence 时仍 unknown。摘要、prefix floor、删除闭包与 root 同一 retention 事务提交；accepted anchors 与摘要篡改均在 mutation 前拒绝。

### 接收回执闭集字段

- 每个新 receipt 都有 `sequence_diagnostics`（按 regression、gap 排序的闭集数组）、`sequence_coverage` 与 nullable `projection_recomputed_through_origin_sequence`。coverage 精确键为 `highest_seen`、`contiguous_through`、`missing`、`observed_from`、`retained_origin_floor`、`missing_truncated`；只含数字、null、布尔与闭集枚举，没有 token/prefix/原 payload。
- coverage 是该原子批全部新事件应用后的快照；同批 duplicate 与后续 exact retry 除 `status` 外逐字段返回原 receipt，包括原 `coverage_status`。仅在该 event/receipt 尚未退休时保证原回执可查，不承诺至少保存满 24h；补洞、restart 或前序清理不会重写仍保留的 receipt。
- `missing` 最多列最早 128 个缺失坐标，更多缺口必须 `missing_truncated=true`。`observed_from` 明示观察下界；`retained_origin_floor=null` 表示从未保留，0 是合法 sequence/floor。floor 以下不声称连续；floor 后首坐标有洞时 `contiguous_through=null`。
- 真实 HTTP `1→3→2`：seq3 返回 `[sequence_coverage_gap]`、highest 3 / contiguous 1 / missing `[2]`；seq2 返回 `[sequence_regression]`、healthy、highest/contiguous 3、missing `[]`，实际重算标记 `3`，随后 HTTP summary locked。此 Gate 不读 store 替代 response，也不声称执行全部 revision-2 manifest runner。
- 本 worker 本次 commit 使用单次既有 `SKIP_PROJECT_STATE=1` 例外，由主窗负责集成状态/DEVLOG；不改 hook、不 push，提交后恢复原环境值。

- Core schema 为 `5`，activity storage schema 为 `5`，wire/feature 仍为 `device.activity.v1` / `1`。activity 有独立 committed migration ledger、规范化 DDL checksum、主键/唯一约束、显式索引和 metadata 值级 invariant；表存在本身绝不算 ready。
- `retained_watermark >= 0`、`snapshot_generation >= 1`、`authority_epoch >= 1`、`commit_high_water >= 0`、replay floor revision/count/root、database role/binding、runtime claim、Core `node_id`/`cursor_secret` 都 fail closed 校验。每个 persisted principal 的 canonical JSON、server-assigned scope/type shape、source/coverage/interval/expiry、generation/timestamps，以及每代 credential 的 UUID/hash/generation/revocation chain 都在 claim 前值级校验；malformed JSON 不会延迟到 authenticate 才抛裸异常。运行中 identity、role、schema 或 replay commitment 变坏时，health 与所有 activity 读写一起关闭，不能出现“health 红、数据面仍写”。
- 只有 metadata 与 activity 表都处于 canonical virgin 状态的 storage schema `1/2/3/4` 可原子升级；任何非空或曾推进 runtime/watermark/snapshot/high-water 的 legacy `1/2/3/4` 均以 `activity_legacy_binding_authorization_required` 零写拒绝。尤其 v4 的旧逐事件 barrier 不能通过现存最大值“洗白”为 v5 replay floor，旧任意 event ID 也不能伪装 structured identity。中断 migration 全事务回滚；未来 Core schema 不降写，旧 binary 写回版本也不假绿。
- 只有真正全新空库可以生成 Core identity。已存在 chat/activity/schema 证据但缺失或损坏 `node_id` / `cursor_secret` 时，在 migration/claim 前零写失败；principal node/epoch 与当前 Core identity 逐行核对。
- activity live DB 保存规范化 `realpathSync.native` 路径的 SHA-256 digest，不无条件小写 Windows 路径。clean clone 到不同路径以 `activity_database_binding_mismatch` 零写拒绝，原库仍可用。该 digest 只是同机异路径误激活防护，不是不可回卷锚点；同路径旧文件覆盖、跨机器相同路径仍需 Gate 1A-3/1C 外部 authority。

## 2. 身份、scope 与运行期 authority

- `activity_principals` / `activity_credentials` 与 devices、chat/change、worker、mail relay、pairing code 物理隔离。probe 固定 `activity.write`，reader 固定 `activity.read_summary`；`capabilities_json` 只展示，永不判权。probe token 绑定 `device_id + probe_id + generation + Core node/epoch + source + coverage`，不能读 chat/change/ack/admin、不能访问其他 probe/device。
- `activity.admin` 仅由独立 owner bootstrap secret 承载。启动在任何 migration/claim 前只读比较配置域及持久 device/activity/consumed-pairing/active-worker-lease/mail-relay token hash；冲突统一 `authority_secret_conflict`，不泄露命中域且零 activity mutation。该入口只证明 synthetic owner 控制面，不代表真人凭据保管/轮换完成。
- rotate 显式提升 generation、沿用同一 event-id prefix；re-pair 不 upsert、不静默轮换或复活。revoke/delete/authority/runtime fresh check 永远先于 duplicate receipt，HTTP body await 之后也在事务线性化点重新加载 durable principal。
- activity runtime 使用独立 claim/fence/lease，但本 Goal 只支持同一 live DB 的 clean-close in-place restart。任何遗留非空 claim，即使租约过期或 runtime label 相同，也不自动 takeover：分别 `activity_authority_busy` / `activity_recovery_required`，零写。clean restart 使 projection 变 `unknown/core_restart_gap`，保留 raw/receipt/token；只有新的新鲜 event 恢复，exact duplicate 不恢复 coverage。
- 未配置 owner 时 activity dormant，不 claim、不续租、不写 restart gap/high-water。构造、TLS、listen 或 close 失败会 finally-safe 释放自己拥有的 server/relay/store；外部 relay 不被关闭。

## 3. structured event identity、ingest 与 replay

- pairing 由 Core 签发随机、非秘密、至少 128-bit、全局唯一 `event_id_prefix`。客户端 event ID 必须精确为 `<prefix>.<canonical_decimal_origin_sequence>`；十进制只允许 `0` 或无前导零正整数，无符号/替代编码。Shortcuts 只需字符串拼接，不需要客户端秘密、HMAC 或 UUIDv5。
- DB 仍保留 `event_id` 与 `(device_id, probe_id, origin_sequence)` 双 UNIQUE。尚未被退休的 canonical payload 相同返回原 receipt，不同即 `idempotency_conflict`。fresh durable credential/authority → closed parse/binding/scope → structured ID → 双键 preflight → 仅新事件 TTL/rate → 单事务写入；尚保留的 exact retry 即使 TTL 已过或 rate 满额仍取回原 receipt，但 revoked/deleted/fenced principal 先拒绝。
- 24h 是 privacy-oriented retention maximum，不是至少可读满一天的承诺。若某 probe 任一 due event 将 floor 推到 F，所有该 probe 已接受且 `origin_sequence <= F` 的 raw 与 accepted change 都在同事务进入退休闭包，包括较晚接收、尚未满 24h 的低序号；不留下 raw ≤ floor。之后任何新 seq ≤ F 明确 terminal `event_retained_out`（410），不会无限期接受迟到低序号；seq > F 可继续乱序补洞。`seq10 due + seq5 recent → 两者 raw/accepted change 均删除 → seq6 410 → seq11 可收` 已验证。
- 逐事件 tombstone 只保留原 `received_at_ms + 24h` 剩余窗口，不额外延长一天。周期 sweep 可能因 60 秒周期、event loop 延迟或停机而在磁盘上晚于边界清除；启动 ready 前、export 与 backup 前同步清理。active probe 永久留下 nullable `retained_origin_floor` 与固定大小退休 clock/permission/source 摘要；删除 probe 将 prefix/floor转为 keyed digest并删除 context。永久状态为 O(probes)，无永久逐事件 membership/receipt/anchor；保留摘要包含一个必要的最大 signal timestamp，不能称为完全抹除全部时间信息。prefix/floor 是 origin 坐标的 terminal replay 边界；feed watermark 是实际被删除 change 的 server_sequence 游标边界，两者不可互换。
- replay root 覆盖 authority epoch、commit high-water、revision、累计 accepted/retired event 计数、所有 active prefix/floor、deleted lineage digest，以及全部 principal registration 与 credential rows 的 keyed digest；metadata 保存 lineage count/root 与事件累计计数。合法但被替换为另一个 allowed source/kind/capability/expiry/token hash 的值也会在 deep authority preflight 时因 root mismatch 关闭，不只拦 malformed JSON。retention/delete 只把 accepted 从 live 计入 retired，不减少累计 accepted；deep audit 要求 `live raw + retired == accepted`，并验证 watermark 之后 change sequence 连续。因此删掉非 current raw 及对应 change、降 floor、换 prefix、坏 digest、孤儿或旧 count/root 回卷都会在重启/深 health/claim 前 fail closed。整库同路径回卷仍无法由库内 commitment 自证，需外部不可回卷锚点。
- `origin_sequence=0` 在从未保留历史时合法；只有真实 retention floor 后才返回 `event_retained_out`。prefix collision、sibling/wrong prefix、rotation/delete/restart/backup/root tamper 均有直接 Gate。

## 4. payload、coverage、投影与 cursor

- event/device/probe/installation ID 使用长度受限 ASCII opaque grammar，拒绝 URL、Bearer/JWT、secret/token/password、stack、控制符与非 ASCII。source/kind/coverage/confidence 为服务端闭集。ADR 尚未冻结 permission/error wire enum，因此 `probe.permission_changed.capability` 与 `probe.error.code` 只能使用 owner pairing 为该 source 注册的安全 machine token；设备诊断文案不进入 raw/export/audit。
- Core 独占生成 `received_at_ms`；客户端只提交 `signal_at_ms`，持久化/输出为 `occurred_at_ms`。所有 `signal/received + ttl/expiry/lease/retention` 派生时间在 SQLite 写入前验证为 nonnegative safe integer；任一 overflow 使全批 `invalid_time_range` 零写失败。payload 4096 UTF-8 bytes、envelope 8192 bytes、request 512 KiB、batch 100 项，每 probe 每分钟最多 120 个真正新事件。
- 协议 revision 2 的可观察错误保持精确：未知 kind 为 `unsupported_kind`；缺字段为 `missing_required_field` 且带 `details.field`；probe credential 访问 chat 与 owner 路由分别在资源查找前返回 `chat_read_forbidden` / `admin_escalation_forbidden`；已编码 payload 4,097 bytes 优先返回 HTTP 413 `payload_too_large`。测试 helper 不再接受会被静默忽略的 `eventId`，只有显式负例可通过 `wireEventId` 改变真实 wire bytes。
- coverage source/mode/expected interval 必须匹配注册值，window 必须包含 signal time。MDA-0 的 `discrete_best_effort` / `heartbeat_only` 可省略 event interval并以 server registration 为准；continuous 必填。24h offline backfill 仅保证尚未跨 floor 且 TTL/outbox 有效的正常路径；projection freshness 仍受注册 expiry SLO 收紧。
- projection 只产 `active | locked | network_only | unknown`，不产 quiet/awake/resting/asleep。closed `status_reason`：`unobserved`、`core_restart_gap`、`future_skew`、`clock_regression`、`coverage_gap`、`coverage_stale`、`coverage_missing`、`coverage_invalid`、`probe_error`、`permission_unavailable`、`reachability_only`、`insufficient_human_evidence`、`fresh_signal`、`credential_revoked`、`ttl_expired`、`retention_expired`；`sequence_regression` 只属于 receipt diagnostics，不进入 summary reason 或 clock health。
- 乱序交付与时钟健康分离：event row 的 `clock_health` 只允许 `healthy | future_skew | clock_regression`，first-seen 较小 sequence 的 receipt 另带 `sequence_diagnostics: [sequence_regression]`，该诊断单独不降级 source。future skew/clock regression 与 sequence gap 会根据 immutable raw 在启动 deep audit 时重算，不能靠协同篡改派生列恢复假 active。sequence gap 持久存在直到补齐，补洞后按 logical sequence 重算 current projection 与 source-health；fixture 等价的 delivery `1,3,2` 会由 gap/unknown 恢复为逻辑 seq3 的 locked，而不是把 seq2 误报 clock regression。`permission_changed available=false` 是持久 source latch，后续 heartbeat/network/input 都不能恢复；只有 logical-order 中明确 `available=true` 解锁，且仍需后续健康具体 evidence 才恢复。健康时钟的新 `probe.error` 可把旧 clock fault 恢复为 healthy，但 source 仍为 `unknown/probe_error`。设备 summary 先按 evidence class，再按 occurred time、server sequence、probe ID：fresh covered active/locked 最高，中性 device evidence 次之，network-only 再次，error/permission unavailable/gap/clock/TTL/revoke 最低；单 probe 失效不能抹掉 sibling 的有效具体证据。
- activity changes/cursor/ack/watermark 与 chat 完全分离。cursor 是“最后已应用 sequence”；`cursor < retained_watermark` 必须 resync，`cursor == watermark` 可继续，`cursor > latest` 为 `resync_required/cursor_ahead`。删除/retention 从实际移除的 activity changes 计算 watermark；snapshot 仅含 current minimal summary、generation、base cursor、digest。

## 5. retention、删除、备份与恢复边界

- retention 使用 `<= cutoff`：activity activation ready 前清理一次，server 运行期每 60 秒尝试受控清理，admin export 与 backup 前强制清理；timer 在 close/startup failure 清除。执行失败会锁存并让 health/普通 activity 数据面 fail closed，只有底层仍完整时显式或定时 retention 成功才能恢复；完整性失败是另一独立且不可由 retention 清除的锁存。自动清理只写 activity 域，不生成离线/quiet/sleep 结论。dormant store 若任一 event/change/tombstone/audit/probe-state/rate/projection 行已满足 sweep 条件，backup 以 `activity_retention_authority_required` 拒绝，不能泄露过期数据。
- revoke 与 projection invalidation/snapshot bump 同事务。delete 先隔离 token，再删除 raw/projection/change，并给出 `device_spool=client_action_required`、`backup=expires_by_policy`，不伪称删除设备 spool 或离线介质。
- 正式 backup 使用同目录唯一 staging：复制 → 在 staging 标 `backup_read_only` → schema/manifest 校验 → close → atomic rename。中断不会暴露未标 final。`backup_read_only` 是 whole-Core verification-only artifact：无论 owner 是否配置，普通 `ICoreStore` / server 都不能以 RW 打开，因此旧 device token 也不能在 backup 上写 chat/change/ack或发 mail。
- `verifyActivityRecoveryCandidate()` 只读验证 HMAC closed manifest、全 activity durable tables 的 canonical history digest、commit/change/watermark/snapshot/runtime/replay floor；同高度分叉、stale/tampered candidate 拒绝，固定返回 `activation_authorized=false`。ICoreStore/server 不接受 recovery floor 作为可写激活授权。异常崩溃恢复、lease takeover、跨机器/旧备份激活明确 unsupported，延后 Gate 1A-3/1C。
- rollback 仅允许 activity 域完全为空；有 principal/event/delete receipt 时拒绝，避免为旧 Core 兼容丢数据。旧客户端 chat/device API 保持原协议；旧 device token不自动得到 activity scope。

## 6. API

除 health 外均使用独立 Bearer principal，协议头仍为 `X-Core-Protocol: 0.1`。

| 方法 | 路径 | principal | 结果 |
|---|---|---|---|
| `POST` | `/v1/core/activity/probes/pair` | owner admin | 签发 write-only probe、token、event prefix |
| `POST` | `/v1/core/activity/readers/pair` | owner admin | 签发 summary reader 与初始 activity cursor |
| `POST` | `/v1/core/activity/principals/{id}/rotate` | owner admin | generation 轮换，prefix 不变 |
| `POST` | `/v1/core/activity/events` | probe | 原子批量 ingest |
| `GET` | `/v1/core/activity/summary` | summary reader | 每设备最小 summary |
| `GET` | `/v1/core/activity/changes?cursor=...` | summary reader | activity-only 增量流 |
| `GET` | `/v1/core/activity/snapshot` | summary reader | resync snapshot |
| `POST` | `/v1/core/activity/ack` | summary reader | 独立 activity ack |
| `POST` | `/v1/core/activity/probes/{probe_id}/revoke` | owner admin | 撤销并失效 projection |
| `DELETE` | `/v1/core/activity/probes/{probe_id}` | owner admin | 删除单 probe 活动数据 |
| `DELETE` | `/v1/core/activity/devices/{device_id}` | owner admin | 删除设备全部 probes |
| `POST` | `/v1/core/activity/admin/retention` | owner admin | 手工触发同一 retention 策略 |
| `GET` | `/v1/core/activity/admin/export` | owner admin | retention 后的 activity-only export |
| `GET` | `/v1/core/activity/admin/audit` | owner admin | 无 token/raw payload 的最小 audit |

health 只有 schema/runtime/owner 全部 ready 才广告 `device.activity.v1` 与 `control_plane_available=true`；始终明示 `e2e_available=false`、collector/summary-client unavailable、clean-close-only、crash/takeover/backup activation unsupported。

## 7. 自动 Gate 与精确结果

`activity_control_plane.test.mjs` 的 108 项保留第五轮 107 项，并新增 50 组 direct recovery 组合 Gate、扩充 14 组 direct orphan 检查及缺失候选零创建检查。第五轮 112 个 orphan sidecar 入口检查与 200 个 unsupported commitment server/store/recovery 检查，以及此前 restart/late gap、partial prefix clock/permission/error、seq10/5早删闭包、12个固定随机种子的多轮 restart/retention、context/anchor篡改、120组独立入口篡改等继续运行。永久摘要 O(probes) 不等于执行成本 O(probes)：deep preflight 与低频 retention closure/重算保留 history 成本，启动分类有副本成本；明确保留性能 P2，未完成性能 Gate。

- Activity 专项：`node --test tools/i_core/activity_control_plane.test.mjs` → `108 total / 107 passed / 0 failed / 1 skipped`。skip 仅在运行测试的 Windows 临时目录不支持同一目录中仅大小写不同的两个真实文件时触发；支持 case-sensitive 目录的平台会执行双文件 path binding Gate。
- Node 全量相关回归：`node --test tools/i_core/*.test.mjs` → `163 total / 162 passed / 0 failed / 1 skipped`；其中 activity `108`（`107+1 skip`）、既有 iCore server `21/21`、mail relay `23/23`、autostart `3/3`、import `2/2`、companion worker `6/6`。
- Gate 1A-0 Dart 联合回归：`D:\flutter\bin\cache\dart-sdk\bin\dart.exe test test/data_authority_preflight/isolation_harness_test.dart test/gate1a0_authority_recovery/synthetic_harness_test.dart` → `27/27 passed`（synthetic 文件自身 20 个 top-level tests）。
- Gate 1A-0 CLI canonical registry：`D:\flutter\bin\cache\dart-sdk\bin\dart.exe run tools/gate1a0_authority_recovery/run_harness.dart --fixture-root tools/gate1a0_authority_recovery/fixtures/synthetic_v1 --output-root <empty-system-temp-dir>` → `202/202 passed`、`allInvariantsHeld=true`，report `1,409,842` bytes / SHA-256 `7E868CDDD330AE92A112A23405D6156EC006D294773FE3BD8741DD83739D78A3`，fixture digest `e6007a58309fa36b7ef5e41da223251a2b9fb16c249a2ad084cd459b48fdc9a7`，scenario SHA `30d038701aef031494dfb854a23c1deedf36ef8cbd5827221a6cf76c31f1df01`。
- `node --check` / `git diff --check`：最终复跑均 exit `0`。

全部自动测试使用 system temp 合成 SQLite 与确定性时钟；未运行真实 iCore、计划任务、Tailscale、设备、App build/install 或真人三 probe Gate。Node 控制面通过不等于端到端产品可用。

## 8. 主窗集成结果与剩余边界

1. 主窗已审计 schema/auth/route/diff，确认 activity 未写 chat/Card/User-truth/Memory/whiteboard；随后选择性集成并同步共享 `I_PROJECT_STATE.md` / `DEVLOG.md`。本 worker 按拥有路径没有直接修改共享状态页。
2. 主 Android 最小只读 reader 已只消费 `activity_summary_v1.fixture.json` 与上述 closed state/status_reason；permission/error 仍走 source-specific registered machine-token，没有放宽为任意设备文案。
3. P2 隐私债务：delete 已立即删除 raw/projection并使 token 失效，但 deleted principal row 仍可能保留 token hash/display/capabilities/source，deletion receipt 尚无独立 expiry。当前 1 天清理不等于完整身份/receipt 擦除。
4. 既有 relay 的更早期构造失败与 close 聚合仍有 P2 审计债务；本包只保证 activity claim/store 不因 TLS/listen/owned-relay close 失败遗留。
5. 外部不可回卷 anchor、crash recovery、lease takeover、跨机器/同路径旧文件恢复属于 Gate 1A-3/1C；当前 path digest 与库内 root 不能替代这些能力。
6. 仍未做 Windows/Android/iPhone collector、真实 Shortcuts、睡眠推断、通知/Chat/来电。主窗后续以纯合成 harness 完成三 probe 报告，Lynx 于 2026-09-06 明确通过；这不是任何真人设备或采集 Gate。structured prefix 的 Shortcuts 可实现性仍只由无需 secret/hash 的 closed string-concatenation 契约支持，未做真人设备验证。
7. 主窗已集成 revision 2 冻结 fixture 与严格真实 loopback HTTP runner：逐个 materialize pairing prefix、消费全部 manifest case 并拒绝 unused field/skip，最终 CLI `26/26`、`213` requests；该结果不扩大为设备或内部调用次序证据。
