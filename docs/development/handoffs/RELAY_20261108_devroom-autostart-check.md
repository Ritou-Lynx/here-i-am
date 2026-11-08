<!-- relay:contract v1 -->
# RELAY 2026-11-08 只读检查 Dev Room 自启残留

## 目标
#114 删除 Dev Room 后，只读检查用户电脑上是否还有 Dev Room Bridge / Tailscale 保活的自启项或运行中的进程，为是否需要停用提供依据。

## 完成标准
- [ ] 脚本轮 `tools/relay_scripts/cleanup/devroom-autostart-check.ps1`（mode=read）输出逐行 JSON，最后一行 `done`。

## 允许修改的路径
- tools/relay_scripts/cleanup/devroom-autostart-check.ps1
- 本合同文件

## 不做 / 边界
- 只读：不停任务、不删文件、不改 Tailscale 配置。输出只含任务名、状态和布尔值，不含本机路径、用户名、主机名。
- 本 PR 不需要 Codex 代码轮。

## 验证命令
- 脚本轮回帖。

## 需要真人的部分
- 无（只读脚本自动运行）。若发现残留，另开 write 脚本轮请用户点 👍 后停用。
