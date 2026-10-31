# relay_scripts

Agent Relay 脚本轮（`relay:to-runner`）运行的 Windows PowerShell 5.1 脚本放这里，规则见 [PROTOCOL.md](../agent_relay/PROTOCOL.md)“脚本轮”。

- 每个脚本按主题放子目录，评论里用 SHA256 固定版本，改了脚本就要发新评论。
- 第一行写 `[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)`，否则 PS5.1 管道输出按本机代码页编码，中文回帖会乱码。
- stdout 每行一个 JSON 对象，便于云端解析；不打印令牌、本机绝对路径或真实数据。
- 产物写到 worktree 外；留在 worktree 里的文件会被 watcher 丢弃。
- 仓库公开：脚本里不写 SID、本机路径、域名或凭据，需要时运行时读取本机配置。
