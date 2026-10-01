# P6 R7 native task executor 候选交接

## 当前 v6 固定回环路由（2026-09-12）

主控后续 actual09/10 已分别通过固定文字完成与精确取消：同一冻结 exe SHA `166637F47E38348CB33B715A0A666CC8A664667BBC5110F2BADF002843F456C9`，恢复宿主既有 `--use-env-proxy`；两次均有匹配终态、绑定停止回执、native exit0、六项完整回收及 pending=false。取消回合为空文字且未释放响应。此前 actual08 打通本地路由但上游交换失败的报告保留。完整输入、独立复核与报告见 [主控实际记录](P6_R7_NATIVE_TRANSPORT_HANDOFF.md#current-v6-routing-evidence)。下方纯测试与路由假设描述保留 worker 交付时点；当前通过结果不替代生产或 App 生命周期验收。

当前源 SHA-256 **`f0639bbd955f16c8739a75eda9b45b22b704bae670b1fec4125518b946c120e6`**，测试 SHA-256 **`10eb770a47b1bbc11f6d6dc813106d0b8bbe600ac830d156e9bde2c120d36f42`**；编译工作区 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`。对冻结 `native-task-executor-05.cs` 的源码差异仅在 `TaskLaunchContract` 的两个方法。历史 v1–v5 冻结源和 exe 不变。

- 两种模式均新增唯一固定 `NO_PROXY=127.0.0.1`，保持原十个环境键值及认证 `CODEX_HOME` 替换；最终环境严格排序、十一键和双 NUL。不读取或继承调用者代理环境。
- 两种模式的固定参数末尾仅新增 `-c "features.respect_system_proxy=false"`，锁定本次所依赖的 reqwest 默认代理分支。原冻结 `CliStartupContract`、认证模式、CLI pin、WFP、Job、IPC、helper、关闭事实与退出策略均未修改。

主控实际 auth07 回报四次 `responseStreamDisconnected`、HTTP status null、willRetry true，broker 全零且完整关闭。主控另做只读系统代理布尔核对：代理启用且存在，绕过表有 `127.*` / `<local>`、无精确 `127.0.0.1`。官方 0.153.4 依赖 reqwest 0.12.28 / hyper-util 0.1.20；后者 Windows ProxyOverride 只做字符串转换，没有当前 master 新增的 IPv4 wildcard 到 CIDR 转换。这支持本次路由假设，仍须新候选实际 A/B 证明，不能称作已定位运行原因。[官方版本依赖](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/Cargo.lock#L11334)、[对应 Windows 代理转换](https://github.com/hyperium/hyper-util/blob/v0.1.20/src/client/proxy/matcher.rs#L621)。

该环境绕过仅改变固定回环地址的代理选择；NO_PROXY 本身不限定端口，原 WFP 继续只允许本 attempt 的 broker 端口，不增加允许的外连集合。它不能排除或修复认证刷新、agent identity bootstrap 等其它前置等待。

`node --test tools/dev_agent_bridge/windows_text_gate_task_executor.test.mjs` **2/2**；managed self-test **63**、独立 harness **589**。新增三组合法端口的两模式参数精确差异、两模式原十键不变、十一键唯一/排序/双 NUL、隔离 harness 合成代理环境不继承检查。全部只编译与 plan/self-test/managed harness；没有真实 CLI、UAC、WFP、模型或网络请求，没有读取真实代理值、凭据或 home 正文。worker 未冻结实际 exe；主控复核、独立审计、冻结与实际验证另行负责。生产与真人 Gate 保持未通过。

以下 v5–v1 是历史交接；各节“当前”仅指当时快照。

## v5 helper 有限诊断（仅纯验证，2026-09-12）

当前源 SHA-256 **`dbca23d0e4b7e56f6a5847468f6cd2aade9db40cfd6f46acd3f5e04d299376ca`**，测试 SHA-256 **`1ff059edebc8f60cea5ee6d0067c4b3694bc1c4588c0893a9e6fbe826e4b2709`**，工作区仍 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`。v4 冻结源 `native-task-executor-04.cs` 复核仍为 `930b436dd011df2f9299107c063d2a7c7d706a00e974c4bad7e016d0b3a10cb5`，未修改。

只读核对 auth04：attempt `9ad201c0-1e9b-4851-873d-0364f52efa53`，supervisor `fbe5882461130a93988f7468290c86edeba0e33cfeab8ad3322f1a7a44867f5f`；返回 `task_install_helper_rejected`、owner exit 4，Job/Handles=true，Process/Stdio/Rules/Helpers=false、pending=true、broker=0。该泛化错误不能区分 ShellExecute、ready、绑定、退出或 receipt，更不能据此断言 UAC 被取消或规则未安装。

v5 仅补充有限诊断。`TaskHelperRun.Invoke` 保存首次固定编码的 RecordedFailure，内容只有固定阶段/错误 family/准确 uint32 Win32 码，不存储或透传原异常正文。`RequireAccepted` 将该安全诊断交还 owner 的既有 error.code；后续 cleanup 阶段或错误不覆盖首次错误。ShellExecute 返回失败的实际 Win32 码在其它句柄查询之前先保存。WaitForSingleObject 的 WAIT_FAILED 保留准确 OS 错误；超时仍不视作真实 helper exit。没有改变 helper Accepted 的事实合取、Job/WFP/auth/receipt、no-child false 字段、pending 或退出码策略。

新增有限 stage 精确为：`helper_preflight`、`helper_shell_execute`、`helper_process_binding`、`helper_ready_wait`、`helper_ready_live`、`helper_image`、`helper_token`、`helper_lease`、`helper_ack`、`helper_exit_wait`、`helper_exit_binding`、`helper_exit_query`、`helper_exit_status`、`helper_receipt_read`、`helper_receipt_validate`、`helper_handle_close`。Node 需同步这 **16** 项白名单。原错误 families 不变，code 仍 ≤80 字符，例如 `task_helper_shell_execute_win32_1223`。这是将来发生该 API 错误时的准确编码示例，不是对 auth04 的原因判断。

验证 **2/2**，managed self-test **63**、独立 harness **506** 项。覆盖全部有限阶段、Win32 编码、首次失败跨阶段保留、不保留原异常内容、失败不改变 Exited/Receipt/Accepted，以及成功/receipt 缺失事实。worker 未执行真实 CLI / UAC / WFP / 模型，没有清理失败 attempt。主窗等待用户说明弹窗情况后再决定实际动作；本候选仍须独立审计与新 exe 冻结，不能继承历史实际通过。

以下 v4-v1 是历史交接；当前源/hash 以上述 v5 为准，v4 的固定物理 home 与原执行边界保留。

---

## 当前 v4 固定物理 home 修复（仅纯验证，2026-09-12）

当前工作区已由另一个获授权任务推进到 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`；本 worker 没有提交或合入。当前 native 源 SHA-256 **`930b436dd011df2f9299107c063d2a7c7d706a00e974c4bad7e016d0b3a10cb5`**，测试 SHA-256 **`1668874fa4736cb0f56d5f10dafc9a1b8f5f6ddc31636427faffcc32db8156b7`**。v1-v3 仍按各自冻结源/产物哈希理解；`native-task-executor-03.cs` 复核仍为 `4c711f83361ea4b3da807e8bfca45333c71256ceb47678a58ecadd1e9efd174f`，未修改。

v3 auth03 已将失败定位到 `task_files_dedicated_pin_canonical_rejected`。此次只读 Win32 元数据诊断确证：逻辑 HereIAm 目录不是 reparse，但 `GetFinalPathNameByHandleW` 与 Node `fs.realpathSync.native` 都返回该 Codex 包的 AppData 私有物理目录。从 HereIAm 起，多出的四段是 `Packages / OpenAI.Codex_2p2nqsd0c76g0 / LocalCache / Local`；不是大小写差异、尾斜杠或凭据缺失。

只读用户上下文核实注册包 `OpenAI.Codex` 的精确 PFN 为 **`OpenAI.Codex_2p2nqsd0c76g0`**。持有桌面父进程句柄（注册安装目录内的 ChatGPT.exe）时，GetPackageFamilyName 返回成功，family 与注册匹配、进程镜像在对应安装目录内且仍 live。当前 shell/CLI wrapper 自身 GetCurrentPackageFamilyName 返回 15700，无 package identity；没有把父进程身份说成执行器自身身份。

两个同时持有的目录句柄证明：逻辑 home 与该精确 PFN 下固定后缀 `LocalCache/Local/HereIAm/Runtime/p6-text-only-codex` 的物理 home **volume/index 相同**；逻辑 final path 正好等于固定物理目录；物理目录和全部 **12** 级祖先均严格 canonical、directory、no-reparse。所有诊断句柄均在 finally 实际关闭。只读查询没有访问任何认证文件或内容，没有移动/复制 home、改 ACL、请求 UAC 或启动模型。

v4 是 **本机精确 PFN 的冻结候选**，不设计无 identity 时的动态包兼容。authenticated 的 CODEX_HOME、VerifyHome 和 Ancestors 统一指向上述固定物理目录；不接受外部 home/PFN 参数、不回退别的 home。物理目录全部祖先继续使用原严格 VerifyPath 并持有句柄。另持有逻辑 home 目录句柄，仅允许其 final path 精确等于固定物理路径，且 logical/physical 两句柄 directory/no-reparse、volume/index 一致；任何另一 family、路径或身份不一致都拒绝。全局 `MatrixNativeApi.VerifyPath` 未修改，专用目录和凭据未改动，no-auth args/env 字节不变。

唯一新增有限诊断阶段为 **`files_dedicated_binding`**，Node 的有限 stage 白名单需同步。清理与退出码语义不变；没有对象时仍不伪造 process/EOF 关闭。

验证 **2/2**，managed self-test **63**、独立 harness **372** 项。新增同目录标识、logical mismatch、另一 PFN/LocalState、错误后缀、reparse/错误类型/零标识，以及部分 handle close 失败后重试仍粘滞失败的回归。worker 没有运行真实 CLI / authenticated probe / UAC / WFP / 模型。主窗将冻结新 exe、独立审计该差异后另做实际验证；本节只证明修复依据和纯测试，不继承 v1 的实际通过结果。

以下为历史 v3-v1 交接；当前源/hash 与 home 入口以上述 v4 为准。

---

## 当前 v3 有限启动诊断（仅纯验证，2026-09-12）

源 SHA-256 **`4c711f83361ea4b3da807e8bfca45333c71256ceb47678a58ecadd1e9efd174f`**；测试 SHA-256 **`023970a45016a248af1239db916b4a09bdd45b1040c4c67d8654aabffc0322e7`**。v2 冻结源 `native-task-executor-02.cs` 仍为 `0f0bfd7e85474742b8d3cea0d2e704c4317187b2531d4256867efe7bd22b1283`，未修改。未放宽 home canonical、路径 pin、ACL、认证、RPC 或关闭契约。

只读核对 `native-task-auth-actual-01.json`：attempt `46698da8-8126-477a-a1c8-66d423d88c34`、supervisor `63ccad13bdd95367593b01fca64ac95ba9c5e7e52167615930c2c7d583078dc6`，started/config/account/thread/turn 均 false、pending=true、upstream=0、报告 code=`native_probe_close_unconfirmed`。主窗观察新 attempt 已有 copied CLI/project0/work，但没有 prepared journal；由于 prepared 在 **TaskFiles 返回且 TaskChild 构造完成以后**才写，不能据此只定位到 home，也不能证明 Job 从未尝试创建。

worker 只读检查 dedicated home 与各级祖先元数据：均为目录、未见 reparse/link，用户有 FullControl。它本身 ACL 为继承态，本候选并不要求 dedicated home protected，也没有修改它。已知 forbidden home 元数据均 absent；skills 存在属于允许项。**现有证据尚不能确定失败原因。**没有读取凭据、重跑 native、请求 UAC、清理失败 attempt 或修改目录。

v3 保持 `error` frame schema 不变，仅将泛化 `task_executor_failed` 换为有限 stage/family code。阶段覆盖 TaskFiles 的源/自身镜像/根/attempt/CLI copy/工作目录/专用 home pin/空 cwd 与 home 元数据，以及 TaskChild 的 Job create/limits/readback、CLI attributes/atomic Job/stdin allowlist/CreateProcess/creation-time/binding 等。例：`task_files_dedicated_pin_win32_5`、`task_job_limits_win32_87`。BoundaryError 有 Win32Error 时保留 uint32 十进制值；其它异常仅映射固定 family，不输出原 exception、路径、SID、凭据或账号值。所有 code 不超过 80 字符。

阶段只是执行位置证据：`job_create` 表示已经到达创建调用阶段，不等于创建成功；`child_spawn` 也不能替代返回句柄/进程状态。未创建 child 时仍保持 process_close_observed=false 与 stdio_eof_verified=false；清理不完整或无法证实仍 exit 4 / pending=true。没有把“没有对象”合成“对象已关闭”。

验证 **2/2**：managed self-test **63**、独立 harness **347** 项，包含所有有限阶段 × 错误类别、Win32 数值、长度/字符集、原异常内容不泄露、未知 stage 拒绝投影，以及 no-child 的 false 关闭字段。仅编译和 managed tests；新候选下一次实际诊断仍由主窗冻结后执行。

以下 v2 / v1 内容是历史候选交接；启动与认证契约未改变，当前源/hash 以上述 v3 为准。

---

## 当前 v2 authenticated 候选（仅纯验证，2026-09-12）

当前源 `windows_text_gate_task_executor.cs` SHA-256 **`0f0bfd7e85474742b8d3cea0d2e704c4317187b2531d4256867efe7bd22b1283`**，测试 SHA-256 **`8f2ce9faa065bf8bd59ff5b55ab66e86d989168fa036d2b714ae8a7c135ecabd`**。新增显式 `--apply-authenticated-task-executor <lowercase UUID-D> <decimal broker-port>`；原 `--apply-task-executor` 继续为 no-auth，Job / copied CLI pin / 网络规则 / IPC 顺序 / 停止与退出码策略不变。默认 plan / self-test 不启动任何 native 角色。

authenticated 固定启动契约与 `CliStartupContract` 逐字相同，唯一参数差异为 `requires_openai_auth=true`；provider/model/flags 不变。环境唯一差异为 CODEX_HOME 指向 `%LOCALAPPDATA%/HereIAm/Runtime/p6-text-only-codex`。它必须已存在，普通 coordinator 持有全部 canonical 祖先目录句柄；不创建、不清理、不复制这个 home，不读取凭据或目录正文。允许已有 skills 缓存，继续依赖固定禁用 flags、skip_host_skill_discovery、空能力根与主窗 config/readback 验证。只做元数据检查，拒绝该 home 内 config.toml、AGENTS.md、AGENTS.override.md、plugins、hooks.json 和 .codex；没有删除或回退至其他 home。CLI 自己拥有认证读取/刷新，网络仍只能到绑定 broker。

STARTED 新增 `auth_mode: "no_auth" | "chatgpt"`，不包含账号值或 home 绝对路径。私有 journal、helper lease 和 helper receipt 升为 v2 并绑定 `auth_mode` 与 `home_class`（`fresh_attempt` / `dedicated_existing`）。窄 helper 的内部参数变为 `--task-executor-helper UUID action mode`；它必须与已持有 attempt journal 的模式和 home 类别一致，不能将另一模式的 attempt 重分类。helper 不访问 dedicated home。

RPC `account/read` 只允许 authenticated 模式且参数精确为 `{refreshToken:false}`；no-auth 仍拒绝。登录、注销、凭据写入和 refreshToken:true 仍拒绝，其余 RPC 白名单不变。这只是允许 CLI 报告认证状态的能力；account 回显不等于 token refresh 成功，更不等于真实模型请求成功。

本包验证：`node --test tools/dev_agent_bridge/windows_text_gate_task_executor.test.mjs` **2/2**，C# `/warnaserror+`，managed self-test **63**、独立 harness **91** 项。新增正反例验证 no-auth args/env 字节不变、authenticated 仅固定差异、skills 残留允许与配置元数据拒绝、模式解析、account/read 模式/参数、journal/lease/receipt 模式绑定和跨模式拒绝。worker **未执行真实 CLI / UAC / WFP / 账户读取 / 模型请求**；主窗仍须冻结新 exe、独立审计和实际验收。

v1 冻结源 `tmp/p6-r7-review/native-task-executor-01.cs` 仍是 `76eb748d27a447c2d6df7e1a1b67d7da73f866fdb39a11800030b6a6fc2b123c`，未修改。只读核对主窗 `native-task-executor-actual-01.json`：attempt `5abbcb3a-6560-48d4-b126-a5ce89a51965`，supervisor hash `19b75e60b11f2783bea551a6909601dbc6a1546ed05d8f50353f693b9ae95a2c`，no-auth / no-turn initialize-config-thread-close 报告 passed=true、process_close_observed=true、cleanup_pending=false、broker admissions/upstream=0。该结果只属于 v1，不能继承为当前 authenticated 候选或真实账户通过。

以下为 v1 的原始交接，保留其精确冻结输入与协议基础；当前 v2 差异以上述内容为准。

---

日期：2026-09-12。基线 `v3-lab@bbb8025d`，保留工作区既有修改；本包只新增 native executor、其测试和本交接。未 stage、commit、启动真实 CLI、请求 UAC、修改 WFP、访问账户或发模型请求。主窗负责冻结候选、实际执行与全局项目状态。

## 当前结果

`tools/dev_agent_bridge/windows_text_gate_task_executor.cs` 实现普通 Medium coordinator 持有 singleton / kill-on-close Job 的真实 CLI 生命周期候选。启动仅接受 `--apply-task-executor <lowercase UUID-D> <decimal broker-port>`；默认与 `--plan`、`--self-test` 均不进入 native 执行。

固定复制官方 CLI `7ac07f4ce733f89a/codex.exe`，SHA-256 `3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004`；不接收任意路径、参数、环境或配置。新 attempt 位于固定 task-executor 根，`project0` 是全新空 cwd，`work/empty-home` 是全新、canonical 且持有路径句柄的 **no-auth home**。使用原 `CliStartupContract`，provider 为 `p6_native_startup`、`requires_openai_auth=false`。专用已登录 home 完全不访问、不复制、不修改；它的既有 skills 目录不再构成本候选前置条件。

本次是 **no-auth 候选**。真实账户可用性、刷新、已认证任务、生产可用性、文件隔离、真人 Gate 均未获证明。后续 authenticated contract 必须单独实现和验收，不能把本候选的 config/account 回显当作认证证据。

## 生命周期与控制协议

- coordinator 持有 CLI 镜像、源镜像、路径、Job、进程、创建时间和 stdio；`CreateProcessW` 使用 `0x8040c`（detached / suspended / Unicode / extended startup），Job 和三个 stdio 端点进入原子属性清单。绑定 image / creation / Medium token / Job singleton 后才 resume。
- 安装和清理由窄 elevated helper 执行。task 自有 domain、scope、fresh append-only metadata、随机 nonce、helper live lease/ACK、真实 helper PID/creation/image/token 和实际 exit + receipt 共同验证；文件存在不视为就绪，等待保留 exclusive-writer sharing/lock violation 重试修复。
- WFP 规则实现逐字复用冻结 coordinator15 的 `CoordinatorBoundary`，唯一规则类差异是 `TaskBoundary.CloseVerified` 检查 `FwpmEngineClose0`、失败粘滞并保留重试，不继承原 Dispose 的乐观关闭。临时 token 和线程句柄也纳入 checked ledger。
- stdin/stdout 是 inherited parent 控制 NDJSON，永不向 Node 返回 HANDLE。JSON 上限 2 MiB UTF-8、深度 32、RPC payload 256 KiB；所有层拒绝重复键，包括 escaped 同名键。输入 `seq`、`command_id` 各从 1 严格递增，attempt 必须精确 UUID。输出 `seq` 在全局顺序锁内递增。
- 输入：`{attempt_id,seq,command_id,type}`；`rpc` 加 `message`，`verify_peer` 加 `tuple`，`close` 无额外键。tuple 严格为 IPv4 TCP loopback 双端点，`local_port` 等于固定 broker port。
- 输出 `started`：`cwd,provider,cli_sha256,pid,creation_time,network_boundary_verified,child_identity_verified,job_singleton`。SHA 小写，creation_time 是十进制 uint64 字符串。该网络字段是本次规则安装 readback + helper exit/receipt，不代表实际网络矩阵或生产验收。
- `written` 只有 `command_id`，在真实 CLI stdin 写完后产生；已可读的旧 stdout 帧先排空，最多 64 帧 / 2 MiB / 256 reads，超过上限拒绝派发。随后写入与 ACK 在同一锁内，CLI 新输出不会抢在 ACK 前。`rpc` 带实际 stdout JSON `message`。
- `peer` 带 `command_id,verified,pid,creation_time,cli_sha256,job_member`；按输入的实际 accepted tuple 查询 TCP owner 表，并重验 held child PID / creation / image / token / Job。拒绝时后三个 identity 值为 null、job_member=false。Node 必须继续持有和复核原 accepted socket；这不是可缓存的任意端口许可。
- RPC 仅放行固定 initialize / initialized、config/read、configRequirements/read、严格 thread/start、text-only turn/start、turn/interrupt 与固定 -32601 server error。thread/start 绑定 cwd、模型、provider、never、read-only、ephemeral 和空工具/环境集合；不放行 config 写入、账户 RPC、认证变更、resume/fork 或执行指令。
- owner stdout 和 CLI stdin 都使用独立 held writer thread、5 秒等待和 CancelSynchronousIo，取消后必须实际 join。未结束线程/未关资源保持失败并在最终清理重试。普通 parent EOF、close、协议错误和 timeout 都进入同一 owned child stop / Job0 / EOF / helper cleanup 路径。

`closed` 带 `command_id`（显式 close 对应值，EOF/失败为 0）与 `receipt`。receipt 精确七键：`process_close_observed,job_empty_verified,stdio_eof_verified,rules_absent_verified,handles_closed_verified,helper_exits_verified,cleanup_pending`。前六项全部来自实际观察；仅全部 true 时 pending=false。尚未创建 child 不伪造 process/stdio 成功。未知或失败保留 pending。Node 仍须同时确认 supervisor 实际 close、严格允许的退出码和 post-pin，才可接受完整停止。最终 closed 帧发送完成后，再检查该帧专用 writer 的实际 join/handle close；正常完成仅 exit 0，operation 失败但清理完整且 final Emit 成功、无粘滞句柄关闭失败才 exit 3；任何清理不完整、final Emit 失败或最后 writer handle 关闭失败统一 exit 4，不能作为关闭证明。32 组 managed 退出决策真值表覆盖所有布尔组合。

stderr 只有限量排空，不作为 transcript 输出；不写 RPC、输入、回复、认证或日志正文。落盘仅为私有生命周期 metadata、lease、ACK 和 receipt。

## 本机验证与冻结输入

`node --test tools/dev_agent_bridge/windows_text_gate_task_executor.test.mjs`：**2/2 通过**；C# `/warnaserror+` 编译、native managed self-test **63 assertions**、独立 managed harness **61 assertions**。覆盖重放/序号/未知字段/IPv4 tuple/重复键/UTF-8文本/深度/大小/旧输出先于新写/写后 ACK 先于响应/并发输出锁/写失败无 ACK/共享写竞争/不安全 RPC/receipt 失败保守投影；并比对 WFP 规则类仅有 checked-close 差异。测试未调用 actual verbs。

| 输入 | SHA-256 |
|---|---|
| executor source | `76eb748d27a447c2d6df7e1a1b67d7da73f866fdb39a11800030b6a6fc2b123c` |
| executor test | `5837135e243df7468816f74720ab475a93c657f680a83dca4186b13f2a23feb4` |
| `windows_text_gate_isolation_helper.cs` | `d22017641d9f8df750f6db7db9319b8c1930a726a8575ff1ffabfde0d5ffdcd8` |
| `windows_text_gate_appid_startup_helper.cs` | `c777023495ccdbf3b52663f49683f5d84dcfd03a36b3d280a75c925f37b7a1ea` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `c1f07e9487b8ce25d0acc2d5bbb03b69c975cbb7e448698d288ff6263cff9311` |
| `tmp/p6-r7-review/native-appid-matrix-contract-01.cs` | `f70ffb86ce5efea2572532e1986f77dde9622893ad4b90a74f9ec40da5ba6774` |
| `windows_text_gate_appid_matrix_native.cs` | `f2d3b35a1e6d1763930ba7f9a82ab8dbb595e02d5d720216a0161dbce8a0d0ab` |

编译主入口 `HereIAm.R7.TaskExecutorProgram`，framework64 C#、x64、`System.Web.Extensions.dll`，与表中五个冻结依赖联合编译。测试临时产物已回收；最终 exe 与其 hash 由主窗冻结，不把 worker 中间编译产物当成候选。

仍待主窗：冻结精确 source/exe、独立审计确认，然后在已授权范围进行 no-auth / no-turn initialize-config-thread-close 实际验证。该阶段不应调用 account/read 或 turn/start，也不沿用其他 exe 的网络/关闭结果。

微软 [CancelSynchronousIo 文档](https://learn.microsoft.com/en-us/windows/win32/api/ioapiset/nf-ioapiset-cancelsynchronousio) 说明需 THREAD_TERMINATE 权限且取消本身不等待 I/O 结束；这里使用对应 held thread handle 并另验实际 join。实际 OS 超时故障仍未注入验收。
