# HUB Go-live P3：规划助手切 i_core（2026-10-07）

## 状态与边界

- 基线：`0a24cac2b7db812f34fb845325e27b77d16139dd`
- 分支：`codex/hub-golive-src-20261007`
- 谱系：`Ritou-Lynx/here-i-am`
- 本工作包只修改 `tools/life_planner/**` 和本交接；未修改 `tools/i_remote_mcp`、`tools/i_core`、schema、maintenance、生命周期或现场清单。
- 未读取真实配置、数据或凭据；未创建真实 Codex 任务、未注册后台任务、未启用生产监视器；未 commit、stage 或 push。
- P3 依赖 W2/W3 已提供的领域协议与 scoped planner MCP。P1 可独立上线，P1 不依赖 P3 的源码、监视器或 Gate。

## 交付

### 规划助手存储边界

`PLANNER_AGENTS.md` 已把结构化规划唯一权威改为 i_core：

- captures：`capture_list`、`capture_ack`；
- plan_items：`plan_list`、`plan_upsert`、`plan_set_status`；
- plan_weeks：`week_get`、`week_set`；
- plan_days：`day_get`、`day_set`。

保留既有分诊、块型、周配额、优先级权重、欠账只滚一周、今日队列八成容量、待拍板、事件驱动与重排规则。思源规划库和本机 `plan.json` 不再是依赖；`today.md`、`week.md`、`study-quota.md` 仅为 Core 接受后生成的可重建投影；`areas.md` 仅为首次建立周记录的人类核对模板。

捕获处理顺序固定为：读 pending revision → 先写 planning domains → Core 接受 → `capture_ack`。未知结果原样重试，不换 op_id、不自动改 base、不升级 actor。

### captures feed 监视器

新增 `capture_sync.mjs`：

- 使用单独的 `captures:read` / `captures:ack` scoped token，直接调用已存在的领域 `snapshot`、`changes`、`records`、`ack` 接口；规划数据仍只走 MCP 工具；
- 默认未启用，配置必须显式 `enabled: true`，Core URL 仅允许 loopback，令牌只从环境变量读取；
- 首次 snapshot 或 resync 后校验分页与集合 digest、snapshot 身份及 binding，再保存 opaque cursor；之后轮询 changes；state 持久保存 committed/seen cursor、pending ID、处理阶段和重试时间；
- 第一条 pending capture 后等待 3 分钟合批；成功唤起间隔至少 10 分钟；23:30–07:00 按 `Asia/Shanghai` 静默；同实例 tick 串行，CLI 独占锁防止两个监视器共用 state；
- Codex 必须用绝对可执行文件和 `--` 前恰好一个匹配的显式模型参数，以 `shell: false` 有界执行；生产运行当前只支持 Windows。锁文件记录子进程 PID；超时/中断时只有 `taskkill /T /F` 明确退出 0 才解除子进程锁，非零退出、启动错误或超时会把 state 与 lock 持久标为 `codex_tree_reap_unverified`，阻止后续批次和新实例接管；
- Codex 退出 0 后逐条读取 pending capture，只有当前可见 record 的 planner disposition 已对当前 text revision 终态化，或 Core 明确返回有效 410 tombstone，才 ack feed cursor；401 / 403 / 404 保留待处理，不以不可见代替删除证据；
- Core、Codex、验证和 ack 失败均保留状态，按 2 秒起、5 分钟封顶、±20% jitter 重试；成功 Codex 后 ack 失败不会重复启动 Codex；cursor resync 合并保留旧 pending，权限绑定变化则持久阻塞并要求显式重绑；
- 日志只记时间、数量、阶段、退出码和 allowlist 错误码，未知 Core 错误码不原样写入；不写原文、记录 ID 或令牌。

README 只给人工上线步骤，没有安装脚本或自启注册动作。

### dot 与模板

- `DOT_PLAN_RULES.md` 把 `today.md` 定义为 `plan_days` 投影，把本机回执定义为待桥接输入，不能声称已经写入规划权威。
- `areas.md` 去掉思源笔记本/数据库初始化项，明确 Core 冲突时以 Core 为准。

## 验证

使用 `D:\Nodejs\node.exe` v24.14.1：

```text
node --check tools/life_planner/capture_sync.mjs
node --test tools/life_planner/capture_sync.test.mjs
node --test tools/i_core/domain_http.test.mjs
```

