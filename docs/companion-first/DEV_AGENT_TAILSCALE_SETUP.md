# Dev Room 外出连接：Tailscale 配置指南

让手机不在家 WiFi 下也能稳定连家里的 Bridge。一次配置，永久有效。

预期耗时：20-30 分钟。配置完之后 URL 不会变，下次开机自动就绪。

---

## 为什么是 Tailscale

| | cloudflared 临时（当前） | Tailscale（推荐） |
|---|---|---|
| URL 稳定 | ❌ 重启就变 | ✅ 永久 |
| 电脑要开窗口 | ✅ 两个 | ✅ Tailscale 后台 + Bridge 一个 |
| 数据走第三方 | ⚠️ 经 Cloudflare | ✅ P2P（直连家里电脑） |
| 国内稳定性 | 中 | 好 |
| 流量元数据可见 | Cloudflare 看得到 | 不存在第三方 |

### 当前结论：不需要再搭一个 Bridge

Dev Room 只需要一个本机 Bridge：`http://localhost:47831`。Tailscale / Cloudflare Tunnel 都只是外出访问层，负责把手机流量带到这一个 Bridge，不应该再起第二套 Bridge。

这次遇到的“电脑明明开着，但手机过一会儿连不上；打开手机 Tailscale 看一眼又好了”，更像是 Tailscale 直连空闲后的假性离线：

1. 家用路由器的 UDP NAT 映射过期。
2. Windows / Wi-Fi 网卡进入省电状态。
3. Tailscale daemon 等下一次流量才重新激活通道。

所以短期修法是：关掉 Windows 网卡省电 + 给 Tailscale 一个低频常驻流量。Bridge 本身不用换。

---

## 一次性安装（电脑 + 手机）

### 1. 电脑：装 Tailscale

下载地址：<https://tailscale.com/download/windows>

装完后会让你登录。**用任意一个邮箱注册一个 Tailscale 账号**（个人版免费，最多 100 台设备，对你完全够用）。

登录后状态栏会出现 Tailscale 图标。

### 2. 手机：装 Tailscale

iOS App Store / Android 应用商店搜 "Tailscale"。装完用**同一个账号**登录。

打开 Tailscale 开关。手机数据流量也会自动走 Tailscale。

### 3. 拿到电脑的 Tailscale 设备名

电脑上打开 PowerShell：

```powershell
tailscale status
```

会看到一行类似：

```
100.x.y.z   your-pc-name        you@gmail.com    windows  -
```

记下 `your-pc-name`。完整的设备名长这样：`your-pc-name.tail-xxxxx.ts.net`，可以在 Tailscale 网页控制台 <https://login.tailscale.com/admin/machines> 看到。

---

## 启动 Bridge + 暴露 HTTPS

### 1. 启动 Bridge（PowerShell 窗口 A）

```powershell
cd D:\memex\.claude\worktrees\friendly-mirzakhani-74e840
.\tools\dev_agent_bridge\start_bridge.ps1
```

保持窗口开着。

### 2. 用 `tailscale serve` 暴露成 HTTPS（PowerShell 窗口 B）

```powershell
tailscale serve --bg https / http://localhost:47831
```

`--bg` 让它后台运行，不需要保持窗口开着。

跑完一次它会输出：

```
Available within your tailnet:

https://your-pc-name.tail-xxxxx.ts.net/
  |-- proxy http://localhost:47831
```

**这个 URL 就是你的永久 Bridge 地址**。Tailscale 自动给真证书，App 不需要任何信任配置。

### 3. 手机 App 改 Bridge URL

App → Dev Room → 编辑项目 → Bridge URL 填刚拿到的 `https://your-pc-name.tail-xxxxx.ts.net`（末尾不要带斜杠）→ 测试 Bridge 看是否通 → 保存。

---

## 修复 Tailscale 假性离线

先做 Windows 省电设置，再加 keepalive。两者不冲突。

### 1. 关闭 Wi-Fi / 网卡省电

设备管理器 → 网络适配器 → 当前 Wi-Fi / 以太网适配器 → 属性：

- 电源管理：取消“允许计算机关闭此设备以节约电源”
- 电源选项 → 高级电源设置 → 无线适配器设置 → 节能模式：改成“最高性能”

如果是 Windows 11 支持 Modern Standby 的机器，插电关屏时也可能偷偷降级网络栈；上面两项优先确认。

### 2. 加 Tailscale keepalive

电脑端定期给手机或另一个 tailnet 节点发一个很轻的 Tailscale ping，避免直连/NAT 映射睡掉。

先在电脑 PowerShell 里找到手机的 Tailscale IP 或设备名：

```powershell
tailscale status
```

手动试跑：

```powershell
cd D:\claude-workspace\memex
powershell -ExecutionPolicy Bypass -File scripts\devroom_tailscale_keepalive.ps1 -Target 100.x.y.z
```

`100.x.y.z` 换成手机的 Tailscale IP，或另一个稳定在线 tailnet 节点。脚本每 30 秒发一次 peer ping，并检查本机 `http://127.0.0.1:47831/v1/health`。日志在：

```text
%LOCALAPPDATA%\HereIAm\devroom-tailscale-keepalive.log
```

### 3. 注册成 Windows 登录后自启

```powershell
$repo = "D:\claude-workspace\memex"
$target = "100.x.y.z"

$action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$repo\scripts\devroom_tailscale_keepalive.ps1`" -Target `"$target`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -RestartCount 999 `
  -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
  -TaskName "DevRoomTailscaleKeepalive" `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description "Keep Tailscale warm for Here I am Dev Room" `
  -RunLevel Limited
