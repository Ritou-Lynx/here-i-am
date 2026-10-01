# P6 R7 执行中宿主强退候选：设计与交接

2026-09-12；基线 `v3-lab` / `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`。本 worker 仅实现独有新候选并做纯测试，未运行真实 CLI、UAC、WFP 或提供方请求。未修改旧 target/witness、native v7、runtime、broker、transport、旧报告或全局状态文档。代码与测试现停止修改，实际运行由主控独立审核冻结后决定。

## 最小证据含义

现有 broker 的 `upstream_attempts++` 位于 exchange 调用之前，不能证明 HTTP 已送达。新 target 在自身 factory 注入真实 `exchangeTextOnly` 的透明包装：原样转交参数、signal、返回值与错误；记录 entered，finally 立即记录 settled。绝不延迟真实结果来制造 pending。

两阶段协议：

1. 真实 HTTP create，检查 profile v2、epoch/thread/session 一致、无 turn/arm/upstream。输出 `p6_r7_inflight_initial_v1`，内含旧九字段 native ready 与三个 session binding 字段。
2. witness 按原规则持有并核实 Node/native/CLI 的进程句柄与 PID/creation/image，读原 prepared/bound journal，确认 final 尚不存在，核对全部 import closure 与映像 pins。
3. witness 仅发送固定 `{"type":"start_turn"}`。target 经真实 HTTP POST 启动一次旧公开固定句 `Reply exactly: P6_R7_NATIVE_OK`。不接受任意 input、turn 或进程参数。
4. HTTP turn 响应全部读完后，等待真实 exchange 进入。真实 native `onDispatched` 回调与四项精确 turn binding 必须成立；同一同步取样段核对 entered=1、settled=false、upstream_attempts=1、无 terminal/text/error/release，随后立即输出 `p6_r7_inflight_ready_v1`。
5. witness 校验 ready 与 initial 对应，再次检查 held 三进程及 final absence。在收到 ready 至 kill 调用不超过 1000ms 的条件下，只强杀 held Node，退出码 77。这个时间限制不消除网络、调度或事件处理窗口。
6. 按旧严门采用 native durable final：原 journal 身份、input_eof、close_command_id=0、stdout emit=false、六项关闭事实全 true、pending=false、native 实际 exit3。Node 必须实际 exit77。witness 文件、raw process handles、reader tasks、managed streams 关闭后写报告；外部 capture 必须见 witness 实际 exit0 并 postpin，才能采用。

允许结论仅为：**在 ready 取样时，本地真实 turn 已派发且真实 exchange 调用未结束；其后精确强杀宿主，并按独立句柄及 durable receipt 验证本地资源回收。**

报告将 remote_running_at_kill、remote_computation_stopped、remote_billing_stopped、upstream_socket_abort_observed、broker_drained_after_kill、provider_terminal_after_kill 保持 null。没有额外原生 pipe 端、上游流量代理、TLS 内容记录或独立 socket 观测。不能声称强杀瞬间远端仍运行、远端停止计算/计费，或把本地进程消失等同于 TaskSession provider terminal/完整取消凭据。ready 后输出/完成仍可能发生；不能把 ready 时无文字提升为强杀前全时段零输出。

重启尚未测试；`restart_resume_verified=false`。当前 text resume API 不支持恢复；新的进程与新 attempt 只能重新开始，不能将丢失的旧 TaskSession ledger 伪造成已取消/已完成，也不自动重放旧任务。

## 失败责任

任意 initial/dispatch/ready/identity/pin 条件失败，尚未强杀时都通过原同一 API/owner 发起 graceful cleanup；不启动第二个 turn，不切通用 adapter。清理失败保留原 owner 和 witness handles，等待固定 graceful 重试；不能用超时许可猜测 PID 后 kill。

强杀后原 Node 已死，无法再通过它完成 graceful。witness 继续持有 native，允许原 cleanup helper 按既有 UAC 路径运行；实际退出/receipt 缺失即保持不确认。后续若需 retired recovery 必须单独按精确本 attempt 审核，不能修改原失败记录或放宽正常 helper 的 owner 条件。native 若先遇到 stdout 错误而记录 operation_failure，严格 EOF Gate 会失败，不能直接更名为 input_eof。

## 入口与编译

新文件均在 `tools/dev_agent_bridge/`：

| 文件 | SHA-256 |
|---|---|
| workbench_text_task_inflight_host_fault_target.mjs | D4E92AAA236888C076BC6AD7C2D5330E1A29F2091A27836091B295FB40881C72 |
| workbench_text_task_inflight_host_fault_contract.mjs | 7A5FA9370A7704798A204F558C8551BFA84F16F82E81646CBBA4BC3B4EBF7785 |
| workbench_text_task_inflight_host_fault_contract.test.mjs | 8C8F5F134C17D17A46C13FE9B5B9DA72239B27E6C3D5C65B5C7EF578C55018FF |
| windows_text_gate_inflight_host_fault_witness.cs | 10514755B6D9612423299C30C6646A4A8AED359C2CDB14817412AFBDB25E160F |

