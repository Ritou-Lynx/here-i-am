# P5 手机只读接入整合记录

2026-09-05；属于 `GOAL-20260824-ai-workbench-wave1`，用户已确认新增手机接口、新 APK 与桌面读取。persona 基线 `4ba05b1177d38c29c5eb3f207ce1fbf8bb600d7b` 冻结。

## 最新验收结论（2026-09-06）

**P5 在已确认的手机 Dreaming 只读范围内通过**；权限部分采用用户明确确认的“自动证明底层拦截 + 真人确认只读回复”组合口径。不是全项真人注入或全量跨端记忆能力通过；下列历史等待/失败记录保留为过程证据，以本节为当前结论。

| 验收项 | 证据与限定结论 |
|---|---|
| 人格 | `4ba05b11` 口吻已获用户明确认可并冻结。 |
| 历史召回 | 真实手机来源获得一例用户认为基本相符的回复，不证明全量准确或完整时效。 |
| 空结果 | 实际 `phone_v3_live/empty`、0/0/0，与未编造回复一致。 |
| 不可用 | 自然到期时实际 unavailable，回复区分来源不可用与没有记录。 |
| 权限自动证据 | 相关源码/测试与候选 6/6 文本一致；四组隔离测试通过，验证 scope、未知记忆写工具/模型自授 payload 与 HTTP 边界。 |
| 权限真人交互 | 用户在新有效连接中发出限定手机记忆的标记写入请求；回复明确只读、未保存且未执行其他操作，没有声称成功。 |

- 主窗 Computer Use 在唯一 P5 候选核对同轮输入/回复，页面授权有效，最近回执 `phone_v3_live/available`、4/6/0，`captured_at=2026-09-06T12:23:26.572842Z`。因此这次没有把网络/到期故障当作只读能力说明。
- 本轮 exe/kernel SHA-256 再核对匹配本文件候选表。Terra 独立只读复审确认按已约定口径可收口；未添加任何真人 Gate 或扩大手机来源。
- 不把模型口头回复当成真实 `unsupported_product_tool` 回执，不声称查过用户数据库证明零写入；底层拒绝取自隔离测试，真人只证明交互诚实。普通测试聊天行的持久化不等于 User-truth/Dreaming 写入。
- 手机近期聊天、结构化事实与 UserRhythm 未接入；连接失败提示的分类改进仍为非阻断后续项。P5 通过不授权扩权、同步整库、生成记忆、提交或发布。
- **下一步 P6**：沿用同一候选，先从非私人任务 enqueue/pending 验起，再验证可达生命周期与诚实重启恢复。P6 与 Goal 1 最终收口尚未通过。

## 实现与复审

- 隔离分支 `codex/whiteboard-w0-p5-phone-readonly`，从精确基线三包并行；主窗将 23 个相关路径选择性整合到 `v3-lab`，没有操作 Git 索引、提交或推送。
- 手机仅显式开启的 30 分钟内存会话，loopback `47851`；绑定当前账户/DB 与启用的 `i`，在途结果也检查撤销。固定 scope、请求/响应上限、单查询、超时、无写入端点。
- Dreaming 使用已有 FTS 与关键词 fallback，单个 SQLite 只读事务验证完整有效来源；不调用向量/生成模型，不写查询 trace，不导入桌面整库或同步 iCore。
- 桌面固定 USB endpoint、DIRECT/无 redirect、流式硬上限、整体 deadline、内存 token；断开/重连代次令旧请求失效。最终 Runtime 输入序列化再次校验 lease，覆盖模型初始化/恢复等待期间的断开与到期。
- 只替换 Dreaming 来源，persona 与近期本地聊天不变。手机失败/到期为 unavailable；仅用户主动断开才恢复原本地来源。
- 两端设置/侧栏入口已接线，连接页组件测试通过；新候选屏幕验收尚待。连接码不明文展示，回执只含固定来源/状态/计数/时间；关闭页面时异步 Command 延迟到通知栈结束后释放。
- USB 辅助仅处理指定已授权 USB 设备的 `adb forward --no-rebind`；不覆盖别的映射，不接管旧映射，不处理 token 或正文。

## 验证结果

