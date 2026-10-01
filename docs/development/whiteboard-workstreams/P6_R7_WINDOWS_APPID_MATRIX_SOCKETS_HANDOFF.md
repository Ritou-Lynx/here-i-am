# P6 R7 本机网络 fixture 实际正控

2026-09-12，`v3-lab@bbb8025d`；仅新增 sockets 模块、专项纯测试及本机 host baseline，不改生产或既有冻结候选。

最新冻结03：source/快照 `native-appid-matrix-sockets-03.cs` SHA `3F0C2DABDA9ECDD1A7F6D56A1CAD81C8B99AD4548FB4E4EA477F08128E4052D2`，test SHA `ABED53B83D8031E359A31A0260C7A7873EB48C9D0649ECD91F886F67DCC7698A`。增加私有实际local/remote tuple、协议及从操作前至close后的精确FILETIME；父进程以相同时钟检查包含关系，严格canonical/IPv6 scope/role/marker/端口。setup或close失败无事件metadata，绝不变成拒绝证据。`EventProbes`返回已验证的副本，`ZeroReceivesVerified`独立要求八项正控、metadata、最终drain与累计零接收；冻结合同01的`AllNegativeBlocked`保持原含义。

纯测试1/1、87断言，独立复核无未关闭P1/P2。host03 exe SHA `E169910CB5A452B30ED1AFA5AE924CF2EF7DCE5A56428F290CB15A7D276C98B2`，显式host-only实际exit0，八项真实正控、精确父子时间窗、metadata、正常流量不能误记为零、drain与关闭均通过；[baseline03](../../../tmp/p6-r7-review/matrix-sockets-host-baseline-03.json) SHA `730A78E2F59CD6C1B59A93C15FBB0DF9A619B077B04E78AB91C2297B046A73E9`。无WFP变更、无CLI或真实账户请求；这仍不是网络隔离证明。以下02/01为独立历史冻结记录，不拼接候选证据。

当前冻结v2：source/快照 `tmp/p6-r7-review/native-appid-matrix-sockets-02.cs` SHA `E11FDD027187429B2D000A5323B897E59FC28282BAEEC2B7C990B1ECEBAF21DE`；test SHA `03B5387D804900F3ABCFEF68D717B68EDEB051F6085E3D75E4B14316FA8BC33F`。只修正socket先进入caller所有权再设置选项/Bind，防止选项异常发生在接管之前。纯测试再次1/1、53断言通过，独立复核无新P1/P2。host exe02 SHA `F9817D7A48BBC095CD473AFE93FD96DAC5E3550B09FC290D5BBCBD525BBA2F40`，相同入口实际exit0，8正控/drain/资源关闭均通过；[baseline02](../../../tmp/p6-r7-review/matrix-sockets-host-baseline-02.json) SHA `62F26D4F2D00AD1EC0AD6DE6AC4E811861DC1784AB47336D8267B08C571859D7`。两次脱敏报告内容相同、分别保存，exe不同不拼接证据。旧01快照与exe保留，下述01记录为历史。

八种 loopback/local × IPv4/IPv6 × TCP/UDP 的真实 fixture 全部完成本机 marker 正控和排空。只选择当前 Up / Preferred 的本机单播地址，保留精确 IPv6 scope，最多64项；每行持有独占 listener，目标 tuple 由实际 bind 得到。TCP 正控验证两端 tuple、marker和EOF，UDP 验证来源tuple、marker和长度。没有域名解析、外部地址或系统规则变更。

负测先完成socket创建/本地Bind，再单独捕获Connect/SendTo原始返回；setup10013不是负测证明，10035/36/37为未完成。只有合同要求的同步10013、正控与drain完整、最终零接收才能blocked。结果绑定固定role和每行随机marker；`Complete`只记录首轮结果，`AllNegativeBlocked`必须finalDrain，child结束后通过`DrainVerified`或`FinalizeNegativeResults`重新判定迟到流量。关闭失败保留受控socket引用并粘滞失败。

主控纯解析测试1/1通过，包含53个组合/缺字段/错role/错marker断言；独立复核关闭此前“缓存早期通过”P2。冻结源码与快照 `tmp/p6-r7-review/native-appid-matrix-sockets-01.cs` SHA `EEF361826497662DABDCF8446E14E18596250F2FC588CCD5FBEA931551A62F32`。

独立可执行文件 `tmp/p6-r7-helper/matrix-sockets-host-check-01.exe` SHA `AC2EC9913666889AD9D317ABBC03CB3F8BA99D7BF91D3AF91474FFD885D5E302`，显式 `--host-local-baseline` 实际exit0，前后pin一致。原始脱敏报告 [matrix-sockets-host-baseline-01.json](../../../tmp/p6-r7-review/matrix-sockets-host-baseline-01.json) SHA `62F26D4F2D00AD1EC0AD6DE6AC4E811861DC1784AB47336D8267B08C571859D7`：all_host_positive_ready/listener_drain_complete/socket_resources_closed/host_baseline_passed均true。

无WFP的四TCP行返回10035、操作未完成，各listener实际接受1个连接；四UDP行成功发送并各接收1个54-byte datagram。未将未过滤结果判为blocked。`matrix_passed/network_enforcement_tested=false`；这只证明fixture真实可用、基本观测和回收正常，不能证明隔离。真实矩阵需另用冻结三角色runtime完成规则安装、owned-peer正控、child负测、child/Job/stdio/drain及规则回收。

实现依据：[Winsock错误码](https://learn.microsoft.com/en-us/windows/win32/winsock/windows-sockets-error-codes-2)、[Socket.Poll](https://learn.microsoft.com/en-us/dotnet/api/system.net.sockets.socket.poll)、[sendto](https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-sendto)。10013也可能来自Bind，因此仅记录目标操作本身的错误，并要求独立host正控。
