# P6 R7 修复包再次验收与固定程序来源

2026-09-13。用户在[四项临时规则复查完成](P6_R7_PREFLIGHT_CLEANUP_20260913.md)后要求继续，当前目标是先复验“运行中取消”，再依次验证页面/后台、退出及未完成任务重启。固定任务仍为“只输出从 1 到 2000 的整数，每行一个，不使用工具或外部资料。”，不改生产启用状态或真实队列。

## running-03：固定CLI来源已不存在，未进入App

running-03窗口开始时，主目录核对为 `v3-lab@68307c9ea837f11dc82e148e8f51feff89b50fb6`，索引空、并行修改保留。原修复候选的157源文件、152 bundle、18项Node闭包及Node/v7映像指纹均核对一致。全新[启动窗口](../../../tmp/p6-r7-review/app-lifecycle-running-03/launcher-build.json)保留原candidate清单 `d46eba2d…9c0f4` 和closure `e56ea781…5fe04`，三个辅助脚本仅重绑定观察目录；未重新构建或替换原候选。

11:12:56–11:12:58（UTC+8）零模型预检失败：[events](../../../tmp/p6-r7-review/app-lifecycle-running-03/events.jsonl)共6帧，SHA `84189f6f416477598c7a19cd59250c5e1c4a22318d13b73d05015d4c95291bf2`。Node10168 / `2026-09-13T11:12:55.8774989+08:00`，launch `b08e602b-6a68-402d-a1df-cda36e306928`，attempt `3dd1ed07-b187-46a5-bb8e-c6e2afa40c65`，native13088，broker45837；错误为 `task_files_cli_source_win32_2`，actual native exit4，startup/profile/turn均null，broker所有请求及arm/upstream为0、drained=true。独立observer未赶上原生短生命周期，observed_attempts=0，不能补造创建时间或parent证据。

当前固定 `7ac07f4ce733f89a` 安装目录已不存在。当前安装映像为另一目录 `bffc5354119c8421`，SHA `081e4de4be8e38fac6ed4d95e3b1a0b9f6d31c090ddc36e1696b349fe406f575`；未据文件指纹推断具体版本号，未运行该CLI或读取认证资料。

冻结v7代码在TaskFiles构造中先创建attempt目录，再打开固定CLI来源；本次在打开来源时失败，尚未复制CLI、创建TaskChild/Job、journal/finalReceipt、TaskBoundary、helper或进入installAttempted。独立只读确认精确attempt目录顶层0项。报告中的Rules/Helpers=true来自未尝试安装分支，**不是WFP实查结果**；原native4/pending和六项verified null保留。依据固定路径与空目录的一致性，本次无需另做WFP回收动作。

11:17:17+08，[精确退役](../../../tmp/p6-r7-review/app-lifecycle-running-03/host-retired-unconfirmed.json)核对Node PID/创建时间/映像/完整命令、原生已退出及broker排空后，仅结束本次失败host。原events指纹不变，不记为正常host shutdown。现役47831/PID32976/创建10:49:28.9962919及47841/PID25332/创建10:48:06.5347680在当前窗口前后保持。普通沙箱中最初服务查询的空列表未经成功状态核实，已由[严格成功的外层只读观察](../../../tmp/p6-r7-review/app-lifecycle-running-03/prestart-processes-verified.json)替代，不能把前一空列表解释为服务缺席。

## 来源修复范围

保留已验证CLI SHA `3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004`。只读复核确认5257受控目录内的既有copied CLI仍精确匹配；新原生候选仅将固定来源重绑定至该映像，继续执行所有祖先/held canonical/非reparse/SHA检查，不接受任意输入路径、不重建旧安装目录、不复制认证材料、不混入清理诊断改动。

App的 `p6R7NativeHash` 和host的 `APP_CANDIDATE_NATIVE_SHA256` 都严格绑定原生映像，因此需要新隔离工作树、新原生/App构建及新闭包清单；不能直接将新native接到旧修复包或放宽校验。原工作树与全部旧证据保留。

