# Chat Message Addenda — 消息附件块基础设施

> Phase 0：让 Chat 消息（包括角色消息）能挂载结构化的"附加内容"——图片、卡片、链接预览、记忆引用等。
> 这是 Reading Companion / 嵌套卡片 / 角色多模态输出共同的基础设施。

---

## 背景

目前 `PersonaChatMessages.attachmentsJson` 字段只走用户上行的图片（base64 编码 WebP）。角色消息只能发文字。Reading Companion、日程提醒、健康指标、链接预览、"我想起那次..." 的旧记忆 — 都被这堵墙挡住。

**Phase 0 不引入新表、不做 DB migration**。在现有 `attachmentsJson` 字段上扩展语义，用 `type` 字段做 discriminator。

---

## Schema 演进

### 旧 schema（v0）

```json
[
  {"mimeType": "image/webp", "base64": "..."}
]
```

只有图片，靠 `mimeType` 区分。

### 新 schema（v1）

```json
[
  {"type": "image", "mimeType": "image/webp", "base64": "..."},
  {"type": "reading_card", "entityId": "...", "title": "...", "source": "xiaohongshu", "coverUrl": "...", "tags": [...]},
  {"type": "memory_recall", "entityId": "...", "summary": "..."},
  {"type": "schedule_chip", "eventId": "...", "time": "..."},
  {"type": "link_preview", "url": "...", "title": "...", "thumb": "..."}
]
```

每个 attachment 必须有 `type` 字段，其他字段按 type 自定义。

### 向后兼容

旧数据没有 `type` 字段 → 当 `image` 处理。
渲染层用 `att['type'] ?? 'image'` 取值，不需要数据迁移。

---

## 第一批 type 列表

| type | 谁会发 | 含义 |
|---|---|---|
| `image` | 用户、角色（未来） | 现有图片，base64 编码 |
| `reading_card` | 角色 | 想读的文章预览，点击进 Full Detail View |
| `memory_recall` | 角色 | "我想起..."的旧记忆引用 |
| `schedule_chip` | 角色 | 日程提醒、待办触发 |
| `link_preview` | 用户、角色 | URL 预览，标题 + 缩略图 |

Phase 0 只实现 `image`（向后兼容）和 `reading_card`（占位 widget，作为基础设施的第一个非 image 类型）。其他类型留待后续 PR 按需添加，每加一种就在 `MessageAddendumRenderer` 里多一个 case。

---

## 渲染架构

```
┌─────────────────────────────────────────────────┐
│ _buildBubble (用户 / 角色)                       │
│                                                  │
│  ┌──────────────────────────┐                   │
│  │ 文字气泡内容              │                   │
│  └──────────────────────────┘                   │
│                                                  │
│  ┌──────────────────────────┐                   │
│  │ MessageAddendumRenderer  │  ← 新组件          │
│  │   按 type 字段分发：       │                   │
│  │     image → ImageAddendumWidget               │
│  │     reading_card → ReadingCardAddendumWidget  │
│  │     ...                                       │
│  └──────────────────────────┘                   │
└─────────────────────────────────────────────────┘
```

### 文件清单

- `lib/ui/character/widgets/addenda/message_addendum_renderer.dart` — 分发组件
- `lib/ui/character/widgets/addenda/image_addendum_widget.dart` — 图片渲染（沿用现有逻辑）
- `lib/ui/character/widgets/addenda/reading_card_addendum_widget.dart` — 阅读卡占位 widget

每加一种 type，新建一个 widget 文件，在 renderer 里加一个 case。隔离改动面积。

---

## 角色如何决定发什么 addendum

后续阶段（不在 Phase 0 范围内）会给 `CompanionAgent` 加 tool：

```
attach_reading_card(entity_id)
attach_memory_recall(entity_id)
attach_schedule_chip(event_id)
attach_link_preview(url)
```

Agent 在合适话题命中或主动提及时调用，post-process 把 tool call 结果序列化进当前回复的 `attachmentsJson` 字段。

Phase 0 不做这块，先用 debug 入口手动注入测试 `reading_card`，验证渲染链路通。

---

## 视觉语言对齐

按 `UI design-here I am/UI_SYSTEM_SPEC.md` 的世界层规则：

- 角色消息气泡内的 addendum 沿用玻璃 + 凝露语言（半透明背景、淡边框、低饱和）
- 不引入高饱和高光，不引入新色相
- 尺寸是嵌入式（mini）—— 当未来 Memory Summary Card 完整版落地后，嵌入式版本就是它的小尺寸 variant，复用同一组件

---

## 不在 Phase 0 范围内的事

- 用户气泡的 attachment 渲染逻辑不动（先只让角色气泡能挂 addendum，避免回归现有用户图片渲染）
- `MessageAddendumRenderer` 跟现有 `_buildAttachmentWidgets` 暂时并存，后续 PR 再合并
- Companion Agent 的 tool 注册（Phase 1 加）
- 数据库索引、性能优化（attachmentsJson 字段已经是 nullable text，访问模式不变）

---

## 验证标准

1. `flutter analyze` 无新增 warning
2. 现有用户发图片功能完全不变
3. 通过 debug 入口手动给当前角色发一条"reading_card"附件消息 → 聊天里看到文字气泡下方挂着一张卡片
4. 卡片视觉跟 UI_SYSTEM_SPEC 的玻璃语言一致
5. 已读取数据库中没有 `type` 字段的旧 attachment 仍按 image 渲染（向后兼容验证）
