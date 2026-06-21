# Here I Am Feature UI Map

本文档是阶段 2 的工作文件：把当前软件里的真实功能放进新的 UI 系统。当前策略是保留现有功能和点击交互，先完成可用的视觉系统，再逐步验证 3D / 空间交互。

## 当前重要决策

1. Chat 现有功能全部保留。
   新视觉不能删掉聊天里已有的入口、按钮、富媒体、语音、任务胶囊、空间入口等功能。

2. 第一版仍以点击为主。
   圆柱大厅、记忆云漫游、捏合穿层、空间坐标等先作为设计方向和后续增强，不作为第一版必须交互。

3. 旧 Life Space 结构需要拆开。
   当前代码里的 `CompanionLifeSpaceScreen` 包含 Review、Schedule、Personal 三个页签，但这不是新 UI 的目标结构。新方案里不再保留一个泛化的 Life Space 三页签容器。

4. 能力留在对话，产物进入观察面。
   比如“帮我规划周六”仍发生在 Chat；规划结果进入 Schedule；相关记忆进入 Memory；花费进入 Ledger。

5. 圆柱屏可以先空置。
   屏幕位置和形状可以先立起来，主题内容随数据和记忆积累逐步长出。已确定屏：Memory Review、Schedule。候选屏：Health / Body、Interests / Culture。

6. 旧 Memex timeline 从主路径移除。
   不保留长时间线兼容入口作为新 UI 的主要页面。

## Life Space 结论

旧 Life Space 只是当前代码里的过渡容器，不作为新 UI 的正式信息架构。

拆分后：
- Personal / Settings 从生活空间中移出，保留为 Chat 右上角或集中按钮进入的设置/个人页面。
- Memory Review 成为圆柱屏幕中的一块屏，负责最近生成记忆的审阅和修订。
- Schedule 成为圆柱屏幕中的一块屏，负责日程规划和安排。
- 旧 Memex timeline 不再作为主 UI 长时间线存在。
- 其他圆柱屏可以先以空屏/薄雾占位存在，后续根据真实数据流和主题沉淀决定内容。

这意味着“生活空间”如果继续出现，只应指向未来的圆柱大厅/观察舱，而不是当前三页签集合。

当前代码对应：
- `CompanionFirstShell`：Chat 是默认 home。
- `PersonaChatScreen.onOpenSpaces`：当前从 Chat 打开旧 Life Space，后续需要改为进入新的观察舱或屏幕集合。
- `CompanionLifeSpaceScreen`：当前二级页面，后续需要拆分或替换。

## 功能归属表

| 功能 / 页面 | 当前位置 | 新 UI 层级 | 第一版形态 | 后续空间化 |
|---|---|---|---|---|
| Chat home | `PersonaChatScreen` | 世界层 | 保留全部现有功能，换视觉皮肤与局部动效 | 加入坠落入口、Presence ring、记忆沉淀 |
| Memory Review | `SharedLifeMemory` / capture 相关 UI | 产品层 | 圆柱屏之一，最近 1-2 天新生成记录瀑布流，对 / 改 / 撤 | 与记忆云点亮联动 |
| Schedule | `ScheduleAggregatorScreen` | 产品层 | 圆柱屏之一，日程规划和安排 | 可升级为圆柱大厅中的“日程”屏 |
| Personal | `PersonalCenterScreen` | 系统层为主 | 从 Chat 右上角或集中按钮进入，保持设置/个人页面形态 | 不进入圆柱主屏 |
| Settings | Settings pages | 系统层 | 普通列表和表单 | 只保留“舱口”入口概念 |
| Model / API config | Settings pages | 系统层 | 清楚稳定的配置页 | 不进入圆柱主屏 |
| Voice / rich capture | Chat 内 | 世界层 | 保留原入口 | 可绑定水汽 / 记录中状态 |
| Memory detail | 多处详情页 | 世界层 + 产品层 | 凝露卡视觉语言 | 从气泡水波展开 |
| Health / Body | 待整合 | 产品层 | 可先空置为候选圆柱屏 | 健康、睡眠、运动、身体状态 |
| Interests / Culture | 待整合 | 产品层 | 可先空置为候选圆柱屏 | 兴趣、影视、追星、阅读 |
| Old Memex timeline | `CompanionReviewScreen` / timeline | 移出主路径 | 不保留长时间线 | 被 Memory Review + 搜索/记忆云替代 |

