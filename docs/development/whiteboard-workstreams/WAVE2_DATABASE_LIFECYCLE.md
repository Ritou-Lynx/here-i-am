# Wave 2：Desktop 数据库生命周期 P0 返修

## 结论

- 分支：`codex/whiteboard-wave2-db-lifecycle`
- 基线：`codex/whiteboard-wave1-integration@c15a3eb9`
- schema 保持 60；未修改 Card / Source / Board / Anchor 身份或迁移。
- 用户现场的 Bilibili 保存异常不是 provider 解析错误，而是共享 Drift isolate 已被关闭；同一故障会同时令首页、卡片库和白板读取失败。

## 根因

Desktop `main()` 先执行 `AppDatabase.init(userId)`，`MemexRouter` 及若干前后台入口还会再次调用。旧实现只合并“正在并发”的同用户初始化；第一次已完成后的顺序同用户调用仍进入 `_openForUser()`，关闭当前 singleton 并建立新实例。

`WhiteboardDataBootstrap` 又永久缓存第一次创建的 `UnifiedCardRepository`。因此第二次初始化后，UI 仍通过旧 Repository 向已经关闭的 isolate channel 发送 `whiteboard_sources` 等查询，精确产生 `Bad state: Tried to send request ... connection was closed`。

## 修复

1. `AppDatabase` 记录 `activeUserId`；已完成的同用户初始化成为 no-op，不替换连接。
2. 所有初始化（包括不同用户）进入同一串行队列，避免不同用户并发关闭半初始化连接。
3. 真正 user switch 仍明确关闭旧连接并建立新连接；`WhiteboardDataBootstrap` 绑定当前 `AppDatabase` 实例，实例变化时废弃旧 Repository future 并重建。
4. `AppDatabase.close()` 变为幂等且共享同一个完成 Future；多个并发调用者都会等待真实关闭结束。若关闭的是 singleton 所有者，同步清空 `_instance` 与 `activeUserId`。备份、删号等既有显式关闭路径不会再留下 `isInitialized == true` 的假状态。
5. 页面和 `UnifiedCardRepository` 不获得关闭生产共享连接的权限；测试仍关闭自己注入的内存连接。

## 现场归属

排查时实际运行进程来自 `D:\memex\build\windows\x64\runner\Debug\memex.exe`，不是 Wave 1 集成 worktree 的 exe；主 `v3-lab@f9557283` 与 `c15a3eb9` 已分叉。主工作树未提交的 W5 diff 只涉及 workbench runtime / bridge 超时，没有修改 `AppDatabase.init/close` 或 Bootstrap，因此“另一个窗口在写代码”本身不会关闭运行进程的数据库。两个分支都继承了本次修复前的生命周期缺陷，任何实际触发顺序二次 init 的代码路径都可能暴露它。

## 验证

- 新生命周期回归 5/5：顺序同用户、并发同用户、真实用户切换、显式关闭后重开、并发关闭共同等待完成。
- Unified Repository 18/18。
- Link ingestion + import UI（含 Bilibili link-only 预览、确认提交）37/37。
- Desktop 冻结路由、首页 ViewModel 与工作台壳 30/30。
- 合计 89/89；改动文件定向 analyze 零 issue。
- `whiteboard_index_screen_test.dart` 的旧夹具已补 `desktopPlatformOverride`，6/6 通过；只修测试运行环境，不改产品路由。

## 集成提示

此修复改动 `lib/db/app_database.dart`，属于全局连接所有权修复，应先由集成窗口审计主分支现状，再与视觉和 provider 分支汇合。不要通过捕获 closed-connection 后静默重建数据库来替代本修复。
