# P6 R7 Matrix fixed inspection handoff

## 当前结果与待执行 v2

用户确认能处理系统弹窗后，主控已实跑冻结 v2 固定只读 runner；held process 51408 实际 exit0。新报告 `tmp/p6-r7-review/native-appid-matrix-inspect-actual-02.json` SHA `FDC639D81401EBA9ED691358735CC46488746E5E3A2A045F50F06417E76E718C`：三 filter 及一 sublayer 均 absent，前后文件/ACL、当前目标进程不活跃、事务结束及资源关闭全部成立，inspection_complete=true、cleanup_pending=false。独立只读审计无 P1/P2。这只解除固定162de实例的规则未知状态，不回填原 helper actual exit、child close、Job-zero或矩阵通过。下列“未执行/等待”均为该次 actual 之前的准备快照。

2026-09-12。主控冻结并实际执行 v1 普通 Medium 检查，exit2、failure_stage5、api_status5：只读事务被 Windows 拒绝访问。报告 `tmp/p6-r7-review/native-appid-matrix-inspect-actual-01.json` SHA `B07550E752021052918E1A44C19F8D80BE9378B89B832508ABA579804C6CCABE`；exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_inspect.v1.exe` SHA `4A8A1E9B4853DF8BF61580E255364EC2C003CD6568158467C37B89ED1FB9351B`。historical_no_child_verified/resources_closed=true；尚未读取四个规则对象，后验未完成，不能把其它 false 解释为进程仍活动或 ACL 错误。规则状态未知，`cleanup_pending=true`，没有修改规则或覆盖原 actual02。

v2 新增显式 `--inspect-never-started-fixed-elevated-readonly`，仅允许同一受保护 root/attempt 目录 owner 的 High/Full/primary/NonAC 调用者；不伪称符合原 Medium token digest，不使用 linked-token 转换。普通动词仍要求原 digest。两种模式只读同一固定实例三条规则及一分层；没有 Add/Delete/Set/Commit、启动或终止进程。新报告用 `caller_check` 区分实际身份依据，不签发 child close、Job-zero、生产或真人 Gate。

- 当前 source 与 `tmp/p6-r7-review/native-appid-matrix-inspect-02.cs` SHA `CE02F71085C13D0DDDB36B311FF029D3170F825B83AE3DA16CC66D2FA1F3D5D5`；test SHA `AEB62A22960EA824C09649ED16A07260FF1D7D11FA3C2BBD206587A0849B17AC`。
- 冻结 exe `tmp/p6-r7-helper/windows_text_gate_appid_matrix_inspect.v2.exe` SHA `02F202A52987B8CBE55AC7E8B78948A0DC4A77F40A6142E05EFC714DBCFC8F8D`。主控 Node5/5、self1027、纯检查101及SDK compile-only6通过；独立复核无未关闭 P1/P2。
- 固定启动脚本 `tmp/p6-r7-review/run-matrix-fixed-readonly-inspection-02.ps1` SHA `8BB214C161976B768E96D76E44FBB327AF4327B5A4F7B57C83D3B4AB9A174A3F`，语法检查零错误。无参数，核查祖先/no-reparse、exe hash及输出缺席，只执行上述固定只读动词；限长校验结果后 CreateNew 写 `tmp/p6-r7-review/native-appid-matrix-inspect-actual-02.json`，保存实际退出码并复核 exe hash。
- v2 和脚本均未实际执行，也没有当前等待中的系统确认窗口。下一步需用户能处理 Windows 管理员确认后，由主控对这一固定脚本显式 RunAs（隐藏窗口）并核实实际退出与新报告；不是重新要求项目授权。原实例 pending 未解除前，不运行新版矩阵或真实账户请求。

## 历史 v1 准备与边界

2026-09-12；仅固定 `162de9b7-046f-45dc-b15e-a6ced3d785e2` 的只读恢复检查准备。源码/test 已停止编辑；主控负责冻结组合 exe 与普通 Medium actual。worker 未执行实际入口、engine open、socket、UAC、启动或终止操作。

- Source `tools/dev_agent_bridge/windows_text_gate_appid_matrix_inspect.cs` SHA `61A4ABC47D04D0C23F823CFD90EA0E8906F1326C9E3C135775AF81F01F3A8BCE`。
- Test `tools/dev_agent_bridge/windows_text_gate_appid_matrix_inspect.test.mjs` SHA `2E084B489E445276D14B814516F86E3361F894716EEB793764257DB8EF3523F3`。
- 已执行 `node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_inspect.test.mjs`，实际 exit 0：Node 5/5、0 skip；self-test 1027、纯 History/closure 90；SDK compile-only 6 static_assert。只运行 plan/self-test/纯 harness/带额外参数的拒绝动词，未运行单独实际动词。
- 编译：Framework64 csc，`/platform:x64 /warnaserror+ /reference:System.Web.Extensions.dll /main:HereIAm.R7.MatrixInspectProgram`；联合 v10 isolation、v11c startup、`tmp/p6-r7-review/native-appid-coordinator-candidate-15.cs`、`native-appid-matrix-contract-01.cs`、current native adapter。五个依赖 pin 与 events01 测试一致，由测试逐项核验；不依赖 runtime/events/socket 源。
- 默认/`--plan` 不读私有目录，保持原 pending 未证明解除。唯一实际动词 `--inspect-never-started-fixed` 无参数、无自动 RunAs；只接受与历史 token digest 相同的 normal Medium。BFE 拒绝会保留 pending 并输出固定阶段与数值 API status，不扩展权限。
- 准入：held read-lock prepared SHA `74FE88F74597E31EBD2AF6DCA727AE8AB458A5363977B514A48023B790BD803D`；actual02 SHA `767E40D8646CB432BA10C555C6884BA13364A9636C34455E6C1616FC1435E031`；原 v2 exe 与 copy image SHA `EB039CB1778F0B56E322CA97FEEEEA6D7675EFECC7A8A9DE3B4EB377E0F3462A`。所有祖先/finalpath/no-reparse、root/attempt 同 owner 的受保护三项 ACL、目录仅 prepared+image，前后复验。
- 原 owner held PID+creation+wait 防 PID reuse；两次有限 Toolhelp 快照只针对原 exe 与 matrix-probe basename 打开 held process、验证完整路径与存活。不输出 PID、路径、nonce、token 或原始异常；只保证检查时点，不承诺对抗恶意同权/admin 或未来进程。
- BFE：`MatrixContract.Scope(Attempt)` 派生精确 3 filter keys+sublayer；READONLY transaction、仅四次 Get，全部 known-not-found 且前后文件/进程证据与真实资源关闭完整才 `cleanup_pending=false`。存在、未知、权限不足或关闭失败均 pending；没有 Add/Delete/Set/Commit，不重写原报告。
- 关闭失败保留所有权、最多两轮 close-only 重试；首次失败粘滞 false，不用 Dispose 或重试成功提升验收。新 `exact_child_closed` / `job_active0` 永远 null；原报告的历史 Job0 不升级为当前实证。helper 启动错误未知，不臆称 1223，不宣称原 helper actual exit 已确认。
- 诊断阶段：1 布局/token/readpins；2 历史/ACL；3 进程；4 engine；5 readonly txn；6 四对象；7 后验/txn abort；8 资源关闭；99 顶层拒绝；完整成功为 0。api_status 为可获得的原生数值，否则 null。进程/Job 关闭、新网络负测、生产与真人 Gate 均不由此检查器宣称通过。
- 依据：[只读事务权限与 flag](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmtransactionbegin0)、[按 key 读取 filter](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmfiltergetbykey0)、[PROCESSENTRY32W](https://learn.microsoft.com/en-us/windows/win32/api/tlhelp32/ns-tlhelp32-processentry32w)。SDK 10.0.26100.0 用 cl /c 核实 x64 size568/offset8,16,44 和 flags2/1；无 native ABI 程序执行。
