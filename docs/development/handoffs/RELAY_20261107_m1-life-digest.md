# M1 合同：林埃日摘要服务端（时间金字塔第一层）

方案：总设计文档“林埃记忆系统重构：时间金字塔”（Claude Doc，项目内）。本 PR 只做 M1：日摘要、待办、`life_digest`/`life_todo`、`i_chat_turn` 快照、ntfy 会催。周/月摘要、档案、App 改动在 M2/M3。

## 改动
- `tools/i_remote_mcp/life_digest.mjs`（自包含，候选逐字内嵌）：读家里摘要目录 `days/`、`todos.json`、`pushes/`，只新建 `inbox/todo-*.json` 与 `pushes/timeline-*`。
  - `life_digest`（i.read）：按日取四栏（your_day/us/todos/anomalies）+ 晨间播报；不存在就 `available:false`。
  - `life_todo`（i.write）：list / done / drop，只处理已有待办。
  - 所有端的 `i_chat_turn start` 返回多一个 `life_snapshot`（≤600 字）：中午前放晨间播报，之后放白天版要点、异常、待办、最近一次推送；没生成就写“暂缺”，不拿旧的充数。
  - 生成器发过的推送在下一次 `i_chat_turn start` 时经现有 Claude 写回通道进聊天时间线（线程 `t_lifenudge_YYYYMMDD`，林埃口吻，只写一次）。
  - 配置：`<MCP state>/life_digest.json` `{format:'life-digest-v1', digest_dir}`；没有这个文件就没有工具、没有快照。
- `chatgpt_candidate.mjs`：`LIFE_DIGEST_PATCHES` 排在 GEMINI_TOOLS 之后，只改 server（候选 server `bde3ff9f`，其余五个文件与 G2 相同）。mainline `server.mjs`/`domain_tools.mjs` 同步。
- `tools/life_digest/`：生成器。计划任务 04:30（前一天定稿）/07:30（晨间播报）/19:30（白天版），登录时补跑。
  - 数据：聊天（Core 库只读，按 MCP 的分享策略过滤，`chat_source.mjs` 与只读模型逐行一致并有对照测试）、饮食（Core 库 `food_entries` 只读）、心率分钟文件、飞书日记副本（`notes_tools.mjs` 的 `notesByDate`，04:00 分天）、高德天气（每天存预报，次日对比）。
  - 生成：本机 Codex CLI（固定模型，`--sandbox read-only`，输出 JSON 校验，不合格带错误重试一次），OpenAI API 只在 Codex 两次失败后兜底（可不配）。全天无记录不调模型。晨间播报模型失败时用事实模板。
  - 待办：只从用户原话抽，带原话和出处；顺延；拖满 7 天推送问一次；`life_todo` 收件箱在下一次生成时合并。
  - 会催（M1 只有两条规则）：记了饮食但 10:30–15:00 没有一餐；待办拖满 7 天。只在白天版触发，每天最多 2 条，00:30–07:00 不推；文字由模型以林埃口吻写，去掉“林埃来电”（避免误触发来电例程），失败用模板。
- 已 cherry-pick 日记线程的 `notes_tools.mjs`（1d9bfc8，原样；#100 合并后与主线一致）。

## 部署（脚本轮）
1. `tools/relay_scripts/life_digest/m1-prepare.ps1`（write，只建 `%USERPROFILE%\life-digest\config` 和部署密钥对，不动生产）：核对现役 G2 任务与数据源、Codex 版本/登录/试跑、打印公钥、工作树里构建候选并读检查。
2. deploy 轮（下一提交补上）：用第 1 轮公钥加密的高德 Key 与 ntfy topic 随脚本提交（仓库里只有密文），安装生成器副本与配置、试跑一次白天版（不推送）+ 一条测试推送、写 `life_digest.json`、切换 MCP 候选、注册计划任务 `HereIAm-LifeDigest`。

## 边界
- 不改 Core、OAuth；对 Core 库只读；不新增凭据。
- 叠在 #93（G1+G2）之上，#93 又叠在 #91 上；须先合 #91、#93。
- 仓库里不写 Key、topic、本机路径。

## 验收
- `node --test tools/i_remote_mcp/*.test.mjs tools/life_digest/*.test.mjs` 全过。
- 部署后：各端开口时 `i_chat_turn` 返回带 `life_snapshot`；`life_digest` 能读到当天；19:30 白天版、次日 04:30 定稿、07:30 晨间播报按时出现；触发规则时三星收到林埃口吻的 ntfy，下次聊天林埃能接上。
