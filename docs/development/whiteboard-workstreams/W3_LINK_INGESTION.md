# W3 / F3 — 普通链接抓取与统一入库

## F3 产品闭环交接（2026-08-19，当前）

**状态**：完成，待集成

**分支/基线**：`codex/whiteboard-f3-link-product`，`v3-lab @ 87897543`，已确认包含 `18981287`

**schema**：60，未新增表、未修改生成代码

### 当前闭环

`/import` 已形成“输入 URL → 安全抓取 → 零持久化 `IngestionResult` 预览 → 用户确认 → `commitResult` → `UnifiedCardRepository.commitIngestion` → Card/Source/版本链立即可查”的产品流程。预览展示 canonical URL、provider、站点/作者、标题、描述、正文摘录、正文能力、图片数量和 OG/正文主图候选 URL。

- 默认不传 `createCard` 时不写 Source、SourceVersion、Card 或对象文件。
- 用户确认提交的是已经展示的同一结果；请求计数测试确认不会二次抓取。
- 同 canonical URL + 同 hash 显示“已在卡片库”，不重复提交。
- 同 canonical URL + 新 hash 显示“确认内容更新”；确认后只新增 SourceVersion、更新同一 Card。
- 临时 SQLite 关闭并从同一路径重开后，Card、Source 和完整版本链仍可恢复。
- 旧 `IngestionStore` 只用于 F0 遗留迁移，不再是产品真相。

### 四态与安全边界

成功、失败、需要授权、不支持四态均有明确页面。安全请求继续强制：http/https；字面量与 DNS SSRF 阻断；连接 pin 到同一次校验得到的 IP；无 pin fail-closed；HTTPS 保留 SNI/证书校验；重定向逐跳重查/重 pin且最多 5 跳；connect 10 秒、receive 15 秒；原始响应默认上限 2 MiB；仅 HTML/XHTML/XML MIME；瞬态失败最多重试一次，SSRF、DNS、401/403、MIME、超限和重定向策略错误不重试。

普通网页为正式范围。小红书普通笔记只沿匿名公开 HTML 路径尝试，401/403 或页面门控时如实失败/请求授权；不携带 cookie、不回退登录 WebView、不调用私有接口、不下载视频、不去水印。bilibili/YouTube 视频明确交给 W4。抓取不写 BoardItem 或 User-truth。

页面不使用 `Image.network` 直接加载不可信主图 URL，以免绕过 DNS pin 与字节上限；当前展示主图候选信息。真实二进制缩略图属于后续非阻塞增强，必须复用安全请求边界。

### 验证结果

固定 fixture 与构造响应覆盖 canonical/OG/正文/图片、重定向、重复导入、内容变化、401/403、错误 MIME、超限、解析失败、DNS pin/rebinding、零写入、确认不二抓、临时 SQLite 重启和 `/import` 四态/更新确认。

- ingestion + `UnifiedCardRepository` + UI：**101/101**；
- 定向 `flutter analyze`：零问题；
- `git diff --check`：通过；
- 合规真实网络：`https://example.com/` 真实 DNS pin + TLS、显式入库、幂等重导、SQLite 重启恢复通过；离线时 smoke 自跳过，不影响核心测试。

### 未完事项与契约请求

- 未做 JS 渲染、登录态抓取、网页快照/Anchor、视频 provider、安全二进制缩略图缓存。
- 小红书尚无稳定公开 fixture 可升级为正式支持，不能把反爬失败伪装成授权能力。
- **共享契约请求：无。** `IngestionResult`、Source/Card 身份、版本语义和 schema 均未变。后续若需要真实远程缩略图，建议另立可复用安全资产预览接口。
- 本分支不 push、不合并；集成目标仍为 `v3-lab`。

---

## 历史 W3 第一轮交接（2026-08-16，已由 F3/F0 语义取代）

