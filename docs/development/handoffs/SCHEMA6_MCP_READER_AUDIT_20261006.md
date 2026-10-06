# Schema 6：MCP 与 Core 直接读取者源码审计（2026-10-06）

## 范围与证据等级

- 只读核对用户指定源码副本与本任务正式源码；没有调用现役 MCP、读取真实数据库/配置/凭据/正文、枚举实际服务或任务、连接手机，也没有运行导入/迁移/启动脚本。
- A = `C:\HereIAm\continuity-b0-b2-20261002`，用户提供的现役来源副本；实际文件哈希见下。读取时 HEAD 为 `2a27f7d7f6b61ff5997db45c8c2f7bde4afb9966`（detached）。不能据此证明当前进程仍从 A 运行或加载相同字节。
- B = 本任务树 `C:\HereIAm\core-deploy-readiness-20261006`，基线 `8b0008b5d8c63e41a0e8d063bdb60053c94f3d2e`。下文 A/B 行号分别属于各自副本，不可混用。
- 清单搜索覆盖两个树中非忽略的 `tools/`、`scripts/` 源文件及直接调用引用；排除测试/fixture/vendor 后分类。未扫描机器全盘、用户工具目录、实际计划任务、忽略的私有脚本或任何配置。因此不是“本机所有现役读者清零”的证明。

## 文件身份（SHA-256，原文件字节）

| 树 | 相对路径 | SHA-256 |
|---|---|---|
| A | `tools/i_remote_mcp/server.mjs` | `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6` |
| A | `tools/i_memory/i_memory_read.mjs` | `cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28` |
| A | `tools/i_continuity_gateway/i_voice_context.mjs` | `9a3bd7c40cca2508b9983cdc8f489e328a3f810a38002695be8209a4d8d0bed1` |
| B | `tools/i_remote_mcp/server.mjs` | `9e0ff616cebfa1552bc2cd81b2644c6b61d5eb28845d747e59eed51df0dd012a` |
| B | `tools/i_memory/i_memory_read.mjs` | `095ab779683179028c0ba39353ed59ff6c42983c800b6d1a549ee8e91a435ce0` |

A 的 server 哈希匹配提供的 `adfc8812` 前缀。B 与 A 不是同一文件；B 增加 policy domains 限制，但保留同类连接缓存生命周期。

## A：打开、缓存、读取与关闭

1. `tools/i_remote_mcp/server.mjs:32–41,475–479`：Core 路径优先 `--core-db`，其次 `I_CORE_DB`，最后源码默认 `tools/i_core/.state/i-core.sqlite`；memory/policy 各有独立路径覆盖。这里只确认解析规则，不推断实际生效路径。
2. `server.mjs:52–61`：`createLazyReadModel()` 初始 `cached=null`。首次调用动态 import `i_memory_read.mjs` 并 `openReadModel()`；后续返回同一个对象。缓存的是模型/数据库句柄与 policy，不是消息查询结果。没有 TTL、文件身份检查、文件替换通知或请求末尾重开。
3. `tools/i_memory/i_memory_read.mjs:244–251`：先加载 policy，再检查 Core 文件存在，然后以 `new DatabaseSync(coreDbPath,{readOnly:true})` 打开 Core。policy 只在创建模型时载入（`loadPolicy:111–117`），没有热重载。
4. `i_memory_read.mjs:321–331`：独立 memory 数据库懒打开、缓存只读连接；缺失时返回 null，后续调用会再检查。`policySummary:362–366` 会查询 memory metadata，因此仅调用上下文也可能打开第二个库。
5. `tools/i_remote_mcp/mcp.mjs:269–293,306–314`：`i_context`、`i_recall`、启用写回时的 `i_chat_turn` 都取此缓存模型；`i_chat_turn` 的 end 阶段同样先取模型。没有按 MCP 工具调用结束关闭。
6. `i_memory_read.mjs:370–406,458–465`：Core 查询直接读取 `chat_messages`，有条件规则还引用 `devices`（286–302）；每次使用同步 `.prepare().all()` / `.get()`。源码未建立跨请求显式事务或保存查询游标，因此不能把“长寿命连接”写成“持续长读事务”或“已经阻塞 checkpoint”。
7. `i_memory_read.mjs:482–487`：`close()` 先关闭 Core，再关闭已打开的 memory，并清空 memory 引用。`server.mjs:60` 再清空模型缓存。没有对 Core close 失败后的 memory close 做 finally 保护。
8. `server.mjs:112–116`：HTTP MCP session DELETE 只删 Map 条目。`86–89` 的过期/容量清理同样只删会话。它们都不关闭数据库。
9. `server.mjs:516–518`：CLI 只在 SIGINT/SIGTERM shutdown 中调用 `getReadModel.close()`；先发起 HTTP server.close()，但不等待连接排空即关闭模型。源码没有可远程调用的“释放只读句柄”管理接口。

