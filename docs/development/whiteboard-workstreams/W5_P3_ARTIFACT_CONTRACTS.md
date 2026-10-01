# W5 P3 — 生成产物、批次与 HTML 安全契约

**状态**：契约、fixture 与定向测试完成；待 W0 / G3 评审集成

## 本轮闭环

- 新增 provider-neutral `GeneratedArtifact / ArtifactManifest / ArtifactBinding`；
- 新增 `ContentBundlePlan`，可在同一授权批次描述多个 Source / Version / Card / Board / Item / Group / Edge；
- 新增幂等 `DomainOperationBatch / OperationReceipt`、逐操作 inverse、conflict hash；
- 新增 `ArtifactCommitJournal / FailureRecoveryPlan`，冻结 staging → hash 校验 → 原子绑定 → 回滚 / 恢复协议；
- 新增显式 `TaskArtifactPromotion`，任务产物不会因被记录而自动成为 Card / Source / User-truth；
- 新增 HTML raw / runtime bundle 分离、CSP、网络、导航、file、localhost、popup、download 与窄 bridge 能力守门。

## 审核返修闭环

- CSP parser 直接拒绝重复 directive，并按浏览器 first-wins 检查首项；已覆盖“危险第一项 + 安全第二项”；
- 网络 origin 拒绝单整数、缩写点分、十六 / 八 / 混合进制数字 host；真实域名仍要求 renderer host 逐跳 DNS 校验并 pin；
- `HtmlRuntimeBundle` 与 raw / runtime manifest 强校验身份、kind、MIME、object ref 与 SHA-256，拒绝 manifest 交叉替换；
- promotion / binding 强校验 SourceVersion→Source、Card→Source、binding→promotion 以及 manifest→SourceVersion 关系；
- operation 移除硬 `delete`，inverse 改为同目标强类型结构；create / bind / promote 只允许 retract，update / retract 必须以带 previous state 的 update 恢复。

## 契约影响

- 新目录：`lib/domain/workbench_ai/artifacts/`；不 import Drift、Repository、UI、renderer 或 provider；
- 复用 `CardKind.taskArtifact / note`、`SourceMediaType.image / web` 与现有稳定 ID；未修改已有 Card / Source / Board / RichTextAssetRef 语义；
- 未改 schema、迁移、依赖、生成文件或根 barrel；由 W0 决定正式共享导出与持久化位置。

## Fixture 与验证

- `normal_content_bundle.json`：HTML 原件 + 安全 runtime、TaskArtifact promotion、两卡、一板、一组、一边；
- `partial_failure_journal.json`：两对象 staging、一项 hash 失败、零产品绑定、显式清理计划；
- `over_limit_manifest.json`：单产物超过 20 MiB；
- `path_traversal_manifest.json`：`../` staging 逃逸；
- `dangerous_html_bundle.json`：危险 CSP、loopback、通配 origin、导航、下载、popup、file 与宽 bridge；
- P3 定向 Flutter 测试 30/30；与既有 W0 白板契约组合回归 56/56；定向 analyze 零问题。

## 安全结论

`inspectRawHtmlCapabilities()` 只是 fail-closed 的能力发现器，不是 sanitizer。生成 HTML 只有在后续 packager 产生独立 hash runtime bundle、policy accepted 且真实 WebView2 host 再执行资源 / 导航 / bridge 守门后才能交互展示。真实域名必须逐跳 DNS resolve + public-address 校验 + connection pin；旧 localhost HTML WebView 与 YouTube 专用 bridge 均不能复用为通用生成 HTML 权限面。

## 未实现 / 下一接入点

1. W0 冻结 G3 类型、Repository、schema 与 content-addressed object store；
2. P7 / P8 在汇合基线上实现知识库与图片 provider / 写入纵切；
3. P9 单独实现 HTML parser / packager / renderer 与 Windows WebView2 对抗验收；
4. 跨进程 receipt / journal recovery、对象延迟 GC 与冲突撤销仍未实现；
5. 本分支不含真实桌面窗口，因为按总控计划 P3 在 G2 前只交付 ADR、fixture 与契约测试。

## 集成信息

- 分支：`codex/whiteboard-w5-artifact-contracts`
- 基线：`v3-lab` @ `f6001ed9`
- 提交：本分支最新提交（交由 W0 以 `git log -1` 核对）
- 不 push、不合并
