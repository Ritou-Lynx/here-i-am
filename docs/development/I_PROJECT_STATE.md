# 林埃的项目状态

## PR14 大容量防回退与现场清单（2026-10-06）

继续同一codex/core-deploy-readiness-20261006 / 草稿PR14，base v3-lab@90f23ce1，不合并不部署。外置domain记录见证改固定摘要，完整认证操作历史重建物化结果；历史改写、revision/body回退、缺行、FK损坏仍拒绝。四只读线程与64MiB临时SQLite缓存没有省略深审计/旧历史；每phase原生证明仍使用新challenge/sequence/MAC和真实句柄。

最终200k容量344.350秒通过，多revision/删除/purge和六种损坏全部验证；floor2213→2674字节，孤儿FK在seal/recover拒绝且head逐字不前进。真实Windows固定包两档完整关闭/异常恢复/每日备份：10倍3.118/25.729/11.865秒，50倍9.014/70.049/51.587秒；备份不含U盘镜像/调度等待，不把局部profile当总耗时。旧超标版明确保留。

主窗650tests/649pass/0fail/0cancel/1既有大小写环境skip，885951.5865ms，相邻95/95；46库存、Node28/PS16语法通过。正式源码/固定manifest与烟测提交后绑定，新精确head CI回执登记同PR，旧a608绿不能代替本次结果。详见[本轮大容量验收](handoffs/SCHEMA6_SCALED_RECOVERY_20261006.md)。

[现场④–⑥](handoffs/SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)覆盖历史精确任务/进程/端口/路径、失败退回、NTFS U盘本人决定格式化（i不格式化）、恢复口令/任务本人批准、合并另授权→合并后重建→切换另授权和真关机四Gate。邮件debug关闭，47862保留、legacy_b3唯一上传器。ARSO实际行为不确定；新电脑新DPAPI/独立恢复key/current-head/配置绑定以建立现役Core列下一轮缺口，本轮只读检查还原。

本轮现役Core/MCP/隧道、原库、真实任务和手机均未读取或操作；没有实际关机/注册任务/装手机。只推同PR，新CI全绿后暂停等审核。


## PR14 自动运行候选验收（前轮已通过，2026-10-06）

继续 `codex/core-deploy-readiness-20261006` / 草稿 PR14，base仍 `v3-lab@90f23ce1`。固定源 `9553cd2b2723cc389d7edf478dd33ff3ad478aa8`：主窗604tests/603pass/0fail/0cancel/1既有大小写环境skip，1,005,950.4859ms；六类原生/合成关机和中断演练全部通过。新43项固定包manifest `08cc28a2e694f66349ac8f2c772378cdd6da476cd08cdf5a009bfe837747095c`，Node25+PS16语法通过，真实启动/认证停止/Job/锁烟测68,500ms通过。最终文档提交库存逐字复核、远端全部检查以同PR正文/Checks精确head实际回执登记，全绿后暂停；不合主线、不部署。

首开前DB/WAL/SHM/journal流式加密，隔离副本回放/4→5→6、独立custody与完整结果认证；隐藏会话正常关机清停、异常后下一登录自动核验恢复，稳定Core死亡可同会话有限恢复。备份键DPAPI+scrypt/AES-GCM口令包，默认每天/30天，可配置外部密文镜像。Tailscale不备机器私钥，换机重新登录同名。

CI失败历史保留：短TEMP/owner夹具修复，白板save屏障5/5与相邻195/195；module发现原10秒门槛超时，hosted-only作用域14/14含23恢复情形通过。1060两次Windows151/151与13checks全部成功，原production gate843/1040ms、目录和两registry完整还原；新交付含生产Frame修复，需要152项与13checks新回执，不能套用前一提交。生产plainPath/ACL逐字不变、timeout未改。

真实PS5.1生产输入BOM修复：旧源码先红、新回归三编码×两帧及失败编码恢复绿，备份相邻38/38；此次604整组含新回归。独立只读源码/范围复核通过，详情见[本轮验收](handoffs/SCHEMA6_AUTOMATIC_MAIN_ACCEPTANCE_20261006.md)。不同标准SID口令真实只读Core恢复在一次性hosted VM已多次通过，最终head还需同一CI；实体异机未实测，检查目录不可直接激活。