### 生命周期缺口（静态推断，未做故障复现）

- `server.mjs:53–58` 未缓存初始化 Promise，也没有 await import 后再次检查 cached。两个首请求同时越过首次检查时，可先后创建两个模型，后创建者覆盖 cached；factory.close 只显式关闭最终缓存对象。前一个模型何时被垃圾回收不属于明确关闭契约。
- 同一处缺少 closing 状态；初始化等待 import 期间执行 close 后，挂起 factory 仍可能继续打开连接。当前 shutdown 也没有请求 drain / import completion 等待。
- 以上是控制流可见的资源所有权风险，不是“现役发生泄漏”的证据。不修改本次核查副本。

## WAL 与部署含义

- A 的 server/read-model 源码未设置 `journal_mode`、`wal_checkpoint`、`immutable=1`、`busy_timeout`、`query_only`，也不执行显式 BEGIN/COMMIT。它是普通 SQLite `readOnly:true` 打开，不能按离线 immutable reader 处理。
- B 的 `tools/i_core/i_core_store.mjs:764–769` 打开 Core writer 并设置 WAL；这是 writer 源码行为，不是对当前真实库 journal_mode 的查询结果。
- B 同文件 `534–576` 已明确处理只读打开的 sidecar 风险：有 WAL/SHM/journal 时复制完整视图到私有临时路径；无 sidecar 的快照使用 immutable。MCP 普通 reader 没有这套处理。因此“只读”不等于“不持有数据库/SHM资源或绝不影响 sidecar”。
- 本次不能证明具体 WAL 文件存在、读标记是否被占用、checkpoint 是否 busy，或 Windows 是否阻止文件替换。也不能只凭 Core writer 已停而宣布全库离线。
- Schema 6 操作若要求无外部句柄/稳定离线视图，应把可能已初始化的 MCP reader 纳入停读与重新打开的依赖，且在真实操作授权后由部署主控取得关闭/原生独占检查证据。仅删除 MCP HTTP session、停止 Core writer 或等待请求结束都不是该源码的模型 close 契约。重新打开必须在目标路径/状态确定后进行。
- 不建议对在线可写库直接追加 `immutable=1` 来消除 WAL/SHM；当前 reader 并不具备离线不可变前提。

本报告的上述 WAL/句柄结论是静态审计边界；主窗后续已用相同字节旧 MCP 与合成 WAL 库复现原生持柄拒绝，结果见[组合验收](SCHEMA6_MCP_SESSION_ACCEPTANCE_20261006.md)。它不扩大为真实原库或现役进程证据。

## 其他直接读取路径与排除项

以下 B 行号按当前源码分类；“存在代码入口”不表示现在正在运行。

