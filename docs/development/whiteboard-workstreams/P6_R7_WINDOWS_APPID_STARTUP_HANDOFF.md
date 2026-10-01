# P6 R7 AppId 无认证启动候选 v11c

主控 2026-09-12 实测结果：v11c 在 DuplicateTokenEx 返回 1346；源 impersonation level=1，primary 未创建，0 CLI/WFP/model、正常清理。见[实际报告](../../../tmp/p6-r7-review/native-appid-startup-03-primary-conversion.json)，SHA `434B7076413268E566175A3F36E22AC3FCC53572FBF5F2DB833BB37ED52AE539`。本路线保留为失败/诊断证据，后续进入独立普通权限 coordinator 候选，不继续重复提权转换或覆盖冻结产物。以下冻结实现与本地检查不等于实际启动通过。

## v11c 当前冻结（2026-09-12）

主控实际 v11b attempt `ef8b434d-ad16-4069-9ca1-20726d3a49ee` 仍在 linked_token_selection 拒绝、exit 3，未创建 child/WFP。固定诊断显示唯一策略差异为 source Type 2；IL=8192、Limited=3、elevated=0、non-AppContainer、AuthId 非零、同 user/session 均符合。父 token Type 1、IL=12288、Full=2、elevated=1。

[官方 DuplicateTokenEx Remarks](https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-duplicatetokenex) 明确支持将 impersonation token 复制为 TokenPrimary，保留其安全上下文。v11c 因此分开源校验和最终 primary 校验：源仅 Type 1/2，其他 Medium/Limited/未提升/non-AppContainer/Auth 非零、父 Full/同 user/session 条件保留；DuplicateTokenEx 参数仍 `desired=1|2|8, level=2, type=1`。复制后必须严格 IsMedium/Type 1，并通过专用比较逐项匹配源 User/Session/AuthId/IL/ElevationType/Elevated/AppContainer。原 Same 方法仍包含 Type；postspawn、peer 和 journal 仍只允许严格 primary。没有把源 Type 2 直接交给 CreateProcessAsUser，也没有替代 API 或权限回退。

保留源 `linked_token_diagnostic`；另加 `linked_duplicate_diagnostic`，固定 schema `p6_r7_linked_duplicate_diagnostic_v1`、diagnostic_only=true、duplicate 固定属性与 primary_identity_matches_source 布尔；尚未完整查询为 null。属性补充 impersonation_level：Type 2 时只记录 TOKEN_STATISTICS 的 0..3 枚举，Type 1 为 null，不加入跨类型 Same/duplicate 安全上下文比较或接受策略。未知原生枚举/查询失败仍关闭，实际 DuplicateTokenEx 失败保留 Win32 数字。身份原值仍不进入报告。

