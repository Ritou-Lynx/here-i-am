# P6 R7：旧 v4 attempt 固定只读检查器

日期：2026-09-12。此工作包只新增检查器、纯测试与本 handoff；未执行实际 WFP / UAC / CLI / Job / 网络检查，未修改原目录、报告、ACL 或凭据。

## 冻结候选

- `tools/dev_agent_bridge/windows_text_gate_task_retired_inspect.cs` SHA-256：`500257BE9B46267ED51783CB752B43DFD9295E48A14DEC02160C7884FCAD05E6`
- `tools/dev_agent_bridge/windows_text_gate_task_retired_inspect.test.mjs` SHA-256：`3FC3ED53B74EB92D53F76AA043056D01AC75AA8D8DB9240DED4ADCE1DEDF7D4E`
- 独占实际入口：`--inspect-retired-fixed-elevated-readonly`，严格单参数；不接受任意 attempt、root、filter、源文件或输出路径。默认、`--plan`、`--self-test` 不检查实际资源。
- 实际入口只输出一份 NDJSON；不会写报告文件。由主控选择新输出文件，冻结输入/产物并运行验收。

## 精确历史绑定

| 字段 | 固定值 |
|---|---|
| attempt | `9ad201c0-1e9b-4851-873d-0364f52efa53` |
| scope | `da9e8e50-2175-a81c-b7ff-52e2a77773b6` |
| 原 owner PID / creation FILETIME | `29032` / `134336685056566773` |
| broker port | `36836` |
| prepared SHA | `800C3922BDA6F7A8701FDBFF1C2E44D10FACE7636F034C470FA56EB83C91062C` |
| 原报告 SHA | `0768A3BC5CDA07568C418347C39D1AC4416D141FC84BC384D0B75842EB60F238` |
| 原 v4 exe SHA | `FBE5882461130A93988F7468290C86EDEBA0E33CFEAB8AD3322F1A7A44867F5F` |
| 原 v4 source SHA | `930B436DD011DF2F9299107C063D2A7C7D706A00E974C4BAD7E016D0B3A10CB5` |
| copied CLI SHA | `3D6CA7085C932B62EF4EE4877E92F15B050FB94B2EB8E6C10A346A06248C6004` |

prepared 位于固定 Task 根目录的该 attempt 下，主控提供其实际 metadata/hash；worker 没有绕过之前的 ACL 拒绝。实际检查器在提权后读取并验证该精确文件，不读 dedicated home。Task-owned v2 的 15 个字段、原失败报告的精确字段、嵌套 broker 和 close receipt 都严格检查；原 nonce/token digest 只验证，不输出。

## 实际读范围与退出语义

1. 仅接受同 protected 目录 owner 的 High / Full / primary / non-AppContainer token；不把当前高权限 token 冒充历史 Medium token。
2. 持有所有证据路径祖先、原 prepared/report/exe/source/copied CLI，严格 canonical / non-reparse / hash，前后复核。根与 attempt 及 `work`、`project0` ACL 保持精确三个 principal；attempt 顶层只接受 `prepared.json`、`codex.exe`、`work`、`project0`。不递归读工作目录内容。
3. 前后核查原 owner PID + creation + wait；PID 复用须 creation 不同才能排除原 owner。两次有界 Toolhelp 快照，每次最多 8192 项，只打开原 v4 exe 名和 `codex.exe` 名对应进程，核对精确完整映像路径与 held process identity。拒绝访问、未知等待状态或未完整枚举均不当作缺席。
4. `FwpmTransactionBegin0(engine,1)` 只读事务，精确读取三个 filter 与一个 sublayer。filter 仅 `0x80320003 + null`、sublayer 仅 `0x80320007 + null` 视为不存在；错误码、非空指针不匹配均拒绝。没有规则枚举、删除、添加、提交或策略设置调用。
5. 只读事务 Abort、engine close、全部 owned handle close 均须成功。失败对象 retained 后有限重试，但首次关闭失败保持失败，不因重试成功升级结论。

精确键：allow4 `5b2c4ed6-03e9-484f-263c-2b5b8ba2b518`；deny4 `491941d9-fa2f-354f-49e7-802660809c7a`；deny6 `728f8811-9d31-642d-604b-f9d0e6be5ee9`；sublayer `c5f670a3-d2fc-3ee6-a660-3f18b9a260ff`。

仅完整满足上述断言，退出码才为 0，`inspection_complete` 与 `current_rules_absent_verified` 为 true。规则存在或任何检查未确认均退出 2；只输出有限阶段号/API 数字状态，不输出原始异常消息、路径或凭据。

**历史与当前不可混用：** `cleanup_pending` 始终 true；原 `historical_cleanup_pending=true`、Job-empty/handles-closed true、process/stdio/helper/stop-receipt false 仅在原证据 pin/schema 通过后分别投影。当前规则缺席不能修复原失败回执。主控验收应检查新报告的 `inspection_complete/current_rules_absent_verified/resources_closed`、实际 inspector exit 0 和输入前后指纹，不能把本报告交给要求完整 native stop receipt 的解析器。

**Job 限制：** 没有 OpenJob / QueryJob 调用。`job_current_inspection=not_performed_original_session_unavailable`，当前 Job absence/empty 均 null。原 prepared 没有 session 字段，不能用当前 `Local\\` namespace 查询代替。

