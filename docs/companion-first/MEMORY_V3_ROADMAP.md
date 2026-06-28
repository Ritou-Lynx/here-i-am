# Memory V3 Roadmap

> 日期：2026-06-28
> 设计源：`docs/memory-research/MEMORY_PROPOSAL_V3.md`
> 状态：Phase 0 详细可执行；Phase 1–5 草案，进入时再细化

---

## 总览

按依赖关系切 6 个 phase。每个 phase 完成后旧代码可逐步删，App 持续可用。

| Phase | 目标 | 工程量估算 |
|-------|------|------------|
| 0 | 有限清理 + 停血 | 1–2 天 |
| 1 | Memory Card 写入端 + Asset 层 | 1–2 周 |
| 2 | 检索基础（FTS5 + DB 过滤 + intent 模板骨架） | 1 周 |
| 3 | 语义检索（embedding + 融合排序） | 1 周 |
| 4 | Dreaming 自动产物（Fragment / Entity / Episode / Saga） | 2 周 |
| 5 | 旧代码清扫 + Memex legacy 全删 | 2–3 天 |

总估算：**约 6–8 周**到 V3 完整能力跑起来。MVP 可用版本（Phase 0 + 1）：**1–2 周**。

---

## Phase 0: 有限清理 + 停血（1–2 天）

### 目标

在开始写 V3 新代码前，做"已知安全"的旧代码清理 + 停掉 `ConversationCaptureService` 自动触发，让代码库进入"可以开 V3 新文件而不被旧污染"的状态。

### 任务清单（按顺序执行）

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

## 下一步（明天的你）

1. 工作电脑 `git checkout personal-lab && git pull`
2. 确认拿到 V3 文档 + memory_v3 目录 + 本 roadmap
3. 跑 Phase 0 Step 1–6
4. 任何卡点写到 `DEVLOG.md` 当天条目
5. Phase 0 完成后 commit + push，准备开 Phase 1
