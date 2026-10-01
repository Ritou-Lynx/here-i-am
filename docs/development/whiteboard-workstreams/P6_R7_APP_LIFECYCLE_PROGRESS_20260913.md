# P6 R7 启动诊断与零模型复验

后续更新：用户已明确确认较长公开数字任务；真实运行中取消暴露App关闭等待过短，修复已验证并生成新候选，实际复验仍待。当前入口为[运行中取消与关闭等待修复](P6_R7_APP_RUNNING_ACCEPTANCE_20260913.md)，下文“尚未得到回答”等均是前一阶段历史状态。

2026-09-13，承接“继续”。本轮开始与候选基线 `v3-lab@1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`，空索引；新隔离工作树 `.worktrees/p6-r7-app-lifecycle`，旧 `.worktrees/p6-r7-app-entry` 和原 App bundle 保持。收尾期间主线并行合入MDA源码及收据，当前为 `68307c9ea837f11dc82e148e8f51feff89b50fb6`；已复核P6四项集成指纹不变，保留全部并行改动。此前 [App 部分验收](P6_R7_APP_ACCEPTANCE_20260912.md) 的真实完成、完成态重启证据不扩大为运行中 Gate。

## 结果与当前待办

启动前身份和有限错误阶段现在可被记录。主控组合 **58/58** 通过，4项源/测试审阅后集成到主目录。修正本轮外层启动器的标准输入接线后，最终真实零模型预检 **Node0/native0、六项回收 true/pending false**，独立观察器在 native ready 之前记录并核对了 PID、创建时间、映像和父子关系。

本轮没有启动 App 或发模型任务，也没有重建 App。运行中取消/后台/退出等验收尚未完成，生产保持 `available=false/fail_closed=true`，P6/Goal1/真人 Gate 未通过。昨晚 d0 启动失败的具体原因仍未补证，不能用本次输入通道问题替代它。

用户待决定：原固定公开任务约两秒完成，当前启动命令结束前取消按钮禁用，且动态内容会移动按钮。已提出仅对隔离候选改用公开任务：**“只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。”** 尚未得到回答；未修改现有固定 goal、未执行较长任务，不能把默认选中或等待时长当批准。

## 最小改动

- native transport 只增加本地 spawn PID 与有限 transport fault 诊断；native error 复用封闭 stage/family，导出两个纯 sanitizer 给 host 再次校验。无任意异常正文、账户字段、命令行或路径输出，未改变 native pin、超时、启动或关闭协议。
- host 在创建 owner 之前保留 `requested_attempt_id` / `requested_broker_port`，即便 ready 失败也可定位；`attempt_id` / `native_startup` 仍仅来自校验后的 ready。
- host 的 `native_spawn_pid` 不自行证明父子或创建时间。`native_reported_close_receipt` 与已验证的六项关闭事实分开，失败凭据不覆盖 `nativeClose`；snapshot 升为 `p6_r7_app_candidate_host_evidence_v2`，准入与挑战协议不变。
- 外层启动器在等待 ready 之前每200ms检查一次**变化后的**有限快照，避免预检失败丢失记录；独立 PowerShell 观察器读取已知 PID，核对映像、启动命令、创建时间及 native parent，保存有限事实，不读取凭据或其他任务内容。

[4项集成和原始指纹](../../../tmp/p6-r7-review/app-lifecycle-launch-01/integration.json)。host source SHA `B95CDFB9F12499BD2AC11E3330F61F2441193770C3A335F1F7F4F9B5CA615920`；transport source SHA `10DF08D03B823F3AA596894ED461E2E37B15F6C2AF74B0C05C07E76987C6572E`。旧 source/关闭边界均保留，不改变生产能力。

验证覆盖 host15、transport17、adapter21、shutdown5，共58项；包括 ready 前失败、非法/私密诊断丢弃、不可变副本、诊断读取不结算 pending write 或改变 close 顺序。主控复核 transport diff，独立审阅 host 无未关闭 P1/P2。本地测试是假 native/provider 加本地 socket，实际预检另列如下。

## 首次零模型尝试：启动器输入提前关闭

`app-lifecycle-launch-01` / attempt `4c7722c1-06e9-42a1-833c-3645c88c0956`。Node PID18892，native held PID28648，broker26693；首个 owner ready 前事件2已是 shutdown_requested，随后捕获 `task_boundary_blob_rejected`、native4。无模型或上游尝试，broker已排空。

