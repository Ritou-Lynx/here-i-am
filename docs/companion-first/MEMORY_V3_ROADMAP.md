# Memory V3 Roadmap

> 日期：2026-06-28（下午修订）
> 设计源：`docs/memory-research/MEMORY_PROPOSAL_V3.md`
> 状态：Phase 0 跳过 / Phase 1 backend ✅ / 1.5 / 1.6 详细可执行；其余 phase 进入时再细化

---

## 总览

按依赖关系切多个 phase。**UI 设计 vs UI 实现** 是分开的：现有 UI（~3000 行）短期复用，等设计稿出来再重做。

| Phase | 目标 | 状态 / 工程量 |
|-------|------|------|
| 0 | 有限清理 + 停血 | ❌ 跳过（停血早已完成；pkm/card_agent 删除留到 Phase 5） |
| 1 backend | Memory Card 表 + Service + Agent + Drift migration | ✅ 完成 |
| **1.5** | **V3 Lab dev screen + DI 接入**（让 backend 真机可测） | ⏳ 1–2 小时 |
| **1.6** | **数据源切换**（现有 UI 改读 V3 表） | ⏳ 1 周（机械任务） |
| 1.7 (deferred) | UI 重新设计（Episode / Saga / Entity / Insight 容器、待审信号、需要用户出设计稿） | ⏳ 时间不定，依赖用户 |
| 1.8 (deferred) | 1.7 设计 → 实现 | ⏳ 1–2 周 |
| 2 | 检索基础（FTS5 + DB 过滤 + intent 模板骨架） | ⏳ 1 周 |
| 3 | 语义检索（embedding + 融合排序） | ⏳ 1 周 |
| 4 | Dreaming 自动产物（Fragment / Entity / Episode / Saga） | ⏳ 2 周 |
| 5 | 旧代码清扫（pkm/card_agent + shared_life_* + Memex legacy） | ⏳ 2–3 天 |

**MVP 可用版本（1.5 + 1.6）：约 1 周**。完整 V3 + 新 UI：6–8 周（取决于用户出 UI 设计稿的节奏）。

### UI 工作线说明

- **现有 UI** 已经覆盖 Memory Summary Card（937 行）/ Full Detail View（920 行）/ Memory Review（410 行）/ 悬浮球（253 行）等
- **短期策略**：1.6 把现有 UI 的数据源切到 V3 表族，先让 V3 可用
- **长期策略**：用户对当前 UI 不完全满意，1.7 / 1.8 阶段重新设计 + 实现，但不阻塞 backend 推进
- **新概念 UI**（Episode 容器、Saga 容器、Entity 详情视图、待审信号、Insight 体系展示形式）属于 1.7 范围，需要用户先出设计

---

## Phase 0: 跳过

原计划的 Phase 0 内容已经实际不需要：

- `ConversationCaptureService` 早已被删除，只剩 no-op handler 排空旧任务
- companion agent prompt 已经清理过
- `pkm_agent` / `card_agent` 删除涉及 14+ 文件，留到 Phase 5 一次性清扫

详见后面 Phase 5。

---

## Phase 1 backend: ✅ 完成（2026-06-28 下午）

### 产物

- ✅ `lib/data/memory_v3/db/tables.dart` — 17 张 V3 表
- ✅ `lib/data/memory_v3/models/organized_record.dart` — Agent ↔ Service 数据契约
- ✅ `lib/data/memory_v3/services/record_organizer_service.dart` — `RecordOrganizerServiceV3`（persist / organizeAndPersist / deleteCard / recordUserCorrection）
- ✅ `lib/data/memory_v3/agents/record_organizer_agent/{agent,prompt}.dart` — V3 § 9 完整规范
- ✅ Drift schemaVersion 36 → 37，迁移 + 索引，build_runner 跑通
- ✅ `flutter analyze`: 0 errors

### 还没做的

- DI 注册（移到 Phase 1.5）
- UI 接入（移到 Phase 1.6）
- 端到端真实 LLM 测试（移到 Phase 1.5）

---

## Phase 1.5: V3 Lab dev screen（1–2 小时）

### 目标

让 backend 在真机上可测，不需要等 UI 切换完成。

### 任务

1. 在 `lib/data/memory_v3/services/record_organizer_service.dart` 已经有 `init(db)` + `instance` 单例模式
2. 找一处 app 启动钩子（很可能在 `lib/data/repositories/memex_router.dart` 或 `app_initializer.dart`），加 `RecordOrganizerServiceV3.init(AppDatabase.instance)` 调用
3. 新建 `lib/ui/memory/widgets/memory_v3_lab_screen.dart`：
   - 顶部输入框 + "整理并保存"按钮 → 调 `organizeAndPersist`
   - 下方 ListView 列最近 N 张 `memory_cards`（title + dropletLabel + retrievalText 前两行 + 情绪坐标小色块）
   - 点单条进 detail bottom sheet，展示全部字段（含 source / structured_fields / entity_links）
   - 长按单条删除（调 `deleteCard`）
