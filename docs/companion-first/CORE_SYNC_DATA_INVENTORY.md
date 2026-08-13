# 林埃核心同步数据清单 v0

> 日期：2026-08-13
> 目的：定义私人电脑权威核心、各客户端和对象存储分别拥有什么。本文是 Phase 0 的数据边界，不是数据库逐表复制方案。

## 1. 分类原则

每类数据只能有一个明确角色：

| 类别 | 含义 | 多端策略 |
|---|---|---|
| 核心事实 | 用户或林埃真正产生、不能靠计算恢复的内容 | 只在核心权威写入；客户端增量读取或提交操作 |
| 核心投影 | 从事实整理出的长期结果，可能含用户反馈 | 由核心生成和版本化；客户端只读，反馈走独立操作 |
| 可重建缓存 | 丢失后可以由核心事实重新生成 | 不同步，只在核心重建 |
| 设备状态 | 只对某一台设备有意义 | 留在设备本地；必要时以 deviceId 分区上传 |
| 二进制对象 | 图片、书籍、视频、音频等大文件 | 核心对象存储保存原件；客户端按需缓存 |

禁止把整张 SQLite 表当作默认同步单位。同步单位是版本化事件、不可变消息或明确的领域操作。

## 2. 核心事实

### 2.1 第一批必须进入核心

| 领域 | 当前来源 | 权威写入规则 | 客户端持有 |
|---|---|---|---|
| 角色聊天 | `persona_chat_messages` | 客户端可提交用户消息；角色消息只由核心生成；`sync_id` 幂等 | 近期窗口 + 离线 outbox |
| User-truth | `memory_cards`、sources、structured fields、relations、assets、operations | 只有显式记录、外部数据流或用户修正才能写 | 只读投影 + 待提交操作 |
| 用户修正 | `user_corrections`、召回反馈 | 作为独立 append-only 操作写核心 | 本地 optimistic 状态 |
| Topic Thread | threads、sessions | 核心整理；`corePositions` 仍需用户确认 | 当前相关话题缓存 |
| Check-in / 提醒 | `system_message_queue` 及提醒语义 | 只由核心调度与领取，防止多端重复 | 设备只接收投递结果 |
| 角色与 Agent 配置 | Character YAML、agent config、可移植设置 | 核心保存当前版本；修改走带版本操作 | 必要配置缓存 |

### 2.2 后续纳入核心的事实域

- 阅读：书目、章节源内容、阅读进度、用户批注、林埃批注、共读 Session 与消息绑定。
- 漫画与影片：作品元数据、字幕、时间轴锚点、观看进度、批注与讨论引用。
- 财务：Ledger 与购买记录；原始记录不可由洞察反推。
- 健康与日程：外部导入原始记录、用户明确确认的计划/例外/修正。
- 白板：空间、白板、节点、分组、连线、锚点、归属、授权与操作日志。
- 通话：会话与消息正文；设备音频缓存不属于核心事实。

## 3. 核心投影

以下数据由核心唯一生成，客户端不能直接覆盖：

- Dreaming：Fragment、Episode、Saga、Saga Snapshot、Memory Entity / Link。
- Life Insight、User Rhythm、Growth Pact 当前状态及检查结果。
- Project Memory 当前投影。
- Memory Recall trace。用户的“有帮助 / 不相关”是独立事实，不能因重建 trace 丢失。
- Record Organizer 生成的 Memory Card 展示与结构化结果；其来源和人工修正必须可追溯。

投影必须带生成版本、来源引用和更新时间。模型升级时由核心重建或迁移，不能让多台设备分别生成后合并。

## 4. 可重建缓存

以下内容不进入增量同步真相：

- FTS 虚表与全文索引。
- embedding 向量。
- `CardCache`、SharedLife summary 等检索或展示缓存。
- Dreaming / capture cursor、后台 Tasks、处理队列、重试计数。
- 缩略图、转码文件、TTS 音频缓存、下载 partial 文件。
- LLM response cache、日志和诊断快照。

这些数据可以备份用于恢复速度，但恢复后不具有比核心事实更高的权威性。

## 5. 设备状态

以下数据必须按设备隔离：

- 安装身份 `deviceId`；绝不随备份或配置同步复制。
- 每台设备的同步 cursor、outbox、失败重试与最后在线时间。
- 聊天已读位置、通知是否已投递/点击、当前打开页面。
- 下载完成情况、离线缓存、模型包和媒体缓存。
- Android SAF 权限、相册/麦克风/无障碍授权、系统通知 token。
- UI 布局、窗口尺寸和设备特有偏好。

当前 `PersonaChatMessages.isRead` 是单机遗留字段。跨设备协议不传这个字段；后续改为 `(deviceId, conversationId, lastReadSequence)` 形式的设备读取位置。

## 6. 二进制对象

核心数据库只存对象元数据：

- `assetId`（UUID）
- SHA-256
- MIME type
- 字节数
- 原始文件名
- 创建者 / 归属空间
- 来源与稳定锚点
- 对象存储相对路径

原件按内容哈希保存，客户端按需下载并校验 SHA-256。聊天消息只引用 `assetId`，不在增量 JSON 中长期传 base64。现有 `attachmentsJson` 中的 base64 是迁移兼容形态，不能成为核心协议。

## 7. 消息引用迁移

当前多个领域仍引用本机整数消息 ID：

- Dreaming Fragment `sourceMessageIds`
- SharedLife operation `sourceMessageIds`
- 共读 Session message
- Memory Card `sourceRef`
- 召回 trace 与原对话定位

迁移顺序：

1. schema v55 为所有聊天补齐 `syncId`，保留整数 `id`。
2. 新增稳定引用字段，写入时同时保存整数 ID 与 `syncId`。
3. 读取优先稳定引用，缺失时回退整数 ID。
4. 完成历史回填与核对后，跨设备 API 永远不暴露本机整数 ID。
5. 整数 ID 可长期作为单库内部性能键，但不再承担证据身份。

## 8. 第一阶段同步范围

私人电脑最小核心首轮只开放：

1. 设备注册与配对；
2. 用户聊天消息幂等提交；
3. 聊天与核心生成回复的增量拉取；
4. 设备 cursor 确认；
5. 核心健康状态。

Memory V3、Dreaming 和 Check-in 在核心内部继续使用现有实现，但第一轮客户端只通过聊天变化间接看到结果。待消息链路稳定后，再逐域开放 Memory V3、资料库和白板 change kind。
