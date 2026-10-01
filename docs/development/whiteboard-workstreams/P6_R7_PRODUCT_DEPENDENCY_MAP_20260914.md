# P6 R7 普通桌面入口依赖图（只读审计）

日期：2026-09-14。范围仅为 P6 的 Debug 候选：以真实普通桌面聊天 UI、当前原话授权队列工具、全新独立数据与 App-owned text host 形成可审接线。本文不启动 App、Bridge、provider 或队列，不读取个人数据库、认证或现役端口。

## 结论

可以复用普通桌面聊天的真实 UI 和现有 `WorkbenchConversationCoordinator.send()` / `manage_long_task_queue` 授权链，但**不能**把当前 `main.dart` 或 `GlobalDesktopChatOverlayHost` 原样作为候选 bootstrap。两者在到达聊天前已经选择普通用户数据、`AppDatabase.instance`、`SharedLifeMemoryService`，并会进入普通全局服务路径。

也不能只把 `WorkbenchTextTaskRuntimeClient` 的 endpoint 指到新 host：普通 coordinator 的默认动态工具同时带入关系上下文、搜索、白板和普通 `PersonaChatService` 写回；它们均可达普通单例数据。候选必须显式装配一个受控 coordinator，并以独立的聊天持久化实现提供该轮已持久化的用户原话和 `userMessageId`。

## 实际入口与可达依赖

| 层 | 当前真实路径 | 可达资源 / endpoint | Debug 候选处理 |
|---|---|---|---|
| 桌面入口 | `MemexApp.builder` → `GlobalDesktopChatOverlayHost` → `GlobalDesktopChatOverlay` → `DesktopChatOverlay` → `DesktopChatPopover` → `PersonaChatScreen` | `GlobalDesktopChatOverlay` 用 `CharacterService.instance` + `UserStorage` 解析角色；默认固定 `i` 时仍进入 `PersonaChatScreen` 的单例聊天服务 | UI 壳可复用；候选必须传入固定、封包内的角色显示数据或受控 resolver，不能调用 `CharacterService.instance` / `UserStorage`。`DesktopChatPopover` 需增加受控 composition 参数并下传。 |
| 普通桌面发送 | `PersonaChatScreen._sendDesktopMessage()` → `sendPersonaDesktopConversationEntry()` | 先由 `PersonaChatService.instance.addUserMessage()` 写入用户原话；该行的 id 传入 coordinator，供 whiteboard authorization 记录消息证据 | 保留此顺序和真实 `userMessageId`，但使 `PersonaChatService` 可构造并绑定候选 DB；候选不得使用普通 singleton。queue authorization 仍只从 `conversationId` 与当前 `userText` 计算。不能用 mock coordinator 或固定数字按钮替代。 |
| 普通协调器 | `WorkbenchConversationCoordinator.instance` → `productionComposition()` | 默认 runtime `WorkbenchRuntimeClient()`；关系上下文、搜索、queue tool、白板 tool 和回写均由普通单例构成 | 新建一次候选 composition，保留 `WorkbenchConversationCoordinator` 实例与实际 `send` 代码；只提供候选 runtime、候选 reply writer、候选 queue tool。关系 / 搜索 / 白板一律不传入，因此不会被列入 dynamic tools。 |
| 普通对话 runtime | `WorkbenchRuntimeClient()` | 默认 loopback `http://127.0.0.1:47831`；`/experimental/v1/runtime/sessions`、`/sessions/resume`、`/sessions/{id}/turns`、`/events`、`/tool-calls/{id}`、`DELETE /sessions/{id}`；provider 由 response metadata 返回 | 不能以候选 text host 替换这条普通对话 runtime，也不能接触现役 `47831`。候选原则上沿用既有会话已授权的专用 ChatGPT/Codex provider、认证与费用来源；实现 / Gate 只核查可否原样沿用，不能读取、复制或改变认证，也不能改费用来源。只有确需新来源或新服务时，才另行标明真实决定。 |
| 受限任务 runtime | `WorkbenchRuntimeTaskQueueTool.production()` → `_productionExecution()` → `WorkbenchTextTaskRuntimeClient()` | 默认也会落到 `47831`，仅在 response receipt 证明 `workbench_text_only_v1`、tools disabled、epoch / provider-thread binding 时放行 | 可复用 `WorkbenchRuntimeTaskQueueTool`、`WorkbenchTaskQueueExecution` 和 `WorkbenchTaskQueueLifecycleOwner`，但必须像候选入口一样显式注入同一候选 `TaskRoomService`、同一 execution、以及封包配置的 App-owned client。不得调用 `.production()`。 |
| 原话授权与队列 | coordinator 在发送前调用 `authorizationForTurn(conversationId, userText)`；工具宿主为 `WorkbenchTaskQueueToolHost` | `DesktopWorkbenchTaskQueueAuthorizationFactory` 从当前用户 text 计算 actions / exact UUID；工具参数不能提供 scope 或授权。入队、状态、开始、暂停、恢复、取消、重试都在 `TaskRoomService` 的 conversation scope 内复核 | 可直接复用。候选 conversation id 必须稳定且来自候选会话；入队仍取该轮用户真实文本，status 的 latest-task 例外仍只读。不要把候选固定任务 id 或预设成功结果接入这一链。 |
| TaskRoom 数据 | `TaskRoomService.instance` 由 `MemexRouter._init()` 使用 `AppDatabase.instance` 初始化并在启动时做 `restoreInterruptedTaskRoomsOnce()` | 普通 TaskRooms、全局静态 service | `TaskRoomService(db: candidateDb)` 可直接构造；当前 tool 只接受 loader，适合注入。为兼容 execution 可在候选进程内初始化 static instance，但候选 root 不得先初始化普通 DB，且需在 closeout 后明确终止其引用。更小的长期改动是让候选 composition 只保有构造服务，不依赖 `TaskRoomService.instance`。 |
| 独立数据库 | `AppDatabase.init(userId)` 是进程单例；候选已有 `AppDatabase.openCandidate(NativeDatabase(...))`，不会注册普通 singleton | `openCandidate` 仅 Debug、由调用方拥有路径与关闭；候选 `P6R7CandidateStore` 已完成目录 / marker / lock / admission / close 的边界 | 可复用 `P6R7CandidateStore` 与 `openCandidate`，但普通 `PersonaChatService` 不能直接使用它，因为该 service 的 `_db` 固定为 `AppDatabase.instance`。 |

