## 2026-10-03 — B3 手机私有通道上线与候选安装

**通道**：经现场确认将 Cloudflare 指标移至 47864，实际服务 PID/loopback 验证通过；公网 ingress 仍只指向 47860。
**网络**：Tailscale Serve 新增 HTTPS :47863 → 127.0.0.1:47862，仅 tailnet；无新 Funnel，现有核心及其他映射保持不变。
**服务**：手机令牌已签发，原文仅进程内存及本机窗口；停服 revoke-all 后恢复常驻，写回与手机监听中文日志确认，本机/公网 scopes 均 i.read/i.write，手机无令牌 401。
**安装**：Lynx 明确授权候选 3069115d 及既定 APK 哈希；USB 断连后重新连接重试成功，专用包已安装并启动，进程存活，未读取手机聊天/数据库。
**未完**：手机令牌保存及 HTTPS 拉取已由用户确认“已同步，暂无新记录”；首次网络失败因手机 Tailscale 未运行，连接后通过。claude.ai 接入及六项真人 Gate 待继续。
**边界**：只提交技术结果；令牌、真实策略、数据库、配置、日志和设备回执保持本机。候选与结果见 docs/development/B3_LOCAL_ROLLOUT_20261003.md。

---

## 2026-10-03 — B3 本机写回部署与 Flutter 拉取候选

**合入**：codex/b3-writeback-local-20261003 合入 2d92a8d7；受控运行源码部署，读取层仅换行差异经用户接受，policy 开关及 openReadModel 检查完成。
**核心**：保留 schema 4，移植 B3 权限补丁至新固定包，经确认切换入口并一次性配对；常驻不带 worker 密钥，前端 feed 读取拒绝。
**远程**：写回启用，旧 OAuth 令牌在服务停止期间撤销并重新加载；本机及公网元数据 scopes 为 i.read/i.write，Cloudflare ingress 仅指向 47860。
**Flutter**：网页端来源、created_at_ms/server_sequence 排序、无回复生成、前台同步；安全存储记录通道、直接 Organizer 入卡、修订/删除/ACK 与持久游标幂等。
**验证**：Node 专项 125 项；schema 4 核心候选 25 项及启动器 9 组；Flutter 专项与相邻回归 64 项通过。critical fixes 3/3，JNI 独立 staging 修复后 hereIAmV3 debug 构建成功，包名核验通过。
**未完**：47862 被 Cloudflare 指标占用；需电脑现场授权的通道处理、令牌交付和物理安装暂缓，claude.ai 重连与六项真人 Gate 未执行，分别记录。
**边界**：未 push；真实数据库、策略、凭据、签名与日志不提交。结果及验收状态见 docs/development/B3_LOCAL_ROLLOUT_20261003.md。

---

## 2026-10-03 — B3 写回：i_chat_turn / i_remember

**交付**：i_remote_mcp 新增 `i_chat_turn`（每轮写回双方原文，内容对齐去重、漏轮补交、本机账本重试）与 `i_remember`（本机账本可真删，手机经本机拉取通道取走直接入卡）；OAuth 新增 `i.write`，需重新授权；Project 指令改为每轮先 `i_chat_turn`。
**i_core / 读取层**：新增受限 `external-frontend` 设备身份（可写 user/companion、不能读 feed、不触发回复，不改 schema）；policy 新增 `messages.auto_share_origins`，只绕过放行清单，私密规则优先。
**决定**：Lynx 选定前端身份路径、记录只存本机可真删、claude_web 默认出站过滤关键词、记录无需确认直接入卡。设计见 docs/development/B3_WRITEBACK_DESIGN.md。
**验证**：i_remote_mcp 67/67、i_memory 35/35 通过（含真实 i_core + 读取层 + MCP + OAuth 合成端到端）；i_core 新增 2 项通过，全量 54 项 activity fixture 失败为既有基线（改动前同为 180/54）。
**未完**：本机部署、配对、policy 开关、claude.ai 重新授权与 Project 指令、Flutter 显示与记录入卡、真人验收由 Codex 本机执行。

---

## 2026-10-03 — B2.3 固定隧道部署与脱敏日志

**交付**：正式 remote MCP 切换到自有域名的 Cloudflare 固定隧道；隧道由 Windows Auto/LocalSystem 服务运行，MCP 保留登录自启。旧令牌已撤销，口令不变。
**诊断**：HTTP/RPC 每行增加 UTC 时间与固定 UA 家族；授权 callback/resource/Origin 和工具结果只记白名单摘要，不记凭据、原始 UA、参数、内容或异常。OAuth/MCP 协议行为未变。
**验证**：本分支合成回归 66 项通过，实际运行副本回归 74 项通过；本机 401 挑战头与两份 200 元数据均使用新 issuer。隧道服务运行、4 条边缘连接；未做重启验收。
**边界**：真实配置、凭据、数据库、策略与日志均留本机；既有私密读取层保留。公网复测、正式 claude.ai 授权与两题真人验收待完成，Funnel 及其他映射暂留。

