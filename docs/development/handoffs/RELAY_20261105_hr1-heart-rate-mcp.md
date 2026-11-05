<!-- relay:contract v1 -->
# HR1 合同：臂带实时心率进 i MCP

## 目标
现在只有手机 App 里的林埃能读心率，而且只能读一个瞬时值（`LiveHeartRateSnapshot`）。走 i MCP 的前端都读不到，包括 Claude、ChatGPT、Antigravity 和 Sesame Charlie 的通话。本合同要做到：戴着臂带时，手机把心率实时推到家里电脑；MCP 新增一个按需调用的 `heart_rate` 工具，能查“现在多少、最近怎么变”，也能查“某段时间的每分钟曲线”。

典型场景有两个：一是聊天或通话时前端每轮调一次，接住心跳的变化（包括亲密互动）；二是之后 HR2 做异常主动发问。HR2 不在本合同。

## 架构
```
HR31 →BLE→ BleHeartRateService（手机前台服务，Kotlin）
          └─ HeartRateUploader：每 5 秒批量 POST
               → https://<电脑 tailnet 名>:8447/v1/heart-rate/samples   （tailscale serve）
               → 127.0.0.1:47866  i MCP 进程内的心率监听（只认 Tailscale-User-Login）
                    ├─ 内存：最近 15 分钟逐秒样本
                    └─ <stateDir>/heart_rate/minutes-YYYY-MM-DD.jsonl  每分钟汇总，保留 14 天
MCP 工具 heart_rate ← 读上面两处
```
- **零操作鉴权**：沿用 V1a.1 的做法。监听只绑 `127.0.0.1`，由 `tailscale serve --https=8447` 转发。请求要带 `Tailscale-User-Login`，并且这个登录名在 `heart_rate.json` 的 `tailscale_logins` 名单里，才收。手机不用填 token。
- **地址自动推出**：App 取已配置的 Core 同步地址（`https://<设备>.ts.net`），换成 8447 端口。设置页可以手动覆盖，留空就自动推。
- **开关**：MCP 状态目录里有 `heart_rate.json`（`{"format":"heart-rate-v1","tailscale_logins":[...]}`，由部署脚本写入）才启用监听和工具；没有这个文件时，生产行为和现在完全一致。

## 数据与工具
**上传**（手机 → 电脑）
- `POST /v1/heart-rate/samples`，请求体为 `{"format":"hr-samples-v1","device":"<名称>","samples":[{"t":<毫秒>,"bpm":<int>}...],"status":"live|stale|reconnecting|..."}`，单次最多 300 条、16 KB。
- 服务端会丢掉 `bpm` 不在 30–220 之间的样本，也会丢掉时间超前 1 分钟以上或早于 24 小时的样本；重复时间戳只保留第一条。返回 `{"accepted":n}`。
- 手机端的队列最多攒 10 分钟。断网时先丢最旧的；恢复后按时间顺序补传。失败退避从 5 秒到 60 秒。不上传 RR、设备地址或 userKey。

**MCP 工具 `heart_rate`**（scope `i.read`，只读）
| mode | 返回 |
|---|---|
| `now`（默认） | `latest`（bpm、时间、距今秒数、`live` 判定：≤15 秒为实时）；最近 1/5/15 分钟的中位、最小、最大值；最近 5 分钟每 30 秒一个点的走势；当天同时段的参考水平（过去 7 天同一小时的中位数，没有就为 null） |
| `range` | `start`、`end`（ISO 时间，跨度不超过 12 小时，默认最近 60 分钟），返回每分钟的中位、最小、最大值和样本数 |
| `night` | `night=YYYY-MM-DD`，返回 18:00 到次日 12:00 的每 5 分钟汇总、最低的 30 分钟均值，以及覆盖时长 |

工具说明写明三点：
- 只给读数和走势，不做诊断，也不凭心率断言情绪或睡眠。
- 数据是“距今 N 秒”的值；`live=false` 时如实说臂带没在线。
- 需要实时跟随时可以每轮调用一次 `now`。

**开放范围**：claude、chatgpt_web、antigravity、sesame 全开；gemini_web 不开（之前实测工具调用不生效）。