此前九类52真实文件还原/退回已获用户通过，本轮未重读。未读取/停启现役Core/MCP/隧道、原库、实际计划任务或手机；未实际关机、注册任务或本机创建账号。captures真机闭环未过保留47862桥，切换单消费者/单上传器；邮件debug可先关闭。只推同PR、全绿后暂停等审核。

## PR14 复核续作：CI 与自动运行（2026-10-06）

用户已通过此前九类备份、真实只读还原和退回说明，要求继续同一 PR #14，暂不合并/部署。CI 根因修复已集成：Windows 测试根先规范实际 8.3 TEMP、固定 Node 输入独立拷贝；CI 测试进程专用 default owner 修复，不放宽生产 plainPath/链接/ACL。白板保存测试使用明确异步完成屏障，阻塞保存时不得关闭；本机 Node86/86+路径3/3、Flutter精确5/5+canvas195/195。精确新提交远端检查待回执，见[CI修复交接](handoffs/SCHEMA6_CI_REPAIR_20261006.md)。

自动关机钩子、异常退出后原始文件加密保全/副本恢复、旧v4副本4→5→6、交互式登录任务模板及每天口令备份正在合成环境中并行推进。Tailscale机器私钥按用户决定不备份，换机重新登录同机器名。此前“每晚人工清停/所有异常必须人工恢复”属于被当前指令替代的历史设计，不是后续产品目标。最终整组/六类演练及全部CI通过后更新同一PR并暂停；现役Core/MCP/隧道、原库、计划任务与手机本轮不触碰。



## schema6 部署准备源码（前轮历史快照，2026-10-06）

本轮从已合入PR13的`v3-lab@90f23ce1`隔离为`codex/core-deploy-readiness-20261006`，推进D4源码准备。新增固定Windows Job/guardian与认证清停、真实离线租约、原canonical路径恢复验证，以及独立认证current-head/不可覆盖凭据链。完整运行备份按九类显式清单流式AES256GCM验证，密钥由backup/recovery分别绑定的CurrentUser DPAPI保管；库存工具不替用户证明生产依赖已列全或writer已停。

固定候选包括34项库存，Core、生命周期/恢复/备份wrapper与Node来自同一真实提交，默认`legacy_b3`单上传器、reply jobs/activity关闭。主窗最终211/211、0失败/跳过，精确候选烟测50.534秒通过；新增Linux便携与Windows生命周期/DPAPI专项CI，远端结果待草稿PR当次检查；精确验证及失败历史见[主窗验收](handoffs/SCHEMA6_READINESS_SOURCE_ACCEPTANCE_20261006.md)。旧v4没有可验证外部清停入口，新监督入口仍拒绝旧库无凭据首接；非优雅停止后的原始日志保全/SQLite恢复/adoption方案见[部署方案](handoffs/SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)，尚未实现该例外。新增认证后隔离提取与真实Core只读检查入口，本轮授权制作九类52文件密文并实际还原，真实Core只读启动/拒写/关闭通过，6库全部表及52项字节一致；Tailscale系统身份权限拒读仍缺，手机使用前轮保留schema62副本。用户要求整包复验、推远端草稿PR后暂停审核；确切回执见主窗验收。现役原库、任务/配置、MCP、47862桥和手机没有因本轮源码改变；D4生产切换未完成。

## PREDEPLOY 审计后兼容修复与源码集成（2026-10-06）

用户已确认 D1–D4 推荐。B3 `codex/b3-writeback-local-20261003@3a9336b1` 与正式副本同根，和 D 私人旧谱系的可达提交交集为零；新增 blob 隐私路径/字面凭据筛查无命中，已推送 GitHub 同名分支，远端 SHA 一致。PR #12 五类精确 head 检查通过后普通合入 `v3-lab@64aea693`；现役服务与主力手机未变。

主窗 `codex/post-audit-integrate-20261006` 整合 B3 Drift61/62 原文迁移、受限 transcript/grant/replay、单一上传器及 PR12 账本/day_get 跟进。隔离白板候选的重开/恢复只读门槛也同步62，旧60和未知63明确拒绝。真实主力手机 B3 schema62 一致副本两次打开，140 张表的数据/列指纹一致；Core 真实 schema4 副本 4→5→6 保留旧表、身份、grant 与完整72绑定。离线副本结果不能代替生产恢复 floor 或升级 Gate。候选包装仅准备固定源码/Node 库存和只读预检，明确未部署；生产 supervisor 与真实恢复证据仍待后续。

