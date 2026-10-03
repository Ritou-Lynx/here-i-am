# 林埃的项目状态

## 方向调整：白板停止开发，转向三端串联（2026-10-02）

用户决定白板工作台停止开发：知识库、白板、视频标注与学习改用 FlexNote（终身版，1.1.53 起提供 MCP），由 Codex 接入。Here I Am 收敛为 i_core 上的一条时间线、一个记忆库与一份林埃身份，供 Claude 网页端、手机 App 与可选 ChatGPT 文字端共用；GPT voice 记录不迁移，私密会话不出站。任务与分工见[任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md)；本条只改文档，未改产品源码。

任务 A4 已交付 `tools/flexnote_tutor/`：基于 FlexNote 1.1.56 MCP 工具清单的 Codex 学习导师模板与科目表（教师编·中学语文，求职空间）；需在本机复制到仓库外学习目录使用。B0.1 定为 i_core 先跑在电脑上。 B1/B2 并行开发按[接口约定](CONTINUITY_B1_B2_CONTRACT.md)进行：`tools/i_memory/`（记忆快照+出站策略+只读接口）与 `tools/i_remote_mcp/`（claude.ai 远程 MCP+单用户 OAuth）。 `tools/i_memory/` 已交付：V3 记忆快照导入、出站策略（缺失即 fail closed）与 `openReadModel` 只读接口，合成 fixture 测试通过；真实导出与导入（B1.4）待 Codex 本机执行。 B2.1/B2.2 已交付 `tools/i_remote_mcp/`（远程只读 MCP、单用户 OAuth、`i_context`/`i_recall`、Project 指令，fake readModel 测试通过）；两者已合入主任务分支：补消息级私密关键词、OAuth 回调默认仅限 claude.ai，B1×B2 集成测试通过（共 60 项）；真实导入、私密配置、Funnel 部署与 claude.ai 接入待 Codex 本机执行。claude.ai 已经 https://i.ilynx.date/mcp（Cloudflare 固定隧道）接入并通过两问真人验收；B3 写回见[简报](B3_WRITEBACK_BRIEF.md)与[设计](B3_WRITEBACK_DESIGN.md)，源码已在 claude/b3-writeback 交付。B2.3 实测：claude.ai 经 Funnel `:10000` 无法连接，经 Cloudflare 隧道可完成注册并到达口令页，长期入口改用 Cloudflare 固定隧道 + 自有域名。A 线已由 Codex 本机跑通（教综拆解导入、初始化、5 题冒烟），模板已按反馈修订。

## B3 手机同步与来源提示修复候选（2026-10-03）

限定确认上线后，只读核对当前安装待发送队列为0，核心网页消息均已入手机、游标追平；用户反馈除来源标签外无其他问题。来源数据完整，标签使用全局日间主题暗字、手机聊天背景为深色，已改为聊天页既有文字色，并补来源变化刷新比较。连接仍出现阶段性超时；新增共享同步真实失败传播及仅连接超时一次退避重试，稳定POST正文，不重试401/409/协议错误或一次性配对。

同步专项及相邻回归39项、标签/桌面回归10项共49项通过，旧APK保留并核对哈希。新候选尚无构建或安装结果；当前手机仍绑定3069115d及原APK哈希，来源提示及同步修复待新候选真机复验，其他五项真人Gate尚未执行。

## B3 限定确认修复上线与真人复验（2026-10-03）

第一项首次真人验收未通过：用户报告聊天没有自动同步，核心手动同步报 immutable_message_conflict。只读内存核对确认手机72条旧outbox副本已在历史导入中，正文/角色/类型/资产一致，原设备映射及部署前核心备份摘要也一致；历史导入转换了设备、序号、整秒时间和附注，严格提交失败阻断了拉取。

新增受本机私有清单约束的精确双摘要确认，序号绑定持久保存在既有core_metadata；仅确认已存在历史用户消息，不改变原消息、事件或回复任务，其他冲突保持拒绝。代码19项专项及相邻回归共146项通过，独立审计通过；新的schema4固定候选44项通过、九文件清单核验通过。自动审批首次拒绝持久写入后，用户明确批准72条限定确认及固定包切换。私有清单已限制本机访问，既有core_metadata已登记72条且逐项吻合；原消息72条摘要复核未变。现役包已切为b3-v4-replay-confirmation-20261003，清单SHA256为`d21be69b0b128360780883a27ce1b4c905a4fa49f5e7c23805418cefd67e3312`；健康检查schema4、worker关闭，旧包及切换前备份保留。该核心修复阶段Flutter源码/APK未变；随后手机同步修复见上节，六项真人结果继续分别记录，不计整体通过。