来源重绑定准备阶段尚未开始新的App运行中回合。后续须先完成新候选固定输入、专项验证及零模型预检，再进行真实UI取消；生产保持available=false/fail_closed=true，P6/Goal1/真人Gate未完成。

## 来源重绑定候选及构建工具恢复

新[原生候选清单](../../../tmp/p6-r7-review/native-source-rebind-01/candidate-build.json)SHA `e2bf9a1d53521f6175e7bfcd18a3d13738e764658212ceeba82d3e449ce28e38`，源码 `448ab285ba89570f925602c56066a298dcce272b57e0c6697994a9e9519af492`，exe `674f159148f47c9702a360bfb4d32fd7b37604cd453a3104a3db08dd83fd02fc`。唯一逻辑变化是SourceCli getter；原CLI hash不变，6项编译输入前后相符，3/3测试含712项托管断言和95项纯自测通过。主控复核唯一差异并对最终exe复跑纯自测95项，独审无新增P1/P2；该阶段尚未实际Run，后续running-04结果见下文。

新工作树 `.worktrees/p6-r7-source-rebind` / `codex/p6-r7-source-rebind` 来自精确 `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`，带入原候选154项非生成源文件与18项host闭包，仅改App与host的两个原生映像hash常量。三个依赖生成文件由现有SDK重新生成，不带入旧build产物。

Flutter batch入口产生了四个卡住的包装进程；36048先退出，其余23472、8608、8484经PID/创建时间/父进程/完整命令及无依赖子进程核对，在人工Windows确认后精确结束。[实际回执](../../../.worktrees/p6-r7-source-rebind/tmp/p6-r7-build-wrappers-retired-actual.json)及[外层退出](../../../.worktrees/p6-r7-source-rebind/tmp/p6-r7-build-wrappers-uac-actual.json)均确认成功，没有停止App/native或现役服务。旧失败记录已校正为termination_attempted_not_completed，不沿用先前误写的成功描述。

主控运行doctor完成环境诊断；普通隔离命令环境中的auth/连通性提示不作为专用P6登录失效证据，也未改认证或系统安全设置。改用同SDK cached Dart + flutter_tools.snapshot。默认缓存路径是指向 `D:\C_Moved\pub_cache` 的既有目录映射，首次主控离线解析已取得依赖但在active_roots登记报路径错误；随后仅为当前调用设置PUB_CACHE至同一实际目录，离线pub get实际exit0，未改全局环境或目录映射。

主控重新运行新工作树7个Dart专项文件，**87/87通过**；新host **15/15通过**，唯一App变更文件的定向分析无问题。host测试沿用既有断言，只在临时目录回收前增加canonical父目录和固定前缀检查。critical **3/3通过后**Windows Debug构建实际exit0（164.8秒），绑定原两项候选enable/data-root值。两处hash改动另外各有一段精确EOF CRLF，冻结时明确记录并保留实际编译源，没有通用trim或放宽其它源比对。

## running-04：取消通过，运行中退出暴露缺陷

新[冻结清单](../../../tmp/p6-r7-review/app-lifecycle-running-04/candidate-build.json) SHA `0e78c6c59d9872b65ba3f62e32c485f4d2c857b55dbabdd87835beb0bcfa34e3`，157源/152 bundle/18闭包，exe `494a52af2bb7a97ee28fa0b33324f2587592585436b468632c272f1ff3831390`，kernel `d1b961c2c699b48cf93ec0c65c2e845596a1eaf11e7c509d5d54be53a0adcdbd`，闭包 `4a183b9d3fbf383c9af80dd8b1a5c66531c92146995a4da6072350a2af14a21c`。主控与独审逐项指纹吻合，四脚本语法通过，未自动派发任务。

以下UTC时间均来自实际工具/文件；本地时间为UTC+8。Node35684/启动11:53:27.0751040，launch `71a86e91-08fa-45b2-84ed-fa5102cac6fd`，port52751。独立observer在host之前启动并捕获全部四个native的PID/创建时间/映像/parent。

