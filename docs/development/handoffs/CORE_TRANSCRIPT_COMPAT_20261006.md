# Core transcript / historical replay compatibility — 2026-10-06

## 工作包与边界

- 分支：`codex/core-transcript-compat-20261006`；精确基线 `d9a8498264d349f8593cd421e76db3e77ad102fd`。
- 仅修改 Core Store / HTTP / 普通服务启动源码、合成测试和本 handoff。没有修改 Flutter、remote MCP、全局状态文档、旧固定发布包的 manifest/hash。
- 移植依据为已审计现役 B3 固定包的 Store transcript/replay 实现，以及 B3 分支的两份对应测试；仅读取源码，没有读取 `.state`、真实授权文件、真实数据库、正文或 token。
- 本工作包具有独立提交授权；提交时仅该次使用 `SKIP_PROJECT_STATE=1`，随后恢复原环境值。全局 DEVLOG/I_PROJECT_STATE 由主控集成时维护；未 push、未创建 PR、未合主线。

## 行为与授权

- 保留 `GET /v1/core/chat/transcript-capabilities` 和 `POST /v1/core/chat/transcripts`，继续要求 protocol + 当前设备 token。响应保留 B3 的 `enabled`、`character_id`、`from_created_at_ms`，增加只读 `companion_upload_mode`。
- Store / server 的 `companionUploadMode` 为 `pr10`（默认）、`legacy_b3`、`disabled` 三选一；未知值启动拒绝。HTTP 请求、pairing 自报 capability 或 domain credential 不能改变模式或签发 companion 权限。
- `legacy_b3` 只开启具有当前 credential hash 绑定的外置 Android grant 的 transcript 上传，普通 messages 拒绝 Android companion；持久 PR10 grant 此时也不启用该入口。旧 B3 客户端允许携带 `request_companion_reply:false` 的兼容语义保留。
- `pr10` 的旧 capabilities 为 `enabled:false`，transcript submit 为 403；普通 messages 的 Android companion 仍需要既有本机 `configurePhoneCompanion` 授权，与领域权限分离。`disabled` 关闭两路手机 companion 上传。普通 user 和 external-frontend finished-turn 保持原权限。
- legacy grant 保留原格式、设备/平台/credential/角色/时间下限，纯 chat 文字、无资产、无附注、1–100 条的限制。重配 token 不转移授权；缺 grant 不授权；非法或链接路径配置 fail closed。所有配置 grant 必须指向同一角色，且与既有 PR10 主角色一致。PR10 注册不能转为别的角色。
- 模式仅通过本机配置后新 Store / 启动切换；不重建 node identity、cursor secret、设备身份或消息 origin sequence。两路共用同一个 `#persistMessages`、批次事务和不可变 digest / sequence 检查。
- legacy 生效时禁止 Core reply jobs 开启或该角色存在 pending/claimed job；worker 对手机角色仍只能 shadow。没有新增模型调用、reply job 或回复生成路径。
- 服务 CLI 支持 `I_CORE_COMPANION_UPLOAD_MODE`、`I_CORE_LOCAL_TRANSCRIPT_GRANTS`、`I_CORE_HISTORICAL_REPLAY_APPROVALS`；普通 PowerShell launcher 只从显式 `-CompanionUploadMode` 取模式，并清除继承的两个文件路径变量，使用 state 邻接的默认文件。默认文件名仍为 `local-transcript-grants.json` / `historical-replay-approvals.json`。

## Replay 及恢复

- 保留 `core_metadata.historical_replay_approvals_v1` 的 version-1 原格式与原 digest 规则；启动前解析外置文件，启动合并既有 ledger，同 sync_id/预留(device,sequence) 的绑定不能被替换。删掉或截短外置文件不会删除耐久绑定。
- 每个持久化事务在 writer lock 内重读 ledger；精确授权仅允许普通设备的既有 `v3-history-*` user 行返回 duplicate，核对 incoming digest 与现有行重算 digest，不重写行/事件。transcript、frontend、worker、import 无权使用该历史例外。
- 预留 origin sequence 冲突检查位于 duplicate 快速返回之前；不同载荷、不同身份/序号、alias、现有行被改动、历史行缺失全部拒绝；整批回滚。
- 合成 72 条验证真实走过 schema 4→5→6，元数据原样、身份/cursor/token 保留、72 条精确 duplicate、重启、同路径合成快照恢复、无外置文件时 ledger 防护，以及从保全外置文件重建缺失 ledger；冲突文件仍拒绝启动。
- **部署恢复前提**：真实 72 条绑定不能进入 Git。主控必须在受控本机恢复/发布预检中验证原外置审批与 durable ledger 的完整精确集合（不能仅比较 count），保全对应历史行与身份/序号。若外置文件和 ledger 均缺失，运行时代码不能凭空知道曾经存在的审批；该来源必须由部署预检拒绝，不能当空授权集放行。whole-Core `backup_read_only` 激活限制保持。

## 验证

- 首轮移植 42 项：41 pass / 1 fail；失败是 HTTP 测试未声明显式 legacy 模式，修正后通过。
- 完整专项及必要相邻回归：**124/124 pass**，文件为 `transcript_compatibility.test.mjs`、`local_transcript_grants.test.mjs`、`historical_replay_approvals.test.mjs`、`domain_companion.test.mjs`、`i_core_server.test.mjs`、`import_v3_chat.test.mjs`、`companion_worker.test.mjs`、`domain_http.test.mjs`、`domain_migrate.test.mjs`、`i_core_autostart.test.mjs`。
- 随后新增 launcher 的实际子进程模式/继承文件路径防护测试；`i_core_autostart.test.mjs` **5/5 pass**。共 **125 个不同测试通过**；没有把重复运行当额外覆盖。
- 一次普通沙箱回归因测试临时目录的 realpath 访问得到 EPERM；使用已授权的提权测试运行上述同一合成套件后全部通过，不属于代码或模型故障。
- 所有数据库和授权数据均为新建临时合成夹具；没有真实副本迁移、生产停启、当前库升级、设备安装、部署验收或真人 Gate。

## 留给主控

1. 复核本 diff 并按既定顺序集成，更新全局 DEVLOG / 项目状态。
2. 过渡固定候选必须显式 `legacy_b3`，保全当前手机 grant 与 72 条精确 replay 绑定；旧 R3/schema4 固定 manifest 不可直接用来发布 schema6 源码。
3. 新客户端每次仅选一个 companion sender；PR10 模式需 owner grant，不能由旧 capabilities 的存在推断已授权。切换必须保留既有 sync_id / origin_sequence，排空旧队列后才退休旧路径。
4. 发布全套代码 hash、库/配置/授权恢复保全、真实副本证明、具体 D4 切换审批和设备验证仍由主控另行完成。本包只交付可复核本地候选。
