# P6 R7 App 候选 Node 宿主交接

本包仅在 `codex/p6-r7-app-entry@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5` 新增独立宿主及专项测试。未修改生产入口、profile、native、broker、TaskSession、runtime adapter；未运行真实 native、UAC、账户或 provider，也未编译 App、提交或改机器配置。

## 本次候选

- `tools/dev_agent_bridge/workbench_text_task_app_candidate_host.mjs` SHA-256：`e7d3f9bb350197131a42f3ae507d1229e6009c492295cc083e6b9648c8e1109f`。
- `tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs` SHA-256：`467b7082b7cc1d5e8ca910444e9b72e50f4cbb7ea65b5bf27268374f2c088ef5`。
- 真实路径固定接受 native v7 SHA-256 `73cbe6277fd4bf5b92bdc3189e00eee5ce78f208d6037d8d16a14df9bde4bc4e`；主控另行提供绝对 exe 路径、冻结清单及实际验收。

## 准入与跨语言契约

显式 CLI 启动标志为 `--apply-app-candidate-host`。依次提供 `--native-executable`、`--native-sha256`、`--closure-manifest`、`--closure-sha256`、`--admission`。没有自动生产启动或默认可用路由。Node 启动参数必须恰好为 `--use-env-proxy`，拒绝非空 `NODE_OPTIONS`、`NODE_PATH`；不修改代理环境或读取其真实取值。

清单 schema 为 `p6_r7_app_candidate_closure_v1`，仅包含 `schema` 和 `files`；每项只有绝对 `path` 与小写 `sha256`。清单摘要为文件原始字节的 SHA-256。递归校验当前 entry 的全部静态 ESM imports，拒绝缺项、额外项、重复项、动态或第三方包 imports；每次准入、创建与派发前重核。文件与全部祖先必须规范且无符号链接/重解析重定向；读取前后核验文件身份与摘要。准入文件 CreateNew，预检完成后才写入并 flush/close；已存在文件不覆盖。

准入 schema 为 `p6_r7_app_candidate_admission_v1`，恰好七字段：`schema`、`launch_id`、`base_uri`、`profile`、`source_closure_sha256`、`native_sha256`、`admission_token`。最后一项是宿主随机生成、仅供本次启动使用的本地能力令牌，不得写入 DB、页面、日志或交接。App 由外部固定 admission 文件摘要，并传 launch 绑定与能力令牌；宿主拒绝重复认证头、错误 Host、Origin 和非 IPv4 loopback 连接。

`/p6/r7/candidate/attest` 的挑战响应 schema 为 `p6_r7_app_candidate_attestation_v1`，恰好九字段：`schema`、`challenge`、`launch_id`、`port`、`profile`、`source_closure_sha256`、`native_sha256`、`no_turn_preflight_verified`、`ready`。挑战只接受单个有界小写十六进制字段。响应不回显能力令牌。真实预检尚未完成时不准入；纯测试注入不能写出实际准入文件，两个就绪事实始终为 false。

宿主只监听 `127.0.0.1` 独占随机端口，明确排除 `47831`、`47841`。runtime 路径复用 `/experimental/v1/runtime`，只允许创建、已知 session 的事件、开始固定文本 turn、精确 interrupt 和 DELETE。未知 session、通用账户/工具/审批/恢复/steer/host-stop 路由不会构造 ordinary adapter。

## 执行与关闭

启动预检复用真实 ExperimentalRuntimeApi 同款 adapter：broker → native owner → attached client → 固定 config/缓存账户类型/thread 校验 → no-turn close。只有品牌 stop receipt 完整绑定，native 实际 exit 0、六项关闭事实 true、pending false、broker drained，并且零 arm、零 upstream、未放行模型响应后才发布真实 ready。允许至多八次本地 metadata 拒绝，拒绝其他请求计数异常。

App 实际输入严格匹配生产 `TaskQueueExecution._input` 的原有完整前缀、固定公开 goal 及最终换行；previousText 必须为空。导出 `APP_CANDIDATE_GOAL` 与 `APP_CANDIDATE_INPUT` 供跨语言 fixture 对照。禁止将裸 goal、部分结果、任意文字或 caller 指定模型/CLI/config 当成新授权。

单个宿主同一时刻只保留一个未确认关闭的 owner，创建中同步占位；每次启动最多 16 个 owner（含预检），宿主寿命 30 分钟。关闭失败保留原 owner/slot，允许同一 DELETE 或宿主 shutdown 重试；幂等 tombstone 不会释放后来新建 owner 的 slot。启动断线交给真实 API AbortSignal 回收同一资源。源码摘要漂移会立即阻止新派发并发起清理，即使最终摘要校验失败也不能阻止资源回收。

SIGINT、SIGTERM、控制输入 EOF 或寿命到期调用既有 `createBridgeRuntimeShutdown`。shutdown 同步阻止新创建和 turn，等待 API/预检所有 owner 及挂起 HTTP 操作；关闭未确认不签发成功状态，不静默重试 UAC，不放弃原资源。准入文件不会被重写为关闭证明；后续每个真实 turn 仍需现有 v2 execution/stop receipt。

## 纯验证与界限

`node --test tools/dev_agent_bridge/workbench_text_task_app_candidate_host.test.mjs tools/dev_agent_bridge/experimental_runtime_api.test.mjs`：**18/18**，其中新宿主 **13/13**。新测试使用真实 API 与 adapter、fake native/provider、真实本地 HTTP socket；覆盖精确 Dart formatter、代理启动限制、路径/闭包/输出拒绝、合成与真实证据隔离、单 owner、固定输入、JSON terminal/幂等关闭、创建中断线/停止、关闭失败同 owner 重试、no-turn 计数/native exit 拒绝，以及闭包漂移时的清理。

这不是 native/UAC/provider 或 App 真人 Gate 证据。source closure 是启动时及关键动作时的文件校验，不是操作系统对监听进程身份的独立证明；主控仍需冻结输入并核验实际监听宿主。JavaScript 路径/摘要校验没有宣称持有 Windows deny-write 句柄，也没有改变原有 native 的精确进程/Job/WFP 权限边界。当前仅是独立 App 候选宿主，生产 profile 继续拒绝。

只读 `snapshot()` 返回 `p6_r7_app_candidate_host_evidence_v1`，明确 synthetic，包含真实 ready attempt/子进程身份、session/turn/stop 回执、六项关闭事实、native exit/pending 和有界 broker 计数；同 adapter 幂等 tombstone 取证，未知保留 null。无新 HTTP 接口，无能力令牌、凭据、正文或原始错误；仍须独立核对实际宿主进程/端口及证据窗口。