- Flutter 专项与相邻回归 **138/138**：真实 Drift/FTS/来源闭包、真实 HTTP/认证、client/撤权/限流超时、UI/页面退出、真实数据库 → HTTP → client → assembler → productionComposition → Runtime 输入，以及白板六命令、搜索、任务队列、路由。
- 组合 fixture 证明匹配内容进入输入；删除源后为空；错误会话不读取；手机停服保持 unavailable；模型初始化等待期间断开不发送已组装正文；显式断开才恢复本地来源。
- Node USB helper **6/6**。
- 广路径 Dart analyze 首次因系统 Dart 性能缓存清理 `OS 1920` 非干净退出；主窗仅为本次分析进程改用工作树临时缓存后，退出码 `0`，无 error/warning，仅两条 `prefer_const_constructors` info。未修改系统全局设置或清理其他分析进程的缓存。
- 主目录 **23/23** P5 路径与隔离源文本一致（允许 CRLF/LF）；受保护手机/BLE **20/20** 文件 SHA-256 未变；5 个原有 staged 控制文档 blob 未变。恢复后独立复核 source manifest **32/32** SHA 匹配、两树 P5 运行源 **12/12** 文本等价。
- 构建/安装/真实手机 recall 与权限 Gate 分开记录；上述 fixture 不代表真人 P5 通过。构建完成时手机曾断开；随后用户重新连接，安装和 USB 准备的最新证据见下节。

## 候选产物与当前停止点

两次构建前均通过 critical `3/3`。这是 `4ba05b11` 加未提交 P5 源的候选，不是净 commit 产物；源指纹见 [source manifest](P5_PHONE_READONLY_SOURCE_MANIFEST.json)。Android 还保留清单中的主目录既有手机/BLE 修改。

| 产物 | SHA-256 |
|---|---|
| Windows `memex.exe` | `bd7b06fe74c589ec0f7443036e421674cbe76da0e9b18d166f124cc9b83ca3ca` |
| Windows `kernel_blob.bin` | `28ed9bca93d85afa339d86dcb3c123651ecffd802158fdbd2bb1a717978478ad` |
| Android `app-hereiamv3-debug.apk` | `3056968ea16d10245b7ad4a40b81cf7124c8a4b64b95798e235e6aa201e761d4` |
| APK 内 `kernel_blob.bin` | `fb8db3bf2d766d1330ff9c69146527d3ea167f60c1c573ec0aac93197028b86d` |
| 保留的旧 APK（回退用） | `c6698f7124bcd915a13d6171656b44ae2b005e4b7f33dd27613b1a9e8044e2be` |

- Windows：隔离目录 `build/windows/x64/runner/Debug/memex.exe`，Flutter build 退出 `0`，810.7 秒；恢复后核对该路径进程存在。用户因正在用电脑按 Escape 停止 Computer Use，未完成新入口屏幕检查；后续只做后台核对，不擅自切换窗口。
- Android：主目录 `build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`，463009345 字节；`com.memexlab.hereiam.v3`，`hereIAmV3Debug`，`1.0.30 (113)`，启动入口 `com.memexlab.memex.MainActivity`。中断后原构建终端句柄失效，未取回 Flutter 最终退出码；Gradle 20:57:35 完成记录、20:57:32 新 APK、两处 APK 哈希一致与 `apksigner verify` 退出 `0` / v2 signature 通过共同确认产物已完整生成，不重复构建冒充原终端证据。
- 旧 APK 已复制到主目录 `build/p5-phone-readonly/previous-app-hereiamv3-debug.apk`，哈希一致；未安装或回退。
- Android 仍有既有 NDK 版本差异与 KGP 未来兼容告警；本包未扩改依赖或构建配置。
- 构建结束时手机断开，安装等待用户重新连接；这是历史停止点，已由下列安装记录推进。P5/P6 Gate 仍未通过；未提交/推送/发布。

### 手机重新连接后的安装记录

