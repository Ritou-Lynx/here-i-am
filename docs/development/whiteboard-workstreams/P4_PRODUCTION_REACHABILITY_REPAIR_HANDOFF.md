# P4 Production Reachability Repair Handoff

## 交付身份与范围

- Goal：`GOAL-20260828-p4-production-reachability-repair`；worker：`/root/p4_reachability_worker`。
- Worktree：`.worktrees/p4-production-reachability-r1`；分支：`codex/whiteboard-w1-p4-production-reachability-r1`；精确基线：`69ddf56b325b774b0b1ffbe806e03edcab4fee27`。
- 第一轮 `0fe885f6` / `973ff8b8` 已被 W0 复核否决；第二轮修复代码提交为 `38334f5e29d3fb88cf1f2b4e486cb46ce5eaf415`，本文位于随后仅含 handoff 的提交中。W0 应以交接时分支 HEAD 复核第二轮增量。
- 第三轮只读问句授权修补代码提交为 `adbc3568c34d2079ed53d13a67b7b49de61be340`；除 Runtime tool、其测试与本文外无新增写入。
- 第四轮最终窄修补代码提交为 `44ce4ac57b206a8ccd3197b82b2c11ea0296fa04`；本文随后以独立 docs commit 更新。
- 第五轮疑问句 fail-closed 补丁代码提交为 `4986f03542ab8adb81aba543527d3e9847efd721`；本文随后以独立 docs commit 更新。
- 第六轮 intent grammar 收口代码提交为 `041787c5a3fdeeb9bbf2f00b7053ae81be155031`；本文随后以独立 docs commit 更新。
- 第七轮完成状态确认补丁代码提交为 `ab7fab26f0c5d029e94438443abaedd0c85c4cf9`；本文随后以独立 docs commit 更新。
- 第二轮仅使用 W0 追加授权的 facade/executor、permission broker、Persona action 精确更新行数，以及原有 P4 UI/Runtime/tests/handoff 路径。未改 schema、生成文件、依赖、Search、Card/Board/wire identity、Goal/Roadmap/I_PROJECT_STATE/DEVLOG。

## 第四轮最终窄修补

- Runtime capability 改为正向明确写意图：正文、标签、移动与缩放都必须出现对应 mutation verb；裸字段不再授权。`如何/怎么/合适吗/对吗` 及事实查询统一 fail closed，只有 `能帮我/可以帮我/请帮我 + 把/将 + mutation` 这类明确委托可越过咨询分类。表驱动正例逐项断言精确 capability 集合。
- host scope 在授权进入 prompt 前校验：selected item/card 各自沿用 broker hard max 64，ID 必须是 portable ASCII 且 UTF-8 不超过 256 bytes；最终单行 untrusted context 不超过 16 KiB。超限分别稳定返回 `whiteboard_scope_too_large`、`whiteboard_scope_invalid`、`whiteboard_context_too_large`，不截断也不把非法内容传给 Runtime。
- Persona 生产 screen 增加最小 conversation connector seam。真实 `_sendDesktopMessage` 仍先持久化 user row，再由同一调用把精确 row ID 交给 production connector。widget mutation gate 操作现有 `desktop_chat_input` 与 `desktop_chat_send`，删除这条真实 UI 接线会使 connector/evidence 断言失败；没有改变按钮或发送语义。

## 第五轮疑问句 fail-closed 补丁

- 非明确委托的 `吗/么/呢/？/?` 状态、能力与必要性问句，以及 `会不会/有没有` 问句，在 capability 提取前统一归类为 consultation。覆盖创建了吗、移动了吗、需要/可以移动吗、缩放过吗等会包含 mutation verb 的反例。
- 只有现有窄模式 `能帮我/可以帮我/请帮我 + 把/将 + mutation` 可以越过疑问句门控；普通对象加“可以/需要 + 动作 + 吗”不会授权。测试保留并新增两种明确委托的精确 `movePlacement` 正例。

## 第六轮 intent grammar 收口

- 强疑问/状态 marker 在 capability 提取前一律拒绝：`是否/是不是/能不能/可不可以/有无/有没有/要不要/需不需要/该不该/应不应该/会不会/与否/还是不/了没/没有/为什么/为何/什么时候/何时`，并继续覆盖普通疑问助词和问号。
- 可带句末“吗”放行的委托已收窄为 `能帮我/可以帮我/请帮我 + 把/将 + 明确结果动作`：移动必须到目标，正文/标签/宽高必须给出改成、设为、添加、移除或调整等结果形态，移除必须明确从白板移除。裸移动、创建、缩放不再借委托前缀绕过。
- 表驱动反例覆盖 W0 指定五句、全部扩展 marker 以及三种裸动作委托；精确 capability 正例覆盖两种 move 委托，并补 body、labels、resize、remove 结果动作。

## 第七轮完成状态确认补丁

- `已/已经/完成了/成功了/好了/了` 等完成状态与句末 `吧/对吧/是吧`（中间允许至多 16 字）组合时统一归入 consultation，阻止“移动完成了吧”“已经移动了对吧”等确认句获得 mutation capability。
- 单纯祈使语气不受影响：`把白板卡片移动到右边吧` 与 `请把白板卡片移动到右边吧` 仍精确授权 `movePlacement`。测试用通用状态结构的五个反例与两个正例守门，没有硬编码完整句到生产逻辑。

## 真人 Gate 返修：恢复内嵌编辑与候选 C

- 代码提交：`b0b9f768`。生产空白双击再次在新建 BoardItem 的同一卡面打开既有 `CompactCardEditor`：透明、无额外 Domain frame/chrome，下一帧 autofocus，一个连续原生输入值的首行为 title、余下为 canonical plain body；BoardItem rect 与当前 viewport 不变。
- 新增 manual-only `EditCardTitleCommand`，具有独立 JSON kind、500 rune validation、capability、inverse、persistent Receipt/Undo/reopen 语义。白板内嵌保存把 title + body 放在同一个 manual batch；Runtime tool schema/intent/grant 仍只暴露原六类，facade 明确拒绝 Runtime title。
- labels 从连续正文框分离到右键“编辑标签”，一次只提交一个 `SetCardLabelsCommand` batch。active receipt reload 只用持久 snapshot 刷新 cards/items，并恢复进入 reload 前的 centerX/centerY/zoom。
- 采用 W0 裁决的候选 C：`EditCardBodyCommand` 只替换 Card canonical plain body，不改 RichTextDocument。repository 以当前 DB Card 验证文件；`document.toPlainText().trim() != card.body` 时返回 `stale + document=null`，文件与 asset 原样保留。exact-match Undo 后复杂 blocks/marks/assets 自动重新 available。
- Card Library 与本地媒体 resolver 已移除 raw storage fallback；cached Card 不会绕过当前 DB projection。full editor 在 stale 时显示 DB body、锁定 document、明确旧文件已保留，仅 labels dirty 时不调用 rich save。production inline Domain surface不加载富结构，且 marks/media/format-only 不产生 completed action。

### 本轮有界验证

- production route：`4/4 PASS`，包括真实 primary pointer 空白双击、同卡面连续 title/body 同 receipt、labels 独立 batch、geometry/viewport 不跳、commit/reload 失败锁。
- manual port `2/2 PASS`；Runtime 单文件 `10/10 PASS`；rich repository/screen `5/5 PASS`。
- title Domain/reopen/Undo `3/3 PASS`；strict stale/notLoaded/cached-card repository `2/2 PASS`；compact format/media-only `1/1 PASS`；Card Library stale media `1/1 PASS`。
- changed-file analyze：`21 items, No issues found`（38.0s）；critical fixes：`3/3 PASS`；`git diff --check`：PASS。无最终 Windows build，符合本工作包约束。

### 明确边界与后续债

- P4 完成声明仅覆盖白板内嵌 title + canonical plain-body Domain 操作；full rich-text authoring 仍是独立 repository writer，不伪称已进入 Domain receipt/Undo。
- RichText 文件不参与本轮 Domain transaction、Receipt 或 Undo；stale 只是计算型读取隔离，不删除/修复文件。跨窗口 full-rich writer 的 optimistic conflict 仍是后续 P2 债。
- 图片导入、富文本 marks/media 命令、旋转、group/edge/viewport、P5/P6/W4/Gate 1A 均未扩大；未改 schema/generated/deps/Card/Board/wire identity 或 W0 控制面。

## 第九轮：Runtime 执行 invariant 与保存失败可见性

- 代码提交：`b3346610`。`executeRuntime` 现在与 `authorizeRuntime` 共用 manual-only batch guard，并在 action running row、事务与 executor 之前拒绝任何 `EditCardTitleCommand`。即使调用方绕过 facade、直接从 broker 签发 title capability grant，也只得到稳定 `ArgumentError(edit_card_title is manual-only)`；Card/Board hash、action rows 与 Undo binding 均不变。
- `CompactCardEditor.domainSave` 返回 `null` 不再静默：它转换为明确“保存失败”提示，保留当前 controller 草稿、dirty 状态和内嵌编辑器，不触发 onSaved/onClose。组件测试同时核对持久 Card title/body 不变；生产 manual host catch 仍保持 fail-closed，无 debug rethrow。
- 验证：forged Runtime grant `1/1 PASS`；manual title reopen/Undo `1/1 PASS`；Domain failure/draft retention `1/1 PASS`；format/media zero-commit `1/1 PASS`；Runtime 全文件 clean exit `10/10 PASS`；production route真实空白 primary-pointer 双击及相邻锁/reconcile `4/4 PASS`。
- changed-file analyze：`4 items, No issues found`；critical fixes：`3/3 PASS`；`git diff --check`：PASS。full-rich optimistic conflict 继续保留为 W0 已裁决 P2 债，本轮未扩大 full-rich writer。

## Windows direct-interactions 测试清理修复