## 当前普通 composition 中必须断开的支路

1. `main()` 的 desktop 分支会读取/必要时写入用户标识，再执行 `AppDatabase.init(userId)`、`SharedLifeMemoryService.init(...)`；随后无条件 `LocalServerService.start()`。这已违反“全新独立数据、不得启动自动后台服务”的候选边界。因此 Debug target 应使用专属 candidate main，而非给普通 `main.dart` 加一个松散环境变量。
2. `MemexRouter` 是单例构造即启动 `_ensureInitialized()`。它会建立普通 data root/DB、初始化 `TaskRoomService`、恢复持久队列，并启动/排程同步、dreaming、reading 等服务。候选依赖 providers 不应包含 `dependencyProviders` 的 `MemexRouter` provider，也不应挂载普通 router/shell。
3. `WorkbenchConversationCoordinator.instance` 默认接入 `WorkbenchRelationshipContextAssembler.production(AppDatabase.instance)`、`WorkbenchRuntimeSearchTool.production(AppDatabase.instance, WhiteboardDataBootstrap.productionRepository)`、`WorkbenchRuntimeWhiteboardDomainTool.production()`，以及 `PersonaChatService.instance.addCharacterMessage`。这四项均不可达候选。
4. `PersonaChatService.instance` 固定 `AppDatabase.instance`；写入 user / assistant 消息会生成设备 identity、写 `sync_outbox_messages`，并调用 dreaming scheduler。即便将 `AppDatabase.instance` 临时指向候选 DB，也会把候选消息纳入普通 outbox/自动调度语义，不能作为隔离证明。
5. `PersonaChatScreen` 还直接用 `CharacterService.instance`、`ActivePersonaChatService.instance`、`MemexRouter()` 和若干 `AppDatabase.instance` 的附加 UI 功能（头像、话题回填、阅读/记忆面板等）。因此“整个完整聊天页”的原样复用不成立；第一候选应只保留普通桌面输入、消息列表、发送/停止及动态 queue tool 这一实际入口，而将其他入口显式隐藏或 fail closed。

## 最小可实施装配