- **零模型预检通过**：owner0/b61e/native7456，03:53:41.941 ready，closed_without_turn，upstream0，native exit0、六项true/pendingfalse。
- **运行中取消通过**：App38440，run7913837e，owner1/4be4910f/native38856。03:55:44.370 UI显示运行中；03:55:53.212完成取消点击；03:56:07.569 UI显示已取消。frame15核对同session/epoch/local/provider turn，interrupt seq9后terminal seq11为interrupted，cancellation_confirmed=true，native0、六项true/pendingfalse；[DB](../../../tmp/p6-r7-review/app-lifecycle-running-04/db-cancel-01.json)同任务cancelled、空结果/user_requested，App随后03:56:37.664 exit0。文件独审通过；UI结论来自主控实际窗口观察，不由DB推造。
- **页面/后台有限观察通过，随后任务失败**：App38328/run3d913fff，owner2/08c1aee7/native15940。03:58:13切到持续状态页，03:58:20 UI仍运行中；随后点击最小化，工具明确返回window is minimized。03:58:52 [只读DB](../../../tmp/p6-r7-review/app-lifecycle-running-04/db-background-01.json)仍running，[进程观察](../../../tmp/p6-r7-review/app-lifecycle-running-04/background-process-01.json)确认同一native/turn且无stop，未重复owner。恢复窗口后03:59:01看到运行中，但host同时间已完成failed终态，故不能以该UI瞬间判断仍有真实执行；03:59:08关闭App不计运行中退出。其broker从exchange到拒绝60.005秒，与固定60000ms截止吻合，具体错误已统一脱敏，不能确认超时根因或归因于最小化；DB保留provider_execution_failed、空结果，native0/六项true。
- **运行中退出未通过**：App37308/runc394f99d，owner3/15cd685a/native36088。04:00:51.752 UI运行中，04:01:00.131 Alt+F4，App于04:01:00.389实际exit0。04:01:37.689 [独立进程观察](../../../tmp/p6-r7-review/app-lifecycle-running-04/after-app-exit-process-01.json)确认App已缺席但同一native仍活、无stop/exit；[DB](../../../tmp/p6-r7-review/app-lifecycle-running-04/db-exit-running-01.json)仍running。这是确定的退出缺陷，不能将App退出码0视为回收。

主控随后通过本次拥有TTY的shutdown入口独立停止宿主，04:01:42产生[正常宿主关闭回执](../../../tmp/p6-r7-review/app-lifecycle-running-04/closed.json)，全部四owner native0/六项true/pendingfalse，Node及observer工具均exit0。该独立回收不能补写App退出通过。[最终进程复查](../../../tmp/p6-r7-review/app-lifecycle-running-04/final-processes-verified.json)确认测试App/native/host全无，47831/PID32976与47841/PID25332的原身份保持。events共30帧，SHA `195ccecae9d34c8cafe51ec043a98a0af2a20ad55aba17eca1b79c0981e2a94a`；closed SHA `7fa49077b5d691483bde617770880acd91caed7a351bbc656438dd4f9c229b73`。

该阶段下一项是修复候选退出等待接线并重跑真实退出/未完成重启，结果见下文。生产/P6/Goal1/真人Gate边界不变。

## window-exit修复与running-05实际复验

只在新`.worktrees/p6-r7-window-exit`（同一1b6a2961基线）修改候选widget及其测试。原问题是仅有detached的不可等待请求，而未实现已有Flutter `didRequestAppExit`；固定SDK框架已有退出协商，不能因runner未写WM_CLOSE就断言必须新增原生channel。修复在退出请求中等待owner的现有关闭证明，true才exit，false/异常均cancel；合并并发退出，失败后可重试，首次退出后永久禁用新任务操作，全路由显示停止/失败提示。未改runner/native/host、150秒关闭等待或停止协议。

主控定向93/93通过，独审无P1/P2；静态分析首次在用户级Dart/perf退出记录处报1920/exit4，换为本次调用的独立LOCALAPPDATA后无问题/exit0，不改全局配置。critical3/3后Windows构建157.4秒、实际exit0。[验证记录](../../../.worktrees/p6-r7-window-exit/p6-r7-window-exit-validation.json)绑定实际日志与源hash：widget `fa3874a8c32a758a5b30d3ccf188d860085f4ef30eee3026a5d44e117c5025a5`，test `702159c3b49151c5094b7072b5fcac8e81e4ca2fa34af761620e9ebb5b57207d`。18项Node闭包内容逐字未变，先前15项测试仅作为这些未变输入的已有验证，不伪称本次重跑。

