# G1 合同：Gemini 授权后被 MCP 协议版本拒绝

## 起因
11-05 Gemini 网页端添加自定义 MCP 报“无法连接到此服务器”。#93 只读诊断：register 201（gemini_pattern）、authorize 302、token 200 都通过，之后 Gemini 对 `/mcp` 的 POST 和 GET 全部 400（GET 本应 405）。服务端在处理 GET 之前唯一的 400 是 `MCP-Protocol-Version` 不在 `SUPPORTED_PROTOCOL_VERSIONS`（只有 2025-06-18、2025-03-26）。Gemini 应已升到 2025-11-25。

## 改动
- `mcp.mjs`：支持列表加 `2025-11-25`（initialize 协商返回该版本；默认版本不变）。
- `diagnostics.mjs`：请求带该头时记 `protocol_version`（日期形状原样，其他为 `other`/`absent`），以后被拒一眼可见。
- `chatgpt_candidate.mjs`：在 HEART_RATE 之后加 `PROTOCOL_PATCHES`（mainline 与 legacy 同一组，只动 mcp/diagnostics），正反向字节一致；候选 mcp `838810b2`、diagnostics `67b0fbec`，server 仍为 HR1 的 `77a8dd30`。
- 部署：`tools/relay_scripts/gemini/g1.mjs`（inspect 只读 / deploy 写），从 HR1 现役任务切到 `HereIAm-iCoreSchema6-g1-proto-20261106`；心率配置、`heart_rate/`、tailscale serve 8447 都不动，切换后检查心率监听与 tailnet 健康。

## 边界
- 不改 Core、OAuth、工具集；Gemini 仍只有 i_context/i_recall/i_chat_turn 与 week_get/day_get。
- 本分支叠在 HR1（#91）之上；HR1 验收前两者都不要合并。

## 验收
- `node --test tools/i_remote_mcp/*.test.mjs` 全过。
- 部署后在 Gemini 网页端重新添加，诊断里 Gemini 的 `/mcp` 不再 400，`protocol_version` 显示实际版本。

## G1 部署结果（11-05 16:26Z）
脚本轮 3 成功：现役任务 `HereIAm-iCoreSchema6-g1-proto-20261106`（mcp `838810b2`），停服 56 秒，8447 健康 200。用户确认 Gemini 能连上，**并且能实际调用工具**（10-24 不调工具的问题已不存在）。

## G2：给 Gemini 开放 ChatGPT 同款工具（用户 11-05 选定）
- 主线：`server.mjs` 中 Gemini 拿 `chatgptDomainTools`（week_get/day_get/food_log/food_day）、`studyTools.gemini_web`、`heart_rate`；`study_tools.mjs` 的 `STUDY_FRONTENDS` 加 `gemini_web:'gemini'`（学习结果文件名后缀 `-gemini.md`）；`domain_tools.mjs` 多包一个 gemini_web。
- 候选：`GEMINI_TOOLS_PATCHES` 排在 PROTOCOL 之后，只改 server（`e418eade`），legacy 内嵌的 study_tools 同步两行，`study_tools.mjs` 仍逐字内嵌。
- 测试：原“Gemini 拿不到”断言改为 Gemini 能拿到（心率、饮食、学习），Antigravity/Sesame 的边界不变；235/235。
- 部署：`g2.mjs`（inspect/deploy），从 g1-proto 切到 `HereIAm-iCoreSchema6-g2-tools-20261106`。
- 数据边界：用户已知晓 Gemini 开着 Keep Activity，心率/饮食/学习数据会留在 Google。
