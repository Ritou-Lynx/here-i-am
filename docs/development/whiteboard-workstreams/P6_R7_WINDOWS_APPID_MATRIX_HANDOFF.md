# P6 R7 AppId 本机网络矩阵：纯合同候选 v1

## 冻结范围与结论（2026-09-12）

这是独立、可编译、纯逻辑验证的合同层，**不是可运行 native matrix**。Main 仅支持默认/`--plan`/`--self-test`，其它参数全部拒绝；没有实际 apply、install、cleanup 或 probe dispatch。报告始终 runtime_implemented=false、matrix_passed=false、network_enforcement_tested=false、single_process_enforcement_tested=false、production_isolation_passed=false、human_gate_passed=false，真实请求/模型turn计数均0。

worker只写 matrix.cs、matrix.test.mjs、本handoff及新的本地编译/快照工件。未读取凭据、未创建外部目录、未运行UAC/WFP/Job/CLI/子进程探针/socket/接口枚举/进程枚举，未改Git index或冻结的coordinator v15b/core。测试执行的是合同exe的纯路径，不是矩阵probe。此包不处理2718或任何历史pending，也不覆盖主控后续清理状态。

| 冻结工件 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_helper.cs` | `F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774` |
| exact `tmp/p6-r7-review/native-appid-matrix-contract-01.cs` | `F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_helper.test.mjs` | `1E2703B2F0FCA9CC72D478829E894DBE8F6D4F40CEB00DAC891961D1F4E1299F` |
| `tmp/p6-r7-helper/windows_text_gate_appid_matrix_helper.contract-v1.exe` | `4AA074827374DB78B728E1210850783AE89FE4B1A996CFB964DB1840F44FC3E8` |

编译使用 Framework64 csc、x64、/warnaserror+、显式 `/main:HereIAm.R7.MatrixProgram`，exit0。Node **11/11 pass、0 skipped**；冻结exe self-test **302 assertions、exit0**；plan exit0、明确not_implemented。Node在测试前后校验所有依赖hash、当前coordinator源/测试未变、外部matrix根存在状态未变。

## 依赖与独立资源域

联合编译复用三个冻结文件，**不使用正在演进的当前coordinator源码**：

| 只读依赖 | SHA-256 |
|---|---|
| `tools/dev_agent_bridge/windows_text_gate_isolation_helper.cs`（v10） | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_startup_helper.cs`（v11c） | `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA` |
| `tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs` | `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311` |

未来目录固定 `D:\HereIAm-P6-R7-AppId-Matrix\<attempt UUID N>`，镜像只能派生为 `matrix-probe.exe`；本包不会创建它。镜像与coordinator须来自同一个冻结exe，期望hash在自复制前后验证，不接受journal自报hash作为权威。Job前缀独立 `Local\HereIAm.P6R7.AppIdMatrixV1.`。

Scope 为 `SHA256("HereIAm.P6R7.AppIdMatrixV1/" + attempt UUID N)` 的前16字节GUID，再将该scope传给冻结CoordinatorBoundary.MakeRules。三条rule的层/action/weight/port计划由正确v15实现产生；真实attempt与scope同时绑定到新记录，不能拿normal attempt直接调用。测试验证scope稳定、不同attempt分离、与同attempt普通coordinator所有规则key不同。新journal/receipt schema分别为p6_r7_appid_matrix_owned_v1与p6_r7_appid_matrix_receipt_v1；与旧coordinator不兼容。

这里只调用纯MakeRules及InspectionNative/CoordinatorJobNative布局断言，没有实例化CoordinatorBoundary、调用Add/Get或WFP事务。未来adapter可复用v15正确Filter200 Add/Get、INDEXED64精确检查、assigned_sublayer_weight读回/绑定及事务代码；旧Native.Filter192、旧AppIdBoundary/NetworkBoundary均不得接入。

## 纯接口与证据合同

`MatrixContract.TargetAllowed(role,target,port,inventory,brokerPort)` 只做内存中的IP值校验，不解析域名、不查接口或路由、不连接。固定8个负例角色为loopback4/loopback6/local4/local6分别TCP与UDP。loopback只能精确127.0.0.1或::1；loopback4 TCP负例不能使用允许的broker端口。nonloopback目标必须与传入的最多64个本机单播地址之一精确匹配，IPv6 ScopeId也匹配；拒绝未知角色/地址族/端口、any/multicast/IPv4mapped IPv6、无scope的IPv6 link-local等。合成测试仅用文档地址和内存fixture。

**inventory是否真实来自本机接口、是否当前仍归本机、listener是否绑定到同一精确tuple，本包没有原生证据。** 未来host必须从NetworkInterface当前可用单播地址构造inventory，并持有listener；不能把调用者任意传入IP数组当作本机事实。缺少任一v4/v6非loopback可用fixture必须incomplete，不访问公网或未知目标，不更改网络配置。

