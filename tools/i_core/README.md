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

## iOS 快捷指令邮件手动测试（debug only）

这是一个单用途的人工测试入口，用来验证：

`Android debug App → Tailscale HTTPS → 私人电脑 iCore → 固定邮件 → iOS 自动化`

它不会读取心率、判断睡眠、创建后台任务或自动重试，也没有接入生产
Check-in / CallKit / Agent。外部请求不能指定收件人、发件人、主题或正文；
邮件主题固定为 `哄睡聊天`，正文只含本次本机 receipt 和时间。

首次配置或任何 token / 邮箱轮换前，必须先停掉当前 iCore；否则旧进程仍握有
旧 token，而发送脚本已经可能读到新收件配置。计划任务安装方式可先运行：

```powershell
Stop-ScheduledTask -TaskName 'HereIAm-iCore'
```

然后在私人电脑运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\i_core\configure_shortcut_mail_relay.ps1 `
  -EnableManualTest -UsePasswordDialog `
  -SenderAddress 'sender@gmail.com' -RecipientAddress 'recipient@icloud.com' `
  -SmtpHost 'smtp.gmail.com' -SmtpPort 587
```

配置器还会独占创建短时 configuration lock，并在整个交互 / 写入期间独占保留
`127.0.0.1:47841`；若已有 iCore 或无法取得端口，立即拒绝且不写入新配置。
常驻启动器看到该 lock 时也不会启用邮件端点。配置进程异常退出遗留的 lock
只有在能够取得文件独占锁、证明没有活跃配置器时才会被安全清理。

把命令里的两个示例邮箱替换为固定 SMTP 发件地址和固定 iCloud 收件地址。
`-UsePasswordDialog` 会单独弹出标题为 `Here I Am - Gmail SMTP setup` 的掩码窗口；
密码只能输入这个窗口。若只看到普通 PowerShell 命令行、或输入字符会明文显示，
应立即取消，不要继续输入。TLS 是强制项；Gmail 使用 `smtp.gmail.com:587`，
并使用该账号单独生成的 16 位 app password，不要输入普通登录密码。SMTP
密码由 Windows DPAPI 绑定当前用户和当前电脑加密，配置和独立发送 journal
位于被 Git 忽略的 `tools/i_core/.state/`。

电脑端 relay 只保存 scoped token 的 SHA-256；用于交给手机的原文另存为当前
Windows 用户 / 电脑绑定的 DPAPI 凭据，不打印到终端、不写入配置或仓库，也不
在配置时自动进入剪贴板。token 默认四小时过期，并且只允许一个新的发送
request；相同 idempotency key 仍可在有效期内读取原回执。

`-EnableManualTest` 会写入独立启用标记；常驻启动脚本只有看到这个标记才向
iCore 注入 `I_CORE_SHORTCUT_MAIL_MANUAL_TEST_ENABLED=1`。仅有邮件配置文件
不会启用远程端点，因此默认仍是 fail closed。

配置完成后用 `Start-ScheduledTask -TaskName 'HereIAm-iCore'` 启动新实例。
等 debug 版 App 的「个人中心 → 林埃
核心 → 睡眠接管邮件测试」已经打开，再在私人电脑显式运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\i_core\copy_shortcut_mail_token.ps1
```

复制脚本会把内容标记为不进入 Windows 剪贴板历史、不上传云剪贴板，并在 90
秒后仅当剪贴板仍是该次内容时清空；随后立即在 App 中粘贴并安全保存。这个
标记和定时清空不能防止同一桌面会话里的恶意程序或不遵守 Windows 格式的第三
方剪贴板工具读取内容，真正的兜底仍是四小时服务端过期和一次发送权。
复制成功后，脚本会立即删除用于交付原文的 DPAPI token 文件；若没有及时粘贴，
必须用 `-Force -EnableManualTest` 重新轮换，不能再次导出同一个 token。
release / profile 构建不展示手机入口；电脑端还需上述独立启用标记。

iOS 自动化至少同时匹配固定发件人和主题 `哄睡聊天`，不能只匹配主题。relay
默认五分钟最多一次、UTC 自然日最多三次；每个短时 token 只允许一个新的
UUID request，且同一 request 只会 dispatch 一次。App 超时后只能查询原
request 的 receipt，不能换新 request 自动补发。

回执 `provider_accepted` 只表示 SMTP 提交调用正常返回，不表示 iCloud 已经
收到，更不表示快捷指令或 ChatGPT 已经启动；这三层必须分别验收。发送开始后
若结果不确定，journal 会保留 `outcome_unknown`，不会冒险重发。

重新配置默认拒绝覆盖。必须先停 iCore，再用 `-Force -EnableManualTest` 轮换；
配置阶段会移除旧启用标记，只有新配置完整写入后才恢复。随后启动新 iCore，
并把新 token 重新保存到 App。过期 token 的发送与回执查询都会被服务端拒绝。

若 SMTP 配置没有变化，只需轮换短时 token，不要重新输入或导出 SMTP 密码。先停
iCore，再运行以下命令；它复用现有 DPAPI SMTP credential 和现有 token credential
路径，移除启用标记并独占 `127.0.0.1:47841`。只有显式 `-EnableManualTest` 才会在
成功后重新启用端点；任何失败都会保持关闭。

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\i_core\rotate_shortcut_mail_token.ps1 `
  -EnableManualTest
```

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
