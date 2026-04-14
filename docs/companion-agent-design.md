# AI 陪伴角色系统改造方案

## 一、现有问题

### 1. 角色定位模糊
- PersonaAgent 是"角色设计师"（帮用户创建角色），不是角色本身
- CommentAgent 是角色的"嘴"，但只能在卡片下面评论，没有独立对话能力
- 两者割裂：设计角色的地方和角色说话的地方是分开的

### 2. 角色模型太简单
- `CharacterModel` 的 persona 是一个大文本 blob，style_guide/example_dialogue/pkm_interest_filter 创建后就合并丢失了结构
- 没有角色的"状态"概念（是否在线、上次互动时间、跟用户的亲密度等）
- memory 字段存在但没有被系统性使用

### 3. 角色选择是随机的
- comment_agent_handler 用 `Random(factId.hashCode)` 选角色
- 已在本分支修复（CharacterSelectionService），但还没有用户主动选择"主要陪伴角色"的机制

### 4. 没有独立的对话入口
- 角色只能在卡片评论区"说话"
- 用户无法主动找角色聊天
- 角色无法主动发起对话

---

## 二、目标体验

用户打开 APP，右上角看到自己选的陪伴角色头像。
红点提示有新消息。点进去是一个 1v1 聊天界面，像微信好友。

角色会：
- 用户发消息时快速回复（2-3秒内开始流式输出）
- 用户发了新记录后，主动在聊天里说一句（"看到你今天去了XX，怎么样？"）
- 记得之前聊过的内容，有连续感
- 根据用户最近的生活状态调整语气和关注点

---

## 三、架构设计

### 3.1 角色模型改造

```
CharacterModel (改造后)
├── id: String
├── name: String
├── tags: List<String>
├── avatar: String?
├── enabled: bool
├── persona: String              # 角色人设 prompt（结构化 markdown）
├── interestFilter: String       # 关注领域描述（从 persona 中独立出来）
└── isPrimaryCompanion: bool     # 是否为用户选定的主要陪伴角色（新增）
```

persona 内部结构（markdown，不是代码字段）：
```markdown
## Identity
你是用户的死党/闺蜜...

## Personality
直来直去，情绪饱满，喜欢用网络梗...

## Boundaries
不讲大道理，不说教，只负责陪伴和情绪宣泄...
```

不再在 persona 里混入 style_guide、example_dialogue、pkm_interest_filter。
interestFilter 独立为字段，供 CharacterSelectionService 使用。
example_dialogue 去掉 — 让 LLM 自己根据 persona 发挥，硬编码的对话示例反而限制了自然度。

### 3.2 记忆系统

存储位置：
```
workspace/Characters/
  {id}.yaml                    # 角色配置
  {id}_relationship.md         # 关系记忆
  {id}_emotional_state.md      # 情绪快照
```

#### 层级 1：用户画像（Identity）
- 来源：全局 `_System/memory/memory.json` 的 `archived_memory`
- 已有，直接复用
- 不需要改动

#### 层级 2：最近生活上下文（Recent Context）
- 来源：最近 2-3 天的 `Facts/{yyyy}/{mm}/{dd}.md` 原文
- 读取时截断到 3000 字符
- 不需要额外存储，每次对话时实时读取
- 已在本分支的 CommentAgent._getRecentFactsContext 中实现

#### 层级 3：关系记忆（Relationship）
- 存储：`{id}_relationship.md`
- 内容示例：
  ```markdown
  ## Ongoing Topics
  - 在纠结要不要跳槽到新公司，已经拿到 offer 但还在犹豫
  - 养了一只猫叫"团子"，经常提到

  ## Key Moments
  - 聊到跟父母的关系时比较敏感，不要主动提起
  - 上次说拿到了新 offer，很兴奋但也焦虑

  ## User Preferences
  - 深夜聊天比较多，这时候情绪更真实
  - 不喜欢被安慰"会好的"，更喜欢被倾听和调侃
  ```
- 更新时机：用户离开聊天界面时（`dispose`）
- 更新方式：LLM 调用，输入 = 本次对话 + 旧 relationship.md → 输出新版本
- 大小上限：2000 字符，超了让 LLM 压缩

#### 层级 4：情绪快照（Emotional State）
- 存储：`{id}_emotional_state.md`
- 内容示例：
  ```markdown
  最近情绪偏低落，工作压力大。上次聊天时提到加班很累，语气疲惫。
  当前需要：倾听和陪伴，不要给建议。
  ```
- 更新时机：跟关系记忆一起
- 更新方式：覆盖式，只保留最新状态
- 很短，200 字以内

### 3.3 陪伴 Agent（CompanionAgent）

新建 `lib/agent/companion_agent/`，不复用现有的 agent 框架。

核心设计：**直接调 LLM，不走 StatefulAgent + Tool 体系。**

