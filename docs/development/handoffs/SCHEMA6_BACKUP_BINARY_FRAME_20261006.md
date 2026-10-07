# Schema6 生产备份 stdin 二进制帧修复

基线 `1060f192f8c0956c49392b6c33a769265736f467`，隔离分支 `codex/schema6-backup-frame-20261006`。仅拥有 `backup_bundle_schema6.ps1`、`backup_bundle.test.mjs` 及本文；主窗负责整合、固定候选重打、整组复验与 PR。

## 原因和最小修改

Windows PowerShell 5.1 / .NET Framework 的 Process.Start 在建立 redirected stdin StreamWriter 时使用 Console.InputEncoding。AutoFlush 可在原始 BaseStream.Write 之前发送 BOM，导致密钥/口令帧与后续 JSON 发生偏移。PS5.1 没有 ProcessStartInfo.StandardInputEncoding 属性，不能采用 pwsh7 的同名接口。

已用基线的真实 AST 提取 Quote-Argument / Start-BackupChild，纯合成 portable frame88 + JSON18 应为106字节：默认936收到106且header/length/payload偏移正确；UTF8 BOM收到109，UTF16 BOM收到108，三个偏移校验均失败。只执行两个函数，不执行 wrapper 顶层、DPAPI、manifest动作或真实数据操作。

生产修复仅包围原 process.Start：保存当前 Console.InputEncoding，临时设置 UTF8Encoding(false)，finally 立即恢复。其余 BinaryBaseStreamWrite、密码学、release/manifest guard、DPAPI、帧格式、子进程退出与清理逻辑未改变。

## 回归证据

新增一个 Windows 专项至现有 `backup_bundle.test.mjs`。测试启动真正的 Windows PowerShell 5.1，AST 提取工作树中的两个生产函数；使用 syntheticRoot / syntheticFixedNode 和随机合成 key/password，仅在合成临时目录生成探针与字节接收器。

- 三种原编码（默认、UTF8 BOM、UTF16 BOM）× 两种帧（32字节key + JSON、88字节portable frame + JSON），共6例，检查完整载荷摘要相等、精确字节数、固定 header/length/payload 偏移及原编码恢复。
- 三种编码各执行一次不存在的合成 exe 启动，确认拒绝且 finally 恢复编码。
- source-before：新增测试实际红，0 pass / 1 fail，`utf8_bom/key` 实收53、应收50。
- source-after：同一新增测试实际绿，1 pass / 0 fail。
- PS5.1 对生产 wrapper 的 AST 检查0错；Node 测试源码语法检查和 diff 检查通过。
- 相邻专项为 `backup_bundle.test.mjs` 与仓库实际存在的 `portable_automatic.test.mjs`，串行执行。首轮沙箱在合成 TEMP 祖先 realpath 遇到 EPERM，不能作为功能失败归因；经已授权单命令正常用户权限重跑，不放宽生产路径校验。最终 **38 tests / 38 pass / 0 fail / 0 cancelled / 0 skipped**，90920.6968 ms（backup24 + portable/automatic14），包含合成 DPAPI 固定包操作与真正只读 Core inspection。

所有专项只使用合成库、合成密钥/口令和测试用本地子进程。没有读取原库、配置或个人资料，没有操作现役服务、账号、任务、隧道或手机。没有把单机源码/专项结果当作重打候选或远端 CI 验收。

独立 worker 仅提交自身3个文件。该次提交使用已有 SKIP_PROJECT_STATE 例外并在 finally 恢复原环境；不 push，主窗统一全局状态和验收。
