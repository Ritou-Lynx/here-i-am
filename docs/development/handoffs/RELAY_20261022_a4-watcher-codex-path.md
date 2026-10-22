<!-- relay:contract v1 -->
# A4 合同：watcher 自己解析 codex 路径，headless 启动写进安装脚本

## 目标
来自 D1b 期间的 watcher 故障（见 `RELAY_20261012_core-release-r1.md` 第 323 行）：

- 计划任务把 codex 所在目录固化进 PATH。codex 目录名随版本变化，更新后 watcher 报 `spawn codex ENOENT`，而且这一轮被记为 failed 并回帖，白白消耗一轮。
- 本机现在靠一个仓库外的 VBS 启动器修 PATH，再用 `conhost --headless` 包装避免闪窗。这两样都不在仓库里，`install_relay_task.ps1` 注册出来的任务和现役任务不一致。

改为：watcher 每轮自己解析 codex 可执行文件；解析失败不领取评论、不计轮数；安装脚本直接注册 headless 任务，不再需要 VBS。

## 完成标准
**解析 codex：`relay_watcher.mjs`**
- [ ] 配置新增两个可选字段（`validateConfig` 校验，`relay.config.example.json` 补示例，示例中用占位路径）：
  - `codexPath`：codex 可执行文件的绝对路径。
  - `codexSearch`：`{ "root": <绝对目录>, "dirPattern": <锚定正则字符串>, "relativeExe": <相对路径> }`。在 `root` 下列出名字匹配 `dirPattern` 的目录（不递归），按名字中的数字段做版本序降序，取第一个 `root/<dir>/<relativeExe>` 存在且是普通文件的。
- [ ] 解析顺序：`codexSearch` → `codexPath` → PATH 上的 `codex`（保持现有行为）。前两者找到的结果必须是绝对路径、普通文件、不是符号链接或目录联接、不在 `repoPath` 或 `worktreeRoot` 内；Windows 上扩展名必须是 `.exe`（`shell:false` 无法直接运行 `.cmd`）。不满足即视为未找到，不回退到下一种来源以外的位置。
- [ ] 解析在领取评论之前完成（早于加 👀 反应和写 `in_progress` 回执）。都找不到时：不加反应、不写回执、不回帖，日志写一行 `codex_not_found`（不含路径），`runOnce` 返回 `{ status: 'codex-not-found' }`，`--once` 退出码非零。下一次轮询照常重试。
- [ ] 找到后用解析出的绝对路径 spawn（仍是 `shell:false`），并在每轮 `result.json` 中记录 `codexSource`（`search`/`path`/`PATH`）和 codex 所在目录名（只写目录名，不写完整路径）。`--dry-run` 预览中的命令显示解析结果。
- [ ] 除上述外，轮次流程、锁、超时清理、提交与推送规则都不变。

**安装脚本：`install_relay_task.ps1`**
- [ ] 计划任务 Action 改为 `%SystemRoot%\System32\conhost.exe --headless <powershell.exe> -NoProfile -NonInteractive -EncodedCommand ...`。conhost 不存在时报错退出，不回退到会闪窗的方式。
- [ ] 不再把 codex 目录写进任务 PATH，也不再要求注册时能找到 codex。`-CodexPath` 参数移除；如果传入则报错并提示改用配置里的 `codexPath`/`codexSearch`。node、gh、git 的处理不变。
- [ ] 新增 `-ShowAction`：只打印将要注册的 Execute 和解码后的命令，不注册、不改任何东西。
- [ ] 同名任务已存在时仍然拒绝覆盖；`-Remove`、`-WhatIf` 行为不变。
- [ ] README 的安装、更新段落改为新方式，写明从旧 VBS 方式迁移的步骤（见“需要真人的部分”），删除“Codex 更新后需重新注册”的说明。

**测试（离线，注入 `run` 和临时目录）**
- [ ] `relay_watcher.test.mjs` 新增：`codexSearch` 在多个版本目录中选最高版本；最高版本缺 exe 时选下一个；`codexPath` 生效；符号链接、位于 `worktreeRoot` 内、非 `.exe`（模拟 win32）都被拒；全部找不到时返回 `codex-not-found`，且没有任何 `gh api` 反应、回帖调用，state 中该评论仍为待处理；spawn 使用的是解析出的绝对路径；`validateConfig` 拒绝非绝对 `root`、非法正则。
- [ ] 现有 `relay_watcher.test.mjs`、`relay_core.test.mjs` 全部通过，除把断言中的 `cmd === 'codex'` 放宽为“解析出的 codex”外不改已有断言。

## 允许修改的路径
- `tools/agent_relay/relay_watcher.mjs`、`relay_watcher.test.mjs`
- `tools/agent_relay/install_relay_task.ps1`
- `tools/agent_relay/relay.config.example.json`、`README.md`
- `docs/development/handoffs/RELAY_20261022_a4-watcher-codex-path.md`（只由 Claude 改）

## 不做 / 边界
- 不改 relay 协议（评论标记、轮数上限、作者与分支白名单、沙箱参数限制）。
- 本轮不动本机现役计划任务、VBS 启动器和 `.state/config.json`（正在运行本轮的就是它）。只读核对可以，结论写 SUMMARY，不写本机绝对路径（用 `<CODEX_ROOT>` 之类的占位）。
- 不碰 i_core 和生产。
- 止损：同一测试名或同一错误码在连续两个提交上失败，即判为 blocked。最多 3 轮。

## 验证命令
- `node --test tools/agent_relay/relay_watcher.test.mjs tools/agent_relay/relay_core.test.mjs`
- `powershell -NoProfile -File tools/agent_relay/install_relay_task.ps1 -ShowAction`（本机，只读；SUMMARY 中把路径替换成占位）
- `git status --short`（只出现允许修改的路径）
- Claude 在云端复跑 Node 测试。

## 需要真人的部分
- 合并由用户进行。
- 合并后迁移本机任务（手动粘贴给 Codex，粘贴即同意）：主仓库拉到最新 v3-lab；在 `.state/config.json` 填 `codexSearch`；`-Remove` 旧任务后用新脚本注册；手动触发一次，确认 `task-last.log` 为“无待处理”且 LastTaskResult 为 0；确认后删除旧 VBS 启动器。