- test-only 代码提交：`97383514`。`_RepoHarness` teardown 先卸载 widget，再关闭 DB；随后 Windows 删除使用最多 10 次、每次 50ms 的异步重试，最后一次 `FileSystemException` 原样 rethrow，非 Windows 仍只尝试一次，不吞永久泄漏。
- 两个受影响用例末尾只核对 Card projection，改用 `getCard(loadDocument:false)`，避免 teardown 前为不需要的 rich document 断言再次打开 `rich_text.json`；产品代码、rich writer 与产品断言均未改变。
- 精确用例分别 `1/1 PASS`：`空白双击建真实 Card，移除 BoardItem 不删 Card`、`原位编辑的标题首行与正文共用单一无框输入面`。整个 `whiteboard_canvas_direct_interactions_test.dart`：`23/23 PASS`；该文件 analyze：No issues；critical fixes：`3/3 PASS`；diff-check：PASS。
- 失败诊断中验证过 0.45s、约 2s、约 5s 的单纯延时均继续 errno 32，说明不能靠无限延长掩盖生命周期问题；卸载 widget + 去除末尾无必要 rich read 后，短重试窗口稳定 clean exit。诊断遗留的 10 个 `w1_direct_*` TEMP 目录已逐一校验位于系统 TEMP 后清理，remaining=0。

## Card Library Windows 异步等待修复

- test-only 代码提交：`9f3fc569`。`pumpApp` 与会触发 Card Library repository reload 的测试步骤统一经有界 helper：先 pump 暴露生产 loading indicator，再以最多 80 次、每次 25ms 的真实时钟延时配合 50ms widget pump 等待 rich document 文件 I/O；2 秒仍未清除 loading 会带稳定原因明确失败，完成后才做必要的 settle。
- 没有延长全局测试 timeout，也没有跳过断言；筛选、建板放入、返回卡片库与 desktop 重新装载均使用同一等待边界。产品代码、rich writer、schema/generated/deps 与 W0 控制面零改动。
- `card_library_repository_test.dart` 整文件：`13/13 PASS`（72s）；`Card Library never renders a stale rich media fallback` 精确复跑：`1/1 PASS`。该文件 analyze：No issues（2.6s）；critical fixes：`3/3 PASS`；`git diff --check`：PASS。

## 真人 Gate：白板新卡进入 full editor 的中性状态

- 代码提交：`30790f31`。诊断确认白板 Domain create 按候选 C 只写 canonical Card/BoardItem，不应在 receipt 后旁路物化 rich 文件；原 UI 却把所有 `CardDocumentState.missing + 非空 body` 都描述成“文件缺失/投影恢复”，把合法纯文本新卡误报成数据异常。
- 无 schema/manifest 时不能可靠区分“从未物化”与整个 card rich 目录被外部删除，因此已明确拒绝并完全撤掉目录存在性 heuristic、`unmaterialized` 新状态和 presentation marker。repository 的 `available/missing/corrupt/stale/notLoaded` 契约、canonical plain body、stale/Undo 与 full-rich writer 均未改变。
- 最小产品修复只把 missing notice 改为中性事实：“当前没有可用的富文本版本，正在显示卡片正文；编辑并保存后会创建富文本版本。”真实 missing 仍显示 notice，但不再无证据声称缺失或恢复；corrupt/stale 继续使用各自明确提示。
- 真实 production Gate 使用 primary-pointer 空白双击创建，内嵌 Domain title/body 与 labels 提交后，通过右键“展开查看”真实 push full editor：正文精确可见、中性 notice 存在、无“富文本文件缺失/正文投影恢复”，且仅打开不创建 rich 文件。`whiteboard_production_domain_route_test.dart`：`4/4 PASS`。
- rich-editor/repository suite：`7/7 PASS`，覆盖纯文本新卡/真实 missing 共用中性 notice、仅标签保存零 rich 写、首次正文编辑保存后 `available`、返回重开无 notice、删除已保存文件后恢复中性 notice、corrupt 与 stale 标签路径。restart/Undo exact：`1/1 PASS`，复杂 marks/asset 在 stale 后 Undo 仍恢复 `available`。
- changed-file analyze 仅输出 `Analyzing 3 items...` 后 60 秒无终态，已中止且未重试；critical fixes：`3/3 PASS`；`git diff --check`：PASS；无残留 dart/flutter_tester 进程。

## 第十轮：空正文与 media-only missing 提示

- 代码提交：`3badd36f`。`CardDocumentState.missing` 现在无论 Card body 是否为空都显示中性 notice；文案明确为“编辑正文并保存后会创建富文本版本”，不再暗示 tag-only 保存会物化 rich 文件。
- 新增真实 media-only 证据：先保存带 image block + asset ref 的 rich document，确认 `available`，再删除整个 `card_<id>` 目录；Card body 为空且状态为 `missing`，full editor 仍显示中性 notice。共享 `objects` asset 在删目录前、删目录后及 UI 验证后均存在，证明测试只模拟 card-owned document 丢失。fresh empty plain Card 同样显示相同中性事实。
- production Gate 的空白双击改为显式 `PointerDeviceKind.mouse + kPrimaryMouseButton` 两次 down/up，继续通过真实 route、inline Domain title/body、右键“展开查看”进入 full editor。
- 新增 empty/media exact：`1/1 PASS`；rich-editor 整文件：`8/8 PASS`；显式 desktop mouse production exact：`1/1 PASS`。changed-file analyze 再次只输出 `Analyzing 3 items...` 后 60 秒无终态，已中止且未重复；critical fixes：`3/3 PASS`；`git diff --check`：PASS；无残留测试进程。

## 第十一轮：Windows 内嵌编辑与单调 rich evidence

- 实现提交：`f740782385967fc9eb527c508bb25c1813529963`。白板进入内嵌编辑后，画布祖先快捷键表只保留 Escape；Delete/Backspace、Ctrl+A、方向键、Shift+方向键、Ctrl+Z/Y 因而交还原生 TextField。Escape 仍保存并退出；退出后单击选中 BoardItem，再按 Delete 仍走 `remove_placement` 且保留 Card。
- `CompactCardEditor` 只在 embedded rich editor 子树加局部 `ScrollConfiguration.copyWith(scrollbars:false)`。Windows Material 自动滚动条不再可见，连续 TextField 与内部 Scrollable、选择和滚动仍保留；全局 ScrollBehavior 未修改。
- fresh plain Card 的 `missing` 是合法未知状态，full editor 静默显示 canonical body，不再呈现中性 notice。`corrupt` / `stale` 的既有可见提示、只读与资源保护不变。
- 经安全审查拒绝 Card `presentation` marker：snapshot save / Undo 的旧 Card 全量 upsert 会清除或回放 marker，事务外 metadata read 还会形成 lost update。最终采用 schema 无关且单调的 `kv_store` 正向证据：bucket `whiteboard.rich_text_materialization`，全局 key `whiteboard.rich_text.materialized.v1:<cardId>`，value 严格校验 `schema_version:1`、exact `card_id`、`card_created_at_ms`。坏 JSON、错 bucket、未知版本或 createdAt 不符均 fail closed 为无证据。
- evidence 只在 `saveRichText` 的文件写成功后写入；Card projection 与 KV 在同一个 Drift transaction 内基于最新 Card 更新。test-only fault point 覆盖 projection 后、KV 前异常，两者同时回滚；文件按现有 stale 规则诚实隔离。`updateCardMetadata` 的 Card 重读已移入它自己的 transaction，受控 tag/rich 并发不丢 tag、title/body 或 evidence。create、tag-only、import、DriftStore snapshot save、persistent Undo 都不创建 evidence；snapshot save 与 Undo 也不删除已有 evidence。
- 读取仅在真实 rich load 得到 `missing` 时查询 KV，不扫描目录、不回填 legacy、不扩散到 Card 字段或 AI Runtime。`missing + evidence` 显示“曾保存过富文本版本，但当前文件不可用；格式或媒体内容可能缺失”；`missing + no evidence` 静默。soft delete/restore 自然保留 KV，createdAt 绑定防未来 ID 复用。

### 第十一轮测试与验证

- 新增 production screen 真实 mouse double-click + focused TextField gate，覆盖编辑态键盘归属、Escape save/close、fresh full editor 无 notice、退出编辑后 Delete 只移除 BoardItem；新增 Windows scroll behavior 下局部无 `RawScrollbar` 且 TextField/Scrollable 仍工作的组件 gate。
- repository/screen tests 覆盖 fresh/tag-only 无 KV、rich save 后文件/projection/KV 与 repository reopen、删除 card-owned rich 目录后 evidence warning 且 shared asset 保留、坏 KV/createdAt mismatch fail closed、事务 fault rollback、受控 tag/rich 并发、legacy absent-evidence unknown/silent、corrupt/stale 不退化。domain facade restart/Undo 测试额外守门 DriftStore snapshot save 不创建/删除 KV。
- `dart format`：9 个改动文件全部完成，最终 `0 changed`。直接 `dart analyze <file>`：4 个生产文件与 5 个测试文件逐文件均 `No issues found!`。
- `powershell -File scripts/verify_critical_fixes.ps1`：`3/3 PASS`；`git diff --check`：PASS。
- Flutter runner 在本 Windows worker 上仍出现零输出挂起：先前 compact exact 在 180 秒、combined compact + production 在约 180 秒均被中止；提交前 repository 单文件在 30 秒零输出后按主窗指令提前中止。以上均明确记为**未验证**，没有伪报 PASS，且终止后确认无残留 `dart` / `flutter` / `flutter_tester` 进程；W0 集成环境需逐文件复跑新增 gates。
- 未执行实际 Windows GUI 真人验收、build、install、push 或发布。

### 第十一轮兼容限制

- marker absent 只表示“没有正向证据”，绝不能解释为“从未富文本化”。历史上已保存过 rich document 但没有本版 KV evidence 的 Card，如果文件后来丢失，仍会按 unknown/silent 处理；当前无法无启发式地补告警，留给未来显式迁移或更强恢复方案。
- DB-only backup 若包含本版 KV evidence 而缺少 rich 文件，会在恢复后明确告警；旧备份没有 evidence 时仍受上述兼容限制。Memory V3 的物理删除路径可能留下 orphan KV evidence 与 rich 文件；createdAt 绑定只防未来 Card ID 复用产生假阳性，不负责回收。未来统一删除协调器必须显式清理 KV 与 card-owned rich 文件。

## 第十二轮：抵抗 EditableText scrollbar 覆盖

