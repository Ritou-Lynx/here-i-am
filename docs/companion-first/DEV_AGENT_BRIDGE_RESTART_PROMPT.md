# Bridge 重启提示词 — Phase 4a+ Git 操作上线

回家后在私人电脑的 Claude Code 里粘贴下面这段。

---

```
帮我重启 Dev Agent Bridge，装上今天新加的 Git 操作端点。

## 背景

今天在 App 端和 Bridge 端各加了一套 Git 操作能力（Phase 4a+）：

Bridge 新增了三个端点：
- GET  /v1/projects/{id}/git-status  → 返回 ahead/behind/分支名/是否未提交改动
- POST /v1/projects/{id}/git-pull    → git fetch && git merge --ff-only
- POST /v1/projects/{id}/git-push    → git push origin {defaultBranch}

App 端对应：Dev Room 项目卡片里多了 Git 状态栏，显示"远程领先 N commits"时
出现[拉取]按钮，"本地领先 N commits"时出现[推送]按钮（推送需要 release_ops 权限档）。

health 端点也加了个 features 字段，返回 ["git_status", "git_pull", "git_push"]。

## 操作

1. 停掉旧 Bridge：
   powershell -File tools\dev_agent_bridge\stop_bridge.ps1

2. 启动新 Bridge：
   powershell -File tools\dev_agent_bridge\start_bridge.ps1

3. 验证 health 端点是否带了 features：
   浏览器打开 https://127.0.0.1:47831/v1/health
   确认返回里有 "features":["git_status","git_pull","git_push"]

4. 确认 git-status 能用，在 Bridge 终端里手动试一下

如果启动报错，把报错贴给我。
```
