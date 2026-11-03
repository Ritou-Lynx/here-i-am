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
