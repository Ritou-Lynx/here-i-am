# ADR: 白板引擎选型（W1 赛马结果）

> 状态：已选定（W1 第一阶段）
> 日期：2026-08-15
> 决策者：W1 画布工作流
> 上位文档：`WHITEBOARD_ENGINE_BAKEOFF_AND_VERTICAL_SLICE.md`、`WHITEBOARD_ENGINE_ADAPTER_ADR.md`

## 背景

引擎赛马文档要求比较三类候选：AFFiNE 可复用部分、BlockSuite、tldraw + 自有内容编辑器。
W0 已冻结适配器边界：所有引擎通过 `load / exportSnapshot / onOperation / setReadonly / focusItem` 接触统一 `WhiteboardSnapshot`。

## 候选评估

### 候选 1：AFFiNE 可复用部分

- 版本：AFFiNE 0.x（2026-08 快照）
- 许可证：MIT（核心），但整体是一个 Electron + React 应用
- 集成路径：无法直接在 Flutter 中复用；需要 WebView 包装或完整 fork
- 硬门槛：
  - ❌ 离线可运行：需要打包整个 Electron / Web 应用
  - ❌ 能由自有稳定 ID 驱动：AFFiNE 的 block tree 是其核心数据模型，适配成本极高
  - ❌ 桌面集成：与 Flutter 窗口、剪贴板、文件系统隔离
- 结论：**淘汰**。它是完整产品而非可嵌入引擎，拆出白板部分的成本远超重写。

### 候选 2：BlockSuite

- 版本：BlockSuite 0.x（2026-08 快照）
- 许可证：MIT
- 集成路径：Web 组件，需要 WebView 桥接
- 硬门槛：
  - ❌ 能由自有稳定 ID 驱动：BlockSuite 的 block/edgeless 模型是核心，强依赖其私有文档树
  - ⚠️ 卡片内容与白板布局可分离：理论上可以，但需要大量适配
  - ❌ 桌面集成：WebView 内部，与 Flutter gesture 系统隔离
  - ❌ 无障碍与输入：中文 IME 在 WebView 中需要额外处理
- 结论：**淘汰**。私有文档树与"卡片内容不写进画布 JSON"的硬约束冲突。

### 候选 3：tldraw + 自有内容编辑器

- 版本：tldraw 2.x（2026-08 快照）
- 许可证：tldraw 闭源 SDK 需付费许可；开源版 Apache-2.0 但有商业限制
- 集成路径：tldraw 是 React 组件，同样需要 WebView
- 硬门槛：
  - ⚠️ 可合法用于目标产品：开源版有商业使用限制
  - ✅ 能由自有稳定 ID 驱动：tldraw 的 shape 模型相对扁平
  - ✅ 卡片内容与白板布局可分离：适配层可行
  - ❌ 桌面集成：WebView 隔离
- 结论：**保留备选**。许可证和 WebView 桥接成本是主要障碍。

### 候选 4（追加）：Flutter 原生画布（CustomPainter + Transform + GestureDetector）

这是 tldraw + 自有内容编辑器思路的 Flutter 等价物：画布完全可控，不依赖任何 JS 引擎。

- 硬门槛：
  - ✅ 可合法用于目标产品：零外部依赖
  - ✅ 能由自有稳定 ID 驱动：产品 item_id 直接作为画布实体 ID
  - ✅ 卡片内容与白板布局可分离：BoardItem 只存布局，Card 通过 ID 引用
  - ✅ 扁平画布、显式分组、连线、跨白板引用：原生实现
  - ✅ 500 卡场景可持续交互：使用 `Transform` + viewport culling
  - ✅ 快照往返无损：adapter 直接操作 WhiteboardSnapshot
  - ✅ 全屏无常驻栏：完全由 Flutter widget tree 控制
  - ✅ 离线可运行：零网络依赖
  - ✅ 桌面集成：原生 Flutter gesture、剪贴板、文件系统
- 风险：拖放、框选、触控板手势需要自行实现；但这些是可控的 Flutter 代码
- 结论：**采用**。在 Flutter 桌面端，自建画布的维护成本低于桥接 JS 引擎。

## 决策

**采用 Flutter 原生画布作为 W1 画布引擎。**

理由：
1. 三类 JS 候选都需要 WebView 桥接，在 Flutter 桌面端引入 WebView 会割裂 gesture、IME、剪贴板和窗口集成；
2. W0 适配器边界已经把引擎私有格式隔离在 adapter 内，自建画布的"引擎私有 ID"就是产品 item_id 本身，适配层最薄；
3. 500 卡性能门槛用 `Transform` + viewport culling 在 Flutter 中可直接达成，不需要引擎级优化；
4. 自建画布零外部依赖，许可证和离线运行无风险；
5. 后续如果需要更成熟的交互（如手绘笔迹），可在 adapter 内替换底层渲染，不破坏产品数据。

## 加权评分（候选 4）

| 维度 | 权重 | 得分 | 说明 |
|---|---:|---:|---|
| 数据模型可控性 | 25 | 25 | 产品 ID 即引擎 ID，快照往返零损耗 |
| 大画布性能 | 20 | 16 | 500 卡可行；1,000 卡需 viewport culling 优化 |
| 核心交互成熟度 | 15 | 10 | 选择/拖动/缩放/框选自行实现，需调试 |
| 自定义卡片/消费视图 | 15 | 14 | 卡片预览完全可控 |
| 可维护性 | 10 | 8 | 代码量中等，无外部升级风险 |
| 桌面集成 | 10 | 10 | 原生 Flutter |
| 无障碍与输入 | 5 | 3 | 键盘快捷键需自行实现，中文 IME 原生支持 |
| **总分** | 100 | **86** | |

## 后果

- W1 画布实现为 `lib/ui/whiteboard_canvas/` 下的 Flutter widget + ViewModel；
- 引擎适配器 `FlutterCanvasAdapter` 实现 W0 冻结的五方法接口；
- 引擎私有节点 ID 映射为 `Map<String, String>`，但在本方案中 key == value（产品 item_id 直接用作画布实体 ID）；
- 后续替换底层渲染引擎时，只改 adapter 实现，不改 WhiteboardSnapshot / Card / BoardItem。