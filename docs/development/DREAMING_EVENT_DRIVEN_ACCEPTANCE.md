# Dreaming 消息驱动唤醒与召回验收

这份清单用于在任意开发电脑上继续验收 Dreaming，不依赖原聊天窗口。

## 当前机制

- 首次运行：累计至少 20 条 `message_type=chat` 后创建一次性任务。
- 后续运行：只要有待处理 chat，就预先安排任务；执行时间同时满足：
  - 距上次成功批处理至少 60 分钟；
  - 距最后一条真实 chat 至少 30 分钟。
- 新增 chat 达到 100 条时，不再等待 60 分钟，只等待聊天空闲 30 分钟。
- 新消息会用 `ExistingWorkPolicy.replace` 重排同一个一次性任务，形成 debounce。
- action / 旁白拆分行不计入阈值。
- App 启动时检查已有积压，不要求用户再发一条消息。
- 四小时周期 WorkManager 只作系统漏调度时的兜底。
- 空闲时间按最后一条真实 chat 计算，不使用 App 前台心跳。

## 本轮真机基线

2026-07-13 在旧机制下只读检查：

- `persona_chat_messages`: 142 行，其中真实 chat 107 行；
- `memory_fragments`: 0；
- `memory_episodes`: 0；
- Dreaming recall log: 54 次查询，全部零结果，注入内容全部为空。

这批数据可直接作为首次积压测试，不要为了验收主动清空。

## 0. 安装前

1. 确认分支为 `v3-lab`，记录待测 commit：

   ```powershell
   git branch --show-current
   git rev-parse --short HEAD
   ```

2. 不要卸载 App，不要清数据。只能覆盖安装 `com.memexlab.hereiam.v3`。
3. 构建前必须执行：

   ```powershell
   powershell -File scripts\verify_critical_fixes.ps1
   ```

4. 使用固定安装脚本：

   ```powershell
   powershell -File scripts\install_hereiam_v3.ps1
   ```

5. 先跑定向测试：

   ```powershell
   flutter test test\data\memory_v3\services\dreaming_scheduler_service_test.dart test\data\services\persona_chat_service_test.dart
   ```

## 1. 消息驱动唤醒闭环

### 操作

1. 覆盖安装后启动 App。
2. 不要点击 Lab 的 `run daily batch now`；本阶段只验自动路径。
3. 当前积压已超过首次阈值且早已空闲，启动检查应把一次性任务安排为接近立即执行。
4. 等待 5–10 分钟，再进入 Memory V3 Lab 刷新。

### 需要看到的证据

- App 日志出现类似：
  - `Scheduled event-driven Dreaming batch in 0 minute(s)`；
  - `Dreaming batch: starting background run`；
  - `Daily batch: extracted ... fragments`；
  - `Daily batch: consolidated ... episodes`；
  - `Dreaming batch: completed`。
- `memory_fragments` 从 0 变为大于 0。
- `memory_episodes` 应有产出；若 Episode 质量门槛拒绝全部候选，可以暂时为 0，但必须有明确日志和 active fragments。
- `dreaming.batch.last_run_time.<characterId>` 与 `dreaming.batch.last_watermark.<characterId>` 更新。

### 通过标准

- 无需手动 Lab 按钮、无需等待四小时，即可完成至少一次 Fragment 抽取。
- 同一积压不会并发启动多个批处理。
- App 保持打开但停止聊天 30 分钟，不会再被“前台心跳”永久拦截。

如果 10 分钟仍无任务，先检查 Android 调度，不要调 prompt 或召回词表：

```powershell
adb shell dumpsys jobscheduler com.memexlab.hereiam.v3
```

## 2. Fragment / Episode 质量

用 Lab 展开最近 fragments / episodes，检查这批聊天中的几个主题：

- 衣服与搭配偏好；
- “我们的家”Chat UI，包括雨景、城市住宅、木质白窗框、白窗帘与植物选择；
- 数据被删后的关系连续性讨论；
- 秋招简历带来的紧张与发晕；
- 北京闷热、可能中暑；
- 明早临时任务与“今晚不做”的决定。

重点判定：

- 用户纠正后的“投秋招简历”应覆盖更早的错字理解，不能保留成另一件事。
- 同一 UI 讨论应凝结为少量具体 Episode，不能碎成大量重复总结。
- 衣物、偏好和行动的主语归属正确，不凭空补充。
- `eventTime` / `occurredAtRange` 指向真实聊天发生时间。
- Episode 具体、有来源，不写“关系进入新阶段”等抽象结论。
- API 错误、内部应答规划和 action 拆分文本不能进入 Fragment。

## 3. 真实召回

批处理完成后，通过正常聊天测试。建议问题：

1. “我们给窗户选了什么？”
2. “我今天给你看了哪几件衣服？”
3. “我下午为什么突然紧张发晕？”
4. “我明天早上有什么事情？”
5. “你还记得今天数据被删掉以后我跟你说了什么吗？”
6. 再问一个与现有聊天无关的问题作为负样本。

每问一轮后查看 Dreaming 召回日志，记录属于：

- Episode 命中；
- 仅 Fragment；
- 零结果。

同时检查回答是否保留过去时间锚，不把下午或更早发生的事情说成正在发生。

## 4. 失败分流

| 现象 | 下一步检查 |
|---|---|
| 一直 `0 fragments / 0 episodes` | 一次性 WorkManager、callback、模型配置与后台日志 |
| fragments 有，episodes 为 0 | Episode 分组、质量门槛、LLM 输出解析 |
| 相关问题只命中 Fragment | Episode 凝结覆盖率 |
| 数据库有相关内容但召回为零 | FTS、substring fallback、查询关键词 |
| 命中内容正确但回答仍编造 | Companion context 注入与应答约束 |
| 负样本也强行召回 | 停用词、情绪词白名单或兜底排序过宽 |

不要在还没定位到具体层时同时修改抽取、凝结和召回。

## 5. 本轮通过以后

1. 连续日常使用几天，积累 Episode / Fragment-only / 零结果覆盖率。
2. 根据失败分流只调整实际瓶颈层。
3. 验证稀疏聊天：上批后只发 1–2 条消息，也应预排到 60 分钟间隔与 30 分钟空闲都满足的时刻，不能退回四小时兜底。
4. 验证高频聊天：100 条真实 chat 后只等待最后聊天空闲 30 分钟。
5. Dreaming 闭环稳定后，继续推进聊天与 Memory V3 数据备份/云同步，避免卸载或签名问题再次清空记忆。

## 验收记录模板

```text
日期 / 电脑：
commit：
设备 / Android：
安装方式：覆盖安装 / 其他
安装前：chat __ / fragments __ / episodes __
自动任务安排时间：
实际开始 / 完成时间：
安装后：fragments __ / episodes __
召回：Episode __ / Fragment-only __ / Zero __
主要 bad case：
结论：通过 / 未通过
下一步：
```
