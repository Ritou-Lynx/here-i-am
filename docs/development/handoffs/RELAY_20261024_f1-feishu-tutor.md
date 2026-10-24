<!-- relay:contract v1 -->
# F1 合同：飞书学习导师（多维表格账本 + 同步脚本 + 沙箱 Codex）

## 背景
- 调研：`docs/reference/FEISHU_NOTES_RESEARCH_20261021.md`（本 PR 由 Claude 带入，含"实测结论"一节）。
- 实测（10-23/24，用户本机）：
  - 个人或豆包账号下的自建应用会被平台策略拦截（21001）。改在用户自建的免费团队租户里配置后通过。
  - CLI 能做到：Markdown 文档往返逐字一致；多维表格建表、增、改、筛选、建视图。
  - Interactive 计划任务可以调用 codex exec 再调用 lark-cli，但必须用 `-s danger-full-access`，因为 DPoP 密钥在 restricted token 下会报 20140。
- 用户决定（10-24）：定时任务拆成两段。确定性同步脚本负责读写飞书；Codex 在沙箱里只处理本地文件，不联网，碰不到凭据。现役 `tools/siyuan_tutor/` 不动。

## 目标
新建 `tools/feishu_tutor/`，结构参照 `siyuan_tutor`，账本换成飞书多维表格：

```
飞书团队租户（多维表格"学习账本"：账本 / 练习记录 / 收件；文档：学习单）
   ▲ push（只增和改）           │ pull
   │                            ▼
 feishu_sync.mjs ◄──► 本地 state/（ledger.json、inbox.json、outbox/*.json）
                                │
                Codex（沙箱，workspace-write，不联网）
                                │
                           today.md ──► dot / GPT voice
```

## 完成标准

**同步脚本 `tools/feishu_tutor/sync/feishu_sync.mjs`（Node 24，无第三方依赖）**
- [ ] 子命令：`pull`、`push`、`push --dry-run`、`check`（只读：确认身份是 user，三张表和全部字段都在，字段类型对得上）。
- [ ] 所有飞书调用都通过 `child_process.spawn` 调 lark-cli，`shell: false`。JSON 和多行文本一律写成临时文件，用 `@file` 传入，用完清理。子进程环境设 `LARK_CLI_NO_PROXY=1`。lark-cli 路径从配置读，默认在 PATH 里找；输出按 UTF-8 解码。
- [ ] **命令白名单**：脚本只能拼出下面这些子命令（单元测试逐条断言），其他一律拒绝，不提供任何通用透传：
  - 读：`whoami`、`base +record-list`、`base +table-get`/`+field-list`（具体名称以 1.0.98 的 `--help` 为准）、`docs +fetch`
  - 写：`base +record-batch-create`、`base +record-batch-update`、`docs +create`、`docs +update --command append`（只能写脚本自己建的文档，文档 token 记在 state 里）
  - 永不出现：任何 delete、remove、clear、`config`、`auth`、权限和成员类命令
- [ ] `pull`：把三张表读成 `state/ledger.json`、`state/inbox.json`（只取"状态 = 待入账"的行），带 `pulled_at` 和每行的 `record_id`。
- [ ] `push`：读 `state/outbox/*.json`，先校验再写。校验规则：
  - 只允许五种动作：`ledger_update`（按 record_id，只改白名单字段）、`ledger_create`（单次最多 30 行）、`practice_create`、`inbox_mark`（只把"状态"改成"已入账"并填入账日期）、`doc_write`（只写学习单文档）。
  - 字段值逐项校验类型和取值范围，例如掌握度只能是 未学/模糊/掌握，连对只能是非负整数，日期必须是合法日期。
  - 任一条不合法，整批拒绝，什么都不写，退出码非 0，错误码写进 `state/push-report.json`。
  - 写入成功的 outbox 文件移到 `state/outbox/done/`，不删除。
- [ ] 防覆盖：`ledger_update` 带上 pull 时那一行的修改时间（或字段快照）。push 前重读，发现飞书上那一行已被改过（比如用户在手机上改了），这一行跳过，记为 `conflict`，不覆盖。
- [ ] 配置 `tools/feishu_tutor/sync/config.example.json`：base token、表名、字段名映射、lark-cli 路径。真实配置放在学习目录里，不入库。

**Codex 指令 `tools/feishu_tutor/STUDY_AGENTS.md`**
- [ ] 由 `siyuan_tutor/STUDY_AGENTS.md` 改写：学习模式、排期规则、入账、出学习单、收尾写回都保留（原来写"学习记录"文档的地方，改为写"练习记录"表的行）；数据读写改为"读 `state/*.json`，写 `state/outbox/*.json`"。
- [ ] 分两种运行方式：
  - **定时（无人值守）**：只能读写本地文件，不调用 lark-cli，不联网。
  - **交互（用户在场）**：可以先跑 `node sync/feishu_sync.mjs pull/push`，也就是只经过同步脚本；不直接调 lark-cli 写表。
- [ ] 硬规则：不改 risk-control，不运行 `config` 或 `auth` 类命令，不删除任何内容；多行 PowerShell 脚本只用 `-EncodedCommand`，执行后读回结果确认（C1 的教训）。
- [ ] 账本字段沿用现有 10 个：知识点、科目、来源、掌握度、最近结果、连对、错次、上次练习、下次复习、备注。"来源"字段写飞书文档链接加标题文字（段落锚点能不能用待 A5 实测）。
- [ ] 新增"练习记录"表：时间、知识点（文本，和账本知识点同名）、科目、结果（对/错/不会）、纠正（你说的 → 正确说法 → 原因）、渠道（Codex/dot/Gemini/手动）、学习单日期。每练一题写一行，只增不改。
- [ ] 新增"收件"表，替代思源的"学习收件箱"：内容、渠道、状态（待入账/已入账）、入账日期。用户在手机飞书里能直接加一行，Gemini 回流的错点也写到这里。

