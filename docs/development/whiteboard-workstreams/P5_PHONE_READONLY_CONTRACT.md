# P5 手机只读接入工作包契约

基线 `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b`；2026-09-05 用户已明确授权新增手机只读接口、更新 APK 与桌面接入。此工作包属于现有 Goal 1/P5，不新建 Goal；不涉及 Voice Gateway、iCore 同步、白板数据或已冻结 persona。

## 所有权

- Phone worker：`lib/data/memory_v3/readonly/phone_memory_read_server.dart`、`phone_dreaming_read_service.dart` 及匹配专项测试、`P5_PHONE_SERVER_HANDOFF.md`。
- Desktop worker：`lib/data/memory_v3/readonly/phone_memory_read_client.dart`、`lib/data/workbench_ai/context/workbench_relationship_context.dart` 的最小接入、匹配测试、`P5_PHONE_DESKTOP_HANDOFF.md`。不改 persona prompt。
- UI worker：新 `lib/ui/settings/view_models/phone_memory_connection_viewmodel.dart`、`widgets/phone_memory_connection_page.dart`，`core_sync_settings_page.dart` 与桌面设置可达入口的最小路由，匹配测试、`P5_PHONE_UI_HANDOFF.md`。不碰 `early_update_settings_card.dart`。
- 主窗：跨边界整合、必要契约修正、构建/安装、控制文档及 Git 索引。所有 worker 禁止派生、提交/暂存、构建/安装、操纵设备、触及真实数据；共享隔离目录仅写各自拥有路径。

## 固定 wire v1

手机 `127.0.0.1:47851`，仅显式启动后的短时会话（30 分钟，不自动续期）。桌面通过针对用户选定设备的 `adb forward --no-rebind tcp:47851 tcp:47851`，不监听 LAN、不覆盖其他转发。不依赖 iCore，不共享 OAuth/asset token。

所有请求必须带专用 `Authorization: Bearer <random session token>`；禁止 Origin（网页）、redirect、query-string token 和不支持的 method/path。token 至少 192-bit 随机，只在内存，停止/到期/账户变化后失效；不写日志、prefs、文件或聊天。服务不随 App 启动自动开启，绑定启动时账户，逐请求重新确认账户及角色 i 启用状态。

连接码：`p5v1.` 加 base64url(UTF-8 JSON)，仅字段 `{v:1, token:string, session_id:string, expires_at:UTC ISO}`。不含可配置 URL、path 或设备凭据。手机 UI 提供复制按钮，桌面用户粘贴；不在最终答复或日志中输出连接码。

- `GET /v1/memory/status`：认证后返回 `{schema_version:1, source_kind:'phone_v3_live', character_id:'i', session_id, captured_at, expires_at}`；不读取/返回记忆正文。
- `POST /v1/memory/read-context`：仅接受 `{schema_version:1, character_id:'i', query:string}`；非空 query，最多 2000 字符、请求字节最多 16KiB，拒绝额外字段。固定 Episode/Fragment/Saga 上限 `4/6/2`，不能由 caller 提高。
- 成功查询响应：上述状态公共字段，加 `dreaming_status:'available'|'empty'|'unavailable'` 和 `dreaming:{episodes:[{id,narrative,score}],fragments:[{id,content,score}],sagas:[{id,title,description}]}`。只能 available 有非空数据；unavailable 不返回任何旧数据，并可带固定非敏感 `reason`。单字段上限沿用桌面 `id120, narrative900, fragment300, title160, description900`，总响应最多 32KiB。
- 错误：`{error:{code:<fixed code>}}`；HTTP 400/401/403/404/405/413/429/503 语义明确，不返回异常堆栈、SQL、内部路径、token、query 或记忆正文。
- 每会话只允许一个查询运行，独立有界超时，不积压；关闭/到期或身份变更期间的在途结果也必须拒绝。不得调用 LLM、生成/记录/同步/修订任何数据；复用 Dreaming 只读查询与严格有效状态/来源闭包。不得把已删/hidden 来源经关系展开重新带回。

## 跨 worker Dart API

Phone：`PhoneMemoryReadServer extends ChangeNotifier`，`static instance`，`PhoneMemoryReadSession? get session`，`bool get isRunning`，`Future<Result<PhoneMemoryReadSession>> start()`，`Future<Result<void>> stop()`。session 提供 `connectionCode`、`expiresAt`、`port`。服务文件中定义 session，生产构造有测试注入接缝。

Desktop：`PhoneMemoryReadClient extends ChangeNotifier`，`static instance`，`bool get isConfigured`、`DateTime? get expiresAt`、`Map<String,Object?>? get lastReceipt`（仅 source/status/counts/time，不带 token、query 或正文）。`Future<Result<void>> connect(String connectionCode)` 先 authenticated status 验证再替换会话；`void disconnect()`；提供供 production context 使用的只读 query 方法，返回有界 DTO。Dio 使用 localhost 固定地址，禁止代理/redirect，短时超时；连接只留进程内，不后台重连/持久保存 token。

两端 UI：设置内可达的“桌面记忆只读连接”页。手机显式开启/关闭、显示到期、复制码；桌面粘贴/连接/断开、最近一次非正文回执。说明需 USB、手机 App 运行、连接不搬运整库；App 退出与会话到期后重开需重新授权。不自动显示任何记忆正文。按当前平台选择分支，ViewModel 用现有 Command/Result。

Desktop composition：只有已配置且 scope=i/persona:i 的情况下替换 Dreaming 来源；persona 和近期本地聊天保留现状。未配置继续现有本地来源，配置后断开/过期/错误不得静默回退成本地 empty。prompt 带来源、采样时间、状态的简短元数据，不再扩写人格规则。新增 tests 证明 wire → context → Runtime input 的真实接线和超时/隔离/删除边界。

## 验证与候选

专项真实 Drift、HTTP、client、UI/route 与 Runtime 组合验证，随后独立复审。Flutter 每次 build 前 critical 脚本。Windows 用隔离候选；手机候选必须保留主目录当前已安装版本的 BLE 修复，主窗选择性整合后构建并记录 dirty-source/产物 hash，不以干净旧基线 APK 覆盖现有 BLE 修复。安装只 hereIAmV3、保留物理确认。未取得真实候选回复，不标记 P5 Gate 通过。