| v11c 冻结文件 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.test.mjs` | `91A1579202DF71262329BD8EB06C6628F5075929FF73E4B70E62035C40433AED` |
| `tmp/p6-r7-helper/windows_text_gate_appid_startup_helper.v11c.exe` | `6FBF8F94778C107EB37E40AA301206ED24B475DB4F5FC8AC117EE64BE0EE1DFF` |
| `tmp/p6-r7-helper/appid-v11c-tests.tap` | `B88342A454B2FEF9CB3652856E0E9CA3A182CE2182A0CA42E31301A45F99C41E` |

实际联合编译、固定 exe plan/self-test 均 exit 0；专项 **18/18 pass、0 skipped**，自测 **74 断言（原 59 + 15）**。新断言覆盖 1→1/2→1 合法、未知 source type、复制后八个身份属性逐项变化拒绝、诊断 schema/null/源 Type 保留、Win32 错误保留。旧 v11/v11b exe 与原 v10 两源均保持原哈希。证据另有 `appid-v11c-plan.json`、`appid-v11c-self-test.json`；没有 apply/UAC、CLI、账户或网络测试。

当前源码/测试/exe 已冻结。主控调度应采用 **`.v11c.exe`**；历史各节中的 source hash、通过结果与命令版本不得当作当前候选。以下历史设计中源 token 必须 primary 的旧约束由本节明确替代，其余环境/ACL/WFP/Job/恢复/通过门槛不变；production/human Gate 仍 false。

## v11b 历史冻结（2026-09-12）

主控在首次 UAC 取消后，已实际运行 v11：`tmp/p6-r7-review/native-appid-startup-01.json`，SHA-256 `0995043ED8C6067631D24207558F7EAAED8421B2D2D3344117698FAA0EFAEA9D`，attempt `fe1ee7ca-d4df-436e-a201-11d36223eb0a`。helper exit 3，stage=linked_token_selection、error_code=linked_token_rejected；未创建 child/WFP，cleanup_pending=false，0 HTTP/model。

v11b 只增加固定诊断，IsMedium、AcceptLinked、postspawn 匹配、环境、ACL、WFP、Job 与恢复策略均不变。`linked_token_diagnostic` 使用 schema `p6_r7_linked_token_diagnostic_v1`，diagnostic_only=true。parent/selected 固定对象仅含 type、integrity_rid、elevation_type、elevated、appcontainer 数字，以及 authentication_id_nonzero 布尔；顶层 same_user/same_session 仅布尔。未完整查询的对象/无法比较的项为 null。在校验前重建记录，异常后保留；不输出 SID/AuthId 值、Session ID/PID 或凭据，不序列化原身份对象，不将诊断当作通过。

| v11b 当前冻结文件 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `33680210A7C585B9DF1DB9255B41EB30261886DE2BDA87E79C653255EE1C2FB3` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.test.mjs` | `557696EF0418C5AA8392805CF81034ED41E3F0EB5D375CA14180A02271E63C94` |
| `tmp/p6-r7-helper/windows_text_gate_appid_startup_helper.v11b.exe` | `B6F6DE2550C63D35F971F909DF09FD8E1755BABEE745B0AF00005884273DE116` |
| `tmp/p6-r7-helper/appid-v11b-tests.tap` | `A6E0364D886F1B1CE29669880682B2EC8AC37C35740EE2630205D834E86E5D6C` |

实际联合编译 exit 0，固定 exe plan/self-test exit 0；专项 **18/18 pass（原 17 + 1），0 skipped**；自测 **59 断言（原 51 + 8）**。新增覆盖固定 schema/类型、未查询 null、身份脱敏、拒绝前保存和异常后保留、零 AuthId、诊断不代表通过；静态核对两条谓词保持 v11 原样。证据另有 `tmp/p6-r7-helper/appid-v11b-plan.json`、`appid-v11b-self-test.json`。

v11b worker 未运行 apply/UAC、CLI 或账户/模型请求。源码、测试、exe 已冻结；旧 v11 exe 与原 v10 两源保持原哈希。主控下一次调度使用下方命令但 exe 后缀改为 **`.v11b.exe`**，Start-Process 加 `-ErrorAction Stop`。下文 v11 冻结/首次 UAC 状态均为历史记录，顶部为当前态；历史结果不能继承为 v11b 实际通过。

## v11 历史设计与冻结

2026-09-11。独立候选，源码、测试与 exe 已冻结。worker 未执行 mutation；主控随后完成静态复核并发起一次 UAC，Windows 返回“操作已被用户取消”，**helper/attempt 未创建、未 apply、未运行真实 CLI、未请求账户或模型**。基线 v3-lab@bbb8025d，复用原 v10 公共原语但不修改其文件。此包只验证后续的 initialize/config-read/EOF 兼容性，不签发生产或停止回执。

## 为什么采用独立候选

主控已经实际运行 v10 AppContainer worker：`tmp/p6-r7-review/native-synthetic-05-canonicalize.json`，attempt `ceabf1bb-52b2-4723-816c-da62a05a906a`，SHA-256 `24951EFBEA92F0D6C702CECCCB0A0774145A1A46AE10DC968371E72A8F5CD26D`。directory open(access 0)、normalized NT、handle close 成功，normalized DOS 与 opened DOS 均 Win32 5；原文件、网络、Job 和清理矩阵通过。这个历史结果证明同模式 worker 的 API 行为，不是 v11 的网络或 CLI 证据。