结果：监视器 5/5 通过；既有领域 HTTP 契约 20/20 通过（Node 报 SQLite experimental warning，不影响退出码）。

离线测试启动临时假 Core HTTP 服务和真正子进程形式的假 Codex，覆盖：

1. pending capture 等待 3 分钟合批；
2. 假 Codex 标记 planner disposition 后，监视器复核再 ack，并持久化 cursor；
3. 日志不含假捕获原文；
4. 假 Codex 首次失败后保存 backoff，新监视器实例读取 state，跨重启第二次成功；
5. 完整批次在 23:30–07:00 不启动进程，到 07:00 再运行；
6. 上次成功后的 10 分钟内返回限频，不启动第二个进程；另覆盖跨午夜静默时间判定。

新增的 `capture_sync.test.mjs` 需由主 Agent 接入项目 CI 入口；本工作包只运行了显式专项文件。

### 返修验证（第二轮）

首轮 5/5 记录保留作为当时边界。收紧删除证据、严格响应形状、snapshot digest / binding、丢失不可见 pending 的 resync 保护、进程锁竞态、Windows 进程树超时回收、上海时区、CLI 退出码与错误 allowlist 后，专项组曾扩展为 21 项并全部通过。最终二审又补上 `taskkill` 非零退出/启动错误/超时的持久失败关闭，以及 `--` 前模型参数唯一性测试；最终计数见本交接的后续验证记录。其中一项使用真实 `DomainStore` + `domain_http` 内存合成 HTTP 链路，验证 snapshot / cursor / binding / digest、capture disposition 和 consumer ack；其余使用假 Core / 假 Codex，不读真实配置与数据。非 Windows 环境只用于协议和直接子进程的合成测试，不代表生产支持。

最终阻断修复后再次执行 `node --check tools/life_planner/capture_sync.mjs` 与显式专项 `node --test tools/life_planner/capture_sync.test.mjs`：语法检查通过，专项 **24/24 通过、0 失败**。首次复跑因合成配置仅给 Windows `taskkill` 100ms 宽限，使两项本应验证成功回收的测试正确进入新加的失败关闭状态；把该合成宽限调整为 2 秒后复跑全绿。生产默认仍为 5 秒，没有因测试调整而缩短。

## 限制与协调项

主控最终又补充“登记过的直接子进程已死，也不能证明其后代退出”的保守恢复规则。只要陈旧锁仍有 `child_pid`，便要求受控人工核对，不自动归档接管。最终监视器专项为 **25/25 通过，0 失败、0 跳过**；已加入项目 CI。

1. **完成/放弃授权链缺口。** `plan_set_status` 强制 `authorization_ref`，但 `capture_list` 返回记录不含可转交的受信授权引用。P3 没有改共享接口或绕过授权；此类捕获当前只能写入 `plan_days.pending_decisions`，等待受信入口确认。主 Agent 需在 i_remote_mcp / Core 所有者处决定是否增加安全的授权转交机制。
2. **dot 回执桥接未在本范围实现。** 本机 `inbox/*.md` 不是权威；需要另一个受信桥接层把回执提交为 Core capture。P3 不直接提升本机文件内容。
3. **真实一天 Gate 未执行。** W8 的真实环境运行一天、生产启用和登录自启均保留为部署 Gate，需要 W2/W3 已上线、用户授权、合成/隔离点验通过后另行执行。
4. **历史 WI 迁移未执行。** 只允许使用 W2 审定导入脚本，默认 dry-run；本工作包未读取或搬运真实 `plan.json`、周账、今日单。
5. **锁恢复 guard 故障时保守失败。** 若进程在恢复陈旧锁时再次异常退出，残留 guard 不会被自动删除。部署者必须先人工确认原监视器和其 Codex 子进程均已退出，再按受控运维步骤处理，避免错误接管。
6. **进程树回收不确定时持久阻断。** `taskkill /T /F` 未明确退出 0 时，监视器不会把父进程退出当成整树回收成功；state 与 lock 保留 `codex_tree_reap_unverified`。部署者必须确认记录 PID 的完整后代均已退出，再人工归档阻断锁并显式重建 state。当前生产边界仅为 Windows；Unix/macOS 路径只用于合成测试。
