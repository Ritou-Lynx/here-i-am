# Here I am 暮雨玫瑰 UI 生图提示词

用途：把当前产品结构和“雨夜玻璃”参考图转成给 ChatGPT / 小周生成页面渲染图的约束稿。

核心原则：参考图只定义气质，页面结构以当前产品为准。不要让生图模型自动补常见 App 模板。

特别原则：**功能不存在，UI 不许出现。** 任何图里出现但当前软件没有对应功能、状态或交互的元素，都视为 AI 幻觉，不进入实现。

---

## 0. 总体硬约束

请把下面内容作为所有页面的共同约束：

```text
产品：Here I am（故我在），本地优先的 AI 陪伴应用。
参考图：“雨夜玻璃”。
目标平台：Android 竖屏移动 App，高保真 UI 渲染图，接近 390x844。

视觉基调：
- 深夜雨中玻璃、雾面水汽、模糊城市灯光
- 烟熏玫瑰、暗红棕、梅子色、少量暖铜光
- 半透明磨砂玻璃，但文字必须清晰
- 成熟、安静、亲密、可信，有夜晚陪伴感

严格禁止：
- 不要底部全局导航栏
- 不要 Chat / Memory / Schedule / Me 这种常驻 Tab
- 不要营销页、概念海报、科幻仪表盘
- 不要每条角色消息都重复显示头像
- 不要把观察面、设置页塞进 Chat 页面底部导航
- 不要添加当前软件没有的状态文案、徽标、角标、已读回执、双对勾、在线点、未定义按钮
- 不要绿色强调色
- 不要奶油风、全紫色、深蓝科技风
- 不要在画面里写设计说明

信息架构：
- Chat 是首页，是沉浸式全屏聊天空间。
- 观察面是从 Chat 显式入口打开的二级页面，不是底部导航 Tab。
- 设置页也是从 Chat 顶部或角色入口显式进入，不是观察面里的 Tab。
- Summary Card 属于观察面里的信息单元。
- 卡片详情页是从 Summary Card 点进去后的详情页。
```

---

## 0.1 功能真实性约束

给 ChatGPT / 设计师时必须附加这一段：

```text
请只画当前软件真实存在或明确要实现的 UI 元素。不要为了让画面更像聊天 App 而自动补功能。

如果某个元素没有在结构骨架或功能清单里出现，请不要画：
- 不要画消息已读/送达双对勾
- 不要画在线状态点
- 不要画角色名下面的状态小字，例如“今晚在这里”
- 不要画未定义的快捷按钮、角标、徽章、进度条、信号图标
- 不要画语音消息时长，除非当前页面真的有语音消息气泡功能
- 不要画“长按保存当前上下文”等未确认交互
- 不要把装饰性光点画成可点击按钮

视觉效果可以自由优化，但所有可见 UI 元素都必须能对应到现有代码里的一个组件、状态或明确产品决策。
```

当前 Chat 首页允许出现的功能元素：

```text
Header：
- 角色头像
- 角色名
- 更多按钮
- 非嵌入页面时可有返回按钮
- 玩具连接点仅在玩具服务存在/连接中时出现，不作为常规设计元素

更多菜单：
- 搜索聊天记录
- 自动朗读开关
- 打开观察/生活空间入口

消息区：
- 时间分割线
- 角色文字消息
- 用户文字消息
- 图片/富媒体附件预览
- 流式回复 / 正在输入状态
- 回到最新按钮
- 后台任务胶囊，仅在有任务时出现

消息操作：
- 复制
- 朗读角色消息
- 撤回用户消息
- 显式记录用户消息或附件

底部输入区：
- 加号/附件入口
- 文本输入
- 语音输入按钮
- 语音模式按钮
- 发送按钮
- 已选图片预览托盘

全局悬浮记录球：
- 现有组件是 `FloatingRecordBall`
- 图标是 edit_note 类记录入口
- 支持拖动 reposition
- 点击打开 quick-save sheet
- 不要改写成“已保存当前上下文”的状态按钮
```

---

## 1. 当前 Chat 首页结构骨架

给 ChatGPT 时可以直接贴这一段。它不是实际代码，而是页面结构约束。