因此 v11 是明确分开的 **Medium linked token + image-path AppId** 候选。它不创建 AppContainer，不修改旧模式，也不继承旧矩阵通过。AppId 识别可执行文件路径，不是实例或哈希；假设受信宿主、受信固定 CLI，无恶意同用户程序或管理员并行改写。本候选没有容器文件访问隔离。

## 实现边界

- 新主入口 `HereIAm.R7.AppIdProgram`，联合编译必须指定 `/main`。无参数或 `--plan` 只输出固定计划，不查询 linked token、不创建进程或网络规则。新 Main 不分派旧 apply/recover/worker 模式。
- 独立 Root：`D:\memex\tmp\p6-r7-appid-isolation`。唯一随机 UUID 子目录；WFP GUID 从 `HereIAm.P6R7.AppIdV11/<UUID N>/<tag>` 派生，不复用旧域。
- 输入唯一真实文件为 basename `codex.exe` 的绝对、无 reparse、精确哈希镜像。固定 pin：`3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004`（主控确认 0.153.4/runtime 7ac07f4ce733f89a）。只复制这个 exe，不复制认证、配置或用户数据。
- 新 attempt 根采用受保护 DACL：SYSTEM/Administrators FullControl，当前用户 RX；新 work 子树才给当前用户 Modify。建立 `work/empty-home`、`empty-workspace`、`Roaming`、`Temp`，继承受控权限并检查祖先无 reparse。只读 Windows 系统目录，复用十键合成环境；不枚举或复制完整用户环境，不调整任何已有祖先 DACL/完整性标签。
- helper 必须是 Full/elevated、primary、non-AppContainer。只读取自身 TokenLinkedToken，并核验 same user/session、primary、Medium IL 8192、Limited、elevation 0、non-AppContainer，复制为 primary 后再次比较。AuthenticationId 来自被选中的 linked token；不要求等于 elevated helper。没有 linked token、权限 1314、任一查询/验证失败都拒绝，不回退管理员、其他用户或 LogonUser。
- 唯一创建调用是 `CreateProcessAsUserW(selected token)`。原子 `PROC_THREAD_ATTRIBUTE_JOB_LIST` 将 suspended child 放入 active limit 1、kill-on-close、无 breakaway 的 Job；`HANDLE_LIST` 仅三个 stdio 句柄，Job/宿主控制句柄不继承。Resume 前验证实际 token 全字段、进程镜像与再次 pin，并持久化 PID+creation time。
- `FwpmGetAppIdFromFileName0` 取得本次复制镜像的完整 blob，再释放原生内存。一个独立子层，ALE_AUTH_CONNECT_V4 上精确 AppId+TCP+127.0.0.1+本次端口 permit，其余 V4 与全部 V6 deny。非 dynamic、非 persistent；错误/崩溃可保留过滤规则等待恢复，不修改普通 Codex 安装路径规则。
- broker 在读取客户端 payload 前同步检查完整 TCP tuple、PID、持有 process handle 的 creation time、镜像和所选 token 身份。宿主错误 peer 正控必须被拒绝。TCP 表检查是该时点的连接归属证据，不能声称是内核每字节认证，威胁模型不扩大为抵抗恶意同用户或受信 CLI 被攻陷。
- 固定共享 CLI 参数和 stdio 协议只执行 initialize、initialized、config/read；没有 thread/turn。任何被识别的本地 CLI HTTP 请求返回固定 403 并令本用例失败；没有 C# 文字门或真实 upstream。异步读取失败、EOF 未正常退出、非零/未证实退出码、清理失败均不能通过。
- 成功必须同时具备 config 严格匹配、reader 完整 EOF、stdin EOF 后自然退出、实际退出码 0、实际进程退出+Job zero、清理完成、无其他错误。强制终止仍执行实际清理，但不是用例通过。

## 报告和恢复

