# 飞书学习导师

Node 24、无第三方依赖。确定性同步脚本读写飞书；定时 Codex 使用 workspace-write，只处理学习目录里的快照、学习单和 outbox。此目录提供模板和合成测试，没有连接真实飞书、创建任务或迁移旧数据。

```text
飞书：账本 / 练习记录 / 收件 + 学习单文档
     ↓ pull                    ↑ push（只增改）
学习目录 state/*.json → Codex → state/outbox/*.json
                              → today.md → dot / GPT voice
```

## 用户手动安装与授权（合并后）

1. 安装 Node 24、Codex CLI 和 `@larksuite/cli@1.0.98`。确认 node、codex 可用，npm 全局目录加入 PATH。使用自己创建的免费团队租户，学习资料不放雇主租户。
2. 以下仅供**用户本人**在终端完成，所有 Agent 和同步脚本都禁止代执行；不要把授权输出、配置或凭据贴进 PR：

   ```text
   lark-cli config init --new
   lark-cli auth login --domain "docs,base"
   ```

   保持 risk-control 默认。逗号分隔参数必须加引号，JSON 和多行文本用 `@file`。Windows 同步进程始终 `shell:false`，npm `.cmd` 会解析到包里的原生 exe；也可在私有配置里直接填写 exe 路径。
3. 在仓库之外建立两个互不包含的目录，已有内容不同先比较，不覆盖：
   - **工具目录** `%USERPROFILE%\feishu-tutor-tool`：复制 `sync/` 和 `run-daily.ps1`。把 `sync/config.example.json` 复制为工具目录根部的 `config.json`。工具目录不得作为 Codex 的工作目录或额外可写根，Codex 不得修改这里的代码和配置。
   - **学习目录** `%USERPROFILE%\feishu-study`：只复制 `STUDY_AGENTS.md`（改名 `AGENTS.md`）、`TUTOR_RULES.md`、`subjects.md`；创建 `state/outbox/`、`inbox/done/`、`logs/`。运行后生成 `today.md`。不向这里复制 sync、配置或 runner。
4. 在工具目录的私有 `config.json` 中，将所有占位符替换为本机实际值：CLI 原生可执行文件路径（或设为 `lark-cli` 走 PATH）、模型、base 标识、三张表名、全部字段映射、科目、来源文档。`sources` 可为空数组；出题需要对应来源时应补全。真实配置、学习快照、日志和 outbox 不入库；凭据只留 CLI 的系统安全存储，不复制到学习目录。
5. 定时 Codex 的本机配置不要启用 MCP、apps、连接器或额外工具；只允许本地学习文件流程。不得给这次运行开放网络或换为 danger-full-access。网络限制由 runner 显式设为 false；AGENTS 同时禁止通过外部服务工具绕行。

## 建三张表（用户在场）

下面的提示词用于用户手动建表或**另一个由用户明确授权的初始化交互**，不让定时导师或同步白名单承担建表权限。建表之前先展示计划并确认；普通导师不能直接调 lark-cli 写表。不要把以下步骤解释为当前仓库执行者的真实飞书授权。

```text
在我指定的飞书学习空间中准备一个多维表格，包含三张表。
先列结构与位置给我确认；我确认后再建，已有同名表或字段先核对，禁止删除或覆盖。
来源使用 text 存带标题的 Markdown HTTPS 文档链接。
科目均为单选，只含我确认的 subjects 科目；单选 multiple=false。

账本（10 字段）：
知识点 text；科目 select；来源 text；掌握度 select（未学/模糊/掌握）；
最近结果 select（对/错/不会）；连对 number；错次 number；
上次练习 datetime；下次复习 datetime；备注 text。

练习记录（7 字段，只增）：
时间 datetime；知识点 text；科目 select；结果 select（对/错/不会）；
纠正 text；渠道 select（Codex/dot/Gemini/手动）；学习单日期 datetime。

收件（4 字段）：
内容 text；渠道 select（Codex/dot/Gemini/手动）；
状态 select（待入账/已入账，默认待入账）；入账日期 datetime。

Base 时区设为我的本地时区。账本增加按下次复习的日历视图和今日待复习视图；
练习记录增加按日期分组的视图。不要导入旧账本，不碰 risk-control、config 或 auth。
```

今天以前或今天到期的动态日期筛选可参考 `["下次复习","<","Tomorrow"]`。视图只供人查看，同步读取整表，不受视图筛选影响。

## 检查、拉取与同步

在用户终端用工具脚本完整路径运行（以下为 PowerShell 单行命令）：

