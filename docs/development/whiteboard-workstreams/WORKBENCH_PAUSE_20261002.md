# 桌面白板工作台暂停收尾（2026-10-02）

> 状态：用户因整体计划调整，暂停桌面白板工作台开发。本页是接续时的唯一入口：先读本页，再按需读链接文档。旧交接与 Goal 文档按各自日期视为历史快照。

## 1. 收尾时的事实

- 源码全部在 `v3-lab`，没有未合并的任务分支独有提交、没有未提交改动。
- GitHub CI（`.github/workflows/ci.yml`）四个作业全部阻断并为绿：
  - Linux 白板 / 工作台套件与脚本化模型验收场景；
  - Linux 全量 Flutter 测试；
  - Bridge Node 测试；
  - Windows 构建、4 个 hermetic 白板集成测试，以及依赖 Windows 文件锁的单元测试。
- 无运行中的定时任务、PR 订阅、测试机进程或候选 App。没有构建、安装或发布任何包；真实账户与真实数据未触碰。
- 暂停期间 CI 照常在每次 push 时运行，用来提醒其他改动是否破坏了白板。`ollama-live.yml` 只在长任务代码变化或手动触发时运行。

## 2. 已完成并有证据的部分

| 部分 | 结论 | 证据 |
|---|---|---|
| UI-T、P4（AI 白板六类命令、持久 Undo、冲突、重启恢复） | 真人 Gate 通过；客观项已改为每次 push 自动重放 | `test/acceptance/whiteboard_ai_acceptance_test.dart`，[最终本地验收](GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md) |
| P5（手机 Dreaming 只读限定来源） | 按限定范围通过 | [最终本地验收](GOAL1_FINAL_LOCAL_ACCEPTANCE_20261001.md) |
| P6 长任务 | 生产默认走应用内 Ollama 纯文本网关；未设置 `HIA_TASK_OLLAMA_MODEL` 时 fail-closed，任务保持 pending；GitHub runner 上真实模型检查通过 | [P6 Ollama 交接](P6_OLLAMA_TEXT_TASKS_20261002.md) |
| 验证体系 | 四层机器优先验证，CI 每次 push 自动运行 | [无人值守验证](../UNATTENDED_VERIFICATION.md) |

## 3. 未完成项（暂停时不处理，接续时再决定）

- **Goal 1 父 Goal 未正式关闭**：真实 App 内的长任务体验（用真实 Ollama 模型）尚未由真人查看。
- **生产准备与减弹窗**：未开始，保持暂停。
- **非阻断债**（来自历轮真人 Gate）：
  - AI 写入后没有 busy / Toast 即时反馈；
  - Bridge 的 per-turn required / allow-only 工具字段在等上游 App Server schema；
  - full-rich 并发、物理删除后的孤儿清理、rich root 备份。
- **旧原生隔离链路**（P6-R2～R7 的 Codex CLI 文字 profile、WFP / Job / 提权 helper、Witness）保留在源码中，不在生产路径上；是否删除由用户决定。
- **`ollama-live.yml` 的 cloud 作业**：需要仓库 secret `OLLAMA_API_KEY` 才能运行，当前未配置时只会显式报错。

## 4. 接续步骤

1. 从 GitHub 完整 clone 或拉取最新 `v3-lab`，按 [多设备协作说明](../MULTI_DEVICE_GITHUB_WORKFLOW.md) 安装提交检查，从 `v3-lab` 新建 `codex/` 或 `claude/` 任务分支。
2. 依次阅读：本页 → `AGENTS.md` →
   - [无人值守验证](../UNATTENDED_VERIFICATION.md)
   - [白板并行开发总纲](../WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md)
   - `docs/design/README.md`
3. 先确认基线是绿的：
   ```bash
   flutter test test/acceptance test/ui/whiteboard test/data/whiteboard test/domain/whiteboard \
     test/whiteboard_canvas test/data/workbench_ai test/domain/workbench_ai test/ui/desktop
   ```
   或直接看该提交的 CI。
4. 新的白板 Gate 先写成 `test/acceptance/` 下的脚本化模型场景，参考现有场景和 `ScriptedWorkbenchRuntime`。真人只看主观项。
5. 需要真实长任务时，在运行 App 的机器上设置 `HIA_TASK_OLLAMA_MODEL`；需要 ollama.com 云端模型时再设置 `OLLAMA_API_KEY`。设置方法见 P6 Ollama 交接。
