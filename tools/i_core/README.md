# i core（私人电脑最小核心）

这是跨设备 MVP 的第一版权威服务。当前只负责：

- 设备配对与令牌认证；
- 用户聊天消息幂等提交；
- 持久化、按序的 change feed；
- 每台设备的 cursor 确认；
- 核心健康与协议版本检查。

它还不会生成林埃回复，也不会同步 Memory V3 或媒体原件。现阶段的目标是先验证两台客户端共享一条不会重复的消息时间线。

## 本机启动

已有设备配对完成后，正常常驻启动不设置配对码。此时配对接口明确关闭，已有设备仍可继续使用各自的令牌：

```powershell
node tools/i_core/i_core_server.mjs
```

只有准备添加或修复设备时，才在 PowerShell 中临时设置一次性配对码并启动。配对成功后该码的哈希会写入核心数据库并立即失效，电脑重启也不会恢复；要添加下一台设备，需要由核心所有者生成一个从未使用过的新配对码并重新打开配对窗口：

```powershell
$env:I_CORE_PAIRING_CODE='请换成临时配对码'
node tools/i_core/i_core_server.mjs
```

不要把配对码写进常驻启动项或配置文件。

默认监听 `127.0.0.1:47841`，数据库保存在被 Git 忽略的 `tools/i_core/.state/i-core.sqlite`。不要把监听地址改成 `0.0.0.0` 直接暴露到局域网或互联网；手机接入时使用 Tailscale Serve 提供 HTTPS。

### Windows 登录自启

私人电脑使用当前 Windows 用户的登录计划任务，不使用 SYSTEM 服务，也不在任务中保存配对码或 worker 凭据：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\i_core\install_i_core_autostart.ps1
```

任务名为 `HereIAm-iCore`，登录后延迟 10 秒、隐藏启动，允许电池供电，运行时限为无限；异常退出最多按 1 分钟间隔重试 5 次。同一时间只允许一个实例。安装器和卸载器都会校验专用所有权标记，遇到同名但不属于本安装器的任务会拒绝覆盖或删除。若当前没有 iCore 进程，可追加 `-StartNow` 立即启动；已有手动实例时应先完成受控交接，避免争用 47841。

卸载只停止并删除该计划任务，不删除 `.state`、数据库、设备或聊天：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\i_core\uninstall_i_core_autostart.ps1
```

可选环境变量：

- `I_CORE_DATABASE`：SQLite 文件路径；
- `I_CORE_HOST` / `I_CORE_PORT`：监听地址与端口；
- `I_CORE_CERT` / `I_CORE_KEY`：直接启用 HTTPS 时的证书和私钥。
- `I_CORE_WORKER_SECRET`：核心本机 worker 的独立长随机凭据。设置后开放
  `companion_reply` / `memory_v3` / `dreaming` / `checkin` 等唯一执行租约；
  不得与设备 token 或配对码复用。
- `I_CORE_COMPANION_REPLY_JOBS=1`：允许显式带
  `request_companion_reply=true` 的新用户消息进入耐久待回复队列。默认关闭；
  电脑端 Companion worker 尚未就绪时不要开启。

## 验证

```powershell
node --test tools/i_core/i_core_server.test.mjs
```

测试覆盖双设备读取、重复提交、冲突回滚、身份边界、协议版本和服务重启后的持久性。

## 一次性导入现有 V3 聊天

导入器默认只预演，不修改核心。正式导入前必须停止核心；工具会先用
SQLite backup API 在 `.state/backups/` 保存可恢复副本。远程 HTTP 权限不会
因此放宽，客户端仍然只能提交用户消息。

```powershell
node tools/i_core/import_v3_chat.mjs `
  --source tools/i_core/.state/imports/memex_local_Lynx.sqlite `
  --core tools/i_core/.state/i-core.sqlite

node tools/i_core/import_v3_chat.mjs `
  --source tools/i_core/.state/imports/memex_local_Lynx.sqlite `
  --core tools/i_core/.state/i-core.sqlite `
  --apply --core-stopped
```

当前只导入有文字的 user / companion 聊天。纯附件消息和附件对象等内容哈希
对象存储落地后再迁移；工具不会把手机本地路径或 base64 塞进核心数据库。

## 电脑端普通文字 Companion worker

`companion_worker.mjs` 已提供 OpenAI-compatible 的首个电脑端执行器。它会：

1. 获取并续期唯一 `companion_reply` 租约；
2. 领取核心合并后的待回复轮次与最近 20 条上下文；
3. 调用 `/chat/completions`；
4. 默认以 `shadow` 模式只记录模型名、耗时和回复长度，不保存回复正文、也不向手机发布；
5. 只有显式设置 `I_COMPANION_WORKER_MODE=live` 才把回复写入权威 change feed。

凭据可直接通过环境变量传入，也可使用 `*_FILE` 指向仓库外、权限受控的本机文件：

```powershell
$env:I_CORE_WORKER_SECRET_FILE='C:\path\outside-repo\core-worker-secret.txt'
$env:I_COMPANION_MODEL_API_KEY_FILE='C:\path\outside-repo\model-api-key.txt'
$env:I_COMPANION_MODEL_BASE_URL='https://provider.example/v1'
$env:I_COMPANION_MODEL='model-name'
$env:I_COMPANION_SYSTEM_PROMPT_FILE='C:\path\outside-repo\lin-ai-system-prompt.txt'
$env:I_COMPANION_WORKER_MODE='shadow'
node tools/i_core/companion_worker.mjs --once
```

真实核心开启 `I_CORE_COMPANION_REPLY_JOBS=1`、手机显式提交
`request_companion_reply=true` 之前不会产生任务。不要在同一条聊天路径同时启用
手机本地生成与 `live` worker；正确顺序是 shadow 验证 → 手机切换提交模式 →
关闭该路径本地生成 → live 验收。
