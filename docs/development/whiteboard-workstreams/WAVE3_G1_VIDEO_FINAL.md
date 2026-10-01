# Wave 3 G1 视频最终收口 handoff

## 本轮闭环与边界

- 最终集成分支：`codex/whiteboard-wave3-final-integration`；从最新真人验收分支继续，不 push、不合入 `v3-lab`。
- 拥有路径：视频 domain / UI / ViewModel、链接导入页、Annotation 原子写入、视频定向测试与本 handoff。
- 共享语义不变：`Card / Source / Anchor / Snapshot / PlayerAdapter / TimedTextTrack` schema 均未修改，无数据库迁移或 W0 contract request。
- 未做：不碰手机 UI、W5 Runtime/Search/Artifact，不绕登录/DRM，不使用未公开平台接口。

## 产品结果

1. 视频笔记继续使用真人已通过的单一无框连续文档；不恢复 title / body / quote 三个输入框。
2. ContextDock 继续使用“字幕 / 视频笔记”双 Tab，笔记纵向排列；新建标注自动进入视频笔记，关闭和重开 dock 后 pending 工作流与草稿仍在。
3. 字幕 cue 和独立当前位置入口都可创建点或区间 Anchor；区间两端分别读取播放器当前时间，相同端点给出可恢复提示且不保存伪点。
4. Bilibili 在 Windows 保持官方嵌入播放与“时间研读受限”边界；保存 link-only Card 后可显式打开 SourceStudy，不读取或保存平台登录态。
5. 链接保存后停留当前页，成功态分别提供打开视频研读与打开卡片库；取消、失败或需授权时不写伪成功。

## Bilibili 能力依据

- 官方外部播放器文档：<https://player.bilibili.com/>。可证实 embed 与初始 `t`，但没有可供本应用依赖的 current/duration/seek 或字幕发现契约。
- 官方开放平台：<https://openhome.bilibili.com/doc>。本轮未找到面向第三方消费者的稳定公开字幕发现 API，因此不实施猜测请求。

## 自动验证

- Widget：单一连续笔记、双 Tab、纵向笔记列表、pending 草稿跨断点与 dock 重开、字幕 cue 冲突保护、无字幕点/区间、相同端点拒绝、错误文案脱敏。
- Repository：真实区间重启恢复；非法 position kind、负时间、start > end、is_point 不一致均零写入。
- 对象写入：新对象交换中断、既有 tmp/bak 精确恢复、同 objectRef 串行及失败后重试。
- 链接导入与平台：保存停留、显式打开研读、取消不写库、Bilibili 能力分类和 SRT/VTT 后备。
- 最终测试数量和构建产物由本分支最后一轮门禁完成后回填到验收状态表，不沿用功能包旧计数。

## 真人待验与剩余风险

1. Windows WebView2 用真实 BV 验证匿名播放、平台登录页、返回研读页和加载失败后重试；应用不应显示自己持有登录态。
2. Windows 真实 YouTube 有 CC/无 CC/受限样例验证轨道发现与失败分类；平台页面变更仍可导致解析器失效，届时应诚实显示分类并改用 SRT/VTT。
3. 真实 Bilibili 仍无可恢复 current/seek，因此不开放时间 Anchor；这是平台契约限制，不是以 `0/null/no-op` 伪装完成。

## 二审返修（2026-08-23）

- Annotation Card 不再经过“建 Note → 绑 Source → 改 annotation”三段可见写入。`createVideoAnnotationCard` 在一个 Drift transaction 内校验 Source、SourceVersion 归属、Card kind/sourceId、完整 Anchor 及摘要一致性。
- Source 对象 final/tmp/bak 文件交换和数据库事务由同一 objectRef 守卫覆盖；失败时精确恢复既有字节，删除本轮新建且未被数据库引用的 sidecar，重试只产生一份对象和一张标注卡。
- 标注草稿在 ViewModel 中非持久保存；用户主动清空字幕引用后不会因布局重建被 initialQuote 回填，保存失败保留草稿和焦点。已有 pending 时其他 cue 的标注入口 fail-closed。
- load / save / session restore / current-time 异常只显示固定安全文案，不向 UI 泄露 provider、存储或数据库异常文本。
- 当前联合定向回归 115/115（视频/数据/链接 83，卡面/画布 32），14 个实际源码文件定向 analyze 零问题；独立二审和 Windows 真人验收尚未完成。

## 独立二审最终返修（2026-08-23）

