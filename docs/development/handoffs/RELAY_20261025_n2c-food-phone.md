<!-- relay:contract v1 -->
# N2c 合同：手机自动领取饮食只读令牌，App 饮食页从 Core 同步（源码与合成测试）

> 已核对 v3-lab `129ec19`（N1 #59、N2a #62、D2b #64 已合并；N2b #63 待合并，与本合同无文件重叠）。用户 10-25 选定“手机自动领取（零操作）”：已配对的手机用自己的设备令牌向 Core 领取饮食只读令牌，不需要用户粘贴任何东西。本合同只改源码，不碰生产。

## 背景
- N2a 已经能在 Core 里登记 `food_entries`，并发出两张领域令牌：`food-mcp-writer` 和 `phone-food-reader`（`personal_data_domains.mjs` 的 `foodPrincipalConfigs()`、`provisionFoodDomain()`）。手机令牌只能读 `food_entries`。
- 领域 HTTP（`domain_http.mjs` 第 140 行）拒绝设备令牌，所以手机必须拿到 `phone-food-reader` 令牌才能同步。原计划是电脑端开通脚本用 `-Rotate phone` 输出令牌、用户手动送到手机，现改为手机自己领取。
- 手机已经保存了 Core 地址、设备令牌和节点号（`lib/data/services/sync/core_sync_connection_store.dart`，存在 `flutter_secure_storage`）。领取请求就用这套凭据。
- App 侧现状：
  - `PersonalDataHub.attach()`（`lib/data/personal_data_hub/personal_data_hub.dart`）在生产中没有任何调用。所以 `FoodHostScreen` 里 `hub.storeFor('food_entries')` 永远是 null，饮食页显示“尚未配置”。
  - `CoreSyncRuntimeService._performSync()`（`core_sync_runtime_service.dart` 第 183–185 行）每次聊天同步前已经调用 `hub.syncConfiguredOnce()`。只要食物领域已 attach，就会跟着聊天一起同步。
  - `DomainStore.configureRoute()` 可以把领域切到 `core`。`DomainHttpTransport` 已经实现了领域协议。`FoodService` 已能读取 core 副本并处理 `route`、`cursor`、`binding_changed` 等状态。
- 运行包清单不能加文件（N2a 合同已说明：`INVENTORY` 48 项和 `package.mjs`、`package_switch.mjs` 的哈希被钉死）。`i_core_server.mjs`、`personal_data_domains.mjs` 本来就在清单里，可以改内容。

## 设计要点
- 领取接口：`POST /v1/core/food/phone-credential`。路径故意不在 `/v1/core/domains/` 下，避免进入领域 HTTP 处理器。
- 认证：沿用 `requireDevice`，即 `X-Core-Protocol` 头加设备令牌。只接受 `platform === 'android'`、不是外部前端（`isExternalFrontendDevice` 为 false）、`device_id` 不以 `frontend:` 开头的设备。其他设备一律返回 403 `phone_device_required`。
- 每次领取都轮换 `phone-food-reader`，旧手机令牌随即失效。轮换只会发生在手机没有令牌或令牌失效时，不会被频繁调用。
- 领取前，食物领域必须已经由 N2a 开通，且与预期一致：mode 为 `authoritative`，hooks 版本为 `food-v1`，schema 一致，`phone-food-reader` 存在且 `active`。否则返回 409 `food_not_provisioned`，不做任何修改。
- 手机写入能力不变：`phone-food-reader` 仍然只有 `food_entries:read`。领取接口不能发出写入令牌，也不能修改 principal 配置。
- App 零操作：只要聊天同步已配对，App 就会在后台领取并 attach，不需要新的设置页。断开这台设备时，食物令牌一起清除。

## 完成标准

**1. Core：领取逻辑（`tools/i_core/personal_data_domains.mjs`，只追加在食物一节末尾）**
- [ ] 新增导出 `claimFoodPhoneCredential(domains)`，在一个事务里完成：
  - 检查领域登记和 `phone-food-reader` 的状态（见上节）。任何一项不满足，抛出 `code: 'food_not_provisioned'` 的错误，数据库无变化。
  - 调用 `domains.rotatePrincipal(FOOD_PHONE_PRINCIPAL_ID)`，并且必须保持 `foodPrincipalConfigs().phone` 的原配置。如果库里的配置与源码不同（scope 或 actors 被改过），按 `food_not_provisioned` 处理，不轮换。
  - 返回 `{format:'food-phone-credential-v1', domain:'food_entries', principal_id, generation, core_instance_id: domains.nodeId, token}`。