47862 桥在 captures 真机新增/改版/删除闭环验收前继续保留；Core 网页消费切换需要独立 Gate 与来源 adoption，不能靠 UI 开关或同文匹配。白板夹具补滚动后layout与实际hitTestable断言后，最终本机受影响Flutter组合再次502/502、Node组合167/167，旧失败和精确复现留在交接；精确提交远端CI按PR Checks回执。Android候选重建与同B3签名校验成功，固定Core候选真实副本预检通过；[PR #13](https://github.com/Ritou-Lynx/here-i-am/pull/13)五类精确head检查全过，用户确认后于2026-10-06 03:25:00Z普通合入 `v3-lab@90f23ce1d38628901e25b421d8f0f21c084f093b`，合并树与已测head `3ec7b1d65a047c895edacd72348af02a7b1ceded` 的树一致，正式副本已仅快进且干净。合并回执在原任务分支单独留存，不追加主线源码提交。最终组合验证、APK候选和本轮交付状态见[审计后主窗验收](handoffs/POST_AUDIT_SOURCE_ACCEPTANCE_20261006.md)。本节下方的并行候选说明为 PR12 合入前的历史快照。

## W3/W4/W5 并行候选与部署前只读调查（2026-10-06）

用户已授权并行源码开发。本批从 v3-lab@8dde12b3 隔离：W3 codex/w3-domain-mcp-20261005，W4 codex/w4-quick-capture-20261005，W5 codex/w5-planning-views-20261005；主窗 codex/hub-parallel-20261005 实现 W7 按记录/操作存储、保留迁移状态与关闭本地去重，见[前置候选](handoffs/W7_ROW_STORAGE_20261005.md)。W3/W4/W5已普通合入该任务分支，主窗完成独立捕获/规划入口、页面外提醒、应用锁及账户DB生命周期返修；最终组合验收见[交接](handoffs/HUB_PARALLEL_SOURCE_ACCEPTANCE_20261005.md)。主窗最终Flutter235/235、Node172/172，新模块严格分析无问题，共享旧43条诊断增量0；新增实际双SQLite连接竞争修复与后台草稿保留。源码提交acb50dae；合成UI预览已目视复核，Android Kotlin任务成功，但完整APK在JNI/CMake环境阶段失败。完整CI按任务PR精确head回执，不等同部署及设备Gate；尚未合入 v3-lab。

用户另开只读调查线程 01a10c93-10d4-73b2-928d-f740fde50046，分支 codex/predeploy-audit-20261005。报告及返修提交19588f4f只留该分支，不合入主线。现役固定 Core4 transcript/replay 未进入当前主线；10条手机 companion 最支持B3上传归因但仍为推断，持续调用未知。发现的B3手机候选 DB62 vs 主线60须先解决兼容；ADB零连接，现装包未核。仅报元数据，未停服、改配置、升级原库、安装手机或启用生产领域。

## W1、W2 与 W7-0 源码已合入（2026-10-05）

42既有失败修复经 [PR #7](https://github.com/Ritou-Lynx/here-i-am/pull/7) 合入 `38ed6b88`；用户已确认[领域接口约定](I_CORE_DOMAIN_CONTRACT.md)。W1 [PR #8](https://github.com/Ritou-Lynx/here-i-am/pull/8) 五类精确 head 检查全过，普通合入 `v3-lab@dc29fd5e`，合并树等于已测 head；[合并回执](handoffs/W1_DOMAIN_MERGE_20261005.json)。原工作副本保留，正式主副本已仅快进源码。

W1最终13源码的授权只读一致副本4→5→6演练通过：[R01](handoffs/W1_COMBINED_R01_VALIDATION_20261005.json)。八表/行/序号/身份/replay保全，独立加密备份与明文清理；输入为真实schema4派生的新空activity5，不证明已有真实activity历史、现役固定v4功能或外置授权兼容。未升级原库/切换服务/签发生产领域凭据/安装手机。

W2四业务域与两个默认dry-run导入脚本完成有限源码验收：[主窗验收](handoffs/W2_MAIN_ACCEPTANCE_20261005.md)。四根Core/Memory/remote MCP/continuity gateway递归42文件654项，653过/0红/1原有平台跳；完整回归后只补既有守护断言诊断，严格断言未改，定向4/4。首轮34文件的1叶子+1父级失败保留且唯一触发分支未恢复。业务仍显式注册、默认off，真实来源和周日映射/旧传输receipt另验。

W2源码提交 `a00112e8` 经 [PR #9](https://github.com/Ritou-Lynx/here-i-am/pull/9) 合入 `652536cf`；手机基础 `feffba94` 经 [PR #10](https://github.com/Ritou-Lynx/here-i-am/pull/10) 合入 `21a813ef`。两项均已核实五类精确 head 检查成功，普通合并树等于各自已测树；正式主副本已快进源码。W7-0手机基础完成有限主窗验收：[交接](handoffs/W7_FOUNDATION_MAIN_ACCEPTANCE_20261005.md)，114/114、相关分析无问题，含9个真实Windows OS-kill SQLite边界；Dart↔真实W2 Node HTTP 5/5，原op丢回执恢复、稀疏merge/后入队base7→8及永久删除已验证。默认空owner配置/phone；整张W7卡的全部域adapter、真实提取触发、去重退役、页面及Android Gate尚未完成。W3/W4/W5可并行源码实施；W3部署前须完成运行MCP对齐及固定Core v4功能保全。逐域影子/回滚/权威切换未进行。

## PR #9/#10 复核返修与下游前置（2026-10-05）

两处返修已完成主窗有限源码验收：[交接](handoffs/PR9_PR10_REVIEW_FIXES_MAIN_ACCEPTANCE_20261005.md)、[回执](handoffs/PR9_PR10_REVIEW_FIXES_VALIDATION_20261005.json)。改卡工具绑定真实触发用户消息 sync_id，以 user_via_agent 改写，缺授权说明原因并拒绝；真实日程勾完成再委托改回未完成成功。claude_web 同源版本更新原卡 ID，明确删除清未修改产出、保护用户改卡并提供中文提示；竞态、持久幂等、FTS/ledger/ack 事务及旧映射兼容已覆盖。Flutter 118/118、Core 14/14、相关分析无问题，最终源码哈希稳定；精确 head CI 与合并以任务 PR 回执为准。

W3 切 i_remember 前须先合入生命周期修复。W4 已明确侧键生活事实交 Record Organizer（ADR 决定12）。W7 新增按记录/操作持久化、area 允许“未归类”、切换前关闭该领域启动去重的硬前置；本批隔离候选已实现逐记录JSON行、原子迁移及域去重退役，见本页首节；未合入或部署，不继承基础验收。保护卡来源原话保留（自动审批拒绝额外清空）；旧无基线或多卡歧义保留待处理。本次未部署、升级原库、安装手机或切换业务领域。

## 个人数据中枢：已合入规划与独立窗口（2026-10-05）

正式[ADR](PERSONAL_DATA_HUB_ADR_20261005.md)二十项/C1–C7 已确认。W0 [PR #5](https://github.com/Ritou-Lynx/here-i-am/pull/5)与 happy@5447c5c4 **整个分支**经[PR #6](https://github.com/Ritou-Lynx/here-i-am/pull/6)普通合入 `v3-lab@6508f1ab5ac2ed57155e95047942875f14fa0c47`，2026-10-05 10:14:46Z；PR#6五项 head 检查成功，合并树等于已测候选树，happy为祖先。未同步 D 私人谱系或切换运行服务；后续源码合入状态见本页首节。

用户指定的新窗口均已完成交接，详见[当前派发](handoffs/PERSONAL_DATA_HUB_DISPATCH_NEXT_20261005.md)。W6 `01a10b7f-d9ae-7bd3-9d2e-26944c3c6f94`完成四域字段映射并在直接获批后只读统计：收支卡74/账本92，仅总数差18；Core已有10条登记Android来源companion；i_remember活动0、删除on_phone1。不能据此证明持续上传/当前消费或具体漏记，旧“全部不在Core/全部等手机”推断已纠正。

MCP对齐 `01a10b80-a21c-7a23-b9f3-3a2a4a2423fb`完成受控源码备份、W0 exact候选、125/125、9/9、2/2合成测试和切换/回滚方案。**实际Core为含transcript/replay的固定v4包**，不能直接被W0/W1覆盖；该窗仅请求独立远程MCP停启/账本及外置配置备份/源码入口切换授权，未执行。主窗已只读核实当前库 schema4，副本链通过仍不证明现役 transcript/replay 功能兼容；Core 升级须先保全这些功能。

42项旧失败完成主窗 diff/逐项证据验收，原16文件独立复跑260过/0红/1既有跳；移植到当前v3-lab@6508f1ab的隔离候选同套262过/0红/1既有跳（保留W0两项frontend负例），未新增跳过/屏蔽。WI源码/12测试、WL指令/链接已验收；W6确定映射与MCP字节比对文案各修正后通过有限交接验收。详见[分派验收](handoffs/DISPATCH_ACCEPTANCE_20261005.md)。42修复PR #7已普通合入，W1已联合复验并经PR#8合入；WI/WL/W6/MCP保留独立候选，当前无生产切换、手机安装或真实业务迁移。

## 学习系统：思源为知识库与学习账本，dot 语音带练（2026-10-04）

用户认定不追求 all-in-one：思源（3.8.6，已购第三方同步）作知识本体和学习账本；FlexNote 只用于需要可视化理解的主题，不全量搬入思源内容，教综线保持现状；ChatGPT dot（用户为 Pro）作语音带练前端，用户期待官方后续支持 dot 主动来电，过渡期用 Tasker 模拟来电。Here I Am 自制语音不用于学习；学习单不经 i_core。

已交付 `tools/siyuan_tutor/`（f76da90）：按用户提供的思源 3.8.6 MCP 工具清单编写 Codex 导师指令（账本为思源数据库独立行 + 来源块链接、间隔复习、入账、每天出学习单写入思源与 `today.md`、不删除边界）、dot/GPT voice 语音规则与结果格式、日语科目表和设置说明（Codex 工具白名单、定时 `codex exec`）。思源内置 MCP 的地址与 Bearer API Token 鉴权已在源码核对。纯文档，未构建；账本单元格写法、dot 读写本机文件与语音守规矩程度待用户本机实测。看板改做思源插件（点击跳转原笔记、就地经思源 Agent 提问）尚为提议，未开工。

10-04 已完成日语初始化（账本 12 点）、dot 连电脑与首次通话；按反馈修订语速、纠正记录与链接格式（44d84dd）。全量交接见 [handoffs/LEARNING_SYSTEM_AND_TOOLS_20261005.md](handoffs/LEARNING_SYSTEM_AND_TOOLS_20261005.md)，供生活规划系统等新窗口接手。

## 方向调整：白板停止开发，转向三端串联（2026-10-02）

用户决定白板工作台停止开发：知识库、白板、视频标注与学习改用 FlexNote（终身版，1.1.53 起提供 MCP），由 Codex 接入。Here I Am 收敛为 i_core 上的一条时间线、一个记忆库与一份林埃身份，供 Claude 网页端、手机 App 与可选 ChatGPT 文字端共用；GPT voice 记录不迁移，私密会话不出站。任务与分工见[任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md)；本条只改文档，未改产品源码。

任务 A4 已交付 `tools/flexnote_tutor/`：基于 FlexNote 1.1.56 MCP 工具清单的 Codex 学习导师模板与科目表（教师编·中学语文，求职空间）；需在本机复制到仓库外学习目录使用。B0.1 定为 i_core 先跑在电脑上。 B1/B2 并行开发按[接口约定](CONTINUITY_B1_B2_CONTRACT.md)进行：`tools/i_memory/`（记忆快照+出站策略+只读接口）与 `tools/i_remote_mcp/`（claude.ai 远程 MCP+单用户 OAuth）。 `tools/i_memory/` 已交付：V3 记忆快照导入、出站策略（缺失即 fail closed）与 `openReadModel` 只读接口，合成 fixture 测试通过；真实导出与导入（B1.4）待 Codex 本机执行。 B2.1/B2.2 已交付 `tools/i_remote_mcp/`（远程只读 MCP、单用户 OAuth、`i_context`/`i_recall`、Project 指令，fake readModel 测试通过）；两者已合入主任务分支：补消息级私密关键词、OAuth 回调默认仅限 claude.ai，B1×B2 集成测试通过（共 60 项）；真实导入、私密配置、Funnel 部署与 claude.ai 接入待 Codex 本机执行。claude.ai 已经 https://i.ilynx.date/mcp（Cloudflare 固定隧道）接入并通过两问真人验收；B3 写回见[简报](B3_WRITEBACK_BRIEF.md)与[设计](B3_WRITEBACK_DESIGN.md)，源码已在 claude/b3-writeback 交付。B2.3 实测：claude.ai 经 Funnel `:10000` 无法连接，经 Cloudflare 隧道可完成注册并到达口令页，长期入口改用 Cloudflare 固定隧道 + 自有域名。A 线已由 Codex 本机跑通（教综拆解导入、初始化、5 题冒烟），模板已按反馈修订。

## B3 写回源码交付（2026-10-03，claude/b3-writeback）

按[设计](B3_WRITEBACK_DESIGN.md)交付：`tools/i_remote_mcp` 新增 `i_chat_turn`（每轮写回网页端双方原文到 i_core 时间线，内容对齐去重、漏轮补交、i_core 不可达时本机账本暂存）与 `i_remember`（显式记录只存本机账本，可改可真删；手机经只监听本机的拉取通道 `:47862` 取走，按用户决定无需确认直接进 Record 流程成卡）。OAuth 新增 `i.write`，启用写回后签发 `i.read i.write`，旧令牌需重新授权；Project 指令改为每轮先 `i_chat_turn`。

i_core 新增受限 `external-frontend` 设备身份 `frontend:claude_web`：可提交 user/companion、不能读 feed/ack、不能请求核心回复，不改 schema，不需要 worker 密钥。读取层新增 `messages.auto_share_origins`：列出的前端来源只跳过 ID/哈希放行清单，私密类型、关键词和私密 ID 仍优先；省略时保持旧行为。

修订（同日，Lynx 决定）：`i_chat_turn` 改为每轮两次调用（start 交用户原话并取上下文，end 在回复末尾交回复原文），对话最后一条回复不再丢；漏调轮次照写并带 `frontend_backfill` 补记标记、时间插值；长文本 MinHash 近似去重；返回 `last_recorded`。i_remote_mcp 回归 71/71。部署只需重新合入 i_remote_mcp 文件、重启 MCP、更换 Project 指令；手机端另加“补记”显示。

合成验证：i_remote_mcp 67/67（含真实 i_core 服务与存储 + 真实读取层 + MCP + OAuth 端到端）、i_memory 35/35 通过；i_core 新增 2 项通过，全量仍有 54 项 activity fixture 合同失败，与改动前基线一致。未部署、未接真实数据。待 Codex 本机：合入、policy 开关、i_core 配对窗口 + `pair-core`、手机令牌与 Tailscale Serve、重启、`revoke-all` 与 claude.ai 重新连接、Project 指令、Flutter 来源显示与记录入卡、真人验收。

## B2.3 固定隧道与运行诊断（2026-10-03）

正式入口已从 Funnel 切换到 Cloudflare 固定隧道和自有域名。隧道注册为 Windows 开机自启服务（Auto、LocalSystem），配置和凭据放仓库外；服务运行并建立 4 条边缘连接。remote MCP 保留既有登录自启，public-url 已更新，旧令牌已撤销，现有口令不变。QUIC 可用，未修改代理或 TUN。尚未执行整机重启验收。

本机配置检查：/mcp 返回 401 且挑战头使用新域名，两份 OAuth 元数据返回 200 且 resource/issuer 一致；这不是公网可达性验收。用户确认 Bot Fight Mode/Under Attack 关闭、自定义规则为空、Access 停留首次设置页。公网复测由 Claude 从 tailnet 外完成，当前尚待报告。

tools/i_remote_mcp 新增脱敏 HTTP/RPC JSONL：每行 UTC 时间、固定 UA 家族、已知 callback/resource/Origin 和工具结果摘要；不记录口令、token、原始 UA、body、工具内容或原始异常。协议及 JSON/SSE 行为未变。本分支合成回归 66 项通过；只部署受控 server/diagnostics 文件后，既有运行副本回归 74 项通过，其私密读取层与真实 policy 的文件哈希保持不变。真实配置、凭据、策略、数据库和日志不在提交中。

B2.4 尚未完成：等待公网复测通过，再做正式 connector i 的口令授权、工具允许设置、林埃 Project 与两题真人验收；届时记录 POST authorize/token 和 tools/call 以及仅 JSON 的实用结果。Funnel :10000 仍保留，正式接入成功后再询问用户是否关闭；其他映射未变。

## B1 审核读取层源码交付（2026-10-03）

codex/continuity-b1-local-policy 从 2a27f7d7 同步既有本机通用读取改动：messages.private_message_ids 按 sync_id 排除；消息/卡片正向 ID 清单只允许审核条目；内容 SHA-256 映射拒绝未审核修订。所有允许条件与角色、类型、关键词及私密 ID 等原有限制取交集，不能覆盖私密排除。显式空清单/映射拒绝全部，省略字段兼容旧策略；更新策略须重新打开读取模型。接口与哈希字段顺序见 CONTINUITY_B1_B2_CONTRACT.md 和 tools/i_memory/README.md。

本分支 i_memory / remote MCP 合成回归 74/74 通过：涵盖合法/非法策略、大 ID 清单、未审核新增和内容变更、所有本地读取出口及远程文本/结构化返回。集成测试注入合成身份，避免读取用户身份投影。该验证不代替手机同步、公网访问或 claude.ai 真人验收。

真实 policy、私密关键词、审核 ID/哈希清单、数据库、审批和日志仍只保存在本机；筛查脚本不包含在交付。运行副本与当前工作分支未改动。本分支以读取层同步为范围，不实现 B3 写回；诊断日志在独立 codex/continuity-cloudflare-diagnostics 分支，协作方按所需合并或 cherry-pick。

## 桌面白板工作台暂停（2026-10-02）

用户因整体计划调整，暂停桌面白板工作台开发。工作已停在阶段性收尾状态：

- 源码全部在 `v3-lab`；
- CI 四个阻断作业为绿；
- 无定时任务、PR 订阅、运行中进程或未合并提交。

Goal 1 父 Goal 未正式关闭，真实 App 内长任务体验与生产准备未做。收尾事实、未完项与接续步骤见[工作台暂停收尾](whiteboard-workstreams/WORKBENCH_PAUSE_20261002.md)。AGENTS 中的长任务规则已改为现行的 Ollama fail-closed 描述。

## 白板 AI 验收自动重放（2026-10-02）

Goal 1 P4 真人 Gate 的客观项已写成 `test/acceptance/whiteboard_ai_acceptance_test.dart`：脚本化模型经真实聊天窗口、生产会话组合与默认白板工具、实时画布和文件型 SQLite 重放创建、改正文、标签、移动、选中加宽、撤销顺序、移除不删卡与重启后持久撤销。它随 CI 白板作业每次 push 阻断运行，并已用两次临时改坏验证能拦下历史回归。真实模型行为与主观体验不在此覆盖，见[无人值守验证](UNATTENDED_VERIFICATION.md)。

## 既有测试债清零（2026-10-02）

全量 Flutter 套件此前 20 红（白板以外），已逐个判定：6 处真缺陷修代码（早期更新卡 Material 断言、设置面板水波被遮、头像把错误响应当 SVG、输入框窄屏溢出、英文合并气泡丢空格、记忆检索同义词缺「做完」「换了」），其余为过时测试按当前设计更新。两项 outbox 文件锁测试只在 Windows 语义下成立，Linux 跳过并由 Windows CI 作业运行。CI 的 `Flutter full suite (Linux)` 改为阻断。本地全量 2569 过、18 跳、0 红。

## 验证规则（2026-10-02）

用户确认后，AGENTS 与协作协议改为机器优先的四层验证，详见[无人值守验证](UNATTENDED_VERIFICATION.md)：CI 对每个候选 SHA 自动重跑并以其结果为证据，自动场景失败不中止，真人只异步看口吻、手感、视觉并按受影响路径沿用结论。无人值守环境（专用测试机、云端 agent、CI，限合成数据）有常设授权；真实数据、合入 `v3-lab`、发布与生产启用仍需询问。

## P6 长任务改走 Ollama（2026-10-02）

用户确认长任务改用 Ollama 纯文本执行，简化优先。生产 `WorkbenchRuntimeTaskQueueTool.production()` 默认使用应用内 Ollama 网关：每次尝试只发一个不带工具的 `/api/chat` 流式请求，不再经过 Codex CLI 文字 profile 和原生隔离，也没有 UAC 弹窗。暂停、取消、宿主退出在进程内中断，停止可确认。未设置 `HIA_TASK_OLLAMA_MODEL` 或配置不安全时 fail-closed：开始被拒绝，任务保持 pending。配置方法与边界见 [P6 Ollama 交接](whiteboard-workstreams/P6_OLLAMA_TEXT_TASKS_20261002.md)。

新增 12 项网关测试（本地假 Ollama 走真实 HTTP 流，配合真实执行引擎与内存库），相邻回归 494 过 11 跳。真实模型检查 `Ollama live check` 已在 GitHub runner 上通过：用真 Ollama 与 `qwen2.5:1.5b` 经生产网关跑完一个真实长任务，3 秒完成，结果精确为 1–30。云端作业只能手动触发，需仓库 secret `OLLAMA_API_KEY`。旧原生隔离链路与 P6-R7 验收入口保留但不在生产路径上；真实 App 内长任务体验尚待真人异步查看。

## 无人值守验证起步（2026-10-02）

用户确认把验收从"人守在电脑前"改为"机器自动跑、人异步看主观项"。第一步新增 GitHub Actions `CI`（`.github/workflows/ci.yml`）：Linux 阻断运行白板 / 工作台 Flutter 套件与平台无关 Bridge Node 测试，全量 Flutter 测试仅提示既有测试债；Windows 运行构建前关键检查、Debug 构建和 4 个 hermetic 白板集成测试，截图上传为产物。仓库公开，GitHub 托管 runner 不占本机。

同批修复 3 个与平台无关的红测试：字体测试对齐 2026-09-04 改用霞鹜文楷的许可决定（视觉规范同步），联网冒烟测试改为 `HIA_NETWORK_SMOKE=1` 显式开启，图片导入测试改用真实时间上限。产品行为未变。

CI 首跑（`c6eccf5`）：Linux 阻断与 Bridge 作业通过；Windows 构建前关键检查与 Debug 构建通过，4 个集成测试 3 过，UI-0 三视口截图作为产物上传。失败的交互回归测试仍在点击分组名称，而名称区域已改为拖动手柄，已改为点击折叠按钮。CI 二跑（`c45f599`）全部阻断作业通过，Windows 4/4 集成测试通过；全量套件暴露的白板列表排序不稳定已定位为同一毫秒创建时顺序不确定，查询加插入顺序兜底并补确定性测试。CI 三跑（`d1ecef5`）全部阻断作业通过；全量套件 2548 过、18 跳、20 红，均为白板以外的既有测试债（含 `input_sheet_test` 一个 10 分钟超时），不阻断。

## GitHub 同步完成（2026-10-01）

原仓库 `Ritou-Lynx/here-i-am` 的默认分支 `v3-lab` 已合入[整合 PR #1](https://github.com/Ritou-Lynx/here-i-am/pull/1)，整合提交为 `4520590a4f1eaa75ee514be3ea2ab320645ae617`。GitHub PR Policy Preflight 通过；其高风险分类来自本次大范围历史文件整合，已有人工范围复核与独立凭据审计，没有拒绝项。

已从 GitHub 完整新 clone 演练其他设备接入：分支和整合 SHA 一致，完整 fsck 通过，130 个受控源码哈希及13个公开保留文件 blob一致，提交检查可安装，未公开的本地/私人检查点对象不存在。正式开发副本的 v3-lab 跟踪 origin/v3-lab，正常 push 地址已恢复；本机具体路径见原交接，各设备使用自己的目录。

其他远端历史分支与旧本地检查点保留；日常集成集中 v3-lab。新设备按[多设备协作说明](MULTI_DEVICE_GITHUB_WORKFLOW.md)重新 clone，旧私人谱系目录继续留档。源码协作恢复不迁移真实账户数据，也不启用生产执行。


## 单一 GitHub 协作谱系

2026-10-01：用户授权恢复单一 GitHub 仓库、多设备源码协作。唯一仓库为 `Ritou-Lynx/here-i-am`，默认集成分支为 `v3-lab`；从公开净化基线 `3856fc7f` 重新整理待公开文件层，不推送未净化的本地检查点。

公开准备已复核凭据、私人资料与素材边界：历史文档只保留技术证据摘要，消息索引、真人健康值与生活引语留本机；13 个原公开保留文件的 Git blob 不变。130 个已验源码保持 SHA-256。旧 Memex globalEarly/cnEarly 定时发布工作流移除；没有建立新的安装包发布入口。

其他设备按[多设备协作说明](MULTI_DEVICE_GITHUB_WORKFLOW.md)完整 clone 并安装提交检查。原私人主树、未公开检查点和 T7 恢复点保留；真实数据库、账户、签名、原始设备回执与迁移审计不进入 GitHub。

## 验证与执行边界

既有源码专项和独立 Windows 构建/启动结果见[本地开发交接](LOCAL_DEVELOPMENT_20261001.md)。原本机构建绑定源码检查点 `339b6bc7`；重新整理公开提交只改文档、忽略规则和旧自动发布入口，没有改变产品源码。

生产长任务仍拒绝执行，活动诊断默认关闭；真实账户迁移、真人验收、减弹窗与生产准备未由源码同步完成。同步是否完成以 GitHub 默认分支和本机复核回执为准。