## Chat 第一版处理

目标：在不破坏现有能力的前提下，把 Chat 变成新 UI 的主场。

保留：
- 现有消息流。
- 现有输入栏能力。
- 语音输入 / 语音通话入口。
- 富媒体 capture 入口。
- 任务胶囊 / agent 活动提示。
- 打开 Life Space 的入口。
- 现有错误、重试、加载、流式回复状态。

新增或改造：
- 暮雨玫瑰暗色雾面背景。
- 玻璃层质感，并叠加静态雨滴贴层：少量凝露点、雾面颗粒、细水痕；不做下雨动画。
- Presence ring，作为角色在场 / 思考 / 记录中的状态灯。
- 记忆沉淀提示：新记忆蒸馏完成时轻量出现。
- 圆柱入口仍然采用点击交互，但具体位置暂不定。

暂不做：
- 用坠落动画替代打开圆柱屏的普通点击。
- 用捏合手势替代按钮。
- 在 Chat 中放完整圆柱大厅。
- 删除任何当前已有聊天能力。

入口待设计：
- 中央呼吸圆环可以作为视觉“井口”，但聊天内容可能遮挡，不能直接假设它是唯一入口。
- Chat 右上角当前已有较多控件，不宜简单再塞一个常驻小圆环。
- 需要单独评估入口位置：顶部、头像/角色状态、输入区附近、浮动圆环、或与现有空间入口合并。
- 无论最终入口在哪里，第一版仍要保持明确点击路径，不依赖捏合或 3D 手势。

## Life Space 第一版处理

目标：拆掉当前三页签容器，不再把 Review / Schedule / Personal 统一塞进一个 Life Space。

保留：
- Chat 作为默认 home。
- Personal / Settings 从 Chat 显式入口进入。
- Memory Review 和 Schedule 作为未来圆柱屏的已确定两块。

改造方向：
- `CompanionLifeSpaceScreen` 后续需要重构或替换。
- 不再维护一个很长的 Memex timeline 作为 Review 主体。
- 圆柱屏先用点击入口和 2.5D 观察面承载，3D 交互后置。
- 未成形屏幕可以以薄雾/空屏占位方式存在，不必马上填内容。

暂不做：
- 正式圆柱大厅。
- 横滑转身切屏作为唯一导航。
- 大规模 3D 记忆云。

## Memory Review 第一版处理

目标：把“可审计、可纠正”的原则做成具体 UI。

形态：
- 圆柱屏之一。
- 最近 1-2 天新蒸馏记录的可下滑集合。
- 每条记录显示来源、摘要、类型、状态。
- 快捷操作：确认、修改、撤销。
- 点开进入凝露卡详情。
- 更早的长期内容不继续堆成无限 timeline。

后续：
- 与记忆云联动。
- 在质检台点某条，云中对应气泡点亮。

## Settings 第一版处理

目标：系统事务保持清楚，避免被世界观拖慢。

形态：
- 仍使用列表、表单、开关、测试连接按钮。
- 使用统一色彩和字体。
- 可以把入口命名/视觉处理为“设置舱口”。

不做：
- 坠落转场。
- 水波转场。
- 圆柱屏内部配置 API key。

## 第一版页面优先级

1. Chat 视觉系统接入，但保留全部功能。
2. 拆分旧 Life Space：Personal / Settings 走 Chat 显式入口。
3. Memory Review 圆柱屏 / Dew Card。
4. Schedule 圆柱屏。
5. Settings / Personal 入口和设置页轻量统一。

## 待确认

- Presence ring 在 Chat 中放在正中、顶部、还是作为头像/状态入口的一部分。
- 圆柱屏的第一版容器叫什么，以及如何从 Chat 点击进入。
- 圆柱屏除 Memory Review 和 Schedule 外，Health / Body 与 Interests / Culture 如何命名和归类。
- 新抽取记忆卡片如何重新设计，是否脱离旧 timeline card template 体系。
