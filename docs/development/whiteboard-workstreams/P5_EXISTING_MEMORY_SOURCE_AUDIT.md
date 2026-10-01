# P5 既有记忆来源只读审计

> 2026-09-05；基线 `v3-lab@4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`。
> 状态：三包已整合，Flutter 138/138；双端候选已生成，手机精确 APK 已安装/核对/启动，USB 通道已准备；当前等待用户开启临时读取会话。真实来源已核对，但 recall Gate 尚未通过。

## 结论

初始审计发现桌面 Dreaming 库为空；iCore 没有 Memory V3 / Dreaming 读取接口，手机 Gateway 的 Voice 投影也未接 Dreaming。手机一致快照已证实源端存在满足严格来源闭包的有效数据，因此随后实现专用手机只读通路；现在待候选部署和真实命中验收，不再把“没有可用源”当作阻塞原因。

用户已确认继续调查并补既有记忆只读接入。首次审计 ADB 在线设备为 `0`；随后连接唯一 `SM-S9110` 并暂停 App，本次 App 停止双重检查、只读 SQLite 完整性与必要列检查均通过。诊断结束已精确删除临时 DB/WAL/SHM 及空目录，没有保留副本或导入白板；手机 App 已重新打开（`am start -W` 返回 `Status: ok`，进程存在），不据此声称心率采集已经恢复。

## 真实来源结果（2026-09-05 18:55:44 +08:00）

手机库 schema `60`，仅查询结构、计数和来源引用；未查询或输出聊天 / 记忆正文，也未把来源文本发送给模型。

| 层级 | 原始条数 | 严格结构性资格计数 |
|---|---:|---:|
| Fragment | 1,215 | 1,166：active 2 + consolidated 1,164，引用均解析到 i 主聊天 |
| Episode | 377 | 342：active，全部引用上述合格 Fragment |
| Saga | 11 | 2：active，全部引用上述合格 Episode |

- 聊天总数 `6,581`，其中 i / chat / 非 TaskRoom `6,527`；User-truth 卡 `126`。卡片业务 `status='active'` 的字面计数为 `13`，**不是**所有当前有效 User-truth 的数量判断。
- Fragment 来源引用可解析的总数 `1,205` 中含 `deleted=39`，不计入合格来源；另有 `10` 条 local 引用不满足 i 主聊天条件。Episode `35` 条引用不合格来源；Saga `3` 条来源不合格、`6` 条引用数组不符合严格规则。这些是排除分类，不直接等同数据损坏，不进行修复或删除。
- 资格计数比现有 Runtime 的部分 Episode/Saga 引用解析更严格，也未执行相关性检索、候选窗口和排序；**不证明某一 query 会命中、已注入桌面 Runtime 或真人 Gate 通过**。
- 临时 probe `11/11` fixture 通过结果保留；真实快照命令 exit `0`、完整性通过且 finally 清理完成。桌面候选仍是 `4ba05b11`，生产代码与提示词未变。

## 手机已连接后的准备过程（历史）

- 只读确认设备、V3 包与运行状态，定向列举账户数据库文件元数据；DB 约 63 MB，WAL 约 4 MB。没有查询私人正文、复制数据库、关闭 App 或改动手机。
- 手机没有发现可用的 `sqlite3` 命令；当前可复用的快照机制要求 App 停止。已向用户说明暂停会中断可能正在进行的心率采集，并请求确认；不自动 force-stop，也不绕过一致性守门复制正在写入的 DB。
- 已准备临时元数据诊断 `tmp/p5-source-metadata/probe_phone_memory.mjs`：App 停止双重核对、临时只读 SQLite、完整性/必要列检查、数量及严格来源闭包聚合，不输出正文或 ID 列表；仅删除本次临时目录内三个精确快照文件。
- Fixture `11/11` 通过：有效闭包、不输出 ID、query-only 拒绝写入、空/重复/损坏证据、TaskRoom/其他角色隔离、deleted 来源拒绝、缺表诚实失败，以及 Episode 重复/超限/断裂。独立复核后补充结构与首个失败类别聚合输出。临时诊断采用更严格的状态和引用校验，不能冒充生产 Runtime 查询等价测试；尚未对手机运行。
- 上述等待已由用户随后确认和本次真实快照核对解除；最终真实查询命中仍须完成生产接线后单独验收。

## 可复核证据

| 来源 | 已有能力与边界 | 代码入口 |
|---|---|---|
| 桌面 Workbench | `AppDatabase.instance` 的近期 i 主聊天与 Dreaming；完整证据闭包，未读取手机 | `lib/data/workbench_ai/context/workbench_relationship_context.dart`；`lib/data/workbench_ai/workbench_conversation_coordinator.dart` |
| 手机 Voice Gateway | ADB 精确设备/账户、App 停止检查、临时 DB/WAL/SHM 快照、SQLite read-only/integrity check；后续 Voice 轮次只读进程内缓存 | `tools/i_continuity_gateway/i_voice_context.mjs` 的 `readAndroidVoiceSession`、`compileVoiceContextFromSnapshot`、`compileVoiceSessionFromSnapshot` |
| iCore | 已配对设备聊天提交、change feed、cursor ack；没有 Memory V3/Dreaming 投影或召回端点 | `tools/i_core/i_core_server.mjs`；`tools/i_core/i_core_store.mjs` |
| Flutter Core 同步 | `fetchChanges` 后写本地消息并 ack，不是纯上下文读取器 | `lib/data/services/sync/core_sync_client.dart`；`lib/data/services/sync/core_sync_engine.dart` |

