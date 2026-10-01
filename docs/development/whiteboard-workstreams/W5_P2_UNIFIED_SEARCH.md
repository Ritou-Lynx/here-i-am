# W5-P2 — 统一只读搜索与 Context Envelope 交接

> 日期：2026-08-22
>
> 状态：provider-neutral 契约与 facade 闭环完成；待 W5 集成窗口接 Runtime tool registry
>
> 分支：`codex/whiteboard-w5-unified-search`

## 1. 本轮结果

新增统一、只读、可审计的 workbench 搜索边界：

- `SearchScope` 覆盖 Card library、Memory V3、Project Memory、产品对话与 Task artifact；Source 尚无独立安全搜索 scope；
- `SearchHitRef` 只返回稳定对象引用、有限标题 / snippet、归一化 relevance 与 provenance，不返回 Drift row、SQL、对象路径或 provider 私有事件；
- `SearchPermissionLane` 把内容库、User-truth、Project Memory、对话和任务产物分开授权；授权由产品侧单独传给 Tool Host，模型 payload 无法自授；
- `WorkbenchSearchFacade` 以 adapter 聚合各域，权限在调用前传入 adapter，并在 hit 出口再次 fail closed；单 adapter 失败不会泄漏异常文本或拖垮其它 scope；
- `WorkbenchSearchBudget` 同时限制 per-scope、总结果、标题 / snippet UTF-8 bytes 与完整响应 UTF-8 bytes；trace 明示拒绝、未支持、失败、候选、返回数和截断原因；
- `ContextSearchProjection` 把按需命中转成既有 `ContextRecallSnippet`，保留稳定 source ref，内容始终标记 `untrusted_content`，不复制巨型检索结果进 Context Envelope。

## 2. 已接真实 adapter

首轮只接边界清楚的三条生产只读入口：

1. `CardLibraryWorkbenchSearchAdapter`：复用 `UnifiedCardRepository.listCards`，只返回 `card:` hit；不把关联 Source provenance 冒充 Source 搜索，不加载 RichText / Source object 文件；受限授权按允许的 board ref 查询。
2. `MemoryV3WorkbenchSearchAdapter`：复用 `MemoryCardQueryService.searchCards + getCardsByIds`，刻意避开会追加 query-tuning log 的高层 recall 方法；不改变 Record Organizer / User-truth 规则。受限 card allow-list 使用固定 128 条 FTS evidence window，先过滤授权再应用请求的 per-scope limit；窗口耗尽时 trace 固定报告 `memory_permission_evidence_window`，不静默声称结果完整。
3. `ProjectMemoryWorkbenchSearchAdapter`：复用 `ProjectMemoryService.search`，allowed project ids 在 FTS candidate generation 前过滤；全 lane 授权也只覆盖本机已投影的 active project ids。

产品对话与 Task artifact 已有同一 adapter 契约和 fake 跨域验证，但暂未接生产实现：当前聊天 API 使用 `characterId`，尚未提供权威 `conversation_id` 范围搜索；Task artifact API 只有按 task 取全量产物，且 `contentJson` 可能包含 raw log / diff / storage ref。P2 不用裸 SQL或语义冒充补洞。

## 3. 安全与预算

- Search Tool 只接受 `request_id / query / scopes / budget`；未知字段拒绝。`authorization` 出现在模型 payload 会返回固定 `invalid_search_request`。
- scope 无 grant 时不调用 adapter；受限 grant 必须携带允许的 opaque container refs；adapter 输出的 scope、lane、adapter id 与 container ref 再验一次。
- stable ref 必须有产品命名空间，拒绝绝对路径、`file:`、`http:`、`https:`；adapter id 最多 8 个且使用受限产品 key。
- 默认 12 个结果、每 scope 8 个、标题 256 bytes、snippet 1536 bytes、完整响应 32 KiB；hard max 分别为 64、32、512 bytes、4096 bytes、64 KiB。
- 响应按实际 `jsonEncode` 后 UTF-8 bytes 迭代计量，receipt 中 `serialized_output_utf8_bytes` 与真实输出一致；超限按稳定排序从尾部裁剪，不切坏 Unicode。
- adapter receipt 区分 examined candidates 与 returned hits；Memory 受限 evidence window 达到硬上限时响应为 `partial`，trace 不包含异常消息、SQL、凭据、原始日志或 adapter 私有 payload。

## 4. 契约影响与拥有路径

新增文件：

- `lib/domain/workbench_ai/search/workbench_search_contract.dart`
- `lib/data/workbench_ai/search/workbench_search_facade.dart`
- `lib/data/workbench_ai/search/workbench_search_tool_host.dart`
- `lib/data/workbench_ai/search/context_search_projection.dart`
- `lib/data/workbench_ai/search/existing_search_adapters.dart`
- `test/data/workbench_ai/search/workbench_search_facade_test.dart`

没有修改 Card / Source / Memory / Project Memory / Conversation / TaskRoom 身份，没有 schema、migration、生成文件、白板 UI、Runtime 对话或 User-truth 写入变化。

## 5. 验证

- `flutter test --no-pub test/data/workbench_ai/search/workbench_search_facade_test.dart test/domain/workbench_ai/context --reporter expanded`：20 / 20 通过。
- `dart analyze lib/domain/workbench_ai/search lib/data/workbench_ai/search test/data/workbench_ai/search`：No issues found。
- fake adapters 覆盖五个 scope 聚合、调用前权限拒绝、返回后 container 过滤、总结果、Unicode UTF-8 snippet / 完整响应预算、稳定引用、异常脱敏、deterministic trace、Context Envelope codec 往返和模型自授字段拒绝；生产 adapter 回归另验证 Card library 只返回 `card:` hit，以及 Memory 获准项位于请求 limit 之后仍可从 128 条 evidence window 命中、窗口耗尽会诚实 trace。

## 6. 待集成与未完事项

1. W5 集成窗口把 `WorkbenchSearchToolHost.toolName` 注册到 Runtime dynamic tool registry，并从产品 permission profile 构造 `SearchAuthorization`；不得接受 Runtime 自报 grant。
2. 先冻结 `conversation_id → PersonaChatMessages` 的权威映射，再接 Conversation adapter；legacy `syncId == null` 的消息不能冒充跨设备稳定引用。
3. 为 Task artifact 提供只读 search projection：只索引经分类的安全摘要与稳定 artifact id，不能直接返回 `contentJson / storageRef / raw log / full diff`。
4. Card library 当前是确定性 substring 搜索，不声称语义搜索；Source 需要独立、只读、有界的 repository 搜索入口后再新增 Source adapter，不能把 Card 的关联来源字段当成 Source hit。
5. 本轮没有接 UI、Bridge transport 或真实 Codex，也没有做 Windows 真人入口验收；这些由 P1 / W5 集成闭环完成。
