# P6 普通入口：9月16日接续

P6 / Goal1仍未完成。本页接续[9月15日现场](P6_R7_PRODUCT_ACCEPTANCE_20260915.md)，保留不同实例的独立结果，不把普通短聊或预检当作任务执行通过。

最新2026-09-18收尾：[11最终现场](../../../tmp/p6-r7-review/task-batch-authorization-11/ACTUAL_ACCEPTANCE.md)确认原文显示修复生效：9月17日23:35前真实窗口1/2/3、999/1000/1001、1998/1999/2000各独占行，精确2000行自动回聊天一份，completed后正常关窗恢复同一结果且不自动执行/重复投递。两代窗口与全部执行/授权持有者正常实际0，完整清理，56事件Witness链独审通过；16/16呈现、产品UI6/6、分析/独审、构建及新封包测试分别通过。09中断提示/恢复完整回流、10running取消、11逐行显示与完成恢复完成本轮有界验收；P6其余故障矩阵、主线集成/发布未因此完成，retry无真实failed资格，不伪造正向验收。文档写入中断后的记录已补齐，未重复启动App或任务。

最新2026-09-17 23:13：[09实际结果](../../../tmp/p6-r7-review/task-batch-authorization-09/ACTUAL_ACCEPTANCE.md)通过中断等待提示、明确resume后完整2000行自动回聊天与去重；[10实际结果](../../../tmp/p6-r7-review/task-batch-authorization-10/ACTUAL_ACCEPTANCE.md)通过running cancel、真实provider interrupted及后继不自动执行，两个批次均正常完整收尾。09数据库原文正确，但真实窗口把数字换行合并为空格；已修复任务消息原文分支和空正文附件回退，16/16测试与定向分析、独审通过，待[11新构建和真实窗口验收](../../../tmp/p6-r7-review/task-batch-authorization-11/ACCEPTANCE_SEQUENCE.md)。09/10冻结输入与独立回执已归档；不同候选的后台、界面、provider及清理结果分别保留。

最新2026-09-17 22:36：任务→聊天精确绑定、完整原文、稳定身份去重及关闭等待已修复，12项专项/71项合并回归和定向分析、独审通过。新Windows构建实际0，09/10两份独立验收包各406pins及scope2/2、真实bootstrap验证通过；两包均未消费，等待用户确认可处理系统弹窗后先09恢复/结果可见，再10运行中取消。此次尚无新App/UAC/任务，未启用生产或commit/push。见[09验证](../../../tmp/p6-r7-review/task-batch-authorization-09/PRELIVE_VERIFICATION.md)。下方21:51“开始修复”已由本条更新，但08实际后台完成不能替代新UI验收。

当前2026-09-17 21:51：[batch08实际结果](../../../tmp/p6-r7-review/task-batch-authorization-08/ACTUAL_ACCEPTANCE.md)已跑通普通UI enqueue/status/start、running正常关窗、单后继blocked/interrupted等待、明确resume及新执行completed（2000精确行/8892bytes）；所有相关原持柄进程正常0、完整清理。405pins归档，普通两代终态与43事件Witness链独审通过。当前产品缺口是TaskRoom状态/完整结果未自动回聊天；开始有界publisher修复，不能将后台完成代填前台交付通过。cancel/retry等余项、最新候选可见性与P6整体仍未关闭。下方早期记录为历史。

当前23:11：批次现场问题已修正，包括scope与App/Node/Witness绑定、控制台helper的额外Job计数，以及今日47831未启用普通runtime入口。05/owned48完成预检和bind_origin，但普通enqueue被未启用网关拒绝、任务0，失败现场已精确收尾。47831按既有授权重启且现有ChatGPT认证/能力通过；新增UAC前只读能力检查、专项22/22与独审通过。06/owned50/51的405pins及Dart2/2通过，但首次系统授权未获ready，owner实际2/root实际4，没有App、任务或native attempt；原cleanup_pending=true保留。尚未完成任务执行/暂停、正常关闭和后继验收，未自动再触发弹窗。详见[本轮真实证据](P6_R7_BATCH_AUTHORIZATION_20260916.md)。下方21:32为历史。