- 实现提交：`5d69636d5bdb5836a88330f191b13d3d3b882173`。W0 在可写 Flutter SDK cache 的沙箱外复跑发现第十一轮普通 `ScrollConfiguration.copyWith(scrollbars:false)` 仍会被多行 `EditableText` 内部再次调用 `copyWith(scrollbars:true)` 覆盖，embedded 子树实际生成 `_MaterialScrollbar`。
- `CompactCardEditor` embedded 子树现使用 `_EmbeddedScrollbarFreeScrollBehavior`：`buildScrollbar` 始终原样返回 child，且自身 `copyWith` 继续返回同类 wrapper，因此后代无法重新打开 scrollbar。其余 platform、physics、drag devices、multitouch strategy、overscroll、keyboard dismiss、velocity tracker 与 pointer-axis modifiers 全部委托给当前祖先 behavior；未改全局策略、EditableText 或滚动能力。
- 组件 gate 继续以 `widget is RawScrollbar` 捕获包括 `_MaterialScrollbar` 在内的真实 scrollbar，不绑定 Flutter 私有 runtime type。断言 embedded 为 0、外部全局 scrollbar 为 1，同时保留内部 Scrollable 可滚及 Ctrl+A 选择验证。
- 沙箱外精确命令 `D:\flutter\bin\flutter.bat test --no-pub --reporter expanded test\whiteboard_canvas\compact_card_editor_test.dart --concurrency=1`：`5/5 PASS`，此前红灯的 Windows embedded scrollbar 用例为第一个通过项。
- `dart analyze lib/ui/whiteboard_canvas/widgets/compact_card_editor.dart` 与对应测试：均 `No issues found!`；formatter 最终 clean；critical fixes：`3/3 PASS`；`git diff --check`：PASS。未执行 GUI 真人验收、build、install、push 或发布；第十一轮 KV evidence 未修改。

## 第十三轮：test/docs 最终收口

- test-only 提交：`edfe23ee1a1ee156d5d260659d681a375b15e275`。production route 在返回画布后先等待 route transition 完整 settle，再通过生产 `ClearSelectionIntent` 明确清空 selection；测试定位真实 `GestureDetector(onTap)` interactive child，断言主体中心 hit-testable，以 primary mouse `tapAt` 点击，并在 Delete 前断言 `selectedItemIds == {itemId}`。不再沿用编辑前 selection，也没有 `warnIfMissed:false`。
- 原 hit-test warning 是测试过早命中返回动画：仅等 `ModalRoute.isCurrent` 时 keyed card rect 为 `(343.8, 310.0)–(707.8, 590.0)`，主体中心 hit path 只有 canvas `RenderPointerListener/RenderCustomPaint`；`pumpAndSettle` 后真实 interactive rect 为 `(518.0, 310.0)–(882.0, 590.0)`，中心 `(700.0, 450.0)` 的 path 包含 card `RenderPointerListener + RenderSemanticsGestureHandler`，selection gate 通过。因此未修改生产点击层。
- rich/tag 并发测试的 fault-point `entered.future` 与最终 `Future.wait` 都有 2 秒 timeout；release 由 `try/finally` 和 `addTearDown` 幂等 complete，并有有界 future drain，未来 fault point 不到达或中途失败会形成明确红灯而非无限挂起。
- `resolveCurrentDocument` 与 `listCards(loadDocuments:true)` 现在和 `getCard` 一样，分别覆盖坏/错配/无 evidence 时 missing+false，以及删除已物化文件后的 missing+true；三条公共读取入口均有正反 gate。
- 沙箱外 exact tests：production mouse/edit/select/Delete `1/1 PASS`；rich/tag concurrency `1/1 PASS`；bad/mismatched evidence public reads `1/1 PASS`；legacy unknown + evidenced missing public reads/UI `1/1 PASS`。三个改动测试文件 direct analyze 均 `No issues found!`；formatter clean；critical fixes `3/3 PASS`；`git diff --check` PASS。

### 第十三轮仍存 P2 / 备份边界

- 两个 full-rich writer 并发，或 rich save 与 `linkSource` / `softDelete` / `restore` 并发，仍可能在文件先写、DB 后事务的边界诚实落入 `stale`；第十一轮只闭环 tag/full-rich 的受控 lost-update，不应扩写成所有 writer concurrency 已解决。
- 当前完整备份不包含白板 rich root；KV evidence 能让 DB-only 恢复后的 missing 可见，但不能恢复 rich document 或 assets。本轮未修改备份系统，也不声称文件恢复闭环。

## 第三轮极窄修补

- 只读事实询问现在 fail closed：`是什么`、`在哪里/在哪儿`、`有哪些/多少/有几/几`、`什么内容/标签/位置`、`多大/多宽/多高` 等模式在 capability 提取前直接归类为 consultation，不会因裸 `内容/位置/标签/大小` 获得写授权。
- 明确写入语法具有窄优先级：`把/将…改成/设为/移到/调整` 及字段后接 `修改为/设置为/移动到/调宽/调高/变宽/变窄` 仍可授权；没有硬编码四个完整阻断句。
- 表驱动测试逐句覆盖 W0 的四个反例，并增加同类问句与 `内容改成/位置移到/标签设为` 正例。

## 第二轮关键设计

- `WhiteboardDomainCommandFacade` 接受同库泛型 transaction runner。生产 coordinator 传入 `WhiteboardDriftStore.db.transaction`；execute 在同一个 Drift 外层事务内完成 running action 插入、executor snapshot save、exact-one terminal action update，Undo 对称。数据库事务成功后才发布 executor applied/undo cache 与 facade binding；事务异常会撤销 prepared cache 与 permission commit/reservation，同 batch 可真实重试。
- 正常失败 receipt 仍提交一条 terminal failed action，board 不变；基础设施异常（terminal update 前/后、零行、permission commit、事务体末崩溃）全事务回滚，不留 running/orphan。`PersonaChatService.updateWorkbenchActionMessage` 强制 affected rows 等于 1。
- 同一 AppDatabase 的 store save/outer transaction 串行化，manual 与 Runtime 均携带持久 baseline hash。并发测试让两个旧 baseline 同时进入，结果严格为一笔 applied、一笔 conflict，不互相覆写。surface lock 改为引用计数；显式保存/退出会等待 manual commit，第二次 nudge/手势被 readonly 拒绝。
- Domain commit 失败后若持久 snapshot reload 也失败，route 进入 `reconciliation-required`：继续 readonly，Ctrl+S/退出不再导出 VM 预览，只允许重试真实持久 reload；提示不再宣称“已恢复”。
- Runtime host 先根据真人祈使决定 capability、总命令数与每 capability 数量。默认/“一张” create 上限为 1；模型 payload 超量在 facade 前拒绝。咨询、查看和能力提问零授权，明确委托仍可用；补齐宽度/高度/变宽/变窄等 resize 词形及否定语义。
- prompt 不拼接 boardName；只输出单行、JSON 转义的 `untrusted_whiteboard_context`，明确它是数据而非指令。恶意换行、伪 closing delimiter 与 item id 均不能逃出 JSON 字符串。
- `productionComposition` 的 whiteboard factory 具有真实 production 默认；无 factory 的测试仍观察到动态工具注册。`createAppRouter` + `AppDatabase.setTestInstance` 的零注入真实 route 自动产生 manual port。Persona 桌面普通发送先落真实 user row，再把该 row id 作为 action evidence 传入 coordinator。
- Runtime deadline/stop 在 facade 前可返回零写入 interruption；进入 durable commit 后返回有界显式 `whiteboard_commit_pending`，画布保持锁定，后台 Future 不被 detach。最终 receipt 后才 reload/unlock；save 或 reload 永久 stall 时 lock 保持，不能声称失败后静默突变。

## 自动验证

- 第七轮按要求未启动 Runtime 或大套件；格式化与静态 diff 审查通过，`verify_critical_fixes.ps1`：3/3 PASS，`git diff --check`：PASS。代码增量仅 Runtime consultation 与对应表驱动测试，共 13 insertions。

- 第六轮 Runtime 单文件按要求只运行一次；60 秒内零测试输出，已中止且确认无后台 dart/flutter 进程。未运行大套件或 analyze，W0 集成环境需复跑。
- 第六轮 `verify_critical_fixes.ps1`：3/3 PASS；`git diff --check`：PASS。代码增量仅 Runtime intent grammar 与对应表驱动测试。

- 第五轮 Runtime 单文件两次均在 60 秒内没有输出测试用例终态，已中止且确认无后台 dart/flutter 进程；未按约束扩大到 route/widget/analyze，W0 集成环境需复跑该单文件。
- 第五轮 `verify_critical_fixes.ps1`：3/3 PASS；`git diff --check`：PASS。代码增量仅 Runtime intent 与对应表驱动测试，共 17 insertions。

- 第四轮 Runtime 授权/scope：`10/10 PASS`。
  - `flutter test --no-pub test/data/workbench_ai/whiteboard_runtime_domain_tool_test.dart --concurrency=1`
- 第四轮 Persona 真实 send-path mutation gate：`1/1 PASS`。
  - `flutter test --no-pub test/ui/character/widgets/persona_chat_screen_test.dart --plain-name "desktop send button passes its persisted user row to production connector" --concurrency=1`
- 第四轮 production route/conversation 最小回归：`25/25 PASS`。
  - `flutter test --no-pub test/ui/whiteboard/whiteboard_production_domain_route_test.dart test/data/workbench_ai/workbench_conversation_coordinator_test.dart --concurrency=1`
- 第四轮 changed-file analyze 在只输出 `Analyzing ...` 后超过 60 秒，已按 W0 指令中止且未重启；W0 集成环境需复跑。`verify_critical_fixes.ps1`：3/3 PASS；`git diff --check`：PASS。

- 第三轮 Runtime：`9/9 PASS`。
  - `flutter test --no-pub test/data/workbench_ai/whiteboard_runtime_domain_tool_test.dart --concurrency=1`
- 第三轮最小 production route/conversation 回归：`25/25 PASS`。
  - `flutter test --no-pub test/ui/whiteboard/whiteboard_production_domain_route_test.dart test/data/workbench_ai/workbench_conversation_coordinator_test.dart --concurrency=1`
- 第三轮 changed-file analyze 两次均在打印 `Analyzing ...` 后 60 秒无终态，已按 W0 要求中止且未留后台进程；应由 W0 集成环境复跑。第三轮 diff 仅 28 insertions/2 deletions，`git diff --check` PASS，critical fixes 3/3 PASS。