冻结 v7 的 `boundary_blob` 阶段还包括安装前的 `input.Poll()==null && !input.Eof` 检查。外层输入 EOF 引发 host shutdown，transport.close 会在 ready 前发送 close 帧，足以使此检查拒绝；不能把阶段名称解释为已经证明 AppId blob 算法失败，更不能归因为 broker 连接计算。

同一执行壳的纯 Node 对照实际收到普通管道 EOF；交互终端对照 `stdin_is_tty=true` 且保持打开。新版启动器在创建 host **之前**要求交互终端，非交互负例 exit1、没有生成 events/admission；信号和 stdin_end 另记原因。[输入保护验证](../../../tmp/p6-r7-review/app-lifecycle-launch-02/stdin-guard-verification.json)。事件2本身未记录原因，单凭该事件不能区分 EOF、信号或其他关闭入口；以上解释结合了接线、源码与同壳对照。

本次 prepared/final 的 owner identity 与 requested binding 匹配，final 为 started=false、operation_failure。该错误位于 installAttempted 之前，未进入规则助手或 CLI 创建；原生 Rules/Helpers=true 来自“未尝试安装”分支，不是实际 WFP 查询。Process/Stdio=false，严格关闭仍失败，native4/pending true 原样保留。

prepared SHA `7BA7FBAF513173840AFEC60C1AED9EC580CC2DCBF02FD0698DA5A1ADCE307759`；final SHA `54F5A1AFA76BC2E82F41EB6DF07D3E4CF611138F4AB81EDAD6B246432C8DE2AE`。这与昨晚 d0 的 installAttempted 已进入且 Rules/Helpers=false 不同，不能拼接两次失败。

核对 PID/创建时间/映像/端口、原生已退出和 broker 排空后，仅定向停用 Node18892/26692；[停用记录](../../../tmp/p6-r7-review/app-lifecycle-launch-01/host-retired-startup-failure.json)。零恢复/删除，不改写原失败。

## 最终零模型预检通过

最终冻结[18项源闭包](../../../tmp/p6-r7-review/app-lifecycle-launch-02/closure.json) SHA `C38F208F35C5599D3F9CA18E2C7CE54870A1BB8AA47053D401A36C06D26BA999`；[构建/启动输入](../../../tmp/p6-r7-review/app-lifecycle-launch-02/preflight-build.json)分别固定 launcher、observer、Node 与 native。native仍为v7 SHA `73CBE6277FD4BF5B92BDC3189E00EEE5CE78F208D6037D8D16A14DF9BDE4BC4E`，未改规则/权限/账户定义。

| 绑定 | 实际值 |
| --- | --- |
| host launch | `07b42876-836e-42ef-b04f-109e060f396e` |
| requested/native attempt | `58ab8eef-b846-444c-ae02-ecb3af2e66c4` |
| Node PID / 创建时间 | `19744` / `2026-09-13T00:28:49.7171189+08:00` |
| native owner PID / 创建FILETIME | `33872` / `134337041299303168` |
| broker port | `20368` |
| local session | `2f7c068a-f8b0-422d-ba3d-deca6fdb80ae` |
| execution epoch | `68b63977-6cd5-4c71-b5e9-81bb52ee0ff7` |
| provider thread | `01a09673-6d5d-72c1-a0bf-15276cf46735` |

[独立身份观察](../../../tmp/p6-r7-review/app-lifecycle-launch-02/native-identities.jsonl)在 native ready 之前完成，Node/native映像、创建时间和parent相符；这才补上新实例的独立身份观察，不回填旧实例未知父子链。

[最终关闭](../../../tmp/p6-r7-review/app-lifecycle-launch-02/closed.json)与[真实退出采集](../../../tmp/p6-r7-review/app-lifecycle-launch-02/actual-exit.json)证明 Node0/native0、process/Job/stdio/rules/handles/helper六项 true、pending false、broker drained。停止回执为 `closed_without_turn`，local/provider turn均null，upstream0、arm0、未释放响应；不把创建provider thread当发出模型任务。

事件9为shutdown_completed，宿主自动关闭。本轮保留现役47831/47841的原PID28396/32704及创建时间；未提交推送、安装手机、改真实数据库/队列或切换现役服务。

## 后续

若用户批准上述较长公开任务，则创建下一份明确冻结的 App/host 候选，记录新goal、source与bundle指纹，再顺序补运行中页面/后台、取消匹配终态、退出回收及未完成任务重启。若保留原短句，则继续当前输入下的启动诊断，不用人为延时或改题目伪造运行中 Gate。