4. 把入口加到 Settings 的 "Developer" / "调试" 分组里

### 验收

- ✅ 在 settings 找到 "V3 Lab" 入口
- ✅ 输入一段中文，点保存，能看到新卡出现在下方列表
- ✅ 点卡能看到完整 JSON 详情
- ✅ 长按能删除
- ✅ 用真实模型跑能验证 prompt 是否输出合规 JSON

### 不在 1.5 范围

- 视觉调优（这是临时调试屏，不追求好看）
- Editing（dev screen 不实现编辑）
- Search / filter（dev screen 不需要）

---

## Phase 1.6: 数据源切换（约 1 周）

### 目标

现有 UI（Memory Review / Full Detail View / 悬浮球 / 消息记录按钮 / 各处 tool call 入口）切换读 / 写 V3 表族。不重做 UI，只换 service / model 引用。

### 子任务

| 子任务 | 文件 | 工程量 |
|---|---|---|
| Memory Review screen 切到读 `memory_cards` | `companion_review_screen.dart` | 2–4 小时 |
| Memory Summary Card 适配新字段（`presentationModule` JSON 结构对齐） | `memory_summary_card.dart` | 4–8 小时 |
| Full Detail View 适配 | `shared_life_entity_detail_screen.dart` | 1 天 |
| 悬浮球路由到 `RecordOrganizerServiceV3` | `floating_record_ball.dart` | 1–2 小时 |
| 消息记录按钮路由到 V3 | chat 相关 widget | 2–4 小时 |
| `LifeMemoryCreate` tool call 改路由 | `lib/agent/built_in_tools/shared_life_memory_tools.dart` | 4–8 小时 |
| Memory Review "待审"信号最小实现（needsFollowUp 非空标个角标） | review widget | 2–4 小时 |
| 兼容老数据（如果用户旧表还有数据，要不就并存显示要不就隐藏） | 各处 | 1 天 |

### 验收

- ✅ 用户通过悬浮球记一条，看到它出现在 Memory Review，新表 `memory_cards` 有数据
- ✅ 用户在 Memory Review 点开详情，看到完整 V3 字段
- ✅ I 通过 `LifeMemoryCreate` tool call 记一条，落到新表
- ✅ 旧表数据不再增长
- ✅ `flutter analyze`: 0 errors

### 风险

- Summary Card 渲染对 `presentationModule` JSON 结构敏感，新 schema 跟旧 schema 字段名可能不一致，需要适配层 / 转换函数
- `shared_life_entity_detail_screen` 920 行，改动面大，要小心 regression
- 兼容老数据是不确定项 —— 如果用户旧表是空的（之前已清），不用兼容；否则要决定怎么处理

---

## Phase 1.7: UI 重新设计（依赖用户出设计稿）

### 范围

| 待设计 | 原因 |
|---|---|
| Memory Summary Card 视觉重设计 | 用户对当前 UI 不满意 |
| Full Detail View 重设计 | 同上 |
| Episode 容器 | V3 新概念，没现成 UI |
| Saga 容器 | V3 新概念 |
| Entity 详情视图 | V3 新概念 |
| Insight 体系入口 + 各面板内 Insight 展示 | V3 新概念 |
| 待审信号 / needsFollowUp 追问 UI | V3 新概念 |
| 主动陪伴 / 关心信号呈现 | V3 范围内但 Phase 4 后才相关 |

### 工作流

- 用户 / 设计师产出 Figma / 视觉稿
- 评审 + 收口
- 进 Phase 1.8 实现

### 不阻塞

Phase 1.7 不阻塞 Phase 2 / 3。即使没新 UI，V3 backend 可以继续推进检索、Dreaming 等能力。

---

## Phase 1.8: 1.7 UI 实现（1–2 周）

依赖 1.7 设计稿。实现细节进入时再细化。

---

## Phase 2: 检索基础（1 周）

### 任务清单（按顺序执行）

**注：以下内容已被上面 "Phase 0: 跳过" 替代，保留供历史参考。**

#### Step 1: 确认 origin / branch 状态

```bash
git checkout personal-lab
git pull
git status   # 确认干净
```

确认 `lib/data/memory_v3/` 目录和 V3 文档已经从今晚的 PR 合进来。如没有，先合 PR 再继续。

#### Step 2: 删已冻结的 agent

```bash
git rm -rf lib/agent/pkm_agent/
git rm -rf lib/agent/card_agent/
flutter analyze
```

修可能出现的 import 错误：
- 如果是 timeline UI / Memex 卡片渲染器引用 → 一起删
- 如果是核心 service 引用 → 改 import 或暂时注释，记下来下次处理