新[候选清单](../../../tmp/p6-r7-review/app-lifecycle-running-05/candidate-build.json) SHA `60ef1a28f017436096130f42a65e046bf9f3caf6fbd2c84f25ffdaf4966da5a2`，157源/152bundle/18闭包；exe `b2261b3a550b08b621d53bc838024c8f0caba535887d357035a8b749bd963511`，kernel `6db65ffd86a77ab3db194fe97f2f7441bb0f15371d4e48f72aaa072cbd2b4b10`，闭包 `c5f3b8a3cb82bcb17f858911c3dccd1e4a0f275b43f9d3535f8ec35f3fa4a7cf`。主控及独审核对全部指纹和四脚本，observer先于host；native仍固定674f1591。

实际Node37656/启动12:20:32.8480532，launch `35ced1dd-b9de-4a0c-8dd4-c847c35ff4ed`、port19264：

- **预检通过**：owner0/e8fa361d/native22180，04:20:45.995 ready；closed_without_turn/upstream0/native0，六项true/pendingfalse。
- **取消复验通过**：App35704/run0f5beea0，owner1/db1fe835/native35832。04:22:23.883 UI运行中，04:22:32.184取消，04:22:41.618 UI已取消；frame15同绑定interrupted（interrupt9/terminal11），native0/六项true；[DB](../../../tmp/p6-r7-review/app-lifecycle-running-05/db-cancel-01.json)cancelled空结果，App04:23:09.496 exit0。
- **真实运行中退出通过**：App37508/run1d335df5，owner2/a0799ebd/native13344。04:24:28.624运行中，04:24:36.377切页，04:24:49.284持续状态页仍运行中；04:24:56.817 Alt+F4后同页实际显示“正在停止任务…”，窗口保留等待。frame23在04:25:04.573确认同session/epoch/local/provider turn的interrupted（interrupt9/terminal11）、native0及六项true/pendingfalse；App随后04:25:04.625才exit0。[DB](../../../tmp/p6-r7-review/app-lifecycle-running-05/db-exit-running-01.json)变为blocked/phase interrupted、空结果。此时宿主尚未shutdown，停止归因于App退出请求，区别于running-04人工回收。
- **同数据重启不自动执行通过**：App12712以restart重开同run/同admission/同候选；04:25:55.041和04:26:39.781 UI保留“已中断或受阻”，未点击恢复。[重启观察](../../../tmp/p6-r7-review/app-lifecycle-running-05/restart-no-dispatch-01.json)报告在60.383秒时生成，引用的frame24为重启后57.975秒；该帧及后续frame25–26中owner仍3、turn仍2、upstream总数仍2，全部native已关闭，结合不删除owner的完整历史支持观察窗口内无自动派发，不能把报告时间当作单帧采样时间。[DB](../../../tmp/p6-r7-review/app-lifecycle-running-05/db-restart-01.json)同任务/epoch/turn与interrupted状态保持，未新增executionRequest。App04:26:51.528 exit0。

最后宿主正常shutdown与observer均实际exit0，独立observer捕获三个native；[最终复查](../../../tmp/p6-r7-review/app-lifecycle-running-05/final-processes-verified.json)测试进程全无、现役服务保持，26帧events SHA `2b82d3a3172890d72d27f9715d1ec16821eb5aba8aaac8a39232bc552d173485`，closed `0cada4ca40724bf60bdb7a0c315d6b053a3876b915d0cd53386235ce50000ce0`。

两处退出修复已在先核对主目录原文件与旧候选完全相等后[本地集成](../../../tmp/p6-r7-review/window-exit-local-integration.json)至当前`v3-lab@b55386cf`，索引不变、未提交推送；主目录原有测试集合的七文件 **91/91** 与两文件定向分析通过，隔离候选集合是93项，两者不混报。CLI来源/原生hash重绑定继续只保留在隔离候选，未擅自改生产入口。