```powershell
node "$env:USERPROFILE\feishu-tutor-tool\sync\feishu_sync.mjs" --help
node "$env:USERPROFILE\feishu-tutor-tool\sync\feishu_sync.mjs" check --config "$env:USERPROFILE\feishu-tutor-tool\config.json" --state "$env:USERPROFILE\feishu-study\state"
node "$env:USERPROFILE\feishu-tutor-tool\sync\feishu_sync.mjs" pull --config "$env:USERPROFILE\feishu-tutor-tool\config.json" --state "$env:USERPROFILE\feishu-study\state"
node "$env:USERPROFILE\feishu-tutor-tool\sync\feishu_sync.mjs" push --dry-run --config "$env:USERPROFILE\feishu-tutor-tool\config.json" --state "$env:USERPROFILE\feishu-study\state"
node "$env:USERPROFILE\feishu-tutor-tool\sync\feishu_sync.mjs" push --config "$env:USERPROFILE\feishu-tutor-tool\config.json" --state "$env:USERPROFILE\feishu-study\state"
```

`--state <学习目录/state>` 必填，不从配置位置推导；`--config` 默认取工具目录根部的 `config.json`。工具和配置目录与学习目录同目录或互相包含时，返回 `daily_layout_invalid`，不调用 CLI；Node 检查会解析符号链接和 junction。配置中的 `cli` 不接受 `.mjs`、`.js` 或 `.cjs`；脚本 CLI 仅允许通过 `FEISHU_TUTOR_CLI` 注入合成测试，日常运行不要设置此变量。没有通用 CLI 参数、命令或端点透传。

`check` 只读：用户身份、三张表、每个字段的类型、单选选项均核对。账本 10 字段，不加修改时间列；pull 保存原始字段快照来防覆盖。记录分页至 has_more=false，同表分页 rev 和 query_context 不一致即失败，不替换原有效快照。练习记录放在 ledger.json 的 practice 数组，收件仅保留待入账行。来源正文及 sidecar 放在 sources.json。

## outbox 协议

每个 JSON 文件一个动作，文件名唯一，扩展名 `.json`。所有文件先校验，任何非法动作、字段、类型、枚举、日期或超限都整批拒绝，没有 CLI 写调用，错误在 `state/push-report.json`。日期按 Base 本地日历的 `YYYY-MM-DD`；练习时间用带时区 RFC3339。文本不接受空白或 null，数字必须为非负安全整数。

```json
{"action":"ledger_update","record_id":"<RECORD_ID>","expected_fields":{"<COPY_ALL_SNAPSHOT_FIELDS>":"<VALUE>"},"fields":{"掌握度":"模糊","连对":0,"错次":2,"上次练习":"2026-10-24","下次复习":"2026-10-25"}}
```

`expected_fields` 必须完整复制该行 pull 返回的 snapshot；上面是形状占位，不是可运行的 baseline。push 前重读，字段快照不一致或行已不存在则 conflict，不覆盖手机改动。返回码 2，原文件保留，其他独立动作可继续；收件确认统一排在最后，本批账本有 conflict 时不标收件已入账。修复必须重新 pull 并人工核对语义，不能直接换快照强推。

```json
{"action":"ledger_create","records":[{"知识点":"示例知识点","科目":"<SUBJECT_NAME>","来源":"[资料标题](https://example.invalid/docx/placeholder)","掌握度":"未学","连对":0,"错次":0,"下次复习":"2026-10-24"}]}
```

一次 push 新增账本总计最多 30 行。来源、最近结果、上次练习和备注可以省略；其他 6 字段必填。Gemini 或手动错点没有来源时直接省略，不编造文档。提供来源时，必须是带标题的 HTTPS Markdown 链接，路径支持 `/docx/` 和 `/wiki/`。

```json
{"action":"practice_create","records":[{"时间":"2026-10-24T06:30:00+08:00","知识点":"示例知识点","科目":"<SUBJECT_NAME>","结果":"错","纠正":"你说的 → 正确说法 → 原因","渠道":"Codex","学习单日期":"2026-10-24"}]}
{"action":"inbox_mark","record_id":"<RECORD_ID>","date":"2026-10-24"}
{"action":"doc_write","date":"2026-10-24","content":"# 学习单 2026-10-24 科目\n预计：20 分钟\n"}
```

上面三行分别放三个文件。practice_create 每批最多 200 行，7 字段全必填，只新增。inbox_mark 只能改成已入账并填日期，不能改内容；该行也会比较 pull 快照。doc_write 不接受文档 token、标题或更新命令：只能新建当日学习单，或追加到脚本已建并登记在 `state/sync-owned/documents.json` 的同日文档。禁止导师改登记文件；这属于本机同步状态，应由用户保护，不能视作可接收任意不可信本机写入的安全边界。

写成功的文件原样移到 `state/outbox/done/`，不删除。执行前移到 `inflight/`；一旦进程中断、返回失败或写后核验不明确，文件仍保留在那里，下次 push 返回 `push_reconciliation_required`，不会盲目重发。用户需先核对远端实际结果，再将文件归档或恢复重试；不要在未核对时恢复。成功调用后的崩溃不能实现 exactly-once，整批校验也不是远端事务或自动回滚。

dry-run 只做本地校验，不调用 CLI、不移动文件、不保证远端此刻无冲突。冲突、校验错误和写入不明确都记录报告；错误码如 `outbox_invalid_field`、`record_conflict`、`command_not_allowed`。不复制真实响应或学习正文到控制台。