`MatrixContract.Outcome` 要求每一行fixtureavailable/localaddressverified/hostpositive/hostdrain，以及child attempt/operationcomplete/listenerdrain全部成立；只有该操作同步返回WSAEACCES **10013**，并且listener accepted-connections/datagrams/bytes均0才为blocked。timeout/refused/其它错误/缺fixture/缺证据均incomplete，成功连接或发送及任一接收不为blocked，未知/重复角色和非法计数无效。UDP send成功但没收到也不算deny。实际固定marker、host阳性连接/发送与accept/receive、清空、child负例与最后清空、每行唯一tuple的生命周期绑定均**尚未实现**。这些bool/counter对象只供纯fixture验证，不能视为原生观测。

`MatrixContract.Summarize` 只输出固定角色/状态、bool，不输出IP/路径/原始错误/任意字段。evidence_contract_satisfied只是输入合同满足，不是matrix_passed。broker自身固定marker往返、wrongpeer拒绝、读取payload前的GetExtendedTcpTable完整tuple+精确PID/creation/image/token准入仍未实现；必须分别取得ownedpeer阳性和hostwrongpeer阴性，不能用listener silence替代。

`MatrixRecords` 提供最大16KiB、递归上限5、canonical JSON、固定keys/type的own-record合同，拒绝重复键、额外键、旧schema、缺字段与非canonical表示。journal绑定attempt/scope/nonce、固定image与ownerhash、ownerPIDcreation/token digest/brokerport/phase/childPIDcreation/token digest，不接受任意路径。prepared/spawning只允许空child；bound/closed必须完整child binding且token digest与owner一致。token digest的原生取得、严格Medium/Limited/非AppContainer及实际same identity验证都尚未实现；hash字符串不是令牌证明。

receipt逐字段绑定原journal、action、真实应持有的helperPIDcreation/同exehash、AppId blob digest与实际assigned UInt16 weight；install/cleanup缺weight或null拒绝，cleanup须closed，install/rollback须prepared。install_rollback可null weight仅表达安装前未赋值情形，不能抵消额外closure/absence证据。这里没有写/读取实际journal或receipt，**不等于原生ownership、安装或cleanup完成**。未来原生helper须自己从UUID推导路径、验证当前owner/Job/child与实际文件handle/hash，而非仅接受合法JSON。

`MatrixInstallFacts.Accepted` 要求ownerlive、held Job query Active0/Total0、安装前absence、事务内/提交后exactreadback、已实际关闭helper exit0、精确receipt。`MatrixRollbackFacts.Clean` 要求prepared/nochild、ownerlive/heldJob/Active0/Total0、原helper已实际关闭、exact-owned或全空、postabsence、rollbackreceipt。未知helperclose、spawning、missingJob、部分规则或receipt缺失不能称clean。`MatrixClosure` 须预Resume绑定、postprobe pin、同heldchild signaled+精确binding、JobActive0、stdioEOF/brokerdrain、cleanuphelper实际exit/receipt/exactdelete/postabsence全部成立。它不查已退出image、不把helperexit当probeexit、不从PID缺失构造close证明。

## 未实现的原生层与停止点

下一包才能实现普通Medium coordinator、只复制自身pin probe、canonical/no-reparse/private新目录、命名Job+原子JOB_LIST+3handle allowlist、suspended预Resume image/hash/token/creation/Job绑定，以及真实stdio协议。UAC helper应只安装/清理本scope，不拥有probe；install receipt需helperactualclose及exactreadback，失败rollback仍需ownerlive/Job0Total0。正常清理必须持续持owner/Job/实际childclose证据，未知保留deny/pending；不实现缺Job的泛化恢复。

本机host正控、8行fixture实际采集、broker admission、child 10013、listener排空、probeclose/Jobzero/stdio/brokerdrain和exact规则删除postabsence都未接线。单进程限额的行为验收是另一个独立问题；网络合同不能补出single-process通过。v15私有Apply/Elevated/receipt生命周期硬编码旧CLI/root/schema，不能直接作为matrix launcher使用；本包避免复制整份包含历史回收入口的coordinator。

当前在纯合同冻结处停止，不继续native实施。主控须先处理既有规则清理与Job诊断，再独立审查后续native包；本exe没有可供UAC实跑的apply入口。

## 本地复核

```powershell
node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_helper.test.mjs
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_matrix_helper.contract-v1.exe' --self-test
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_appid_matrix_helper.contract-v1.exe' --plan
```

以上均为本地纯路径，不产生网络或WFP证据。
