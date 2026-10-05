# W3 领域 MCP 源码交接（2026-10-05）

基线 `v3-lab@8dde12b312ad83f7475df8bd99a359f1b2d782d6`，分支 `codex/w3-domain-mcp-20261005`。只改 remote MCP、i_memory 工具层白名单和本交接；未改 Core 业务、全局状态、线上服务、真实配置/数据库/凭据。未派生子 Agent。本地提交按 worker 常设授权，主窗整合全局状态；没有 push/PR/merge 或手机动作。

## 运行源码对齐

先只读核对隔离 `mcp-align-20261005` 的 `MCP_RUNTIME_ALIGNMENT_20261005.md` 及状态。其原五源码结论为：旧 Core 两文件不是现役固定包入口；MCP/memory/writeback 的运行改动已在 W0。进一步比较 W0 `858497947912940903be12841c8f8026b6fe790f` 与本基线，mcp/writeback/server/oauth/diagnostics/i_memory_read 六个路径提交差异为空。因此没有可补回的新 MCP 源码，不覆盖旧候选或现役工作树。现役固定 schema4 Core 的 transcript/replay 保全仍由主窗另办，不将本证据说成升级已完成。

## 实现

- `tools/i_remote_mcp/domain_tools.mjs`：capture_add/list/ack、plan_list/upsert/set_status、week_get/set、day_get/set；严格工具参数、业务字段 schema、固定 actor/source/processor，原样传递 Core receipt/problem/tombstone。所有写入需稳定 op_id/id/base/timestamps，不自动 rebase、重排或重试创建新 intent；网络结果不明标 transport_unknown。
- 独立 `planner_server.mjs` 硬绑定 127.0.0.1，scoped token→受控目录上限→同 token 转发 Core；无 chat handlers、无 worker key、拒绝浏览器 Origin/Fetch 请求。默认最小权限 captures:read/ack、plan 三域 read/create/patch；额外 capture create/user status 必须分别获得真正 Core 能力。不会扩大公网 listener。
- 网页 createApp 拒装 planner 工具；只可 capture_add/week_get/day_get。网页 OAuth i.read/i.write 与真实 Core scope 两层限制。Core notes 使用外置显式配置选择，默认仍保持既有路径。
- Core `i_remember` 支持 add/update/delete/list、旧 note_id，user_via_agent authorization_ref 必须经 Core verifier；不自动读取聊天构造授权。Core 模式只写 captures、不写旧 notes、不启旧 47862 feed。聊天轮次仍用原 B3 账本；Core notes 暂不可用时，保留已成功聊天结果并显式 notes_error，不回退旧 notes。
- 网页捕获 owner-only 凭据和计划只读凭据独立：origin_device_only 是 Core principal 的全局过滤，不能为读取其他来源计划而放宽捕获归属。可用 plan_reads 单独 scoped token 组合周/日查询。
- 删除 permanent=true；真实 Core 验证在线正文/操作 payload 清除、旧 create 重放拒绝、删除精确重试复用 receipt。只声明在线正文，不声明磁盘页/WAL/备份物理擦除或用户改卡级联清除。
- 旧迁移复用 W2 `import_personal_notes.mjs`，保持默认 dry-run、旧 ID/revision/author mapping；迁入来源 i_remember 的 planner skipped，新的 claude_web capture 双处理者 pending。只验证合成关闭副本。
- i_memory policy v2 的 domains 白名单可选 chat/memory_v3 子集（空集也可），未列领域正文/ID/统计/时间元数据不读，未知领域拒绝。v1 只固定兼容旧 chat/memory_v3，不自动授权新增 Core 表；未改真实 policy。

## 验证

最终 Node 组合 **172 tests / 172 pass / 0 fail / 0 skip，exit 0**，18 suites。覆盖 remote MCP 全部测试、i_memory 全部测试，加 Core personal_data_domains、personal_data_http、import_personal_notes。Node 为指定 SDK；临时合成 schema6 Core 在独立随机 loopback 端口运行，所有候选服务关闭并清理各自临时数据根。

其中新增真实 Core MCP 集成 **11/11**：创建/精确重试/改请求冲突；周/日版次/原子组；planner ack 与 text revision；即时删除及旧重试；伪造授权/他人对象/未知字段；真实 planner token 请求 `/v1/core/changes` 的认证拒绝；用户状态派生时间和 user_conflict/user_locked；丢失响应后唯一 change；本机 listener/OAuth 隔离；Core off 下聊天结果保全；legacy dry-run/adoption/skipped；OAuth→MCP→Core；独立网页计划 reader；Core token 轮换拒绝。新增 policy 白名单 3 项并通过全部旧读取回归。

最终组合日志 SHA-256：`91FFCA1B421231E8CFCE1A45534CA2BBD171F13B29EF50E30574AFA01BB976D5`。日志只留本机临时目录，仓库不收 shell 输出。源码最后一次改动后执行该最终组合；通过后只增加本文。`git diff --check` 通过。先前开发测试中的包装/测试路径问题已修正；没有放宽业务断言或跳过测试。

## 主窗接线与限制

1. **目录 scope 是上限，不是实时授权证明。** Core 现在没有 token introspection，工具目录来自 owner 配置，可能比当前已撤销/缩权的 token 宽；每条实际数据操作使用同一真实 token 到 Core 再检查 generation/scope/对象归属，撤销拒绝已测。若验收要求 tools/list 也即时反映真实 grants，需要主窗另加受审计的 Core introspection 接口；本 worker 按禁止改 Core 的边界没有自造接口或直读库绕过。
2. **生产授权 verifier 尚未接线。** captures user_via_agent 和用户 status 要有受信入口发出的、绑定 principal/操作/目标/字段的 authorization_ref；本包只用合成 verifier 证明边界，未给任意文本/消息 ID 签发证据。缺 verifier 时 Core 拒绝，不能启用后宣称可用。
3. **生产切换未执行。** owner 需签发最小 scoped credentials、配置业务 hooks/模式和独立网页计划 reader，升级 policy v2；保持生命周期修复与固定 schema4 transcript/replay 保全前置。旧 notes 冻结/一致备份/真实迁移/对账及主机服务切换仍需独立接受，不在本包运行。
4. 本包仅查询分页，最后一页释放短期 snapshot；没有为 Codex 建第二份数据仓库/耐久同步副本。维护副本的客户端须走完整 Core feed/snapshot 持久化协议。
5. worker 本地提交只 stage 拥有路径与本 handoff；按单次 `SKIP_PROJECT_STATE=1` 例外，主窗负责 DEVLOG/I_PROJECT_STATE 和最终整合，环境变量随后恢复。

配置及参数细则见 `tools/i_remote_mcp/README.md` W3 节；未提供真实 token 或生产路径模板值。
