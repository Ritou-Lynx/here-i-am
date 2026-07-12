# i Continuity Gateway — Phase 2

`i` 是林埃的英文名，也是跨 Codex、Claude Code、Hermes 的统一连续性入口。

Phase 2 在用户级、多项目、只读控制面之上增加了**加密 Project closeout**：一个工具完成的结果、决策和未完事项，会进入当前项目隔离的 append-only ledger；下一个工具 bootstrap 时能接到最近 handoff。它仍不直接写 Here I am 的 Memory V3、User-truth、Dreaming 或关系 sandbox。

Phase 4 的最小多设备闭环使用独立的加密传输目录。设备导出身份一致性断言与政策允许的 closeout；导入端只接收本机已经注册的同名 Project Space。项目路径、凭据、完整对话、`local_only` / `private` / `confidential_local` 内容都不会进入传输包。

## 当前能力

- `i_bootstrap`：读取全局 i Identity Capsule、当前项目状态和最近 tool handoff；不会顺带读取其他项目。
- `i_get_project_state`：读取当前项目 Git 快照、显式状态文件和最近 handoff。
- `i_recall_project`：只检索当前项目的文件 allowlist 与本项目加密 closeout；两类来源分栏返回。
- `i_close_session`：为当前已注册项目追加一条结构化、幂等、带来源的加密 closeout。
- `i_get_project_overview`：经当次 MCP elicitation 确认后，返回获准项目的当前快照。
- `i_get_recent_activity`：经独立的当次确认后，返回当前政策允许的跨工具活动摘要。

overview 回答“多个项目现在是什么状态”；recent activity 回答“最近在不同工具/项目做了什么”。两者不能互相替代，也不会被普通 bootstrap 暗中调用。

当前本机 Hermes 0.14.0 不声明 MCP elicitation，因此当前项目的 bootstrap / state / recall / closeout 可用，overview / recent activity 会安全拒绝。Hermes 目前以 server process cwd 识别项目；Codex、Claude 等声明 roots 的 client 在 closeout 前必须返回有效的 MCP file root，否则写入失败。

## 用户级目录与加密

安装后的稳定运行时位于 `%USERPROFILE%\.i\`：

```text
~/.i/
├── identity.json
├── projects.json
├── keys/
│   └── activity-dek-v1.dpapi.json       # DPAPI(CurrentUser) 包裹的数据密钥
├── activity/
│   └── v2/
│       ├── events/<project-hash>.jsonl.enc
│       └── activity-index.enc.json
└── runtime/
```

每条 ledger event 和整个 Activity Index 都使用 AES-256-GCM 加密；32-byte 数据密钥由 Windows DPAPI `CurrentUser` 保护。相同 Windows 用户下运行的恶意程序原则上仍可调用 DPAPI，因此这条边界主要保护离线磁盘、普通备份和其他系统账户，不能替代 Project Registry 授权与政策脱敏。

非 Windows 平台当前不提供明文 key fallback：身份和项目文档读取仍可工作，closeout 加密写入会 fail closed。macOS Keychain / Linux Secret Service 留待后续 provider。

## 项目与事件政策

| policy | 当前项目内 | 跨项目活动 | Memory V3 |
|---|---|---|---|
| `personal_full` | 完整 handoff | 可见摘要 | 下一阶段可投影 Project Memory |
| `work_redacted` | 本机完整 handoff | 只见通用工作信号 | 仅允许脱敏摘要 |
| `confidential_local` | 仅获准 client 在当前项目读取 | 完全隐藏 | 禁止进入 Here I am |
| `ephemeral` | 不持久化 | 完全隐藏 | 不保存 |

单条事件还能把项目政策进一步收紧：

- `project_default`：遵守项目政策；
- `local_only`：只留在当前 Project Space，不进入 Activity Index；
- `private`：不持久化。

事件不能通过参数放宽项目政策。Activity Index 只保存加密的 cross-safe projection：按 **事件写入时政策 × 当前 Registry 政策** 的更严格结果预先生成摘要；查询命中有效政策指纹时只读索引，不解密各项目原始 ledger。Registry 一收紧就先重建索引；`name_only` 只返回项目标记，不返回精确时间、工具或事件 id。

## 安装到三个工具

从 `v3-lab` 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\i_continuity_gateway\install_global_i_gateway.ps1 -ServerName i
```