| 入口 | 数据库/用途 | 连接生命周期与界限 |
|---|---|---|
| `tools/i_memory/i_memory_read.mjs:250–255,492–497` | Core chat reader + 独立 memory snapshot | 与 A 同类只读长寿命句柄；唯一发现的非测试 openReadModel 消费者是 remote MCP server。新 domains policy 不消除 Core 打开。 |
| `tools/i_core/import_v3_chat.mjs:150–162` | Core 去重统计 | dry-run 也会打开指定 Core，只读，finally close。不是只读源手机库即可完成的路径。 |
| 同文件 `187–206` | apply 前 Core 在线备份；随后导入 | 只读 liveCore 在 await backup 期间持有，finally close；随后 ICoreStore 为写入者。审计未执行。 |
| `tools/i_core/i_core_store.mjs:424–530` | 凭据分域、数据库角色、绑定、Core 身份 preflight | 四个普通 `readOnly:true` 临时打开，finally close；可能读取真实路径，但不是独立后台常驻 reader。 |
| 同文件 `534–576` | activity/recovery preflight | 有 sidecar 时读取原文件字节到完整副本后在副本查询；无 sidecar 时 immutable 读取原路径；最后关闭、校验原文件视图。 |
| `tools/i_core/domain_migrate.mjs:515–519` | `inspectDomainDatabase` | 普通只读直开指定 Core、finally close。其迁移 `196–250` 是读写入口，不能当作 reader-only。 |
| `tools/i_core/inspection_read_only.mjs:68–112` | inspection HTTP 模式 | 对受约束检查库使用 immutable，保留连接至 server close；不是普通现役 MCP reader。 |
| `tools/i_core/release_schema6/automatic_backup.mjs:24–27` | 在线 Core/清单 SQLite 备份 | `mode=ro`、query_only、显式 BEGIN，在 await backup 完成后 ROLLBACK/finally close；此处确有跨 await 的读事务，部署排空应覆盖正在执行的备份。 |
| `release_schema6/preflight.mjs:82–143`、`backup_bundle.mjs:106–121`、`lifecycle/common.mjs:44–57` | 已受约束的离线元数据/备份验证 | immutable 打开，finally close；不能拿其离线前提替代在线 reader 审计。路径均位于 `tools/i_core/` 下。 |
| `release_schema6/recovery_adapter.mjs:155–194`、`recovery_witness_worker.mjs:51–55` | 恢复源检查与只读 witness | immutable 打开并显式关闭；恢复修改发生于另外的 staging/activation 路径。路径均位于 `tools/i_core/` 下。 |
| `tools/i_core/runtime_pin/verify_v4_state.mjs:20–27,54` | schema4 检查 | 原库+sidecar 复制到自有临时副本后 SQLite 打开；不直接 SQLite 打开 source。 |
| `tools/i_core/runtime_upgrade/r3/runtime_child.mjs:39–58,132–135` | schema5 候选前置检查 | sidecar 门禁后的 immutable 读取并 close；是候选运行器，不证明现役部署状态。 |
| `tools/i_continuity_gateway/i_voice_context.mjs:299–434,457–504,599–628` | 手机 memex snapshot，表含 persona_chat_messages/memory_cards | 每次 compile 打开指定 snapshot，finally close；获取入口复制手机 DB/WAL/SHM 到 scratch。不是本机 Core DB reader。未调用。 |
| `tools/i_memory/import_v3_memory.mjs:64–114,147–155,177–216` | V3 源与独立 i-memory snapshot | 源/检查只读，导入输出读写，均 close；未见指向 Core 的调用接线。 |
| `tools/i_core/import_personal_notes.mjs:28–48` | 独立 notes 账本源 | 经 offlineDatabase 门禁后只读打开，query_only + BEGIN，读 notes 表后 ROLLBACK/finally close；不是 Core 直读连接。 |
| `tools/i_remote_mcp/writeback.mjs:130–133,655` | 独立 writeback ledger | WAL 写连接；Core 写回由 HTTP 客户端完成。不能误计为 Core DB reader，但总停机范围若包含 MCP ledger 应单独管理。 |
| `tools/mda2_windows_queue/store.mjs:52`、`tools/i_core/shortcut_mail_relay.mjs:107–108` | 各自 queue/relay DB | 不因同用 SQLite 就视为 Core reader；未检查真实参数是否被误配。 |
| `tools/siyuan_tutor/README.md:1–27` | 思源学习工作流文档 | 指向思源自身 MCP 与学习文件交接。B 的该目录只有导师文档，未见 Core/SQLite 直读实现；A 无此目录。不能推出外部思源插件/本地私有脚本绝无 Core 接线。 |

在限定的 `scripts/` 源码搜索中未发现额外 `DatabaseSync`、`sqlite3.connect`、`better-sqlite3` 打开入口。测试/合成 fixture 不列为现役依赖。

## 复核与未完成项

- 已核对 A 的关键文件哈希、源码行号、B 基线；报告只含源码/元数据，无真实数据内容。
- 只静态读取既有 integration 测试源码：A `tools/i_remote_mcp/integration.test.mjs:200–207` 覆盖 factory 成功打开/关闭。不能据此宣称并发初始化、数据库替换、停读排空或现役句柄已验证。本次未运行测试。
- 待真实部署授权阶段核对：现役 MCP 实际 executable/source/hash/参数路径，初始化是否发生，其他进程或私有脚本读者，停止后的独占与 sidecar 证据，以及重新启动后目标绑定。这些信息均未在本次越界查询。
