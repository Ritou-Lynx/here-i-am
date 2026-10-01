# W2 来源与证据

- task：`01a09504-2fbf-7963-82a5-d9940f635d70`；W0：`01a0917d-17fa-7bf3-a282-fd4c551d93b2`；host：local。
- Worktree：`C:/Users/ExampleUser/.codex/worktrees/4dd2/memex`；分支 `codex/mda2-w2-20260912`；起步干净 detached HEAD，随后只在此新树创建指定分支。
- 基线与最终 HEAD：`1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`；无 stage/commit；tracked/index diff 均空。
- 指导输入：当前 `D:/memex/AGENTS.md` 与协作协议只读；第三批计划和第二批裁决从 `832e/memex/docs/development/activity/mda2/` 的未提交原件读取，没有复制主目录修改。

## C2/W1 只读输入

接受契约为 `C2-CR01-R2-20260912`，完整 C2 patch SHA `124cd8039cce1fcd85213492f73d3a9aea00db49675dccd8346be556b87f17cb`（W0 接受记录）。以下内容本任务实际读取并复核指纹：

| 输入 | SHA-256 |
|---|---|
| `4b45/memex/docs/development/activity/mda2/contract/CR-01.md` | `3862c414ef13517cb275662316e5117451c0122b1b20766341d6d3e15a73f36a` |
| 同目录 `INTERFACES_AND_ACCEPTANCE.md` | `faa5bf716d60374288aba97068ea7598d6a78cd2d4561114b86b9007ea1159b6` |
| `4b45/memex/tools/mda2_contract_fixtures/reference_queue.mjs` | `a7c1ef3ca4e29a72c0514043ce898f54257c680421f0d8ea69a111ecead2d7ee` |
| `f48e/memex/tools/mda2_windows_probe/README.md` | `fe3cb060a66f3c38949eb6a92987b836ae927f29c6d051a2f46f27d1e93e2ee9` |
| 同目录 `synthetic_support.mjs` | `98cdf871e014a6f6f2cf9678b768dbf950a35ae8d7eae1b871c183c6a3369f89` |

W2 按 C2 状态/错误语义重新实现磁盘事务与进程协议，没有复制/改名内存 journal 交付。终态集合、never_sent/attempted_unknown、期限优先、原字节回放和保守冻结来自 C2；新增的 Windows guard、SQLite AES-GCM adapter、独立 broker 的预留/提交/proof 验证及真实进程 fixture 都在 W2 新命名空间。W1 仅用于粗信号、配对和 scope 的只读参考；旧 W1/C2 树未修改。

## 实际执行输入

`SOURCE_MANIFEST.json` 列出 9 份本包可执行源（含两个 fixture、两个 PowerShell helper），以及实际 import 的 2 份只读 Core 源。未引入根依赖；复用 Node 自带 SQLite。最后整套执行期间的清单与完成后的逐文件 SHA 核对一致。

- Node：`D:/Nodejs/node.exe`，`v24.14.1`，SHA `58e74bf02fc5bbacc41dcb8bef089961cd5bddd37830b87784e4fc624d145d1f`。
- 全套：`node tools/mda2_windows_queue/fixtures/run_tests.mjs`，35 场景，exit 0，未设置 filter。
- `RESULT.json` SHA：`ed7c64d2efada2c251d32f2f3bd6bd50c12522b98d8be096bd5a523e400cf96a`。
- `SOURCE_MANIFEST.json` SHA：`34e287504b377ef12fda1ab9115601eb972b7efafb8c450279ff68ff357962cf`。
- 记录 208 个受控进程生命周期事件；正常 close 同时核对 SQLite close 和 guard exit 0。crash 场景记录实际子进程被终止的屏障/exit。最后所有 broker 正常退出，异常 broker 的旧 lineage 拒绝另有明确事实。
- 原生 Windows 年龄正例、原生年龄 helper 被终止、broker 被终止都是实际进程行为；TTL/raw 等号与跨 24h 边界使用显式合成年龄提供者，未让电脑经历真实 24h/休眠/重启。
- 本轮测试成功后 scratch 删除；另清理本任务此前 10 个自建失败/定位目录，最终 `.scratch` 不存在。只删除自建资源，不把文件删除说成 SSD 物理不可恢复。

沙箱曾对祖先原生句柄返回 Win32 5；限定测试通过现有自动审批在沙箱外执行。后续曾发现 Windows PowerShell 继承 PowerShell 7 的 PSModulePath 导致模块命令不可用，现 helper 环境只保留最小 Windows 路径/临时目录。未放松 ACL/canonical 检查。

## W0 早审 P2 闭环

W0 指出 worker 可以把 projection rawDeadline/digest 与 capture 脱钩。现 broker 对首次分配自行规范化签名观测并核对 sequence/digest/origin/rawDeadline/TTL；后续 prepare 保持不可变字段与合法状态转移，不接受无 capture 新行、提前移除、已解决/退休行复活。原始回执有独立 proof，真实 transport 只能在最终 fence/期限检查之后执行，同一个 attempt 最多派送一次。

fixture 直接调用 broker prepare 的 14 个伪造负例均拒绝；这些是 broker 层攻击输入，不是只调用正常 queue API 的自洽测试。W0 最终审查尚未发生，此处不代替接受裁决。