## 完成标准
**MCP（tools/i_remote_mcp/）**
- [ ] 新文件 `heart_rate.mjs`：只依赖 `node:` 内置模块，好让 legacy 候选原样内嵌。内容包括配置加载、监听（鉴权、限长、校验）、内存环形缓冲、分钟汇总写盘（分钟结束后追加写入，进程退出时补写当前分钟）、14 天清理、工具定义与执行。
- [ ] 主线 `server.mjs` 和 `domain_tools.mjs` 接入工具和监听；`chatgpt_candidate.mjs` 在 STUDY 之后加 `HEART_RATE_PATCHES`（覆盖 mainline 和 legacy），正反向补丁字节一致，并改钉候选 server 的哈希。
- [ ] 测试：没有 `heart_rate.json` 时，工具和监听都不出现；没有或伪造 Tailscale 头一律 401；登录名不在名单里返回 403；超长、非法 JSON、越界 bpm、时间异常都按规则处理；三种 mode 都要验证（包括跨午夜和空数据）；分钟文件不跟随符号链接，只在 `heart_rate/` 目录内读写；gemini 调用返回 -32602。
- [ ] `node --test tools/i_remote_mcp/` 全部通过，CI 绿。

**App（Kotlin + Dart）**
- [ ] 新文件 `android/.../ble/BleHeartRateUploader.kt`：纯逻辑的部分（队列、批次、退避、丢弃规则）可以在 JVM 单测里跑；HTTP 用 `HttpURLConnection` 放在后台线程，不碰 Store 的 writer。`BleHeartRateService` 每收到一个样本就交给它，服务停止时停止上传。
- [ ] 上传地址和开关存在原生 SharedPreferences 里，由 Dart 经现有 MethodChannel 新方法 `configureUpload({url?, enabled})` 设置；App 启动时以及 Core 地址变化时同步一次。
- [ ] 心率设备设置页新增一个“同步到电脑”区块：开关（默认开）、推出的地址（可覆盖）、最近一次成功上传的时间、最近一次错误的代码。
- [ ] 测试：`BleHeartRateUploaderTest.kt`；gateway 和设置页只追加用例。现有断言不改。

**部署（脚本轮，tools/relay_scripts/heart_rate/）**
- [ ] 第 1 轮（只读）：读 tailscale serve 状态、当前登录名、现役任务、MCP 状态目录，确认 47866 和 8447 都没被占用。输出只给“是否满足”，不打印登录名、域名和路径。
- [ ] 第 2 轮（写入，需用户 👍，会停服约 1 分钟）：按 ST1 的流程生成 MCP 候选，写入 `heart_rate.json`（登录名取本机 tailscale 当前用户），给 `heart_rate/` 目录设受保护的 ACL，执行 `tailscale serve --bg --https=8447 http://127.0.0.1:47866`，最后切换任务。
- [ ] 第 3 轮：复用 build-install-v3b 装 App（需插手机并点 👍）。
- [ ] 验收：戴上臂带，在 Claude 里问“我现在心率多少”，能拿到 `live=true` 的读数；一小时后用 `range` 能看到每分钟的曲线。

## 允许修改的路径
- `tools/i_remote_mcp/`
- `android/app/src/main/kotlin/com/memexlab/memex/ble/BleHeartRateUploader.kt`、`BleHeartRateUploadSettings.kt`（新建）、`BleHeartRateService.kt`（只加样本转交和启停）、`channels/BleHeartRateChannelHandler.kt`（只加 `configureUpload`、`getUploadStatus`）
- `android/app/src/test/kotlin/com/memexlab/memex/ble/BleHeartRateUploaderTest.kt`（新建）
- `lib/data/services/ble_heart_rate_gateway.dart`、`lib/ui/settings/widgets/heart_rate_device_settings_page.dart`、`lib/data/services/heart_rate_upload_sync.dart`（新建），以及 `lib/main.dart` 中启动时同步地址的一行
- `test/data/services/ble_heart_rate_gateway_test.dart`、`test/ui/settings/widgets/heart_rate_device_settings_page_test.dart`（只追加用例；共享的假 gateway 需要补两个新接口方法）
- `tools/relay_scripts/heart_rate/`、本合同、`DEVLOG.md`

