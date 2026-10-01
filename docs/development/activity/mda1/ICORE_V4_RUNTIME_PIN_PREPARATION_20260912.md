# iCore v4 固定运行入口：准备与切换单

后续状态：用户确认后已于当日执行，见 [实际切换记录](ICORE_V4_RUNTIME_PIN_SWITCH_20260912.md)。
以下保留准备阶段的边界与证据，不能当作当前仍未切换的状态。

状态：**准备完成，尚未应用**。本轮只做固定包、临时数据验证与可审切换单；
没有停止/重启现役任务，没有读或复制真实 `.state`，没有更新主线或提交。
执行下一节的真实切换需要单独确认；上一轮约定的“第 1 步”到此为止。

## 固定对象与交付

| 项目 | 本次对象 |
|---|---|
| 旧版源码 | `bbb8025d99fc0acaa846d58b4e5a94cef90f8756`，schema 4 |
| Node | `v24.14.1`，91,426,304 bytes，二进制一并复制进包 |
| Node SHA-256 | `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f` |
| 固定包 manifest SHA-256 | `7eb6f1bc7267159647fa435534b5686267018e53b00feb7709186e54f2d4a15f` |
| 本地交付 | `tmp/i-core-runtime-pin-20260912/v4-bbb8025d/`，9 个受校验文件及 manifest |
| 拟用运行目录 | `D:\HereIAmRuntime\i-core\releases\v4-bbb8025d`，本轮未创建 |
| 原状态目录 | `D:\memex\tools\i_core\.state`，未来仍原位使用 |
| 拟用端口 | `127.0.0.1:47841` |

工具位于 `tools/i_core/runtime_pin/`：builder 只从精确 Git commit 提取六个旧文件，
不会把当前候选的 schema-5 server/store 放入包。六文件包括 server、store、
relay、SMTP sender、严格 TLS 校验脚本及旧 launcher。另加固定 Node、校验入口
和 schema guard；旧 launcher 原样留存为来源依据，实际入口由新 wrapper 持锁
检查后启动旧 server，避免双重获取同一锁。

固定包不含数据库、邮件配置、token、DPAPI 凭据或用户日志。它是本机运行产物，
二进制与 `tmp/` 证据不纳入源码提交。Windows PowerShell/系统模块/DPAPI 仍由
Windows 维护；没有声称冻结操作系统。

## 本轮实际查明的运行状态

- `HereIAm-iCore` 为 Running；动作指向主目录
  `D:\memex\tools\i_core\start_i_core_service.ps1`，工作目录 `D:\memex`，
  显式 NodePath 为 `D:\Nodejs\node.exe`；原 task ownership marker 符合管理脚本。
- `127.0.0.1:47841` 的本轮初查 listener PID 为 `20316`。PID 只是当次快照，
  真实操作前必须重新读取并核对启动时间/命令路径，不能直接拿它执行终止。
- 主目录 `tools/i_core` 相对该 commit 没有文件差异；User/Machine 环境中没有
 持久 `I_CORE_DATABASE`、mail config/database、`NODE_OPTIONS`、`NODE_PATH`
 覆盖项。本轮没有读取其真实配置值或数据库，也不据此推断库当前 schema。
- 原 v4 server CLI 无 SIGTERM/SIGINT 清理器；`core.close()` 只在被显式调用时
 有效。因此停止任务、终止进程、端口关闭均不等同于优雅关闭。

## 校验入口的实际边界

默认运行 `start_pinned_i_core.ps1 -ManifestSha256 <上述值>` 只校验包，返回
`verified_only`，不要求 state、不创建 state、不启动子进程。只有显式 `-Start`
和现存绝对 `-StateDirectory` 才进入真实运行分支。

入口先校验 manifest、全部文件哈希与严格目录清单，拒绝 reparse 路径、卷根
state、相互包含的 code/state 路径；固定系统 PowerShell 模块路径，清理继承的
`I_CORE_*` / `NODE_OPTIONS` / `NODE_PATH`，固定 Node 和系统 PowerShell 搜索路径。

Start 分支持有原状态目录的 `shortcut-mail-relay.runtime.lock`，先探测端口空闲，
再做 schema preflight，最后才启动旧 server。端口探测到正式 listen 之间仍有
短竞态，必须配合真实切换的独占停机窗口，不能把探测称为全局排他证明。

原 v4 Store 在构造时会无条件写 `schema_version=4`；其 `/health` 也只报告二进制
常量。因此 schema preflight **不 import Store、不用 health 证明原库版本**：

1. 在原 state 下创建本轮自有的 `.runtime-preflight-*` 子目录；复制主库和存在
   的 journal/WAL/SHM 全视图，只在副本打开 SQLite。
2. 核对 schema 4、八张旧表、各列 name/type/notnull/default/pk 的合成基准哈希、
   身份元数据非空，并排除 activity 元数据。索引及所有 SQL 语义不在此证明内。
3. 关闭并删除自有副本；前后比较源四文件指纹，变化则拒绝启动。

这避免 SQLite 在拒绝路径维护源 WAL/SHM，但 **Start 仍会读取真实 state、创建
runtime lock，并在其中创建/删除临时副本**；不是“完全不触碰 state”。异常杀死
preflight 可能留下含真实数据的自有副本；将来只在核对无进程持有后按精确目录
清理，不能通配删除其他 state 内容。本轮仅对合成 state 执行这些动作。

聊天库、mail config、mail journal、enabled marker、configure lock、runtime lock
全部显式使用原 state。未来保留原 Windows 用户和 DPAPI 绝对凭据路径，不复制
或迁移凭据；mail 是否启用仍由原 marker 且无 configure lock 决定。不会主动请求
发送邮件，也不会打开 pairing/worker/activity 权限。