**状态**：第一轮闭环 + 安全返修 + **Task E 安全收口与真实 UI 入口**已完成（2026-08-16）
**权威范围**：URL 规范化、provider 识别、安全请求、元数据 / 正文能力、来源版本、去重、失败与重试
**当前目标**：普通公开网页链接从输入到可恢复 Card 的真实闭环
**拥有路径**：
- `lib/data/whiteboard/ingestion/` — canonicalizer / safe http / html parser / ingestor / store / service
- `lib/ui/whiteboard/link_import_screen.dart` — 真实导入 UI（`/import` 路由占位填充，router.dart 未动）
- `test/data/whiteboard/ingestion/` — 单元 + 集成 + fixture + smoke + DNS pin 测试
- `test/ui/whiteboard/link_import_screen_test.dart` — UI 四态 / 显式建卡 / 重启恢复
- `docs/development/whiteboard-workstreams/W3_LINK_INGESTION.md` — 本 handoff
**共享契约**：只读 `IngestionResult` / `SourceContent` / `SourceVersion` / `CardContract`（均来自 W0，未修改任何共享类型；四态 `IngestionStatus` 枚举本就包含 needsAuth / unsupported，本轮只是让管线诚实产出这两种状态）
**明确不做**：视频下载 / 去水印、画布交互、富文本编辑器内部状态、自动写入 User-truth、数据库迁移 / 路由表 / pubspec

## 本轮实现

### ① DNS rebinding 完整防御：连接 pin 到已验证 IP（Task E）

旧实现只做"检查时点"验证：DNS 检查与实际 TCP/TLS 连接之间存在 TOCTOU 窗口——恶意 DNS 可在检查后对同一 host 返回不同结果。本轮把窗口彻底关闭：

- **pin 簿记**：`SafeHttpClient._validateHost` 每跳（初始 URL + 每个重定向目标）解析并逐地址校验后，把**同一份解析结果**里的首选地址（IPv4 优先）写入 `_pins[host]`——校验与 pin 来自同一次 lookup，检查后不再发生第二次解析。
- **PinnedHttpAdapter（自定义 dio adapter）**：生产客户端（`enforceDnsCheck=true`）不再用 dio 默认 IO adapter，而是直连 pin 的 `InternetAddress`：
  - 无 pin 即**fail-closed**（抛出 `SSRF guard: no validated IP pin`），绝不回退到未校验的解析连接；
  - **HTTPS 保留 SNI + Host + 证书校验**：TCP 直连 pin 后在同一 socket 上 `SecureSocket.secure(socket, host: 原主机名, onBadCertificate: 拒绝)`——只 pin TCP 端点，TLS 身份验证语义与默认 HttpClient 一致；
  - `Connection: close` 单请求语义：每一跳都是新建连接，用的必然是**该跳验证过的 pin**（重定向目标逐跳重新解析 + 校验 + 换 pin）；
  - 直连、不经过代理（代理隧道会把端点决策移出 pin 层）；
  - 逐读 receive timeout + connect timeout；流式 body（Content-Length / chunked / EOF 三种模式），字节上限逻辑沿用（在 `SafeHttpClient` 层）。
- **rebinding 攻击面**：连接目标 = 检查时验证过的地址；重定向后的第二次 lookup 即使返回内网地址也永远不会成为连接目标。

**测试**（`test/data/whiteboard/ingestion/dns_pin_test.dart`，4 项）：
- 连接使用精确验证地址，且每 host 只解析一次（无连接时二次解析）；
- rebinding 攻击阻断：post-validation 答案变化（公网 → 127.0.0.1 → 169.254.169.254）不影响连接目标；
- 无 pin 时 transport fail-closed（连接层零调用）；
- 重定向逐跳 pin（真实 socket 端到端：本地测试服务器 + 302 → 第二跳，断言两跳各连各自的验证地址、各解析一次）。

### ② 四态诚实产出（Task E）

管线现在能诚实产出全部四种 `IngestionStatus`：

| 状态 | 触发 | 说明 |
|---|---|---|
| `ok` | 正常抓取解析 | 原逻辑 |
| `failed` | 网络 / MIME / 超限 / 解析失败等 | 原逻辑（错误信息原样透出） |
| `needsAuth` | HTTP 401 / 403 | `SafeHttpResult.authFailure`（`authRequired=true`）→ `LinkIngestor` 映射为 `needsAuth`，消息说明"站点要求登录或拒绝了抓取（可能被反爬拦截）"；作为策略错误不重试 |
| `unsupported` | bilibili / youtube 视频平台 URL | 抓取前直接判定（W4 研读模块范围），消息注明归属，不做无谓抓取 |

### ③ 真实 UI 入口（Task E）：`/import` → `LinkImportScreen`

W6 冻结路由 `/import` 的占位体替换为真实闭环（`router.dart` / `routes.dart` 未动）：

