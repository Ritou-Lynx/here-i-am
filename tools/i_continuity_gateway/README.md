# i Continuity Gateway（已退役）

2026-11-07 起，本机连续性网关（`i_bootstrap` / `i_get_project_state` / `i_recall_project` / `i_close_session` / `i_voice_*` 等本机 stdio MCP 工具）退役，由远端 i MCP（[tools/i_remote_mcp](../i_remote_mcp/README.md)：`i_context`、`i_chat_turn`、`i_recall` 等）取代。Codex、Claude Code、Hermes、OpenCode 里的本机 `i` 条目和 `i-continuity` 指导块已从用户电脑上清除，安装器、MCP 服务、语音上下文、多设备同步和探针代码也已删除。

本目录只留下仍有调用方的部分：

| 文件 | 调用方 | 去向 |
|---|---|---|
| `identity.default.json` | `tools/i_remote_mcp/mcp.mjs` 的默认身份（生产候选也依赖） | 保留；挪位置需随远端 MCP 重新部署 |
| `i_activity_store.mjs`、`i_activity_crypto.mjs`、`i_activity_key_provider.mjs`、`i_project_registry.mjs` | `tools/dev_agent_bridge` 的 DevRoom 项目记忆收尾 | 随记忆重构 M5（删项目记忆）一起删 |

用户电脑上的 `~/.i/` 目录暂不删除：远端 MCP 未设 `I_HOME` 时会读 `~/.i/identity.json`，DevRoom 收尾也写这里的加密账本。

历史设计见 [LIN_AI_CROSS_TOOL_CONTINUITY.md](../../docs/companion-first/LIN_AI_CROSS_TOOL_CONTINUITY.md)（已标记退役）。
