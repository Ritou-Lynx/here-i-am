# Here I Am Memory Card Visual Spec

本文档定义 Memory Summary Card 的视觉规范。它基于 `MEMORY_PRESENTATION_MODULES.md` 与 `CARD_SYSTEM_NOTES.md`，只描述卡片外壳、主模块和通用组件如何呈现。

配套静态样例页：`card-visual-mockups.html`。

## 1. 设计定位

Memory Summary Card 采用统一凝露外壳 + 固定主体组件。

它不是旧卡片系统里的多套硬模板，也不是只有普通文本框。每张卡都使用同一个 Card Shell，主体区域从 6 个 Primary Module 中选择一个：

- Text
- Quote
- Number
- Table
- Plan
- Media

通用组件不占主模块位置：

- LinkAttachment
- status
- tags
- emotion dot
- place mark
- related entity chips
- chatAboutIt

## 2. Card Shell

### 2.1 材质

外壳使用 L4 凝露卡语言：

- 厚雾玻璃底。
- 半透明白与当前皮肤背景混合。
- 极淡白色内描边。
- 边角可有轻微凝露、水痕、窗影。
- 阅读区域保持安静，装饰集中在边缘和角落。

避免：

- 紫色硬框。
- 强镜面高光点。
- 多层框中框。
- 每种内容换一套完整背景海报。

### 2.2 色彩

默认使用 R1 玫瑰雾：

- Background: `#F6F0EF`
- Primary soft: `#E3C2C4`
- Primary: `#C08E96`
- Primary deep: `#B27D88`
- Text strong: `#6F5A59`
- Text soft: `#A8908E`
- Surface: `rgba(255, 249, 246, .58)`
- Hairline: `rgba(117, 97, 95, .14)`

不同圆柱屏可以继承对应时辰皮肤，但卡片内部不使用多色主题编码。

### 2.3 尺寸

移动端建议：

- Review 瀑布流卡宽：容器宽度 - 24/32。
- 水珠展开卡宽：`min(370px, 100vw - 40px)`。
- 最小高度：按内容自适应，不低于 148。
- 常规最大高度：不超过首屏 60%，超出后进入 Full Detail View。
- 外壳圆角：24-30，延续凝露卡语言。
- 内边距：20-24。

桌面 / 平板：

- 单卡宽度建议 340-420。
- 圆柱屏瀑布流可使用 2 列，但每张卡仍保持同一信息结构。

### 2.4 Shell Layout

```text
┌─────────────────────────────┐
│ shell marks                  │  emotion / place / time / status / entities
│                             │
│ primary module               │  Text / Quote / Number / Table / Plan / Media
│                             │
│ optional attachments         │  LinkAttachment, if useful
│                             │
│ tags                 chat    │  tags + chatAboutIt
└─────────────────────────────┘
```

卡片整体点击进入 Full Detail View。`chatAboutIt` 和 `LinkAttachment` 有独立点击目标。

## 3. Shell Marks

### Emotion Dot

用于显示情绪坐标，是 Memory Summary Card 的必备外壳标注。

- 形态：6-9px 小色点或细环。
- 位置：顶部左侧。
- 低置信：空心 / 低透明。
- 可附极短文字，如 `情绪 · 中性`、`情绪 · 低置信`、`情绪 · 期待`。
- 不显示成对象评分、推荐分或好坏判断。
- 可点开调整坐标或标记为情绪中性。

### Place Mark

地点是外壳标注，不进入主模块。

- 形态：极轻 pin 图标 + 短地点名，或只有 pin 图标。
- 有多个地点：显示 `多地点`，详情展开。
- 可点开看缩略地图或来源地点列表。

### Related Entity Chips

人物、作品、地点等实体使用轻贴片。

- 不使用厚标签。
- 1-2 个优先显示，更多折叠。
- 视觉上比 tags 更靠近主模块上方，表示“这条记忆涉及谁/什么”。

### Status

生命周期状态只在需要时出现。

- 待确认、已完成、已撤销、需复核等。
- 使用微型文字 + 淡色边框。
- 不占据主模块视觉重心。

## 4. Primary Modules

### 4.1 Text

用途：AI 对事件、事实、偏好、感受、关系变化的整理结果。

视觉：

- 一段安静正文。
- 不设大标题。
- 1-3 句，最多 4 行。
- 行高 1.7-1.9。
- 可用轻微加深或水痕下划强调 `emphasis`。

示意：