- [ ] 不改 `provisionFoodDomain` 和 N1、N2a 的既有导出。

**2. Core：路由（`tools/i_core/i_core_server.mjs`）**
- [ ] 在设备类路由附近加 `POST /v1/core/food/phone-credential`：
  - 先 `requireDevice`，再按上节检查设备类型。
  - 请求体必须是 JSON 对象 `{}`，长度不超过 1024 字节，有多余键返回 400 `invalid_request`。
  - `store.domains` 不存在时返回 503 `food_not_provisioned`。
  - 调用 `claimFoodPhoneCredential(store.domains)`，成功返回 200，响应头加 `Cache-Control: no-store`。
  - 令牌不得进入日志、诊断或错误消息。
- [ ] 不改 `domain_http.mjs`、`domain_store.mjs`、`i_core_store.mjs`，不放宽 `domain_http.mjs` 对设备令牌的拒绝。不改 `runtime_child.mjs`、`package.mjs`、`package_switch.mjs`、`INVENTORY`。

**3. App：领取与连接（新 `lib/data/personal_data_hub/food_connection.dart`）**
- [ ] `FoodCredentialStore`：放在 `flutter_secure_storage`，独立的键名前缀 `i_core_food_`。保存 `token`、`generation`、`principal_id`、`core_instance_id`、`base_url`。和 `CoreSyncConnectionStore` 一样，不进 SharedPreferences、配置同步或备份。
- [ ] `FoodPhoneCredentialClient`：用 Dio 向 `<baseUrl>/v1/core/food/phone-credential` 发请求，带 `Authorization: Bearer <设备令牌>` 和 `X-Core-Protocol`（取值与 `core_sync_client.dart` 相同，引用同一常量，不要复制字符串）。
  - 严格校验响应：`format`、`domain`、`principal_id === 'phone-food-reader'`、`core_instance_id` 等于已保存的 `coreNodeId`、`generation` 为正整数、`token` 至少 24 字符。任何一项不符都按失败处理，不保存。
  - 只接受 2xx。其余情况把服务端的 `error`/`code` 映射成固定错误码，至少包括 `food_not_provisioned`、`phone_device_required`、`unauthorized`、`network_error`。
- [ ] `FoodConnector`（单例或由 runtime 持有，二选一，在 PR 描述里说明）。提供 `ensureAttached(PersonalDataHub hub)`：
  - 读取 `CoreSyncConnectionStore`。没有聊天连接时直接返回，状态记为“未连接林埃核心”。
  - 已存的食物凭据与当前 `baseUrl`、`coreNodeId` 一致时直接使用；不一致或不存在时领取一次。
  - 构造 `DomainStore(db, binding: DomainBinding(coreInstanceId: 节点号, principalId: 'phone-food-reader', generation: 领取到的 generation, installationId: 本机 DeviceIdentityService 的 installation id))`，以及 `DomainHttpTransport(baseUrl, token, binding)`。调用 `hub.attach('food_entries', store, transport, allowLocalRecall: false)`。
  - 切换路由：领域存储里的 binding 与新 binding 不同时，先 `resetCredentialView('food_entries')`；`route` 不是 `core` 时再 `configureRoute('food_entries', DomainRoute.core)`。手机从不写食物，所以 outbox 必定为空。
  - 已 attach 且 binding 未变时不重复 attach。
  - 同步返回 `unauthenticated` 或 `credential_expired`（例如电脑端用 `-Rotate phone` 换过令牌）时，清除食物凭据并重新领取一次。每次 App 进程内最多重领一次，避免轮换来回打架。
  - `food_not_provisioned` 时不重试，下次聊天同步时再试，并记录状态“电脑端尚未开通饮食同步”。
  - 令牌不得出现在日志、异常消息或 UI 中。
- [ ] 接入点：
  - `CoreSyncRuntimeService._performSync()` 在调用 `syncConfiguredOnce()` 之前调用 `FoodConnector.ensureAttached(hub)`。异常要吞掉并记录状态，绝不能影响聊天同步。
  - `CoreSyncRuntimeService.disconnect()` 同时清除食物凭据。若食物领域已 attach，需要让它脱离：`PersonalDataHub` 可以追加一个 `detach(domain)` 方法（只追加，不改 `attach` 的语义），或者用等价方式让饮食页回到“未连接”。
  - `pair()` 之后的 `syncNow(reason: 'paired')` 会自然触发领取，不需要额外调用。
