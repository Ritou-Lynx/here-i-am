# Workbench 生成产物、原子批次与 HTML 安全契约 ADR

> 状态：P3 契约提案，待 W0 / G3 集成评审
>
> 日期：2026-08-22
>
> 范围：provider-neutral domain、fixture 与接纳守门；不含 renderer、provider、schema、迁移或 UI

## 1. 背景

桌面工作台未来会一次生成多张 Card、Source、白板布局、图片或 HTML。模型不能直接写 Drift、任意路径或 WebView，也不能在某一步成功后留下半张卡、孤立文件或无法撤销的布局。现有 `TaskArtifacts` 只记录任务过程产物，现有 `Card / Source / BoardItem` 是产品稳定身份，两者不能靠隐式字段等同。

旧 `HtmlWebViewCard` 默认 base URL 指向 localhost，并允许普通 WebView 导航；YouTube WebView2 adapter 则是一个经产品控制、只服务官方播放器的专用 host。二者都不能直接承载模型生成的任意 HTML。

## 2. 决策

新增纯领域契约：

- `GeneratedArtifact`：生成结果的逻辑身份；
- `ArtifactManifest`：MIME、字节数、SHA-256、staging object ref、内容寻址 final object ref 与 provenance；
- `ArtifactBinding`：TaskArtifact、Source、SourceVersion、Card、BoardItem 的稳定软引用；
- `ContentBundlePlan`：一次授权内的 Artifact、Source、Card、Board、Item、Group、Edge 与 promotion；
- `DomainOperationBatch / OperationReceipt`：授权、runtime turn、幂等键、冲突哈希、逐操作结构化 inverse 与确定性回执；
- `ArtifactCommitJournal / FailureRecoveryPlan`：记录 staging、hash 验证、原子绑定、回滚或待恢复；
- `TaskArtifactPromotion`：把任务产物显式提升为 Source / Card 的唯一契约入口；
- `HtmlRuntimeBundle / HtmlSandboxPolicy`：原始 HTML 与可执行 runtime bundle 的分离及能力清单。

这些类型不 import Drift、Repository、UI、renderer 或 provider。它们复用现有 `CardKind.taskArtifact / note`、`SourceMediaType.image / web` 与所有 Card / Source / Board 稳定 ID，不扩枚举、不复制身份。

`ContentBundlePlan` 中的实体列表是本批次声明并纳入 conflict guard 的引用集合，不等于全部执行 create；真正的 create / update / bind 语义只由 `DomainOperationBatch.operations` 决定。因此后续把新图片放入已有白板时可以携带该 Board 的受守卫投影，而不复制 Board 身份。

## 3. 原子提交协议

提交顺序固定：

1. Here I am 生成 `ContentBundlePlan`，绑定明确 `authorization_id`、`runtime_turn_id`、`idempotency_key` 与 `expected_state_hash`；
2. provider 只能把 bytes 写入受控 staging root，返回相对 `staged_object_ref`；绝对路径、URI、反斜杠与 `..` 均拒绝；
3. host 流式计算实际字节数、MIME 与 SHA-256，对照 manifest；任一对象失败时零产品绑定；
4. 全部对象验证完成后，先落内容寻址对象，再在一个产品事务中绑定 Source / Version / Card / Board；
5. 事务成功生成 durable receipt，保存 after hash 与逆序 inverse；同一幂等键重放只返回原 receipt；
6. staging 成功但验证失败：写 `recovery_required` journal，清理 staging，不产生 Card / Source；
7. 对象落盘后产品事务失败：执行 inverse / 软撤销，内容对象进入延迟 GC，不在错误路径直接删除可能已被引用的对象；
8. 撤销前复核 conflict guard，不覆盖用户在批次之后的编辑。

领域 operation 不提供 `delete`。`create / bind / promote` 只能以同一实体的 `retract` 为 inverse；`update / retract` 只能以携带 previous state 的 `update` 为 inverse。验证器同时核对 entity type / ID 已在 plan 声明，任意非空 map、跨实体 inverse 或硬删除字符串都不能冒充可逆操作。

默认预算提案：单产物 20 MiB、单批 100 MiB、64 个产物、512 个操作。它们是接纳上限，不是 UI 承诺；W0 可在 G3 统一调整。

## 4. TaskArtifact promotion

`TaskArtifact` 默认只属于任务房间。记录任务结果、错误日志或生成草稿不会自动写 User-truth，也不会创建 Card / Source。

promotion 必须同时具备：

- 非空且与 batch 一致的用户授权 ID；
- 已验证 Artifact；
- 新建或明确复用的 Source / SourceVersion / Card 稳定 ID；
- 可逆 operation 与 receipt；
- provenance refs。

promotion 还必须满足关系闭环：SourceVersion 的 `source_id` 属于目标 Source，Card 指向同一 Source，ArtifactBinding 的 TaskArtifact / Source / Version / Card 与 promotion 完全一致，并且 manifest 的 final object ref / SHA-256 与 SourceVersion 一致。验证器不把“这些 ID 分别存在”视作足够条件。

