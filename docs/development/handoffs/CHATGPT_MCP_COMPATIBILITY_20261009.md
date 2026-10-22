# ChatGPT MCP 兼容源码交接（2026-10-09）

当前是独立源码候选，`deploymentReady=false`。用户已授权兼容开发及无需真人的验证；本轮不合并、不换现役 MCP、不改生产配置、任务、Core 运行包、隧道、原库或手机。真实 ChatGPT 连接及新候选的关机验收仍待本人。

## 基线与当前运行边界

- 分支：`codex/chatgpt-mcp-compat-20261009`，从已合并 PR #20 的 `v3-lab@3ce7aacc75615faf31aab7d4d902598070ffa898` 开出。
- 既有授权现场已完成 Core 同 schema 换包；本轮开始时现役 Core 是 `2c01de5baa35a8bdb3f007dd56f5b4ae88c13ef7` 固定包，manifest 为 `aef68af00ff8e084b52d7db5b61dc8635399c741de19a844069e879f121f0158`。本轮不再次签收它的真人 Gate。
- 现役 MCP 仍是旧六文件包。`legacy_b3` 唯一上传器、47862 桥及登录会话管理顺序保持；PR10 上传器与 W3 captures/规划功能均未在本轮激活。
- 上一轮现场、批准配置及其 settings 目录继续保留、不可清理。源码分支不携带生产配置、真实库、凭据或私有回执。

## 已证实的兼容缺口与证据界限

用户截图的 URL、OAuth、DCR 和 discovery 端点正确。现役代码默认只接受 Claude 两条精确回调；ChatGPT 稳定回调会被 `/register` 拒绝。`/mcp` 若收到 ChatGPT Origin，也会在认证前被拒绝。此前只读核对确认公开两份 discovery 为 200、未认证 MCP 为正常 401、现役源码 pin 一致。

没有捕获用户那次失败的实际 DCR 请求，因此只确认存在兼容阻断，不能声称已证实该次错误的唯一阶段。截图中的 CIMD/OIDC 不可用属于未实现能力，不作为这次错误原因。

