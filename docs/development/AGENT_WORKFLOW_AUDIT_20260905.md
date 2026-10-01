# Agent 指令与工作流审计 — 2026-09-05

本轮针对 Here I am 仓库的开发 Agent Markdown、Skill 入口、工作流与模型路由落实精简。基线为 `v3-lab@4ba05b1177d3` 加原有未提交修改；未提交、推送、发布或重建产品。本文是审计记录，日常任务不必加载。

## 官方依据与采用方式

- [GPT-6 Astra 官方指导](https://developers.openai.com/api/docs/guides/latest-model)：专门要求审计 Skills/AGENTS 的冲突指令；建议明确授权后的持续完成、并行委派与适量验证。本轮据此去掉重复审批、固定失败次数、过度测试与纯管理员式主控限制。
- [Codex 最佳实践](https://learn.chatgpt.com/guides/best-practices)：根指令保持简短准确，复杂流程按需引用。本轮合并重复入口，将实现历史与日常执行契约分开。
- [AGENTS 加载规则](https://learn.chatgpt.com/docs/agent-configuration/agents-md)：项目级规则可覆盖此前的全局个人指令。本轮仅在本仓库覆盖旧 Sol 路由，不写用户级配置。指令在任务启动时加载，旧任务上下文不会因为文件变化自动清空。
- [Skills 官方文档](https://learn.chatgpt.com/docs/build-skills)：按名称/描述匹配，再加载正文；同名 Skill 不会自动合并。本轮不复制插件缓存或参考仓库技能。
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)：按任务配置模型和推理等级。该页部分模型示例仍为 GPT-5.6，Astra 主控选择依专属指导和当前工具目录，不能把旧示例当成最高能力上限。

模型分层、状态表与提交例外是项目适配，不是官方要求所有仓库采用的标准；没有仅凭文档宣称“最优性能”。本轮不涉及 App 内 API/provider 迁移，因此没有把 Responses API 参数改动套到 Codex 桌面配置或人格 prompt。

## 发现与落地

| 发现（原版位置） | 处理 |
|---|---|
| 全局 AGENTS 37/42 行固定 Sol 主控与验收，但实际配置已是 Astra/ultra | 根 AGENTS 明确仓库局部覆盖；保留用户选定 effort，不用文字把 Astra 限为 high |
| 全局路由同时包含每轮 Spark 门控、固定逐级失败、逐次查 rollout | 仓库默认 Luna/low；仅明确选 Spark 时检查；按证据升级，路由变更/冒烟/异常才核查运行元数据 |
| CLAUDE 引用 AGENTS 后仍复制完整契约，45–46 行的“将重构”已过期 | CLAUDE 收敛为单入口；以 RecordOrganizerServiceV3 和退役流水线为准 |
| CLAUDE 289–293、315 行存在独有记忆边界 | 迁入根契约：Memory V3 写入目录/禁扩旧服务，记录可编辑删除、只呈现有效版本 |
| AGENTS 383–387 行的五条 `.Codex/references/` 链接不存在 | 去掉过期自动入口；参考原件实际在 `.claude/references/`，仍按任务检索 |
| 协作协议把跨回合/两个工作包自动升级为完整阶段流程 | 普通任务用短 Plan；Goal 工具和独立任务遵守用户明确授权，Worktree 不等于新任务 |
| 主窗只派发、等待所有结果才裁决、压缩后强制换窗 | 主 Agent 可实现关键路径；就绪结果按依赖回收；实际连续性失效才交接 |
| 模板重复启动声明、全套资料、全局状态写入 | 只声明一次、按领域读相关章节；worker 写自身 handoff，主窗集成后统一写全局状态 |
| 新 handoff 归属与现有状态 hook 相冲突（二审发现） | 已授权隔离 worker 可单次用已有 SKIP_PROJECT_STATE 例外并记录；恢复环境变量，主窗正常通过 hook |
| 日终流程容易把“只检查”或脏工作树变成整体停工 | 默认检查；既有提交授权不重问；先准备精确分组，保留无关 staged/unstaged 内容 |
| W6 老模板要求先 pull/checkout、把全部未提交内容 WIP 提交、每包全量测试 | 标明历史阶段适用范围，改为精确本地基线、只提交授权范围和按风险验证 |

## 实际路由与生效边界

只读核对本机配置：`~/.codex/config.toml` 第 25–26 行为 `gpt-6-astra / ultra`；第 38–39 行为默认 worker `gpt-5.6-luna / low`。全局 `~/.codex/AGENTS.md` 的旧路由仍存在，未修改。

| 角色 | 仓库路由 |
|---|---|
| 主控、复杂判断、最终复核 | GPT-6 Astra；保留用户当前 effort |
| 机械提取、明确重复任务 | Luna / low |
| 边界明确的工程、审计 | Terra / medium |
| 复杂或高判断 worker | Astra / high，或用户要求的更高 effort |

该表是派发策略，不是运行时模型切换器。当前工具可调用目录有 Astra 及相应 effort；本轮有 Terra 审计与 Astra 独立复核请求，但未读取 worker rollout 证明实际路由，也未做旧/新提示词性能对照测试。普通任务无需为证明模型可用而额外空跑。

新任务会读取更新后的仓库入口。旧任务可以继续按新规则工作，但已经注入的全局文字、历史 prompt、MCP 描述与 Skills 元数据不会从上下文中消失；本轮没有批量重启、重发或修改其它任务。

## Skill Markdown 盘点

对包含隐藏/忽略文件的仓库扫描，排除隔离 Worktree、构建、临时目录、依赖和外部参考副本后：**本仓库自有 SKILL.md 为 0**，也没有现成 `.agents/skills/` 可精简。

未排除参考副本时命中的 lieflat-charts / kami 技能属于外部资料，不是仓库自动加载入口。当前会话列出的 Skills 来自用户级目录、系统或插件缓存；本轮仅使用 OpenAI Docs 技能核对官方来源，没有审计或改写全部已安装 Skill。

后续真正封装重复流程时，Skill 只承担一个明确任务，描述先写触发场景与边界，正文写输入、输出、必要步骤和验证；长资料按需引用。当前日终/协作文档已有明确入口，不再加一层内容相同的 Skill。

## 验证与保留边界

- 修改后的八份指令/模板经过链接与代码围栏检查；根入口的 8 个本地 Markdown 链接有效。
- 独立二审核对旧文件快照与当前 diff，发现并修复提交 hook 冲突；没有改 hook、全局权限或 CI 令牌。
- 原 staged 差异前后 SHA-256 一致；共享 DEVLOG / 项目状态仅增加本轮窄记录，其余已有内容保留。
- 按场景复核：普通文档任务不创建 Goal/构建；“先给草案”仍只给草案；已授权隔离 worker 不重复审批；日终不自动提交；既有真人 Gate 不自动通过；不同候选证据不混用。
- User-truth 显式写入、Memory V3 边界、白板共享身份、hereIAmV3、构建前 critical 检查、手机物理安装确认、用户无关修改、push/发布授权均保留。

根 AGENTS + CLAUDE 的原始 UTF-8 文本约 40 KB，精简后约 10.5 KB，减少约 **74%**。这是文件文本量减少，不是模型 token、延迟、成本或准确率的实测收益。白板专有产品契约和已有 Gate 未为减字而削弱。

纯指令/文档修改未运行 Flutter 构建或 App 功能测试；静态验证不代表产品真人验收，也不代表所有未来任务已经证明按新路由执行。

## 审计覆盖到、但不在本轮改写的范围

1. **用户级指令和插件/MCP 描述**：全局 Voice 规则及所有 i 工具描述有重复常驻内容。仓库局部覆盖只消除这里的路由冲突，不能缩短这些全局输入。i Gateway 安装器只替换 i-continuity 托管块，不修复独立 model-routing 块；其指导源与安装脚本已有其它任务未提交修改，本轮未触碰或执行安装器。
2. **项目历史体积**：本轮前 I_PROJECT_STATE 约 379 KB、DEVLOG 约 599 KB。根入口已改为工具摘要/相关部分按需读取；没有重排这些包含其它 staged/unstaged 工作的文件。历史归档和当前投影缩短应单独保持可追溯地处理。
3. **GitHub Actions**：`android-daily-early.yml` 仍每天从默认分支构建 globalEarly/cnEarly，并创建及删除 prerelease；与本地主线 V3 目标不同。`pr-policy-preflight.yml` 是可信 base 执行的影子检查，会评论 PR。本轮审计了这两项定义，但不改变现有发布行为或外部评论权限。若后续要调整，应明确选择保留旧 Early 渠道、停用，还是迁成 V3 构建；不能将开发 prompt 精简顺带变成发布管线迁移。
4. **运行中的产品模型与人格**：Bridge、App provider、Voice、已验收的人格 prompt、既有 Goal 历史与 Gate 记录不属于开发 Agent 路由切换。本轮没有批量替换历史 Sol 型号、恢复旧阶段或更改产品完成状态。