```text
最近你对周末安排有点抗拒，更想把时间留给自己。TA 需要在之后提议活动时先问你的精力状态。
```

### 4.2 Quote

用途：保留原话、摘录或短句本身。

视觉：

- 固定引言样式，不是普通段落。
- 左侧可有细水痕竖线或大号浅引号。
- 原句字号略大于 Text，行距更松。
- 上下留白更明显。
- `quoteContext` 用小号软文字放在引言下方。

示意：

```text
“我想把这个周末留给自己。”

近期休息边界的一个明确信号。
```

### 4.3 Number

用途：主数值或简单数值关系是记忆重点。

视觉：

- 大数字是视觉中心。
- `metricLabel` 使用小号 caption。
- 单位贴近数值，不另起厚标签。
- `supportingMetrics` 以 1-3 个轻量行呈现。
- `sparkline` 如出现，只用细线或微柱，不做完整图表。

示意：

```text
睡眠
6.8 小时
入睡偏晚，时间略少。
```

```text
收入
¥1,500
TA 30% · ¥450
你保留 ¥1,050
```

### 4.4 Table

用途：多个字段并列，用户需要快速核对。

视觉：

- 不做传统重边框表格。
- 使用两列参数排版：左 label，右 value。
- label 使用 soft text，value 使用 strong text。
- 每行之间用极淡 hairline 或留白分隔。
- Summary Card 显示 2-4 个字段。

示意：

```text
外卖订单
商家    喜茶
金额    ¥38
内容    多肉葡萄、芝芝莓莓
```

### 4.5 Plan

用途：日程、待办、预约、阶段安排、完成状态。

视觉：

- 第一行显示安排摘要。
- 时间 / 截止 / 下一步用清楚的行式结构。
- 状态以轻标出现。
- 多事项最多 3 条。
- 可使用细竖线或小节点表达阶段，但不做复杂时间轴。

示意：

```text
牙科复诊
周五 14:30
状态  已预约
```

```text
论文修改
下一步  整理参考文献
截止    周日
状态    待处理
```

### 4.6 Media

用途：图片本身是记忆体验主体。首版只支持图片。

视觉：

- 顶部或主体区域显示封面图。
- 图片圆角略小于卡片圆角。
- 图片上不压大段文字。
- AI caption 放在图片下方。
- 多图使用 2-3 张轻拼贴或封面 + 数量标。

示意：

```text
[照片预览]
晚上在江边散步，你特别喜欢那盏蓝色路灯。
```

隐私：

- 敏感图可模糊预览。
- 加载失败回退 Text，并在详情保留来源。

## 5. Optional Components

### LinkAttachment

链接附件是通用组件。

视觉：

- 轻量行，不做主模块。
- 平台名 + 标题 + 打开图标。
- 多链接最多显示 3 条，更多折叠。
- 不抢占主模块内容。

示意：

```text
小红书 · 快闪活动详情  [打开]
```

### Tags

tags 是主题归属，不是水滴短标题。

- 放在底部或底部上方。
- 只显示少量。
- 使用低对比小 pill 或纯文字分隔。
- 标签必须来自用户的受控标签表 `tags.md`。
- AI 不新增、不翻译、不创建同义标签。
- Summary Card 最多显示 1-3 个 tag。
- 不用不同色相编码主题。

### chatAboutIt

固定操作：和 TA 聊聊 / 纠正这条记忆。

- 放在右下或底部操作区。
- 形态为轻按钮，不与 tags 混在一起。
- Summary Card 上使用短文案：`聊聊`。
- Full Detail View 或二级操作区可使用更完整文案：`和 TA 聊聊`。

## 6. Module Selection And Visual Output

AI 输出时，前端需要的不是完整视觉描述，而是结构化内容：

```text
presentationModule: Text | Quote | Number | Table | Plan | Media
modulePayload: ...
shellMarks: emotion / place / relatedEntities / status
linkAttachments: []
tags: []
```

前端根据 `presentationModule` 套用固定组件。视觉变化来自组件结构、内容密度和外壳标注，而不是生成新的卡片模板。

## 7. First Visual Mockup Set

第一轮需要画 8 张样例：

1. Text：普通对话记忆。
2. Quote：用户原话。
3. Number：睡眠 / 支出。
4. Number + split：收入分配。
5. Table：订单 / 预约信息。
6. Plan：活动安排。
7. Media：照片记忆。
8. Plan + LinkAttachment：分享链接形成的活动计划。

这 8 张样例覆盖第一版真实输入，不再扩展更多视觉模板。