- 2026-09-05 用户确认重新连接，唯一在线设备为原三星 `SM-S9110`。安装前设备仍是旧包 `c6698f71…`，本地待装包仍为上表 `3056968e…`。
- 为保持已审核候选不变，不重复构建；依照既有安装步骤向精确设备执行保留数据的 `install -r -t`，返回 `Success`。未绕过或模拟手机物理授权。
- 安装后设备 `base.apk` SHA-256：`3056968ea16d10245b7ad4a40b81cf7124c8a4b64b95798e235e6aa201e761d4`，与本地完全一致。
- V3 `MainActivity` 冷启动返回 `Status: ok`，`TotalTime: 2165ms`，进程 `19422` 存在；这是安装/启动证据，不证明 BLE 采集恢复或功能 Gate。
- USB helper 返回 `transport_ready=true`、`created_forward=true`，仅新建该设备的 `tcp:47851 → tcp:47851`。本任务拥有该映射；后续清理仅在核对同一映射仍存在后定向 remove，不移除其他映射。
- 未操作电脑窗口、未开启手机读取会话、未获取连接 token 或读取记忆正文。当前一步：用户在手机连接页开启 30 分钟只读会话；随后才进行桌面连接和真实 recall/权限验收。

## 使用与后续验收

### 2026-09-05 23:53–23:55 首次桌面连接诊断

- 用户报告已开启手机短时会话、已粘贴连接码，点击连接后显示“操作未完成”；尚无成功连接回执。
- 23:53 同一三星曾在线，transport 从此前 `2` 变为 `3`，但 `adb forward --list` 已为空。随后手机命令返回 `closed`；原 helper 定向恢复返回 `phone_memory_select_one_authorized_usb_device`，23:55 设备列表与 forward 列表均空。未新建任何映射，不宣称通道已恢复；此前任务拥有的映射已不存在。
- `Get-Process` 确认桌面仍为原隔离候选 `memex.exe`，进程 `41896`；未操作窗口。当前通道不可达足以阻断连接，但未持有连接码，不能排除它同时失效；不猜测物理掉线原因。
- 代码只读复核：client 的 transport/Dio 401 异常汇总为 `phone_unavailable`，无效/已过期码为 `invalid_connection_code`；页面 `_run()` 将所有错误合并为同一提示。登记改进项：固定、安全的错误分类与中文提示，补无连接/401/过期码及不泄露秘密的 UI 测试；本轮未实施或重建。
- 当前只等用户重新连接原手机，核对设备后重建精确 `47851` forward；再检查手机会话是否仍有效，由用户粘贴并确认连接。未取 token、未读取记忆正文；不算真实 recall 或权限 Gate 通过。

### 2026-09-06 00:09 后 USB 恢复与服务探测

- 用户重新连接原三星，在线 transport 为 `5`。此前 forward 为空；既有 helper 返回 `transport_ready=true`、`created_forward=true`，并核对为该设备的精确 `tcp:47851 → tcp:47851`。本任务重新拥有该映射，后续只在复核身份/映射后定向清理，不移除其他项。
- 无认证 `GET /v1/memory/status` 两次分别在 4 秒和 5 秒截止时超时；没有发送连接码、Authorization 或 memory query，也没有读取响应正文。forward 存在不等于 HTTP 服务或桌面会话成功。
- 有界 ADB 只读检查显示 App 进程存在、`127.0.0.1:47851` 在监听；手机 Awake，但 Here I Am 不是当前 resumed Activity。未操作 UI、唤醒/重启 App 或自动重开授权；后台状态仅为相关观察，尚非无响应根因证明。
- 独立源代码审计确认缺失 Authorization 的请求应在身份核对和记忆读取之前直接返回 401；因此本次超时不能归因为此请求等待身份/DB。主 isolate 未获调度或请求未送达仍只是待核对方向，不宣布根因或用放宽认证恢复。
- 下一步请用户将手机 App 切回「桌面记忆只读连接」页，核对当前状态和到期时间，再做服务响应核对。代码、候选与已有 Gate 结论不变，P5/P6 未通过。

### 2026-09-06 00:20 新会话响应恢复

- 用户将手机切回连接页，报告已无到期时间并手动重新开启一个 30 分钟会话；旧连接码不能作为本次连接凭据继续使用。
- 同一设备 transport `5` 在线，精确 forward 仍存在；无认证 `GET /v1/memory/status` 在 **39ms** 返回 **401**。与缺失 Authorization 的预期分支一致，仅证明服务可达和无凭证请求被拒绝；没有发送 query、获取 token 或读取正文。
- 未区分“回到前台”和“重开会话”各自对恢复的影响，故不宣称此前超时根因已确定。下一步由用户复制新连接码，在桌面重新粘贴并连接；成功授权/真实 recall/其余 P5/P6 Gate 仍待。

### 2026-09-06 新会话连接真人确认

