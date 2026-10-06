# Schema6：MCP 持柄冲突修复与会话组合验收（2026-10-06）

基线 `codex/core-deploy-readiness-20261006@8b0008b5d8c63e41a0e8d063bdb60053c94f3d2e`，继续同一草稿 PR #14。仅只读用户指定 MCP 源码及既有报告；所有进程、数据库、端口与故障注入均为隔离合成环境。未读取原库/真实配置/正文，未查询或操作现役 Core/MCP/隧道/任务/手机，未合并、部署或实际关机。

## 源码审计与真实复现

详见[直接读取者审计](SCHEMA6_MCP_READER_AUDIT_20261006.md)。指定旧 MCP 入口 SHA256 为 `adfc88126c6d7ee047fd7fed7eda6b3b536c9e1fe0baffafbedc290b6c5554d6`；6 个生产模块的原字节与完整 SHA 清单作为合成夹具保留，Git `-text` 防止 CRLF 被转换。没有迁入旧 Git 历史、`.state`、凭据、数据库或私人正文，正式 `tools/i_remote_mcp/` 程序未改。

实际启动该旧 `server.mjs serve` CLI，显式指向合成 Core/独立 memory/policy/OAuth/identity/log 目录和随机 loopback 端口。通过真实 HTTP OAuth 授权、initialize 与 `i_recall`，断言合成 memory 和 Core 消息确实被读到；没有 mock read model 或使用在线 immutable 读取。

未托管旧 MCP 的对照：关机 QUERY 后 Core 清停失败，侧文件仍存在；Windows 原生独占门控首先返回 `offline_probe_failed`，比预想 `sqlite_sidecars_not_quiescent` 更早拒绝。旧 MCP 仍活着时下一次恢复同样在该门控拒绝，尚未执行替换。结束该合成 MCP 后，原始加密保全/副本恢复正常通过。它证明真实持柄阻断；不冒称已经复现到后续替换步骤或真实现役发生过。对照关闭总耗时 1,022.025ms；复现与端口冲突专项 2/2，99,117.1407ms。

首次组合测试的 1 个红项是夹具仍向关闭失败后已经销毁的 HWND 发送 ENDSESSION；保留首轮日志并改成识别真实 QUERY 后提前失败退出。首次规模脚本的检索词与随机合成正文不匹配，在计时前断言失败；保持原数量/正文，改为检索实际合成词后重新测量。未放宽生产门控。

## 会话管理与失败边界

- 登录：固定 source inventory/executable/config 外锚及 ACL/路径/硬链接检查；新空 control 中 Core 实际 ready 与当前 supervisor PID/创建时间/token/manifest 绑定后，才启动独立 MCP Job。生产 `PrepareOnly` 拒绝缺少托管 MCP 配置；仍不注册或启动实际任务。
- 停止：停止派发 → MCP 有限 grace（0–3000ms）/必要时 force 所属 Job → 确认真实退出与 Job 空（证明此所属树句柄已释放）→ 活动备份排空/必要时 force → Core 认证 close → Core/guardian/supervisor 正常退出、无强杀、marker `clean_closed`、锁释放及真实 DB 独占重开。只有完整 Core 清停才成功。
- 以上均从首次关闭请求使用同一个单调 30 秒预算；ENDSESSION 不重领 30 秒，保留强停收尾时间。每代 control 的 `mcp-start.json`、`mcp-stop.json`、`session-close.json` 与会话 exit 记录阶段耗时、进程身份、退出码/force/Job/句柄证明；自然退出和启动失败粘滞标失败。
- CREATE_NO_WINDOW 下没有可靠 Windows POSIX 信号通道。当前旧 CLI虽有 SIGINT/SIGTERM handler，方案只是有限等待后结束所属进程树；这不是 MCP 应用优雅退出。MCP SQLite 账本须在下次启动依其自身事务/WAL恢复，未确认响应沿原 op_id 重试；MCP force 不延伸为 Core force 的成功许可。
- Core 异常重启：先确认上一代 MCP 完全退出，再用新 control 保全/恢复/替换；Core 新 ready 后才启动新 MCP。未托管的其他脚本/工具须在授权现场排空；所属 Job 证据不表示全机所有读者已经清零。
- 自然 MCP 退出发生于两次 Tick之间也拒绝：StopMcp 在等待前后、force后及收尾直接检查所持进程句柄和退出码。自然 9/7/0 均失败；只有本代确实请求 force 且实际码124视为预期强停。测试侧反射调用真实方法，四个真实持柄进程与独占重开验证不依赖计时器 Tick，不新增生产注入点。

## 全合成两档原生实测

关闭使用真实 WM_QUERYENDSESSION/WM_ENDSESSION 和完整 Windows supervisor/guardian/Job/lease。MCP 已成功处理实际 `i_recall`；采用最大的 3 秒 grace。外部总时间从发送 QUERY 前开始，含测试消息辅助进程与真实会话退出；内部时间为会话共用预算计时。每档一次样本、串行且无其他重测试竞争，不承诺任何机器/负载均同耗时。

