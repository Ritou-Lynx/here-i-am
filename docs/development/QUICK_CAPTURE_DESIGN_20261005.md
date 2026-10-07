# Here I Am 快速捕获（"记一下"）设计（2026-10-05）

> 2026-10-05 补充：捕获表按[个人数据中枢规划](PERSONAL_DATA_HUB_PLAN_20261005.md)的领域约定实现（W2），App 部分是 W4，电脑端唤起 Codex 并入 W8。

> **2026-10-05 按[个人数据中枢 ADR](PERSONAL_DATA_HUB_ADR_20261005.md) 第 8 节修订（用户已确认），以下几处以 ADR 为准：**
> - 所有"记一下"（侧键、网页端 i_remember、dot）进同一个 `captures` 收件箱；手机 Record Organizer 处理其中的生活记录（消费、睡眠、经期、事实），Codex 处理待办和时间变化，各自在 capture 上记处理结果。§2、§9 第 1 条"捕获完全不让林埃看到"作废；捕获仍不进聊天时间线、不触发林埃回复。
> - §5 电脑端接口不用 `I_CORE_WORKER_SECRET`，改用 `captures:read`、`captures:ack` 范围令牌。表结构按 W1 领域约定，由 W2 定。
> - §4 不另建 `quick_captures` 表，用 W7-0 的通用 outbox。
> - §7 今日单不单独推回手机，手机直接读 `plan_days` 副本。

**状态：设计稿，已按上面的修订确认。** 服务于 [`tools/life_planner/`](../../tools/life_planner/README.md)：手机上随手记的事，要在几分钟内到达电脑上的规划助手（Codex），由它分诊和重排。

## 1. 为什么要做

- dot 不能用快捷方式直接唤醒。
- 思源手机端每次启动都要同步很久，当捕获入口太慢。
- 手机和电脑之间已经有 i_core 这条链路：设备令牌已配好，经 Tailscale HTTPS 连接，有离线补发。用它来送记下的事，不需要再加新工具。

## 2. 目标与边界

- 按下侧键后 2 秒内能开始说话，说完点一下就走。
- 联网时，记下的话 1 分钟内到达电脑；离线时先存在手机上，联网后自动补发，不丢、不重复。
- 到达电脑后，几分钟内唤起 Codex 重排今日单。
- **不进聊天时间线，不触发林埃回复。** 侧键“记一下”是用户显式记录：其中生活事实交给 Record Organizer 成卡（ADR 决定 12），待办与时间变化交给 Codex；混合内容按类型分工并各自确认处理结果。普通聊天仍不自动成为 User-truth，Project Memory 与生活事实隔离。
- 不扩大旧 Memex 链路：现有图标长按的"记一下"打开的是旧输入框，走 `MemexRouter.submitInput`；新入口不复用这条路。

## 3. 入口

| 入口 | 做法 | 说明 |
|---|---|---|
| **侧键双击（主入口）** | 新增一个 launcher `activity-alias`，名称"记一下"，有独立图标；在三星"设置 → 高级功能 → 侧键 → 双击 → 打开应用"里选它 | **待真机验证**：三星的应用列表会不会列出 alias。不列出时，退路是 Good Lock 的 RegiStar 侧键动作，或者改用下面几个入口 |
| 图标长按 | 现有 `quick_note` 快捷方式改为打开新的捕获页 | 不再打开旧输入框 |
| 下拉快捷开关 | 新增一个 TileService，点了直接打开捕获页 | 锁屏下也能用（解锁后打开） |
| 侧键长按（可选） | 声明 `android.intent.action.ASSIST`，在系统里把 Here I Am 设为"默认数字助理" | 会替换掉 Gemini 或 Bixby，由用户决定要不要 |

alias 和图标长按都指向 `MainActivity`。`MainActivity` 根据启动它的组件名或 extra 判断这是一次捕获，直接进捕获页，不加载陪伴主界面。

## 4. 捕获页

- 一打开就开始录音，用 App 已有的本机流式识别：sherpa-onnx 的 `StreamingTranscriber`，旧"记一下"已经在用。说话时实时显示文字。
- 点"完成"停止录音，用已有的 `transcribeSamples` 做一次整段校准；文字可以改。然后点"发送"或"取消"。
- 也可以切到键盘打字。
- 本机识别模型还没下载时，不弹下载窗口拦人：先用系统语音识别（`RecognizerIntent`）或键盘，页面上提示一次可以去下载本机模型。
- 发送后提示"记了"，页面关闭，回到原来的 App。捕获页不进最近任务列表（`excludeFromRecents`，单独的 taskAffinity）。
- 页面底部显示最近 3 条的送达状态：待发送 / 已到电脑 / 已安排。第三期再加"今天的队列"（见第 7 节）。
- 离线时先写进 W7-0 的通用领域 outbox，下次同步时补发，不另建 `quick_captures` 队列。W7 迁移前将副本和队列改为按记录/操作独立持久化，不能把整个同步状态存成一行 JSON。

