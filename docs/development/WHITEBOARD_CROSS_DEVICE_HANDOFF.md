# 白板 Desktop 跨电脑与跨窗口接力规范

> 适用范围：私人电脑与工作电脑轮流开发，以及 Codex / Claude Code / OpenCode 不同窗口接力。
>
> 当前功能基线：`v3-lab`，冻结点 `a0e28893`。F0–F4 已集成；后续不得另建平行 Card / Source / Board 身份。

## 1. 默认分支

- 日常顺序开发只使用 `v3-lab`。换电脑不等于换分支。
- 同一时刻只允许一台电脑修改并 push `v3-lab`；另一台开始前必须先同步。
- 小型、单窗口、可当日收口的 bug 直接在最新 `v3-lab` 修复。
- 只有用户明确启动多窗口并行、风险较大的跨模块改造或需要独立验收时，才创建隔离 worktree 与临时 `codex/whiteboard-*` 分支；最终仍合回 `v3-lab`。
- 不要为了“保险”长期保留两台电脑各自的开发分支，这会重新制造双版本。

## 2. 离开当前电脑前

1. 确认目标测试和静态检查结果。
2. 查看 `git status --short`，不要提交数据库、凭据、构建产物、`tmp/` 或 worktree 目录。
3. 提交本轮改动；同步更新 `I_PROJECT_STATE.md` 与 `DEVLOG.md`。
4. 再次确认分支为 `v3-lab`，然后 push：

```powershell
git switch v3-lab
git status -sb
git push origin v3-lab
```

5. 记录最终提交号。没有成功 push，不得告诉另一台电脑已经可以接力。

## 3. 到另一台电脑后

不要直接从未知状态运行 `git pull`。按以下顺序：

```powershell
git switch v3-lab
git status --short
git fetch origin
git pull --ff-only origin v3-lab
git status -sb
git merge-base --is-ancestor a0e28893 HEAD
```

判定规则：

- `git status --short` 出现已修改的跟踪文件：停止同步，先判断它们是不是本机未交接工作；不要自动 stash、reset 或覆盖。
- `git pull --ff-only` 失败：说明本地与远端已经分叉；停止并交给集成窗口核对，不要自行 rebase 或制造 merge commit。
- 最后一条命令退出码为 0：当前代码包含白板功能基线。
- 同步完成后先读 `AGENTS.md`、`docs/development/I_PROJECT_STATE.md` 和本文件，再读与任务对应的白板 workstream 文档。

## 4. 修 bug 的固定流程

1. 先从真实入口复现，写清楚预期、实际结果和最短复现步骤。
2. 找到既有拥有模块，不在 UI 临时造第二套 Repository、卡片或 Source。
3. 先补失败测试，再做最小修复；不顺带重排 UI 或升级依赖。
4. 涉及 Card / Source / Board / Anchor、数据库 schema、冻结路由或根依赖时，必须先停下并声明共享契约影响。
5. 至少运行受影响测试和定向 analyze；桌面交互、视频、IME、文件选择等行为需要 Windows 真窗口验收。
6. 更新对应 handoff、`I_PROJECT_STATE.md`、`DEVLOG.md`，提交后等用户确认再 push。

## 5. 通用“白板 bug 接力”提示词

```text
你现在接力 Here I am 的独立 Whiteboard Desktop。请先不要改代码。

先完整读取：
1. 根 AGENTS.md；
2. docs/development/I_PROJECT_STATE.md；
3. docs/development/WHITEBOARD_CROSS_DEVICE_HANDOFF.md；
4. docs/development/WHITEBOARD_PARALLEL_DEVELOPMENT_CHARTER.md；
5. 与本 bug 对应的 docs/development/whiteboard-workstreams/ 文档。

先检查并报告：当前目录、当前分支、git status、HEAD、origin/v3-lab，以及 HEAD 是否包含功能基线 a0e28893。当前分支必须是 v3-lab；若有未提交的跟踪文件、与远端分叉或不包含基线，停止并告诉我，不要 stash、reset、rebase 或覆盖。

本轮只处理这个问题：[在这里写 bug 和复现步骤]。

要求：先复现并补失败测试，再做最小修复；沿用 UnifiedCardRepository 与现有 Card/Source/Board/Anchor 身份，不改 schema、冻结路由、根依赖或视觉规范，除非先明确提出契约变更请求。完成后运行受影响测试、定向 analyze 和必要的 Windows 真窗口验收，更新对应 handoff、I_PROJECT_STATE.md、DEVLOG.md，并提交到 v3-lab。不要 push，最终给我提交号、修复原因、验证结果和未完事项。
```

## 6. 下一阶段“UI-0 规划窗口”提示词

```text
你现在负责 Here I am Whiteboard Desktop 的 UI-0 迁移规划，只做审计与规划，暂不修改生产代码。

先完整读取根 AGENTS.md、docs/development/I_PROJECT_STATE.md、docs/development/WHITEBOARD_CROSS_DEVICE_HANDOFF.md、白板并行开发总纲，以及总纲路由的视觉/组件/页面 spine 文档。确认当前为最新 v3-lab，HEAD 包含功能基线 a0e28893，工作树没有未提交的跟踪文件。

对照最终 HTML 预览 desktop/whiteboard_mvp/ 与当前 Flutter 功能版，建立“页面 → 功能入口 → 数据来源 → Flutter 文件 → 可复用组件 → 视觉差异 → 验收方式”的完整映射。范围至少包含：首页工作台、可收起侧栏、白板索引、全屏画布、卡片库、富文本编辑、链接导入、来源/视频研读、任务与记忆、林埃悬浮对话。

必须保留当前 F0–F4 功能和统一身份；不得恢复旧方案 A，不得新建第二套页面数据源，不得把 HTML mock 数据带进生产。给出分阶段实施顺序、文件拥有边界、哪些部分可以分窗口并行、每阶段验收清单、冲突风险和可直接复制的后续实施提示词。规划完成后先让我审阅，不要开始改 UI。
```

## 7. 当前阶段建议

先开一个新的 UI-0 规划窗口，不创建分支、不写代码。规划通过后，再决定首页外壳、卡片库/编辑器、画布、来源研读是否需要隔离窗口；全局 token、导航壳和路由整合必须由一个集成窗口统一拥有。