## running-06：同包最小化补验与最终回收

新[证据窗口](../../../tmp/p6-r7-review/app-lifecycle-running-06/launcher-build.json)复用running-05逐字相同的candidate、closure与launcher-config；157源/152bundle/18闭包、exe/kernel/native指纹不变。四辅助脚本仅变更05→06观察目录，launch.mjs正文未改；没有复制旧events、admission或DB。Node2076/启动12:33:57.2872968、launch `ab2e5268-6a83-4a96-ad9e-1198a993c11e`、port15478。owner0/ac7eb9fe/native38884在04:34:19.387完成零模型预检、closed_without_turn/upstream0/native0/六项true；独立observer捕获两次native创建身份及parent。

App3160/启动12:35:20.8625108，新数据run15011104，owner1/3339a374/native30752。04:36:41.511主控看到运行中，随后最小化工具明确返回window is minimized；04:37:04.749的[只读DB](../../../tmp/p6-r7-review/app-lifecycle-running-06/db-background-01.json)仍running，04:37:04.856的[进程观察](../../../tmp/p6-r7-review/app-lifecycle-running-06/background-process-01.json)核对同native创建时间/映像仍存活，owner仍2、同session/epoch/local/provider turn，无stop/native exit。该进程快照本身未查询parent，parent依据另存的native-identities。04:37:14.054恢复窗口，UI仍显示运行中。以上为新包最小化期间持续执行的有限观察，不以旧包结果代替。

04:37:19.902 frame12的broker rejected_requests从0变1，距首次观测upstream=1的frame11约59.985秒；04:37:24.184 frame14确认同回合terminal failed/seq12、native实际exit0、六项true/pendingfalse、drained=true/response_released=false。04:37:22.933虽尝试点击取消，[最终DB](../../../tmp/p6-r7-review/app-lifecycle-running-06/db-background-final-01.json)只有start执行请求，状态failed/provider_execution_failed、空结果；stop的interrupt_dispatched与cancellation_confirmed均false，**不计取消成功或正常任务完成**。04:38:02.630及04:46:00.505实际UI均显示失败。该失败发生在App关闭前，不能当作运行中退出通过，也不能仅凭时间或最小化动作归因。

04:46:07.550发出正常关闭；[App实际退出](../../../tmp/p6-r7-review/app-lifecycle-running-06/app-background-01-exit.json)04:46:07.8189828、exit0。随后通过本次owned TTY shutdown宿主，04:46:15.640写入[closed](../../../tmp/p6-r7-review/app-lifecycle-running-06/closed.json)，host与observer工具均实际exit0。两owner native0/六项true/pendingfalse；[04:47:12最终进程复查](../../../tmp/p6-r7-review/app-lifecycle-running-06/final-processes-verified.json)确认测试进程0，47831/PID32976与47841/PID25332的映像/创建时间保持。events共16帧，SHA `08110ca13fee3ab5214b546e1a5d68ef0b3b3fc4dbd73ae0a96587c5e7327d8f`，closed `a846fbbd4998f98901e0a9ed9f15d300919330f5fe6b5d25e171104be4e26aff`。

最终独立只读审阅逐项核对running-06的157源/152bundle/18闭包及launcher指纹、后台与最终DB绑定、failed非cancel、16帧连续记录与closed一致、最终进程和服务身份，未发现新增P1/P2。host/observer真实exit0采用主控工具证据；UI最小化/恢复结论只采用主控实际窗口观察。退出修复与running-05的独审结果另按各自证据窗口保留。

限制与下一项：running-04/06的约60秒failed仍未确诊；现有broker把所有交换失败统一脱敏，仅时间相近不能证明timeout。已提出不放宽60000ms且不暴露响应/认证的有限错误枚举方案，尚未实现。重开提示仍使用原有保守的“停止结果未知/需显式恢复”文案，不能将外层已有关闭证明伪称已投影进该提示。异常强退/宿主崩溃、显式恢复、生产接线及完整真人Gate没有由以上常规退出观察替代；P6/Goal1仍未整体完成。
