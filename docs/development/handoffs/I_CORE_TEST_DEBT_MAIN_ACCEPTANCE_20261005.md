# i_core 42 项既有失败：主窗验收（2026-10-05）

## 结论

源码修复候选通过主窗验收；用户“请继续”承接先集成42修复、再组合W1的方案，已授权本候选提交、PR及普通合入 v3-lab。合入状态以后续PR回执为准，未授权运行服务切换。原清单是 41 个叶子失败加 1 个父测试汇总，共 42 项；本次没有增加 skip、屏蔽测试或降低原安全断言。

- 原修复副本：f605d501 基线、16 个既有递归 i_core 测试文件。worker 的完整默认/串行日志与源码 SHA 已核验；主窗独立默认复跑 **261 项：260 通过、0 失败、1 原有跳过**。
- 当前主线移植：v3-lab@6508f1ab5ac2ed57155e95047942875f14fa0c47，分支 codex/core42-acceptance-20261005。仅移植 tools/i_core 最小补丁及三份新合成夹具；未复制 worker 的 DEVLOG / 项目状态。W0 两项 frontend 权限负例完整保留。
- 主窗同 16 文件默认复跑 **263 项：262 通过、0 失败、1 原有跳过**。原有跳过是 Windows 大小写不区分文件系统条件，不是此次修复新增。
- [机器回执](I_CORE_TEST_DEBT_MAIN_ACCEPTANCE_20261005.json)分别绑定当前 17 处工作区实际字节、Git暂存blob和日志 SHA；三处测试文件仅CRLF/LF不同；原逐项判断/失败清单见[worker 交接](I_CORE_TEST_DEBT_20261005.md)、[原验证回执](I_CORE_TEST_DEBT_VALIDATION_20261005.json)。

## 修复与有限证据

不存在于公开 sanitized Git 谱系的旧 bbb8025d 不能伪装成可运行历史源码。M3 使用公开、静态 schema4 八表及代表性合成行；旧入口使用受限合成 reader（允许自有临时库热日志恢复），old_constructor_called=false。runtime_pin 夹具使用真实临时 Git 提交和精确 blob，但明确为 synthetic-public-schema4-test-only；生产 pin 对缺失旧提交/来源继续拒绝。

R3 固定六份源码的 SHA 不变，以相同字节的公开 f605d501 Git blob 重新绑定；生产 launcher/hash/manifest 守卫未改为从当前源码自证。实际修复了 PowerShell 7 模块路径传入 PowerShell 5.1 引发的模块类型冲突；控制文件采用写完关闭后原子发布，避免读取半写文件。

其余修复限定测试隔离、当前契约字段、HTTP 连接复用和冷启动预算。原数据路径、WAL 只读预检、错误拒绝、受控结束、Job 成员/孙进程/guardian 退出及 125 秒连续场景等断言仍执行。主窗复跑未读取真实数据库、替换服务或安装手机。

## 下一步

本候选先按授权提交/建 PR 并集成 42 项修复；W1 后续在其上重做组合验收。W1 的新静态 import 需加入 test_fixtures/schema4/runtime_pin_lab.mjs 的合成包库存与对应 builder/launcher 夹具变换：domain_http.mjs、domain_store.mjs、domain_schema.mjs；只改合成夹具，保留生产 historical pin。当前回执不声称 W1 与该候选已联合通过。
