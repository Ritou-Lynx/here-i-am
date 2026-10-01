# P6 R7 Job 限额合成探针 v4

## v4 当前交接：显式 detached 自有哨兵对照

### v4 本机固定哨兵实际通过（root 执行，本包到此停止）

root 对相同冻结候选完成最终 Node **13/13**、managed selftest **29 策略（27 负例）+16 parser+2 flags** 与四份 hash 复核，并运行 `--apply-job-limit-synthetic-detached`，记录真实 native exit **0**。报告 `tmp/p6-r7-review/native-job-limit-probe-03-detached.json` 已由 worker 只读核对内容及 SHA-256：`1DDFAE35807CD68A2B5FB5A9263310052CEDBEDC64CB5C4128F81487D01AD283`。root 确认 EXE 在执行前后 pin 未变，仍为本页 v4 哈希。

- `passed=true`，requested flags `525324 (0x8040C)`，Job flags `8200 (0x2008)` / ActiveLimit `1`；before 与 during 均 active/total/terminated=`1/1/0`。
- first 的 pre-resume identity、ready alive 与 second 尝试前后 alive 均 true；second `created=false`、真实 error=`1816`、entry=false。first exact exit=true，正常 exit code=`0`。
- after accounting=`0/1/0`，child/all owned handles closed=true，cleanup query 成功，`cleanup_pending=false`。
- after-create 与 ready 的 class 3 列表各只有一名 expected-probe；before-cleanup 列表为空。三阶段 snapshot 均 complete，bookend counts 一致。

该结果仅证明**本机、此固定哈希、自有事件哨兵使用 DETACHED_PROCESS 时，ActiveLimit1 拒绝了唯一第二次 atomic create，并完成本次 Job 清理**。它不证明真实 CLI、network、production 或真人 Gate；也不能据此改动真实 CLI 的 console 行为。`cleanup_pending=false` 只针对本次探针的资源，不代表其他工作流已清理。root 交接的 **2718 WFP 仍 pending、尚未清理**；本包未查询或修改它，后续先等待人工 Windows 确认。此次仅补本文结果，冻结 source/test/snapshot/EXE 未改，不再继续该包实验。