- 原子/重启 facade suite：`9/9 PASS`。
  - `flutter test test/data/whiteboard/domain_commands/whiteboard_domain_command_facade_test.dart --concurrency=1`
  - 使用真实临时 SQLite 文件 close/reopen；覆盖六类 execute→重启→Undo、create Undo 的 Card 软删除、execute/Undo terminal update 回滚、零行、permission commit、transaction-end crash、同 batch retry、manual/runtime stale-baseline race。
- Runtime production suite：`9/9 PASS`。
  - `flutter test test/data/workbench_ai/whiteboard_runtime_domain_tool_test.dart --concurrency=1`
  - 覆盖六 shape 注册/派发、默认 production 注册 mutation gate、Persona user-row evidence、咨询/否定/resize 词形、host 限额、prompt 注入、失败/冲突/幂等、stop pending、deadline save stall、重启 Undo。
- route/production UI suite：`18/18 PASS`。
  - `flutter test test/routing/whiteboard_routes_test.dart test/ui/whiteboard/whiteboard_production_domain_route_test.dart --concurrency=1`
  - 覆盖 `createAppRouter` 零注入 manual port mutation gate、真实 UI commit 锁、save+reload 双失败后的 Ctrl+S/退出/第二次 nudge 零旁路。
- P4/conversation/action-card/Persona 串行组合：`66/66 PASS`。
  - facade、whiteboard coordinator/surface、conversation coordinator、action projection/card、manual port、Runtime tool、production route、Persona service 共 10 个测试文件，`--concurrency=1`。
- 白板/Persona 邻接串行组合：`106/106 PASS`。
  - canvas product loop、direct interactions、interactions、Persona screen、whiteboard routes 共 5 个测试文件，`--concurrency=1`。
- changed-file analyze（除已有基线告警的大型 `persona_chat_screen.dart`）：首次发现并修正测试 const lint，最终相关生产/测试文件 `No issues found!`。Persona 文件单独仍为既有 19 项 warning/info，本轮新增 helper/调用区无 analyzer issue。
- `powershell -File scripts/verify_critical_fixes.ps1`：3/3 PASS；`git diff --check`：PASS。

## 恢复、冲突与失败证据

- execute terminal update 后抛错：reopen 后 board hash、action、Undo 全无分裂；相同 batch 可成功重试。
- Undo terminal update 后抛错：reopen 后 board 仍为 applied 状态、action 仍 completed、`canUndo == true`；再次 Undo 成功。Undo 后再 reopen 保持 undone 且不可再次 Undo。
- 六命令至少一次通过真实 SQLite reopen 后恢复 Undo；remove placement 只删 BoardItem，Card 仍存在；create Undo 只把新 Card 软删除。
- stale expected hash 的 manual/runtime race 最多一笔 applied，另一笔 conflict；保存失败与事务基础设施异常不覆写基线、不留 running action。
- durable stop/deadline 有界返回 pending；测试在 save gate 持续未 release 的有界观察窗内确认画布仍锁且无虚假失败结论，随后 release 做清理时 action/receipt 落地、reload 后才解锁。

## 边界、风险与 W0 后续

- 未执行最终 Windows build，按任务约束留给 W0 唯一候选；仍需真人 Gate：六类 UI 入口、普通桌面对话、完整退出/重开 Undo、undo 后再重开及可见 reconciliation/pending 提示。
- production 的 `WhiteboardCanvasScreen` 唯一调用点是 `WhiteboardCanvasRouteScreen`，零注入 route 自动带 Domain port。为保留 fixture，显式注入 store/repository 且不注入 host 的测试组合仍允许旧 adapter fallback，不属于桌面 production composition。
- durable pending 没有新增 schema；其状态由 surface readonly/引用计数锁和最终 reload 管理。进程在 pending 期间被操作系统强杀时，DB 事务自身决定全提交或全回滚，重开依赖 action/receipt hydration；没有跨进程“正在核对” UI 行。
- 图片导入、旋转、group/edge/viewport、P5/P6/W4/Gate 1A 不在本轮六命令范围；未 build_runner、依赖升级、push 或发布。

## 可供 W0 写入状态页的短片段

> P4 production reachability repair 第七轮已补齐完成状态确认语法：`已/已经/完成/成功/好了/了 + 吧/对吧/是吧` 统一 fail closed，普通“移动到右边吧”祈使仍精确 move。代码 `ab7fab26f0c5d029e94438443abaedd0c85c4cf9`，critical 3/3、静态 diff 与 diff check 通过；本轮按要求未重启 Runtime 测试，待 W0 集成前统一复跑并完成 Windows 真人 Gate。

> P4-R 真人 Gate 返修已恢复同一卡面透明连续 title/body 编辑与真实空白双击入口；manual title/body 同 receipt，active reload 不跳 viewport。候选 C 以当前 DB Card 验证 rich document，stale 时隐藏但保留文件/assets，Undo exact-match 后恢复。代码 `b0b9f768`；production route 4/4、Runtime 10/10、rich screen 5/5、其余定向 9/9、changed-file analyze clean、critical 3/3、diff-check PASS。剩余 P2 债仅为跨窗口 full-rich writer optimistic conflict；未执行最终 Windows build。

## P4-R W1：Runtime 可见落点、legacy rich 兼容与 Card Library 持久放置

### 交付边界与提交

- worker 分支：`codex/whiteboard-w1-p4r-runtime-card-library`；精确基线：`v3-lab@7fa6cbb9e44fe1771aae44c579d5e3a2f9e393f1`。
- 原子代码提交按顺序为 `5f515512 fix(whiteboard): keep runtime cards visible and storage-safe`、`4d533f2c fix(whiteboard): persist card library placement`；W0 应按此顺序集成。代码范围为 `5f515512^..4d533f2c`。
- 未读写真实用户数据库；未做 schema migration、依赖升级、生成文件、真实数据修复、Windows 候选构建、push 或发布。Goal、Roadmap、`I_PROJECT_STATE.md`、`DEVLOG.md` 均未写。

### Runtime 与存储契约

- Runtime create 的新 Card/BoardItem ID 改为确定性 filesystem-safe 形式 `card_<24hex>_<index>` / `item_<24hex>_<index>`；create 执行边界同时拒绝包含 `:`、`/`、反斜杠、`..` 的新 card/item ID。
- host 授权时记录真实 active `BoardViewport`；payload 同时省略 x/y 时先解析 width/height，再以 `centerX - width / 2`、`centerY - height / 2` 生成左上角，保证默认尺寸与自定义尺寸均以当前可见中心为落点。模型仍不能提供或伪造 board/scope/viewport；x/y 必须成对出现，显式有限数值契约保留。
- `RichTextStorage` 只兼容精确 legacy Runtime 形态 `card:<24hex>:<index>`，投影到独立的 `legacy_runtime_cards/card_<hex>_<index>/rich_text.json` namespace；正常 `legacy_runtime_<hex>_<index>` Card 仍使用原 `card_<id>` 目录，因此两者不会碰撞，也不迁移或改写正常旧目录。
- 任意其他不安全 ID 继续由专用 `RichTextUnsafeCardIdError` 拒绝。repository 只按卡隔离这一精确安全拒绝并降级为可理解的 corrupt document；其他 `ArgumentError`、I/O 与编程错误继续冒泡。测试覆盖反证以及 legacy save/load/delete/reopen/recoverAll。

### Card Library 持久放置契约

- 新增 manual-only `PlaceExistingCardCommand` / `place_existing_card`，Card Library 当前白板的 click 与 drag 均经既有 Domain facade 单写路径落 Card placement，产生 durable action/Receipt，支持后续 move/resize、reopen 与 Undo/reopen；失败时不先改 ViewModel，因此不留幽灵 placement。
- 执行边界要求新 itemId portable safe；被放置 Card 允许 normal safe ID 或精确 legacy Runtime Card ID，因而已存在 `card:<24hex>:<index>` 可被手动放入白板。该 capability 未加入 Runtime tool prompt、schema、shape 或路由；facade 的 Runtime authorize/execute 双层都拒绝 manual-only command。
- 没有保存整个 ViewModel snapshot 的旁路。成功后 route 从持久 surface reload，selection 使用 receipt 返回的新 itemId；失败保持原持久与 UI 状态。

### 自动验证

- 目标组合 5 文件：`86/86 PASS`。文件为 `rich_text_storage_test.dart`、`unified_card_repository_test.dart`、`whiteboard_domain_command_facade_test.dart`、`whiteboard_runtime_domain_tool_test.dart`、`whiteboard_manual_command_port_test.dart`。
- 邻接回归 5 文件：`33/33 PASS`。文件为 `whiteboard_production_domain_route_test.dart`、`card_library_repository_test.dart`、`card_rich_text_repository_screen_test.dart`、`compact_card_editor_test.dart`、`compact_card_editor_projection_test.dart`。
- changed-file analyze：15 items，`No issues found!`（4.7s）；`scripts/verify_critical_fixes.ps1`：`3/3 PASS`；`git diff --check`：PASS。
- Windows sandbox 不允许 SDK 写 `D:\flutter\bin\cache\lockfile`，上述 Flutter 验证按授权在受控提升权限下运行；没有删除或手工改写 SDK lockfile。依赖文件未改变，测试/analyze 均使用现有依赖与 `--no-pub`。
- 旧 UI 测试在右键菜单关闭后直接送 Delete 的 CallbackShortcuts 焦点链不稳定；W0 已在未改白板代码的 `7fa6cbb9` 上复现同类失败，确认非本轮生产回归。最终测试先确定性选择再验证右键移除，并在 fresh focused canvas 以真实 tap + selection 断言验证键盘 Delete；未为基线焦点问题扩大生产改动。

### 风险、真人 Gate 与恢复

- W1 没有运行真实生产数据库 Gate。W0 仍需在唯一候选上复验：Runtime create 的安全 ID、active viewport 可见中心、surface reload 与全局 `listCards(loadDocuments:true)`；Card Library click/drag receipt、即时 move/resize、完整退出重开、Undo 后再重开。
- 本轮不做 DB ID migration。legacy 逻辑 ID 原样保留；兼容仅改变其 rich 文件路径投影。若未来撤回代码，正常 Card 目录完全不受影响；本轮也没有向真实 legacy namespace 写文件。
- 恢复时在集成分支按新到旧 revert：先 `4d533f2c`，再 `5f515512`。若候选期间已为 legacy Runtime Card 新写 rich document，撤回 `5f515512` 会使独立 namespace 暂时不可读，但文件不会被删除；恢复该提交即可重新读取。

