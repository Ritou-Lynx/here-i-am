# W0 运行源码差异处理与合入后更新（2026-10-05）

## 五处差异的结论

仅核对受控源码，未读真实 policy、数据库、凭据或运行日志，未覆盖或重启服务。运行目录 HEAD 为 `2a27f7d7f6b61ff5997db45c8c2f7bde4afb9966`；HEAD、磁盘内容和已加载模块是三个不同证据层。

| 文件 | 原始运行状态 | 处理 |
|---|---|---|
| `tools/i_core/i_core_server.mjs` | clean，旧版 | 保留 W0 新版；部署时更新，不能反向用旧运行源码覆盖 |
| `tools/i_core/i_core_store.mjs` | clean，旧版 | 保留 W0 外部前端只追加/角色隔离保护；部署时更新 |
| `tools/i_memory/i_memory_read.mjs` | modified | 精确归属正式 C 谱系的 `6ab0278a`、`05112dde`；已选择性收入 W0 |
| `tools/i_remote_mcp/mcp.mjs` | modified | 精确归属 `2004d3b8` 的 phase 透传与说明修复；已收入 W0 |
| `tools/i_remote_mcp/writeback.mjs` | untracked | 精确归属 `2004d3b8` 的安全去重修复；已收入 W0 |

三处运行修改源码的 Git blob 均精确等于正式分支 `codex/b3-writeback-local-20261003@3a9336b122b2fda22ff65ed32d9cee263e8fc2da` 对应文件，没有发现无法归属的线上独有热修复。该分支的额外 Core transcript/replay 功能不在运行 Core 两文件中，未随本次差异处理整枝搬入。哈希回执见 [W0_RUNTIME_SOURCE_HASHES_20261005.json](W0_RUNTIME_SOURCE_HASHES_20261005.json)。

## 补丁与验证范围

- 当前轮消息按线程末尾未变化的精确重试去重；历史相似匹配只用于连续末尾对齐的 assistant 补交前缀，用户事实修正和新回复不按历史相似度去重。MCP 必须向 writeback 传入标准化 phase，start/end 角色与条数在写入前校验。同步修正 Project 指令对 last_recorded 的说明。
- 出站读取恢复显式 Android 设备、登记平台、接收序号边界及可选 sender / 半开历史窗口。私密类型、关键词、ID 与角色排除始终优先；不复制、更改或重建真实 policy。
- sender/history 读取直接查询已有 chat_messages 与 devices，不依赖 Core transcript/grant API。它不导入缺失历史，也不使仅在手机本地的 companion 回复自动上传；Core 生成的回复仍按原审核规则处理。
- 已带入五份合成测试变更：i_memory 单测、writeback 单测、MCP 写回端到端、v1 账本升级与不可变 pending payload、Android → Core → OAuth MCP 设备边界组合测试。保留 W0 Core 前端权限测试，不新增 transcript 功能测试来扩大范围。

## 合入后的更新步骤（尚未执行）

1. 用户确认 PR 合入后，记录实际 merge SHA；从该 SHA 建立干净正式 C 副本作为发布源码。先核对当前服务入口、Node 可执行文件、启动方式、各模块实际来源与外置状态路径，不能只看旧目录 HEAD。不要对 dirty 运行目录直接 pull/reset/restore，也不要把运行 .state 复制进仓库。
2. 在停止服务和接触真实数据前取得部署授权。仅在仓库外保存现有启动配置、受控源码与哈希回执；按现有数据库一致性流程保全 Core、MCP 账本及外置配置/凭据，不能只复制正在写入的主库而忽略 WAL。真实 policy、设备凭据、令牌、账本与数据库都留在原有本机状态区，避免换源码时重置身份或重新批准出站。
3. 用新副本、独立合成状态先跑当前接口/写回/出站专项，以已批准 merge SHA 校验五源码 Git blob，并在实际发布副本生成文件 SHA-256 清单供切换后核对。审计 JSON 中的 SHA-256 是本次磁盘字节值；新 checkout 的 LF/CRLF 可不同，不能只凭该差异判定源码改动。Core 两文件升级到 W0 版本；三处本地补丁已收进该版本，不再靠 dirty 热改保留。若启动脚本固定旧目录，先准备其源码入口调整和可恢复副本，复核实际模块解析路径后才切换。
4. 经授权的停机窗口停止受影响的 Core/MCP 写入，确认旧进程退出和锁释放；将既有启动器的源码入口切换到已验 merge SHA 副本，保留外置状态参数。先启动 Core 并做最小健康/认证拒绝检查，再启动 MCP。必要的账本 v1→v2 升级已有合成保全测试；本次不新增 Core domain schema 迁移或真实 transcript grant。
5. 记录新 PID、入口、加载版本/源码哈希与服务健康证据。用非敏感合成场景核验完整重复轮次、精确重试、相似事实修正、pending 原文重送、前端拒绝 feed/生成回复与私密优先；只有用户批准的真实读取/写回冒烟才触及真实时间线。不要把磁盘更新或一次健康响应写成真人/跨端验收通过。
6. 若失败，停止新写入并切回保全的旧源码/启动配置；涉及数据库变化时先判断兼容性，按一致性备份恢复，不直接降级运行不兼容库。记录已接收但未处理的写回状态，避免丢失/重复。完成后另写部署回执，当前 W0 源码收尾不等于已经部署。

PR 合入与部署是独立动作；本轮只完成源码差异归属、补丁保存与可审阅更新方案。