- **粘贴 URL → 抓取**：`LinkIngestionService.ingestUrl(createCard: false)`——抓取本身只产出 `IngestionResult` 并持久化 Source/Version，**绝不自动建 Card**；
- **四态诚实呈现**：ok（标题 / provider / canonical URL / 摘要 / 图片数 / MIME）+ 存入卡片库按钮；failed（错误图标 + 原样错误信息）；needsAuth（锁图标 + 解释）；unsupported（警示 + 归属说明）。失败态一律不出现"存入卡片库"；
- **显式建 Card**：用户点「存入卡片库」→ `ingestUrl(createCard: true)` → 展示「已在卡片库 / 卡片已更新（内容有新版本）」+ cardId + 「打开卡片库」跳 `/cards`；
- **去重不静默复制**：已存在的链接再抓取 → 显示「已在卡片库」（经 `getSource().card` 检测），不再出现建卡按钮；内容变更 → 新版本 + 卡片更新提示；
- **重启恢复**：打开页面即从文件 store 读取「最近导入」列表（标题 / canonical URL / 日期 / 版本数）；store 目录 = `getApplicationSupportDirectory()/whiteboard/ingestion`（测试可注入 service / storeDirResolver，构造函数保持 `const LinkImportScreen()` 兼容路由）。
- 空输入内联校验；存储不可用时有明确错误态。

### 管线组件（沿用，未变）

| 组件 | 文件 | 职责 |
|---|---|---|
| `UrlCanonicalizer` | `url_canonicalizer.dart` | URL 规范化（host/scheme 小写、默认端口剥离、tracking 参数删除、query 排序、fragment 丢弃）、provider 识别（bilibili / xiaohongshu / youtube / wechat_mp / web）、canonical_id 抽取 |
| `SafeHttpClient` | `safe_http_client.dart` | 安全 HTTP：仅 http/https；字面量私网 / 元数据 / `.local` / `.internal` 阻断（SSRF）；DNS 级 SSRF 防护（生产默认启用，每跳解析并逐地址检查 IPv4/IPv6）；**DNS rebinding：连接 pin 到已验证 IP（PinnedHttpAdapter，fail-closed，HTTPS 保留 SNI/证书校验）**；重定向逐跳复查 + 逐跳重新 pin；超时；真实流式字节上限（Content-Length 预检 + 流式计数中断，默认 2MB 原始字节）；MIME 类型校验；重试上限 + 退避；401/403 → `authFailure` |
| `parseHtmlPage` | `html_page_parser.dart` | OG / twitter title、description、og:image、site_name、author、正文容器选择、正文提取（nav/script/style 剥离、pre→fenced code）、图片列表（20 上限、avatar/icon 过滤） |
| `LinkIngestor` | `link_ingestor.dart` | 编排：canonicalize → 视频 provider 提前判定 unsupported → safe fetch → parse → 产出 `IngestionResult`（含 `SourceContent` + `SourceVersion`）；sourceId 派生（provider 用 canonical_id，web 用 URL hash）；content hash（sha256）；不写 Card |
| `IngestionStore` | `ingestion_store.dart` | JSON 文件持久化 Source + 版本列表 + Card 索引；去重（同 canonical URL → 同 sourceId）；版本化（hash 变化 → 新 SourceVersion，幂等重导不产生新版本）；Card 显式创建 / 更新 |
| `LinkIngestionService` | `link_ingestion_service.dart` | 应用层：运行 ingestor → 持久化 Source → 明确决定创建 / 更新 Card（`createCard=false` 可仅抓取不建卡） |

### 去重与版本化语义

- 同一 canonical URL → 同一 sourceId → 复用 Source。
- 内容 hash 未变 → 幂等重导，无新版本、无新 Card（`versionIsNew=false`）。
- 内容 hash 变化 → 新 `SourceVersion`，Source 的 `currentVersionId` 更新，Card 复用（更新标题 / 缩略图），绝不静默复制 Card。
- 保留 original URL（`metadata.original_url`）、抓取时间（`resolvedAt` / `createdAt`）、解析器版本（`SourceVersion.parserVersion` = `w3-html-parser-v1`）、失败原因（`IngestionResult.errorMessage`）。

### 安全边界（已测试）

