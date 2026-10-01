> 历史交接说明（2026-10-01 标注）：下文保留旧阶段事实，其中的工作区、分支、数据库版本与自动预查询描述不能作为当前接线依据。当前入口为 [本地开发交接](docs/development/LOCAL_DEVELOPMENT_20261001.md) 与 [项目状态](docs/development/I_PROJECT_STATE.md)。

# Memory V3 — 下次交接提示词

复制以下内容到新 Claude Code 会话：

```
继续 Memory V3 工作。

repo: D:\鱼\here-i-am
branch: claude/elastic-varahamihira-c6d4aa
latest: 06de960 test(memory_v3): add query benchmark

已完成的 Phase：
- Phase 2: FTS5 检索基础设施（memory_v3_fts、RecordOrganizerServiceV3 自动索引、IntentClassifier + FusionRanker）
- Phase 3 Lite: QueryExpander 同义词扩展 + relaxed fallback
- Phase 3 BugFix: 端到端召回修复（FTS 表缺失 + Companion prompt 路由 + 自动预查询注入 systemReminders）
- UI: Toast 圆角胶囊（ShowToast extension）

当前架构关键点：
- Companion 每次对话前自动调 MemoryCardQueryService.searchCardsResolved()，结果注入 state.systemReminders['memory_v3_cards']。LLM 不需要主动调 tool 就能看到记忆。
- RecordOrganizerServiceV3.init() 启动时兜底建 FTS 表 + reindexAllCards
- Schema 当前版本 38
- FTS5 在 Windows 测试环境不可用（winsqlite3 不含 FTS5），真机（sqlite3_flutter_libs）正常

构建/测试命令：
  powershell -File scripts\verify_critical_fixes.ps1
  flutter test test\data\memory_v3\retrieval\query_benchmark_test.dart
  flutter test test\data\memory_v3\retrieval\query_expander_test.dart
  flutter build apk --debug --flavor hereIAmV3
  $adb install -r -d -t build\app\outputs\flutter-apk\app-hereiamv3-debug.apk

下一步 Phase 3 Lite+：
1. 日常使用中积累坏例（query + 期望结果 + 实际结果），攒十几条后调同义词表
2. 同义词表在 lib/data/memory_v3/retrieval/query_expander.dart 的 _synonymGroups
3. Full Phase 3 embedding 暂缓，等 embedding provider 或本地模型路线确定

已知限制：
- Windows 上无法跑 FTS5 集成测试，用 flutter test --device-id <手机> 可在真机跑
- MiniMax 模型不主动调 memory_v3_query，依赖自动预查询注入（已解决）
```
