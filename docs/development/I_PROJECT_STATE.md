# 林埃的项目状态

## 方向调整：白板停止开发，转向三端串联（2026-10-02）

用户决定白板工作台停止开发：知识库、白板、视频标注与学习改用 FlexNote（终身版，1.1.53 起提供 MCP），由 Codex 接入。Here I Am 收敛为 i_core 上的一条时间线、一个记忆库与一份林埃身份，供 Claude 网页端、手机 App 与可选 ChatGPT 文字端共用；GPT voice 记录不迁移，私密会话不出站。任务与分工见[任务单](PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md)；本条只改文档，未改产品源码。

任务 A4 已交付 `tools/flexnote_tutor/`：基于 FlexNote 1.1.56 MCP 工具清单的 Codex 学习导师模板与科目表（教师编·中学语文，求职空间）；需在本机复制到仓库外学习目录使用。B0.1 定为 i_core 先跑在电脑上。 B1/B2 并行开发按[接口约定](CONTINUITY_B1_B2_CONTRACT.md)进行：`tools/i_memory/`（记忆快照+出站策略+只读接口）与 `tools/i_remote_mcp/`（claude.ai 远程 MCP+单用户 OAuth）。 `tools/i_memory/` 已交付：V3 记忆快照导入、出站策略（缺失即 fail closed）与 `openReadModel` 只读接口，合成 fixture 测试通过；真实导出与导入（B1.4）待 Codex 本机执行。 B2.1/B2.2 已交付 `tools/i_remote_mcp/`（远程只读 MCP、单用户 OAuth、`i_context`/`i_recall`、Project 指令，fake readModel 测试通过）；两者已合入主任务分支：补消息级私密关键词、OAuth 回调默认仅限 claude.ai，B1×B2 集成测试通过（共 60 项）；真实导入、私密配置、Funnel 部署与 claude.ai 接入待 Codex 本机执行。claude.ai 已经 https://i.ilynx.date/mcp（Cloudflare 固定隧道）接入并通过两问真人验收；B3 写回见[简报](B3_WRITEBACK_BRIEF.md)，另开会话执行。B2.3 实测：claude.ai 经 Funnel `:10000` 无法连接，经 Cloudflare 隧道可完成注册并到达口令页，长期入口改用 Cloudflare 固定隧道 + 自有域名。A 线已由 Codex 本机跑通（教综拆解导入、初始化、5 题冒烟），模板已按反馈修订。

## B2.3 固定隧道与运行诊断（2026-10-03）

正式入口已从 Funnel 切换到 Cloudflare 固定隧道和自有域名。隧道注册为 Windows 开机自启服务（Auto、LocalSystem），配置和凭据放仓库外；服务运行并建立 4 条边缘连接。remote MCP 保留既有登录自启，public-url 已更新，旧令牌已撤销，现有口令不变。QUIC 可用，未修改代理或 TUN。尚未执行整机重启验收。

本机配置检查：/mcp 返回 401 且挑战头使用新域名，两份 OAuth 元数据返回 200 且 resource/issuer 一致；这不是公网可达性验收。用户确认 Bot Fight Mode/Under Attack 关闭、自定义规则为空、Access 停留首次设置页。公网复测由 Claude 从 tailnet 外完成，当前尚待报告。

tools/i_remote_mcp 新增脱敏 HTTP/RPC JSONL：每行 UTC 时间、固定 UA 家族、已知 callback/resource/Origin 和工具结果摘要；不记录口令、token、原始 UA、body、工具内容或原始异常。协议及 JSON/SSE 行为未变。本分支合成回归 66 项通过；只部署受控 server/diagnostics 文件后，既有运行副本回归 74 项通过，其私密读取层与真实 policy 的文件哈希保持不变。真实配置、凭据、策略、数据库和日志不在提交中。

B2.4 尚未完成：等待公网复测通过，再做正式 connector i 的口令授权、工具允许设置、林埃 Project 与两题真人验收；届时记录 POST authorize/token 和 tools/call 以及仅 JSON 的实用结果。Funnel :10000 仍保留，正式接入成功后再询问用户是否关闭；其他映射未变。

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