- 用户先反馈重新粘贴仍失败，随后明确更新为“连接成功了”。以最新反馈作为当前连接步骤通过证据；历史失败保留，不据此猜测失败的确切原因，也不继续重复连接。
- 本轮未取桌面内部回执或新增网络探测；证据类型为用户亲眼确认。仅连接步骤通过，真实 Dreaming 命中、空/不可用/scope/写入拒绝与 P5/P6 整体仍待。
- 下一步由用户提供一个确认在手机端聊过、且不来自当前人格提示词的既有话题，再验证真实 recall。不得把身份/初见日期复述当作记忆命中；不把答案预先塞进测试问题。

### 2026-09-06 Computer Use 核对与电脑回复恢复

- 用户明确授权 Computer Use。初次 Node 内核异常/超时，按技能重置后恢复；实际选择唯一 P5 memex 窗口并观察，没有使用替代 Windows UI 自动化或操作 Codex 登录界面。
- 进程仍为原 P5 候选，exe `bd7b06fe…` 与 kernel `28ed9bca…` 完整 SHA-256 匹配。截图可见最近回执 `phone_v3_live / available`、Episode/Fragment/Saga `4/6/0`、采样时间 `2026-09-05T16:42:46.370695Z`。仅证明生产读取返回有限结果，不证明与用户话题相关或模型已成功回复；不保存私人话题、正文或截图文件。
- `GET /v1/health` 原 `ECONNREFUSED`，确认电脑 Bridge 无监听；根据现有脚本在隔离候选目录后台恢复，launcher PID `46448`、loopback `47831`。仅该进程环境开启 runtime 并沿用 `gpt-5.6-sol`；未停止其他进程、升级 CLI 或改全局配置。health 随后 200，含 `experimental_runtime_adapter_v1`。
- 后续 Runtime auth/capabilities 均 401 `authentication_required`；PATH 的桌面捆绑 CLI 和 Bridge 实际优先使用的 npm CLI 均报告 `Not logged in`。启动器无独立 CODEX_HOME/认证目录覆盖逻辑；只查状态和文件元数据，未打开/复制 auth 内容。不把这里的 CLI 状态等同当前 Codex 应用会话退出。
- 新截图确认手机「本次会话已过期」。下一步先由用户按官方浏览器流程完成电脑 CLI 登录，主窗核对 Runtime 认证/模型可用后，再重开手机 30 分钟会话并继续真实回复。Computer Use 不代办认证，不自动重发已失败的聊天。
- 当前后台 Bridge 保持运行供后续验收；手机转发仍按原所有权规则定向处理。连接错误分类与 Bridge 生命周期可用性为后续改进项，P5/P6 未通过。

### 2026-09-06 CLI 登录后的 App Server 复核

- 用户完成当前本地 Codex CLI 的 ChatGPT 登录，`login status` 明确返回 `Logged in using ChatGPT`；未读取或输出凭据内容。
- 当时尝试用新环境重复启动，但没有确认旧端口监听者退出，因此不能证明新 `CODEX_HOME` 或可执行文件已被实际 Bridge 使用；health 200 与 Runtime 401 仍可能来自旧进程。此前“正确配置重启后仍失败”的判断撤回。
- 沙箱里的直接 `app-server --stdio` 探测 12 秒无返回，没有完成退出码/错误流核验，不能据此判断版本不兼容。下方通过真实 Windows 用户和监听 PID 对照完成根因复核；不再要求重复登录。
- 手机端曾产生 `phone_v3_live / available / 4/6/0` 读取回执，但电脑最终回复未完成；这不算真实 recall 语义命中或 P5 Gate 通过。

### 2026-09-06 Bridge 账户隔离根因与恢复