```

要停：

```powershell
Unregister-ScheduledTask -TaskName "DevRoomTailscaleKeepalive" -Confirm:$false
```

### 4. 什么时候换 Cloudflare Tunnel

Dev Room 阶段优先用 Tailscale + keepalive：安全边界简单，只有 tailnet 内设备可访问。

如果后续把“角色实时聊天接 Claude / Codex brain”也依赖这条链路，Bridge 可用性要求会高很多。那时可以把同一个 Bridge 放到 Cloudflare Tunnel 后面：

```text
https://bridge.your-domain.com -> http://localhost:47831
```

这不是“新搭一套 Bridge”，只是把访问层从 Tailscale 换成 Cloudflare 的 outbound 长连接。需要配 Cloudflare Access 或 Bridge token，避免公网裸露。

---

## 日常使用流程

之后每天用，只需要：

```powershell
cd D:\memex\.claude\worktrees\friendly-mirzakhani-74e840
.\tools\dev_agent_bridge\start_bridge.ps1
```

⚠️ 注意 **必须从 worktree 路径启动**，不要直接从 `D:\memex` 跑——主仓库的 `v3-lab` 本地副本可能落后于 origin，会跑到旧版 bridge 上。等 Phase 2 改动合入 `v3-lab` 并 pull 下来，就能从任意路径起了。

Tailscale 服务和 `tailscale serve` 配置都是后台/持久的。

## 开机自启（推荐，省得每次手动启）

`tailscale serve` 已经是后台的，重启后自动恢复。只剩 Bridge 进程需要每次手动起。一次性配好就再也不用管。

### 方法 A：开机自动启动脚本（最简单，3 分钟）

1. 按 `Win + R`，输入 `shell:startup`，回车。打开"启动"文件夹
2. 在里面新建一个 `start-dev-bridge.bat`，内容：

```batch
@echo off
cd /d "D:\memex\.claude\worktrees\friendly-mirzakhani-74e840"
start "Dev Agent Bridge" /min powershell -NoLogo -NoProfile -File ".\tools\dev_agent_bridge\start_bridge.ps1"
```

3. 重启电脑测试一次：登录后会自动弹一个最小化的 PowerShell 窗口跑 Bridge，不打扰前台

要停掉的话，按 `Win + R` → `shell:startup` → 删 .bat 文件。

### 方法 B：Windows 任务计划程序（更稳，崩了会自动重启）

适合长期严肃用。挂个开机触发的计划任务：

```powershell
$action = New-ScheduledTaskAction `
  -Execute "powershell.exe" `
  -Argument "-NoLogo -NoProfile -WindowStyle Hidden -File `"D:\memex\.claude\worktrees\friendly-mirzakhani-74e840\tools\dev_agent_bridge\start_bridge.ps1`""

$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME

$settings = New-ScheduledTaskSettingsSet `
  -StartWhenAvailable `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask `
  -TaskName "DevAgentBridge" `
  -Action $action `
  -Trigger $trigger `
  -Settings $settings `
  -Description "Dev Room Bridge for Here I am" `
  -RunLevel Limited
```

之后 Bridge 在你登录后自动起、隐藏窗口、崩了会自动重试 3 次。

要停：`Unregister-ScheduledTask -TaskName "DevAgentBridge" -Confirm:$false`

### 注意

- worktree 路径如果你之后改了（比如 fast-forward 到主仓库后从 `D:\memex` 起），记得更新脚本里的路径
- Bridge 升级了代码后要手动重启一次它的进程，自启脚本只管"起来"，不管热重载

---

## 怎么停掉外网访问

不想用了：

```powershell
tailscale serve reset
```

URL 立刻失效。下次想再用，重跑第 2 步即可（URL 不变）。

---

## 排查常见问题

**手机点"测试 Bridge"超时：**
- 电脑上 `tailscale status` 看自己在不在线
- 电脑上 `curl http://localhost:47831/v1/health` 看 Bridge 本机能不能通
- 看 keepalive 日志：`%LOCALAPPDATA%\HereIAm\devroom-tailscale-keepalive.log`
- 手机 Tailscale 开关有没有开着
- 防火墙：Windows Defender 第一次可能弹"是否允许 Node.js 通过网络"，选允许

**HTTPS 证书错误：**
- 不该出现。Tailscale 给的证书是它官方签的、有效的。如果出现，可能是 `tailscale serve` 启动姿势不对，重跑第 2 步。

**URL 变了：**
- Tailscale 设备名不会变。除非你在 Tailscale 控制台手动改了机器名。

**国内访问慢：**
- Tailscale 国内连接有时候要等几秒打洞。一般 5-10 秒内能通。如果超过 30 秒，先确认 keepalive 任务在跑，再重启 Tailscale 服务。

---

## 安全要点

- **不要把 `tailscale serve` 暴露成 funnel**（那是给整个公网用的）。当前用的是 tailnet 内部 https，只有你登录了同账号的设备能访问。
- Bridge 自己不存任何 token，认证靠 Tailscale 身份层。
- 手机和电脑都在你的 Tailscale 账号下，丢手机马上去 <https://login.tailscale.com/admin/machines> 把那台设备 remove 掉。

---

## 下一步

Tailscale 通了之后，建议 dogfood 2-3 天，真用 Dev Room 做点小事（看代码、问问题、做小修改）。攒一些真实 run 数据之后再做 Phase 3 的 Daily Coding Log，coding 卡片才有内容可生成。
