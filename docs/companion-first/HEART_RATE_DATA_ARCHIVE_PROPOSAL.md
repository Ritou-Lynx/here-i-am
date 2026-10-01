# 心率数据长期档案方案（草案）

> 状态：Policy Gate 已于 2026-09-05 确认；本文件冻结“仅本地、一年 raw、睡眠佩戴意图”，不代表同步、MCP 或长期保留已经实现。
> 范围：COROS 光学臂带经 Android 标准 BLE HRS 产生的逐秒数据，以及可关联但独立保存的 COROS 账户数据。

## 要解决的问题

每天佩戴臂带会产生一条稀缺的连续时间序列。它既不应只留在手机私有目录里等 14 天后删除，也不应直接塞进聊天记录、User-truth 或 Git 仓库。目标是让 Lynx 能在 Here I am、Codex 或 ChatGPT 中按日期取回可信数据、看到覆盖率与缺口，并在以后加入睡眠、活动与主观记录后重新分析。

## 当前事实与边界

- 手机已经把标准 HRS 样本按日写入 app-private `files/ble_heart_rate/<user-key>/YYYY-MM-DD.jsonl`。当前代码保留 14 天，只有设备上的 App 沙箱能直接读取，尚无导出、上传、跨日索引或历史查询接口。
- 当前 COROS 臂带真机只观察到 BPM，没有 RR、接触状态、energy、原始 PPG 或体动。单一 BPM 不能证明睡眠、清醒、焦虑、离腕或睡眠分期。
- 产品支持睡眠用途佩戴窗口。档案可把每次连续佩戴记录为该用途，但窗口可能包含入睡前清醒、夜间醒来和起床后尚未摘下设备的时段，不能把整段样本直接标记为已睡眠。
- COROS MCP 读取的是 COROS 账户 / 手表产生的健康与活动数据；本地 BLE HRS 是手机现场采集的另一来源。两者可以按时间关联，但不可互相冒充或覆盖。
- 逐秒遥测不写 Memory V3、SharedLife、普通聊天数据库或 i Project closeout。分析结论若以后需要成为 User-truth，仍须经过既有显式记录流程。

## 推荐架构

```text
COROS 臂带
   │ 标准 BLE HRS，约 1Hz
   ▼
Android app-private 滚动缓冲
   │ 每日封包；断点续传；服务端回执后才可进入淘汰期
   ▼
Windows 用户级加密 Health Vault
   ├─ 不可变 raw 日包
   ├─ SQLite 目录与来源索引
   ├─ 5 分钟 / 整夜摘要、覆盖率与 gap
   └─ 只读 Health MCP
          ├─ Codex 本机访问
          └─ ChatGPT 可选 Secure MCP Tunnel
```

长期库放在用户目录下独立于仓库的位置，例如 `%USERPROFILE%\.i\health-vault`。它只保存在 Lynx 自己的本地设备，不上传第三方云端，不进入 Git，也不依赖某个 Here I am 工作区或某段聊天是否还存在。Windows 主机离线时，手机继续缓冲；日包只有在主机返回匹配的内容哈希与导入回执后才视为已备份。

## 档案格式

建议保留三层，而不是只存一张“昨晚平均心率”表：

1. `raw/android_ble_hrs/<device-pseudonym>/YYYY/MM/YYYY-MM-DD.ndjson.zst`
   - 原始、不可变、压缩的 sample / status / gap 记录。
   - 不把蓝牙 MAC 暴露给查询端；设备使用本地随机 pseudonym。
2. `catalog.sqlite`
   - 记录日期、来源、时区、schema 版本、首尾时间、样本数、覆盖率、最大缺口、状态事件数、日包 SHA-256、App / APK 来源、导入批次和删除状态。
   - 同一日重复上传以哈希幂等，绝不静默覆盖不同内容。
3. `summaries/`
   - 5 分钟桶与“佩戴窗口”摘要；保留 count、min/max/mean、分位数、覆盖率和 gap，不只留均值。
   - 后续与 COROS 睡眠、HRV、活动、闹钟、屏幕活动或主观入睡记录关联时，保存来源与算法版本，可随时从 raw 重算。

目录同时维护 `wear_sessions` 投影：以真实首尾样本、连接状态与 gap 划分连续佩戴窗口，并写入用户选择的 `intended_context=sleep`。`intended_context` 仅表示用途标记，不是算法已经判断睡着；以后得到可靠的睡眠边界时，另存带来源和版本的派生区间，不改写原始窗口。