独立 C# 编译只需 Framework64 v4.0.30319 `csc.exe`、`/warnaserror+ /platform:x64 /target:exe /r:System.Web.Extensions.dll` 与此单一 `.cs`。Main 为 `HereIAm.R7.InflightHostFault.Program`，没有其他 native 编译依赖。

默认无参数 / `--plan` 仅打印 plan；`--self-test` 仅纯断言。实际入口仍九个参数：

```text
--apply-inflight-host-fault <nodePath> <nodeSHA> <newTargetPath> <targetSHA> <nativeV7Exe> <nativeSHA> <newReportPath> <closureManifest>
```

witness 启动 target 的固定参数是 `--use-env-proxy <target> --inflight-host-fault-target <nativeExe> <lowerSHA>`。原环境白名单、NODE_OPTIONS/NODE_PATH 排除、原生 `detached:true` 与三个 pipe 保持原候选。

实际 static-import closure 共 20 个 `.mjs`：bridge_runtime_shutdown、codex_app_server_adapter、codex_app_server_client、experimental_runtime_api、runtime_adapter、workbench_request_text_gate、workbench_response_text_diagnostics、workbench_response_text_gate、workbench_text_gate_transport、workbench_text_only_profile、workbench_text_stop_receipt、workbench_text_task_broker、workbench_text_task_host_fault_contract、workbench_text_task_inflight_host_fault_contract、workbench_text_task_inflight_host_fault_target、workbench_text_task_native_executor、workbench_text_task_native_probe、workbench_text_task_runtime_adapter、workbench_text_task_runtime_pin、workbench_text_task_session。主控需生成这 20 项精确新 manifest，保留原 `p6_r7_host_fault_closure_v1` schema，并冻结外层 build/runner/capture 与 inputs；不可借用旧 19 项 manifest。

## 验证

`node --test tools/dev_agent_bridge/workbench_text_task_inflight_host_fault_contract.test.mjs`：8/8 通过，包含独立 C# 无警告编译、默认 plan、66 项 managed self-test。`node --check` 新 target 通过。

覆盖真实包装的参数/signal/error 原样转交、同步与异步失败 settled、拒绝把已 settled 结果当 pending；ready binding 与 dispatch/重复 turn/arm/terminal/text/error/release 负例；逐字节 LF/CRLF、无效/超长控制帧、单次 start、graceful 重试及 close fence；六项关闭事实逐个 false、native exit0/4/unknown、PID creation 错配拒绝。C# 同时覆盖 initial/ready 精确键、身份与时间、Node exit77 必需、native6facts、句柄关闭失败保留等原 self-test。

这些是纯验证，未证明真实执行中强退、真实 graceful fallback、重启、App 生命周期或 production/human Gate。旧 idle host-fault actual03 及旧 HTTP 候选的实测结论仍只属于原冻结输入。

## 首帧编码修订（candidate 02）

主控实际 candidate 01 的 attempt `427b4805-2bb9-40b0-9c01-d25b3ea66676` 在 `inflight_ready` 失败，未 kill；主控记录 native exit0、graceful fallback=true，并独立读取原 final 的 close_command/stdout=true/六项 true/pending=false。原失败报告与冻结文件保留，不改判通过。

已确认编码机制：Framework `Process.StandardInput` 使用继承的 `Console.InputEncoding`。本 worker sandbox dummy 为 gb2312、preamble 空；主控使用与 actual 相同的非沙箱 PowerShell 启动方式运行同一只读源码 dummy，实见 `encoding=utf-8;preamble=EF-BB-BF`，首条 `start_turn` 线 bytes 以 `239,187,191,123,34,...,10` 开头。严格解析器因此不能匹配第一条命令；第二次 graceful 无新 BOM，可正常收敛。该定位不新增 actual01 的 turn 派发事实。

按主控批准，本次仅更改 control contract 与测试：整个控制流绝对起点允许一次 U+FEFF，其他位置、重复 BOM、前导空白与帧内 BOM 仍拒绝。有限命令/单次 start/重复 graceful/关闭 fence 不变，C# writer、target、native、三 pipe 及六项关闭要求全部保持原哈希。不用通用 trim，不放宽 JSON 或 RPC。

新增真实 Framework Process redirected-stdin → dummy Node control reader 回归：在仅测试进程内设置 Console 的 UTF8 编码缓存，避免更改父进程 Windows console codepage；仍使用真实 `Process.Start` 构造真实 StandardInput，断言 UTF8 BOM 与完整两行 wire bytes，以及首 start/次 graceful 各一次。没有 native/CLI/UAC/provider/WFP 调用。纯负例覆盖 BOM 绝对位置、重复/中间/后续帧/超长帧后以及分片字符输入。

旧 candidate01 contract SHA `C370B1A19765DD88EA026860A49F5D3D9D9EB12483F8FAA1BFA00894523C0F46`、test SHA `6B852B523342A304B3118C6011ECD3980AA598945A859D05A5878B9B239950EB` 仅为历史输入。新 candidate02 必须重新冻结 20 模块 manifest 与 inputs，不能沿用旧 closure pin。此修订尚未实际运行。
