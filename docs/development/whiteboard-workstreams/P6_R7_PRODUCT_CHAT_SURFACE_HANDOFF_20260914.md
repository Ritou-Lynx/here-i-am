# P6 R7 普通产品 Chat Surface 候选交接

日期：2026-09-14。只新增受控聊天 Store、ViewModel、Surface 及专项测试；未改主入口、Provider、router、现有聊天页或 coordinator，也未启动 App、网络、认证、真实数据库或现役端口。

`WorkbenchProductChatStore` 显式接收已可信打开的 `AppDatabase`、固定角色 `i` 和同库 conversation id。它仅读写并 watch `persona_chat_messages`，按时间/id 倒序返回消息；用户原话不 trim。它拒绝错误角色、附件、空白和超长输入，并且不生成 device identity、sync outbox 或 dreaming 调度。DB 关闭继续归产品 resources/root。

`P6R7ProductChatViewModel` 显式接收此 store、同一个真实 `WorkbenchConversationCoordinator` 与 conversation id，发送经 `sendPersonaDesktopConversationEntry`，因此仍是 persist-first 与真实 message id。空白、附件、超长和落库错误统一转为可读失败结果，不写假消息也不调用 coordinator。它只维持一个活跃 send；quiesce 同步封新输入并等待该 send。若 fence 在原话落库期间命中，connector 在调用真实 coordinator 前保守拒绝，原话保留且不启动普通回合。stop 仅转交 coordinator，ACK 不作为终态；严格 `closeConversation` 仍由 root 注入的关闭 gateway 负责。dispose 同步 fence，取消 watch，后台 quiesce 错误被观察，并禁止晚到异步通知。

`P6R7ProductChatSurface` 只复用 `DesktopPersonaChatView` 的消息、输入、发送和停止；不使用普通单例、router、task lifecycle 按钮或固定任务输入。

专项测试覆盖：内存库原话保留、拒绝和零 outbox；共享入口在 connector 前持久化；无效输入零 runtime；原话落库与 quiesce 竞态不启动 coordinator；并发 send 拒绝、quiesce 等待/fence、dispose 后无晚到通知，以及已接受发送不清空期间新写草稿。此为本地候选代码证据，不是 App 启动、provider、host、队列执行、关闭终态或真人 Gate。