生成 HTML 使用既有 `SourceMediaType.web`，生成图片使用 `SourceMediaType.image`；作为任务产物提升的卡可用 `CardKind.taskArtifact`，综合文字卡继续用 `CardKind.note`。不新增 `htmlCard` / `generatedImageCard` 平行身份。

## 5. HTML 原件与 runtime bundle

原始 authored HTML 是不可变证据，SourceVersion 的 authoritative `object_ref / content_hash` 指向它。runtime bundle 是经过静态审核、资源归档、CSP 注入和能力收窄后的独立衍生 Artifact；二者必须是不同 Artifact 身份与 object ref。`HtmlRuntimeBundle` 必须与引用 manifest 强一致：raw kind / MIME 为 `html` / `text/html`，runtime kind / MIME 为 `html` / `application/vnd.hereiam.html-runtime+zip`，runtime object ref / SHA-256 与 manifest 逐项相等。卡片渲染只消费已 `accepted` 且无未处理 finding 的 runtime bundle，不能交叉替换另一个 bundle 的 manifest。

契约层的 `inspectRawHtmlCapabilities()` 只报告能力，不声称清洗安全。真正的 parser、sanitizer、packager 和 WebView2 host 属 P9。

### 当前 v1 能力清单

| 能力 | v1 决策 |
|---|---|
| 本地静态 CSS / 图片 / Canvas | 可在审核后声明 |
| 脚本 | 只允许打包后内容哈希列举；禁止 `unsafe-inline` / `unsafe-eval` |
| 网络 | 默认无；只有显式授权、精确公共 HTTPS origin 可声明，禁止通配符 |
| 页面导航 | 禁止；外链由 Flutter 读取稳定 intent 后另行确认 |
| 表单 / 剪贴板写入 | v1 禁止 |
| `file://` / UNC / 任意本机路径 | 禁止 |
| localhost / loopback | 禁止，包括 `localhost`、`127.0.0.1`、`::1` |
| popup / download | 禁止 |
| JS bridge | 只允许 `report_height`、`open_stable_ref`、`emit_user_intent` 三个窄方法；无任意命令、文件或网络桥 |

最低 CSP 必须包含：`default-src 'none'`、`base-uri 'none'`、`object-src 'none'`、`frame-ancestors 'none'`、`form-action 'none'`。任何 `*`、`file:`、localhost、unsafe-inline 或 unsafe-eval 都拒绝。任何重复 directive 也直接拒绝并按浏览器 first-wins 保留首项做安全判断，避免“危险第一项 + 安全第二项”被验证器误判为安全。

网络 origin 只接受规范域名或规范四段十进制公网 IPv4。验证器拒绝单整数、缩写点分、十六进制、八进制、前导零与混合进制等数字 host（例如 `2130706433`、`127.1`），避免 URL / OS 栈把它们解析到 loopback 或私网。这个字面量守门不能替代网络层安全：P9 / host 对真实域名的每次请求与重定向仍必须 DNS resolve、验证全部地址为公网，并把连接 pin 到已验证地址，防止 DNS rebinding / TOCTOU。

## 6. Windows WebView2 宿主约束

P9 renderer 接入时必须：

- 使用固定的非 localhost 虚拟 HTTPS origin；
- 映射只读、内容寻址 runtime bundle，host resource access 取最小值；
- 默认 deny popup、context download、权限请求、新窗口和顶层导航；
- 所有资源请求按 manifest + CSP + exact-origin allowlist 再校验；
- 对 allowlist 中的真实域名逐跳 DNS resolve、拒绝任一 loopback / private / link-local / reserved 地址，并把实际连接 pin 到同一份已验证地址；
- bridge 按每张 bundle 的 policy 建立窄路由并校验消息 schema / 大小 / 用户手势；
- 卡面使用静态可信预览，只有当前聚焦的一张内容创建交互 WebView；退出焦点销毁 runtime；
- 不复用旧 `HtmlWebViewCard` 的 localhost base URL，也不把 YouTube 专用 bridge 泛化给生成 HTML。

## 7. 失败恢复与安全后果

- 验证失败不创建产品身份；事务失败不留下半绑定；恢复 journal 可跨进程继续。
- receipt 和 inverse 是产品审计，不把 task transcript 或原始凭据写入 Card / User-truth。
- runtime bundle 可重新派生；原始 HTML 与 provenance 保留，安全策略升级不改变 Source 身份。
- 本 ADR 不保证任意 HTML 安全。只有后续 packager + WebView2 host 通过真实对抗测试后，才允许交互 renderer 上线。

## 8. W0 / G3 接入请求

1. 评审新目录 `lib/domain/workbench_ai/artifacts/` 为共享 provider-neutral contract；
2. 决定 durable journal / receipt 的 Repository 与 schema，P3 不自行建表；
3. 定义 content-addressed object store 的 staging root、原子 rename 与延迟 GC 接口；
4. 在 Wave3 与 W5 汇合后做跨模块契约测试，再派发 P7 / P8 / P9；
5. P9 必须另交 HTML packager、CSP enforcement 与真实 Windows WebView2 安全验收，不能把本轮静态检查当成 renderer 完成。