依据：[OpenAI 身份验证文档](https://developers.openai.com/plugins/build/auth)、[自定义 MCP 指南](https://developers.openai.com/api/docs/guides/custom-mcp-server)。声明 RFC 9207 issuer 返回能力后，新 ChatGPT DCR 可使用精确稳定回调；不能据此开放任意逐连接回调。

## 实现

1. `I_REMOTE_MCP_CHATGPT_ENABLED` 未设置或 `0` 时关闭，`1` 开启；空值或其他值拒绝启动。OAuth 实例保留启动时布尔快照。
2. 仅增加 `https://chatgpt.com/connector_platform_oauth_redirect` 精确回调。域名大小写、显式端口、子域、query、fragment、userinfo、路径追加、编码近似及任意 `/connector/oauth/*` 均不自动放行；原有显式 extra HTTPS 精确配置能力保留。
3. 元数据诚实声明 `authorization_response_iss_parameter_supported: true`，两处实际重定向均已有 exact `iss`；不能安全重定向的错误仍在本地返回。
4. 仅启用时为 exact `https://chatgpt.com` 提供受限 MCP CORS。OPTIONS 只允许 POST/DELETE 和五种 MCP 请求头，不读取业务数据；actual 请求仍经过 Bearer、scope 和 session 家族校验。不增加 credentials CORS。
5. 原公共客户端 DCR、PKCE S256、resource/client/redirect 绑定、refresh 轮换与重放吊销、写入 scope 不变。旧 i.read 令牌刷新不能自行扩权。
6. 将一条“去 claude.ai 重连”的拒写提示改成“当前客户端的连接器设置”，避免 ChatGPT 收到错误平台指引；不改变拒写条件或响应结构。
7. 沿用 `frontend:claude_web` / `claude_web` 既有网页主体与 B3 thread/sync_id 规则。它是历史渠道别名，不是对实际客户端的归因。不同客户端/线程相同正文不合并。

## 最小候选与防止夹带功能

主线 MCP 同时含未激活 W3/领域实现，不能直接把主线目录换到生产。新增 `tools/i_remote_mcp/chatgpt_candidate.mjs`：

- 只读固定基线 Git blobs，逐项验证既有 legacy 六文件 SHA256/大小；不读生产目录、配置、库或凭据。
- 只向旧 server/oauth 应用这次严格兼容差异，向旧 mcp 应用一条提示替换；逆变换须恢复原 SHA。对固定主线基线应用同一变化必须等于当前源文件，任何额外差异拒绝构建。
- diagnostics、writeback、i_memory_read 三项字节完全不变；不复制 domain_tools 或 W3 依赖。
- 输出必须是本 checkout 下新建的 build 子目录，拒绝现存目录、链接、别名或越界路径。输出根的 manifest 与 `runtime/` 六文件分开，避免现役 inventory 全目录检查把 manifest 当第七个运行文件。
- manifest 记录固定基线、源码提交、六项前后 hash 和变化状态，标为 `not_deployed`。输出本身不启动服务，不生成生产配置，不改变 approved hash 链。

本地示例：`node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/chatgpt-mcp-candidate`。实际候选测试直接 import 这六文件的真实导出，检查与主线实现引用不同，再复用相同 HTTP 端到端用例，避免只测主线后假定候选通过。

## 验证与 CI 签收

主窗本机 MCP+i_memory 整组 **180/180** 通过，22 suites，零失败、零跳过（8.110 秒）。其中 OAuth 29 项、候选构建/实际 CLI 7 项、主线和实际候选同一套 HTTP E2E 共 12 项；独立安全复核 OAuth+E2E 通过。`git diff --check`、CI YAML 九 job 和两处 historical checkout 检查通过。实际还未进行的 CI 和真人 Gate 不计入这些结果。

CI 增加必跑 Windows MCP job，Linux Bridge 同时覆盖新增测试；两者都获取固定历史基线，Windows 上传只含源码的六文件候选及 manifest。最终精确 HEAD、完整 CI/Policy 和候选 manifest 摘要见本 PR 的实时检查及验收说明，不将历史绿灯或待运行状态写成当前完成。

最小候选字节（从固定 Git 原件生成，Windows/Linux checkout 的换行差异不会改变这六项）：

| 文件 | 相对旧包 | 候选 SHA256 |
|---|---|---|
| i_remote_mcp/server.mjs | 兼容接线 | `3aeb9295bc3071302c11343471cdaa60bec4577d7599d1813e8a4d984f7f41c9` |
| i_remote_mcp/oauth.mjs | 精确回调及 issuer 声明 | `d7ac4c7608df99d3bc3e030cecf10d4e74d8aed6875182688c89880d25bccab9` |
| i_remote_mcp/mcp.mjs | 仅中性重授权提示 | `f639c9d210f3632456d682835cd9e5f87309e9556da0b50519bb55d61773c63b` |
| i_remote_mcp/diagnostics.mjs | 逐字不变 | `b60230926d0fa8cbcf2cbfefa5667656190507d828fc953605837d8f04e5b4f7` |
| i_remote_mcp/writeback.mjs | 逐字不变 | `f2aac48db1cf61a44a0c9b5b28087b90894f03396cd52830a4428532944bc52a` |
| i_memory/i_memory_read.mjs | 逐字不变 | `cee185180b825a141b645a12ab1f1812a61b9eb7462c347465b7ac4449af4e28` |

合成验证范围：真实本地 HTTP、临时 SQLite、真实 read model/writeback、假 Core，DCR→授权→PKCE→MCP→聊天写回→检索→refresh；默认关闭、近似地址拒绝、CORS、Claude 并行、独立线程、私密过滤、只读拒写及凭据不进入日志。未调用真实 ChatGPT/Claude、现役服务、手机或真实数据库。

## 激活方案与授权节点（本轮不执行）

| 步骤 | 工作及成功判据 | 失败处置 / 本人节点 |
|---|---|---|
| 0 审核 | 审核本独立 PR、精确源码/六项候选 manifest、Windows/Linux 回归与完整 CI。确认旧 notes、legacy_b3、47862 保持 | 未批准不合并、不发布；合并也不自动授权激活 |
| 1 准备配置链 | 将最小候选作为独立 MCP 包，按现役私有文件要求准备 owner/ACL/source inventory；显式 flag=1。保留原状态/令牌/B3 账本/手机拉取凭据，Node 和 Core 包字节不变 | 新 mcp.json、备份覆盖、login/XML 及双 SDDL/父 SD 必须重新生成精确审批。现有 Core 换包工具锁定 MCP 不变，不能假装原链仍适用；若需维护层扩展，另开维护 PR，先合成验证和审批 |
| 2 备份 | 最新九类与 custody 动态清单捕获前后 check，本机+电脑外完整加密备份，隔离真实还原及只读 Core 校验 | 需要本人确认介质/口令时叫人；不以 hash 或 backup_completed 代替恢复 |
| 3 受控激活 | 仅按另行批准的 MCP 配置切换路径执行；仍由会话管理器保证先停 MCP、再认证关闭 Core，Core ready 后再启 MCP | 不手工启动第二个 MCP，不编辑已批准 pin 或复用未授权链；停点按最终维护方案执行 |
| 4 ChatGPT 真人 | 添加 URL `https://i.ilynx.date/mcp`、OAuth/DCR、i.read+i.write，OIDC 关闭；完成口令授权，实际 i_context / i_recall / i_chat_turn，观察 accepted、重复、重试与手机可见性 | 需要本人登录和输入口令，不记录口令/令牌；创建失败只取无敏感固定错误和阶段。调用合成通过不能签收此项 |
| 5 回归/关机 | Claude 可用时做同工具回归；手机不安装、不改配置。让 MCP 实际处理请求后进行正常关机→开机→登录，分别核入口到达、六终态、登录自启及客户端同步 | 需要本人真实操作。入口零份先查 session-window 的 window station/desktop/任务模式。任何 Gate 未完成保持 deploymentReady=false |
| 6 回退与签收 | OAuth客户端新增/聊天写回不等于更换 Core schema；保留旧包和原配置。反向仍应由批准的受控维护路径恢复，原状态不回滚 | 兼容前后 B3数据格式不变，但启用后已有写入不能通过恢复旧账本丢弃；单纯关闭flag会拒绝ChatGPT回调，不能作为无影响回退。禁止手工放宽检查或并行拉起旧服务 |

ChatGPT 的重授权权限提示已中性化；其连接界面并不需要手填通配回调。若启用后的真实 DCR 仍请求不同精确 URI，先保存无敏感元数据调查，不直接扩大白名单。

## 尚未完成及明确保留

- 本轮只完成源码、自动测试与候选准备；未合并、部署、激活或签收真人 Gate。
- 未改变 Core 的关机/恢复/会话运行字节，既有真人 clean-close 验收继续待人。
- 未启用 PR10、安装手机、切换 captures 消费者、退役 47862 或刷新旧记忆快照；这些仍按原专项方案推进。
- 定时静态备份不会自动纳入未来 custody 历史的既有缺口、换机激活重绑缺口仍保留，不因本次兼容被宣告解决。