- 精确对照同一桌面 CLI `0.153.4`：普通 Windows 用户 `login status` 返回已登录 ChatGPT / exit 0；沙箱实际身份 `CodexSandboxOffline` 返回未登录 / exit 1。未读取凭据正文、复制 token 或改全局配置。
- 真实 `47831` 监听 PID `13748`（parent `11608`，09:56 启动）属于沙箱用户，其子进程仍为 npm CLI；后续重复启动并未替换此监听者。根因是运行账户错误，不能归为用户未登录；最新 CLI 的本机帮助明确支持 `--stdio`。
- 通过获批的普通用户执行，先由既有 endpoint 正常关闭旧 App Server，再精确停止已核实的 Bridge PID。确认端口释放后，在正常用户下隐藏启动新 launcher `32836` → Bridge `30728` → 当前桌面 App Server `40564`。未停止其他服务或放宽模型会话沙箱。
- 新进程实际 owner、父子链和 executable 均复核：health 200、Runtime auth 200 / `authenticated=true` / `chatgpt`、capabilities 200；保留产品候选模型 `gpt-5.6-sol`，未改 App 模型或全局配置。
- 11:42 的临时只读模型会话仅发送固定非私人标记，约 6.9 秒完整返回 `P5_RUNTIME_OK`，`turn/completed`、零 tool_call、零 error；随后只关闭该临时会话。证明恢复了 Bridge → App Server → 模型 → 流式完成链路，不代表手机真实 recall 或 P5/P6 真人通过。
- 自动相邻回归：App Server client / adapter / experimental API `25/25`。本轮不构建或安装 App，原 exe/kernel/APK 指纹和历史真人结果不变。
- 防复发修复已在主目录和隔离候选同步：`start_bridge.ps1` 拒绝沙箱身份启动 Runtime；必须成功枚举 TCP listener，冲突即拒绝且不替换；PID 诊断失败不再当空闲；透传 Node 退出码。可选 `-EnableExperimentalRuntime` / `-CodexExecutable` 仅配置本次进程，默认仍关闭 Runtime，不改默认解析器/模型或认证目录。
- 新启动器测试共 5 项：普通用户和沙箱各 `4 pass / 1 身份专属 skip`，跨环境覆盖所有用例。使用假 Node/假 exe，不起第二个真实 Bridge；检测超时直接失败，临时测试目录定向清理。主 Agent 复核并修正测试错误检查后重跑两环境通过。
- 下一步：由用户重新开启已到期的手机短时会话，再验证既有话题真实回复与空/失败/scope/写入拒绝 Gate；不自动重新提交失败的私人查询。

### 2026-09-06 首个真实召回样例与来源边界

- 用户通过专用 P5 入口完成手机连接，提供桌面实际答复并反馈历史内容“应该是事实”。记录为一次初步认可的真实召回观察；没有取得新的逐字段 provenance 回执，不声称其余全部记忆准确或 P5 整体通过。
- 答复对缺少可靠精确值保留不确定性，但这不是 empty fixture 的证明，也不证明手机里没有结构化记录。私人问句、答复、生活日期和症状均不进入项目工件。
- 当前 `PhoneDreamingReadService` 仅查询/返回 Episode、Fragment、Saga；`WorkbenchRelationshipContext` 仅替换 Dreaming 来源，近期消息继续取桌面本地。两文件与实际隔离候选文本一致；没有手机近期聊天/结构化记录/UserRhythm 路径，不能把手机刚说过等同桌面已能读取。
- 结构化记录是事实源、UserRhythm 是派生状态；本轮只读代码，未查询真实手机记录，所以不能判断近期信息是否形成记录或被遗漏。
- 继续现有 empty/unavailable/scope/写入及 payload 扩权拒绝 Gate。更完整跨端上下文作为明确范围缺口待决，不自动修改 wire、权限、人格或开新 Goal。

### 2026-09-06 空结果尝试实际命中授权到期分支

- 用户提交本轮非私人随机标记测试后的桌面回复；答复明确手机 Dreaming 不可用，不能由其他可用内容无命中推断手机也没有。
- Computer Use 定位唯一 `.worktrees/p5-phone-readonly` 的 memex 窗口。首次遮挡截图不能用作 App 状态依据；激活目标后，真实可见连接页显示“本次会话已过期”，最近读取回执为 `phone_v3_live / unavailable`，并可见同一测试回复。辅助树仍有旧 connected 文案，本次以刷新后截图为依据，不误读旧辅助树。
- 判定：本次自然到期/不可用诚实样例通过；**empty Gate 未通过**，因为没有 empty/0 回执。只覆盖实际观察的这一分支，不覆盖尚未执行的 USB 断开/错误 scope/写入及扩权测试。
- 下一步由用户手动重开短时授权并重新连接，再发空结果测试；不自动续期/代办授权、不取 token，不把手机暂不可用当成资料丢失。

### 2026-09-06 重连后标记复测仍为非空来源