### W0 双审计后的 test-only P2 证据补强

- test-only 提交：`8982b9a5 test(whiteboard): prove Card Library production placement`；只修改 facade 与 production route 两个既有测试文件，生产代码、schema、依赖、生成文件与真实数据均未改变。
- forged Runtime grant 测试与既有 forged title 对称：`PlaceExistingCardCommand` 的 selected card/item targets、capability 与 operation count 全部伪造成精确匹配，`executeRuntime` 仍在 action/transaction 前以 `place_existing_card is manual-only` 拒绝。持久 action 为空、snapshot hash 不变、目标 item 不存在、`canUndo == false`，因此没有第二种 target mismatch 拒绝理由。
- production route 使用临时文件 SQLite，真实驱动 `WhiteboardCanvasRouteScreen → _RouteManualCommandPort → WhiteboardManualDomainCommandHost → Facade/Drift → route reload → ViewModel`。快捷 Card Library click 后 placement 真实可见且选中，action 为 completed 且有 Undo token；随后真实 ArrowRight move、resize handle drag 均持久成功。Card Library drag 在同一组合测试稳定进入相同整链并产生第二个 placement；卸载 route、关闭 DB、以同一 SQLite 文件重建 DB/repository/store/coordinator/host 后，两次 placement 与 move/resize geometry 均重新可见。
- 失败证据在另一份临时文件 SQLite 上把 active surface 切换到另一 owner，再从真实 Card Library row 点击；host 返回 surface-changed unavailable，UI 显示失败提示，同时 ViewModel boardItems、持久 boardItems 与 action rows 全为空，没有幽灵 placement。没有直接调用私有函数，也没有 mock 掉 host、facade 或 Drift。
- 新增 exact：`3/3 PASS`；原目标组合增加 forged test 后为 `87/87 PASS`；原邻接组合增加两条 production route test 后为 `35/35 PASS`。两个改动文件 changed-file analyze：`No issues found!`（2.5s）；critical fixes：`3/3 PASS`；`git diff --check`：PASS。
- 本 follow-up 未读取或修改真实用户数据库，未 build、install、push 或发布。恢复只需 revert 本 test-only commit 及其 handoff commit，不影响任何生产持久状态或运行时行为。

## P4-R15 W1：manual reload selection 与画布焦点交接

### 基线、边界与实现

- 隔离 worktree 精确基线：`884dcd801dbda5af721bbe6610c5bcd89fac9abb`；本轮只修改 production route/manual UI 边界、画布焦点交接、对应 production widget 回归与本 handoff。未改 Card / BoardItem / DomainCommand / Receipt / Undo 语义，也未改 schema、数据库迁移、permission/capability、Runtime 六命令、rich-text 或 Card Library 全局数据语义。
- `WhiteboardCanvasViewModel.loadFromSnapshot` 继续默认清空 selection。route manual port 在 host lock/reload 前捕获当前 selection；只有 receipt 为 applied、当前 surface owner/board 仍匹配、route 未进入 reconciliation-required、VM 可写时，才把“已持久 reload 后仍存在”的 item IDs 重新选中。失败、remove 后 item 已不存在、reload 核对失败或 surface/route 已切换时均不恢复陈旧 selection。
- `WhiteboardCanvasScreen` 现在显式拥有并释放画布 `FocusNode`。真实卡片主鼠标选择、增量选择、marquee 成功，以及 placement / move / resize 成功后会安全 `requestFocus`；readonly、页面已销毁或 embedded editor 正在编辑时不会抢焦点。编辑态 shortcut map 仍只接管 Escape，Delete/Backspace/Ctrl+A 等文本键继续属于输入框。
- production Card Library click 的 applied placement 经真实 reload 后恢复新 BoardItem selection 与画布 primary focus；紧接硬件 ArrowRight、第二次连续 ArrowRight 分别产生真实 `move_placement` completed action，x 精确累计 `+8`、`+16`，两次 reload 后 selection/focus 均保留。drag placement 与 resize 的既有路径也继续保留 surviving selection/focus。
- production 鼠标/Delete 回归挂载真实 `DesktopPersonaChatView` 与 `desktop_chat_input`：composer 取得 primary focus 后，主鼠标点击画布卡片会把 primary focus 明确交回画布，随后 Delete 只产生一条 `remove_placement`，BoardItem 消失而 Card 仍存在；embedded editor 内 Delete/Backspace 继续只编辑文本。

### 自动验证

- production/manual/editor/direct 组合：`38/38 PASS`。命令覆盖 `whiteboard_production_domain_route_test.dart`、`whiteboard_manual_command_port_test.dart`、`compact_card_editor_test.dart`、`whiteboard_canvas_direct_interactions_test.dart`，`--no-pub --concurrency=1`。
- R14/Domain 邻接组合：`40/40 PASS`。命令覆盖 `card_library_repository_test.dart`、`whiteboard_domain_command_facade_test.dart`、`card_rich_text_repository_screen_test.dart`、`compact_card_editor_projection_test.dart`，`--no-pub --concurrency=1`。
- 真实桌面 composer → 鼠标卡片 → Delete exact：`1/1 PASS`；Card Library click → 即时 ArrowRight → 第二次 ArrowRight 在上述 production route 组合内通过。
- changed-file analyze：3 items，`No issues found!`；`scripts/verify_critical_fixes.ps1`：`3/3 PASS`；`git diff --check`：PASS。

### 风险、真人 Gate 与恢复

- 未运行真实 Windows GUI、真实用户数据库、build、install、push 或发布。W0 仍需在唯一候选上按 R15 真人现场复验：快捷库单击刚出现即连续两次 ArrowRight；聊天 composer 返回画布后真实鼠标点卡再 Delete；离开/切换白板期间不恢复旧 selection。
- 自动测试证明 primary focus 为画布显式 FocusNode，并覆盖 surface switch、commit/reload failure 与 applied remove 的 fail-closed selection；未模拟窗口失焦、系统级 IME 或不同 Windows 键盘驱动的硬件差异。
- 本轮不修改父 Goal、Roadmap、`I_PROJECT_STATE.md` 或 `DEVLOG.md`。回滚只需 revert 本轮提交；没有数据迁移或真实用户数据补偿步骤。

### 只读审计 P2：非空 selection 的 in-flight surface switch 证据

- test-only follow-up 只增加一条 production route widget 回归与本 handoff，生产代码零修改。真实链路为 `WhiteboardCanvasRouteScreen → route manual port → WhiteboardManualDomainCommandHost → Domain facade/Drift`，没有调用私有恢复函数，也没有 mock Host、Facade 或 Receipt。
- 旧 route 先以真实鼠标选中 existing `item_surface_selection`，再发送硬件 ArrowRight。route port 在 host lock 前捕获非空 selection；`_GatedStore` 的真实 save gate 证明命令已进入 Facade 持久提交，而 production readonly lock 已按既有安全语义清空旧 route selection。提交执行中把 active surface 切换为另一 owner/`board_switched`，release 后 action 仍为 completed `move_placement`、持久 x 从 `-90` 精确变为 `-82`，旧 route 解锁后 selection 保持空，没有被 applied receipt 错误恢复。
- exact 新增用例：`1/1 PASS`；完整 `whiteboard_production_domain_route_test.dart`：`7/7 PASS`；changed-file analyze：`No issues found!`。critical fixes：`3/3 PASS`；`git diff --check`：PASS。
- 未改 Card / BoardItem / DomainCommand / Receipt / Undo / schema 语义，未读取或迁移真实用户数据，未 build、install、push 或发布；该 follow-up 可独立 revert，不影响前一提交 `245af967a845ade68d4542f7fc02ac47a6ef2094`。

## P4-R16 W1：Runtime 混合否定授权解析

### 基线、根因与交付

- task/thread：`01a04d7d-d383-79b2-a7ce-865f80761452`；隔离 Worktree：`.codex/worktrees/8ad3/memex`；分支：`codex/whiteboard-w1-p4r16-runtime-authorization`；精确基线：`a36e523605bd16e0ae0329cb2521f8348fa3b0e5`。
- 代码/测试提交：`4a15faad8b2aceb41a6963d1109176b220752127` (`fix(whiteboard): scope runtime negation by capability`)。生产只改 `whiteboard_runtime_domain_tool.dart`，测试只改其既有 Runtime 测试。
- 根因为 `_capabilitiesFromExplicitRequest` 在正向能力提取前以整句 `_containsNegatedWhiteboardWrite` 短路；真人原句尾部“不要改标题、标签、位置或大小”因而把前面明确的正文写授权也清空。同时，标题字面量「Runtime 创建验收 R14」中的“创建”不应被当成 create 意图。

### 实际支持边界与证据

- 授权现在先从剔除 `「」` / `“”` 字面量的用户文本中提取正向 capability，再以中英文逗号、句号、叹号、问号、分号或换行为边界，从“不需要 / 不必 / 不想 / 不希望 / 不要 / 别 / 不许 / 禁止 / 请勿 / 无需 / 不用 / 不能 / 不可以 / 不准”引导的局部明确否定子句中扣除 create/body/labels/move/resize/remove 对应能力。
- exact 真人原句的 `prepareAuthorization` 非 null，`allowedCapabilities == {edit_card_body}`，`maxOperationCount == 1`，per-capability limit 也精确为 1；单独“不要修改白板卡片正文”继续返回 null。
- 真实跨界测试从 `sendPersonaDesktopConversationEntry` 持久本轮 user row，进入 `WorkbenchConversationCoordinator.productionComposition`，分发 canonical `whiteboard_domain_commands/edit_card_body`，最终经真实 harness Facade/Drift 落一条 completed Receipt/action。正文变为“R15 Runtime 正文编辑通过”，title/tags/x/y/width/height 与执行前精确相同；action evidence 精确指向该持久 user row。
- 同一 exact 原句下，模型 payload 混入 `set_card_labels` / `move_placement` / `resize_placement` 时，在 Facade/action 之前以 `whiteboard_operation_limit_exceeded` 拒绝；正文、标题、标签、geometry 全部不变，action/Receipt 为空，无部分写入。

### 自动验证、契约影响与未完事项

