# ChatGPT MCP 部署准备与维护分流 — 2026-10-09

本窗接手已授权的 ChatGPT 接入与真人验收。兼容改动在 PR21（f90058f21049f514f8ab2af407227aee02e2f259）；本分支以 v3-lab@3ce7aacc75615faf31aab7d4d902598070ffa898 为基线，仅补独立 MCP 配置维护流程。两个 PR 分开审阅，不把兼容 CI 继承为维护 CI，不合并或自动部署。

## 已完成

- 逐字核对兼容候选六文件、manifest、ZIP 与源提交；三变三不变。该 head 的 PR/push CI 各9个job及 Policy 均成功。
- 当前 Core schema6 release/configuration 的原路径和哈希不变；不修改固定48项、旧 package-switch MCP不变检查或 custody 包切换逻辑。
- 新生成器严格允许原 tools/ 六文件布局到候选无 tools/ 六文件布局，仅新增 ChatGPT flag=1；Node、数据路径、参数、端口与其余环境字段不变。
- 新backup保留原覆盖、精确重绑4附件与6文件，另保全10个旧链附件；静态167→177项，仍为九类。模板循环hash须由实际捕获更新，不作为备份证明。
- 实际新私有配置已经原固定 PrepareOnly验证，proposal finalize成功；prepared XML与审批预览一致，COM内存仅派生disabled登记XML，未登记任务。
- 独立登记入口固定完整来源闭包，核真实在线会话六终态/MCP start-stop/闭态树hash，持双OS锁与raw DB排他读，CREATE新disabled任务及双SDDL/父SD前后回读；不启动任务、不写custody或数据库。
- 主窗整合专项/相邻权限模板80/80通过；候选来源/ACL修订后窄测分别2/2和3/3通过；登记最终53/53零跳过，含完整wrapper合成成功、四项创建前拒绝、双SD/零实例/数据hash不变及两nonce清理。新head完整CI另签收；合成不等于生产/真人Gate。

## 现场阻断与边界

只读入场发现公网discovery 502，固定Core/MCP无进程，相关端口无监听；旧登录任务enabled零实例，最近会话有ready/mcp-start却缺六终态，marker仍listening。进程消失不能补算clean_closed，也不能拿上一会话的关闭回执替代。原因未判定；本窗未启停/恢复/冻结生产、未读真实DB或独立凭据内容。

静态Prepare初次拒绝来自工具宿主继承NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S。仅清理子进程环境后原固定guard通过；不修改机器环境或guard。

完整审批单与精确配置/source/XML/双SDDL仅位于本机忽略的 build/private-candidates/；不把SID、绝对路径、任务原件、真实数据、密码或凭据提交仓库。

## 待本人决定与后续

先交精确审批单，请本人批准原现有链的一次恢复，以及最新九类＋动态custody的本机/T9加密备份、真实隔离还原与只读Core汇总验证。密码只由本人在安全本机UI输入。未完成新鲜备份/还原，不引用10/08旧结果抵充。

实际clean-close与新鲜备份/还原通过、维护精确head CI全通过后，再绑定现场真实闭态/冻结task/XML/SDDL及source closure形成登记humanApproval，交本人批准；当前没有production authorized=true文件。登记只CREATE disabled，启用另签收。

ChatGPT真人接入用OAuth+DCR、i.read+i.write、OIDC关闭，URL https://i.ilynx.date/mcp；授权由本人完成。分别签收context/recall/chat accepted/重试/幂等/手机同步，以及先有实际MCP请求后的正常关机入口、六终态、开机登录自动启动/同步/写入。只保存ID/状态/hash/时间，不保留消息内容。

flag=0或换旧MCP不会吊销已经发出的access/refresh grants；服务器无Origin请求仍可能访问。需要撤权时按精确ChatGPT客户端处理，不revokeAll影响Claude，不回滚OAuth/B3 ledger丢失新增写入。

`deploymentReady=false`。未改PR10、手机安装、W3、schema、credential或公开历史；D私有旧谱系只读。
