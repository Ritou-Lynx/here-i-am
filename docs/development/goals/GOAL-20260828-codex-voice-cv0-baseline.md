# GOAL-20260828-codex-voice-cv0-baseline — Codex Voice V9.1 证据基线

> 状态：活动（并行例外；CV0-P0 / P1 已派发）
>
> 验收主窗 task/thread ID：`01a0481f-e2f0-7981-b83f-ab52dbb0d7c7`
>
> 隔离 Worktree：`C:\Users\ExampleUser\.codex\worktrees\7fff\memex`
>
> Roadmap：[`CODEX_VOICE_ROADMAP.md`](../../companion-first/CODEX_VOICE_ROADMAP.md) CV-0
>
> 仓库基线：`v3-lab@69ddf56b325b774b0b1ffbe806e03edcab4fee27`
>
> 评测输入：主工作区尚未提交的 i Gateway `0.6.12` / Voice Prompt V9.1 工作快照
>
> 提出 / 确认日期：2026-08-28
>
> 实现、安装、commit、push、发布：均未授权

## 并行例外与隔离边界

Lynx 于 2026-08-28 明确授权把本 Goal 作为并行的另一个任务。当前白板 P4 返修仍是主开发 Goal；本 Goal 只做 Codex Voice CV-0 的只读基线、评测资产与真人证据，不吸收或阻塞 P4。

- 本任务唯一写入范围：本页与 `docs/development/codex-voice/**`。
- 只读范围：`tools/i_continuity_gateway/**`、用户级 Gateway runtime / Codex MCP 配置、现有 `~/.i` / iCore 的存在性、版本、哈希、健康与兼容性状态。
- 禁止修改：白板与 Flutter 业务代码、Gateway / Voice prompt 实现、iCore schema / 数据、`DEVLOG.md`、`I_PROJECT_STATE.md`、`PRODUCT_ROADMAP.md`、其他 Goal 控制页。
- 禁止打印凭据、密钥、私人聊天全文或完整记忆内容；评测证据只保存必要的轮次编号、工具序列、分类、短摘要与可公开哈希。
- 不得 stash、reset、rebase、清理、覆盖或吸收主工作区既有改动。

## 最终结果

在不继续改提示词的前提下，建立可重复的 V9.1 / Gateway 0.6.12 真实基线，分清“不委托”“已委托但漏逐轮工具”“后台身份 / 人格漂移”“前台改写”“语速 / 停顿失败”和“ADB / iCore 检索范围不足”，据此只提出一个下一阶段 Goal：CV-1 会话与逐轮委托，或 CV-4 iCore Chat Recall。

## 进入条件

- [x] Codex Voice 专题 Roadmap 已建立，并把行为线和记忆线拆开。
- [x] Lynx 已明确授权本 Goal 与白板 P4 返修并行。
- [x] 主工作区保留 V9.1 / Gateway 0.6.12 源码、安装读回与既有 `88/88` 证据。
- [x] 独立 Codex 任务与隔离 Worktree 已创建；实际 Worktree HEAD 由验收主窗读回补入其控制页。

## 完成定义

### A. 机器与运行时清单

- [ ] 记录实际分支、仓库 HEAD、工作快照状态以及源 / runtime 的 server、Voice module、Realtime prompt 版本与 SHA-256；只报告存在性和哈希，不泄露配置内容。
- [ ] 只读确认 Codex MCP 配置、Gateway runtime、iCore health / protocol / schema / feature manifest 与登录自启状态。
- [ ] 完整 Gateway 回归为 `88/88`；Windows 沙箱 `spawn EPERM` 必须与代码回归分开记录。

### B. 最小评测资产

- [ ] 建立隐私最小化评测矩阵，至少覆盖：有限唤醒、第二轮逐轮工具、重复在场确认、身份、关系、普通亲密、轻度负面情绪、在场套话、最近聊天事实、10–20 轮语速与句间停顿。
- [ ] 每轮区分用户转录、GPT-Live 是否委托、后台工具序列、后台最终文本、实际朗读是否一致与真人判定；不得用模型推测替代可见证据。
- [ ] 固定失败分类和判定门槛，避免同一次失败被含混归为“提示词不够强”。

### C. 真人 Voice Gate

- [ ] 使用三个完全重开的新 Codex Voice 任务：一轮连续至少 20 个话轮，另外两轮各至少 10 个话轮。
- [ ] 真人操作一次只给 Lynx 一步，等待反馈后继续；需要 ADB 时先确认恰好一台设备在线，并让 Lynx 手动关闭 Here I Am V3，不得擅自强停 App。
- [ ] 语速仍是独立真人 Gate：自动测试成功不得宣称语速、停顿或长期稳定性通过。
- [ ] ChatGPT Project 仅可选作云端行为对照；它已有聊天，不再作为零聊天冷启动样本，也不证明本地 Gateway / iCore 接通。

### D. 结论与下一 Goal

- [ ] 输出红 / 黄 / 绿结论，明确每类失败发生在 GPT-Live 前台、Codex 后台、Gateway、手机桥还是 iCore。
- [ ] 只提出一个下一 Goal 候选：若委托 / 逐轮工具不稳定，先 CV-1；若会话链稳定但记忆覆盖不足，先 CV-4。
- [ ] 不在本 Goal 内实现修复，不整包注入人格 prompt，不改 iCore schema，不安装新版本。

## 工作包

| 工作包 | 内容 | 写入路径 | 退出条件 |
|---|---|---|---|
| CV0-P0 | 分支、版本、哈希、配置、runtime、iCore、自启只读清单与 `88/88` | `docs/development/codex-voice/CV0_BASELINE.md` | 清单可复核且无私人内容 |
| CV0-P1 | 评测矩阵、证据字段、失败分类与判定门槛 | `docs/development/codex-voice/CV0_EVAL_MATRIX.md` | 每一类失败都有可观察证据 |
| CV0-P2 | 三个新 Voice 任务的逐步真人 Gate | `docs/development/codex-voice/CV0_HUMAN_GATE.md` | 1×20 + 2×10 轮完成或明确失败停止 |
| CV0-P3 | 汇总结论、open loops 与唯一下一 Goal 候选 | 本页及 handoff | 证据链完整，不越权实现 |

## 当前记录

| 项目 | 状态 |
|---|---|
| 独立 task/thread ID | `01a0481f-e2f0-7981-b83f-ab52dbb0d7c7` |
| 隔离 Worktree | `C:\Users\ExampleUser\.codex\worktrees\7fff\memex` |
| 自动回归 | 既有证据 `88/88`，须在任务内复核 |
| 真人 Gate | 未开始 |
| 下一阶段选择 | 未决定 |