微软 [Process Creation Flags](https://learn.microsoft.com/en-us/windows/win32/procthread/process-creation-flags) 定义 `DETACHED_PROCESS=0x8`：console process 不继承父控制台，不能同时使用 `CREATE_NEW_CONSOLE`；与它混用 `CREATE_NO_WINDOW` 时后者会被忽略。[Creation of a Console](https://learn.microsoft.com/en-us/windows/console/creation-of-a-console) 进一步明确，通过 DETACHED_PROCESS 创建的 console process 初始不附着控制台，可在随后主动调用 AllocConsole。探针自己的 Sentinel 成功路径仅使用具名 Win32 事件，不调用 AllocConsole/AttachConsole 或控制台 I/O，因此官方契约支持进行这个有界对照；这不预先证明 conhost 会消失，也不外推真实 CLI 的控制台需求或兼容性。

v4 相对冻结 v3 的源码仅增加：显式 `--apply-job-limit-synthetic-detached` 入口、贯穿同一路径的 detached 选择、纯 `CreationFlags(bool)`、报告 mode/`requested_creation_flags`、版本号及两种 flags 的 managed 检验。新模式请求 `0x0008040C`（SUSPENDED | EXTENDED_STARTUPINFO_PRESENT | UNICODE_ENVIRONMENT | DETACHED_PROCESS），不混入 NO_WINDOW / NEW_CONSOLE。既有 `--apply-job-limit-synthetic` 保持 NO_WINDOW 请求值 `0x08080404`。ActiveLimit1、before active=1/total=1 gate、class 3 三阶段诊断、同一 atomic second-create 次数、second never-Resume 与最终清理判定均未改变。未改真实 CLI、网络或其他 helper。

### v3 已有真实观察（root 执行）

报告 `tmp/p6-r7-review/native-job-limit-probe-02-members.json` 已只读复核，SHA-256 `DE86B42D9F33D741DA49BB84BA08F51A1F81AA596BC6239973BEDD4F977B7C47`。root 记录实际 exit 2；JSON stage7、before active=2/total=2/terminated=0、second 尚未尝试。after-create 是唯一 expected-probe；ready 与 before-cleanup 各两名，另一成员精确路径类别为 system32-conhost，身份/member/wait/close 与 accounting bookend 均完整。最终 afterActive=0、allhandlesclosed=true、cleanup_pending=false。此证据定位了 NO_WINDOW 哨兵候选的额外 Job 成员类别，不是 second-limit 通过，也不是 CLI 行为、限额失效或 conhost 创建者的证明。

### v4 验证、冻结与实际入口

- 最终 source/test 的 Node **13/13** 通过；managed selftest **29 策略用例（27 负例）+16 parser 用例+2 launch flag 用例**。新增纯测试验证 detached 与 no-window flags 互斥、不含 NEW_CONSOLE、两模式仍拒绝缺失 cleanup 与 before2/2，除 mode/请求 flags 外同一纯证据报告一致。原成员诊断与边界测试保留。
- candidate-04 经 Framework64 compiler `/platform:x64 /target:exe` 编译实际 exit **0**；冻结 v4.exe `--selftest` / `--plan` 实际 exit 均 **0**，报告 `native_executed=false`。worker **未运行任何 v4 actual apply**；没有创建此对照的 Job、sentinel、事件或 attempt 目录。v3 snapshot / EXE 未覆盖，v4 冻结后 source/test/snapshot/EXE 不再编辑。
- 以下前两项是已执行的纯验证命令；第三项后来已由 root 对本表同一 EXE 哈希实际执行，结果记录在本页开头，worker 未执行。该结果未继承 v3 证据。

```powershell
node --test tools/dev_agent_bridge/windows_text_gate_job_limit_probe.test.mjs
& .\tmp\p6-r7-helper\windows_text_gate_job_limit_probe.v4.exe --selftest
# 已由 root 执行；此处仅保留所用入口，不要求再次执行：
& .\tmp\p6-r7-helper\windows_text_gate_job_limit_probe.v4.exe --apply-job-limit-synthetic-detached
```

可复核最小源码 diff（exit 1 仅代表有差异）：

```powershell
git diff --no-index -- tmp/p6-r7-review/native-job-limit-probe-candidate-03.cs tmp/p6-r7-review/native-job-limit-probe-candidate-04.cs
```

| v4 产物 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_job_limit_probe.cs` | `D9FD7D454E4B5C7906420C76FAC3277DA1FA5492088ACD48874E6BC288E3DA1D` |
| `tools/dev_agent_bridge/windows_text_gate_job_limit_probe.test.mjs` | `CB08284234A80921D2E61504AEA9AC28BB318D5D126B088B477D71BAC88650DA` |
| `tmp/p6-r7-review/native-job-limit-probe-candidate-04.cs` | `D9FD7D454E4B5C7906420C76FAC3277DA1FA5492088ACD48874E6BC288E3DA1D` |
| `tmp/p6-r7-helper/windows_text_gate_job_limit_probe.v4.exe` | `27250168488554600D3DE33433CF944A2D4437784FA1F56A8AFAFEBB10CFE41A` |

## v3 冻结时交接（历史）：仅增量诊断

v3 保留 v2 的 `before ActiveProcesses == 1 && TotalProcesses == 1` 门槛及唯一 atomic second-create，没有放宽通过条件、增加继承 spawn 或恢复 second。只增加 held own-Job 的三次固定成员快照：first suspended 创建成功后、ready 后、进入清理之前。未知诊断禁止进入 second-create，并使最终通过判定失败；首次 first 的既有身份核验/Resume 仍可完成，以取得固定 ready 后快照。

实现依据为微软的 [JOBOBJECT_BASIC_PROCESS_ID_LIST](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-jobobject_basic_process_id_list) 与 [QueryInformationJobObject](https://learn.microsoft.com/en-us/windows/win32/api/jobapi2/nf-jobapi2-queryinformationjobobject)：class 3，两个 DWORD 分别 offset 0/4，x64 ULONG_PTR 数组 offset 8，头部含首元素结构大小 16；本探针分配固定上限 16 个成员的 136-byte buffer。纯 parser 严格检查 buffer 长度、返回长度/对齐、完整 assigned/list count、数量上限、截断、DWORD PID 范围、零值与重复值。失败不扩容、不重试、不使用部分列表；失败查询的未知 returned_bytes 为 null。

唯一 `OpenProcess` 调用只接受上述完整 own-Job 列表给出的成员，访问权为 `PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE`，不继承句柄。逐个检查 held process 的 PID、非零且稳定 creation time、creation 不晚于列表查询开始、`IsProcessInJob`，以及若匹配 first 则与其原 held identity 一致。仅在 wait=timeout 时查询完整映像，随后再次验证身份和 wait；每个诊断句柄当场核验关闭，失败仍进入总清理 ledger。没有系统全表查询，没有 raw PID、creation 值、身份或路径输出。

`image_class` 只投影为固定集合 `expected-probe` / `system32-conhost` / `system32-openconsole` / `other` / `query-failed`，按完整 canonical 路径逐项匹配，不按 basename 推断；这些是路径类别，不证明签名、可信性或谁创建了进程。报告还有独立 wait 状态与固定错误类别；query-failed 不等于已终止，只有 held handle 返回 signaled 才报告当次 signaled，且此时不再查询映像。

快照明确 `atomic_snapshot=false`：列表查询、逐个 Open/查询和两端 accounting 有时间间隔，可能遇到退出中对象。报告 assigned/listed、两端 active/total/terminated、counts_consistent、query_ms、snapshot_ms。只有完整列表、两端 active 与 listed 一致、total 不变、每个成员身份/图像查询/两次 timeout/关闭均明确成功才标 complete；计数一致不证明这段时间完全没有成员变化。creation 与列表开始时间的检查也仅提供保守的时间约束，不能从失败推断 PID 已退出。

### 已有 v2 真实失败证据

root 后续实际执行 v2 后保存 `tmp/p6-r7-review/native-job-limit-probe-01.json`，本 worker 已只读验证 SHA-256 为 `5D1403229214733792800DF71ACB4CC45230445C33846EDC2978FF49FDEC47B9`。其 stage=7，flags=8200/limit=1，first pre-resume identity 与 ready alive 均 true，before active=2/total=2/terminated=0；second_created 与 second_create_error 均 null，尚未尝试 second。after active=0，child/all handles closed=true，cleanup_pending=false。它证明第二次创建之前已拒绝并清理，**不是 second-limit 通过，也不能据此归因为 CLI 创建了其他进程或限额已经失效**。v3 用于进一步定位实际 own-Job 成员。

### v3 实际验证与边界

- 最终 source / test：Node **12/12**；managed selftest **29 个策略用例（27 负例）+ 16 个 parser 用例**。Node 另以独立编码的字节向量检验 **23 个 parser 输入**，检验 **22 个成员快照证据组合**与 **7 个精确路径类目输入**；旧 **36 个 second / 12 个 cleanup / 8 个 exit** 组合保留。
- Framework64 C# compiler `/platform:x64 /target:exe` 对冻结 candidate-03 编译 exit **0**；冻结 v3.exe 的 `--selftest` / `--plan` 实际 exit 均 **0**，报告 `native_executed=false`。冻结后 source/test/snapshot/exe 未再修改。
- **本 worker 未运行 v3 actual apply**，未在本增量执行 Job、sentinel、事件或 attempt 目录创建。上述是编译与纯策略证据，不能当成 native 限额、真实 CLI/账户/网络、生产或真人 Gate 通过。actual 由 root 对相同冻结候选单独执行和记录。

精确验证命令（当前仓库根）：

```powershell
node --test tools/dev_agent_bridge/windows_text_gate_job_limit_probe.test.mjs
& .\tmp\p6-r7-helper\windows_text_gate_job_limit_probe.v3.exe --selftest
$LASTEXITCODE
& .\tmp\p6-r7-helper\windows_text_gate_job_limit_probe.v3.exe --plan
$LASTEXITCODE
```

已执行的冻结编译命令如下；输出已经存在，不要用该命令覆盖现有 v3：

```powershell
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /platform:x64 /target:exe /out:D:\memex\tmp\p6-r7-helper\windows_text_gate_job_limit_probe.v3.exe D:\memex\tmp\p6-r7-review\native-job-limit-probe-candidate-03.cs
```

| v3 产物 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_job_limit_probe.cs` | `9AACCEEA4284491D34E225EF1E0516D9AD597F59754FB50AA9F2348B9E48384A` |
| `tools/dev_agent_bridge/windows_text_gate_job_limit_probe.test.mjs` | `A3F895ED7B746A496EED897C3BDC9471B51BD58D8D4D7254580D53E310A5F519` |
| `tmp/p6-r7-review/native-job-limit-probe-candidate-03.cs` | `9AACCEEA4284491D34E225EF1E0516D9AD597F59754FB50AA9F2348B9E48384A` |
| `tmp/p6-r7-helper/windows_text_gate_job_limit_probe.v3.exe` | `F70CECC78D17FE55FF609E08D03A02F35DD0B6F520318181ABD3DDF387286FF4` |

## v2 冻结时交接（历史）

## 范围与候选

这是独立、无网络的 own-Medium sentinel 实验候选，不引用固定 CLI、账户、UAC、WFP 或旧 AppContainer ABI。默认、`--plan`、`--selftest` 不调用 native 探针逻辑，不创建 Job、sentinel、事件、目录或系统配置。只有显式 `--apply-job-limit-synthetic` 才创建本次私有目录与自身映像副本；`--sentinel` 是该副本的内部子进程入口。

冻结源：`tmp/p6-r7-review/native-job-limit-probe-candidate-02.cs`；x64 EXE：`tmp/p6-r7-helper/windows_text_gate_job_limit_probe.v2.exe`。没有覆盖 candidate-01 / v1.exe。本 worker 仅改探针源、同名测试、本 handoff，并新增上述两份冻结产物；未写全局状态、Git 索引或其他 helper。

## 已修边界

- x64-only：BasicLimit / ExtendedLimit / Accounting 分别 64 / 144 / 48 bytes，校验关键 offsets；class 9 真实读回的 flags 和 active limit 进入报告，必须为 `0x2008` / `1`。Job 与事件的 `ERROR_ALREADY_EXISTS` 在修改/使用前拒绝，不重配置已存在 Job。
- 输出仅限 `D:\memex\tmp\p6-r7-job-limit\<UUID>`。源文件及输出祖先在创建前以 no-delete-share 句柄固定，拒绝 reparse，核验 handle metadata 与 canonical final path；源和副本拒绝多个硬链接。新 root / attempt / EXE 原子创建时设置 protected own-user-only FullControl ACL，再由 held handle 读回 owner、DACL、继承及规则。已有 parent 不改 ACL；已有 base root 必须原本满足私有 ACL，否则 fail closed，不修旧目录。目录与映像句柄保留到最终清理。
- first 以 `PROC_THREAD_ATTRIBUTE_JOB_LIST` 原子创建 suspended；caller 在 native create 前持有结果对象，后续读取 creation time 抛错不会丢失 process/thread handles。命令行是可写 `StringBuilder`，无 handle inheritance，使用 `CREATE_NO_WINDOW` 与 SystemRoot/SystemDrive/TEMP/TMP 最小 Unicode 环境。
- 预 Resume 与运行中核验同一 held process 的返回 PID、`GetProcessId`、非零且不变 creation time、Job membership、canonical image、pinned image hash、normal Medium / non-elevated / non-AppContainer token。ready + first marker + exact handle wait-timeout 证明实际进入且仍活动。二次创建前后均检查 first 仍活动。
- 仅有一次 atomic second-create。只有 `created=false` 且真实 Win32 error 为 `1816`，同时独立 second 入口 marker 未触发，才可记为限额拒绝。其他错误 unknown；任何创建成功都失败，second 永远不 Resume。during accounting 仅作为观测值，不单凭 total/active 计数推断 second 是否执行。
- first 经 release 正常退出后，在 held process 上读真实 exit code，必须为 `0`；退出后不再查 image。失败清理可终止仍活动的本次进程，但不能因此补造 normal exit。关闭 child process/thread、token、事件、目录/文件、Job 均核验 CloseHandle 返回值。最终 accounting 在同一 held Job 上、child 清理后读取；未知计数是 `null`。只有真实 close 全通过且最终 active=0，才清除 `cleanup_pending`；总体 pass/exit 0 在 finally 清理之后由纯策略统一计算。
- 报告 `p6_r7_job_limit_probe_v2` 仅含固定字符串与数值/布尔/null，不输出异常文本、账户 SID、任意路径或凭据；从不读取或复制 credentials。`failure_stage` 只表示失败所在阶段：1 token/ABI，2 path/attempt，3 image copy，4 events，5 Job，6 first create/binding，7 first ready/accounting，8 second attempt，9 first release/exit；0 表示主操作已完成，仍须核对最终 cleanup。

## 本次实际验证

- Node **9/9** 通过；测试真实 Add-Type 编译、检查 `Main(--selftest)` 返回 0、default/plan 返回 0、非法参数返回 2，不吞 selftest 返回值。
- managed selftest **26 个策略用例，其中 24 个负例**，包含 ABI 校验；另外 Node 运行纯策略 **36 个 second-create 组合、12 个 cleanup 组合、8 个 normal-exit 组合**，验证 strict JSON schema、未知 null、关闭失败不能保留 passed，以及原生 API 静态边界。
- 冻结源经 Framework64 C# compiler `/platform:x64 /target:exe` 编译成功，编译 exit **0**。冻结 v2.exe 的 `--selftest` exit **0**、`--plan` exit **0**；二者报告 `native_executed=false`。
- v2 冻结时 worker **未运行 `--apply-job-limit-synthetic`**；后续 root 已实际运行，失败诊断见上方 v2 JSON。本段编译/纯测试结果不证明 native 限额有效，不构成真实 CLI、账户、网络、生产或真人 Gate。

| 产物 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_job_limit_probe.cs` | `2949FBF60E8202C345CF9AC97EA2FDA00C5913E220745194A408AAB88B0AB5B7` |
| `tools/dev_agent_bridge/windows_text_gate_job_limit_probe.test.mjs` | `6F9CE18B274ECAE2AFD71663ED90302287F184872F99766DEFDF6B920C786608` |
| `tmp/p6-r7-review/native-job-limit-probe-candidate-02.cs` | `2949FBF60E8202C345CF9AC97EA2FDA00C5913E220745194A408AAB88B0AB5B7` |
| `tmp/p6-r7-helper/windows_text_gate_job_limit_probe.v2.exe` | `E89A5FD1E4D5B94C4888528A833932E5E947EEB6B27712E7FF376AD4F094827F` |