---

## 2026-10-03 — B2.3 入口 A/B：Funnel 不通，改 Cloudflare 固定隧道

**现象**：claude.ai 经 Tailscale Funnel `:10000` 多次 "Couldn't reach"，同期 12 国公共节点均可达，服务端规范检查无缺项。
**对照**：同一服务经 Cloudflare 临时隧道（443）完成 POST /register 201 与口令页，测试实例与隧道已关闭。
**决定**：长期入口用 Cloudflare 固定隧道 + 自有域名；Funnel 不再作 claude.ai 入口。纯文档，未改代码。

## 2026-10-03 — B1 本机审核读取层源码同步

**交付**：从约定基线 2a27f7d7 在 codex/continuity-b1-local-policy 分支同步私密消息 ID、消息/卡片正向 ID 清单与内容 SHA-256 放行。导出纯哈希函数供本机审核复用。
**行为**：私密排除优先；显式空清单/映射全部拒绝；未审核新增 ID 或已放行 ID 的内容修订不出站；字段省略兼容旧策略。更新 policy 后须重新打开模型。
**验证**：i_memory 与 remote MCP 合成回归 74/74 通过，覆盖大清单、所有读取出口及远程文本/结构化投影；集成测试显式使用合成身份。
**边界**：仅同步通用代码、合成测试和接口说明，真实 policy、关键词、ID/哈希清单、数据库、审批、日志与筛查脚本均不提交；既有正式服务和当前工作分支不变，B3 写回未实现。

---

## 2026-10-02 — B1×B2 整合复核 + 学习导师 A6 修订

**整合**：合入 `tools/i_memory/` 与 `tools/i_remote_mcp/` 两个并行会话；新增消息级 `private_keywords`；OAuth 回调默认只收 claude.ai（额外回调走环境变量），修复注册校验回调参数错位导致的 500。
**验证**：新增 B1×B2 集成测试（真实读取层 + MCP + OAuth，私密不出站）；`node --test` 60 项全过。
**A6**：按 Codex 冒烟反馈修订 `STUDY_AGENTS.md`（题卡作答、重做、不会≠答错、先定位再检索、位置类型区分）。
**未完**：B0.2 私密规则、B1.1/B1.4 真实导入、B2.3 Funnel 部署、B2.4 claude.ai 接入由本机执行。

---

## 2026-10-02 — 任务 B2.1/B2.2：claude.ai 远程只读 MCP

**交付**：`tools/i_remote_mcp/`：Streamable HTTP MCP（`/mcp`，2025-06-18/03-26）+ 单用户 OAuth 2.1（DCR、口令页、PKCE S256、refresh 轮换、令牌只存哈希、口令限速）；只开放 `i_context`、`i_recall`，输出白名单投影。
**数据**：经 `tools/i_memory/i_memory_read.mjs` 的 `openReadModel` 懒加载读取；测试用 fake readModel，36 项 `node --test` 通过。另交付 Project 指令 `CLAUDE_PROJECT_INSTRUCTIONS.md`。
**需实测**：claude.ai 回调/`resource`/Origin 实际值、仅 JSON 无 SSE 是否被接受、Funnel 部署（B2.3）。未构建 App。

---

## 2026-10-02 — 任务 B1.2/B1.3：i_memory 记忆快照与出站策略

**交付**：`tools/i_memory/`：V3 记忆卡快照导入（默认 dry-run，整体替换，FTS5 trigram）、`policy.json` 出站策略（fail closed）、`openReadModel` 只读接口。
**验证**：`node --test tools/i_memory/*.test.mjs` 18 项通过，全部合成 fixture；未改 i_core 与 lib，未碰真实数据。
**未完**：B1.4 真实导出、导入与私密配置由 Codex 在本机执行，步骤见 README。

---

## 2026-10-02 — 任务 A4：FlexNote 学习导师模板

**交付**：`tools/flexnote_tutor/`：Codex 学习导师指令、科目表与设置说明，按 FlexNote 1.1.56 实际 MCP 工具编写（已核对工具名）。
**约定**：从知识库现出新题并注明出处；学习记录卡 + 标签属性记薄弱点和掌握度；只新建、不改原笔记、不删除。
**限制**：MCP 只操作当前打开空间、仅本机；教综拆解资料待导入（A4.5），不进 GitHub。纯文档，未构建。

