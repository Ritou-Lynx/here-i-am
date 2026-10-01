# MDA-2 A3-E — Android 屏幕事件时间与授权连续性方案

> 状态：独立架构任务已完成并通过 W0 文档审计；只接受为条件性实现候选，尚未授权实现；2026-09-16。
> 起点：`v3-lab@6ea772f18bb1ad7b50a5a04eafc3e972af91116c`。
> 触发证据：[A3-D OEM 延迟解锁失败](android/a3d_device_gate/6ea772f1/OEM_DEFERRED_UNLOCK_FAILURE.md)。

## 本包要回答的问题

在 Android 14+ cached process 会延迟或合并 context-registered screen broadcasts 的前提下，给出一个能同时证明以下两件事的最小产品方案：

1. `screen.interactive` / `screen.non_interactive` / `session.unlocked` 使用真实发生时间，不以 callback/query 收件时间替代；
2. 若事件读取依赖 Usage Access，只接受发生在可证明连续授权的 epoch 内的事件；cached、process death、revoke/regrant 或 OEM gap 不得被回填成 fresh。

## 工作范围

- 只读核对 Android 官方能力与当前 A3-I/A3-D 源码、MDA wire/coverage/freshness 契约。
- 比较至少三类方案：
  - foreground-only、后台一律 unknown；
  - 独立且用户可见的 activity FGS + 权限边缘/epoch/fence；
  - 可提供系统发生时间的其他 Android 官方接口或用户控制自动化。
- 对每个方案写出：能证明什么、证明不了什么、权限与隐私、OEM/进程死亡行为、耗电/常驻通知、撤销/重授、恢复、最小改动面和真机 Gate。
- 给出唯一推荐或明确 no-go；不得以概率、短时间阈值、mtime、当前 AppOps 状态或“通常会及时投递”冒充权威。

## 不做

- 不改生产代码、Manifest、Gradle、依赖、Core/wire/schema、BLE、Companion FGS、check-in 或 UI。
- 不构建/安装 APK，不调用 adb，不操作手机，不读真实聊天/Memory/用户数据。
- 不 push、不发布，不把设计结论提升为 A3-D 通过。

## 交付与验收

- 在 `docs/development/activity/mda2/android/a3e/` 提交方案、证据表、风险与建议 Gate，并留下干净 commit/handoff。
- 官方 API 结论必须带一手文档链接；源码断言带文件与行号。
- W0 独立核对关键 API、失败反例与范围，再决定：接受某方案进入实现、维持 foreground-only，或停止 Android screen source。
- 任一实现都必须形成新 APK hash，并从零重跑 A3-D 全矩阵；旧局部通过证据不继承。

## 派发回执

- task/thread：`01a0a5e9-8177-7ca3-a4fe-62e528a3d455`
- Worktree：`C:/Users/ExampleUser/.codex/worktrees/5ab6/memex`
- 起点：detached `6ea772f18bb1ad7b50a5a04eafc3e972af91116c`
- 路由：L2，`gpt-5.6-sol / high`
- 首次状态：已确认精确基线和 docs-only 拥有路径，正在建立 `codex/mda2-a3e-architecture-20260916` 分支；未修改生产源码。

## W0 回收裁决

- worker commit：`45daa2d9e7a8aa28ddf044ebfc70c31e0c4313d9`，相对固定基线只新增两份 Markdown，worktree clean，`git diff --check` 通过。
- W0 独立核对 Android cached broadcast、UsageEvents 原始时间、FGS 类型/后台启动/通知约束及当前源码接收时间路径，结论与交付相符。
- 接受的仅是 prospective、fail-closed 架构候选：独立且用户可见的 Activity FGS + AppOps watcher + 持久 boot/epoch/owner fence/query cursor + 原始 UsageEvents timestamp。
- 历史 backfill、当前 AppOps 推断过去连续授权、receiver 收件时间冒充 occurrence time，以及复用 BLE/Companion FGS 均为 no-go。
- 主线选择性集成：`v3-lab@c240a83f26e4235821b8b0472e9c091f1e6c2ed7`，父提交精确为 `6ea772f1`，两文件 blob 与 worker commit 一致，index 为空；未改生产代码、构建或设备。
- 下一停止点是产品 Gate：是否接受明确 opt-in、持续通知、额外耗电与 OEM/商店限制，再决定是否创建独立实现包；未确认前不派发实现。
- 详细审计见 [W0 验收](android/a3e_review/45daa2d9/W0_ACCEPTANCE.md)。