- Runtime 专项全文件：`14/14 PASS`；相邻 conversation coordinator：`23/23 PASS`；两个改动文件 analyze：`No issues found!`；critical fixes：`3/3 PASS`；`git diff --check`：PASS。
- 新隔离 Worktree 初始无 `.dart_tool/package_config.json`；离线 `pub get` 在完成本地 package index 后因 Pub cache `active_roots` 目录报错退出，未改 `pubspec.lock`。使用已生成的本地 index 受控运行后，上述 Flutter 测试均干净通过。
- 共享契约零变更：未改 tool schema、六类 capability、DomainCommand、Card/Board/BoardItem/Receipt/Undo、DB schema、依赖或 UI；未增加 title→ID resolver，仍依赖 host-owned 当前 selection 产生 `selected_card_ids`。
- 未运行真实 Windows GUI、真实用户数据、build/install/push/发布。W0 应审计并选择性集成上述提交，再从最终干净集成基线构建唯一候选，重试 exact 真人句与完整退出/重开/Undo Gate。

### P1 只读审查 follow-up

- 独立代码/测试提交：`2ad8c1349ee4e27918f69d855d790f4af8a100f2` (`fix(whiteboard): cover explicit negation variants`)；在既有 R16 提交之上追加，未改写历史。
- 阻断为否定词族漏掉“不需要 / 不必”，使 negative-only move 仍获得授权；同时若不把逗号作为局部否定边界，会错误扣除混合句逗号后的正向 body 授权。修复还将同类明确意愿否定“不想 / 不希望”收入同一安全词族。
- 精确回归证明：“不需要移动白板卡片”、“不必移动白板卡片”、“不想移动白板卡片”、“不希望移动白板卡片”均为 null；“不需要移动白板卡片，编辑正文”与“不必移动白板卡片，编辑正文”均精确只授权 `edit_card_body`，`maxOperationCount == 1`。
- 最终复验：Runtime 全文件 `14/14 PASS`，conversation coordinator `23/23 PASS`，目标 analyze `No issues found!`，critical fixes `3/3 PASS`，`git diff --check` PASS。exact R15 仅 body、negative-only、引号内“创建”不扩权、混入 labels/move/resize 整单零写入等原回归全部保持。

## P4-R17 W1：当前白板唯一标题目标作用域

### 基线、范围与实现

- task/thread：`01a04de1-94ba-7c63-b685-0e88301b9468`；隔离 Worktree：`.codex/worktrees/8dd4/memex`；分支：`codex/whiteboard-w1-p4r17-title-target-scope`；精确基线：`66017099e54ac6015949eb2419bf9a92e1dc7d55`。未吸收并行心率提交 `012c5eb5`。
- Runtime 授权准备在 surface flush 成功并重新核对 owner/board 后，从该次持久 `WhiteboardSnapshot` 只沿“当前 board 的 BoardItem → Card”解析 `当前白板上/白板上标题为「…」的卡片`。标题严格相等、最多 500 runes，空白、控制字符、语形残缺、多目标 marker 均 fail closed。
- selection 与 host-resolved target 在 prompt/context 中分字段呈现；显式标题目标的执行 scope 只取 resolved target，不与无关 selection 并集。无显式既有目标语形时继续使用原 selection-only 契约。
- 当前板 0 个匹配返回 `whiteboard_title_target_not_found`；多个不同 Card 同名返回 `whiteboard_title_target_ambiguous`，均不向模型开放候选。相同 Card 多 placement 时只开放去重后的 Card ID；item target 留空并标记 placement ambiguity，因此 body/labels 可执行，move/resize/remove 整体拒绝。唯一 placement 才开放其 item ID。
- resolver 只在存在 body/labels/move/resize/remove 等 target-dependent capability 时启用，并要求既有目标语形。create-only、新卡“标题为”以及正文 literal 中的 title marker 不进入 resolver；既有 exact R14 create 在空 selection 下保持成功。
- 生产只改 `whiteboard_runtime_domain_tool.dart`；未改 Runtime 六命令 schema、capability、DomainCommand、Card/Board/BoardItem、Receipt/Undo、DB schema、依赖、UI、行动卡、卡片库或全局搜索。

### 自动验证与失败证据

- Runtime 专项全文件：`23/23 PASS`。exact 真人 R15 从 `sendPersonaDesktopConversationEntry → productionComposition` 且 empty selection 发起；测试 Runtime 只从宿主 prompt 读取 resolved Card ID，payload 不预置 `card_a`，最终仅正文改变。
- 同文件覆盖：当前板唯一未选中 Card/placement 成功；卡片库有 Card 但当前板无 placement、另一白板同名、不存在标题、非法/超长标题均拒绝；两个不同 Card 同名 ambiguity 拒绝；同一 Card 多 placement 的 body+labels 成功且全部 geometry 不变、placement 请求拒绝；无关 selection 与伪造 ID 不扩权；surface race、R16 payload 混入第二能力/命令均零部分写。
- 主窗提前指出的 create P1 已关闭：exact R14 create 空 selection 成功；新卡标题 literal 与正文 title literal 均不触发 existing-target resolver。原 selection-only、逐 capability 否定、operation limits、hash/幂等/保存失败/重启 Undo 回归在完整 Runtime 文件中继续通过。
- 相邻 `workbench_conversation_coordinator_test.dart`：`23/23 PASS`；两个改动文件 analyze：`No issues found!`；critical fixes：`3/3 PASS`；`git diff --check`：PASS。
- 隔离 Worktree 初始无 `.dart_tool/package_config.json`；离线 `pub get` 已生成可用索引，但最终因 Pub cache `active_roots` 目录不存在返回非零。`pubspec.lock` 未改变；测试均以现有缓存和 `--no-pub` 运行。

### 共享契约影响、风险与真人重测

- 共享契约零变更；新增内容只是一次 Runtime turn 的 host-owned 授权 scope 表达与 fail-closed 错误码。未 build、install、读取真实用户数据库、push、merge 或发布；Goal/Roadmap/`I_PROJECT_STATE.md`/`DEVLOG.md` 均未写。
- 自动测试证明 current-board-only 与准备阶段 surface race；仍需 W0 在最终唯一候选重测真实窗口 selection 为空、标题唯一且 Card 已持久 placement 的状态。真人重测句：`把当前白板上标题为「Runtime 创建验收 R14」的卡片正文改成「R15 Runtime 正文编辑通过」。不要改标题、标签、位置或大小。`

### P1 follow-up：同 owner / board 的 surface 重挂

- 首个 R17 提交为 `f026b23b40aa51e5f27790011d768f9348089465`；独立审查随后指出 owner + boardId 不足以证明还是原 surface。follow-up 不改写历史，在授权中保存 host 捕获的 surface 实例，并把 flush 后、invoke 初始、parse 后 durable 前与 durable completion reload 四处 gate 全部收紧为实例同一性。
- prepare 的 flush 内以相同 owner + `board_1` 重新 attach 时返回 `whiteboard_surface_changed`，action 为空且 snapshot 不变；授权后、invoke 初始 gate 前同样重挂也零写拒绝；利用第二次 cancellation check 在 parse 后/durable 前重挂仍零写拒绝。
- 已跨 durable save gate 后才同 owner/board 重挂时，旧事务按既有原子语义完成并产生唯一 Receipt；completion 不 reload 或锁定 replacement surface，只解锁旧实例。测试精确断言 replacement reload 为 0、replacement lock 为空、旧 lock 为 `[true, false]`，持久 move/action 各一次。
- follow-up 后 Runtime 专项为 `23/23 PASS`；相邻 coordinator、changed-file analyze、critical fixes 与 diff check 需以最终提交前复跑记录为准。

### P1 follow-up：只在直接命令层解析标题目标

- 独立审查复现正文错指向：selection 为 `card_a`、当前板另有标题为 `Unique Target` 的 `card_target` 时，正文值本身若完整包含 `当前白板上标题为“Unique Target”的卡片`，旧 resolver 会把字面量内部 marker 当成现有目标并覆盖 selection。修复不改写前两笔提交，只追加本轮限定提交。
- host 现在先扫描命令层 quoted-literal spans；成对 `「」`、`『』`、`“”`、`‘’`、ASCII 双引号均作为不透明正文/参数值，span 内完整 target 语形不参与 resolver。游离闭符、未闭合及可识别的同型嵌套歧义 fail closed。ASCII 单引号未纳入，以避免英文 apostrophe 与代码片段误判。
- top-level marker 还必须满足 direct-target 结构：marker 前只允许句首空白及极短 `把/将/请把/请将/请帮我把` 类前缀；marker 前已经出现 selected-object、正文操作、比较或说明子句时返回 `whiteboard_title_target_invalid`，不在 selection 与 title card 之间猜测。
- target match 后必须紧邻对应的窄 canonical 操作短语。body 只接受 `编辑/修改/改写 + 正文/内容` 或 `正文/内容 + 改成/改为/修改为/设为/设置为`；labels、move、resize、remove 同样只接受明确赋值/方向/移除动作。`正文修改后`、`标签修改后`、`大小调整后`、`移动后`、`放大后`、`然后再修改正文` 等说明态均 invalid，零 action/Receipt/写入。
- exact 复现证明：外层 `「…」` 正文完整写入 selected `card_a`，同名 `card_target` 不变；`『…』`、`“…”`、`‘…’`、ASCII `"…"` 表驱动覆盖同样只写 selection。empty selection 下五种 pair 均不解析目标，伪造 `card_target` payload 全部 `whiteboard_target_outside_scope` 且零写。
- 最终 Runtime 全文件：`28/28 PASS`，包含 exact R15 production composition、exact R14 create、五类外层引号、body/labels/move/resize/remove canonical 正向语形、direct-target/canonical-operation 说明态反例与全部 R16/surface-race 回归；相邻 coordinator：`23/23 PASS`。changed-file analyze、critical fixes 与 diff check 以追加提交前最终记录为准。

## P4-R18 W1：相对几何与 Runtime 白板工具路由

### 基线、范围与交付

