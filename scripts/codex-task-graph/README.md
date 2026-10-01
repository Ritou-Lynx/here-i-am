# Codex Task Graph

本地只读的 Codex 任务脉络查看器：扫描 `~/.codex/sessions` 的 JSONL 会话记录，合并线程的 `parentThreadId` / `forkedFromId` 关系，再在浏览器里展示为一张自动布局的脑图。语义层（Goal、阻塞、验收、跨分支关系）写到本项目自身的 `data/task-graph.json`，不改动 Codex 的任何数据。

与 ChatGPT 的评审稿差异：不依赖 Codex App Server 的 `experimentalApi`，也不引入 React / React Flow / Electron；dagre 在 `public/dagre/` vendored，完全离线可用。

## 启动

Node 18+，零外部运行时依赖。

```bash
node server/index.js
# 默认 http://127.0.0.1:47837
```

Windows 双击启动（自动开浏览器）：

```
scripts\codex-task-graph\start.bat
```

可选环境变量：

- `PORT`：默认 `47837`（避开 Here I am dev bridge 的 47831）
- `CODEX_HOME`：默认 `%USERPROFILE%\.codex`

## 数据源

- `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`：读取 `session_meta`（含 `parent_thread_id` / `forked_from_id` / subagent 派生信息）与 `thread_name`，按 `createdAt`/`updatedAt` 排序。
- `~/.codex/session_index.jsonl`：合并权威命名（重命名后的线程在此更新）。

不依赖 Codex App Server / SQLite / Electron / Flutter。

## 图模型

```
Thread (from Codex, read-only)       Overlay (from task-graph.json, writable)
  id, sessionId, cwd, createdAt  +    pinnedTitle, goal, kind (work/goal/gate/handoff)
  parentThreadId, forkedFromId        runState, acceptanceState, blocker, nextAction, note
  snippet (preview from first user msg)
```

自动边：`parentThreadId` / `forkedFromId`（来自 Codex）。
手动边：`branch` / `depends_on` / `handoff` / `supersedes`（来自 Overlay）。

## 主要交互

- 点击节点 → 右侧详情面板（Codex 元数据 + 子分支列表 + 语义层编辑 + 关系编辑）。
- 双击空白处 → 适配视图。
- 拖空白处平移，滚轮缩放（以鼠标为中心）。
- 顶部过滤器：搜索线程 / 隐藏子代理 / 隐藏孤立根节点 / 只看当前前沿。
- “刷新”按钮：重新扫描所有 JSONL（默认 10 秒缓存；新开启的 Codex 任务点一下即可看见）。

## 当前前沿的判定

每棵树的“叶子”里：

1. 优先取语义层里 `runState ∈ {pending, running, blocked}` 的节点；
2. 若都没有 tagged，则取最近 `updatedAt` 最大的叶子。

被判定为前沿的节点用紫色描边高亮；与其相连的边也加深。

## 文件

- `server/codex.js` — JSONL 扫描 + 森林构建。
- `server/store.js` — `data/task-graph.json` 持久化（原子写入）。
- `server/index.js` — HTTP server；`/api/graph` 返回合并后的数据。
- `public/index.html` / `style.css` / `app.js` — 前端。用 dagre 自动布局（vendored in `public/dagre/`），零 CDN 依赖。

## 不做

- 不改 Codex 任何文件、不杀线程、不发新任务：read-only。
- 不解析聊天内容推断依赖（太噪）；脉络真相由线程派生关系 + Overlay 提供。
- 不实时 WebSocket；定期 (60s) 软刷新 + 手动「刷新」。
- 不做桌面跳转 / 深链 / 拖拽布局。

## 许可

仅本机使用。