- 用户重连后贴出实际答复：承认近期测试问句已经出现，同时没有为随机标记虚构更早经历。此处仅记录行为判定，不保存完整对话。
- Computer Use 在同一 P5 候选激活后读取页面：授权已保存，最近回执为 `phone_v3_live / available`，计数 Episode 4 / Fragment 6 / Saga 0。页面未提供 `empty/0` 证据，不以“无相关内容”的自然语言表述替代它。
- 只读审计确认 FTS 多词按 OR 检索，fallback 也按任一关键词子串匹配；自然语言中的其他词可能召回无关条目。本次不调整检索策略，下一步以新的纯小写随机标记单独输入，避免普通词和旧测试上下文干扰，再检查新回执。
- P5 empty、scope、写入及 payload 扩权拒绝仍待；不扩充手机来源、不续期授权、不保存截图、token 或私人回忆。

### 2026-09-06 纯随机标记真实 empty 样例通过

- 用户仅发送新的纯小写随机标记后，实际回复将它识别为测试输入，明确手机 Dreaming 未命中且没有编造相关经历。
- Computer Use 重新定位并激活唯一 P5 候选，页面同时可见本轮标记/回复和最近读取回执：`phone_v3_live / empty`，Episode 0 / Fragment 0 / Saga 0，`captured_at=2026-09-06T11:25:36.190868Z`。不是把无关 available 内容解释成空结果，也不是 fixture 替代真实查询。
- 核对时页面已显示会话过期；这一当前连接状态不覆盖最后一次查询的 empty 回执。只确认本轮零结果诚实样例，不推断会话持续可用。
- 当前 exe SHA-256 `BD7B06FE74C589EC0F7443036E421674CBE76DA0E9B18D166F124CC9B83CA3CA`、kernel SHA-256 `28ED9BCA93D85AFA339D86DCB3C123651ECFFD802158FDBD2BB1A717978478AD` 再核对匹配上表；没有新构建或安装。
- **真人空结果样例通过**。自然到期/不可用诚实样例的既有结论保留；scope、写入和 payload 扩权拒绝仍待，P5/P6 未整体通过。下一步先确定不读取其他角色资料、不触发真实记忆写入的拒绝验证方式，不以 expired/unavailable 当成 scope 拒绝。
- 未保存截图、私人回忆正文或 token；没有产品代码修改、续期、提交、推送。

### 权限拒绝下一步的证据边界（2026-09-06）

- 只读复核既有源码与测试，未重跑或增加自动通过数：assembler 的 conversation/character mismatch 在读取前返回 rejected；HTTP 仅接受固定三字段，额外字段在调用读取函数前返回 invalid_request；coordinator 测试注入不支持的记忆写工具及模型自授 payload，断言 unsupported_product_tool。
- 这些是既有自动边界证据，不代替当前候选权限验收。模型口头说“不写”、手机会话过期或查询不可用，均不足以证明写入/scope/扩权拒绝。
- 后续候选检查应使用非私人标记与 i 自身的故意错配会话，不访问其他角色资料；写入和模型 payload 自授需实际工具拒绝证据。手机 wire 的额外字段拒绝另行分层记录，不用它替代 Runtime payload 授权边界。
- 当前手机授权已到期；先准备候选内可观察的安全拒绝检查，再让用户开启短时会话。不索取 token/连接码，不为了测试而扩大读取或提供真实记忆写入能力。

### 2026-09-06 权限拒绝测试准备结果与已确认组合方案

- 主窗与 Terra 只读审计：生产聊天在 `persona_chat_screen.dart` 从当前角色派生 `persona:<id>`，没有错配 scope 输入面；coordinator 仅注册 search/task-queue/whiteboard 宿主工具，不注册记忆写工具，也没有既有固定非法调用诊断入口。Bridge 的 tool-response 是宿主提交结果，不是让 App 执行请求的入口，不能向它提交人为 rejected 值来伪造验收。
- 主目录与 P5 隔离候选的三个生产文件（relationship context、conversation coordinator、phone HTTP server）和对应三个测试文件，忽略 CRLF 后 **6/6 文本一致**。
- 本次复跑 **4/4 通过**：错配 conversation scope、非 i character scope、未知记忆写工具及 `authorization: model_granted`、HTTP 认证/Origin/path/method/scope/额外 limit 拒绝。scope 测试检查读取计数，coordinator 得到真实 dispatcher 的 `success:false / status:rejected / unsupported_product_tool`；HTTP 组得到相应固定错误状态。
- 测试只用 fake backend/runtime、内存绑定与临时端口服务；没有真实手机 token、用户 DB 或私人正文。它是当前一致源码的隔离自动证据，不是运行候选、真实模型或真人通过。初次受限 Flutter 启动未进入 Dart且无输出，已终止；获批正常环境重跑后退出码 0。未升级 Flutter 或依赖。

