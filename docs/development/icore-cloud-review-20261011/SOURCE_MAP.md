# 源码地图与脱敏说明

## 必须优先检查的执行链

所有链接是文本快照，不是可部署源码包。行号保留原文的换行结构；脱敏替换可能改变列位置。

| 内容 | 文件 |
|---|---|
| 最新控制器 | [r08 continuous-activation](snapshot/r08/tools/i_core/release_schema6/lifecycle/continuous-activation.ps1.txt) |
| 失败候选控制器 | [r07 continuous-activation](snapshot/r07/continuous-activation.ps1.txt) |
| 入口与通用 catch | [entry](snapshot/r08/tools/i_core/release_schema6/lifecycle/continuous-activation-entry.ps1.txt) |
| 私有读租约 | [evidence-native](snapshot/r08/tools/i_core/release_schema6/lifecycle/evidence-native.ps1.txt) |
| 隐藏子进程及固定映像 | [evidence-pinned-launch](snapshot/r08/tools/i_core/release_schema6/lifecycle/evidence-pinned-launch.ps1.txt) |
| 文件父目录/ACL/排他创建 | [owned_artifacts](snapshot/r08/tools/i_core/maintenance/owned_artifacts.ps1.txt) |
| SID 规范化、任务注册 | [register_task_primitives](snapshot/r08/tools/i_core/maintenance/register_task_primitives.ps1.txt) |
| 任务安全策略 | [task_security_policy](snapshot/r08/tools/i_core/maintenance/task_security_policy.ps1.txt) |
| 包切换/实际启动 | [start_schema6](snapshot/r08/tools/i_core/release_schema6/lifecycle/start_schema6.ps1.txt) |
| 配置派生 | [derive r09](snapshot/preparation/configuration-derive-r09.ps1.txt)、[functions r06](snapshot/preparation/configuration-functions-r06.ps1.txt) |
| 最终绑定 | [task-binding-finalize r07](snapshot/preparation/task-binding-finalize-r07.ps1.txt) |
| 批准材料生成器 | [materializer](snapshot/preparation/materialize-repaired-r06-approval-r01.ps1.txt) |
| 待批准启动包装器 | [launcher](snapshot/preparation/invoke-repaired-r06-production-r01.ps1.txt) |
| 9 项 SID 回归原测试 | [focused regression](snapshot/preparation/focused-regression-r01.ps1.txt) |
| 只读至 321 行适配器 | [readonly preflight](snapshot/preparation/readonly-task-preflight-after-fix-r01.ps1.txt) |

## 控制器阶段索引（原始行号，仅作导航，请核对快照）

- 63–109：读租约、pins、函数、真实配置引用；101：额外基线文件；102–104：备份配置 ACL。
- 110–112：新 attempt 不存在、创建目录、记录消费。
- 261–266：派生预期任务定义和材料。
- 297–321：COM 只读前置；314：本次身份修复。
- 322：真实入口进程自身份，不在只读适配器覆盖内。
- 323–352：源码/包清单、锁与前置、旧 marker/head、pending capture。
- 365–383：switch control、切换目录、start_schema6 子进程、切换后证明。
- 391 以后：再次捕获与任务更新；419 附近 Enable；431–437 claim / Run 消费 / Run。
- 447–458：P3/P4 与完成；459 起：通用 activation_failed 和失败收容。

## 快照范围与对比方式

snapshot/r08 包含冻结 r08 中全部 82 个 .ps1/.mjs/.cs 程序文件；另外包含 1 个 r07 控制器和 10 个准备/诊断脚本，共 93 份。不包含 node.exe、manifest.json、端点 JSON、README 及生产配置。manifest 与端点配置的存在被明确记录，不能假装省略后仍是完整可运行包。

检查 r07/r08 控制器应只有 SID 比较逻辑修正。准备脚本没有与旧版本完整成对收录，勿将其视为全部演变历史。仓库顶层维护代码提供已提交基线；snapshot 提供本机冻结候选，两者可能不同。第三方依赖、实际 COM/Windows 行为、真实 ACL 与配置值不能仅靠快照证明。

## 脱敏与校验

[source-inventory.json](source-inventory.json) 为每份文本记录原始字节 SHA256、公开副本 SHA256、字节数及是否变换。原始 SHA 只能作后续本机对照，不能证明云端拥有原文件。

变换：本机工作目录改为 C:\ReviewFixture 下的合成目录；用户目录/账户/主机名改为 REVIEW_USER/REVIEW_HOST；个人域 SID 改为合成 SID；真实服务域名改为 mcp.example.invalid；旧/新 attempt ID 分别改为以 1/2 结尾的合成 GUID；统一 UTF-8 无 BOM / LF 文本并去除行尾空白；目录级 .gitattributes 固定快照字节，避免 checkout 换行转换。Windows 系统路径、SYSTEM SID、COM 接口 GUID 和程序逻辑保持。

没有重新计算脚本内部生产哈希。反复出现的哈希常量是待审逻辑的一部分，但经过脱敏的副本不会满足那些原始 pins。源码中的 task 名称/日期/候选版本用于工程关联，不携带运行授权。

不上传：原始四份配置、派生配置、真实数据库、密钥/令牌、签名、个人生活资料、完整对话、原始任务 XML/SDDL、stdout/stderr、设备回执、二进制、私有清单的原始路径。运行事实来自人工选取字段的摘要，不是把原始 JSON 简单改名上传。

## ChatGPT MCP 兼容源码（已公开的精确提交）

维护基线未包含全部兼容分支改动。可阅读 [f90058f2 的 tools/i_remote_mcp](https://github.com/Ritou-Lynx/here-i-am/tree/f90058f21049f514f8ab2af407227aee02e2f259/tools/i_remote_mcp)；重点是 server.mjs、oauth.mjs、mcp.mjs、chatgpt_candidate.mjs 及对应测试。相对 PR #20 合并基线，这一目录有 9 个文件变化（1046 行新增、12 行删除）。它是源码参考，不是最新运行时已经接入的证明。
