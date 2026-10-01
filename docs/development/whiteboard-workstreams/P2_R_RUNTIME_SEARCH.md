# P2-R — 桌面 Runtime 搜索接线交接

> 日期：2026-08-23
> 状态：隔离功能分支完成，待 W0 审核、选择性集成与 Windows 真人 Gate
> 分支：`codex/whiteboard-p2-runtime-search`

## 本轮闭环

- `search_workbench_content` 以动态工具注册到普通桌面 Codex Runtime；新建与 provider thread resume 都重新携带同一受限工具定义。
- 工具参数只包含 `request_id / query / scopes / budget`，Runtime schema 首批仅公开 Card library、Memory V3、Project Memory；Conversation 与 TaskArtifact 未注册。
- 产品侧 `DesktopWorkbenchSearchAuthorizationFactory` 独立组装授权：Card library 与 Memory V3 为桌面只读 lane，Project Memory 只授予本机当前 policy-gated projection 中的 project IDs，空投影不发 grant。
- Conversation coordinator 分发 Runtime `tool_call`，调用既有 Host/Facade/真实 adapters，将完整预算响应与 trace 编码回传；未知工具、非法参数和 host 异常使用固定安全错误。
- 模型 payload 不能携带 `authorization` 扩权；既有 Host 的 exact-key 验证会固定返回 `invalid_search_request`，adapter 不执行。

## 权限与契约影响

- 搜索 wire contract、Memory V3 / Project Memory 核心、Card / Source / Anchor / Snapshot、手机聊天和白板写工具均未修改。
- 未新增 Conversation / TaskArtifact adapter；未读取 raw log、diff、storage ref；未写 Memory / User-truth。
- 无裸 SQL、schema、migration、依赖或生成文件变更。
- Project Memory 的 `allContainers` 永不由该 Runtime profile 发放；实际 allow-list 每次 tool call 从当前已投影 project IDs 重新读取。

## 验证

- Runtime/Search/Conversation 专项：23/23 通过。
- 覆盖动态 schema、产品授权、模型自授拒绝、UTF-8/总响应预算、确定性 trace、tool-call 分发、Bridge 本地 session 丢失后的工具重新注册及既有 conversation 回归。
- changed-file `dart analyze`：No issues found。
- `git diff --check`：通过。

## 待集成与 P5 解锁

1. W0 审核本提交边界并选择性合入 `v3-lab`，跑桌面 Codex / 白板组合回归。
2. 唯一 Windows 候选需用真实 Codex 完成至少一次 Card、Memory V3、受限 Project Memory 调用，并确认空/拒绝/预算 trace；本窗口未启动真人进程。
3. 上述 Runtime 搜索接线合入并通过集成 Gate 后，P5 才可开始 Memory V3 人格/关系只读 recall/context；P5 仍不得写 User-truth。
4. Conversation 需先冻结稳定 `conversation_id` 映射；TaskArtifact 需先提供排除 raw log / diff / storage ref 的安全摘要投影，之后才能扩充 Runtime schema。