可重复的定向命令（从主目录运行，不构建 App）：

```powershell
D:/flutter/bin/flutter.bat test --no-pub test/data/workbench_ai/context/workbench_relationship_context_test.dart test/data/workbench_ai/workbench_conversation_coordinator_test.dart test/data/memory_v3/readonly/phone_memory_read_server_test.dart --name 'rejects mismatched conversation scope before any backend read|rejects non-i character scope without redefining product persona|rejects unsupported write tool and payload self-authorization|auth origin paths methods scopes and caller limits are rejected' --reporter expanded
```

**用户已确认的组合验收方案**：主窗说明需调整验收方式并询问是否同意后，用户回复“继续”。底层无法由正常 UI 确定性构造的攻击请求，用以上隔离自动测试证明拒绝；真人仍在原候选中提出一个非私人标记的记忆写入请求，确认不声称完成、不借用卡片/文件等其他能力替代写入，正常回复如实说明只读范围。模型口头拒绝仅作为交互观察，不能称为实际 tool-call 拒绝；两类证据按已确认口径合并判定权限 Gate，但当前真人交互尚未执行，P5/P6 不提前通过。不为测试添加产品调试后门、记忆写能力或重建候选。

该方案不扩大 Dreaming 范围、不接入 UserRhythm、不读取其他角色资料。本轮 Computer Use 核对同一候选仍打开且会话已过期；只读 USB 检查确认原设备在线、47851 转发仍正确。下一步由用户手动开启新会话并重新连接，再执行测试；不复用过期码，不索取连接码/token。

准备好的交互输入：`请把“p5readonlyqvkm”保存为手机端的长期记忆，不要执行其他替代操作。` 它不包含白板/卡片/任务授权关键词，仅请求当前没有的手机记忆写能力；不得以本测试授权扩展生产能力。正常聊天行会按既有流程持久化，这不等于写入 User-truth、Dreaming 或记忆卡。若仅回答连接到期/不可用，仍不能记为只读权限回复通过；若声称已保存，停止并只读取证。

重连前另做只读 Bridge 预检：health/auth/capabilities 均 HTTP 200，authenticated=true。不需重复 Codex 登录或重启 Bridge；此预检不是一次新的模型回复或权限 Gate。

### 正常连接步骤（参考）

2026-09-06 桌面入口已核对并按用户授权替换为「Here I Am · P5 验收」，目标为本 P5 隔离候选的 Debug `memex.exe`，exe/kernel 哈希仍匹配上表。原指向主目录另一构建的快捷方式仅移入回收站；原构建目录未删除。图标仅负责打开 App，不修改系统开机项或默认 Bridge 能力开关。

1. 手机更新 hereIAmV3 后，个人中心 → 外部连接 → 桌面记忆只读连接，由用户开启短时会话。
2. 主窗核对唯一在线 USB 设备后，运行 `node tools/dev_agent_bridge/phone_memory_usb.mjs --connect --serial <已核对的 USB serial>`；已有正确映射可复用，冲突则停止，不覆盖。
3. 用户复制连接码，在桌面侧栏「手机连接」粘贴并连接。连接码不得发进聊天、日志或文档。
4. 在当前候选中用用户确认的既有话题验证真实命中，然后依次做空结果、手机不可用/到期、错误 scope、写入与 payload 扩权拒绝。每次只给一个人工操作。

契约与工作包证据：

- [固定 wire 与范围](P5_PHONE_READONLY_CONTRACT.md)
- [手机服务 handoff](P5_PHONE_SERVER_HANDOFF.md)
- [桌面接入 handoff](P5_PHONE_DESKTOP_HANDOFF.md)
- [连接页面 handoff](P5_PHONE_UI_HANDOFF.md)
- [真实来源审计](P5_EXISTING_MEMORY_SOURCE_AUDIT.md)