- [ ] 不改 `planning`、`captures` 等其他领域的行为。不为它们 attach 任何东西。

**4. App：饮食页**
- [ ] `FoodHostScreen` 在食物领域被 attach 或 detach 之后，不需要重新进页面就能切换到新的 store。可以监听 `hub.changes`，也可以让 `FoodService` 每次读取时向 hub 取 store。
- [ ] 打开饮食页时，如果已 attach，就在后台调用一次 `hub.syncOnce('food_entries')`。页面支持下拉刷新，刷新时先 `ensureAttached` 再 `syncOnce`。同步失败不能清空已显示的数据。
- [ ] 状态文字（中文，短）：
  - 未配对：“尚未连接林埃核心”
  - `food_not_provisioned`：“电脑端尚未开通饮食同步”
  - 首次同步前：沿用 `FoodService` 的“等待首次同步”
  - 同步失败：“同步失败，下拉重试”
  - `FoodService` 现有的其他文字不改。
- [ ] `core_sync_settings_page.dart` 在现有状态区下方加一行只读状态“饮食同步：已连接 / 电脑端尚未开通 / 未连接”。不加按钮，不加输入框。

**5. 测试**
- [ ] Node（追加到 `tools/i_core/food_domains.test.mjs`，或新建 `tools/i_core/food_phone_credential.test.mjs`）。用真 `createICoreServer` 加 food hooks，走 HTTP：
  - 未开通时：android 设备领取得到 409 `food_not_provisioned`，数据库无变化。
  - 开通后：android 设备领取得到 200 和 `no-store`。返回的令牌能读 `food_entries` 的 snapshot 和 changes，create 得到 `scope_forbidden`。
  - 第二次领取后，第一次的令牌被拒绝（401），新令牌可用。写入令牌不受影响，MCP 写入仍然正常。
  - 外部前端设备（`frontend:claude` 加外部前端 platform）得到 403 `phone_device_required`。无令牌得到 401，缺 `X-Core-Protocol` 得到 426，请求体有多余键或超长得到 400。
  - 库里 `phone-food-reader` 被 revoke，或配置被改成带写 scope：得到 409，且不轮换。
  - 日志或诊断回调里不出现令牌（用一个收集器断言）。
- [ ] 断言 `INVENTORY` 仍为 48 项，`package.mjs` 和 `package_switch.mjs` 的哈希不变（复用 R1 测试常量）。
- [ ] Flutter（新建 `test/data/personal_data_hub/food_connection_test.dart`，可复用 `food_service_test.dart`、`domain_sync_test.dart` 的夹具）。用假的 credential client 和假的 transport：
  - 没有聊天连接：不领取，不 attach。
  - 领取成功：attach `food_entries`，route 变为 `core`，`syncOnce` 后 `FoodService.read` 能读到记录。
  - 响应的 `core_instance_id` 与已存节点号不同：拒绝，不保存，不 attach。
  - 同步返回 `unauthenticated`：清除凭据并重领一次；第二次仍失败就停止，不再重领。
  - `food_not_provisioned`：状态文字正确，不 attach。
  - 断开设备：食物凭据被清除，饮食页回到“尚未连接林埃核心”。
  - 领取或 attach 抛异常时，`CoreSyncRuntimeService` 的聊天同步照常进行（可以只测 `ensureAttached` 的异常被吞掉）。
  - 已 attach、binding 未变时，再调用一次 `ensureAttached` 不会 reset 副本。
- [ ] Widget 测试：`FoodHostScreen` 在 attach 后无需重进页面就显示数据；下拉刷新会触发同步。

**6. 文档**
- [ ] `tools/i_core/maintenance/README.md` 的“食物领域开通”一节补一段：手机会自动领取只读令牌；`-Rotate phone` 会让手机下次同步时自动重领；开通脚本输出的 `phone_token` 不再需要人工处理。
- [ ] `DEVLOG.md` 追加一条 N2c 记录（只追加）。