```dart
class CompanionAgent {
  /// 流式对话 — 用于用户主动聊天
  static Stream<String> chat({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String userMessage,
    required List<ChatMessage> history,  // 最近 N 轮
  }) async* {
    // 1. 组装 context
    final persona = await _loadPersona(userId, characterId);
    final userProfile = await _loadUserProfile(userId);
    final emotionalState = await _loadEmotionalState(userId, characterId);
    final relationship = await _loadRelationship(userId, characterId);
    final recentFacts = await _loadRecentFacts(userId);

    // 2. 构建 messages
    final messages = [
      SystemMessage(_buildSystemPrompt(persona, userProfile, emotionalState, relationship, recentFacts)),
      ...history.map((m) => m.toLLMMessage()),
      UserMessage([TextPart(userMessage)]),
    ];

    // 3. 流式调用 LLM（无 tool calling）
    yield* client.generateStream(messages, modelConfig: modelConfig)
        .map((chunk) => chunk.textOutput ?? '');
  }

  /// 生成主动消息 — 用于角色看到用户新记录后主动说一句
  static Future<String?> generateProactiveMessage({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required String newRecordContent,
  }) async {
    // 类似 chat，但 prompt 不同：要求角色基于新记录主动发起话题
    // 返回 null 表示角色觉得这条记录不值得主动聊
  }

  /// 更新记忆 — 对话结束后调用
  static Future<void> updateMemory({
    required LLMClient client,
    required ModelConfig modelConfig,
    required String userId,
    required String characterId,
    required List<ChatMessage> conversation,
  }) async {
    // 1. 读旧的 relationship.md 和 emotional_state.md
    // 2. 一次 LLM 调用，同时输出新的关系记忆和情绪快照
    // 3. 写回文件
  }
}
```

### 3.4 主动消息机制

触发流程：
```
用户发新记录
  → submitInput
    → GlobalEventBus 发布 userInputSubmitted
      → 现有: card_agent_task, pkm_agent_task, comment_agent_task
      → 新增: companion_message_task（依赖 pkm_agent）
```

companion_message_task 的逻辑：
1. 读取用户选定的主要陪伴角色
2. 调用 CompanionAgent.generateProactiveMessage()
3. 如果返回非 null，存入 PersonaChatMessages 表（Drift）
4. 通过 EventBus 通知 UI 更新红点

角色不是每条记录都主动说话。prompt 里会告诉角色：
- 只在你觉得值得聊的时候才说话
- 如果内容跟你的关注领域无关，保持沉默（返回空）
- 不要每次都说话，频率大概 1/3 到 1/2

### 3.5 UI 改动

#### 右上角角色头像
- 在 timeline header 的 chat 按钮旁边加一个角色头像
- 带未读红点（数字）
- 点击进入聊天界面

#### 聊天界面
- 类似微信 1v1 聊天
- 角色消息在左（带头像），用户消息在右
- 流式输出（打字机效果）
- 底部输入框
- 角色的主动消息也显示在这里（带时间戳）

#### 角色选择/管理
- 保留现有的 CharacterConfigScreen（角色列表页）
- 新增：用户可以长按某个角色设为"主要陪伴角色"
- 角色模板：首次使用时展示模板选择页，用户选一个作为主要陪伴角色

### 3.6 要删除/改造的现有代码

| 现有代码 | 处理方式 |
|---------|---------|
| CommentAgent 在卡片下评论 | 保留，但同时把评论内容推送到聊天通道 |
| comment_agent_handler 的随机选角色 | 已改为 CharacterSelectionService（本分支） |
| PersonaAgent（角色设计师） | 保留，但降低优先级，后续可以让陪伴角色自己进化 persona |
| CharacterModel.memory (CharacterMemoryBlock) | 废弃，改用 relationship.md + emotional_state.md |
| defaultCharacters 里的 style_guide/example_dialogue | 合并进 persona，去掉独立字段 |
| CharacterEditPage 的大文本框编辑 persona | 后续改为结构化表单，但不在本次范围 |

---

## 四、实施顺序

### Phase 1：基础设施
1. CharacterModel 加 `isPrimaryCompanion` 和 `interestFilter` 字段
2. CharacterService 支持设置主要陪伴角色
3. Drift 新增 PersonaChatMessages 表
4. PersonaChatService（消息 CRUD + 未读计数）

### Phase 2：CompanionAgent 核心
5. CompanionAgent.chat() — 流式对话（无 tool calling）
6. CompanionAgent.updateMemory() — 对话结束后更新记忆
7. 记忆文件读写（relationship.md, emotional_state.md）

### Phase 3：UI
8. PersonaChatScreen（聊天界面）
9. PersonaAvatarButton（右上角头像 + 红点）
10. 集成到 TimelineScreen header

### Phase 4：主动消息（后续单独设计）
11. CompanionAgent.generateProactiveMessage()
12. companion_message_task handler
13. 注册到 GlobalEventBus 的 userInputSubmitted 订阅

### Phase 5：清理
14. 默认角色模板重构（合并 style_guide 等）
15. 废弃 CharacterMemoryBlock，迁移到文件记忆
