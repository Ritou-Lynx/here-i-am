# RELAY 2026-11-01：V1a.1 本机更新林埃英文语音服务

PR #77（Tailscale 身份鉴权）已合并，但合并前没跑本机更新的脚本轮。本 PR 只用来承载那一轮。

- 第 1 轮（write，需用户 👍）：`tools/relay_scripts/linai_tts/install-v1a1.ps1`，钉住 `install_linai_tts.ps1` 的哈希后运行。幂等，会更新 app 副本、把本机 Tailscale 登录账号写入 config 的 `tailscale_logins`、重启服务、检查本机与 tailnet health。
- 通过标准：`tailscale-login` ok，`local-health` 中 model_loaded 为 true，`tailnet-health` ok 为 true（`caller_authorized` 也应为 true）。
- 输出不含路径、token、域名或账号。

本 PR 没有代码改动，验收后合并或关闭都行。