## 允许修改的路径
- 修改：`tools/i_core/personal_data_domains.mjs`（只追加）、`tools/i_core/i_core_server.mjs`、`tools/i_core/maintenance/README.md`、`DEVLOG.md`（只追加）
- 修改：`lib/data/personal_data_hub/personal_data_hub.dart`（只追加 `detach`）、`lib/data/services/sync/core_sync_runtime_service.dart`、`lib/ui/food/widgets/food_host_screen.dart`、`lib/ui/food/widgets/food_screen.dart`、`lib/data/personal_data_hub/food_service.dart`（只在需要按 hub 取 store 时改）、`lib/ui/settings/widgets/core_sync_settings_page.dart`
- 新建：`lib/data/personal_data_hub/food_connection.dart`、`tools/i_core/food_phone_credential.test.mjs`、`test/data/personal_data_hub/food_connection_test.dart`，以及必要的 widget 测试文件
- 追加：`tools/i_core/food_domains.test.mjs`、`test/data/personal_data_hub/food_service_test.dart`
- 既有测试只能追加，不能改已有断言。若某处钉了 `i_core_server.mjs` 或 `personal_data_domains.mjs` 的哈希，就停下，发 blocked 说明具体位置。
- `docs/development/handoffs/RELAY_20261025_n2c-food-phone.md` 只由 Claude 改。

## 不做 / 边界
- 不碰生产：不换包，不运行开通脚本，不登记任务，不接触真实数据库、令牌或手机。
- 不改 MCP（N2b）和 `tools/i_remote_mcp/` 下的任何文件。
- 手机不写食物，不加任何食物写入入口。
- 不新增依赖（`dio`、`flutter_secure_storage` 已经在用）。不放宽任何现有校验。
- 止损：同一测试名或错误码连续两个提交失败，就发 blocked。最多 3 轮。

## 验证命令
- `node --test tools/i_core/*.test.mjs tools/i_core/release_schema6/*.test.mjs`。基线上已失败的 PowerShell、SMTP、计时类用例请列出名字，不必修。
- `node --test tools/i_core/food_domains.test.mjs tools/i_core/food_phone_credential.test.mjs tools/i_core/release_schema6/maintenance_n2a_food.test.mjs tools/i_core/release_schema6/maintenance_r1_pairing.test.mjs`：全部通过。
- `flutter test test/data/personal_data_hub/ test/data/services/sync/`，以及新加的 widget 测试：全部通过。
- `flutter analyze` 不新增问题。
- CI 全绿。

## 之后（不在本合同）
- 窗口 1：换 Core 包（包含 N2a 和本合同的 Core 部分），然后运行开通脚本，把写入令牌经 stdin 交给 N2b 的 `set-food-credential`。
- 窗口 2：用 N2b 候选执行 `update-mcp-source`，`--from-task` 用 D2b 的现役任务，然后重启会话，三端验收 `food_log`。
- 手机：装上带本合同的 App。下次聊天同步时会自动领取，饮食页即可看到记录。
- 每一步都要用户单独同意。

## 需要真人的部分
- 合并由用户进行，收到 `relay:done` 前不要合并。
- 生产换包、开通、装 App，由用户另行同意。

## 审核记录

### 第 1 轮（10-25）：Codex 完成，Claude 审核并小修
- Codex 提交 `aeec5cc`，只改了允许的路径。
- Core：
  - `claimFoodPhoneCredential` 在单事务里检查领域登记、hooks 版本、schema，以及 principal 的状态和配置。任何一项不符就报 `food_not_provisioned`，不轮换。
  - 路由先 `requireDevice`，只接受安卓手机；请求体严格为 `{}`，上限 1024 字节。共用的 `json()` 自带 `no-store`。
- App：
  - 凭据存在安全存储里，响应要严格校验，包括节点号必须一致。
  - 在 `_performSync` 前 attach，失败时吞掉异常。认证失败后每个进程只重领一次。断开设备时会清除凭据并 detach。
- 云端复跑：专项 Node 测试 56 项，48 过、0 败、8 跳。`tools/i_core/*.test.mjs` 共 438 项，11 败，都是基线已有的 PowerShell/SMTP 用例，没有新增失败。这个环境没有 Flutter，Flutter 部分以 CI 为准。
- Claude 小修一处：之前如果在首次聊天同步之前打开饮食页，页面只会显示“尚未连接林埃核心”。现在打开页面时会尝试连接一次（每次打开最多一次，避免和状态变化互相触发）。