新建候选专用 bootstrap（不改默认生产 composition）时，最小对象图如下：

```text
candidate store.open() -> candidateDb
  -> CandidateChatStore(candidateDb, no sync-outbox, no scheduler)
  -> TaskRoomService(candidateDb)
  -> candidate WorkbenchTextTaskRuntimeClient(sealed App-owned host URI)
  -> WorkbenchTaskQueueExecution + one lifecycle owner
  -> WorkbenchRuntimeTaskQueueTool(loadService: candidate service,
                                  loadExecutionController: same execution)
  -> WorkbenchConversationCoordinator(
       runtime: approved normal-conversation gateway,
       addReply: CandidateChatStore.addCharacterMessage,
       taskQueueTool: above tool,
       bindingStore: candidate-local/durable binding store,
       relationshipContextProvider/searchTool/whiteboardTool: null)
  -> constrained PersonaChatScreen/desktop popover
       (CandidateChatStore, candidate coordinator, fixed candidate character)
```

其中 queue tool 保持生产的 `DesktopWorkbenchTaskQueueAuthorizationFactory`。`sendPersonaDesktopConversationEntry` 已可复用为“先持久化用户原话、再传 coordinator”的实际入口；需要的改动是让屏幕取得上述 `CandidateChatStore` / coordinator，而不是在 `_sendDesktopMessage()` 与 `_stopDesktopConversation()` 中读取 `.instance`。

建议的最小代码面：

1. 为聊天持久化提取窄接口（读取消息、`addUserMessage`、`addCharacterMessage`、retract/notify）；给 `PersonaChatService` 增加受控 DB 构造与候选禁用 outbox / dreaming 的实现，或新增候选实现。不要重用普通 singleton。
2. 给 `PersonaChatScreen` 增加可选的 chat store、coordinator、stop callback 和 character resolver；默认值仍维持既有 singleton 行为。`DesktopChatPopover` / overlay 只转发这些依赖。候选使用相同 UI 的发送函数，不改变授权 factory。
3. 新建 `WorkbenchTaskProductSession` 一类的显式组合根，持有 candidate service、runtime、execution、owner、client 与 close 顺序；它创建候选 coordinator，禁止 model 提供 endpoint、数据目录或 host ownership 参数。
4. 候选 root 仅挂载受控 chat popover/page，不使用 `MemexApp`、普通 `dependencyProviders`、`createAppRouter` 或 `GlobalDesktopChatOverlayHost` 默认 resolver。关闭先封新 turn/queue 写入，关闭 lifecycle/execution 与 host，再 close client/store；unknown 不能记作 app closed。

## 验证证据、阻塞与下一 Gate

本图由静态源码审计得出：`lib/main.dart` 的 desktop bootstrap / `MemexApp.builder`，`lib/config/dependencies.dart`，`lib/ui/desktop/widgets/global_desktop_chat_overlay.dart` 与 `desktop_chat_overlay.dart`，`lib/ui/character/widgets/persona_chat_screen.dart`，`lib/data/workbench_ai/workbench_conversation_coordinator.dart`、`task_queue/workbench_runtime_task_queue_tool.dart`、`task_queue/workbench_task_queue_tool_host.dart`、`workbench_runtime_client.dart`，`lib/data/memory_v3/services/task_room_service.dart`，`lib/data/repositories/memex_router.dart`，以及候选 `lib/p6_r7_candidate_main.dart` / `candidate/p6_r7_candidate_store.dart`。未运行 Flutter、App、Bridge、provider 或数据库查询。

阻塞不是 queue tool 本身：它已有可注入 `loadService` / execution seam，且当前原话授权仍在 coordinator 内按 `conversationId` 与 `userText` 计算。实际缺口是普通桌面聊天 UI 对普通全局聊天/角色/协调器的隐式依赖。实现前必须先审定候选聊天持久化不写 sync outbox、不排程 dreaming，并核查受控普通对话 gateway 能否原样沿用既有专用 ChatGPT/Codex provider、认证与费用来源且固定 endpoint / admission；该核查不构成新的认证或费用授权。未满足隔离和可信启动条件时，候选必须保持关闭，不能用 mock coordinator、固定按钮或 `47831`/`47841` 的现役实例补齐。

现役 `47831`、`47841` 与默认生产 profile 在本审计中没有被读取、连接或修改。