## 不做 / 边界
- 不改 Core，不新建 Core 领域；心率不进 i_core 或 Memory V3。
- 不改采集、重连、watchdog 和 JSONL 格式；手机本地的保留期仍是 14 天。
- 不判睡，不来电，不主动发消息（主动发问是 HR2）。
- 心率端口不接公网隧道（Cloudflare），只走 tailnet。
- 仓库公开：不写本机路径、tailnet 域名、登录名、token；测试数据全部是合成的。

## 验证命令
- `node --test tools/i_remote_mcp/`
- `cd android && ./gradlew :app:testHereIAmV3DebugUnitTest --tests "com.memexlab.memex.ble.*"`（云端没有 Android SDK，以本机脚本轮的结果为准）
- `flutter analyze` 与 `flutter test`（只跑上面两个测试文件，以 CI 为准）

## 需要真人的部分
- 合并 PR；部署第 2 轮和装 App 的第 3 轮各点一次 👍；戴上臂带在前端试问一次。

## 实现说明（Claude，2026-11-05）
- **MCP**：新文件 `heart_rate.mjs` 只依赖 `node:fs`、`node:path`、`node:http`。主线在 `domain_tools.mjs` 里加了 `createHeartRateDomainTools`，把输入错误转成结构化错误；`createApp` 把 `heartRate`（store 和 config）返回给 `main()`，由 `main()` 起 127.0.0.1 监听。
- **legacy 候选**：`HEART_RATE_PATCHES` 排在 STUDY 之后。和 ST1 不同，补丁不再把源码写成字面量，而是构建时从同一 checkout 读取 `heart_rate.mjs` 原样内嵌；`heart_rate.test.mjs` 会逐字节核对，构建器也断言源码里没有 `String.replace` 会解释的 `$` 序列。补丁还改了这些地方：RPC 包装同样接管 `heart_rate` 的输入错误；`serve` 启动前校验 `heart_rate.json`；`heart_rate_` 开头的错误码原样打到 stderr；sesame 的工具列表改成可追加的数组。候选 server 哈希为 `77a8dd30…`，其余文件不变。
- **存储**：样本时间必须严格递增，重复的计为 duplicates。分钟结束 15 秒后（或下一分钟的样本到达时）把这一分钟追加写入当天的文件；进程退出时补写当前分钟。重启后同一分钟可能被写两次，读取时保留样本数多的那一行。读写都不跟随符号链接；数据目录必须是状态目录下真实的 `heart_rate/`。
- **App**：`BleHeartRateUploader.kt` 是纯 JVM 代码。400 和 413 的批次直接丢弃，不会无限重试；网络错误、401、403 和其他错误则保留队列并退避。同步关闭或没有可用地址时清空队列，不会攒数据留到之后再发。同步设置存在 `ble_heart_rate_upload` SharedPreferences 里，只有地址和上传结果，没有凭据。
- **验证**：云端 `node --test tools/i_remote_mcp/*.test.mjs` 233/233；在独立 Kotlin JVM 工程里跑 `BleHeartRateUploaderTest` 8/8，Android 整体编译要以本机脚本轮为准；`flutter analyze` 改动文件无问题，`flutter test` 涉及 BleHeartRateGateway 的测试 28/28。
- **部署脚本**：`tools/relay_scripts/heart_rate/hr1.mjs` 用 `--mode inspect` 做只读检查（`hr1-inspect.ps1`，脚本轮 read），用 `--mode deploy` 上线（`hr1-deploy.ps1`，脚本轮 write）。切换沿用 ST1 第 5 轮成功的做法：遇到 Core 崩溃恢复标记时等待，不当成失败；新任务起不来就停掉它、重启旧任务。维护工具直接复用 ST1 的 `tools-4603fb79` 副本，因为此后 tools/i_core 没有改动。新任务名为 `HereIAm-iCoreSchema6-hr1-heart-20261105`。上线完成后开 `tailscale serve --https=8447`，再经 tailnet 请求一次 `/v1/heart-rate/health`，用本机自己的 Tailscale 登录验证鉴权。
- **装 App**：复用 `tools/relay_scripts/app/build-install-v3b.ps1`。
- **合并时机**：本 PR 用未合并的分支直接部署。脚本轮 1–3 都跑完、验收通过之前不要合并。