所有时间同时保存 UTC epoch 与采集时区；跨午夜按手机本地日期封包，但查询以明确时间窗为准。没有样本的区间保留为缺口，绝不插值成真实心率。

## 已确认的保留策略

Lynx 于 2026-09-05 确认：原始数据只保留在本地一年，核心目的不是永久囤积，而是在需要复盘或采用新算法时仍能取回重算。

- Android：滚动保留 14 天；在自动同步和回执机制经过真机 Gate 前，不缩到 1 天。
- Windows raw：自采集时间起保留 1 年，到期删除对应逐秒 raw；不把“压缩”当成延长保留期。
- 5 分钟桶、整夜摘要、manifest 与删除审计：保留至 Lynx 主动删除。

当前 Android 14 天代码尚未修改，Windows Vault、同步与一年到期清理也尚未实现；以上是已确认的下一阶段产品契约，不可提前宣称数据已被长期保存。

## 给 Codex 与 ChatGPT 的查询边界

只读 MCP 第一版只开放受限工具：

- `health_list_nights(from, to, source)`：列出日期、来源、覆盖率和缺口。
- `health_summarize_window(start, end, bucket)`：返回限量聚合，不默认传逐秒 raw。
- `health_compare_nights(night_ids, metrics)`：比较多晚趋势并带数据质量。
- `health_export_window(start, end, resolution)`：经用户明确请求，导出有行数 / 时长上限的 CSV 或 NDJSON。

写入令牌与查询令牌分离；聊天模型只拿只读、限窗、可审计能力。默认结果不含设备 MAC、用户目录、鉴权信息或其它 App 私有数据。每次查询返回来源、覆盖率、gap 和算法版本，防止把残缺数据说成完整睡眠事实。

Codex 可直接连接同机的本地 Health MCP。ChatGPT 若账户与工作区具备 Developer Mode / Tunnel 权限，可通过 OpenAI 的 Secure MCP Tunnel 访问只出站连接的私有 MCP，而无需把家庭电脑服务公开到互联网；正式接入还须建立 tunnel ID、在本机 runtime 配置 Platform API key，并确认目标 ChatGPT workspace 与对应 Platform organization 已关联。如果当前账户没有这些能力，先用受控 CSV / 摘要导出，不为此暴露公网端口。官方边界见 [Connectors and remote MCP servers](https://developers.openai.com/api/docs/guides/tools-connectors-mcp) 与 [Secure MCP Tunnels](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels)。

## 安全与删除

- Vault 静态加密；密钥不写仓库、日志、聊天或 manifest。
- Android 上传端只可追加日包，不能查询历史；分析端只读，不能删除。
- 删除由单独的本地用户动作执行，生成以 `(source, date/window, content hash)` 标识的 tombstone / receipt，并清除 Vault 中对应 raw、摘要和索引引用；导入端必须拒绝 tombstone 命中的旧日包，避免手机残留再次把它导回。
- Android 14 天缓冲不能被假装已经同步删除：手机可达且用户选择“同时删除源数据”时才清除对应日包；否则它继续留在 App 沙箱直至自然到期，但 tombstone 已阻断重导入。实现前须把这两种结果分别显示在删除回执中。
- “忘记设备”是否同时删除历史必须做成显式选择；当前 `forget()` 只移除配置 / 快照 / 诊断，不应被误说成已经删除 JSONL。
- 第一版不做自动睡眠判断、医疗结论或基于 BPM 的主动来电。

## 实施顺序

1. Policy Gate（已完成）：仅本地；Windows raw 一年；摘要保留至主动删除；佩戴窗口标记为睡眠用途而非已睡眠。
2. Archive MVP：冻结 schema 与 fixture，先从一份真实脱敏 JSONL 手工导入，验证 hash、重复导入、跨午夜、坏行与 gap。
3. Android Export：增加受控日包导出 / 上传、断点续传、导入回执和 14 天缓冲；不得影响实时 BLE 服务。
4. Codex Access：实现本机只读 Health MCP 与有限查询，先用历史数据做可复现分析。
5. ChatGPT Access（可选）：核对账户能力和批准流程后接 Secure MCP Tunnel；不可用时继续用受控导出。

这是独立于当前 BLE 连续性 Gate 的后续 Goal。当前硬件 Goal 仍先完成新 APK 的 fresh-live、短锁屏和同哈希 8 小时长测。