当前21:32：用户授权“那就先修改”后，批次授权候选已实现、构建并封存：同一限时批次只发起一次 runas，安装 / 清理复用受限 broker，任务保持 medium，失证拒绝。隔离分支基线3da91ebc，新的 owned40/41 与404 pins、真实 bootstrap 只读验证均通过；Dart114、关闭38、原Node106及新增闭包回归47均通过。没有新开验收窗口、触发UAC或写入队列，真实一弹窗闭环与P6/Goal1仍待验。详见[批次授权修改与交付](P6_R7_BATCH_AUTHORIZATION_20260916.md)；下方09:25为修改前诊断。

## 09:25人工授权流程审计与改进建议

- 实际冻结源码 `tmp/p6-r7-review/native-source-rebind-01/native-task-executor-rebound-01.cs` SHA `448ab285ba89570f925602c56066a298dcce272b57e0c6697994a9e9519af492`，exe SHA `674f159148f47c9702a360bfb4d32fd7b37604cd453a3104a3db08dd83fd02fc` 均复核。第348行每次helper通过 `runas` 提权；390行单独install，405行单独cleanup/rollback，376行明确要求helper已提权。普通owner/CLI保持medium。主目录源码hash不同，不混为同一冻结文件。
- 38启动脚本第51行设置30分钟总期限，包含人工等待。多次预检、安装、清理和再启动因此扩大人工在场需求；这是当前验收设计限制，不能将用户错过弹窗归咎为操作不配合。
- 建议改成一次明确验收批次的限时授权，由专用受限helper存续管理该批次的固定隔离规则与清理；只接受固定候选、身份和操作，普通任务保持低权，保留逐任务原话授权、真实回执、撤销和范围扩大时再确认。常驻系统服务并非默认选择，本轮没有安装服务或改系统设置。
- 必须重新设计并验证helper失联/死亡、owner死亡、授权过期时的关闭顺序，确保子进程停止先于隔离规则解除。动态WFP会话的自动删除机制本身不能证明这一顺序，不能直接替换当前保护后宣称安全。
- 这是源码诊断及改进建议，未实现一次授权无人值守能力、未运行新验收。下一阶段应先解决授权生命周期与清理可靠性，再安排用户在场的最小验证窗口。
- 依据：[Microsoft最小权限与runas说明](https://learn.microsoft.com/en-us/windows/win32/secbp/running-with-administrator-privileges)、[WFP访问控制](https://learn.microsoft.com/en-us/windows/win32/fwp/access-control)、[WFP对象生命周期](https://learn.microsoft.com/en-us/windows/win32/fwp/object-management)。

## 09:10状态复核：38已过期且任务为零

- 主控`0325fa`只读最终事件：仅预检owner0，native9548实际0、六项关闭true/pendingfalse，无task/turn；普通guardian无session、session_start_attempted=false、turn_ids为空、closed=true。预检完整关闭不等于App正常关闭。
- [只读DB投影](../../../tmp/p6-r7-review/app-lifecycle-owned-38/db-status-expired-01.json) UTC `2026-09-16T01:09:50.071Z`，observer `6c0837` actual0，SHA `bf56e98ec681c73456989609f0ec5045c7c00799b7146b0531607c9ca1f8d602`；主控`121805`读回同dataset/package/bootstrap且tasks[]。未遗漏新入队结果。
- 原exec39890已不可查询（`Unknown process id`），`witness-actual-exit.json`缺席（`c07878`）；不据此推断原Witness退出码、App/Node死亡或恢复资格。
- 独立只读CIM `299031` actual0、UTC01:10:15，原App48884/Node47720/Witness35920当前快照均未见；只是当前缺席，不补写原持柄退出码，也不对缺席进程执行清理。
- 本轮仅核实状态与记录，无队列写入、进程清理、候选重启或新模型请求。后续须先确认电脑操作途径并按精确身份收尾旧实例，再准备新独立验收；不复用38已消费bootstrap。

## owned38实际启动及预检

- 主控复核v11最小绑定差异（`d61298`），399/399固定文件校验、双PowerShell Parser与Node语法均通过（`14d5d7`）。数据集 `915a748c-f99a-4d73-abda-89c3d1505b93`，38/39 package SHA `4aac44bddbd82fe612071aef2d1cb70f082fc6d2fb41ef597df20c14fc8e205b`，bootstrap SHA `0e1893f5ff8a372f00d088b426263aa6557bb891fa8c478f76bba7beed70e645`；冻结产品源码与二进制未改。
- 实际启动 `3cfcdb`，原exec39890；prestart UTC `2026-09-15T17:44:42.0143362Z`，候选App/Witness/native/Node数量0且查询成功，服务身份与新产物缺席校验通过。前台新窗口ID13369676，普通输入尚空。
- seq11 `preflight_verified` 于17:45:09.062Z、ready=true；唯一owner0 attempt `d98fcaf9-7aff-4a6d-8458-bb297b72460a`，native9548、broker56096、Node47720。主控`c3d7ec`确认native_exit_code=0、cleanup_pending=false；独立只读`bddbbd`补核六项关闭全true、closed_without_turn、upstream/arm=0、drained=true。仅预检，不是任务执行或暂停通过。
- 用户复制就绪后，主控原生工具读到空编辑框；右键与两次前台激活均返回 `user input was detected in this window; call get_window_state before continuing`，每次先重新观察，无粘贴、发送或额外任务动作。已请求用户暂交鼠标键盘；不因输入争用绕开原生工具或改变验收入口。

## 01:36重新触发：78f6实际只读检查完成

- 主控核launcher固定SHA后正常审批启动（`9926f3`、原exec88670），用户处理本次Windows确认；`ad0754`实际exit0。collector39092，creation `2026-09-16T01:36:36.8116539+08:00`，持有process实际exit0，capture pin未改。
- [实际报告](../../../tmp/p6-r7-review/app-lifecycle-owned-36/78f6-rule-inspect/app-native-rules-actual-01.json) SHA `47d2ab37840ded0d5097a555583066edaf74c5ac4e8c0728a00819c3b8881022`；主控`4bb246`读回：[capture](../../../tmp/p6-r7-review/app-lifecycle-owned-36/78f6-rule-inspect/app-native-rules-actual-01-capture.json) inspector实际0，窗口17:36:37.224—17:36:43.891Z。
- 三filter及唯一sublayer均present=false，inspection_complete/current_rules_absent/current_owner_inactive/current_images_inactive/files_and_acl/transaction_ended/resources_closed全true；删除filter/sublayer=0、model/upstream=0。只是本次四项规则当前缺席；历史native4/cleanup_pendingtrue、未确认原stop/EOF/helper证明保持，非正常关闭或恢复通过。
- 原36失败任务保留，后续只准备38/39新独立dataset与未消费bootstrap；固定产品源码/二进制未改。不因用户错过确认放宽执行边界或延长旧轮期限。
- [实际独审](../../../tmp/p6-r7-review/app-lifecycle-owned-36/78f6-rule-inspect/ACTUAL-INDEPENDENT-REVIEW-01.md) SHA `dc32eee6ad8aec2232ab5424ba1713d141c02ac497efa814b05459c9bfe580d8`，主控`82b7e2`读回：三回执、固定keys、原历史绑定一致，无新增P1/P2；未在审计中再次运行检查器。
- 用户已再次回复固定enqueue文字“已复制”，不再等待文字准备。主目录现为`v3-lab@add2c1e6e06a8606fa6e6d58061f7540ca2fa958`；与先前6ea772f1仅A3文档/I_PROJECT_STATE变化（`8171cd`），不改P6候选字节，保留并行改动。

## owned36启动失败及精确收尾

- 16:48:13.384Z seq97：runtime native60452退出码字段4，`task_helper_shell_execute_win32_1223 / native_startup_timeout`；没有startup/profile/turn，六项整体关闭证明未知、cleanup_pending=true、upstream/arm均0。当前无法仅凭该错误判断用户是否看到或点击弹窗，已询问实际观察。
- [启动失败DB](../../../tmp/p6-r7-review/app-lifecycle-owned-36/db-after-start-failure-01.json)，`240a55` actual0、SHA `78547a4dfa3a1a12a7c918bb63c4082d33c6b0e286875b3dd3f0215fa9845563`：同一任务failed/retry0/actions=[start]，epoch `cc25e505-9988-4ccf-8007-4d760d91ef71`、phasefailed/seq0、session/turnnull/空结果；context SHA `1d9ea025aaabdd4c9430f374d3e573c18e341e6ed02365d8d7f04e0c159dc3a2`。未出现running或pause，模型遵守条件失败后停止。
- 主控正常UI AltF4后seq99 `shutdown_unconfirmed / input_shutdown`，guardian closedtrue、零pending（`5dc908`）。[普通事件收取](../../../tmp/p6-r7-review/app-lifecycle-owned-36/ordinary-events-01.json) `859db7` actual0、主控`7d14ff`读回：232事件closed，enqueue/status/start各1call+1result，前二successtrue、startsuccessfalse；两个普通turn均exact `turn/completed`，provider终态seq177/354，session closed逐turn匹配。无pause/resume/retry/cancel；普通回合completed不等于任务完成。
- 固定99事件SHA `6735799b7658aaa3eec8b6e6dc61c70ce2af807b31a392679a55100fd0f726c6`同时绑定普通collector与精确cleanup36。脚本SHA `24e10f6328c63558ea9674e824cdb6c9dc6f5707a785b95a7d7f0dcb2ca6c7df`，Parser/VerifyOnly通过，主控最小diff`01d1d5`复核后Apply `31250b` / session92938→`ff8cbd` actual0。
- [强制收尾回执](../../../tmp/p6-r7-review/app-lifecycle-owned-36/forced-failure-cleanup-01.jsonl)：新持柄App53708和Node56828实际各-1；conhost46036/creation134339637070837200仅观察自然0。不kill native/Witness/服务，不tree kill、改规则或删除数据；历史runtime cleanup_pending保持true，不授予正常关闭/恢复通过。
- 原exec17326经`575a9e`实际外层1，[原Witness回执](../../../tmp/p6-r7-review/app-lifecycle-owned-36/witness-actual-exit.json)实际4，`owned_recovery_frozen / first_close`。原预检native50700完整0与本次runtime失败分开。
- 正常审批只读元数据`d45784` actual0：78f6 owner60452 creation134339643584604192，scope `13353a9b-5f30-1071-4887-4db320145550`；prepared SHA `7e46b388a190246eb01b0a06d0bcfa5b4f0253e8a82766024d0b0725df4d78c6`，final SHA `023aef4eb6b00863592f1a8735037b2e274e8021d2211a88511b336df62e6c38`。只用于准备固定3filter/1sublayer检查，尚无当前规则结论。
- [最终独审](../../../tmp/p6-r7-review/app-lifecycle-owned-36/ACTUAL-FINAL-REVIEW-01.md)，主控`ea8126`读回：最终Witness78事件链通过，末SHA `c7b328453daf579bfde0d42b25d6c03643eba3d3ee8ee233c6e2e7b833cb3b04`；仅owner0完整closed，owner1仅requested，无后继37启动或claim。清理后DB有限任务投影与startfailure完全相同，context保持；强制收尾仍不建立恢复权威。

## 78f6固定规则检查准备（尚未执行）

- [独立检查包](../../../tmp/p6-r7-review/app-lifecycle-owned-36/78f6-rule-inspect/README.md)仅相对已审251b变更六个固定C#绑定；主控`00426b`核最小diff与完整launcher/capture。四GUID分别为allow4 `fab97b45-5d7d-d83e-177d-8d73c061f3c2`、deny4 `7ca35870-03ac-f9a3-5fb3-633222ec46ee`、deny6 `30389362-db13-4002-4769-ebdad1ac5d9d`、sublayer `09d93724-7bd9-3408-52af-360635b6a198`。
- source SHA `feb10ac867358df05a15165fbd23eb68fae514fe2062a5e97a9d6e26b01c5cbf`，exe `1a6bf1850f842fb4cc2b5e11db085a91160cdbffbd43b7bfc91d0f2fb1de62e4`，launcher `8ce465d736ac71e4a80a21e6d12ac52afbc3f1c035db1e7074b1f062af6640f0`，capture `d89a4caefada27f9e720277d95946331ff51d741a9aaad86e82a4fdadc251779`。
- C#编译actual0、静态4/4、双PowerShell Parser0；未运行inspector/collector/UAC/WFP查询或修改。已有只读检查授权保持，但用户本轮是否看到或处理启动弹窗仍待答，先保留具体可审查包，不盲目重复触发。
- [独审报告](../../../tmp/p6-r7-review/app-lifecycle-owned-36/78f6-rule-inspect/INDEPENDENT-REVIEW-01.md) SHA `ca59b08ea2c39084f7c74eb9d058a3738d6417fa96eb50bbb01983b796965001`：六处C#替换逐字相等、四产物hash和六依赖匹配，全部history/caller/ACL/reparse/held pins/idle/事务撤销/资源关闭守卫保持，无新增P1/P2；未触发实际检查。

## owned36实际启动及唯一入队

- 用户明确“已复制”后，主控固定v10双脚本hash并串行prestart/invoke（`0b296f`，原exec17326）；prestart UTC `2026-09-15T16:34:58.6284956Z`，精确候选App/Witness/Node/native数量0、服务身份和新产物缺席检查通过。窗口ID1513728，原Node56828，launch_id `9647dab9-644d-4505-8605-93ebcb6cd718`。
- [启动观察](../../../tmp/p6-r7-review/app-lifecycle-owned-36/STARTUP-OBSERVATION-01.md)与主控`462cd8`：seq13 preflight_verified于16:35:42.363Z，ready=true；native50700、attempt `5f90b0a5-1731-4d47-b1e7-2d3b11efc194`、broker19502。原生actual0/六项true/pendingfalse，无任务turn；仅证明预检。
- 用户复制的固定enqueue原话通过原生输入框右键Paste后Return实际发送，UIA核全文匹配，随后回复唯一任务 `f68fc728-8df6-402b-bf12-1f833309f448`。本轮未另发HI，不继承34短聊为36短聊。
- [入队后DB](../../../tmp/p6-r7-review/app-lifecycle-owned-36/db-after-enqueue-01.json)实际`ec8d5e` exit0，UTC16:39:45.604Z，SHA `ffa80f3241c7ffaf93ea792152ddb62466906ab875b74334fd9db48f71d64f96`。仅1任务、固定title/goal、pending/retry0/actions[]、execution epoch/session/turn/phase/sequence全null、结果0字节；context SHA `f90799459a87a51185a4b0b0b5e3d84fb17b6a6c4f2f9d9bd2ab132d82cedf61`。入队不代表执行成功。
- 本轮再次尝试type_text仍不填入，set_value报`element 1985 is not available in cached app state for memex.exe`，未发送控制。已请求用户仅复制包含本轮UUID的完整顺序查询/启动/暂停句；其余步骤主控操作，Windows安全确认仍由用户本人点击。普通精确终态报告须待该session真实关闭再收取。
- [入队独审](../../../tmp/p6-r7-review/app-lifecycle-owned-36/ENQUEUE-REVIEW-01.md)与主控`af12c9`：DB SHA匹配；[Witness投影](../../../tmp/p6-r7-review/app-lifecycle-owned-36/witness-after-enqueue-01.json)40事件链通过，seq28绑定任务，末SHA `e4ad505877ed68a05766d72f09b783b0391ef68dadecbef040b75dc4471a0131`。原App53708 creation134339637045949370/parent1076，Node56828 creation134339637070779400/parent53708。运行中快照不提供死亡或恢复权限。
- 用户再次明确“已复制”后，主控右键Paste→Return发送唯一任务完整顺序指令，UIA全文匹配。普通session `3ce0f246-e3ab-4a63-ab11-20acb08a0564`，provider `01a0a5ef-d4d3-7e22-bf25-adb65ba0152c`；enqueue turn `01a0a5ef-d5da-7be0-b406-0762801a85f8`，控制turn `01a0a5f5-d24a-78c0-a4e8-a248f59ceacf`。
- seq71→72（16:45:58.087→.499Z）出现runtime owner1，attempt `78f671d7-9bf2-4f2e-88d9-f289bab33c7c`、broker43487、native60452。主控`0764d8`与worker当前观察均仍startup/profile/turn/exit为null、pendingtrue、upstream0；已提示用户处理这次新的安装及后续清理确认，不能将starting算running。

## owned34超时及用户随后发送的结果

- 冻结产品字节未改；主目录`v3-lab@6ea772f18bb1ad7b50a5a04eafc3e972af91116c`，产品工作树仍389aa735已选字节。34/35 package `8412c24810f94198c0968bb40f0b6bbc982e2ebe8c502d53ec004941150c13b5`，dataset `265e2174-1ba0-4bff-9e32-4cc74c22122b`。
- 34于9月15日13:34:35Z到达30分钟`launcher_deadline`，seq56 `shutdown_unconfirmed`，ready=false。native40240已actual0、六项true/pendingfalse；无任务执行turn，普通guardian已closed。超时不是正常App关闭，不能重新激活已消费bootstrap。
- 用户13:55Z报告已粘贴并直接发送。UI记录固定enqueue原话后显示电脑Codex不可用；[只读DB](../../../tmp/p6-r7-review/app-lifecycle-owned-34/db-after-user-enqueue-01.json)仍tasks[]（`a3debf`）。保存聊天消息不等于成功入队，本轮没有enqueue provider turn，也没有任何新任务ID。
- [普通事件报告](../../../tmp/p6-r7-review/app-lifecycle-owned-34/ordinary-events-01.json)实际收取`54ec0e` exit0，主控读回`f5d645`：33事件closed，唯一短聊turn `01a0a52e-49be-7cb3-8e6d-0880643d4325`由精确`turn/completed`终结，provider seq117、工具0。普通session `04b00fc5-44a2-4603-aade-2e7922cf09b3`，provider `01a0a52e-488c-7331-a02f-9aff06e26384`。
- 原执行session24814先输出`owned_recovery_frozen / first_close`，最终实际退出码仍未取得。正常UI关窗请求未确认，窗口保留；随后工具报告用户物理Escape停止，当轮停止电脑操作并中断两个worker，未继续清理或启动36/37。

## 9月16日00:17重新核实

- 用户再次继续后，精确CIM/创建时间/镜像/argv只读核实（`29d03f`）：App57520 creation134339510728148577 parent57116；Node16592 creation134339510752086777 parent57520；conhost15816 creation134339510752163810 parent16592。原Witness57116/native40240未出现在精确查询结果；当前缺席不替代原持柄退出证明。
- 34事件仍56行、相同超时末态，普通session关闭、native完整actual0、无任务。UI恢复后显示“关闭尚未确认，窗口已保留”，因此需精确失败收尾；仅针对上述App/Node，conhost仅观察，不修改规则/数据库/共享服务，也不授予恢复权限。

## 9月16日00:26失败收尾实际完成

- 主控复核cleanup34最小diff及SHA `6aeaab9f55e683c3259261bf76af5f5334ded24b3ac947e09e3a30fdb1c6562a`；worker Parser/VerifyOnly实际0。Apply `153559` / session19225 → `da25ac`实际0，严格固定56事件SHA `19e1fcb38192f697fc0db2f278b1510b572fc67315fb66c73dc35ea6f89f3621`，逐进程身份、创建时间、父链、argv与镜像验证后执行。
- [强制失败收尾回执](../../../tmp/p6-r7-review/app-lifecycle-owned-34/forced-failure-cleanup-01.jsonl)：新持有handle观察App57520与Node16592各actual -1；conhost15816未kill、自然actual0。native/Witness/共享服务未kill，未tree kill、未改规则，数据保留。`normal_close_proved=false / acceptance=false / recovery_authority_granted=false`；native原预检已完整关闭与App整体失败分开记录。
- 原始exec24814经`aedad1`终于返回：外层脚本actual1，[原Witness实际回执](../../../tmp/p6-r7-review/app-lifecycle-owned-34/witness-actual-exit.json) actual4，仍`owned_recovery_frozen / first_close`。这是旧失败实况补齐，不改写为正常关窗或成功恢复。
- [独立复核](../../../tmp/p6-r7-review/app-lifecycle-owned-34/ACTUAL-FINAL-REVIEW-01.md)核实清理原回执及普通终态绑定；[清理后DB只读投影](../../../tmp/p6-r7-review/app-lifecycle-owned-34/db-after-cleanup-01.json)仍tasks[]。首次Witness投影01因无法读受保护目录而保留`unknown / audit_chain`；主控随后经正常审批路径只读执行`645c86` actual0，[投影02](../../../tmp/p6-r7-review/app-lifecycle-owned-34/witness-final-failed-02.json)为verified_snapshot。130事件连续，末SHA `489112b328a69f9cb79cd77ff7078396263cf92b57cf1d354956aea5cf9bd3a9`，仅首App/Node注册，无claim/后继spawn；末项为resources_released，要求原Witness actual0但实际4，因此不授予恢复权限。该reader不提供进程死亡证明，实际退出仍以原执行回执和精确清理持柄为准。
- ordinary collector绑定的快照准确对应launcher前56事件；清理时追加57 stdin_end、58 shutdown_requested、59 stdout_unavailable、60 shutdown_unconfirmed，导致最终文件hash变化，未改变旧快照内容或短聊终态结论。

## 新36/37准备（尚未启动）

- 独立dataset `0fb38de6-5b88-4e76-9359-10a61ff253e3`；package SHA `bcf09a26f1faba6eb162bff736b9caa8e27c4ee5d01a8b7117d56c58b71dd64e`；bootstrap SHA `b9eb3c9d533d859ea94ed3740db7e194791d41034db7c1ca879b771445d3ac35`。399pins、包绑定、新数据目录缺席与无收据复用已核。
- invoke-v10 SHA `8cd522d486b1a24adbebd4e7de5933cf2cbc35cebd1ba882bd25568e13b1bffb`；prestart-v10 SHA `8f2982e588a707ab7a176a6365785a676d5b557b52bea127f154660001c35d74`。仅换36/37及新dataset/package/bootstrap/观察01，保留v9类型安全UTC解析和0..60秒新鲜度，主控最小diff`cff44c`核实。
- post-close collector-v8 SHA `525884bde40c6da3c7b1e01f6b7339f68ce7776c4fc18b71216885f75dfd0ec8`，同样只换绑定，严格closed/逐turn终态及CreateNew条件保持。语法通过，尚未GET或启动候选。
- 旧34精确收尾与原Witness实际退出已取得。已发出固定enqueue文字复制准备请求，等待用户确认复制好后再启动新包，避免30分钟窗口耗在人工文本准备。Windows安全确认仍须用户本人处理；不延长时限或复用已消费bootstrap。旧32 pending任务保留，生产入口继续拒绝，真实任务和共享服务不在本次操作范围。
