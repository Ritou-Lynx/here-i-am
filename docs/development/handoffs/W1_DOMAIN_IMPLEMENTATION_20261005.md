# W1 通用领域框架实现候选（2026-10-05）

> 当前组合交付优先：[最终组合主窗验收](W1_COMBINED_MAIN_ACCEPTANCE_20261005.md)。42修复已PR #7普通合入；组合31文件507过/0红/1原有跳，八处尾空行格式整理后领域专项111/111，最终13源码副本链通过。下方单包过程与旧R01保留历史边界。


## 结果与基线

用户已明确确认接口约定并授权实现。工作副本 `C:\HereIAm\w1-domain-contract-20261005`，分支 `codex/w1-domain-contract-20261005`，基线 `6508f1ab5ac2ed57155e95047942875f14fa0c47`；原候选保留未提交 diff；当前集成分支为 `codex/w1-integration-20261005`，基于42修复提交 `6895e86b25f6bfdd9a53e1a0155a2893da0158f3` 组合。W0 [PR #5](https://github.com/Ritou-Lynx/here-i-am/pull/5) 和 happy 整枝 [PR #6](https://github.com/Ritou-Lynx/here-i-am/pull/6) 已普通合入 v3-lab；happy@5447c5c4 为祖先，PR #6 五项 head 检查通过，合并树等于被测 67710151 树。

[接口约定](../I_CORE_DOMAIN_CONTRACT.md)与 PLAN W1 已标“约定已定稿”；W3/W4/W5/W7-0 的约定依赖已释放，W7-0 已在独立副本实现手机基础；W2已只读核对业务字段与权限。最初合成候选阶段没有读取真实副本；本轮在用户单独批准后完成[真实 schema4 一致副本 4→5→6 有限演练](W1_R01_REAL_COPY_VALIDATION_20261005.md)。未升级运行库、签发生产领域令牌、部署服务或安装手机。私有 D 工作区、WI/WL、旧失败修复窗及两个独立新窗没有混入此 diff。

## 实现

| 路径 | 可复核行为 |
|---|---|
| `tools/i_core/domain_schema.mjs` | 12 张新增表及严格 DDL/索引核查；`domain_sequence` 按命名空间/领域独立，内部自增主键不出站，`changed_at` 为内部 Core 时间。 |
| `domain_store.mjs` | 范围主体/actor、用户证据默认拒绝、字段组/用户锁、单 op 原子修改、并发裁决、HMAC 幂等、原授权集合复核、判重钩子与完整合并引用集合；没有业务域默认注册。 |
| `domain_store.mjs` | 永久墓碑、30 天恢复/清理、立即清正文来源、相关 duplicate 请求清理、合并/操作元数据无正文；old replay 不恢复删除正文；影子无生产接受回执。 |
| `domain_store.mjs` | 认证 cursor、固定读截面快照/分页/集合 digest、单调 ack、60 天 feed/90 天消费者保留、持久高水位。已发 cursor 与已完成快照缓存每 consumer 各 1024、域合计 8192/8MiB，计入正文容量；超限 429、不逐出有效快照，90 天失活元数据清理。 |
| `domain_http.mjs` | 六类路由、单 op、262144 字节预检、重复 JSON 成员/非法路径/query/protocol 拒绝；错误白名单及最小 tombstone/resync 指令，不透出异常正文。 |
| `domain_migrate.mjs` | 显式停写 supervisor、当前 recovery floor、独立 AES-256-GCM/HMAC 离线备份、单事务加表/marker 5→6、旧表/identity 核验；已产生领域内容或 sequence 历史后不降级。CLI 不接受未经验证的 --apply/停写布尔值。 |
| `domain_migrate.mjs` | 到期备份清理默认 dry-run；真实执行需 fresh owner 回调；仅认证/匹配/到期的自有 ciphertext，append-only 最小清理回执，失败重试/中断恢复，不声称物理抹除。 |
| `domain_migrate.mjs` | `validateDomainMigrationCopy()` 独立演练：可信副本哈希/原绑定/floor/离线复制证据；原 candidate 仅读字节，在 fresh scratch 保留绑定并写双重 backup_read_only 标记、自动加密备份、演练同 DDL并核旧表；不接原库路径、不放宽迁移入口，退出精确清理 scratch。 |
| `i_core_store.mjs` / `i_core_server.mjs` | schema 5 继续既有聊天、领域 503；只显式 schema 6 接领域。主服务接授权与判重适配器、保留任务；保留旧请求同步读取正文的时序。 |
| `i_core_store.mjs` | 本机 owner 给已登记 Android 当前 token 哈希/唯一主角色授 phone companion 能力；自报 capability 无效、错 origin/角色/任何 companion reply 字段拒绝、无 Core reply job；轮换/重启/角色或schema异常复核；授权/待队列检查同事务。 |
| `activity_control_plane.mjs` | 仅兼容 Core marker 6 与阻止 activity-only 回退覆盖较新 marker；activity schema、DDL、数据业务规则与路由未扩展。 |

`fields[domain]` 是写字段白名单，不是部分字段只读投影；汇总/明细隔离仍用独立权限域。用户授权验证器/配置是可信 owner 的代码适配器，不存在远程自行授予用户 actor 或生产 token 的通道。生产用户证据适配器、业务域 schema 和同步客户端分别随相应后续包实现。

## 主窗验证

Node v24.14.1；临时库/端口/凭据均为合成。主窗在 owner 冻结后串行执行，无新增跳过或屏蔽断言。

| 套件 | 实际结果 | 边界 |
|---|---:|---|
| 全部六个 `domain_*.test.mjs` | **111 pass / 0 fail / 0 skip**，51.78s | engine 51、HTTP 20、phone 10、schema+offline migration/cleanup 25、copy validation 5。包含真实 Core/SQLite/loopback HTTP 与提交后丢响应恢复。 |
| W0 同套 Core/Memory/MCP 顶层 18 文件 | **344 pass / 0 fail / 1 原有 skip**，261.14s | 总 345；只重跑已有套件。递归 Memory V3 42 条旧失败未合入独立修复候选，不报全仓全绿。 |
| 新路由时序修复专项（HTTP fixture runner + phone） | **24/24** | 初次整套出现 5 个新 fixture 失败，根因为通用 await 延后旧流读取监听；已修 prefix gate，同一整套最后零失败。没有把新失败称为旧债。 |
| 主服务语法与 diff | 通过 | 最后仅缩进整理无行为变化；`git diff --check`，新增模块语法/文档链接另核。未构建 App。 |

合成矩阵 A01–A17、A19、A21–A24 的服务端范围有实际专项断言。A18 固定 snapshot/到期/删除失效与 ack 已测，但客户端缺页/digest 拒绝、canonical+cursor 原子替换属于 W4，当前 partial。A20 Core 预检/持久事务/响应丢失、迁移 abrupt child exit 已测；客户端 A/B/E/F 的 outbox 排队、终态保存、投影崩溃属于 W4，当前 partial。测试夹具中的 example 域只用于合成，没有上线。

## 独立复核与修复

独立 worker/主窗逐项复核并补实际负例：领域序号不泄露其他域写入间隔；旧 import source 权限缩小后含 purge 的 GET 拒绝；semantic duplicate 的真实 target 删除清关联正文/旧 create 拒绝；首次旧 merge 多目标回执不泄露不可见 ID；merge/purge 的原 scopes 与引用字段同时在 GET 和 POST replay 前复核；影子 feed 按自身 Core 时间保留；同步缓存有界；缺身份/secret、schema/role 改动锁存拒绝，不靠恢复 metadata 字节自动重启接受。

## 验收范围与下一步

1. **R01 已获独立授权，并按追加批准的 4→5→6 副本链完成有限演练。**主窗核实现役库为 schema4，没有已有真实 schema5 输入。SQLite RO 事务 + backup API 一致快照；受控派生的新空 activity schema5 保全原八表/identity/replay 元数据后生成来源 floor，关闭后复制到独立 candidate，通过正式安全适配器 5→6、加密备份/旧表核验/明文清理。见[演练交接](W1_R01_REAL_COPY_VALIDATION_20261005.md)与安全回执；不声称已有真实 activity 历史或线上功能兼容已验收。
2. 独立 MCP 窗确认实际 Core 是包含 transcript/replay 的固定 **v4 源码包**，并非旧 checkout 的两个 Core 文件；不能直接用 W0/W1 覆盖现役功能。主窗已只读核实原库 marker=4；副本链通过只证明数据库内容保全，要先独立明确现役 transcript/replay 功能兼容和发布/回退，再考虑线上升级。远程 MCP 的独立源码切换仍在该窗口请求授权。
3. W1 未 commit/push/建 PR；提交/集成按用户授权进行。候选以以下文件哈希为证，不把 dirty diff说成已合并。
4. W3 接业务前先完成 MCP 源码对齐；W4 实现客户端 outbox/替换事务及剩余客户端 Gate；W2/W7 注册具体业务域。W6 只读聚合/映射与线上观察留其独立交接，持续上传/消费仍未验收。

## 候选源码 SHA-256

下表绑定当前组合工作区原始字节，覆盖13份代码/专项及activity兼容文件；原单包测试与先前R01属于历史候选证据，组合回归和最终副本链另报。Git暂存换行规范化需单独绑定，不能把原始字节冒充提交blob。

| 文件 | SHA-256 |
|---|---|
| tools/i_core/activity_control_plane.mjs | 18FE801708B5D1FF01DEEFE09E3EC9871A647A771522DF0045E8B6C241FA27CE |
| tools/i_core/domain_companion.test.mjs | 33F614A4A73E89AD35B6D039B4D7851F4079F721A540B116A9A357BD1B6247E7 |
| tools/i_core/domain_copy_validation.test.mjs | BDD93F2CCA4EF67999F8C2467AA7BFF42AE948A4924911B4907382BD32D9A0F0 |
| tools/i_core/domain_http.mjs | F3917F8FAE8F20421AED71BDD55CDD65027726734A7825CC8987758581A304EA |
| tools/i_core/domain_http.test.mjs | 9E9013B27502CF33AD85DF77228EFBCE1579C9721AAF86390C29F22BA8DE8A0F |
| tools/i_core/domain_migrate.mjs | DB1B9BF87558463CAC4532A36A2FB6405F16771CA15F2487E937E1B96D28DA82 |
| tools/i_core/domain_migrate.test.mjs | 4991E640F7692B76D4F93C91BAC22B1752F7001B37DCB834BDBABCF5E9D124E2 |
| tools/i_core/domain_schema.mjs | 4FE326D383E1AB6A5E94602AA0A83D1505B06FFFC5A2517E620B54576DE8EC34 |
| tools/i_core/domain_schema.test.mjs | 7FB0F5848AEE17B5BE83F973FA150F7DA02E9303E6F30E8CE81F11101A0997B5 |
| tools/i_core/domain_store.mjs | 96A5B292C281087C3A70EFC32D9FCFB053DA0466D9004C0A196CBFE1F721B0F6 |
| tools/i_core/domain_store.test.mjs | 10DBFD0386EDAF5BA83D735C774AC1101A53B530CF28CDD13BD98EFB5CB0BD06 |
| tools/i_core/i_core_server.mjs | 073C7F24E586C5984BAE6E5F358AC2F3C54B2D751D6CD9DB3024EDDBFBB2EB06 |
| tools/i_core/i_core_store.mjs | BC249946D526DCA3E06ED9189F0CBE2BA3AA84CBE84C4A535EC5E56E56AFA051 |

合成 runtime pin 夹具新增三份模块库存（domain_http/domain_store/domain_schema），生产pin守卫未改。夹具当前 SHA-256：`tools/i_core/test_fixtures/schema4/runtime_pin_lab.mjs` = `3D6D29DD56DBA4C9A776EEBA4F173B9557157D0A2F460AF74C752077656BBFEA`；对应七项打包/边界专项7/7。

四个业务域尚未注册。W2核对后的受控历史导入、业务状态取值、输入版本/嵌套/跨字段校验及源删除cascade引用登记随W2实现；通用框架通过不能宣称四域已可写或真实迁移完成。