## B3 本机部署与 Flutter 候选（2026-10-03，codex/b3-writeback-local-20261003）

已合入 `2d92a8d7` 并完成受控运行源码部署；读取层 CRLF-only 差异经用户确认，新增 auto_share_origins 后 openReadModel 成功。初次部署核心保留 schema 4，仅移植 B3 八个权限补丁至固定包，用户确认切换后完成一次性 external-frontend 配对；现役限定确认包见上节；常驻不带 worker 密钥，前端读取聊天 feed 返回 403。旧固定包保留。

remote MCP 已启用写回，旧 OAuth 令牌在停服期间撤销并重新启动加载；本机及公网元数据均支持 `["i.read","i.write"]`。Cloudflare ingress 只指向 47860。用户现场确认后，Cloudflare 指标已移至 47864，并核对服务 PID/loopback；手机通道使用 127.0.0.1:47862，Tailscale Serve HTTPS :47863 仅 tailnet，未启用新 Funnel，现有映射保持不变。手机通道无令牌返回 401，两个中文启动日志已确认。

Flutter 已接入网页端标签、创建时间/服务序列排序、外部消息不触发回复、前台同步和 Daily Dreaming；显式网页记录经安全存储配置、Record Organizer 直接入卡，按 note_id/revision 修订、删除、ACK 并持久化游标。PersonaChatMessages 仅新增两个 nullable 排序字段，schema 61，生成代码由 build_runner 生成。合成测试与既有相邻回归 64 项通过；Node 专项 125 项、核心固定包 25 项及启动器 9 组通过；每次构建前 critical fixes 3/3；JNI 独立 staging 修复后 hereIAmV3 debug 构建成功，包名 com.memexlab.hereiam.v3，APK SHA256 为 `0d34095ccc488d68d7058e2127baf78c40c34bee93b5c832032dc2597702eeee`。最终 main/依赖分析零错误，main 25 项既有诊断，新增同步块无诊断。

手机令牌已签发，只在本机窗口显示；用户已保存并实测 HTTPS 拉取“已同步，暂无新记录”。首次同步失败因手机 Tailscale 未运行，连接后通过；令牌框不回显是预期安全行为。Lynx 已明确授权候选 3069115d 及既定 APK 哈希；专用脚本更新安装成功，启动进程存活，未读取手机内容。用户已确认完成 claude.ai 重连、四工具始终允许及 Project 指令替换；第一项首次真人验收发现核心手动同步报 immutable_message_conflict；旧 outbox 与历史导入差异已核对并按明确授权启用限定确认修复，自动聊天拉取待手机复验，其余五项尚未执行。详细分项状态见[本机部署结果](B3_LOCAL_ROLLOUT_20261003.md)。备份恢复后需按现有页面提示重启 App，以重新绑定记录导入器数据库。这些源码和合成证据不等于真人验收。

## B3 写回源码交付（2026-10-03，claude/b3-writeback）

按[设计](B3_WRITEBACK_DESIGN.md)交付：`tools/i_remote_mcp` 新增 `i_chat_turn`（每轮写回网页端双方原文到 i_core 时间线，内容对齐去重、漏轮补交、i_core 不可达时本机账本暂存）与 `i_remember`（显式记录只存本机账本，可改可真删；手机经只监听本机的拉取通道 `:47862` 取走，按用户决定无需确认直接进 Record 流程成卡）。OAuth 新增 `i.write`，启用写回后签发 `i.read i.write`，旧令牌需重新授权；Project 指令改为每轮先 `i_chat_turn`。

i_core 新增受限 `external-frontend` 设备身份 `frontend:claude_web`：可提交 user/companion、不能读 feed/ack、不能请求核心回复，不改 schema，不需要 worker 密钥。读取层新增 `messages.auto_share_origins`：列出的前端来源只跳过 ID/哈希放行清单，私密类型、关键词和私密 ID 仍优先；省略时保持旧行为。

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
