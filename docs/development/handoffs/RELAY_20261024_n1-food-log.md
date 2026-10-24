<!-- relay:contract v1 -->
# N1 合同：食物记录（Core 领域 + MCP 工具 + App 今日页，源码默认关闭）

> 已核对 v3-lab `5745238`。设计稿与用户决定见下文“用户决定”。

## 背景
- 目标：用户在 Claude / ChatGPT / Antigravity 发食物照片或描述，前端模型识图、拆成“食物 + 克数范围 + 每项热量和三大营养素”，经 i MCP 写入 Core；手机 App 新“饮食”页显示当天记录。照片不经 MCP、不留存；模型自己估值，标来源和置信度。
- 存储走个人数据中枢的通用领域引擎：`tools/i_core/domain_store.mjs` 的 `registerDomain`（第 52 行）+ 主机 hooks，写法参照 `personal_data_domains.mjs`（schema 第 17 行起，hooks 第 183 行起，注册第 245 行）。生产上个人领域从未启用（`registerPersonalDataDomains` 没有生产调用方，手机端“默认不发任何领域流量”），本合同同样只做源码与合成测试，不接入生产启动。
- actor：`domain_store.mjs` 第 5、151 行规定 `user_direct`/`user_via_agent` 为第 3 级，必须带已验证的 `authorization_ref`。用户决定前端写入不要授权引用，所以 MCP 写入用 `agent_inferred`（第 1 级）。副作用是以后 App 里以 `user_direct` 改过的字段，前端不能再覆盖，这正符合“用户改的为准”。
- MCP：领域工具在 `domain_tools.mjs`，网页端白名单 `WEB_DOMAIN_TOOLS`（第 57 行），配置入口 `server.mjs` `createWebDomainOptions`（第 480 行起，`plan_reads` 是独立令牌的先例），ChatGPT 系前端的领域工具按名字过滤（第 98 行）。
- 生产 MCP 是 `chatgpt_candidate.mjs` 从旧基线生成的六文件候选，legacy 侧没有领域工具。改 mainline `server.mjs` 必须在构建器加只作用于 mainline 的补丁组，候选输出必须逐字节不变（本合同不改生产 MCP 行为）。
- App：领域副本与同步在 `lib/data/personal_data_hub/`，`PlanningService`（`planning_service.dart` 第 47 行）是只读视图的先例；生活空间页 `companion_life_space_screen.dart` 第 47–51 行用 tab 跳 `AppRoutes.planning`。

## 数据（领域 `food_entries`，schema version 1）

| 字段 | 类型与规则 |
|---|---|
| `eaten_at` | 带时区的业务时间，`validBusinessTime` |
| `local_date` | `YYYY-MM-DD`，`validBusinessDate`；由 MCP 按配置时区、以本地 04:00 为日界算出，调用方不能提交 |
| `meal` | `breakfast` / `lunch` / `dinner` / `snack` / `drink` |
| `title` | 非空，≤200 字 |
| `note` | 字符串，≤2000 字，可空串 |
| `input_kind` | `photo` / `text` / `mixed` / `app` |
| `items` | 数组，1–40 项，每项见下表 |
| `totals` | `{kcal,kcal_low,kcal_high,protein_g,fat_g,carb_g}`，必须等于按下面算法从 items 算出的值 |
| `user_corrected` | boolean；本合同里 MCP 写入恒为 false |
| `voided` | boolean；前端“撤销这条”时置 true，读取和 App 一律隐藏；真正删除留给 App 的 `user_direct`（N3） |

每项 `items[]`（键集合精确，不许多余键）：

| 键 | 规则 |
|---|---|
| `name` | 非空，≤100 字 |
| `food_ref` | `{source,id}`；`source` ∈ `model` / `label` / `personal` / `usda`，`id` 为字符串或 null（本期前端只会用 `model`、`label`） |
| `grams`, `grams_low`, `grams_high` | 有限数，`0 < grams_low ≤ grams ≤ grams_high ≤ 5000` |
| `kcal`, `protein_g`, `fat_g`, `carb_g` | 有限数，0–10000，是这一项（按 `grams`）的值 |
| `basis` | `weighed` / `label` / `photo` / `described` / `model_guess` |
| `confidence` | `high` / `medium` / `low` |