报告 schema：`p6_r7_cli_appid_startup_candidate_v1`。`appid_startup_passed` 独立；`appcontainer_isolation_passed`、`production_isolation_passed`、`human_gate_passed` 始终 false，`network_enforcement_tested=false`。没有继承 `synthetic_passed`。只输出固定阶段/错误码、计数/布尔与可选 Win32 数字；保留首个 failure，次要失败分列。stderr 仅使用原有固定词表分类，不输出 raw stderr，也不通过伪造旧 Root 获取共享摘录。

私有 ownership journal schema：**`p6_r7_owned_appid_startup_v1`**，固定 mode `apply_cli_appid_startup_synthetic`。20 个固定键，16 KiB 上限、严格 canonical JSON 与精确 schema，拒绝重复/未知字段、旧 AppContainer schema、任意路径/image/hash。journal 存储选中 token 的用户 SID/session/AuthId/安全属性和宿主/child 创建时间，仅用于同用户精确恢复；这些身份值不进入控制台报告或本 handoff。它们不是账户登录凭据。

`--recover-cli-appid-startup-synthetic <canonical UUID>` 只从新 Root/UUID 派生镜像和 own WFP keys；先校验 journal、同用户 elevated host、旧 owner 已关闭、固定镜像 pin，再读回完整 AppId blob、层、动作和条件。若 child 存在，核对 PID+creation+image+token 后才停止并等实际退出。已退出/精确 PID 不存在或复用可作为绑定进程关闭依据。单例/无 breakaway 契约支持其余进程不能存活的推论；恢复报告用 `process_closure_basis`/`singleton_closure_proven`，**不伪造失去 Job handle 后的实时 Job 查询结果**。

`creation_started=true` 但 child binding 缺失，或 owner/process/规则状态无法证明时，保持 fail-closed、`cleanup_pending=true`，不删除拒绝规则，不凭 journal 自称 Job zero。此处没有扫描/盲杀猜测 PID 的回退。正常入口只有实际退出与 Job zero 之后才删 own WFP；恢复只有上述可核验关闭依据之后才删 own WFP。永不触碰 profile/loopback exemption；不递归删除 attempt，磁盘镜像、合成目录、journal/report 均保留作证据。

全局修改范围仅本次三条 AppId filters 与一个子层；另有临时 Job/process 和本次新磁盘目录 ACL/文件。没有 kernel driver、SDK 安装、全局普通 Codex firewall、用户环境、账户配置、AppContainer profile 或 loopback 全表修改。WFP 非 persistent 规则不保证跨 BFE 重启/系统重启；这些故障仍待专门验收。

## 冻结与本地证据