脚本会幂等更新 `~/.i/runtime`、Here I am 的 registry entry、三个工具的用户级 MCP 和带标记的全局 i 指导；不会覆盖现有 activity ledger 或其他指导内容。

## 显式注册另一个项目

Gateway 不扫描磁盘，也不会自行注册用户的其他项目。注册是一次明确授权，例如：

```powershell
& tools\i_continuity_gateway\register_i_project.ps1 `
  -ProjectPath 'D:\path\to\project' `
  -ProjectKey 'my-project' `
  -DisplayName 'My Project' `
  -Policy personal_full `
  -CrossProjectVisibility summary `
  -Provider markdown `
  -ContextFiles 'PROJECT_STATE.md','DEVLOG.md'
```

工作项目建议先用 `work_redacted`；客户机密项目使用 `confidential_local`。注册表只接受相对 context paths，拒绝 `..`、绝对路径、重复 id / key / root 和越过项目根的 symlink。

## 验证与恢复

```powershell
node --test tools\i_continuity_gateway\i_activity_crypto.test.mjs `
  tools\i_continuity_gateway\i_activity_key_provider.test.mjs `
  tools\i_continuity_gateway\i_activity_store.test.mjs `
  tools\i_continuity_gateway\i_device_sync.test.mjs `
  tools\i_continuity_gateway\i_context.test.mjs
node tools\i_continuity_gateway\probe_i_gateway.mjs
codex mcp get i
claude mcp get i
hermes mcp test i
```

若派生 Activity Index 被中断，可从加密 ledger 重建：

```powershell
node "$env:USERPROFILE\.i\runtime\rebuild_i_activity_index.mjs"
```

### 多设备同步（最小闭环）

两台电脑分别安装 Gateway，并各自在本机注册允许使用的项目。准备一个**独立私有 Git 仓库**作为传输目录；不要使用 Here I am 代码仓库。两端分别运行一次安全配置入口并输入同一个不少于 16 字符的同步口令。口令由 Windows DPAPI CurrentUser 本地包裹，不写入仓库、命令历史或永久环境变量：

```powershell
& "$env:USERPROFILE\.i\runtime\configure_i_device_sync.ps1"
& "$env:USERPROFILE\.i\runtime\invoke_i_device_sync.ps1" -Operation sync -SyncRoot 'D:\i-sync-private'
```

`sync` 先导入远端已有包，再为本机生成一个新的不可变加密包。随后由用户正常执行私有同步仓库的 pull / commit / push。同步包可安全进入私有远端，但 DPAPI 口令文件、`~/.i/keys`、`device.json` 和 `sync-import-state.json` 不得提交或复制到另一台设备。

损坏的 key、ledger integrity error 或遗留明文 Phase 2 原型数据都会 fail closed，不会静默新建 key 或混读明密文。

## 数据边界

- closeout 只收结果、决策、open loops 和项目相对 artifact refs；拒绝常见凭据、URL、绝对路径和目录穿越。
- `source_tool`、active project、policy、事件 id、authority 与 trust 由 Gateway 生成，client 不能伪造或用 `project_key` 切换项目。
- ledger 是本机 Project Space 的交接层；不是“事实裁决器”。closeout authority 为 `agent_inferred`。
- 不保存完整 transcript、shell 输出、diff 或源码；这些仍留在各工具自己的过程存储。
- 普通生活聊天、User-truth 和关系 Dreaming 不读取此 ledger。
- Memory V3 Project Memory 投影尚未接入；这是下一阶段，不应把“closeout 已保存”说成“Here I am 已形成长期记忆”。