本轮本机 `/v1/core/health` 实测在线，协议 `0.1`、schema `4`，features 为 `device_pairing / chat_submit / change_feed / cursor_ack`。未调用配对、消息、同步、worker 或外部动作端点。

## 适配约束与下一步

1. 不直接复用整个 Voice 投影：其近期聊天按最新 active character 选取，缺少 Workbench 的精确 i / 非 TaskRoom 过滤；不把 Voice 唤醒、会话缓存或手机 persona YAML 带入桌面。
2. 用户已经确认的桌面人格不变。白板数据库、Memory V3 writer、同步引擎和 Gateway 当前未提交修改不在本次来源审计写入范围。
3. 源端已确认存在 Dreaming，生产读取仍须逐 query 核验同一来源里的 Saga → Episode → Fragment → i 主聊天证据；不能把本次全库资格计数当成该轮查询结果。
4. 空结果、源不可用和来源未实现分别报告。快照不是实时同步；若采用快照方案，必须明确时效和失效条件，不能默默用旧数据冒充当前有效投影。
5. 现有快照机制要求手机 App 停止；本次仅在用户暂停后作临时诊断，不把它变成日常桌面记忆读取方式。不会为通过 Gate 生成记忆或启用导入。
6. 不扩建 iCore 的记忆同步/权威协议。下一步核定手机运行中按需只读查询的最小接缝；如需新增手机服务与安装候选，应将该新增部署范围明确交给用户确认，不伪装为已存在的桌面接线。

## 已确认的新增部署范围与派发

独立 Terra medium worker `/root/p5_live_readonly_seam` 与主窗复核现有手机运行中入口：OAuth loopback server 只处理授权回调，asset server 只服务本地资源，Dev Agent Bridge 手机侧是客户端，均无可直接复用的 Dreaming 读取端点。

建议只新增手机 V3 的有界只读记忆查询服务，抽取/复用 Memory V3 查询与来源闭包验证，桌面通过受控 USB 本机通道按需取结果；手机仍是既有记忆来源，不把 DB 导入桌面、不建立 iCore 记忆同步、不生成新记忆，也不改冻结人格。桌面→手机的 USB 方向应为 `adb forward`，不是 `reverse`；这是待实施的运输方案，不是已经创建的端口转发。手机入口须有显式启用、短时专用认证、固定身份/预算、关闭失效以及 empty/unavailable 区分，不能复用文件服务 token 或开放局域网。

该方案需要新增手机端代码并构建/安装新 `hereIAmV3` APK（保留物理安装授权），再重新构建桌面候选。Lynx 已明确答复“可以”，新增范围已授权，不再重复等待决定。当前未安装、未开启真实接口或端口转发，不涉及 Voice Gateway 改动。

执行目录 `.worktrees/p5-phone-readonly`，分支 `codex/whiteboard-w0-p5-phone-readonly`，精确基线 `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`。该目录三包按文件互斥写入，Git 索引、最终整合和构建由主窗串行处理。

| 包 | 执行者 | 拥有范围 | 状态 |
|---|---|---|---|
| 手机查询/会话服务 | `/root/p5_phone_read_server`，Astra high | Memory V3 readonly server/service、Drift/HTTP tests、自身 handoff | 已交接并整合 |
| 桌面 client/context | `/root/p5_phone_desktop_client`，Terra medium | readonly client、relationship context 最小接入、tests、自身 handoff | 已交接并整合 |
| 两端连接 UI | `/root/p5_phone_connection_ui`，Terra medium | 新连接页/VM、两端真实入口、tests、自身 handoff | 已交接并整合 |

主窗已经完成 offline 依赖准备，并新增仅负责 USB 精确转发的 helper（6/6 fixture），没有创建真实端口转发。工作包 wire/API 见隔离目录 `docs/development/whiteboard-workstreams/P5_PHONE_READONLY_CONTRACT.md`。固定短会话、默认关闭、token 仅内存；已配置手机来源发生网络断开/到期时返回 unavailable，不静默回退为空桌面记忆。现有 orchestrator 涉及 embedding 初始化/查询日志，手机纯读取包不整块调用它，只复用本地搜索与严格来源校验。

手机候选必须保留主工作区当前已安装版本的未提交 BLE 修复，不能用净旧基线 APK 覆盖；主窗已记录相关源文件指纹，构建时继续核对。人格与白板数据仍冻结，当前主线/原候选未变，未提交/推送/发布。

## 接入实现与最新验证

主窗已将 23 个 P5 路径选择性整合到 `v3-lab`；与隔离源逐一比对文本一致，20 个受保护手机/BLE 文件及 5 个原有 staged 控制文档 blob 未变。Flutter 专项和相邻回归 `138/138`、USB helper `6/6`；真实 Drift → HTTP → client → assembler → Runtime 输入 fixture 通过，另覆盖模型初始化等待中撤权、删除来源、空/不可用和显式断开。广路径静态检查退出 `0`，无错误/警告，两条风格 info。双端候选已生成、指纹与 APK 签名核对通过，详见 [P5 整合记录](P5_PHONE_READONLY_INTEGRATION.md)。手机已从 ADB 列表断开，尚未安装、真实转发或通过 recall Gate。

## 初始来源审计交付（历史步骤）

- 主窗审计桌面生产接线、iCore 路由与实际健康状态；Terra medium 子 Agent `/root/p5_existing_memory_route_audit` 独立审计 Gateway / Core / 同步边界，未修改文件、未派生子 Agent。
- 本轮仅更新审计与控制文档；未改产品代码、未构建、未提交/推送/发布。文档 diff 与引用检查独立执行。
- 原候选 `4ba05b11` 的人格通过结论保留；真实 recall、其余 P5 与 P6 仍待验。
