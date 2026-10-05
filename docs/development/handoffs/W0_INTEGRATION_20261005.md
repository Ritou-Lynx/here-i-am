# W0 三分支本地整合交接（2026-10-05）

## 输入与结果

- 起点：获取时远端 v3-lab `f605d5017cbc0a8eb69983e00c25cd1bba08a0eb`，本地主分支未切换或合入。
- 按序普通合并：wonderful-carson `4a33f95d71c61d2d7c1de80984047ca2c80a8eef` → b3-writeback `445d665ee58e682e1dc41a96d90fb05d656bc10a` → festive-ride `053000db48bfd19700a2ab583842d50d7744c151`。
- 三条 merge 提交：ed7b1fa3、24c78812、9b23d511；完整源码候选 9b23d511fc28d588c3d1fe2c73014901e4824070。当前 codex/w0-integrate 后续仅增派发/交接文档。
- 冲突只在 DEVLOG.md / I_PROJECT_STATE.md，保留各工作线的记录。Core/memory/remote-MCP 源码与 b3-writeback 完全一致，学习导师模板与 wonderful-carson 一致；没有附加功能改动。
- [首批派发表](PERSONAL_DATA_HUB_DISPATCH_20261005.md)记录三个独立 worker 及后续释放规则；它们的改动不混入 W0。

## 验证

- Node 24.14.1 当前接口层 16 个测试文件：317 项，316 通过，1 跳过，0 失败；覆盖 Core、只读记忆、OAuth、MCP 和 B3 端到端合成路径。
- 三目录递归发现 23 个测试文件：368 项，325 通过，42 失败，1 跳过。失败涉及未迁入净化谱系的旧冻结基线 bbb8025d Core 源码，以及 Windows PowerShell Security 模块加载失败。相应历史迁移/运行包/fixture 目录与 v3-lab 没有差异；未修改历史断言或引入私人 Git 历史来消红。
- 总规划写的 node --test <目录> 在 Node 24 将目录当文件，先报 MODULE_NOT_FOUND；按实际测试文件清单执行后得到以上结果。
- 合并 marker 检查和 git diff --check 通过；既有 project-state 提交 hook 正常通过。
- 尚无本候选新 CI 证据；未本机构建 App。完整递归测试不能声称全绿。

## 运行一致性

- 本机 remote MCP 从既有 continuity-b0-b2 工作目录启动；其 HEAD 为 2a27f7d7，但含未提交源码修改，HEAD 不是运行内容证明。
- 候选与该目录磁盘源码有五处 hash 差异：i_core_server.mjs、i_core_store.mjs、i_memory_read.mjs、mcp.mjs、writeback.mjs。运行进程可能还持启动时的模块，本次只证明磁盘代码差异。
- 仅比对受控源码路径与哈希，未读取真实数据库、凭据、笔记或消息，未覆盖/重启/升级任何生产服务。运行一致性验收仍开放。

## 未完与授权

自动审批拒绝将规划、派发表和项目状态推送到 GitHub，要求用户明确本次对外上传范围。未绕过，尚未推送任务分支或建立 PR；现有成果保存在本地隔离分支。已向用户请求允许推送 codex/w0-integrate 到 Ritou-Lynx/here-i-am 并建草稿 PR。即使上传获准，仍等 CI、完整测试限制处理和运行差异处置；合入 v3-lab 须另行确认。W1 尚未开始。