`state/.sync.lock` 记录同步进程的 pid 和开始时间。已有锁且 pid 仍在运行（或锁无法可靠判定）时返回 `sync_locked`；pid 已退出时返回 `sync_lock_stale`。脚本不会自动删除已有锁。用户应先确认没有正在运行的同步进程，再手动删除残留锁文件，随后先检查 `state/outbox/inflight/` 并核对远端实际结果；核对完成前不要再次 push。pid 可能被系统复用，开始时间供人工判断，不能仅凭文件很旧就移除。

## 每日运行与 Interactive 计划任务

工具目录的 `run-daily.ps1` 兼容 Windows PowerShell 5.1，`-StudyDirectory` 和 `-ConfigPath` 均必填，没有学习目录默认值。它检查学习目录与工具/配置目录互不包含，否则报 `daily_layout_invalid`；随后依次 pull → `codex exec -C <学习目录> -s workspace-write -m <配置模型>` → push，同步命令均显式传 `--state`。每步检查退出码，失败即停。显式关闭 sandbox 网络；不加 danger-full-access。日志在学习目录 logs，仅记步骤和退出码。已有未处理 outbox 或 inflight 时，出新学习单前先停。日运行持有独占文件句柄，多个实例不能同时操作。

合并后用户先手动试跑，确认报告、today.md 和远端均正确，再自己注册任务。任务设置为 **Interactive / 仅在用户登录时运行**，不使用“无论用户是否登录”；电脑须开机并登录。时间由用户决定。不要让本仓库执行者注册、启用或触发真实计划任务。

多行脚本统一经 EncodedCommand。用户可在 PowerShell 中生成一次 Action 参数，再把输出复制到任务计划程序；这段只生成字符串，不注册任务：

```powershell
$studyDirectory = Join-Path $env:USERPROFILE 'feishu-study'
$toolDirectory = Join-Path $env:USERPROFILE 'feishu-tutor-tool'
$escapedStudyDirectory = $studyDirectory.Replace("'", "''")
$escapedToolDirectory = $toolDirectory.Replace("'", "''")
$dailyCode = "& (Join-Path '$escapedToolDirectory' 'run-daily.ps1') -StudyDirectory '$escapedStudyDirectory' -ConfigPath (Join-Path '$escapedToolDirectory' 'config.json'); exit `$LASTEXITCODE"
$dailyEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($dailyCode))
'-NoProfile -NonInteractive -EncodedCommand ' + $dailyEncoded
```

程序用 `powershell.exe`，参数用上述输出。Node/Codex 若不在该任务的 PATH，可在用户私有启动代码里显式传 `-NodeExecutable` / `-CodexExecutable`。手动运行也用同样的 EncodedCommand 参数。试跑后读 logs、push-report 和 today.md 的日期，而非只看任务 LastTaskResult。

## 语音与旧模板

dot 读 `%USERPROFILE%\feishu-study\today.md`，按 TUTOR_RULES 带练；GPT voice 由用户粘贴学习单。来源提示用飞书的标题链接。Gemini 或语音结果可以手动加入飞书收件表。

`subjects.md` 原样复制；TUTOR_RULES 调整学习单路径、“先打开”链接形式及结果路径。dot 写入新目录的 inbox：`%USERPROFILE%\feishu-study\inbox\YYYY-MM-DD-HHMM.md`，由 Codex 按入账规则处理。本轮不会改动现役 siyuan-study。

## 已知限制与验收层次

- 个人 / 豆包账号下的应用授权有平台拦截记录；采用用户自己的团队租户。access token 过期后的刷新曾实测可用，refresh token 有效期 7 天；到期后的续期于 **2026-10-31 待用户复测**，不声称已解决。
- Windows 沙箱的 DPoP/KSP 限制正是拆分同步与 Codex 的原因。任务用登录用户运行同步脚本；不把 lark-cli 放入沙箱，也不解除 Codex 沙箱。
- compare-then-write 不能阻止比较之后、写入之前的极短并发窗口；飞书 CLI 没有这里可用的条件更新原子操作。不承诺消除所有并发覆盖。
- 飞书更新可能异步可见。读回不一致会保留为不确定状态，需要核对；不自动重试。
- CLI 帮助已核对，部分返回容器依据本地说明/适配约定，用户合并后须 check、单条试跑。未联网验收、未建计划任务、未迁移旧账本。CLI 升级后先重新核对帮助和合成测试。
- 不碰思源、flexnote、App、MCP、i_core 或 Memory V3。旧账本迁移另做，需要用户同意。

合成验证：`node --test tools/feishu_tutor/sync/*.test.mjs`。假 CLI 在系统临时目录生成，只记录合成 argv 和 @file 字节；涵盖白名单穷举、整批拒绝、冲突、字节一致、dry-run、归档及失败保留。GitHub CI 的 bridge-node 跑相同命令。测试通过、真实飞书试跑、定时任务验收和真人体验是分开的结论。
