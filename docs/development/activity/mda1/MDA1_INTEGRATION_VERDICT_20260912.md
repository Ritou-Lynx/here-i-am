# MDA-1 合并方案裁决与隔离候选验收

> 2026-09-12；唯一验收责任任务：`01a0917d-17fa-7bf3-a282-fd4c551d93b2`。
> 来源任务：`01a04839-f159-71f1-8fd3-4e3b83ef9178`。
> 裁决：**修订后采用；隔离候选组合验收通过；未提交、未更新 v3-lab、未部署。**

> 上述为初次候选验收快照。后续已完成固定旧 v4 运行包的获准切换，并由 Lynx 确认原手机聊天可续用；MDA schema 5 尚未部署。共享文档融合与下一次本地提交范围见 [主线协调记录](MDA1_MAINLINE_COORDINATION_20260912.md)，它是当前入口；本报告保留当时的验证与未执行边界。

## 1. 执行方式

采用 [原方案](MDA1_V3_LAB_INTEGRATION_PLAN_20260912.md) 的无提交三方合并。
应用创建的工作树已是目标精确提交且 clean，因此直接在该独立工作树建立
`codex/mda1-v3-integration-20260912`，无须再复制一份工作树。没有 pull。

| 项目 | 精确输入/状态 |
|---|---|
| 目标 | `bbb8025d99fc0acaa846d58b4e5a94cef90f8756` |
| 来源 | `44268fa91238bfde50363a1207120faee0a9f650` |
| 共同祖先 | `2edaf17a3f8bb733e6ac6f54024941267d7f32a4` |
| 分叉 | 目标独有 26、来源独有 55 提交；相对祖先改动路径分别 64/71，交集 19 |
| 隔离分支 HEAD | 仍为目标提交；无提交 merge 的第二父项固定为来源提交 |
| 候选标识 | 独立索引内容树、逐路径 blob 映射及完整 patch 指纹见候选清单；**不能把分支 tip 当已完成的合并提交** |

完整候选清单和 patch 位于本工作树 `tmp/mda1-integration-20260912/`，不是主目录
索引，也不是共享运行配置。`candidate-manifest.json` 绑定最终 tree、父项、路径
来源、验证文件和 `MDA1_INTEGRATION_CANDIDATE.patch` 的 SHA-256；它在候选之外
生成，避免报告自引用指纹。该 patch 可供复核，不能直接应用到当前脏主目录。

## 2. 必要修订与四项冲突

| 路径 | 采用内容与理由 |
|---|---|
| `tools/i_core/i_core_server.mjs` | 逐块保留 activity import、独立认证、结构化错误、启动激活与 timer；保留邮件授权，关闭统一走 `closeResources()`，尝试 server/自有 relay/store 全部清理并传播首个错误；显式外部 relay 不归本实例关闭；保留 graceful shutdown。最终 blob 与来源一致，系语义复核结果。 |
| `DEVLOG.md` | 保留双方历史条目，按日期融合冲突段，再追加本轮集成记录；旧候选 Gate 与本轮测试分开。 |
| `I_PROJECT_STATE.md` | 汇合来源 MDA-1 / Gate 1A-0 通过记录、主线 COROS 记录，并只读核对主目录 P4/P5/P6 新事实；不纳入 P6 未提交代码。 |
| `PRODUCT_ROADMAP.md` | 保留 Gate 1A-0 合同依赖与隔离例外；P4、限定 P5 已过、P6 未过；旧 R19/R20 待验文字明确标成历史，MDA-2 未启动。 |

邮件 `86c7394f` 与 `455be35e` 的相关生产文件逐路径 blob 相同，不能把来源的
55 个提交都称为 MDA 新功能。邮件实现保持主线版本；不另行重复移植邮件提交。
Gate 1A-0 的 ADR、fixture/harness 和固定 fixture 字节的窄 `.gitattributes`
全部保留，未纳入 Gate 1A-1 的生产实现。

另有三项收敛：

- 常驻 launcher 清除 `I_CORE_ACTIVITY_ADMIN_SECRET`；实际子进程合成测试先证明
  去掉 guard 会继承合成值，再证明完整 launcher 会清除。非 Windows 显式跳过
  这个 PowerShell 行为测试，静态测试照常；子进程有 20 秒上限并隐藏窗口。
