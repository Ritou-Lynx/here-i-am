# Goal 1 最终本地验收（2026-10-01）

## 判定

**本地验收 GO；生产长任务执行继续 fail-closed。** 此判定关闭 Goal 1 既定 UI-T、P4、限定 P5 与 P6 的本地自动 / 真人 Gate，不授权生产默认启用、真实旧任务操作、commit、push 或发布。W4 字幕 `0/18` 仍是非阻断红灯；手机近期聊天、结构化事实与 UserRhythm 仍在本 Goal 范围外。

## 最终组合候选

- 工作树：`v3-lab@b2adc44b7c04983a931c39695b81491cd295084b`，保留并行未提交修改。
- Windows 隔离普通入口 exe SHA-256：`A8A3FF2943B2B6F6837A1945F9ED7AEF6CC5F9BC232FB492B59F34C789A192C3`；原生 v2 SHA-256：`4B052BDF2DAE7F239A94CBC2C289A55A0E50F9995C914835370CE6536EAE3905`。
- `tmp/goal1-p6-combined-20261001/source-manifest-runtime-v3.json` 的 104 个受控源码路径在最终审计时全部同哈希，0 缺失 / 0 漂移。UI-T / P4 / P5 / P6 组合自动回归 69/69、普通入口与队列 53/53、Bridge 相邻专项 82/82、构建前关键检查 3/3 已在同候选装配时通过；此后没有修改这些受控源码。

## Gate 证据与跨包取舍

| 范围 | 最终事实 | 判定边界 |
|---|---|---|
| UI-T | 九项主题及输入真人 Gate 既已接受；新候选未改主题实现。2026-10-01 在同一 P6 exe 追加输入可编辑及右键菜单视觉点验；未发送草稿，隔离任务仍 7 条、原任务状态不变。 | 此点验不冒称重做完整剪贴板 / 第三轮粘贴 Gate；保留先前已接受结论。 |
| P4 | 六种卡片命令、持久 Receipt / Undo、冲突拒绝与重开恢复此前已获真人通过。当前差异中的白板根目录分支仅在隔离候选标记启用时重定向；正式路径仍使用原目录。DomainCommand / Receipt / Undo 的核心行为未改。 | 本 P6 隔离入口在 `lib/main.dart` 只显示受限聊天页，不能据它声称新做了白板真人操作；既有 P4 Gate 予以保留。 |
| 限定 P5 | 用户已接受手机 Dreaming 只读来源和“自动拦截 + 真人只读回复”组合口径。`P5_PHONE_READONLY_SOURCE_MANIFEST.json` 的 12 个源文件当前同哈希。 | 不扩张为全量跨端记忆或真人实际未知写工具拒绝。 |
| P6 | 同一普通入口 exe 已验短聊零任务、精确入队与 status、唯一 start 后完整 1–2000 结果、pause / resume / cancel、正常与异常退出恢复、失败关闭后保留窗口并重试关闭。任务 `b2b1680e-8ff4-4ddc-b451-f14daf8223f6` 又在一次受控本地终态交付故障后持久 failed/retry0，仅 retry 一次至 completed/100/retry1；结果 8892 字符逐字正确，同包重开保持。两次原生六项清理均 true、`cleanup_pending=false`、owner exit 0；隔离端口关闭、SQLite integrity ok。 | 故障为合成本地交付错误，不称真实 provider 失败；生产 profile 仍拒绝。证据 `tmp/goal1-p6-combined-20261001/terminal-delivery-retry-result.json`，SHA-256 `ED08CBDB11BD05F327AD030742E530846E9821AE03FF9CCE0CBAB6BF49F9C9E5`。 |

## 减少真人确认的执行决定

现有原生执行器每次 task execution 以 `runas` 分别启动 install 与 cleanup helper；一次 start 加一次 retry 对应两个独立 owner，代码路径上可能提出四次系统提权。实际 Windows 弹窗数量未被回执记录，不写成实测四次。P6 所需本地 Gate 已完成，不再为了同一结论创建新任务或重复触发系统确认。

若未来要把每次执行从两次提权降为一次，需另立短寿命、单 attempt 绑定的高权限 lease helper，并重新验证 WFP 删除、owner / job / stdio / handle 关闭和失败回滚。跨任务常驻高权限 broker 或计划任务绕过 UAC 不作为本 Goal 的捷径；此类改动会产生新原生哈希，不能继承本次 Gate。

## 收口与后续

Goal 1 的本地完成定义据上述证据收口。生产默认启用、真实用户任务迁移、commit、push、发布及后续 Gate 1A-1 分别遵守各自授权和检查；本次没有执行这些动作。旧的失败批次与 `cleanup_pending=true` 原始回执作为历史负证据保留，不因最终新批通过而改写。
