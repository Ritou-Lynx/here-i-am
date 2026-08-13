# i core（私人电脑最小核心）

这是跨设备 MVP 的第一版权威服务。当前只负责：

- 设备配对与令牌认证；
- 用户聊天消息幂等提交；
- 持久化、按序的 change feed；
- 每台设备的 cursor 确认；
- 核心健康与协议版本检查。

它还不会生成林埃回复，也不会同步 Memory V3 或媒体原件。现阶段的目标是先验证两台客户端共享一条不会重复的消息时间线。

## 本机启动

在 PowerShell 中临时设置一次性配对码并启动。配对成功后该码的哈希会写入核心数据库并立即失效，电脑重启也不会恢复；要添加下一台设备，需要由核心所有者生成一个从未使用过的新配对码并重启服务：

```powershell
$env:I_CORE_PAIRING_CODE='请换成临时配对码'
node tools/i_core/i_core_server.mjs
```

默认监听 `127.0.0.1:47841`，数据库保存在被 Git 忽略的 `tools/i_core/.state/i-core.sqlite`。不要把监听地址改成 `0.0.0.0` 直接暴露到局域网或互联网；手机接入时使用 Tailscale Serve 提供 HTTPS。

可选环境变量：

- `I_CORE_DATABASE`：SQLite 文件路径；
- `I_CORE_HOST` / `I_CORE_PORT`：监听地址与端口；
- `I_CORE_CERT` / `I_CORE_KEY`：直接启用 HTTPS 时的证书和私钥。

## 验证

```powershell
node --test tools/i_core/i_core_server.test.mjs
```

测试覆盖双设备读取、重复提交、冲突回滚、身份边界、协议版本和服务重启后的持久性。
