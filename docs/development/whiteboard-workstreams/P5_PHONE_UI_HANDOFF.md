# P5 手机只读连接 UI handoff

## 结果

- 新增 `PhoneMemoryConnectionPage` 与可注入 `PhoneMemoryConnectionFacade`：手机端默认关闭，只有手动开启 30 分钟会话后才显示复制连接码按钮；连接码没有明文回显。
- 桌面端提供受保护、关闭自动纠正的连接码输入框；提交时立即清空，并可显式断开。桌面只显示来源、状态、计数和时间的回执投影。
- 手机与桌面页面均明确 USB 转发由用户自行执行，不会自动建立转发；手机 App 退出、会话到期都需要重新授权。
- 新增桌面路由 `/phone-memory-connection` 与工作台侧栏“手机连接”入口；手机个人中心的“外部连接”也能进入同一自适应页面。
- 过期或最近回执不可用的桌面授权仍可显式断开，且不会被表述成在线连接。只有用户主动断开才恢复原有本地来源；到期或手机/USB 不可用不静默回退。
- 回执经过严格重建：固定来源、已知状态、仅 `episodes/fragments/sagas` 三个非负整数计数及可解析 UTC 时间；嵌套字段不能透传。
- 页面在异步开启、关闭或连接仍在执行时退出，会先脱离 UI/facade 监听，等各自 Command 结束最后一次通知后再释放 Command，避免通知已释放对象。

## 契约影响

- 只消费 `PhoneMemoryReadServer` / `PhoneMemoryReadClient` 的已定 API；没有改动 wire、服务、人格、上下文、依赖或 schema。
- `LivePhoneMemoryConnectionFacade` 只监听全局单例，销毁页面时仅移除监听，不会 dispose 单例。

## 验证

- 已格式化新增 UI/ViewModel 与相关测试，`git diff --check` 无空白错误。
- 编写 ViewModel 与 widget 测试，覆盖空码拒绝、嵌套回执脱敏、手机默认关闭/仅复制按钮、桌面掩码输入/提交清空、手动 USB 文案、失效授权仍可断开，以及 pending connect 后退出页面再完成不触发 disposed notifier。
- Windows 当前有进程锁定 `build\\unit_test_assets`，`flutter test` 在执行测试前的资产清理阶段失败；`dart analyze` 完成分析启动后在 Dart perf 目录清理时被系统拒绝，未得到可报告的干净退出。未清理构建目录或终止其他进程。

## 待集成

- 在主窗合并后重跑本 handoff 列出的两项专项测试和相关路径 `dart analyze`；若 Windows 锁释放，预期不需改动 UI 接口。