```dart
Scaffold(
  background: DuskyRoseRainStage,
  body: Stack(
    children: [
      // Full-screen atmosphere layer.
      // Use the uploaded rain-glass reference only as background mood.
      RainGlassAtmosphereBackground(),

      Column(
        children: [
          SafeAreaTopPadding(),

          // Character presence anchor.
          // The avatar belongs to the whole chat scene,
          // not to each individual assistant message.
          ChatHeader(
            left: optionalBackButton,
            avatar: currentCharacter.avatar,
            name: currentCharacter.name,
            trailing: MoreButton(
              opens: [
                SearchChatHistory,
                AutoReadToggle,
                OpenObservationPanel,
              ],
            ),
          ),

          // Only appears when the companion is doing background work.
          OptionalTaskCapsule(
            text: "正在整理...",
            expandedDetail: optionalTaskDescription,
          ),

          Expanded(
            child: ChatMessageList(
              reverse: true,
              messages: [
                TimeDivider("今晚 22:18"),
                CompanionTextMessage(
                  text: "我在。外面雨声有点重，你刚回来吗？",
                  showAvatar: false,
                  actions: [copy, playVoice],
                ),
                UserTextMessage(
                  text: "今天下班路上又淋雨了，回家以后有点累。",
                  actions: [recordThisMessage, retract, copy],
                ),
                CompanionTextMessage(
                  text: "那今晚先别急着安排太多。我可以帮你把这条状态记下来，明天再看它是不是偶然。",
                  showAvatar: false,
                  actions: [copy, playVoice],
                ),
              ],
              states: [
                TypingIndicator,
                StreamingReplyBubble,
                JumpToLatestPill,
                EmptyStateWithLargeCharacterPresence,
              ],
            ),
          ),

          OptionalMediaTray(
            images: selectedImages,
            visibleWhenPlusButtonActive: true,
          ),

          // Bottom composer only. This is not a navigation bar.
          ChatComposer(
            addOrMediaButton: true,
            textInput: true,
            voiceInputButton: true,
            voiceModeButton: true,
            sendButton: true,
            recordSaveAffordance: true,
          ),
        ],
      ),

      OptionalHeaderActionOverlay(
        anchoredToTopRight: true,
        actions: [
          SearchChatHistory,
          AutoReadToggle,
          OpenObservationPanel,
        ],
      ),
    ],
  ),
)
```

给生图模型的解释：

```text
上面的代码是结构硬约束，不是灵感参考。请严格遵守：
- Chat 页面没有底部全局导航。
- 底部只有输入 composer。
- Header 只有角色头像、角色名、更多按钮；不要在角色名下面添加“今晚在这里”等状态文案。
- 角色头像是顶部 presence anchor，不要放进每条角色消息。
- 观察面入口藏在顶部更多菜单或轻量图标里。
- 角色消息尽量纯文本化、沉浸化，少做客服式气泡头像布局。
- 不要添加消息双对勾、已读回执、在线点、未定义徽章。
- 可以优化玻璃质感、间距、字体、按钮样式，但不要改变信息架构。
```

---

## 2. Prompt：Chat 界面

```text
请基于我上传的“雨夜玻璃”参考图，生成 Here I am（故我在）的 Chat 首页高保真 UI。

这是 App 首页，是沉浸式全屏聊天空间。请严格遵守我给你的结构骨架。

必须包含：
- 全屏暮雨玫瑰夜晚背景
- 顶部角色 presence：头像、角色名“暮雨”、更多按钮
- 顶部更多按钮，展开后可以看到：搜索、自动朗读、观察
- 中间是聊天消息流
- 角色消息不要每条都带头像
- 用户消息可以有显式“记录”操作入口，表示用户主动保存为 User-truth
- 可出现一个很轻的任务胶囊，例如“正在整理...”
- 底部只有输入 composer：加号、文本输入、语音、语音模式、发送
- 可出现全局悬浮记录球，但它必须对应现有 `FloatingRecordBall`：点击打开 quick-save sheet，拖动可移动

禁止：
- 不要底部全局导航栏
- 不要 Chat / Memory / Schedule / Me Tab
- 不要把观察面做成底部 Tab
- 不要每条角色消息都显示头像
- 不要在角色名下面添加状态小字，例如“今晚在这里”
- 不要添加消息已读/送达双对勾
- 不要添加在线状态点
- 不要添加当前代码没有的语音消息时长、信号按钮、徽章或快捷操作
- 不要把悬浮记录球画成“已保存当前上下文”的状态按钮

视觉要求：
- 雨滴玻璃背景只作为氛围，不要影响文字阅读
- 角色头像属于整个聊天空间的 presence anchor
- 聊天内容尽量纯文本、轻气泡、克制玻璃质感
- 页面要像真实 Flutter App 截图，而不是概念海报
```

---

## 3. Prompt：观察面板

