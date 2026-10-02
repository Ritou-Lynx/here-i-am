# 无人值守验证

> 状态：2026-10-02 起生效，用户确认。目标是让真人不再守在电脑前等授权：机器跑全部客观检查，真人只异步判断主观体验。根规则见 `AGENTS.md`「验证与交接」和「无人值守环境常设授权」。

## 1. 四层验证

| 层 | 内容 | 在哪跑 | 何时跑 |
|---|---|---|---|
| L1 | 单元、widget、生产组合场景（`productionComposition`、真实 Drift、真实键鼠事件，模型与 Bridge 用脚本化替身）、平台无关 Bridge Node 测试 | GitHub CI · Linux | 每次 push 任务分支或 `v3-lab` |
| L2 | 构建前关键检查、Windows Debug 构建、hermetic 白板集成测试（真实窗口），截图作为产物 | GitHub CI · Windows | 每次 push |
| L3 | 真实模型、真机/手机、系统输入法与第三方输入 | 专用测试机或带密钥的手动 workflow | 每个候选或每晚 |
| L4 | 口吻、手感、视觉 | 真人看报告、截图或录屏 | 每个里程碑一次 |

CI 定义在 `.github/workflows/ci.yml`。仓库公开，GitHub 托管 runner 对公开仓库免费；Windows runner 以管理员运行且 UAC 关闭，不会弹系统确认。

## 2. 规则

- 自动层对每个候选 SHA 重跑，CI 运行页、JSON 结果和截图产物就是证据，不再手写 SHA、PID、句柄计数长文。
- 失败不中止：一次跑完全部场景，汇总后一轮返修。每个场景使用独立临时数据目录，避免一个失败连带后续。
- 新 Gate 先写成自动场景。只有确实无法自动判断的主观项进入 L4。
- 真人结论按受影响路径沿用：改动没有触及该结论覆盖的源码路径时沿用，并在报告注明；触及时只重看受影响的项。
- computer use 只用于探索或系统集成点验。它往 Flutter 输入框注入文字不可靠、点不到 UAC 安全桌面、授权会过期且占用屏幕，不作为回归验收手段。
- 交互与输入用 `integration_test` 的 `tap` / `enterText` 驱动：它们直接进入 Flutter 引擎，不经过系统输入法，也不移动真实鼠标。

## 3. 脚本化模型验收场景（L1）

`test/acceptance/` 用脚本化模型重放真人 Gate：`ScriptedWorkbenchRuntime` 按 Codex App Server 的事件协议工作（先发工具调用，等宿主逐个回应后再回复并结束本轮），读取宿主拼进提示的白板上下文来决定命令，其余全部走生产路径——桌面聊天窗口、持久化用户消息、`productionComposition` 与默认白板工具、实时画布路由、文件型 SQLite。

`whiteboard_ai_acceptance_test.dart` 覆盖 Goal 1 P4 真人 Gate 的完整顺序：创建 → 改正文 → 设标签 → 相对移动 → 画布选中后在聊天里加宽 → 旧撤销在后续改动存在时被拒且令牌保留 → 按序撤销 → 从白板移除且卡片本体保留 → 关库重开后用持久令牌撤销移除。每一步同时断言工具回执、行动卡、画布、数据库与卡片本体。曾在真人阶段才暴露的两类回归（撤销顺序检查、R19 只清选区被误判为白板重挂）已用临时改坏代码验证会被它拦下。

新增 Gate 按这个模式先写成场景。真实模型的措辞与判断仍属 L3，口吻与手感仍属 L4。

## 4. 看结果

- 每次 push 后看 GitHub Actions 的 `CI`；手机 GitHub App 会推送失败通知。失败用例在作业日志和注释里逐条列出，产物包含 JSON 结果与白板截图（`whiteboard-screenshots`）。
- `Flutter full suite (Linux)` 运行全部 Flutter 测试并阻断。依赖 Windows 文件锁语义的两项 outbox 测试在 Linux 跳过，改由 Windows 作业运行。
- `bridge-node` 跳过只能在 Windows 编译的原生隔离测试和依赖本机 pin 的产品宿主测试；这两类仍随 Windows 验收流程运行。

## 5. 专用测试机（备用电脑）

只承担 CI 做不了的 L3：真实手机、系统输入法 / `Win + H`、需要 ChatGPT 登录的 Codex App Server 等。按下面一次性配置后无需有人值守。

1. 新建本地管理员账户（如 `hia-test`），只放本仓库 clone 和合成数据；除测试用的 Codex 登录、模型密钥外，不登录私人账户、不复制真实数据库。
2. 用 Sysinternals Autologon 设置自动登录；电源设为从不睡眠、不关屏，唤醒不要求密码：
   ```powershell
   powercfg /change standby-timeout-ac 0
   powercfg /change monitor-timeout-ac 0
   powercfg /SETACVALUEINDEX SCHEME_CURRENT SUB_NONE CONSOLELOCK 0
   powercfg /SETACTIVE SCHEME_CURRENT
   ```
3. 只在这台机器上让管理员提权不弹窗（管理员 PowerShell）：
   ```powershell
   Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' ConsentPromptBehaviorAdmin 0
   ```
4. 界面测试需要未锁定的控制台会话：不要用远程桌面（RDP）连上再断开，断开会锁屏。远程查看用以系统服务方式安装的 RustDesk 或 Chrome 远程桌面（能处理 UAC），配合已有 Tailscale。
5. 测试机上的 Codex 使用完全访问、不询问审批的模式（例如 `~/.codex/config.toml` 中 `approval_policy = "never"`、`sandbox_mode = "danger-full-access"`，以当前 Codex 版本文档为准）。
6. 手机常插 USB 并在开发者选项打开「充电时保持唤醒」，USB 调试选择始终允许这台电脑。
7. 公开仓库不挂 GitHub 自托管 runner：别人 fork 后发 PR 就能在 runner 上执行代码。测试机由 agent 直接运行验证，或用计划任务轮询自己的任务分支。
