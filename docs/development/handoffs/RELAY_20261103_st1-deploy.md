<!-- relay:contract v1 -->
## 目标
把现役 MCP 换成带 ST1 学习工具的候选（#87 已合并），让 ChatGPT 和 Claude 能读今天的学习单并写回【学习结果】。Core 不换。

## 完成标准
- [ ] 脚本轮 `tools/relay_scripts/study/st1-deploy.ps1`（mode=write）全部步骤 ok：预检 → 维护工具副本 → 候选（server a0bd0491，其余五个文件不变，受保护 ACL）→ 写入 study.json 并用候选只读自检 → update-mcp-source 登记新任务（停用）→ switch-login-task 切换（允许回滚）。
- [ ] 新任务 `HereIAm-iCoreSchema6-st1-study-20261103` Running，旧任务 Disabled 保留。
- [ ] 云端经 i MCP 看到 study_* 四个工具；用户在 ChatGPT 里试一次“开始今天的英语练习”，结束后 inbox 出现新文件。

## 允许修改的路径
- tools/relay_scripts/study/
- docs/development/handoffs/RELAY_20261103_st1-deploy.md、DEVLOG.md

## 不做 / 边界
- 不换 Core 包，不碰飞书凭据、lark-cli、账本、食物凭据和配对凭据。
- study.json 只新建（已存在且内容相同时保留），不改 MCP 状态目录里的其他文件。
- 只改 MCP 的 working_directory/source_files（update-mcp-source 限定的字段）。
- 输出不含令牌、本机路径、SID 或学习内容。

## 验证命令
- 脚本轮输出逐行 ok；云端 i MCP tools/list 含 study_today、study_source、study_progress、study_result。

## 需要真人的部分
- 在脚本轮评论上点 👍（会短暂停服，约 1 分钟）。
- 在 ChatGPT 里试一次练习并写回结果。

## 部署记录（11-03 至 11-04）
- 第 1 轮：候选目录、study.json 和停用状态的新任务都已就绪。停旧会话时宿主收尾超时，被强制结束（child 已干净关库），宿主以退出码 1 退出，切换停在 stop_old，服务中断。
- 第 2 轮：补救脚本里 tools 副本的目录名写错（tools_copy_missing），什么都没改。
- 第 3 轮：新 Core 因为上一次收尾不干净，启动时先做了自动崩溃恢复（16:37，成功）；但 switch-login-task 的就绪等待每次循环都会检查待恢复标记，看到恢复期间的临时标记就判失败。回滚停新会话时报 mcp_receipts_not_paired（新会话的 MCP 还没启动，会话本身是干净退出的），最后由 r2 重启了旧任务。
- 第 4 轮（只读，st1-inspect）：旧任务在跑、新任务停用、无待恢复标记，lifecycle 为 listening。
- 第 5 轮（st1-retry，等过恢复标记，失败回退）：旧会话干净停止，新任务直接就绪，用时 81 秒。新任务 HereIAm-iCoreSchema6-st1-study-20261103 在跑（server a0bd0491），旧 n2-food 任务已停用。云端 i MCP 已列出 study_*，study_today 返回 2026-11-04 学习单（is_today true）。
- 遗留：Wait-Schema6LoginReady 把待恢复标记当成失败，这是维护工具的缺陷，崩溃之后的下一次切换都会撞上，另开 PR 修。
