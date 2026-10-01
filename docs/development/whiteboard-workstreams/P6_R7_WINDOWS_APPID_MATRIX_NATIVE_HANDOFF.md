# P6 R7 AppId matrix native adapters v2

2026-09-12；工作树 `v3-lab`，读取 HEAD `bbb8025d99fc0acaa846d58b4e5a94cef90f8756`。本包只新增独立源码、专项测试及本文，不修改既有合同、v10/v11c/v15/v16、Job 探针或共享状态/索引。

**冻结的是未接线的原生适配层，不是可实跑矩阵。** 独立 `HereIAm.R7.MatrixNativeProgram.Main` 只接受默认、`--plan` 和 `--self-test`；其他参数一律固定拒绝并返回实际 exit 2，包括未来 probe/helper/apply 入口。报告固定 `runtime_status=adapters_only_not_wired`、`runtime_implemented=false`、`native_executed=false`，所有 matrix/network/single-process/production/human gate 均为 false。不得用反射调用 internal 适配器来绕过未接线入口。

## 已实现、未实际运行的层

- `MatrixHandleLedger` 对已接管句柄做精确关闭；仅成功关闭才移除。关闭返回 false 或抛错均保留所有权并成为粘滞失败，可在后续显式 close 调用重试；重试成功不能清除首次失败。`Empty` 绝不等于正常完整关闭，必须同时保留 `AllCloseCallsSucceeded`。`MatrixPinnedAttempt.CloseVerified`、`MatrixOwnedPipes.CloseVerified` 每次都执行 CloseAll；已 disposed 的 `MatrixOwnedProbe.Dispose` 仅重试 CloseAll，不重新 Stop/Query 已关闭句柄。mock 覆盖 false/throw 后成功重试、保留所有权、粘滞失败和不重复关闭成功句柄。
- `MatrixPinnedAttempt` 只读校验合同路径、held file/directory final path、无 reparse、文件单链接与内容 hash，并绑定普通 Medium owner 的 PID/creation/token 摘要。它接受未来 host 准备的记录；**尚未证明目录 ACL 来源，也不创建 fresh root/UUID、不设置 ACL、不读写 journal**。因此不能作为实际创建/授权边界完成的证据。
- `MatrixOwnedPipes` 持有三组管道，只有精确三个 child endpoint 可继承；父端禁止继承。尚无 stdio pump、协议或 EOF 证明。
- `MatrixOwnedProbe` 包含 own Job collision 拒绝、ActiveLimit1/class9 读回与初始 accounting；使用 DETACHED `0x8040c`、atomic JOB_LIST、精确 HANDLE_LIST、可写命令缓冲及最小环境。创建结果先交给 caller-owned 结构与 ledger，再查询 creation/identity；pre-resume 校验 held PID/creation/token/image/hash/member。退出后不重新查询 image；held process/Job 查询未知保留未知，只在规则删除证明之后释放。`Dispose` 的 best effort 不是 WFP 删除、EOF、socket drain 或最终成功证明。
- `MatrixRuleAdapter` 复用冻结 v15 的 `CoordinatorBoundary` 与合同 Scope/Image/Rules，沿用正确 Filter200、INDEXED64 与实际 assigned weight；不调用旧 CLI 私有生命周期或旧 Filter192 实现。构造器完成 boundary 构造后若 blob digest 校验抛错，会尝试 Dispose boundary 并原样重抛原异常。helper 的 owner/Job 验证仍是待接线 callback；旧 boundary Dispose 不提供已检查的 engine close 证明，必须由未来 actual helper exit/receipt 补齐。
- owned-peer 适配入口复用 `AppIdLauncher.Peer(accepted, Binding, owner, image)` 的本机 tuple/held PID 证明；尚无 broker accept、marker 交换或 wrong-peer 运行。

构造失败时会尝试释放已接管资源并保留原异常；若释放本身失败，构造器不能把对象返回给 caller，当前层没有实现这种路径的恢复容器，不能宣称正常关闭。此限制与缺少实际 cleanup 状态机一起维持 runtime 拒绝，不能将异常捕获解释为回收成功。

## 纯状态门与仍缺少的运行层

纯 policy 为 `Prepared → Installed → Spawning → Bound → Observed → Closed → Removed → Released`；允许 `Bound → Closed` 清理观测失败。它只验证输入证据组合，不产生真实证据，也不替代任意阶段异常处理。

`Closed` 需要 exact child identity exit、held Job query Active0、stdio EOF、socket drain、post pin；`Removed` 需要 helper actual close、receipt、规则删除及 postabsence；最终还需 native handles 真实关闭。缺少任何一项不能 complete，未知不能当零。