```text
请基于我上传的“雨夜玻璃”参考图，生成 Here I am（故我在）的“观察”页面高保真 UI。

页面定位：
观察面是从 Chat 顶部显式入口打开的二级空间页面，不是底部导航中的 Tab，也不是点击切换的分类页。
它用于查看从 User-truth 中整理出的生活观察。

核心交互：
- 观察面必须是“横向滑动切屏”的空间容器。
- 用户左右滑动时，不同主题屏幕像围绕一个圆柱/转盘轻微旋转切换。
- 当前主题屏幕在中央完整显示，左右两侧应该露出相邻主题屏幕的窄边或模糊预览。
- 主题之间不是点击 Tab 切换，而是 swipe carousel / rotating panels / spatial pager。
- 可以有很轻的分页刻度、底部滑动提示或侧边透视阴影，用来暗示“可左右滑动”。
- 每个主题是一整屏观察面：记忆、日程、身体、账本、兴趣分别是不同屏幕，不是同一屏上方的五个按钮。

请参考项目里已经存在的圆柱大厅原型：
- 文件：`UI design-here I am/screen-carousel-v3.html`
- 标题：`Here I Am · 圆柱大厅 v3`
- HUD 文案：`HERE I AM · 观察舱 · 圆柱大厅`
- 提示文案：`横滑转身 · 圆柱整体绕你旋转`
- 关键结构：`#hall` 是透视相机，`#scene` 是 3D 场景，`#ring` 是整体旋转的圆柱环，`.panel` 是贴在圆柱内壁上的屏幕。
- 几何逻辑：每个 panel 使用 `rotateY(index * -60deg) translateZ(-R)` 放到圆柱内壁，切换时不是移动卡片，而是 `#ring` 整体 `rotateY`。
- 移动端比例参考：`R=360px`、`panelW=410px`、`panelH=660px`、`perspective=1700px`，前方面板约占手机宽度 88%-89%。
- 需要出现圆柱空间锚点：顶部/底部可见淡淡的同心椭圆环，表示站在圆柱中心看内壁屏幕。
- 面板状态：中央 front panel 清晰可读；侧边 panel 降低亮度/饱和度；转到背后的 panel 不可见。
- 右侧可以有竖向 rail 指示当前屏，当前项是一条更长的发光短线；不要做成横向 Tab。

推荐主题屏顺序沿用原型：
- 记忆：质检台 / 最近沉淀 / 云中定位
- 日程：未来事项 / 约会计划 / 提醒
- 账本：余额 / 支出 / 共同生活账目
- 身体：运动 / 睡眠 / 恢复趋势
- 书房或兴趣：共读 / 摘录 / 待读
- 未成形：新的共同生活流入后，这里会长出一面墙

必须包含：
- 顶部返回按钮，返回 Chat
- 当前居中的主题屏标题，例如“记忆”
- 页面总标题可以是“观察”，但不要抢过当前主题
- 副标题“把最近的生活线索放在这里”
- 当前主题屏里的今日概览：待确认记忆、今晚提醒、最近变化
- 当前主题屏里的观察卡片列表，例如：
  - “最近睡眠有点乱”
  - “周末有两个未定安排”
  - “这几天常提到下雨和疲惫”
- 每张卡片可点击进入详情
- 左右边缘要能看到相邻主题屏幕的存在，例如左侧露出“兴趣”的边缘，右侧露出“日程”的边缘
- 底部可以有一个细小的弧形进度线或 5 个极小分页点，但不能做成 Tab
- 可出现 HUD：`观察舱 · 圆柱大厅`、`横滑转身`

禁止：
- 不要底部全局导航栏
- 不要把 Settings / Personal 作为这里的 Tab
- 不要做点击切换 Tab
- 不要做一排“记忆 / 日程 / 身体 / 账本 / 兴趣”的五个分类按钮
- 不要把五个主题塞在同一屏顶部
- 不要做成普通列表页加顶部图标分类
- 不要画成普通横向 carousel 卡片堆叠；必须是用户站在圆柱中心看内壁屏幕
- 不要把左右箭头按钮作为主要交互，主交互是横滑转身
- 不要做复杂商业 dashboard
- 不要密集图表

视觉要求：
- 像一个安静的生活观察台
- 信息可扫描，但不要工具感过强
- 磨砂玻璃卡片低饱和，文字清晰
- 可轻微保留雨夜背景，但主要服务信息阅读
- 横向切屏的空间感要可见：透视、层级、边缘遮罩、轻微旋转都可以使用
- 不要为了表现 3D 牺牲可读性，当前中央屏幕必须清楚可读
- 保留“圆柱大厅”的建筑感：内壁玻璃屏、上下同心椭圆环、侧屏透视、当前屏正对用户
- 使用“雨夜玻璃 / 暮雨玫瑰”皮肤替换原型里的白天玫瑰雾，但空间结构必须沿用原型
```

如果 ChatGPT 生成了点击 Tab 或顶部分类按钮，追加这段纠偏：

```text
这个结果不符合交互结构。请移除顶部五个分类按钮和点击 Tab。
请按项目原型 `UI design-here I am/screen-carousel-v3.html` 重画：用户站在圆柱中心，多个主题屏贴在圆柱内壁，`#ring` 整体 rotateY；当前屏正对用户，侧边屏以透视角露出，背面屏不可见。
请重新生成，重点表现“横滑转身 · 圆柱整体绕你旋转”，而不是 tab navigation 或普通分类按钮。
```

---

## 4. Prompt：设置页

```text
请基于我上传的“雨夜玻璃”参考图，生成 Here I am（故我在）的设置页高保真 UI。

