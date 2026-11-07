<!-- relay:contract v1 -->
## 目标
给 here-i-am 远程 MCP 加一组“学习”工具，让 ChatGPT 和 Claude（以及她们背后的林埃）能直接读到今天的学习单、飞书笔记和学习进度，练完把【学习结果】写回家里的学习目录 inbox，次日学习导师自动入账。用户不用再点链接、贴结果。

## 工具（ST1）
| 工具 | scope | 做什么 |
|---|---|---|
| `study_today` | i.read | 返回今天学习单（today.md）的日期和指定科目那一节，或整份；学习单不是今天的就如实返回日期，让 AI 提醒用户 |
| `study_source` | i.read | 按标题返回一篇飞书笔记正文（来自导师 pull 的 `state/sources.json`），单篇最多 20000 字；不传标题时返回笔记标题列表 |
| `study_progress` | i.read | 各科知识点数、掌握/模糊/未学、今日到期数、最近 7 天正确率、错次前 10 的薄弱点（来自 `state/ledger.json`） |
| `study_result` | i.write | 写入一段【学习结果】（≤ 8000 字，须以“【学习结果】YYYY-MM-DD 科目”开头），落到学习目录 `inbox\YYYY-MM-DD-HHMMSS-<前端>.md`，只新建不覆盖 |

工具说明里写清出题方式：先调 `study_today` 取当天要点，必要时 `study_source` 读原笔记，用互动题一题一题练，结束时按 TUTOR_RULES 的【学习结果】格式调 `study_result`。

## 开放范围
- claude（主线）和 chatgpt_web：四个工具全开。
- gemini_web、antigravity、sesame：暂不开（Gemini 工具调用之前实测不生效；以后成熟了只改白名单）。
- 学习目录路径来自 MCP 状态目录里的 `study.json`（`{"format":"study-v1","study_dir":"..."}`，由部署脚本写入）；没有这个文件就不列出学习工具，生产行为与现在完全一致。

## 完成标准
- [ ] 主线 `domain_tools.mjs` / `server.mjs` 加学习工具；`chatgpt_candidate.mjs` 在 FOOD 之后加 `STUDY_PATCHES`（mainline + legacy），正反向补丁字节一致。
- [ ] 新测试：路径只能落在 study_dir 内（拒绝 `..`、符号链接、junction）；只读三个固定文件；`study_result` 只能新建、文件名格式固定、内容格式与长度校验；无 `study.json` 时工具不出现；gemini/antigravity/sesame 调用返回 -32602。
- [ ] `node --test tools/i_remote_mcp/` 全过，CI 绿。
- [ ] 部署脚本轮：生成候选、写 `study.json`、切换任务（按 N2 流程，受保护 ACL），ChatGPT 里说“开始今天的英语练习”能拿到学习单，结束后 inbox 出现新文件，次日 daily_done 后该结果已入账。

## 允许修改的路径
- tools/i_remote_mcp/
- tools/relay_scripts/study/
- docs/development/handoffs/RELAY_20261102_st1-study-mcp-tools.md、DEVLOG.md

## 不做 / 边界
- 不碰飞书凭据，不调用 lark-cli，不改 feishu_sync、账本表结构。
- 只读 `today.md`、`state/sources.json`、`state/ledger.json`；只写 `inbox\` 新文件；不删除、不覆盖。
- 不改 Core、i_context（林埃上下文里加“今日学习进度”放到 ST2，单独确认）。
- 学习内容不进 i_core / Memory V3。
- 仓库公开：不写本机路径、用户名、域名。

## 验证命令
- node --test tools/i_remote_mcp/

## 需要真人的部分
- 合并 PR；部署脚本轮点 👍（会短暂停服，约 1 分钟）。
- 在 ChatGPT 里试一次“开始今天的 XX 练习”。

## 实现说明（Claude，2026-11-03）
- 学习工具写在新文件 `tools/i_remote_mcp/study_tools.mjs`，只依赖 `node:fs` 和 `node:path`。`domain_tools.mjs` 加了 `createStudyDomainTools`，把学习工具的输入错误转成主线的结构化错误；主线 `server.mjs` 从 `stateDir/study.json` 加载学习工具，只挂到 claude_web 和 chatgpt_web 上。
- 生产候选：`STUDY_PATCHES` 排在 FOOD 之后。legacy server 把 `study_tools.mjs` 整个文件原样内嵌进去（`study_tools.test.mjs` 逐字节核对），因此主线和候选的工具定义和行为都来自同一份源码。另外三处改动：FOOD 的 RPC 包装也接管 study_* 工具，输入错误照样以结构化形式返回；`serve` 启动前先校验 `study.json`；`study_` 开头的错误码原样打印到 stderr。
- `study_source` 增加了可选参数 `offset`，用来续读超过 20000 字的笔记。
- 候选 server 的哈希从 `f42f291f…` 改钉为 `a0bd0491…`，其余五个文件不变。
- 云端 `node --test tools/i_remote_mcp/*.test.mjs`：223/223 通过。
- 已知限制：用 `study_result` 写回的收件文件，入账时练习表的“渠道”仍沿用导师现有的规则（选项只有 Codex/dot/Gemini/手动），本轮不改账本结构。