合计算法（Core、MCP 各实现一份，测试互相对照）：`round1(x)=Math.round(x*10)/10`；`kcal=round1(Σkcal)`，`kcal_low=round1(Σ kcal×grams_low/grams)`，`kcal_high=round1(Σ kcal×grams_high/grams)`，`protein_g/fat_g/carb_g=round1(Σ对应值)`。

## 完成标准

**Core（新文件 `tools/i_core/food_domains.mjs`）**
- [ ] 导出 `FOOD_HOOK_VERSION='food-v1'`、`FOOD_DOMAINS=['food_entries']`、`FOOD_SCHEMAS`、`foodTotals(items)`、`validateFoodRecord(record)`、`createFoodDomainHooks({writerPrincipalIds=[]})`、`registerFoodDomains(store,{mode='off'})`。
- [ ] 校验按上面两张表：键集合精确、枚举、长度、数值范围、`grams_low ≤ grams ≤ grams_high`、`totals` 与 `foodTotals(items)` 逐键严格相等；不合规的转换被 hooks 拒绝。
- [ ] `authorizeOperation`：只允许 `writerPrincipalIds` 里的 principal，以 actor `agent_inferred` 做 create / patch；patch 只能针对同一 principal 创建的记录。其他 principal、其他 actor、`delete`/`status`/`merge`/`restore`/`purge` 一律拒绝（引擎本就要求 delete 为第 3 级，见审核记录第 1 轮）。lookup 阶段规则同理。
- [ ] 不改 `domain_store.mjs`、`i_core_server.mjs`、`i_core_store.mjs`、`personal_data_domains.mjs`、`release_schema6/`；不接入任何生产启动路径。
- [ ] 新测试 `tools/i_core/food_domains.test.mjs`（合成数据，用真实 `DomainStore` 走 HTTP 或 store 接口）：注册 → 授权 principal 以 `agent_inferred` 创建、修改、置 `voided:true` 成功，`agent_inferred` delete 被拒；未授权 principal、`user_via_agent` 无授权引用、`status` 操作被拒；totals 错 0.1、缺键、多键、`grams_low>grams`、41 项、未知枚举各被拒；`foodTotals` 有固定样例（含小数进位）。

**MCP（`domain_tools.mjs`、`server.mjs`、`mcp.mjs` 仅确需时）**
- [ ] 新工具 `food_log`（scope `i.write`）：参数 `action`（`add`/`update`/`void`）、`op_id`（UUID，重试原样）、`id`（UUID，add 时新建）、`base_revision`（update/void 必填）、`entry`（add/update 必填：`eaten_at`、`meal`、`title`、`note?`、`input_kind`、`items`）。MCP 自己算 `local_date`、`totals`，补 `user_corrected:false`、`voided:false`、`created_at`/`expires_at`，actor 固定 `agent_inferred`；update 为整条覆盖这些字段；void 只 patch `voided:true`。调用方传 `totals`、`local_date`、`actor` 一律报错 `food_field_not_allowed`。返回 `{id,revision,local_date,totals,day_totals}`。
- [ ] 新工具 `food_day`（scope `i.read`）：参数 `date?`（缺省为按 04:00 日界的“今天”），返回当天全部未删除且 `voided` 不为 true 的条目（按 `eaten_at` 升序）和 `day_totals`（各条 totals 逐键求和后 round1）。
- [ ] 两个工具的 description 用中文写清：照片由你自己看，不要尝试上传；逐项列食物，中式炒菜把“烹调油”单列一项；给克数范围；参照物写进 note；不确定标 low，不编数；`food_ref.source` 用 `model`，拍到营养标签时用 `label`、`basis:'label'`；写入后把结果和今日累计告诉用户并请对方纠正；用户说记错了、不要这条时用 `void`。
- [ ] `WEB_DOMAIN_TOOLS` 加 `food_log`、`food_day`。`createWebDomainOptions` 支持可选 `food` 配置块：独立令牌（与 `token`、`plan_reads.token` 都不同），scopes 只能是 `food_entries:read/create/patch` 的子集，否则 `invalid_web_food_configuration`。
- [ ] 前端：`claude_web`、`chatgpt_web`、`antigravity` 都暴露 `food_log`、`food_day`；`gemini_web` 不暴露。`food_log` 的 `requiredScope` 为 `i.write`（第 96 行现有 `capture_add` 特判一并改成按工具声明）。
- [ ] 未配置 `food` 块时工具清单与现在完全一致（既有测试不改即通过）。
- [ ] 新测试 `tools/i_remote_mcp/food_tools.test.mjs`：假 Core 客户端；`local_date` 日界（本地 03:59 归前一天、04:00 归当天）；totals 由 MCP 计算且与 `foodTotals` 一致（import Core 文件只在测试里做对照）；禁止字段报错；add→update→void 的请求形状（actor、base_revision、op_id 重试原样）；四个前端的工具清单（gemini 无 food 工具）；`food` 配置非法的各种情况。