该检查只能关闭“此固定 attempt 当前是否仍有规则遗留”的疑问；不证明历史 helper 实际退出、原 stdio EOF、完整任务停止、未来持续缺席、App 接线、production/human Gate。没有新增 P1 源码阻塞；上述 session 与历史回执限制必须保留。

## 编译与纯测试

已运行 `node --test tools/dev_agent_bridge/windows_text_gate_task_retired_inspect.test.mjs`：**2/2 通过，self-test 1028 项，managed harness 217 项**。覆盖精确字段/错误字段/重复字段、错误 caller、意外顶层文件名、四键 API 错误/指针组合、owner PID 复用与未知状态、关闭错误/异常/保留重试，以及 current success 永不清除历史 pending。

测试创建自身随机临时目录，先验证所有依赖/历史证据 SHA，使用 x64 C# `/warnaserror+` 编译，运行 plan/self-test/合成 harness/无效参数；清理前核对临时目录确实位于任务测试父目录，前后复核输入。没有运行实际检查入口。

供主控编译（先核对上述 source/hash；输出路径不存在才执行）：

```powershell
$retiredOutput = 'D:\memex\tmp\p6-r7-helper\windows_text_gate_task_retired_inspect.v1.exe'
if (Test-Path -LiteralPath $retiredOutput) { throw 'Choose a fresh frozen output path.' }
$retiredSources = @(
  'tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs',
  'tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs',
  'tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs',
  'tmp/p6-r7-review/native-appid-matrix-contract-01.cs',
  'tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.cs',
  'tools/dev_agent_bridge/windows_text_gate_task_retired_inspect.cs'
)
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /platform:x64 /warnaserror+ /target:exe /reference:System.Web.Extensions.dll /main:HereIAm.R7.TaskRetiredInspectProgram "/out:$retiredOutput" @retiredSources
```

依赖精确 SHA（与 `.test.mjs` 相同，联合编译前必须匹配）：

- isolation：`D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8`
- startup：`C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA`
- coordinator15：`C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311`
- contract01：`F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774`
- native adapter：`F2D3B35A1E6D1763930BA7F9A82AB8DBB595E02D5D720216A0161DBCE8A0D0AB`

实际提权触发、产物/报告冻结与验收由主控完成；本 worker 不执行。

## 主控实际检查 01 与独立产物复核

主控随后执行了本候选的固定只读提权检查。worker 只读取冻结产物、运行脚本、报告与 capture，没有再次调用 WFP / UAC / CLI / Job / 网络，也没有重新读取 protected prepared 或 dedicated home。

| 产物 | SHA-256 |
|---|---|
| `tmp/p6-r7-review/native-task-retired-inspect-01.cs` | `500257BE9B46267ED51783CB752B43DFD9295E48A14DEC02160C7884FCAD05E6` |
| `tmp/p6-r7-helper/windows_text_gate_task_retired_inspect.v1.exe` | `2DB3AED9F1F3A9B83A356637B3325D2F18E54C23972835285A42F6F2E26805AC` |
| `tmp/p6-r7-review/run-task-retired-readonly-01.ps1` | `CCB3F46E11978DED717981DEBA3990D26996FE2414FB144E6F1F41659D6FFFB7` |
| `tmp/p6-r7-review/native-task-retired-inspect-actual-01.json` | `2D061EF1AE5436B9873D356A661D699D6F60ABCF70B736359B552643AEC92BCA` |
| `tmp/p6-r7-review/native-task-retired-inspect-capture-01.json` | `6854E2B48F1CB9D5A5EE14F109081F0805FC1E4333B770BCCC5E3C8AE99E9764` |

独立产物断言 **63/63 通过**，包含以上 5 项与原 v4 source/exe/report 共 **8 项当前 SHA**。这是已完成实际操作的证据复核，不是又一次原生测试。

- runner 固定 exe/hash 和唯一只读参数，输出文件使用 CreateNew，执行前后验证 exe pin；capture 绑定 native actual exit **0**、同 attempt、输出 SHA、`parsed_expected_report=true`、`candidate_post_pin=true`。报告是保留下来的单行 stdout 文本，外层 capture 不替代内部断言。
- 实际报告的 attempt/scope、prepared/原报告/owner/CLI hash 与冻结契约一致；三个精确 filter `present=false`，精确 sublayer `present=false`，`filters_checked_count=3`、`filters_present_count=0`。
- `inspection_complete/current_rules_absent_verified/current_owner_inactive_verified/current_images_inactive_verified/files_and_acl_verified/transaction_ended/resources_closed` 全为 true。对应实现要求规则查询前后的进程及证据检查均通过，首次资源关闭没有失败；`failure_stage=0`、`api_status=null`。
- `cleanup_performed=false`，filter/sublayer 删除数、上游请求与模型 turn 数均 **0**。
- 原报告 SHA 保持不变。新报告仍保留 `cleanup_pending=true`、`historical_cleanup_pending=true`；历史 Job-empty/handles-closed 为 true，process/stdio/helper/stop receipt 为 false。Job 当前检查仍为 `not_performed_original_session_unavailable`，当前 absent/empty 均 null。

**可收口结论：** 在本次实际只读检查窗口，该旧 v4 attempt 的三个 filter 和一个 sublayer 均不存在，原 owner 身份及两个指定完整映像路径无活进程，检查器自身资源确认关闭。因此“当前是否仍有该 attempt 规则遗留”的疑问已得到否定证据。没有把原失败回执改成成功，没有补造当前 Job 或历史 helper/stdio 的证明，production/human Gate 仍为 false。
