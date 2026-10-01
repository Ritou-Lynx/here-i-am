# A2-R2 `ae9bfea0` W0 验收

日期：2026-09-13
结论：**接受为本地合成持久队列候选，可选择性集成。**

## 固定对象

- 候选：`ae9bfea023776e28b835633d74053194debf9b5c`
- 总基线：`b55386cfc896c98376a071009f349dcbc88dc84b`
- 原任务：`01a09933-d22f-7b53-9144-395a7a7ae6e8`
- 分支：`codex/mda2-a2-android-durable-20260913`
- 被拒历史：`7d0494436d55578d6388b12e69080a7741e4dc9d`、`47adfbf69baecea40e60bbeb8c8659ed4af32b1b`

最终工作树干净。R2 相对 R1 只修改 5 个 A2 文件；最终候选相对总基线仅新增 12 个允许路径。共享 Core/validator、Android/Manifest、根依赖、DI/UI、数据库、BLE、前台服务和全局状态文件均未被 worker 修改。

## 两轮独立退修

首版在 stale-owner 接管中先释放 lease、后递归删除 owner 目录，允许旧 authority 删除另一恢复者刚建立的新 owner。R1 改成永久稳定的 `owner.gate`，在同一 OS 独占锁内复核 authority、替换 `owner.json`，并把 gate 句柄延续为新 owner 的生命周期锁。

R1 的 `_removeOwnLock` 又在 owner 删除后才释放 gate；删除异常会使已关闭实例遗留活锁。R2 用 `finally` 无条件释放 gate，删除失败保留签名 owner、poison 旧实例并返回固定错误；后续只允许与该 owner 和 anchor 精确匹配的恢复权威接管。两项确定性故障注入覆盖 close 与 open 清理失败。

## W0 独立验证

W0 从最终 Git 提交对象导出干净副本。两次首次离线解析均在生成有效 `package_config.json` 后被本机 Pub `active_roots` 路径故障拦住；按候选脚本的受控路径复用该离线映射，以 `-NoResolve` 完成测试。最终同一导出候选结果：

- A1：`56/56`
- A2：`30/30`
- source analyze：无问题
- test analyze：无问题
- 候选副本内拥有 Dart 文件测试前后字节一致
- 现有 validator：`20/20`
- 全内存 `ActivityControlPlane`：`20/20 accepted`
- 诊断 unknown：6 项
- 隐私负例：7 项
- duplicate / TTL 边界：通过

独立范围与语义复核最终均无 P0/P1/P2。A1 的 8 个来源、9 个被测 owned 文件、共享 Core 的工作区与 Git blob 哈希均复核一致；`activity_control_plane.test.mjs` 的 CRLF 工作区 SHA 与 Git LF blob SHA 已分栏，不再混称。

## 接受边界

本次接受的是纯 Dart、本地文件、合成信号和内存 Core 的持久 outbox 候选。它证明固定 wire bytes、sequence、`never_sent` / `attempted_unknown`、journal 恢复、单 owner、精确 stale 恢复权威、晚回执隔离、冻结、年龄证明和隐私拒绝在已测范围成立。

它不证明 Android 原生 UsageEvents/屏幕采集、真实进程或断电恢复、Android Keystore、网络 transport、真实 Core、真实数据库、APK、Doze/强停/重启、手机 UI、部署或真人 Gate。整目录连 anchor 一起回滚、物理介质 raw 删除证明也未支持。A3 仍须另行规划和授权。