**候选构建器（`chatgpt_candidate.mjs`）**
- [ ] 新补丁组只作用于 mainline（legacy 为空），v3-lab 新源码通过正反向校验。
- [ ] `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/n1-candidate` 成功，六文件，`changed_files: 5`，且六个文件哈希与 `48bd91e` 候选相同（前 8 位 server `c1926ef7`、oauth `7c82a07d`、diagnostics `2b461c32`、mcp `0ae610bf`、writeback `783e8fd0`、i_memory_read `cee18518`）。

**App（只读今日页）**
- [ ] `lib/data/personal_data_hub/food_models.dart`：`FoodEntry`、`FoodItem`、`FoodTotals`、`FoodDaySnapshot`（含 `error` 文案）；从副本 JSON 严格解析，坏记录跳过并计数，不崩溃。
- [ ] `lib/data/personal_data_hub/food_service.dart`：`FoodService({DomainStore? store, DateTime Function()? clock})`，`Stream<void> get changes`，`Future<FoodDaySnapshot> read(DateTime date)`；绑定检查、`route!='core'` →“尚未启用”、需重同步 →“副本需要重新同步”、无 store →“尚未配置”，写法同 `PlanningService.read`；`voided:true` 的条目不显示、不计入合计。本期没有任何写操作。
- [ ] `lib/ui/food/widgets/food_screen.dart` + `food_host_screen.dart`：今日视图。顶部当日热量“约 N 千卡（低–高）”；蛋白 / 脂肪 / 碳水三条横条（克数与占热量比例，按 4/9/4 千卡每克算）；按 `eaten_at` 的餐次卡片（时间、标题、热量与范围、置信度点、来源标签）；点开列出每项食物、克数、来源（模型估 / 标签）；左右切换日期；无数据和各错误状态有中文提示。
- [ ] 来源标签：副本记录若有 `origin.device_id`，用 `chat_message_source_label.dart` 里同一份映射显示（允许在该文件新增一个公开函数，原有行为不变）；没有就不显示。
- [ ] 路由 `AppRoutes.food = '/food'`；生活空间 tab 末尾加“饮食”，点击 `context.push(AppRoutes.food)`，写法同第 47–51 行。
- [ ] 测试：`test/data/personal_data_hub/food_service_test.dart`（合成副本：正常、坏记录、未启用、未配置、日期过滤）；`test/ui/food/food_screen_test.dart`（合计、范围、横条、卡片展开、空状态）。

