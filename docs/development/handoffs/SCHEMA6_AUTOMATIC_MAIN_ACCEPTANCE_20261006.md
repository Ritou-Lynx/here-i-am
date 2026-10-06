# PR14 自动运行、口令备份与 CI 续作｜主窗验收（2026-10-06）

用户通过前轮备份/真实还原/退回，要求只在 `codex/core-deploy-readiness-20261006` 更新同一草稿[PR #14](https://github.com/Ritou-Lynx/here-i-am/pull/14)，完成后暂停等审核。base仍 `v3-lab@90f23ce1`。本页当前为收口中的证据登记；**整组与新演练尚待最终集成提交复验，不提前记为完成。**

全程合成环境；没有读取/停启现役 Core、MCP、隧道，未打开原库，未改任务/配置、未操作手机，不合v3-lab。上一轮真实九类52文件与恢复证据原样保留，不混作本轮重新取证。

## 已独立复核的 CI 根因

两次旧Windows job同为96tests/89fail，证据显示8.3 TEMP `RUNNER~1`及elevated默认owner group。夹具规范root/独立固定Nodecopy、CI-only token default owner修复；生产plainPath、ACL、link/hardlink检查未动。白板唯一失败是空标题/H1保存测试只等待600ms实际IO，改为明确保存Completer/关闭回执并验证阻塞时不关闭。

- CI修复worker首次四组86/86、路径3/3，真实8.3 TEMP全Windows99/99、0skip，756566ms。
- 主窗在整合后独立Node89/89、0fail/skip，94168.1215ms。
- 白板worker精确5/5、相邻canvas195/195；主窗锁定依赖准备后精确5/5，磁盘保存/重开完整断言通过。
- CI已修复并推送源码 `aaba5065`，状态提交/head `45bcab16`。该head两次Linux白板/全Flutter/Bridge及PRPolicy已通过，Windows检查当时仍在运行；最终head的全部checks将在本页收口，不借历史green替代。

## 并行包与主窗复核

| 包 | 所有权与复核重点 | 交付 |
|---|---|---|
| CI与用户会话 | 夹具/CI先修；隐藏WM关机、登录新control、PrepareOnly XML、根进程Job托管、备份先收口 | [CI交接](SCHEMA6_CI_REPAIR_20261006.md)，会话交接随包登记 |
| 自动恢复/旧v4 | raw-before-first-SQLite、copy4→5→6、真离线租约、独立head/prefix与正常编辑、提交中断 | [恢复交接](SCHEMA6_AUTOMATIC_RECOVERY_20261006.md) |
| 口令/每天备份 | scrypt/AES-GCM、原DPAPI缺失仍真实readonly restore、在线一致副本、30天与离线mirror补复制 | [备份交接](SCHEMA6_PORTABLE_AUTOBACKUP_20261006.md) |

root review发现并要求修复：同device_id合法re-pair改变token不能被误报回退；snapshot归档floor不能替代真实生产head；自动backup锁不可依赖CreateNew文件残留；关机必须等完整exit/Job/锁回执而非ACK；正在写入和timeout演练需明确实际边界，不把假回执或readonly单开当下一启动实证。

## 六类演练（最终集成复验后填回执）

| 情况 | 预期下一启动 | 结果 |
|---|---|---|
| 正常关机消息 | 自动clean close，下次新control正常启动 | 待最终复验 |
| 关机时Core正在写入 | 已接受事务保留；真实关闭后下一次启动同记录 | 待最终复验 |
| 关机hook超时 | 不造clean；下次raw保全/copy检查通过则自动启动 | 待最终复验 |
| 强杀Node | 原始sidecar先加密，已提交WAL回放、未提交回滚、schema6可启动 | worker真实Windows child death168秒通过，待最终整组 |
| 强杀guardian | Job限制孤儿；下次相同恢复流程，通过后启动 | 待最终复验 |
| 副本迁移中断 | 原DB/WAL/SHM/journal摘要不变，新start明确阻断待处理；旧v4原件保留 | auto专项已证明原件不变，待最终整组 |

这是对自建合成进程/数据库/隐藏窗口的演练，不实际关机/注销电脑，不代替未来现役停机/真机/异机Gate。

## 电脑外恢复与明确限制

随机合成口令、独立Node与固定Windowswrapper在原DPAPI不可用时启动真实只读Core：node/schema/devices/全部表数量与指纹、5类写/配对403、退出DB字节不变。仍待最终集成整包复验。没有第二Windows账号/第二机器环境，不创建账户、不称跨账号已实测。用恢复口令保管与换机步骤见[说明](SCHEMA6_OFF_MACHINE_RECOVERY_20261006.md)。

Tailscale机器私钥按用户决定不备份；新机重新登录同tailnet、释放/沿用机器名，按原协议/路径/端口恢复Serve，手机使用数字IP时更新Core与47862地址，重核认证/cursor/单一消费者。当前并未重配。

调试邮件允许先关闭，保全旧SMTP配置/凭据/journal，不自动重发。新Core合法运行与备份检查不等于现役上线；MCP与手机还需独立现场Gate。操作单已删除“每晚先说停机口令”，改为登录后自动运行/正常关机自动清停/异常下次恢复，只有检查失败或迁移中断人工处理。

## 最终固定包、测试与远端（收口后填写）

待集成固定source commit、inventory、manifest SHA、Node/PS语法、整组计数/日志SHA、精确head checks链接、工作区/远端/基线状态。全部通过后更新同一PR并停止；没有合并、部署或下一轮开工。