页面定位：
设置页从 Chat 顶部或角色资料入口显式进入。它是系统事务页面，不属于观察面，也不是底部导航 Tab。

必须包含：
- 顶部返回按钮，返回 Chat
- 标题“设置”
- 顶部用户/本地状态区域：头像、昵称、本地优先、数据加密状态
- 设置分组：
  - 角色与声音
  - 记忆与记录
  - 位置服务
  - 备份与导出
  - 隐私安全
  - 模型设置
  - 关于 Here I am
- 每行包含图标、标题、简短状态、右箭头
- 示例状态：
  - “本地数据已加密”
  - “最近备份：今天 22:10”
  - “语音：已启用”

禁止：
- 不要底部全局导航栏
- 不要把设置做成观察面的一部分
- 不要花哨个人中心
- 不要系统原生灰白列表

视觉要求：
- 成熟、克制、清楚
- 使用暮雨玫瑰夜晚主题，但设置项阅读性优先
- 图标和行距要像真实 App
```

---

## 5. Prompt：Summary Card

```text
请基于我上传的“雨夜玻璃”参考图，生成 Here I am（故我在）的 Memory Summary Card 高保真 UI。

页面定位：
Summary Card 是观察面里的信息单元，用来让用户快速确认一条被整理后的 User-truth 是否准确。

卡片内容示例：
标题：“最近睡眠有点乱”
摘要：“你这几天多次提到凌晨后才睡，早上醒来有些累。系统把它整理为一个暂时的生活观察，等待你确认。”
来源：“来自 3 条聊天记录”
时间：“最近 7 天”
标签：睡眠、状态、晚间
状态：待确认

必须包含：
- 一张主卡片，占据页面视觉中心
- 标题、自然语言摘要、来源、时间、标签、状态
- 来源证据入口
- 操作按钮：确认、修改、忽略
- 可点击进入详情的暗示

禁止：
- 不要像数据库字段表
- 不要做成厚重信息面板
- 不要加底部全局导航

视觉要求：
- 卡片像雨夜玻璃上的一层凝露信息
- 半透明、柔和、轻，但文字非常清晰
- 操作按钮要真实可点，不能只是装饰
```

---

## 6. Prompt：卡片详情页

```text
请基于我上传的“雨夜玻璃”参考图，生成 Here I am（故我在）的 Memory Card 详情页高保真 UI。

页面定位：
用户从 Summary Card 点入后查看完整内容、来源证据、结构化字段、相关实体和修订历史。

必须包含：
- 顶部返回按钮，返回观察面
- 标题“记忆详情”
- 更多按钮
- 主标题：“最近睡眠有点乱”
- 状态：待确认
- 内容区：自然语言整理结果
- 结构化字段：
  - 类型：生活状态
  - 时间范围：最近 7 天
  - 相关标签：睡眠、疲惫、晚间
- 来源证据区：2 到 3 条简短来源片段
- 相关实体区：例如“晚间作息”“工作日早晨”
- 修订历史区：创建、用户确认、用户修正
- 底部自然语言修正输入框：“补充或修正这条记忆”

禁止：
- 不要底部全局导航栏
- 不要把详情页做成后台管理系统
- 不要用大段不可读小字

视觉要求：
- 像可信的个人生活档案
- 信息层级清楚，可阅读，可编辑
- 保持暮雨玫瑰夜晚主题和磨砂玻璃质感
- 底部修正输入框类似轻量聊天输入，但不是 Chat 首页
```

---

## 7. 推荐工作流

```text
第一轮：用“五屏总览”看整体方向。
第二轮：只精修 Chat，因为 Chat 是首页，结构偏差成本最高。
第三轮：精修观察面、Summary Card、详情页。
第四轮：最后处理设置页，保证系统事务清楚克制。
```

如果 ChatGPT 又自动添加底部导航，直接追加这句：

```text
你违反了结构约束。请移除底部全局导航栏。Chat 首页只能有底部输入 composer，观察面和设置页必须通过顶部入口或返回关系进入。
```