## 允许修改的路径
- 新建：`tools/i_core/food_domains.mjs`、`tools/i_core/food_domains.test.mjs`、`tools/i_remote_mcp/food_tools.test.mjs`、`lib/data/personal_data_hub/food_models.dart`、`lib/data/personal_data_hub/food_service.dart`、`lib/ui/food/widgets/food_screen.dart`、`lib/ui/food/widgets/food_host_screen.dart`、`test/data/personal_data_hub/food_service_test.dart`、`test/ui/food/food_screen_test.dart`
- 修改：`tools/i_remote_mcp/domain_tools.mjs`、`server.mjs`、`mcp.mjs`（仅确需时）、`chatgpt_candidate.mjs`、`chatgpt_candidate.test.mjs`（只追加）、`tools/i_remote_mcp/README.md`（加“食物记录”一节）、`lib/routing/routes.dart`、`lib/routing/router.dart`、`lib/ui/companion/widgets/companion_life_space_screen.dart`、`lib/ui/character/widgets/chat_message_source_label.dart`
- 既有测试只能追加，不能改已有断言；若确需改（例如 life space tab 数量断言），停下发 blocked 说明。
- `docs/development/handoffs/RELAY_20261024_n1-food-log.md` 只由 Claude 改。

## 不做 / 边界
- 不接入生产：不改 Core 运行包清单、启动、`release_schema6/`、维护工具；不生成部署候选，不部署，不碰真实数据。
- 不做 `food_search`、营养库、个人食物库、App 改份量、周统计、目标（属于 N2 之后）。
- 不新增依赖；不上传或保存照片；仓库里样例数据用虚构食物。
- 止损：同一测试名或错误码连续两个提交失败即 blocked，最多 3 轮。

## 验证命令
- `node --test tools/i_core/*.test.mjs tools/i_remote_mcp/*.test.mjs tools/i_memory/*.test.mjs`
- `node tools/i_remote_mcp/chatgpt_candidate.mjs --out build/n1-candidate`（输出不提交，核对哈希）
- `flutter analyze lib/data/personal_data_hub lib/ui/food lib/routing lib/ui/companion/widgets/companion_life_space_screen.dart lib/ui/character/widgets/chat_message_source_label.dart`
- `flutter test test/data/personal_data_hub/food_service_test.dart test/ui/food/food_screen_test.dart test/ui/core/widgets/chat_message_source_label_test.dart`（本机无 Flutter 时以 CI 为准）
- CI 全绿。

## 之后（不在本合同）
- N2：食物领域上线（数据中枢首个领域）：Core 运行包加 `food_domains.mjs` 并注册、建 MCP 用 principal 与令牌、六文件候选加入领域工具、手机打开该领域同步。每一步是生产操作，单独同意。
- N3：营养库与 `food_search`、个人食物库、App 份量修正（`user_direct` 需受信 UI 授权引用）。N4：周统计与趋势；N5：与心率、睡眠并列。

## 用户决定（10-24）
1. 照片由前端模型识别，服务端不碰照片，也不留存。
2. 热量能查库就查，查不到用模型估值并标注；数据源零操作：个人库自动积累、营养标签、菜谱拆解配模型参考值、USDA 兜底，不导入成分表。
3. Claude、ChatGPT、Antigravity 可写；Gemini 不管。
4. 前端写入不要授权引用（落地为 actor `agent_inferred`，见背景）。
5. 第一阶段只记录、不设目标；林埃不主动评论饮食。
6. App 入口：生活空间新增“饮食”。

## 需要真人的部分
- 合并由用户进行，收到 `relay:done` 前不要合并。
- N2 上线每一步单独同意。

## 审核记录

### 第 1 轮（10-24）：blocked，合同修订
- Codex 复现：`domain_store.mjs` 提交入口在 hooks 之前要求 delete 的 actor 为第 3 级，`agent_inferred`（第 1 级）delete 返回 403 `actor_not_authorized`，无改动。
- 裁决：不改 Core 引擎。删除是用户级操作，属引擎设计；前端撤销改为 patch `voided:true`（新增字段），真正删除留给 App 的 `user_direct`（N3）。合同已相应修订。