提示：这两个 agent 在 CLAUDE.md 里明确标"冻结"，理论上没有运行时引用。

#### Step 3: 停血 `ConversationCaptureService`

找到 `lib/data/services/conversation_capture_service.dart`（或类似路径），在 start / trigger / 入口方法加 early return：

```dart
// LEGACY: 不再扩展，等 V3 上线后删除
@deprecated
class ConversationCaptureService {
  void start() {
    return;  // Phase 0: disabled per V3 memory contract
  }
  // ... 其他方法同样加 early return
}
```

文件顶加注释 `// LEGACY - 不再扩展，等 V3 Phase 5 删除`。

#### Step 4: 改 companion agent prompt

打开 `lib/agent/companion_agent/prompt.dart`（路径以实际为准），grep 找：

- "后台整理" / "自动捕获" / "ConversationCapture" 等描述
- "记忆会自动..." 等暗示自动写入的句子

全部删除或改成"用户明确说'记一下'时才写入记忆"。

#### Step 5: 确认 app 能跑

```bash
powershell -File scripts\verify_critical_fixes.ps1   # CLAUDE.md 强制
flutter build apk --debug --flavor hereIAmDev
adb shell am force-stop com.memexlab.hereiam.dev
adb install -r build/app/outputs/flutter-apk/app-hereIAmDev-debug.apk
```

打开聊天，发条消息：
- I 还能正常回复
- 不再有"已记录"或类似的自动写入提示
- 聊天 → 悬浮球 → "记一下 X" 这种**显式记录路径还能工作**（用旧的 record_organizer，因为新的还没写）

#### Step 6: commit

```bash
git add -A
git commit -m "$(cat <<'EOF'
Phase 0: legacy cleanup before V3

- 删 pkm_agent / card_agent（已冻结）
- 停 ConversationCaptureService 自动触发
- companion agent prompt 删自动整理描述
- 准备进入 V3 Phase 1

详见 docs/memory-research/MEMORY_PROPOSAL_V3.md
和 docs/companion-first/MEMORY_V3_ROADMAP.md
EOF
)"
```

### 验收标准

- [ ] `lib/agent/pkm_agent/` 和 `lib/agent/card_agent/` 不存在
- [ ] `flutter analyze` 通过（或只有 deprecation warning）
- [ ] App 能启动并正常聊天
- [ ] `ConversationCaptureService` 不再写新 SharedLifeEntity 记录
- [ ] 用户显式"记一下"的显式路径暂时仍走旧 record_organizer（Phase 1 才替换）
- [ ] commit 推到 personal-lab

### 风险与回退

| 风险 | 检测 | 回退 |
|------|------|------|
| 删 pkm / card agent 后 app 启动失败 | flutter analyze 报错或 app crash | `git revert` 那个 commit，逐个 import 排查 |
| 停 ConversationCaptureService 后 chat 异常 | 聊天界面无响应 | 注释 early return 改成 feature flag，先关 flag |
| Companion prompt 改动让 I 措辞变奇怪 | 试聊几轮 | git revert 那段 prompt 改动，重新精修 |

---

## Phase 1: Memory Card 写入端 + Asset 层（1–2 周）

### 目标

实现 V3 § 4 Memory Card 表族 + § 6 Asset 层 + § 9 Record Organizer。让"用户显式记录"路径走新系统。Memory Review 切到读 `memory_cards`。

### 关键产物

1. Drift migration: 新建 V3 表族
   - `memory_cards` / `memory_card_sources` / `memory_card_structured_fields` / `memory_card_relations` / `memory_card_assets`
   - `assets` / `asset_analysis`
   - `user_corrections` / `memory_card_operations`
2. `lib/data/memory_v3/services/record_organizer_service.dart`
3. `lib/data/memory_v3/agents/record_organizer_agent/agent.dart` + `prompt.dart`（按 V3 § 9 规范）
4. Memory Review UI 切到读 `memory_cards`
5. 悬浮球 / 消息记录按钮 / 自然语言"记一下" → 新 Record Organizer
6. Full Detail View 适配新结构

### 验收

- 用户点"记录"按钮，新数据落到 `memory_cards` 而不是 `SharedLifeEntities`
- Memory Review 列表展示新卡（旧卡可暂时并存或隐藏）
- 用户能在 Full Detail View 编辑卡内容，编辑落 `user_corrections`
- Asset（图片/链接）独立保存到 `assets` 表

---

## Phase 2: 检索基础（1 周）

### 目标

实现 V3 § 7.1（DB 过滤）+ § 7.6（FTS5）。让 I 能用工具检索新 Memory Card。

### 关键产物

