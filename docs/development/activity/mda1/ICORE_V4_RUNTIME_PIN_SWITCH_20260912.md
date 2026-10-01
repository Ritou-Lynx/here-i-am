# iCore v4 固定运行入口：实际切换记录

**结果：现役入口已切换并完成技术验收；随后手机聊天续用获用户确认通过。**
原 [准备与切换单](ICORE_V4_RUNTIME_PIN_PREPARATION_20260912.md) 的固定包未修改。
本次只实施运行隔离，没有提交、合入 MDA 主线或启动 MDA-2。

## 当前运行对象

| 项目 | 实际结果 |
|---|---|
| Scheduled task | `HereIAm-iCore`，Running、Enabled |
| 固定目录 | `D:\HereIAmRuntime\i-core\releases\v4-bbb8025d` |
| 源码版本 | `bbb8025d99fc0acaa846d58b4e5a94cef90f8756`，旧版 schema 4 |
| manifest SHA-256 | `7eb6f1bc7267159647fa435534b5686267018e53b00feb7709186e54f2d4a15f` |
| Node | 包内 `runtime/node.exe`，v24.14.1，SHA-256 `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f` |
| 数据位置 | 继续使用 `D:\memex\tools\i_core\.state`，没有搬迁原库或凭据 |
| 监听 | `127.0.0.1:47841`，唯一 listener |
| 本次进程 | 新 Node `32704`，PowerShell 父进程 `40532`；均为当次验收快照 |
| 完成时间 | 2026-09-12 13:28:01 +08:00 |
| 停止请求至新服务验收 | 16.78 秒；不是精确测量的所有客户端断连时长 |

## 实际执行与证据

1. 再次核对主线 HEAD、六个旧源码 blob、Node hash、原任务、listener 和父子
   进程。原任务仍指向开发 checkout；新正式目录此前不存在。
2. 将固定包复制到正式目录并验包。原任务 XML、定义和临时比较用的 node identity
   保存于仓库外的私有 maintenance 目录，ACL 只允许当前用户、SYSTEM 和本地
   Administrators；交付中不含真实 identity、token、配置正文或数据库内容。
3. 观察到无 SMTP 子进程、无已建立的 Node TCP 连接及数据文件时间戳/大小稳定
   的短窗口后，禁用任务并停止。旧 Node `20316` 和父进程 `18684` 均确认退出，
   端口与原 runtime lock 释放。旧 CLI 没有优雅信号清理，本次按非优雅停止记录。
4. 在同一 runtime lock 下运行真实库副本校验，schema 4、八表及列结构等检查
   通过。源 SQLite 未被预检打开，原目录内自有完整副本已删除；新 wrapper
   启动时又按同一固定规则检查后打开原库。
5. 只替换原任务 Action，随后恢复 Enabled。principal、triggers、settings 和
   RegistrationInfo 的 XML 比较一致，没有用 installer 覆盖整项任务。
6. 固定包新进程通过 health；原 node identity 相同，protocol `0.1`、schema `4`。
   未认证 mail receipt GET 在切换前后均为 `503`，保持原关闭状态；没有发送
   测试邮件、重新配对、开放 worker 或 activity，也没有调用聊天读写接口。
7. 13:29:39 +08:00 的后验再次确认 Running、原进程为 0、runtime lock 被新服务
   持有、临时副本为 0、包的严格目录/哈希校验通过。未在 release 下生成 `.state`。

工作区证据目录：`tmp/i-core-runtime-pin-20260912/`。

- `live-prepare.json`：回退定义已保存、正式包已验，服务尚未停止时的记录。
- `live-switch.json`：实际切换、16.78 秒、identity/非 Action 字段/mail 状态对比。
- `live-postcheck.json`：后验健康、旧进程退出、锁和副本清理。
- `live-switch-manifest.json`：本次文档、执行器和证据文件的哈希清单。
- `execute-switch.ps1`：本次有范围限制的执行器；不属于固定 release，不用于
  日常自启动，也不能在已切换后重跑 Prepare/Switch。

独立 worker 只读核对当前任务、精确进程、监听、manifest 和 release 目录，确认
新 Action、新 Node/server 路径、旧 PID 不存在及 `release/.state` 不存在；没有
读取 state、维护备份或凭据，没有发 HTTP。主窗完成真实 guard、identity 对比
和后验，未用 worker 的静态审计替代实际结果。

首次尝试在停止前被时间比较误拒绝：PowerShell 将 JSON ISO 字符串自动转成
DateTime，直接字符串比较不相等。实查 PID 和 UTC ticks 相同后，将执行器改为
UTC ticks 比较再继续；该误拒绝未停止服务、未改任务或打开真实库。固定包内容
和 manifest 没有因此变化。

## 手机聊天续用确认

Lynx 说明回复能接续之前的聊天，并表示“如果算那就成功”。按本次既定的
手机原有聊天续用检查，这满足验收标准，记录为 **PASS（用户报告）**。
本项关联上述固定 manifest；助手未自行观察手机界面或记录新的聊天正文。

该结论只确认切换后原聊天仍可继续、回复能承接前文；不据此推定手机本次请求
一定经由 iCore，也不扩展为完整历史同步、全部长期记忆或其他设备场景通过。
用户确认的独立证据见 `tmp/i-core-runtime-pin-20260912/phone-chat-acceptance.json`；
先前 `live-switch-manifest.json` 的 pending 保留为技术验收时的历史快照。

## 保留边界与下一步

- 已完成的是**真实运行入口隔离、技术验收及用户报告的手机聊天续用确认**。
  手机结论来自用户实际使用报告，不以 loopback health 或合成测试替代。
- quiet 窗口不证明所有远端投递完成；没有请求 SMTP 发送，也不对不确定投递
  自动重试。一般情况下 relay 启动可恢复 journal 中断状态，本次观察为关闭。
- 原任务定义保留在私有 maintenance 目录。今后若需要回退，必须重新核对进程、
  端口、锁及数据兼容；主线更新后，旧 checkout 路径不能再当成旧版回退入口。
- 主目录 `v3-lab` 仍为 `bbb8025d`，原五份 staged 内容保留；隔离 MDA 候选
  暂存树仍为 `cce2481365c6131894c3eb60c861d54d0b48fe45`。本轮交接未暂存。
  下一步才是协调主目录重叠文档/索引，再复核并决定本地提交与合入。