**运行脚本与说明**
- [ ] `tools/feishu_tutor/run-daily.ps1`：依次执行 pull → `codex exec -C <学习目录> -s workspace-write -m <配置里的模型> "出今天的学习单"` → push。每一步失败都停下，写日志并给出非 0 退出码。codex 不加 `danger-full-access`，也不加网络放行。
- [ ] `tools/feishu_tutor/README.md`：
  - 安装和授权步骤：团队租户、`config init --new`、`auth login --domain "docs,base"`；PATH 和引号的坑。
  - 初始化：建表的提示词。建表由用户在场的交互 Codex 完成，或者由用户手动建。
  - 计划任务：Interactive 模式，只在登录时运行。
  - 当前已知限制：个人账号被拦截；refresh token 有效期 7 天，续期情况待复测。
- [ ] `tools/feishu_tutor/TUTOR_RULES.md`：从 siyuan 版复制，改动只有学习单路径（`%USERPROFILE%\feishu-study\today.md`）和"先打开"的链接形式。`subjects.md` 从 siyuan 版复制。

**测试（合成数据，不连飞书）**
- [ ] `tools/feishu_tutor/sync/*.test.mjs`：用一个假的 lark-cli（测试里生成的 Node 脚本，记录收到的参数并返回固定 JSON）覆盖以下情况：
  - 白名单：每个子命令都能拼出来；任何 delete/remove/config/auth 都拼不出来。
  - outbox 校验：每种非法值都会导致整批拒绝，而且一次 lark-cli 写调用都没有发生。
  - 防覆盖：修改时间变了的行被跳过，记为 conflict。
  - 中文、多行文本、引号、`$` 都经 `@file` 原样到达假 CLI（逐字节比对）。
  - dry-run 不发生任何写调用。
  - push 成功后 outbox 文件移进 done/，不删除。
- [ ] `ci.yml` 的 bridge-node 作业加一步 `node --test tools/feishu_tutor/sync/*.test.mjs`。

## 允许修改的路径
- `tools/feishu_tutor/**`（新建）
- `.github/workflows/ci.yml`（只在 bridge-node 作业里加上面那一步）
- `docs/development/handoffs/RELAY_20261024_f1-feishu-tutor.md`（只由 Claude 改）

## 不做 / 边界
- 不改 `tools/siyuan_tutor/`、`tools/flexnote_tutor/`、i_core、MCP 或 App。学习数据不进 i_core 和 Memory V3。
- 不迁移现有思源账本的 12 行。迁移另写一份 Codex 提示词，在用户本机交互执行，需要用户同意。
- 不连真实飞书，不建计划任务，不碰用户电脑。这些都在合并后由用户按 README 手动操作。
- 仓库里不出现租户域名、base token、App ID、openId 或本机路径（示例一律用占位符）。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `node --test tools/feishu_tutor/sync/*.test.mjs`
- `node tools/feishu_tutor/sync/feishu_sync.mjs --help`（不需要配置也能输出用法）
- `git status --short`（只出现允许修改的路径）
- Claude 在云端复跑 Node 测试并逐条核对白名单。

## 需要真人的部分
- 合并后，用户在本机按 README 操作：建学习目录、复制配置、在交互 Codex 里建三张表并跑 `check`，试跑 `run-daily.ps1`，再注册 Interactive 计划任务。
- 思源账本 12 行的迁移另出提示词，用户同意后执行。
- 2026-10-31 refresh token 到期后复测续期（已有测试任务 FeishuCliTest-C1）。

## 用户决定（10-24）
- 定时任务拆成两段：同步脚本读写飞书，Codex 在沙箱里只处理本地文件，不联网（不用 danger-full-access）。
- 飞书账本放在用户自建的团队租户里，不放个人账号。
- 学习目录用 `%USERPROFILE%\feishu-study`，和 `siyuan-study` 分开；dot 的指令改路径。
- 新增"收件"表，取代思源的"学习收件箱"文档，手机和 Gemini 的错点都直接加进去。
- 纠正明细只写进"练习记录"表，再建一个按日期分组的视图，不单独写"学习记录"文档。
- Gemini 的错点先手动记到"收件"表，这次不做自动化。
- risk-control 保持默认；任何 Agent 都不改 risk-control，也不运行 `config` 或 `auth` 类命令。

## 审核记录
- 第 1 轮（78a50aa，10-24）：实现完整，云端 58 项通过、4 项 PS 跳过。返修 5 项：
  1. 同步代码、配置、runner 原本放在 Codex 可写的学习目录里，沙箱被绕过，改为独立的工具目录，sync 必须带 `--state`；
  2. 配置不能把 CLI 设成 `.mjs`；
  3. 来源改为选填，并允许 `/wiki/`；
  4. 锁文件写 pid，崩溃后报 stale；
  5. TUTOR_RULES 的 inbox 路径改到 feishu-study（更正合同疏漏）。
- 第 2 轮（99354d3，10-24）：5 项都已修复。目录检查同时比较原路径和 realpath，能防 junction 绕过；runner 的 `-StudyDirectory`、`-ConfigPath` 为必填。云端 71 项通过、7 项 PS 跳过（Codex 在 Windows 上 78/78）。**通过。**