---

## 2026-10-02 — 方向调整：白板停开发，FlexNote × 三端串联任务单

**决定**：白板工作台停止开发，知识库与学习改用 FlexNote + Codex（MCP）；Here I Am 只保留时间线、记忆与身份。
**任务单**：FlexNote 接入 Codex（A），Claude 网页 × 手机 App ×可选 ChatGPT 串联（B0–B5），按 [你]/[Codex]/[Claude] 分工。
**边界**：轻量通道，仅本人使用；私密会话不出站；真实数据与令牌不进 GitHub。纯文档，未构建。
**交接**：[任务单](docs/development/PLAN_20261002_FLEXNOTE_AND_THREE_FRONTEND_CONTINUITY.md)。

---

## 2026-10-01 — GitHub 单仓库协作恢复完成

**结果**：原 here-i-am 仓库的整合PR #1已合入默认v3-lab，GitHub自动检查通过；正式开发副本恢复正常push并跟踪远端。
**净化**：公开提交重新接在3856谱系；私人文档原文和旧本地检查点未进入祖先，作品README/截图/许可保留。
**验证**：从GitHub全新完整clone、fsck、130源码哈希、13公开文件blob、提交检查安装通过；没有旧私人检查点对象。
**保留**：原私人主树、工作电脑归档、T7恢复点、旧本地及远端历史分支保留；日常集成统一v3-lab。
**边界**：真实数据迁移、真人Gate和生产准备未开展；旧Memex每日发布入口移除，没有新安装包自动发布。
**交接**：[多设备操作](docs/development/MULTI_DEVICE_GITHUB_WORKFLOW.md)。

---

## 2026-10-01 — 单一 GitHub 协作版本公开准备

**目标**：复用原 here-i-am 仓库，以 v3-lab 汇集多设备源码成果；用户已授权推送与合入。
**做法**：从3856净化基线重新整理未公开文件层，去除历史文档中的真实消息索引、健康值与生活引语；原私人记录及检查点保留本机/T7。
**验证**：130受控源码与13公开保留文件不变；产品源码未改，沿用原候选的专项和独立构建证据，不提升为新真人Gate。
**协作**：补完整clone、任务分支、提交检查与换设备操作；共享本机验证/数据库忽略规则。
**发布边界**：移除旧Memex globalEarly/cnEarly每日自动发布流程；不新建安装包发布入口，不启用生产。
**交接**：[多设备源码协作](docs/development/MULTI_DEVICE_GITHUB_WORKFLOW.md)。

---

## 2026-10-01 — 本地版本固定与Windows启动检查完成

**目标**：以C盘副本、本地v3-lab和源码提交339b6bc7固定唯一源码开发落点。
**验证**：130受控源码在提交/快进后仍同哈希；构建前关键修复3/3，Windows debug构建exit0；独立数据/测试桌面中聊天页面、实际PNG与正常退出0通过，无未处理错误。
**边界**：原D源码与T7恢复点保留；未推送、未迁入真实账户数据、未开启生产。前三轮检查器未通过记录保留，最终同产物通过；既有lint/文档空白不改写已验字节。
**交接**：[本地开发结果](docs/development/LOCAL_DEVELOPMENT_20261001.md)。

---
## 2026-10-01 — 正式本地开发版本收敛

**目标**：按用户确认将整合成果固定为本地提交，以C盘副本和本地v3-lab作为唯一源码开发落点。
**做法**：复核717个迁入文件、130个受控源码和私密排除边界；补当前技术交接，旧SESSION_HANDOFF标为历史。
**决策**：原D主树与T7恢复点保留；仅本地提交、同谱系快进，不推送。Windows构建与独立数据启动检查随后记录，生产准备保持暂停。
**交接**：[本地开发说明](docs/development/LOCAL_DEVELOPMENT_20261001.md)。

---
## 2026-10-01 — 净化谱系源码整合完成

**做法**：从净化3856fc7f建立独立NTFS副本，选择性迁入有效源码和文档；保留公开作品内容与许可，不接回私有历史。
**验证**：104+26受控文件同哈希；105/439/232/77专项及隔离组合通过。桌面分析0error，51条既有lint与原源码镜像相同，0新增。
**决策**：固定受控字节，安装本clone提交检查，本机审计与测试输出默认不提交。生产准备仍暂停，未commit/push/构建/安装/发布。
**交接**：[迁移说明](docs/development/SANITIZED_MIGRATION_20261001.md)。

---