## 真实切换：待确认后的具体顺序

1. 重新核对主目录 HEAD、现役 six-file blobs、Node hash、任务 ownership/动作/
   principal/trigger/settings、实际 listener 进程及其启动路径。出现不明变化先
   停在原服务，重新裁决。保存原任务完整定义用于回退，并通过已有 health
   临时持有原 node identity 用于切换后等值比较；不输出真实 identity 或库内容。
2. 将已验固定包复制到上表的新目录；不覆盖已有 release，不经过 junction。
   对最终目标重新执行 verify-only，manifest 必须逐字节一致。目标目录校验与
   task 变更都属于下一步，当前只交付 workspace 内的包。
3. 获取短暂停机窗口，避免正在进行的聊天写入和邮件发送；暂停该任务的自动
  重启/触发，再停止旧任务。只按重新核实的本任务进程树处理残留 Node；确认
  进程终止、47841 无 listener、同一 runtime lock 可独占取得后再继续。不可
  把 task 状态 Stopped 单独当作停止证明，也不把强制结束称为 graceful。
4. **只替换现有任务的 Action**，保留原 principal、trigger、settings 和 enabled
  状态；不使用旧 install 脚本重新注册。新动作如下（完整机器可读版见同目录
  证据中的 `proposed-task-action.json`）：

   ```text
   Execute: C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
   WorkingDirectory: D:\HereIAmRuntime\i-core\releases\v4-bbb8025d
   Arguments: -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\HereIAmRuntime\i-core\releases\v4-bbb8025d\start_pinned_i_core.ps1" -ManifestSha256 7eb6f1bc7267159647fa435534b5686267018e53b00feb7709186e54f2d4a15f -Start -StateDirectory "D:\memex\tools\i_core\.state" -CorePort 47841
   ```

5. 启动一次，schema preflight 若拒绝则保持停止并调查，不删 WAL/SHM、不手工
  改版本、不绕过 guard。启动成功后检查新进程路径、包指纹、127.0.0.1 listener、
  health protocol/schema/既有 node identity，以及旧任务定义中未改动字段。
  身份比较只记录“相等/不等”，不把真实值写入交付。
6. 用既有设备做短暂聊天续用确认；不重新 pairing、不发送测试邮件、不跑迁移。
  运行切换成功后再处理 MDA 主线集成，不能把本轮临时数据测试写成真实切换通过。

## 回退

- 在主目录尚保持原 six-file blobs 时，停止固定包任务，核对新进程、端口和锁
 均释放，然后精确恢复第 1 步保存的原任务 Action/启停状态并启动原入口。
- 如果 guard 因 schema、源指纹变化或结构未知而拒绝，不得盲目启动不带 guard
 的旧入口；先确认原库仍兼容，必要时保持停机并交由人工决定。
- 不回退/删改数据库，不删除 WAL/SHM，也不清除原 enabled/configure marker。
 这次只隔离代码，正常启动使用同一个 state，不承诺通过源码回退恢复数据。
- **未来主线已合入 MDA 后，旧 checkout 路径不再是 v4 回退入口**；需要保留上次
 验证过的固定 release，独立处理运行升级。不能把任务重新指回已变化的主目录。

## 验证与候选关系

本轮专项 **6/6 pass、0 fail、0 skip**，最终包 verify-only 为 `verified_only`。
结果、包校验、文件清单在 `tmp/i-core-runtime-pin-20260912/`：

| 专项 | 结果 |
|---|---|
| 六文件的精确 Git blob/hash、Node 固定和验包 | 通过 |
| 默认只验包，manifest/内容篡改拒绝 | 通过 |
| 缺库及 schema 5 在旧 Store 启动前拒绝 | 通过 |
| WAL 中仍持有的 schema 5 拒绝，源主库/WAL/SHM 字节不变，副本清理 | 通过 |
| 版本仍标记 4、但基表列被修改时拒绝 | 通过 |
| 无关 cwd 真启动、权限收敛、外置 mail journal、configure-lock 禁用、第二启动拒绝、停止后端口释放 | 通过 |

测试只使用旧 Store 建立的合成 state、随机 loopback 端口、伪造 mail config；
没有 SMTP 发送。测试进程按自有 PID 树强制结束并检查端口释放，属于非优雅
停止后的合成检查，不能升级为现役服务连续性或真人验收。

独立依赖审计发现并关闭了 mail 路径分裂、旧 Store 覆写版本、readonly SQLite
sidecar、副本清理、卷根路径与 Node 父进程 PowerShell 模块环境等问题。源码
闭包和最后版本由主窗复核；最终专项计数见同目录测试日志。

首次运行中，Node SHA 常量复制多一个字符导致在构包前拒绝，修正为真实 64 位；
Node 父进程继承的 PowerShell 7 module path 也曾使 Windows PowerShell 5.1
找不到 Get-FileHash，已在入口固定 host 内置模块。后续沙箱允许启动但拒绝
taskkill，8 个合成子进程曾未自动清理；按精确路径/PID核实后已清除，再由主窗
以一致权限完整运行，6/6 及自动 teardown 通过。最后另核查测试进程为 0，
并清理八个已归属的失败 fixture 目录；不是通过忽略清理错误取得通过。

MDA-1 原暂存候选仍为 `cce2481365c6131894c3eb60c861d54d0b48fe45`，原 patch/
manifest 不覆写。本轮工具、切换单和两份状态文档作为额外未暂存准备成果交付，
不会把原候选的 208 pass/1 skip 冒充为本轮固定包的专项验证。主线、真实运行、
设备与 MDA-2 状态均没有被推进。