- scheme 白名单：http / https only。
- **字面量 SSRF 阻断**：localhost、0.0.0.0、`[::1]`、IPv4 私网 / loopback / link-local / CGNAT / TEST-NET / multicast / 保留段、IPv6 loopback / ULA / link-local / multicast / unspecified 字面量、169.254.169.254 元数据、`metadata.*`、`.local` / `.internal` 全部阻断。
- **DNS SSRF 防护（真实启用）**：`SafeHttpConfig.enforceDnsCheck` 生产默认 `true`。每次初始请求和**每一跳重定向前**都经可注入 `DnsResolver` 解析 host（生产用 `SystemDnsResolver` = `InternetAddress.lookup`），并逐地址检查：任何地址落在 loopback / private / link-local / unspecified / multicast / reserved / 云 metadata 范围即整请求失败（混合公网 + 私网也失败）。IPv6 的 `::ffff:0:0/96` IPv4-mapped 地址会解出内嵌 IPv4 再检查。
- **DNS rebinding（完整防御，Task E 落地）**：见上「①」。连接 pin 到检查时验证过的同一份解析结果；传输层不再发生任何 DNS 解析；无 pin 时 fail-closed。仅当"解析服务本身在单次 lookup 内返回混合或恶意结果"时才会被拦截失败——这已不是可利用的 TOCTOU。
- 重定向：逐跳重新校验目标 URL（字面量 + DNS + 重新 pin），上限 5 跳；重定向到 localhost / 私网 / 危险域名被阻断。
- 超时：connect 10s / receive 15s（含头部等待与逐读）。
- **流式响应上限（真实生效）**：`maxBodyBytes` 默认 2MB **原始字节**。`Content-Length` 已超限时在读取前直接拒绝；未带或虚假 Content-Length 时，响应流按原始字节累计，一旦超过上限立即取消（`CancelToken` + 中断流订阅），超限内容不会完整进入内存；确认未超限后才 `utf8.decode` 正文。
- MIME：仅 text/html / application/xhtml+xml / application/xml。
- 重试：瞬态错误最多 1 次重试 + 线性退避；策略错误（SSRF 字面量 / DNS 失败 / 401 / 403 / MIME / 超限 / 超限重定向）不重试。

## 测试

### fixture（`test/data/whiteboard/ingestion/fixtures/`）

| fixture | 覆盖 |
|---|---|
| `open_graph.html` | OG 元数据、正文、多图、pre→fenced code、nav/footer/script 剥离 |
| `plain_body.html` | 无 OG、title + meta description 兜底 |
| `no_title.html` | 无 title / og:title / h1，仅正文 |
| `redirect_target.html` | 重定向后的最终页面 |
| `duplicate_import.html` | 重复导入幂等 |
| `updated_content.html` | 内容变更 → 新版本 |

超大体 / 错误 MIME / 解析失败由测试内构造（不落 fixture 文件）。

### 测试套件（Task E 后共 87 项 + W0 契约）

- `url_canonicalizer_test.dart` — 规范化、tracking 删除、端口、scheme 拒绝、provider / id 识别。
- `safe_http_client_test.dart` — 字面量 SSRF；DNS SSRF；**401/403 → `authRequired`（策略错误不重试，其他 HTTP 错误仍为 generic failure）**；流式字节上限；重试语义；`enforceDnsCheck` 默认 true。
- `dns_pin_test.dart`（Task E 新增 4 项）— pin 到精确验证地址且单次解析；**rebinding 攻击被阻断**（post-validation 答案变化不影响连接目标）；无 pin fail-closed；**重定向逐跳重新 pin**（真实 socket 端到端）。
- `html_page_parser_test.dart` — OG / body / no-title / code 保留 / 空与垃圾 HTML。
- `link_ingestion_service_test.dart` — 端到端成功、失败、重复导入去重、内容变更版本化、重定向 canonical 更新、重启恢复、`createCard=false`、错误 MIME / 解析失败、Card 契约完整性、**四态（视频 → unsupported、403 / 401 → needsAuth）**。
- `smoke_real_url_test.dart` — 真实 `https://example.com/` smoke test（**真实网络 + 真实 pin 传输 + 幂等重导 + 重启恢复**），网络不可达时自动跳过。
- `link_import_screen_test.dart`（Task E 新增 7 项 widget 测试）— 初始态 / 空输入校验 / **ok 流（抓取 → 预览 → 显式建卡 → 无重复按钮）** / failed / needsAuth / unsupported 四态诚实呈现 / **重启恢复（同目录新 service 读出最近导入；重导幂等显示"已在卡片库"）**。
- `whiteboard_routes_test.dart` — `/import` 路由解析（占位替换后无回归）。