| 文件（项目相对路径） | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `57649AB37365CAEC74A8AFB42E45CF8F590E070E13EFC173C52D726C596BBFD4` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.test.mjs` | `F12B99019F1D2E09BF905B95CD55410586EC43A205C5137E4E38DF39690C9AD6` |
| `tmp/p6-r7-helper/windows_text_gate_appid_startup_helper.v11.exe` | `852E2D34B9495DB23F2BB56AB9A91E6F52D53C382B2DF225F681B1B57142B7AF` |
| 原 v10 `tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs`（未改） | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| 原 v10 `.test.mjs`（未改） | `3B30A568278284378BB75FB7024F3ED175FE289583B32AAA76C4E4FDDE261D0F` |
| `tmp/p6-r7-helper/appid-v11-tests.tap` | `8B71E98386AD535347E153B1E6DB6880510BB989078EAD205FD8EEAFA9CDDF6C` |
| `tmp/p6-r7-helper/appid-v11-self-test.json` | `6EACDAE72108EEC6FE8A7D5E945F47C99FBE9F4ACFB439F507154686E6AF88F2` |
| `tmp/p6-r7-helper/appid-v11-plan.json` | `F7EBD548F67937151FDE05AB68AEAD91C8F4D72F7D4D8FE34D6F289FF9EB3FDE` |

Framework64 联合编译实际 exit 0。Node 专项 **17/17 pass，0 skip**；冻结 exe `--self-test` **51 断言通过**，`--plan`/`--self-test` 均 exit 0。自测只用 managed 合成身份/日志、原生结构布局、固定错误和策略检查，没有调用 token 选择、WFP、进程创建、CLI 或网络。测试前后强制比较旧两文件哈希，检查新 isolation Root 未新增目录。

| 验收项 | 当前证据 |
|---|---|
| linked 选择策略、postspawn 比较、无 elevated fallback；不同父 AuthId 可接受 | 合成断言通过；实际 OS linked token 尚未执行 |
| 精确/未知/旧 schema、重复 JSON、错误 pin、缺 binding 拒绝 | 合成断言通过；实际 crash recovery 尚未执行 |
| AppId GUID 域与 blob 比较、x64 ABI、只读入口 | 本地通过；AppId 规则安装/读回尚未执行 |
| initialize/config-read、自然 EOF exit 0、实际 Job zero | 待主控本候选实测 |
| 新 AppId 的 TCP/UDP 正负控、允许 peer、child spawn 拒绝 | 本候选未测试；不能继承 v10 AppContainer 矩阵 |
| 非 loopback、强崩、BFE 重启/系统重启 | 未测试 |
| 双向文字门/Node IPC/真实账户/模型/取消/恢复产品接线 | 本包不实施，生产与 human Gate 仍 false |

## 主控复核后运行

主控和独立审计已按上述 source/exe hash 完成启动范围静态复核，无未关闭 P1/P2。首次系统确认未完成，见[调度报告](../../../tmp/p6-r7-review/native-appid-launch-01.json)；不是原生 helper 退出结果。下次调度应给 `Start-Process` 加 `-ErrorAction Stop`，取得非空 Process 后才等待和读取退出码，不能把 PowerShell 非终止错误后的 exit 0 当作成功。

只读命令可直接执行；以下 mutation 命令仅供主控核验并自行执行，本 worker 未执行。源路径占位符必须替换为当前精确 pin 的绝对 codex.exe 路径，候选仍在运行时再次验证。

```powershell
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_startup_helper.v11.exe' --plan
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_startup_helper.v11.exe' --self-test
node --test tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.test.mjs

Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_startup_helper.v11.exe' -ArgumentList @('--apply-cli-appid-startup-synthetic','"<verified-absolute-codex.exe>"') -Verb RunAs -WindowStyle Hidden -Wait -PassThru

& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_startup_helper.v11.exe' --recovery-plan '<canonical-attempt-UUID>'
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_startup_helper.v11.exe' -ArgumentList @('--recover-cli-appid-startup-synthetic','<canonical-attempt-UUID>') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
```

源码复编需要 x64 Framework csc，`/reference:System.Web.Extensions.dll /main:HereIAm.R7.AppIdProgram`，同时输入原 v10 `.cs` 与新 AppId `.cs`。不要省略 `/main`、运行旧默认 Main，或覆盖已冻结 exe；后续修改另版本产物。旧原始报告和产物不变。

## 主要 API 依据

- [TokenLinkedToken](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_linked_token)、[TokenElevationType](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ne-winnt-token_elevation_type)、[TokenStatistics](https://learn.microsoft.com/en-us/windows/win32/api/winnt/ns-winnt-token_statistics)：OS linked handle、Full/Limited、认证 LUID 的来源。
- [CreateProcessAsUserW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessasuserw)：primary token QUERY/DUPLICATE/ASSIGN_PRIMARY，调用者权限要求。可能需 SeIncreaseQuota/SeAssignPrimaryToken；本实现不主动调权，1314 不回退。
- [UpdateProcThreadAttribute](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)：Job list 与可继承 handle allowlist，值内存持续到删除属性表。
- [FwpmGetAppIdFromFileName0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmgetappidfromfilename0)：路径转 AppId blob，用 FwpmFreeMemory0 释放。
- [Filtering condition identifiers](https://learn.microsoft.com/en-us/windows/win32/fwp/filtering-condition-identifiers-) 与 [官方 SDK 头文件](https://github.com/microsoft/win32metadata/blob/main/generation/WinSDK/RecompiledIdlHeaders/um/fwpmu.h#L1752)：ALE_APP_ID 为完整应用路径的 BYTE_BLOB，GUID `d78e1e87-8644-4ea5-9437-d809ecefc971`。