1. SQLite FTS5 索引（`memory_cards.retrievalText` 等）
2. `lib/data/memory_v3/services/memory_query_service.dart`
3. `lib/data/memory_v3/retrieval/intent_classifier.dart`（4 类 intent 分类）
4. `lib/data/memory_v3/retrieval/fusion_ranker.dart`（v1 公式骨架）
5. Chat agent 的 `memory_query` tool 切到新检索

### 验收

- I 能召回新 Memory Card
- intent 分类生效（事实型 / 进度型 / 反思型 / 情绪型）
- 已删除内容确保不被召回

---

## Phase 3: 语义检索（1 周）

### 目标

实现 V3 § 7.5（embedding）。本地优先 embedding 探索 + 融合排序权重调优。

### 关键产物

1. 本地 embedding 方案选型（bge-m3 / 其他）+ Android 包体测试
2. `lib/data/memory_v3/retrieval/embeddings.dart`
3. embedding 失效 / 重算机制（基于 contentHash）
4. v1 融合排序公式具体权重值确定

### 验收

- 语义检索能召回字面不匹配但语义相关的卡
- 本地 embedding 在 Android 上跑得动（首次加载 < 5s，推理 < 200ms）
- 模型切换时 embedding 能批量重算

---

## Phase 4: Dreaming 自动产物（2 周）

### 目标

实现 V3 § 5 Dreaming 表族 + § 10 后台任务 + § 10.4–10.7 各项边界。Episode / Saga 进 Memory Review。

### 关键产物

1. Drift migration: `memory_fragments` / `memory_entities` / `memory_entity_links` / `memory_episodes` / `memory_sagas` / `memory_saga_snapshots`
2. `lib/data/memory_v3/services/dreaming_orchestrator_service.dart`
3. `lib/data/memory_v3/agents/dreaming_agent/`（Fragment / Episode / Saga 三段，分别按 § 10.4–10.6 规范）
4. 触发分层实现（§ 10.7 五个阈值）
5. Memory Review 容器混合 Memory Card + Episode + Saga，带来源标识
6. Insight 入口（最小实现：Entity 详情 + Saga 列表）

### 验收

- Daily Dreaming 在充电 + Wi-Fi + 空闲时自动跑
- Fragment / Episode / Saga 按阈值生成
- 用户在 Memory Review 能看到 Episode / Saga 并可编辑 / 删除
- 用户修正后下次 Dreaming 不覆盖

---

## Phase 5: 旧代码清扫（2–3 天）

### 目标

V3 完全替代旧记忆系统后，一次性删 Memex legacy。

### 任务

1. 确认所有 UI 入口已切到 memory_v3（chat / Memory Review / 各面板）
2. 删 `lib/data/services/shared_life_*.dart`
3. 删 `lib/data/services/conversation_capture_service.dart`
4. 删 `lib/agent/conversation_capture_agent/`
5. 删 Memex 专属 timeline UI、旧卡片渲染器
6. Drift migration 删旧表（或保留只读 view）
7. CLAUDE.md 删红线 #3（"已耦合不再扩张"那段）
8. 一次性大 commit：`Here I am: full standalone, all Memex legacy removed`

---

## 跨 Phase 工程开口

这些不属于单一 phase，跨期持续：

### B 类（中等缺口）

- B6 本地 embedding 在 Android 上的实测可行性 → Phase 3 必须解决
- B7 Insight 体系最小集 → Phase 4 决定
- B8 Memory Card 里 "提到的 entity" 怎么呈现 → Phase 4 决定
- B9 "待审"信号设计 → Phase 1 上线 Memory Review 时定

### C 类（小缺口）

按需在对应 phase 实现时一次性定，不单独讨论。完整清单见 V3 § 14.C。

### 持续工程

- prompt 迭代调优（Record Organizer / Dreaming 三段）：每个 phase 上线后用真实数据跑
- 检索权重调优：Phase 2/3 上线后基于实际 query 表现调

---

## 决策与争议挂起

写 roadmap 时发现下面这些需要在执行前再讨论一次：

- Memory Card 的"待审"信号 UI 形态（Phase 1 前定）
- 自然语言"删除某 asset"的具体识别 prompt（Phase 1 或 2）
- Insight 各产物的展示容器具体设计（Phase 4 前定）
- 主动陪伴是否 MVP 范围（暂排除）
- 游戏 / 剧本存档是否 MVP 范围（暂排除）

---

## 下一步（你 / 任何接手的会话）

1. **如果 V3 Lab dev screen 已建好**：用真实账号登录，进 settings → V3 Lab → 输入文本验证 backend
2. **Phase 1.6 子任务可以并行启动**：选一个最容易的子任务（例如悬浮球路由切换）跑通端到端，再扩展到其他入口
3. **UI 设计稿**：用户准备 Memory Summary Card / Episode / Saga / Entity 详情等的视觉稿，进 Phase 1.7
4. 任何卡点写到 `DEVLOG.md`