- 专题 Roadmap 保留来源的 MDA 已完成/1 天保留协议；`REAL_DEVICE_GATE_RECORD`
  保留来源 structured replay 契约，并融入主目录 C-12/C-13 与已提交的 9 月 10 日
  COROS 当前哈希 C-14 记录，不用旧红灯覆盖新通过，也不重跑设备。
- iCore README 明确 schema 5、休眠仍迁移、备份 whole-Core 只读和运行入口随
  checkout 的限制；删除旧文案中可直接恢复的误导。

## 3. 运行影响裁决

只读精确查询证实：`HereIAm-iCore` 计划任务 **Running**；PowerShell launcher
指向主目录 `tools/i_core/start_i_core_service.ps1`，工作目录为主 checkout；
`127.0.0.1:47841` 有监听。launcher 按自身目录加载 server，因此主目录源码更新
会影响下一次启动。没有读取真实数据库、凭据值或完整含敏感参数的命令行。

低权限查询最初返回 `0x80041003 PermissionDenied`；其空输出不能证明任务或
监听不存在。最终结论来自授权提升后的成功精确查询。同名 Windows Service
不存在不影响上述登录计划任务实际存在。

**选择原方案第 6 节的第二分支：完成隔离候选，暂不更新运行 checkout。**
本轮不改变既有迁移/备份语义来掩盖部署成本，也不凭无 admin secret 宣称零写。
合成测试证实旧 v4 在未启用 activity 时仍迁移为 schema 5；七张原表的已有行、
identity、旧 token、chat/change/ACK 保持兼容；activity 不 claim 或激活，邮件
默认 503。正式备份仍只能离线验证，不能作为可写 Core 打开。

这证明代码兼容的限定行为，**不证明真实库已适合升级**：没有检查真实数据量、
现有 schema/身份/备份状态、性能或异常恢复。已知三项历史 P2 和备份激活限制
仍保留：删除后最小身份/receipt 非完整过期擦除；同步 deep audit 无性能 Gate；
listen 失败清理子状态可能过于乐观但整次失败；备份写激活和崩溃接管不支持。

## 4. 本轮新组合验证

运行时：Node `v24.14.1`、Dart `3.12.0`、Windows。所有测试仅使用合成库、
fake adapter/dispatcher、独立临时目录和随机 loopback 端口。Node 启动环境先
清除继承的 `I_CORE_*`；没有真实邮件发送、服务重启、设备安装、网络配置或 push。

| 验证 | 本轮结果 | 证据 |
|---|---|---|
| 完整 iCore Node 组合，串行文件执行 | **208 pass / 1 skip / 0 fail**，209 total | `node-tests.log`；包含 activity、mail、server、autostart、fixture/HTTP、human-harness 等全部 9 个测试文件，不重复相加 |
| 真实 loopback fixture CLI | **26/26，213 requests** | `http-runner.json`；closed case/field 全消费 |
| 三 probe CLI | 自动场景通过，`close=confirmed`、`cleanup=confirmed` | `three-probe.json` 的状态仍是 `passed_awaiting_human_acceptance`；它不新造一次真人通过 |
| Android 内存只读 reader | **15/15**；相关两文件 analyze 无问题 | `dart-reader-tests-direct.log`、`dart-reader-analyze.log` |
| Gate 1A-0 Dart 组合 | **27/27** | `dart-gate-tests.log` |
| Gate 1A-0 CLI | **202/202**，`allInvariantsHeld=true`，1,409,842 bytes | `gate1a0-report.json`，SHA-256 `7E868CDDD330AE92A112A23405D6156EC006D294773FE3BD8741DD83739D78A3`；与历史确定性报告逐字节指纹一致 |
| 精确旧 v4 → 默认休眠兼容 | **10 个聚合断言通过** | `legacy-compat.json` 与 `legacy_v4_default_dormant_compat.mjs`；旧 store blob `9e26379cca9716645d43bf2cf0344bfe23b06982` 从目标提交摘取 |
| 默认休眠但有到期 activity 的备份 | 既有完整组合测试通过 | `dormant formal backup rejects every row that a retention sweep would remove or rewrite`，不只验证空库 |
| lifecycle / ownership / failure | 原源码不变的组合回归通过 | 构造/listen 失败、owned relay 异常、外部 relay、graceful shutdown 与 retention timer 清理均在完整 Node 中 |
| diff / 范围 | 无冲突标记、diff check 通过，禁止源路径变更 0 | 独立审计与最终清单 |