| 规模 | 消息/变更/领域记录 | 外部完整关闭 | 内部总预算 | MCP停止 | Core认证关闭 | Core强杀 | 异常Core退出→Core与MCP可用 | 恢复后再次关闭 |
|---|---|---:|---:|---:|---:|---|---:|---:|
| 10倍 | 70,000 /70,000 /20,000 | 6.215872秒 | 5.581秒 | 3.043秒 | 2.524秒 | 否 | 28.819973秒 | 6.224536秒 |
| 50倍 | 350,000 /350,000 /100,000 | 12.084255秒 | 11.394秒 | 3.033秒 | 8.343秒 | 否 | 82.936273秒 | 13.782012秒 |

两档均真实 `clean_closed`、MCP/各所属树退出、最终独占探针及清理通过；恢复前旧 MCP 已停，新 MCP 重新读到恢复后的库。该轮每个关闭都低于30秒，Core阶段50倍仍低于10秒。MCP宽限已计入，不能拿前轮不含MCP的9.014秒冒充本轮总耗时。没有增加关机预算、降低数量/历史扫描或宽化 strictClosedPath。

domain_ops/domain_receipts 分别20,000/100,000；关闭后 DB 213,024,768 /1,065,857,024B。当前量测没有在途每日备份，backup_stop_elapsed_ms=0；原有活动备份排空/超时由整组相邻测试验证，不把本表称为三组件最坏负载保证。恢复时间包含停止旧MCP、Core保全/副本恢复、新MCP真实授权与召回，不受关机30秒预算约束。

合成固定 manifest `75a1ef96a7b60789fde30be467e0827763e6ae43daa4678092659cee1831ef64`；session_window SHA `0b961ebdf90e872a0e9fc0b9b34af232d82113c678fe75bfda0f4cab0fd44c46`。这是测试新建 Git 源树的包锚，不是未来上线包。47库存包含新增MCP配置helper；正式提交重建的包与烟测回执另列。

## 最终整组与固定候选

主窗最终完整命令包含 `release_schema6/*.test.mjs`、`lifecycle/*.test.mjs`、`i_core/*.test.mjs`、remote MCP writeback/unit+e2e和旧MCP夹具协议；文件并发2。实际 **662tests /661pass /0fail /0cancel /1既有大小写文件系统skip**，1,077,611.5668ms；没有新增跳过或屏蔽。新增8项组合和4项协议夹具均通过。

主窗本次对照关闭1,138.732ms；托管正常关闭1,846.746ms（MCP133ms/内部1,177ms），下次登录1,938.878ms；Core异常到Core+MCP实际召回18,381.424ms，恢复后关闭1,873.514ms；MCP 2.5秒宽限超时被force，停止2,542ms、整次关闭6,454.699ms，下次登录4,444.424ms。正常/恢复/强停后均实际clean_closed。实际端口冲突仍保持会话失败，即使Core数据安全关闭；无Tick的自然退出9/7/0和owner force124四例全部完成真实持柄/独占重开。

200,000条领域记录/操作/回执再次完整验：353,221.905ms，floor2,213→2,674B，多revision/删除/purge通过；真实旧行/revision/body/缺行/历史前缀/设备FK损坏全部拒绝。未降低前轮大容量保护。28MJS+17PS运行脚本语法通过，另含新夹具语法；旧6模块哈希/长度匹配，46份源文本经Git过滤仍与已测字节一致。两处包装脚本的已测混合换行用根`.gitattributes -text`固定，不改生产脚本字节。

证据位于忽略目录 `build/ci/`，正文/凭据/数据库不提交：

| 回执 | SHA256 |
|---|---|
| pr14-mcp-main-final.spec.log | 5c1ccdb6d5500604659cfa04a5f79784f2d6128c18f55d93aeed36fbaa6ced78 |
| pr14-mcp-main-final.tap | cfb25e60f912341c9bed70f7951a17af59265f125d44ed988eb2cdbf62a62493 |
| pr14-mcp-native-scale-final.log | 6b61e0d1f4aa838faa0bd708a958b9f24469d9bc24bd37609fd3c4baa3f478ee |

正式已提交固定候选待本次源码提交后构建并验证；CI以最终推送同PR精确head的新13项Checks及实际Windows/跨用户回执为准。没有拿8b的旧CI绿或本机合成manifest充当本次远端/上线证据。

## 现场授权与未完成边界

[现场清单](SCHEMA6_CUTOVER_FIELD_CHECKLIST_20261006.md)、[本人操作单](SCHEMA6_OWNER_DEPLOY_CHECKLIST_20261006.md)、[部署手册](SCHEMA6_DEPLOYMENT_RUNBOOK_20261006.md)已补：另行授权停用旧 `\HereIAm-iRemoteMCP` 任务触发/失败重试，MCP改由会话启动器管理，同字节固定源码与现有mutable `.state`分离；⑥.4必须在关机前让MCP真实处理请求而已打开read model，正常关机→开机→登录后核新MCP再次服务及四Gate。

NTFS U盘/不自动格式化、恢复口令本人输入、登录任务另批准、debug邮件关闭、47862桥/legacy_b3单上传器保持。先另获合并授权→合并后提交重建固定候选→再另获切换授权。真实关机、手机同步/claude.ai写入与生产源/路径/其他读者检查均仍未执行，不用合成测试替代。换电脑口令备份建立新现役Core的重新DPAPI/独立key/head/config绑定仍是下一轮缺口。
