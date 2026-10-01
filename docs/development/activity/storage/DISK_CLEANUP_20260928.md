# D 盘安全清理记录（2026-09-28）

## 结果

- 范围：仅 `D:\memex`；未沿 Junction、未清理其他盘或仓库外目录。
- 删除：29 个 Git 已忽略、无重解析点、可重新生成的休眠工作树缓存目录。
- 目标文件合计：18,447,607,360 bytes（约 17.181 GiB）。
- D 盘可用空间：10.052 GiB → 27.245 GiB；本轮实际净增 17.193 GiB。
- 首次普通权限删除被 ACL 拒绝；复核相同精确清单后，以提升权限完成。所有目标删除后均复核为不存在。

## 已删除的精确路径

`.dart_tool` 生成缓存：

- `.worktrees/whiteboard-w0-ai-integration/.dart_tool`
- `.worktrees/goal1-acceptance-53d2dc91-20260828/.dart_tool`
- `.worktrees/ble-heart-rate-gateway/.dart_tool`
- `.worktrees/legacy-cleanup-wave1-control/.dart_tool`
- `.worktrees/hr-live-tool-candidate-884dcd80/.dart_tool`
- `.worktrees/p4-r19-candidate-722a646d/.dart_tool`
- `.worktrees/p4-r18-candidate-2ed4b015/.dart_tool`
- `.worktrees/p4-final-candidate-7fa6cbb9/.dart_tool`
- `.worktrees/p5-persona-cleanup/.dart_tool`
- `.worktrees/p4-r17-candidate-1f77633a/.dart_tool`
- `.worktrees/p5-phone-readonly/.dart_tool`
- `.worktrees/p4-r16-candidate-66017099/.dart_tool`
- `.worktrees/p4-final-candidate-a36e5236/.dart_tool`
- `.worktrees/p4-final-candidate-884dcd80/.dart_tool`
- `.worktrees/p4-r20-candidate-e77045fa/.dart_tool`
- `.worktrees/p4-final-candidate-526db238/.dart_tool`
- `.worktrees/p4-final-candidate-77949971/.dart_tool`
- `.worktrees/goal1-acceptance-45f4/.dart_tool`
- `.worktrees/p4-acceptance-30a73ce3/.dart_tool`
- `.worktrees/whiteboard-w5-g2-staging/.dart_tool`
- `.claude/worktrees/distracted-bell-8e6225/.dart_tool`
- `.claude/worktrees/happy-germain-fd5ed7/.dart_tool`
- `.claude/worktrees/friendly-mirzakhani-74e840/.dart_tool`

Android 构建中间产物：

- `.worktrees/legacy-cleanup-wave1-control/build/app/intermediates`
- `.claude/worktrees/happy-germain-fd5ed7/build/app/intermediates`
- `.claude/worktrees/friendly-mirzakhani-74e840/build/app/intermediates`
- `.claude/worktrees/distracted-bell-8e6225/build/app/intermediates`
- `.worktrees/hr-live-tool-candidate-884dcd80/build/app/intermediates`
- `.worktrees/ble-heart-rate-gateway/build/app/intermediates`

## 明确保留

- 主目录 `build` 与 `.dart_tool`，避免干扰正在运行的 P6 / A3F-R3 工作。
- `tmp/p6-r7-review`、`tmp/a3f-r3-w0` 及 A3F-R3 设备 Gate 目录。
- `build/portfolio-cleanup`、全部工作树、源码、未提交/未跟踪内容、`.git`、数据库与原始验收证据。
- 所有 `build/app/outputs`；已复核四个含 APK 的输出目录仍在，每个保留 2 个 APK。
- `checkin-off-fix` 与全部 P6 工作树缓存，因仍有关联 Gate / 验收链，不纳入本轮。

## 边界

未执行 `git clean/reset/stash`，未删除或归档工作树，未构建、安装、操作设备、提交、推送或部署。后续若继续清理，须重新核对活动聊天、工作树状态和候选哈希绑定产物。