**结果**：ingestion 80 项 + UI 7 项 + 路由/白板 UI 35 项全通过（原 W3 68 项零回归）；`flutter analyze lib/data/whiteboard/` 零问题；`git diff --check` 干净；真实 example.com smoke 通过（本机网络可用时）。

## 真实输入与恢复验收

- 真实 URL smoke test（`example.com`，走 PinnedHttpAdapter + 真实 TLS）：成功解析、建 Card、幂等重导、重启恢复均通过（本机网络可用时）。
- UI 四态：widget 测试全量渲染真实 screen（`MaterialApp.router` 真实路由 / `LinkImportScreen` + 真实 `IngestionStore`）；`/import` 路由在真实 GoRouter 中解析。
- 重启恢复：`IngestionStore` 用同一目录重建实例后，Source / 版本 / Card 全部可读；重新导入同一 URL 不再产生新 Card / 版本；UI 层面「最近导入」列表从磁盘恢复。

## 契约提案（W0 集成工作流审阅）

1. **持久化迁移（仍建议）**：本轮 `IngestionStore` 用 JSON 文件实现闭环。建议 W0 迁移为 Drift 表：`whiteboard_sources` / `whiteboard_source_versions` / `whiteboard_cards`。JSON 文件与 Drift 应可共存（当前数据可导出导入），不破坏现有契约。
2. **DNS rebinding 完整防护（✅ 已落地，Task E）**：自定义 transport 已实现——DNS 检查通过后直接连接已验证的 `InternetAddress`，HTTPS 保留 SNI + Host + 证书校验，rebinding 攻击测试被阻断。该改动只影响 `lib/data/whiteboard/ingestion/` 传输层，共享契约类型无变化。
3. **四态状态产出（新增说明）**：管线现在会产出 `needsAuth`（401/403）与 `unsupported`（bilibili/youtube 视频平台 URL，W4 范围）。`IngestionStatus` 枚举为 W0 共享类型且本就包含这两种状态，本轮未改任何类型，仅补齐了诚实产出路径。UI 按状态呈现并决定是否给出「存入卡片库」。
4. **小红书记录**：小红书普通笔记仍走正常抓取（canonical_id 已支持 note/explore 24-hex id）；视频类链接因 W3 不做视频解析，如实失败或部分内容，不伪造支持。

## 待集成 commit

- 本 worktree 分支 `codex/whiteboard-w3-security-ui`（基于含 Task 0 / W6 基座的 `v3-lab`），包含：
  - 首轮 W3（`fe11c0fc` + 安全返修，已合入 v3-lab 的历史提交）
  - Task E：DNS pin（`safe_http_client.dart` / `dns_pin_test.dart`）、四态产出（`link_ingestor.dart`）、真实 UI（`link_import_screen.dart` / `link_import_screen_test.dart`）、测试增补、本文档。
- 未 push、未 merge，交集成确认后合入 `v3-lab`。

## 未实现范围 / 风险 / 下一接入点

- **未实现**：视频 provider 解析（bilibili / youtube / xiaohongshu 视频为 W4 范围，本管线诚实标记 unsupported）、WebView / JS 渲染页面、正文全文存储（本轮只存 excerpt 到 Card body，全文 object 存储待 W0 迁移）、Drift 持久化、卡片库真实列表（`/cards` 占位归 W2 / Task S）。
- **风险**：大量站点使用 JS 渲染，`parseHtmlPage` 只能拿到 SSR 内容；失败时 `IngestionStatus.failed` 带错误原因，不假装成功。反爬 UA / cookie 站点可能 403（`needsAuth` 状态，不越权）。**DNS rebinding 已 pin 关闭**；剩余攻击面收敛为"单次 lookup 返回混合/恶意地址"（会被校验直接拒绝）。
- **下一接入点**：`LinkIngestionService` 是 UI 可直接调用的入口（已由 `/import` 使用）；W2 卡片库 / W0 白板可将 `CardContract` 纳入卡片库筛选与白板摆放；真实桌面窗口的 `/import` 端到端验收（App 启动 → 粘贴 URL → 建卡 → 重启）可在 Task S 外壳就绪后补一条 integration_test（本轮以 widget 四态 + 路由解析 + 真实网络 smoke 覆盖同一代码路径）。

## 待填写（W0 集成后）

- 结果 / 验证：已填（见上）。
- 待集成提交 / 未完事项：见上。
