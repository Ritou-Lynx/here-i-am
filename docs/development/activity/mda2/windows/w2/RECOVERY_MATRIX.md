# W2 恢复和保留支持矩阵

本包使用真实自建 Windows 文件、独立 broker/queue/helper 进程。原生时钟正例与显式合成时钟的期限边界分别记录；短测试没有假称跨过真实 24 小时。最终通过数和进程退出证据以 `RESULT.json` 为准。

| 窗口/条件 | 允许结果与证据 | 不得推论 |
|---|---|---|
| 分配预留前终止 | SQLite 无新行、next 未消费、零发送；新观测可用原序号 | 没有覆盖断电 |
| 分配权威预留后/SQLite 事务内终止 | SQLite 原事务回滚；外部预留 next 保留，清理冻结 | 不能重用预留序号 |
| SQLite 分配提交后/权威确认后终止 | 同 broker 校验磁盘 digest/revision，恢复 never_sent | 不是跨 broker 恢复 |
| attempt 已提交但尚未调用 transport | attempted_unknown；新 owner 再次记录 attempt 才能发送 | 不把零网络调用倒推为 never_sent |
| Core 接受、receipt 尚未写入 | 重放原字节返回 duplicate，receipt_id/server_sequence 保持 | duplicate 不刷新采集/TTL |
| receipt SQLite 事务内终止 | 事务回滚，但未完成外部预留协调；保守清理冻结 | 当前实现不自动重试该预留缺口 |
| receipt SQLite 提交后终止 | 恢复 accepted，raw 不存在，不重发 | 没有新的采集证据 |
| freeze 与在途 receipt 交错 | 原 receipt 结算，freeze 保留，后项 attempts 不变 | 无法撤回已经发出的字节 |
| queue 快照回滚，broker 未回滚 | 独立 digest/revision 不匹配，保留 next floor 并冻结 | 整个可信域回滚仍未支持 |
| 第二进程/旧 owner callback | 独占 Windows 文件句柄及 broker owner/fence 拒绝；只在实际 exit 后释放 | 没有超时抢占 |
| 年龄提供者丢失 | 清理当前 raw 明细并冻结；不得延长 deadline | 不能等待 wall 追平 |
| broker 被终止后用新 broker 开旧库 | queue 子进程退出；raw 可保留到下次拒绝式 reopen 才清理冻结 | 没有即时删除保证、新 broker 导入或自动重新配对 |
| raw 等号/超期的晚 callback | 分配前拒绝，零新序号、零 row | 不从 callback 到达重计 |
| TTL 等号/严格过期 | 等号可接受；仅 TTL 已过的未分配输入拒绝且不消费序号 | TTL 不等于 raw 保留 |
| 已分配 never_sent TTL 过期 | expired_unsent、去除 bytes/digest、冻结缺口；期限后整行移除 | Core 不知道本地丢采原因 |
| 已尝试未知且 TTL 已过 | 原 raw 期限内原字节协调，Core 可返回 duplicate | 不能重写 TTL 或时间 |
| raw 期限与 receipt 同时到达 | 期限优先，删除所有每事件 bytes/digest/receipt/时间/状态 | 不复活 receipt 明细 |
| 容量/元数据上限 | 分配前拒绝，不消费序号、不逐出 attempted_unknown | 这些夹具上限不是生产测量 |
| 坏/错密钥、版本/密文篡改、错绑定 | 停止打开/出口；保护失败时不越权清理 | 不把可解密当新鲜度 |
| ACL 扩宽/reparse/硬链接 | 在保护校验处拒绝；不沿 reparse 遍历目标 | 未证明抗恶意同账户/管理员 |
| broker 伪造投影 | 新行期限/TTL/digest/序号错绑；后续延长/新增/复活均拒绝 | 不依赖正常 worker 的自觉 |
| 无 enqueue/发送、owner 已退出 | 独立 maintenance 启动只清理 owner，期限后逻辑 rows=[] | 不是 Windows 计划任务或强停保证 |
| 历史密文/WAL/备份 | 当前 SQLite 逻辑行已去明细；保存的历史密文仍可解密 | **不支持物理硬删除 Gate** |

Windows 年龄实现直接使用原生 API，微软说明 elapsed time 包含 sleep/hibernation；本包只实测正常运行和子进程恢复，没有令本机休眠或重启。[Windows Time](https://learn.microsoft.com/en-us/windows/win32/sysinfo/windows-time)。DPAPI 保护范围参考 [CryptProtectData](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)；本包额外绑定路径/配置并限制 ACL，仍不把 DPAPI 当回滚权威。