## 5. i_core 捕获通道

在 i_core 里加一张独立的表，和聊天、activity 互不相干：

- **表**：`captures(capture_id TEXT PRIMARY KEY, device_id, text, captured_at, received_at, delivered_at)`。`capture_id` 是手机生成的 UUID，用来去重。
- **schema**：版本从 5 升到 6，只新增这张表，不改已有表。
- **手机端接口**（设备令牌）：
  - `POST /v1/core/captures`：同一个 `capture_id` 重复提交返回原回执，文本上限 2000 字；
  - `GET /v1/core/captures/recent`：只返回本设备最近几条的状态。
- **电脑端接口**（本机 `I_CORE_WORKER_SECRET`）：
  - `GET /v1/core/workers/captures?pending=1`：取还没送达的；
  - `POST /v1/core/workers/captures/ack`：确认已送达。
- **处理与隔离**：以 W1/W2 领域接口和范围令牌为准，捕获不写聊天 feed。生活记录由手机 Record Organizer 消费后进入 Memory V3；规划处理者只处理待办和时间，不因此获得聊天读取权限。来源改版本时更新原产出卡，明确删除时清除未被用户修改的产出、保留已修改卡并提示；W3 切换 `i_remember` 前必须合入此生命周期修复。
- **测试**：沿用 `i_core_server.test.mjs` 的方式，覆盖重复提交、身份边界、协议版本、重启后数据还在，以及从 schema 5 迁移上来。

## 6. 电脑端 `capture_sync.mjs`

放在 `tools/life_planner/`，用 Node 22，不依赖 npm 包，Windows 登录后自启（参照 i_core 的自启脚本）。

- **拉取**：每 60 秒从 i_core 取一次待送达的捕获，每条写成 `%USERPROFILE%\life-plan\inbox\capture-<时间>-<id 前 8 位>.md`（头部写记录时间和设备，正文是原话），写成功后再 ack。
- **监视回执**：同时监视 inbox 里 dot 新写的回执。
- **唤起 Codex**：有新内容后先等 3 分钟，把这段时间里陆续进来的合成一批，然后运行一次：
  ```
  codex exec --cd "%USERPROFILE%\life-plan" --full-auto "刷新今日单"
  ```
  - 同一时间只跑一个；
  - 两次之间至少隔 10 分钟；
  - 23:30–07:00 不唤起，留给早上的"出今日单"。
- **日志**：写到 `life-plan\logs`，不记录捕获原文，只记条数和结果。

## 7. 回到手机（第三期）

思源手机端同步慢，看今日单也不方便。规划助手重排后，`capture_sync` 把今日单的队列摘要（`today.md` 的前几行和"这次改了什么"）推到 i_core，捕获页底部只读显示。这样在手机上记一句"今晚加班"，几分钟后就能在同一个页面看到重排的结果。

## 8. 分期与验证

| 期 | 内容 | 验证 |
|---|---|---|
| 一 | i_core 捕获通道；`capture_sync.mjs`；规划助手接入（规划助手部分已完成） | `node --test`：i_core 接口和迁移；用假的 core 和假的 codex 测 capture_sync 的去重、合批、限频、静默时段。云端就能跑 |
| 二 | App 捕获页、各入口、本地待发送队列 | Flutter widget 测试和 CI 的 Windows 构建；侧键双击、冷启动速度、本机识别、离线补发要在用户的三星手机上验证（L3/L4） |
| 三 | 今日队列回传手机 | 同上 |

部署时按 AGENTS 走：真实 Core 升级 schema 前要停 Core、做备份，安装到主力手机，这两步都需要用户来做或明确授权。

## 9. 待用户确认

1. 捕获是否完全不让林埃看到。建议默认不进聊天、不变成记忆，以后需要时再加"林埃可读的摘要"。
2. 侧键长按设为数字助理，要不要做。
3. 先做第一期（服务端加同步程序，可以在云端写完并测好），还是一、二期一起做。