- task/thread：`01a05185-dbe9-7313-8e2c-d02fd40f051e`；实际模型 / effort：`gpt-5.6-sol / high`；隔离 Worktree：`.codex/worktrees/82ae/memex`；分支：`codex/whiteboard-w1-p4-r18`；精确基线：`2edaf17a3f8bb733e6ac6f54024941267d7f32a4`，开始时 detached HEAD / clean，白板路径与 `1f77633a` 无提交差异。
- 代码 / 测试提交：`9297fd1c775da29d3ded9af9cd38fb867e0440a8` (`fix(whiteboard): expose bounded runtime placement geometry`)。生产只改 `whiteboard_runtime_domain_tool.dart`，测试只改其既有 Runtime 专项；本文随后以独立 docs commit 更新。
- 未改六项 dynamic tool schema、Card / BoardItem / DomainCommand / Receipt / Undo 公共语义、DB schema、依赖、UI、模型默认配置或三分钟 turn timeout；未增加 no-tool fail-fast。

### 相对几何闭环与安全边界

- `prepareAuthorization` 在 flush、持久 snapshot load、owner / board / surface-instance revalidation 后，只为该轮已经授权的 target item 生成 `target_placement_geometry`：`item_id/x/y/width/height`。字段与 `expectedSnapshotHash` 来自同一个 authoritative snapshot，按 item ID 排序，受既有 64-ID / 16 KiB prompt 上界约束，并继续位于整体 `untrusted_whiteboard_context` 内。
- 几何只在本轮包含 move / resize capability 时出现；exact-title 仍只从当前 board 的 `BoardItem → Card` 唯一解析。0 / stale target 不生成几何；同一 Card 多 placement 继续 `placement_ambiguous=true`、item scope 与 geometry 均为空，move / resize / remove 不获得可执行 target。geometry 不参与 scope 计算，伪造 item 或用户文本内伪造几何仍以 `whiteboard_target_outside_scope` 在 Facade / action 前拒绝。
- tool schema 继续只接收绝对 `x/y` 或 `width/height`。exact R18 测试从 host geometry 读取 `x=35,y=-20`，首个且唯一产品调用为 `whiteboard_domain_commands/move_placement`，提交 `x=155,y=-20`；标题 `Runtime 创建验收 R14`、正文 `R15 Runtime 正文编辑通过`、标签小写 `runtime验收`、宽高均逐字段不变，唯一 completed action / Receipt 产生。
- Runtime parser 现在按领域共享几何策略，在 durable boundary 前把 non-finite / 越界坐标及低于最小或高于最大尺寸统一归类为 `invalid_whiteboard_request`；边界内负坐标继续合法。非法几何零 action / Receipt / snapshot 写入，forged target 继续零写拒绝。既有 surface reattach/switch、parse 后竞态、durable completion replacement 不 reload、interrupt / pending / late completion 回归继续通过。

### 真实 Codex App Server feature probe

- 当前真实二进制：`C:/Users/ExampleUser/AppData/Local/OpenAI/Codex/bin/b99306303521e97e/codex.exe`，`codex-cli 0.151.0-alpha.7.2`。运行 `codex app-server generate-json-schema --experimental --out <temp>` 后，`v2/TurnStartParams.json` 的实际字段只有 `additionalContext, approvalPolicy, approvalsReviewer, clientUserMessageId, collaborationMode, cwd, cyberAccessProgram, effort, environments, input, model, multiAgentMode, outputSchema, permissions, personality, responsesapiClientMetadata, runtimeWorkspaceRoots, sandboxPolicy, serviceTier, serviceTierForTurn, summary, threadId, toolOutput, turnTrigger`；没有 `toolChoice`、`requiredTool`、`allowedTools` 或 per-turn `dynamicTools`。`dynamicTools` 只存在于 `ThreadStartParams`。
- 真实 stdio App Server JSON-RPC probe 分别向 `turn/start` 附加 `toolChoice:'required'`、`requiredTool:'whiteboard_domain_commands'`、`allowedTools:[...]`、`dynamicTools:[]`，与无附加字段的 baseline 对同一不存在 thread 全部返回完全相同的 `-32600 / thread not found`。这证明当前 server 不对这些候选字段提供可观察的校验 / 返回语义；结合生成 schema，不能把任一字段实现成生产 required / allow-only 保障。
- 因此按派发边界停止 adapter/runtime-contract 这一半实现，Bridge 三个 adapter 与 Flutter runtime client / coordinator 零修改。兼容性提案：未来只有在真实生成 schema 或官方 App Server capability 新增具名 per-turn tool policy 后，才在 `RuntimeCapability` 增加版本化 capability，并由 experimental API 严格校验 host `required_dynamic_tool` / `allowed_dynamic_tools` 后映射到该真实字段；未知 provider 必须返回 `unsupported_capability`，不得 silent ignore。真实 binary probe 应成为该接线的 Gate。

### 自动验证、异常与 W0 下一步

- Runtime 专项全文件：`30/30 PASS`（新增 exact R18、forged geometry / invalid size、0 / 多义 placement；保留 R14-R17、surface race、interrupt、pending、restart / Undo）。相邻 coordinator + Runtime client：`25/25 PASS`。Bridge App Server client / adapter / experimental API：`25/25 PASS`。另有 exact R18 单测 `1/1 PASS`；完整非重复组合计 `80/80 PASS`。
- `scripts/verify_critical_fixes.ps1`：`3/3 PASS`；`git diff --check`：PASS。`flutter analyze --no-pub <2 files>` 在 `Analyzing 2 items...` 后超过 120 秒无终态并已中止；同 SDK `dart analyze` 完成扫描但在 analysis-server shutdown 因无法删除 `C:/Users/ExampleUser/AppData/Local/Dart/perf/<pid>` 以 OS errno 1920 非零退出，未输出代码诊断。该项不能标绿，W0 必须在集成环境复跑 changed-file analyze。
- 未运行 Windows GUI、真实用户数据库、build、install、push、merge 或发布；未操作真实白板。W0 集成时必须把首版 `9297fd1c` 与下方 P1 follow-up `f4ed3b75` 作为同一代码单元，并带上最新 handoff docs commit；复跑 P4 组合 Gate 后再构建唯一候选。真人仍需用 exact R18 原句验证一次 move、行动卡 / Receipt、退出重开、Undo 与再次重开；required-tool 首调用保障仍受当前 App Server 能力缺口限制，不能宣称已实现。

### P1 follow-up：统一领域几何边界并修正零写声明

- 独立审查证明上文原始“非法尺寸零 action / Receipt”声明不成立：首版 Runtime 只拒绝 `<= 0`，`width=1/79/3001` 会越过 parser，在 Facade 已创建 action 后才由领域 executor 拒绝；move 也只检查 finite，`double.maxFinite` 可生成 applied Receipt / Undo 并持久化。follow-up 不改写已有提交，追加代码 / 测试提交 `f4ed3b75` (`fix(whiteboard): enforce runtime geometry bounds`) 修复两项 P1。
- 仓库此前只有领域尺寸边界：width `80..3000`、height `60..3000`，没有坐标绝对边界。画布变换使用 `(canvas - viewportCenter) * zoom`，最小 zoom 为 `0.25`；据此在 domain executor 内建立唯一共享 `WhiteboardPlacementGeometryPolicy`，坐标边界取宽松但稳定的 `[-1,000,000, 1,000,000]`。该范围在最小 zoom 下仍是 250,000 像素量级，避免极端 double 进入持久化 / renderer 算术；边界内负坐标保持合法。
- domain executor 的 create / place-existing / move / resize 全部使用同一策略，并把 batch 校验前移到 request JSON hash 之前，使 NaN 也明确返回 `invalidRequest`，不再因 JSON 编码抛异常。Runtime 的 schema、create / move / resize parser 与 prepare geometry gate 引用同一策略；existing over-bound coordinate、width `1` 或 `3001` 均使 authorization unavailable，prompt 不含 geometry，也不自动迁移或修复已有数据。
- Runtime 表驱动覆盖 size `1/79/80/3000/3001`、合法负坐标、正负边界及边界外一单位、`±double.maxFinite`、NaN；逐项断言 action 与 snapshot-save 增量，非法项均为 0，合法边界正常产生一次持久 action / save。领域 executor 对相同矩阵断言非法项零 save / 无 Undo；exact R18 `x + 120` 回归继续通过。
- 最终复验：Runtime `32/32 PASS`；domain facade / executor `17/17 PASS`；相邻 conversation coordinator + Runtime client `25/25 PASS`；Bridge App Server client / adapter / experimental API `25/25 PASS`，非重复合计 `99/99 PASS`。四个改动 Dart 文件 analyze：`No issues found!`；critical fixes：`3/3 PASS`；`git diff --check`：PASS。
- 剩余风险：本策略不会修复历史 over-bound snapshot，只会阻止 Runtime 暴露 / 新写入；若真实用户库已存在这类数据，需要 W0 另行裁决显式修复流程。Windows 真人 exact R18、退出重开、Undo / 再重开与 required-tool 能力缺口仍按上文保留；本轮未 build、install、push、merge、发布或操作真实白板。

## P4-R19 W1：中文相对尺寸意图与单选择快速拒绝

### 基线、范围与提交

- task/thread：`01a052f1-da65-7ad2-8f44-15a9ead2d80f`；隔离 Worktree：`.codex/worktrees/7757/memex`；分支：`codex/whiteboard-w1-p4-r19`；精确基线：`2ed4b015c3455d651e22f3918ec3058e5baa1762`，开始时 detached HEAD / clean。
- 代码 / 测试提交：`37c77acd43e6e4ce3a845d58fe007dc9da2b6c7f` (`fix(whiteboard): authorize relative runtime resize`)。生产只改 `whiteboard_runtime_domain_tool.dart`，测试只改其直接 Runtime 专项；本文随后以独立 docs commit 更新。
- 未改 180 秒 timeout、App Server schema / dynamic tool wire、required-tool / allow-only、六命令 schema / capability 集合、Card / BoardItem / DomainCommand / Receipt / Undo、DB schema、依赖、UI、Goal、Roadmap、`I_PROJECT_STATE.md` 或 `DEVLOG.md`。

### 实现与安全边界