Node 唯一 skip 是原有 Windows 大小写双文件能力条件，不是新跳过。
reader 测试首次被 SDK 锁权限与缺失 `package_graph.json` 阻断；补齐与来源相同
pubspec/lock 对应的缓存解析并使用获权 SDK 后通过，没有升级依赖、构建 APK 或
改写生成源。Gate CLI 首次因要求“已存在的空目录”拒绝，按契约创建后通过。

旧库验证脚本首版误将迁移后的 schema 5 与旧 schema 4 整体比较，并在断言失败
时遗漏 close，造成清理等待被误报为构造阻塞。主窗按真实合同修正断言、ACK
端点与 finally 清理后通过；**没有为迎合该错误测试修改生产 store**。

## 5. 独立复核与主目录保护

- `scope_audit`（Terra medium）复核每个来源路径均存在、关键源码 blob 与来源
  等价、邮件目标版本保持；相对目标无 Android/BLE/白板/workbench/P6 源差异。
  最后又独立运行修正版旧库兼容 runner，exit 0、10/10 聚合断言通过。
- `launcher_guard`（Terra medium）实现并验证两文件窄补丁；主窗检查实际 child
  环境正反例、清理范围、跨平台 skip 和 timeout。
- `runtime_audit`（Terra medium）提供源码拓扑与旧库 runner；主窗纠正了低权限
  空结果和初版兼容测试两处判断，并以成功查询和完整合成结果替代。
- 四个 worker 旧 runner 会话已结束；主窗提升权限按该唯一合成脚本精确查询，
  残留 Node 进程数为 0，没有终止真实 iCore 或其他进程。
- 主窗最终负责冲突、diff、关键断言、所有测试与文档验收。没有以 worker 的
  “通过”替代复核，也没有用 MDA 原候选历史测试证明当前组合。

前后核对目标仍为 `bbb8025d`，五份原有 staged 路径及所记录 index blob 全部
未变。本任务未写主目录。期间原主目录的 DEVLOG、Roadmap、项目状态、Goal 1
及方案文件有并行工作更新，故不宣称所有 working-tree 字节恒定；路径和指纹
差异已保存在 `main-protection-before.json` / `main-protection-after.json`。

## 6. 实际落主线条件与建议顺序

本轮原授权是方案验收、执行方式裁决与可逆候选准备，没有实际更新主线或真实
运行配置的授权。方案通过不能代替这两类决定。推荐保持当前候选，之后：

1. 对本候选明确授权本地提交与落主线；同时选择现役 iCore 的版本安排。
   **推荐先把现役 v4 运行入口与开发 checkout 固定隔离**，待其独立准备、合成
   验证和受控切换获准且完成后再落源码；若选择直接升级，则需另行明确真实库
   迁移/恢复与服务窗口。本轮没有实施或验证真实版本切换。
2. 获取共享索引和实际重叠文件的短暂独占窗口。只协调全局三文档、已有 staged
   状态及新增路径碰撞，不要求 P6 的无关功能全部完成，也不清空全仓。
3. 重新核对 v3-lab HEAD、五份 staged blob、重叠 working-tree 指纹，以及主目录
   新增方案/专题 Roadmap 的内容。如果 ref 前进，重算相交路径并只返修受影响
   部分；不能把本次旧基线候选直接套到新主线。
4. 由原拥有者收口实际重叠改动后，建立含新目标祖先的最终候选并复核三层状态，
   再用正常 Git 操作落主线。当前 dirty 文档会阻止直接快进；本报告不授权
   stash/reset/覆盖，不用单独 `update-ref` 绕过 checkout/index，也不预设临时
   索引重建作为默认办法。原工作树和既有 staged/unstaged 内容继续保留。
5. 落主线后再次核对目标、index、working-tree 和运行版本。源码回退与数据库
   回退分别处理，不能以 revert 承诺 schema/数据恢复。

## 7. 四种状态分别签字

| 状态 | 裁定 |
|---|---|
| 方案 | 修订后采用 |
| 隔离候选 | 限定组合验收通过；可复核无提交 patch/内容树已交付 |
| 主线 | 未更新；现役运行路径与重叠索引窗口尚未处理，合入尚无授权 |
| 真实运行/设备 | 未部署、未迁移、未重启、未安装；MDA-2 未启动 |

MDA-1 的历史用户接受继续有效；本次没有改变 activity 协议、恢复激活或保留期，
因此不要求重复同一合成三 probe 审看。运行升级及任何产品语义变化仍需自己的
明确授权与验证。