下一层必须另行实施/审计后才可能接线：

1. own fresh root/UUID、所有祖先 canonical/no-reparse、来源可验证的 owner ACL、held path pin、唯一授权 owner，以及严格 journal/receipt 原子读写。
2. 普通 Medium coordinator、独立 own probe、只管理 own rules 的 UAC helper 三角色入口；实际 owner/held Job 证明、helper lease/actual exit/receipt/postabsence 和任意阶段故障回收。
3. 有界 stdio pumps/协议与 EOF；held broker socket 的 owner tuple、marker round-trip、wrong-peer 拒绝与排空。
4. 八个本机 TCP/UDP × v4/v6 × loopback/nonloopback fixture：运行时 fresh unicast/scope 选择与绑定正控；每阶段唯一 host marker、精确接收核验和阶段排空；负测需精确 10013 与对应 listener drain，超时/地址不可用/无观测不能判拒绝成功。IPv6 或本地地址不可用应 incomplete，仍执行已拥有资源的完整回收。
5. 统一 cleanup 状态机：部分安装/部分创建/peer 失败/fixture 不可用均保持 pending，直到同一 owned attempt 的规则 postabsence、helper actual exit、held Job Active0、stdio/socket drain 和句柄关闭证据齐全。不得用当前适配器 Dispose 或纯 policy 填写成功事实。

## 冻结与验证

冻结 02/v2 取代之前未交付的 adapters-01/adapters-v1；旧快照/exe 保留且不覆盖。v2 仅修正关闭失败 retain/retry 与 wrapper 的 close-only 重试，并保留构造失败资源释放。JSON schema 仍为同一 adapters v1 schema，表示兼容报告格式，不表示运行层已实现。

源码 `tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.cs` 和快照 `tmp/p6-r7-review/native-appid-matrix-native-adapters-02.cs` 同 SHA-256：

`C0C3DA4DFA7D3939860D8C966213BC8C31A55F40FB108FD8C51FEF74EBB0BB35`

测试 `tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.test.mjs`：

`90F2823C0B96C271AB937AFBBF78597F68768DF977CA022ECCB5D995A6482FFE`

冻结 exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_native.adapters-v2.exe`：

`40BCD22DAA4EECFD12CF5E9151643E791F92EB8B29F4C48CD32AC76ADBFD4D9C`

联合编译依赖（只读，不继承它们的 Main 或历史验收）：

| 依赖 | SHA-256 |
| --- | --- |
| `tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs` | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs` | `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311` |
| `tmp/p6-r7-review/native-appid-matrix-contract-01.cs` | `F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774` |

在仓库根目录验证：

```powershell
node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_native.test.mjs
& .\tmp\p6-r7-helper\windows_text_gate_appid_matrix_native.adapters-v2.exe --self-test
& .\tmp\p6-r7-helper\windows_text_gate_appid_matrix_native.adapters-v2.exe --plan
```

实测 Node **9/9**、0 skip，实际 exit 0。Node 在 own fresh tmp 目录联合编译后只调用 Main 的纯入口和公开纯 policy；独立检查 64 阶段组合与 18 缺失证据字段。托管 self-test **166 assertions**（含 128 阶段/null 组合及 14 个注入 closer 的 ledger 检查），实际 exit 0。固定计划报告实际 exit 0。未知参数的实际 exit 2 在 Node 中验证；未调用任何 actual 参数。

冻结编译命令（已执行成功 exit 0；不要覆盖冻结产物，重编译必须换新 `/out:`）：

```powershell
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /platform:x64 /target:exe /warnaserror+ /reference:System.Web.Extensions.dll /main:HereIAm.R7.MatrixNativeProgram /out:D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_matrix_native.adapters-v2.exe D:\memex\tools\dev_agent_bridge\windows_text_gate_isolation_helper.cs D:\memex\tools\dev_agent_bridge\windows_text_gate_appid_startup_helper.cs D:\memex\tmp\p6-r7-review\native-appid-coordinator-candidate-15.cs D:\memex\tmp\p6-r7-review\native-appid-matrix-contract-01.cs D:\memex\tmp\p6-r7-review\native-appid-matrix-native-adapters-02.cs
```

本包 worker 没有执行 native adapter、Job/process probe、socket、UAC、WFP、CLI 或网络尝试，没有读取凭据或修改网络配置。编译器和纯验证程序的运行不等于上述实际链路。没有继承前包 detached Job sentinel、真实 CLI、网络或生产验收。主控仅复核本适配层；本轮停止于冻结交接。
