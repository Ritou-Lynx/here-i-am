# Here I Am 开发副本契约

本目录为正式本地源码开发目录，基于净化谱系。林埃的英文名为小写 i。当前事实见 `docs/development/I_PROJECT_STATE.md`，迁移证据和边界见 `docs/development/SANITIZED_MIGRATION_20261001.md`。此处保存工程约束，不恢复私人历史中的关系/生活文本。

## 工作与协作

- 明确行动请求直接完成必要调查、修改和适当验证；保留并行改动。缺少信息时先推进独立工作，实质范围变化才澄清。
- 主控保持用户当前模型/effort，复杂跨模块工作由主控整合复核；可独立的明确工作并行委派，worker 默认不再派生。模型以实际工具可用性为准，不改全局配置。
- 简洁中文交付结果、验证与限制；不把测试、构建、安装、真人 Gate 合并成一个接受结论。

## Git 与数据

- 单一 GitHub 仓库为 `Ritou-Lynx/here-i-am`，正式日常集成分支为 `v3-lab`，任务分支使用 `codex/`。每台设备从净化公开谱系完整 clone，目录按设备选择；操作入口见 `docs/development/MULTI_DEVICE_GITHUB_WORKFLOW.md`。修改前核对分支、HEAD 与已有改动；不擅自切换或 pull。
- 私人旧谱系与净化谱系无共同祖先，只选择性迁入文件；不合并旧历史、force-push、reset、stash 或覆盖旧工作区。需要隔离时从明确精确基线建立 `codex/` 分支。
- 本地修改不等于 commit/push/发布授权（无人值守环境见下文常设授权）；保留 staged/unstaged 变更。真实数据库、凭据、签名、日志、设备回执与私人材料不进入源码提交。
- 本机迁移审计、验证输出和缓存默认忽略；130 个受控文件按 `.gitattributes` 保存精确字节。不要为了换行或样式整洁改写已验源。
- `upstream/main` 只读参考，不 rebase。首次 clone 使用 `scripts/install_git_hooks.ps1`；提交遵守既有状态检查，不全局禁用 hook。

## 工程与产品

- Flutter/Dart，MVVM + Provider；ViewModel 在 screen 创建，异步使用 Command 与密封 Result，依赖通过构造注入，service 注入 db。
- 新文件不 import MemexRouter；不扩大旧 PKM/Card Agent/自动聊天抓取链路。新增记忆进入 `lib/data/memory_v3/`，先读对应方案；普通聊天不自动成为 User-truth。
- 用户事实可编辑可删除，UI/检索只使用有效版本；Project Memory 与生活事实、关系记忆隔离。桌面白板编辑不自动提升为生活事实。
- 新 Drift 表与旧卡片不建外键；nullable fact_id 软引用。不要手改生成代码，只在源定义改变时生成。
- Chat 视觉采用 `docs/design/README.md` 的当前方案；白板工作先读其总纲，不恢复 archive 旧方向。
- 桌面白板工作台已于 2026-10-02 阶段性收尾并暂停开发；接续前先读 `docs/development/whiteboard-workstreams/WORKBENCH_PAUSE_20261002.md`，暂停期间只做保持 CI 绿所需的修复，不扩展白板功能。
- 工作台长任务生产路径为应用内 Ollama 纯文本网关，未配置 `HIA_TASK_OLLAMA_MODEL` 时 fail-closed；活动诊断默认关闭。减弹窗、生产准备、真实账户/数据操作按当前暂停状态执行，不自行启用。

## 验证与交接

- 逻辑改动做专项及必要相邻回归；文档核对链接与差异，纯文档不构建 App。通过后不无故扩大/重复检查。
- Dart 使用相关路径 analyze，Flutter 使用相关测试；既有 lint 需与新增问题分开，如实报告严格检查退出码。
- 每次 `flutter build` 前运行 `scripts/verify_critical_fixes.ps1`。Android 只使用 `hereIAmV3`、`com.memexlab.hereiam.v3`，安装优先专用脚本并保留真实手机安装授权。
- 验证机器优先、分四层：L1 单元/widget/生产组合场景与 L2 Windows 构建、hermetic 集成测试由 GitHub CI 每次 push 自动运行；L3 真实模型、真机、系统输入法由无人值守环境运行；L4 真人只判断口吻、手感、视觉等主观项，每个里程碑一次，看自动报告异步完成。详见 `docs/development/UNATTENDED_VERIFICATION.md`。
- 自动层对每个候选 SHA 重跑即完成精确绑定，证据用 CI 结果与产物，不手写 SHA/PID 长文。真人结论按改动是否触及其覆盖路径决定沿用或重看，沿用须在报告注明。自动场景失败不中止，跑完全部再汇总返修。旧 D 路径 native binding 只是历史 candidate-only 参考。
- 新增 Gate 先写成自动场景；computer use 只用于探索或系统集成点验，不作为回归验收手段。
- 实质成果更新 `DEVLOG.md` 顶部中文记录（不超过15行）和项目当前态；主窗统一落全局交接，worker 写各自 handoff。
- i 工具可用时，新会话调用 i_bootstrap；当前项目只用 i_get_project_state/i_recall_project，不切换项目参数。实质结果用真实 session/thread ID、稳定幂等键 closeout，默认 project_default，只写简洁结果、决定、未完和相对 artifacts，不写凭据或生活资料。

## 无人值守环境常设授权

- 范围：专用测试机、云端 agent 会话与 CI，且只用合成数据根。构建、启动/关闭/结束候选进程、新建与删除隔离数据、合成任务全生命周期与故障注入、提权与清理、失败后重建重跑、提交并推送 `codex/`/`claude/` 任务分支、发送报告，均已授权，不再逐次询问。
- 仍需询问：真实账户/数据库/手机数据，合入或推送 `v3-lab`，发布或安装到主力设备，生产启用，扩大模型工具或权限边界。