- 新的共享窄 matcher 只接受 `尺寸 / 大小 / 宽度 / 高度 + 增加 / 减少 + 明确阿拉伯数字`，末尾只允许可选 `像素 / px`；不接受“一点 / 一些”、中文数词、百分比，也不以 `.{0,n}` 跨标点。它被 capability 提取、带“吗”的明确委托、current-board exact-title 直接操作与否定扣权共同复用，避免四套 grammar 漂移。
- exact provider 归一化句 `当前选中卡片宽度增加 120 像素` 与用户原始重复口语 `把选中卡片卡片宽度增加 120 像素` 都只授权 `resize_placement`。普通问句仍返回 null；明确 `能帮我把…宽度增加 120 像素吗` 才允许写。`resize + 不要移动` 只留 resize，`不要 resize + move` 只留 move；标签 / move / body literal 不扩出 resize。
- capability 提取复用 R17 五类 quote scanner，把合法 quoted literal 整体遮蔽；malformed quote 若前缀已有明确白板写意图则返回 unavailable 且 capability 为空，普通非白板聊天或只讨论白板 / 卡片的 malformed quote 仍返回 null，不劫持普通对话。
- selection-bound 相对尺寸请求必须恰好一个 selected item：0 个在 flush / Runtime / action 前返回 `whiteboard_selection_required`，多个返回 `whiteboard_selection_ambiguous`。exact-title 请求继续复用 R17 current-board-only resolver；成功授权继续复用 R18 同一 authoritative snapshot 的 `item_id/x/y/width/height`，模型只能提交绝对 `width/height`，不能从 DB、全局卡片库或模糊标题猜 target。

### 自动验证、风险与唯一真人 Gate

- Runtime 专项全文件：`34/34 PASS`，包含 exact R19 production composition：host 注入真实审计 geometry `x=1039.862130884688 / y=1045.1693417620572 / width=887.5555555555558 / height=740.4444444444441`，fake Runtime 唯一提交该 item 的绝对 `width=1007.5555555555558`、height 不变；最终只 width `+120`，title / body / tags / x / y / height 逐字段不变，唯一 completed action / Receipt 产生。0 / 多 selection 均在 surface flush / Runtime / domain action / Receipt / save 前拒绝，现有测试断言 `saveCalls` 不变（零 save）。
- 相邻 conversation coordinator：`23/23 PASS`；两个改动文件 analyze：`No issues found!`；critical fixes：`3/3 PASS`；`git diff --check`：PASS。离线 `pub get` 已生成 `.dart_tool/package_config.json` 且未改 `pubspec.lock`，最后仅因本机 Pub cache 缺 `active_roots/69` 返回非零；测试均以现有缓存和 `--no-pub` 完成。
- 自动测试无法证明真实 Windows focus / selection、App Server 一定首调用白板工具或真实用户 DB 的最终状态；当前 App Server 仍无 per-turn required / allow-only 能力。本轮未 build、install、读取或修改真实用户 DB、push、merge、发布，也未执行真人 GUI。
- 推荐唯一真人 Gate：W0 从集成后的唯一候选完整退出 / 重开 App，回到目标白板并明确单选标题为 `Runtime 创建验收 R14` 的卡片后，只发送 `把选中卡片卡片宽度增加 120 像素`。通过标准：单次白板工具调用与 completed Receipt；宽度从 `887.5555555555558` 变为 `1007.5555555555558`，x / y / height、标题、正文、标签不变；退出重开仍保持，Undo 后再重开恢复原宽度。若重开后未重新单选，预期必须快速拒绝，不得猜目标。

### 独立审查 follow-up：畸形引号路由与 snapshot selection 复核

- 独立审查发现三处阻断：畸形标题引号的咨询问句会被错误劫持为 unavailable；quote scanner 的 span 来自原文却消费 normalized text，前后空白可能导致错位；prepare 开始时的单选在 authoritative snapshot 中已 stale 时仍可能继续交给 Runtime。追加代码 / 测试提交 `16aab238c1b054fecf9295a0857334a366047561` (`fix(whiteboard): keep malformed resize routing closed`)；不改写已有提交。
- quote scanner 现在直接扫描 normalized text；畸形 quote 只在首个引号边界前已经存在可信白板写能力，或存在句首 direct exact-title target 前缀时返回 fail-closed unavailable。`为什么当前白板上标题为「Card A 的卡片不能移动？` 与普通咨询继续返回 null；明确正文写入或 direct exact-title 畸形命令分别返回 `whiteboard_quoted_literal_invalid` / `whiteboard_title_target_invalid`，capability、action、Receipt 与 save 均为空。带前后空白的合法正文 literal 继续只授权 body，不扩出 resize。
- selection-bound 相对 resize 在 authoritative snapshot 建出 target items 后再次要求恰好一个存活 item；原本单选但已 stale 的 item 返回 `whiteboard_selection_required`，prompt 不暴露 geometry，不会把空 geometry 授权交给 Runtime，也不产生 domain command / action / Receipt。必要的 surface flush 已发生，生产环境可能持久当前画布状态，本测试未证明零 surface save。多选仍返回 `whiteboard_selection_ambiguous`，exact-title 路径继续使用 R17 resolver。
- follow-up 最终复验：Runtime 专项 `34/34 PASS`；相邻 conversation coordinator `23/23 PASS`；两个改动 Dart 文件 analyze `No issues found!`；critical fixes `3/3 PASS`；staged 与最终 range `git diff --check` 均通过。独立审查原三项 finding 已按上述自动证据关闭，但仍待 W0 最终复审，不在此声称集成通过。未 build、install、push、读取或修改真实用户数据库；上节唯一 Windows 真人 Gate 与 required-tool 能力缺口保持不变。

## P4-R20 W1：Runtime 锁定时 selection 清空不再伪装成 surface 重挂

### 基线、失败证据与交付

- task/thread：`01a04de1-94ba-7c63-b685-0e88301b9468`；隔离 Worktree：`.codex/worktrees/8dd4/memex`；分支：`codex/whiteboard-w1-p4r20-surface-selection-lock`；精确基线：`722a646de5b0c5903e1c70fedf6a6f2138187315`，开始时 clean。代码/测试提交：`591caf3a`；范围收窄提交：`3c6265c7`，两者必须作为同一 R20 代码单元集成。
- 真人候选连续两次对已选中卡片执行宽度 `887.5555555555558 → 1007.5555555555558`，均返回 `whiteboard_surface_changed`；两次均为零 action、零 Receipt、零持久写，宽度未改变，因此 R19 真人 Gate 仍失败，不能按“偶发 surface race”重试宣称通过。
- 根因是 Runtime 捕获 selected surface 后调用 production route 的 `setInteractionLocked(true)`；route 进入 readonly 会清空 selection，selection listener 随即用 `copyWith` 发布同一 route/board 的新 surface snapshot。R17 的严格实例 gate 把这次合法、同步的 selection-only snapshot 更新误判成真实重挂，并在 durable write 前拒绝。

### 修复与三道 gate

- `WhiteboardWorkbenchSurface` 新增 host-owned `attachmentIdentity`：每次 controller `attach` 都产生新对象；`updateSelection → copyWith` 只保留原 token。它不进入 prompt、工具 schema、领域命令或持久化，仅表达宿主 attachment 生命周期。
- prepare flush 后仍要求原 surface 实例完全相同，selection 在授权 snapshot 建立期间变化继续 fail closed；授权同时保存实例与 attachment token。invoke 初始 gate 仍要求授权实例、owner、board、token 全部一致，授权后的人为 selection 变化与同 owner/board 重挂继续拒绝。
- `setInteractionLocked(true)` 返回后只允许两种状态：原实例未变，或同 attachment token 且 selection 已变为空的新 snapshot。该窄例外只覆盖 production readonly 同步清空；fresh attach、非空 replacement、owner/board 变化全部返回 `whiteboard_surface_changed`。随后把这个 post-lock 实例冻结为 `lockedSurface`，parse 后/durable 前与 completion reload 继续要求该实例和 token 完全一致。
- durable completion 只 reload post-lock 实例；若 durable save 后才发生 fresh reattach，既有原子提交可完成，但 replacement surface 不接收旧 reload/lock。unlock 仍落在原 route callback，保持既有 readonly/reconciliation 语义。
- 未改 Runtime 六命令 schema/capability、Card/BoardItem/DomainCommand/Receipt/Undo、数据库 schema、相对尺寸 grammar、标题 resolver、UI 交互语义或行动卡呈现；未改 Goal/Roadmap/`I_PROJECT_STATE.md`/`DEVLOG.md`。

### 自动验证、共享契约影响与真人重测

- Runtime 全文件 `36/36 PASS`：新增 production lock callback 同步 `updateSelection(owner, {})` 后唯一 resize 成功，宽度只增加 120、高度/x/y 不变，lock 为 `[true,false]`、reload 一次、唯一 completed Action 与 applied Receipt；新增同 owner/board 在 lock callback 内 fresh reattach 的零写拒绝。原 flush 重挂、授权后重挂、parse 后/durable 前重挂、durable 后 replacement 不 reload、R14-R19、scope/hash/幂等/interrupt/Undo 回归继续通过。
- 相邻 conversation coordinator `23/23 PASS`，两文件合跑共 `59/59 PASS`。真实 `WhiteboardCanvasRouteScreen` production route 全文件 `8/8 PASS`：实际 readonly 清 selection 后，卡片宽度从 `887.5555555555558` 变为 `1007.5555555555558`；画布与持久 snapshot 一致，height/x/y、标题、正文、标签逐字段不变，Action completed、Receipt applied。
- 四个改动 Dart 文件 analyze：`No issues found!`；critical fixes：`3/3 PASS`；最终 range `git diff --check`：PASS。基线到代码 HEAD 的净 diff 只含四个拥有路径文件：`315 insertions / 3 deletions`；其中生产代码 `45 insertions / 3 deletions`，其余为直接/route 回归。
- 共享契约影响仅是内部 host surface lifecycle identity；不扩大模型权限、目标 scope 或持久数据语义。未 build、install、读取/修改真实用户数据库、push、merge 或发布。
- 剩余 Gate：W0 审计并选择性集成 `591caf3a + 3c6265c7` 与本 handoff 后，构建唯一候选。完整退出/重开 App，回到目标白板并明确单选卡片，只发送：`把选中卡片卡片宽度增加 120 像素`。通过标准：一次 completed Action/applied Receipt；宽度变为 `1007.5555555555558`，height/x/y、标题、正文、标签不变；退出重开仍保持，Undo 后再重开恢复 `887.5555555555558`。若未重新单选，仍应快速 `whiteboard_selection_required`，不得猜目标。
