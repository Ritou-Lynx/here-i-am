# P1-R × P2-R — Runtime 韧性与受限搜索组合交接

> 日期：2026-08-23
> 状态：隔离组合提交完成，待 W0 选择性集成与 Windows 真人 Gate

## 组合闭环

- `WorkbenchConversationCoordinator` 同时持有 provider-neutral continuity 与产品只读搜索；没有恢复 provider 写死或把 provider thread ID 当作产品对话身份。
- `WorkbenchConversationRuntimeGateway.resumeSession` 最终同时接收 `provider`、`providerSessionId`、`dynamicTools`。客户端保留 provider mismatch guard，并在 start / resume 的 `config.dynamic_tools` 注册同一 `search_workbench_content` 定义。
- 每次 tool call 都由产品侧重新组装授权；模型参数不能自授 Card、Memory V3 或 Project Memory 范围。Conversation / TaskArtifact 仍未注册。
- 单轮 deadline 同时覆盖 `readEvents`、搜索 adapter 与 `respondToToolCall`；任何一步挂死都返回 `runtime_timeout`，随后把 binding 降为 unavailable，并 best-effort interrupt + close local session。
- stop 在工具调用期间通过本地 stop signal 立即解除等待；只有 provider 明确终态才视为 settled。工具中停止、stop 失联或控制面挂死都会废弃 local session，不能接受迟到的 completed 事件伪装成功。
- interrupt、close 与清理期 binding 转移各自受独立 control timeout 约束；清理失败不覆盖原始 timeout、stop 或工具响应错误。

## 持久与非持久边界

- 默认 `InMemoryWorkbenchRuntimeBindingStore` 的 durability 仍是 `processMemory`。它只支持同一 Flutter 进程内 coordinator/Bridge local session 重建后的 provider resume。
- store 只保存 `RuntimeSessionBinding`；local session ID、turn ID、事件 cursor、prompt、工具响应与凭据都不是持久状态。
- 只有 active binding、没有最小 turn projection 与 provider reconciliation 时固定返回 `runtime_recovery_requires_reconciliation`。
- 本组合没有新增 Drift 表、migration、Memory 写入或共享配置。跨应用进程恢复仍须 W0 按 `W5_P1_RUNTIME_CONTINUITY.md` 的精确变更请求另行评审。

## 自动验证

- fake Runtime 覆盖：start / resume 工具重新注册、provider mismatch、普通多轮 continuity、挂死搜索超时、工具中 stop、工具响应 transport 失败、挂死 stop 控制有界失败。
- 联合回归包含 P1 coordinator/binding contract、P2 search facade/tool、原白板 coordinator 与桌面 overlay。
- 最终测试数量、analyze 与 diff check 结果在组合提交完成后由 W0 以提交报告为准。

## 真人验收

自动测试不能证明外部进程事实。W0 集成后须在唯一 Windows 候选串行确认：

1. 普通两轮对话后关闭/重开面板继续同一 provider thread；
2. Bridge / Codex App Server 重启后按 provider thread resume，且搜索工具仍可调用；
3. Card、Memory V3、受限 Project Memory 各一次真实搜索及拒绝/空结果；
4. 搜索进行中停止、Bridge 失联与超时 UI 均诚实显示，迟到响应不落为完成；
5. 原白板“整理选中卡片并连线”仍走独立受限 action coordinator，可恢复、可撤销。

未调用真实模型，未修改 Memory 核心/schema、手机设置、白板 UI/命令或搜索 wire contract。