- ingestion 锁从 incoming objectRef 改为工作区 + provider + canonicalId/URL 的稳定 identity；不同 incoming sourceId 的真并发在同一锁内串行，并在 Drift transaction 内复查 canonical Source 与 content hash，最终只落一套 Source / SourceVersion / Card / object。
- 对象写入前新增仓库私有 intent journal。模拟“final 已写、DB 未提交”的进程退出后，重启只删除 intent 明确声明且 DB 无引用的 final/tmp/bak；模拟“DB 已提交、intent 未清”的退出则保留引用对象、只删 intent；无 journal 的合法文件不参与孤儿清理。
- `time_range` 的 `start_ms/end_ms` 只接受整数，小数不再截断；Repository 回归确认拒绝后 MemoryCard / Extras 均零新增。
- `annotationDraftWasFocused` 由只写标志改为编辑器重建时的真实恢复条件；测试可区分“已有草稿但从未聚焦”与“此前聚焦”。字幕文件选择和标注保存故障均注入内部 secret，并确认 UI 只显示固定安全文案。
- 视频笔记列表以 12 张卡制造真实 overflow，断言滚动范围非零并滚到末卡完成时间回跳；单一无框文档、双 Tab、纵向列表和区间标注产品形态未改。
- 最终数据/视频联合回归 116/116；7 个生产源码定向 analyze 零问题；关键修复守门 3/3；`git diff --check` 通过。Windows 真人验收仍按上节三项执行。

## 第二轮数据复审返修（2026-08-23）

- intent journal 升级为 v2，在任何 Source 对象写入前记录 final/tmp/bak 的精确 bytes 或“不存在”状态。DB 未提交即退出时，启动对账按 snapshot 原样恢复旧现场，并跳过当轮通用 exchange 清理，避免恢复后又被清扫。
- Drift transaction 成功即越过补偿边界；后续 intent cleanup 的普通异常不会回滚已引用的新对象，只留下 journal。启动时看到 DB 引用便保留 final、仅移除 intent，确保文件内容和 SourceVersion 一致。
- ingestion 使用工作区级单一协调锁，同时覆盖 provider+URL / provider+ID 任一相同的 canonical 等价类，以及 canonical 不同但最终 objectRef 相同的写入；无多键锁顺序和死锁风险。
- 同 objectRef 一败一成时失败者先恢复现场、胜者再提交；两次成功时后到的同 hash 来料不改写首个对象、canonical 身份或 Card 正文，但仍允许同版本缩略图候选更新。
- 新增 5 项专项回归；最终数据/视频联合 121/121，仓库专项 32/32，本轮 2 文件定向 analyze 零问题，关键修复 3/3，diff check 通过。

## 第三轮 journal 完整性返修（2026-08-23）

- v2 snapshot 对每个存在的 final/tmp/bak 同时记录 byte length 与 SHA-256；启动恢复严格验证 schema、精确字段、类型、base64、长度与 hash，任何未知版本或损坏 journal 都保留原 intent 和对象交换现场供诊断，并继续处理其他合法 intent。
- 可解析但损坏的 intent 仍只使用经过路径边界校验的 objectRef，阻止后续通用 exchange recovery 误删其 final/tmp/bak；不可解析内容不被当作恢复依据。
- snapshot 单文件上限 4 MiB、三份合计上限 8 MiB；超限在 journal 和对象写入前以固定安全错误拒绝，旧 final/tmp/bak 与数据库保持不变。
- 新增可解码位翻转、非法 base64、缺 hash、未知版本、journal final 中断且残留 tmp/bak、合法/损坏 intent 同轮对账及 9 MiB 聚合超限回归。最终数据/视频联合 148/148，仓库专项 34/34；2 文件 direct-dart analyze 零问题，关键修复 3/3，diff check 通过。

## 第四轮不可读 journal 与真实路径返修（2026-08-23）

- 启动时对 intent main/tmp/bak 逐份做 regular-file、12 MiB envelope 上限和完整 v2 语义预检；main 即使存在但截断或非 JSON，仍可按 RecoverableFileExchange 顺序从合法 tmp、bak 恢复。
- 三份候选均无可信语义副本且无法确定 objectRef 时，保留全部候选并标记 unresolved；本轮仍继续处理其他合法 intent，但完全跳过通用 Source final/tmp/bak 修复，不猜测不透明 journal 的目标。
- 写回 snapshot 或运行通用 Source exchange 前，验证 whiteboard root、sources root 与目标父目录的真实路径 containment，并拒绝 symlink/junction/file-link 逃逸；平台无法证明时保留 intent 与对象 peers。
- SHA-256 只用于发现存储、写入中断或偶发位损坏；它不是认证签名，不防御拥有本机写权限并能同时重签 journal 的攻击者。
- 新增截断 main + 合法 tmp/bak、三份全坏、13 MiB 伪造 envelope、真实路径解析越界 seam 回归。最终数据/视频联合 151/151，仓库专项 37/37；3 个实现/测试文件 direct-dart analyze 零问题，关键修复 3/3，diff check 通过。
