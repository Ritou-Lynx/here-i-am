# 方案 00 — Memex 原始体系（上游方案）

## 方案概述

Memex 上游采用"文件系统 + SQLite 索引"双轨架构，信息流经三个阶段：原始记录（Facts）→ 结构化展示（Cards）→ 知识归档（PKM/P.A.R.A.）。全部数据本地存储，无云依赖。

## 数据架构

### Facts（原始记录层）
- 按日期组织的 Markdown 文件：`Facts/YYYY/MM/DD.md`
- 每条记录有全局唯一 ID：`YYYY/MM/DD.md#ts_N`（fact_id）
- fact_id 是整个系统的"锚点"——卡片、知识库条目、洞察都指回它
- 支持文字、图片、语音转文字，统一落入同一格式

### Cards（结构化展示层）
- YAML 文件，路径与 fact_id 对应：`Cards/YYYY/MM/01_ts_1.yaml`
- CardAgent（LLM）分析原始内容，从约 20 种模板中选择最合适的
- 模板覆盖面广：生活（event/task/mood/routine）、知识（article/snippet/quote/link）、人物地点（person/place）、数据（metric/transaction/rating）、视觉（snapshot/gallery）
- 标签从受控词表 tags.md 中选取，最多 3 个，不允许自造
- LLM 不可用时有规则兜底（单图→snapshot，多图→gallery，URL→link，其他→snippet）
- CardCache（SQLite 索引表）加速 Timeline UI 的分页、标签筛选、日期范围查询

### PKM / P.A.R.A.（知识归档层）
- PkmAgent 将输入整理到 `PKM/` 目录下的四级结构：
  - Projects：当前正在推进的项目
  - Areas：持续关注的生活/工作领域
  - Resources：将来可能有用的参考资料
  - Archives：已完成或不再活跃的内容
- 产出是普通 Markdown 文件，每个文件里用注释标记来源 fact_id
- PkmAgent 有完整的文件操作工具（读/写/编辑/移动/删除/搜索），自主决定放在哪里
- 内置结构健康检查：文件过长提醒、目录碎片化检测、日期命名警告、频繁编辑检测

### 检索路径
- Timeline UI 浏览：走 CardCache SQL 查询（按时间倒序分页、标签筛选、日期范围）
- PKM 内容检索：PkmAgent 通过 grep/glob 工具在文件系统中搜索
- 洞察关联：InsightAgent 跨记录发现模式，生成图表和叙述型洞察卡片

## 方案优点

1. **信息源唯一性**：所有数据从 Facts 出发，fact_id 贯穿全链路，溯源清晰
2. **AI 操作友好**：P.A.R.A. 分类标准是"可操作性"而非"主题"，LLM 判断相对容易；文件操作都是标准的 tool-call
3. **模板丰富**：20 种卡片模板覆盖大量生活场景，视觉表现力强
4. **数据自由**：全部是 Markdown + YAML，无专有格式，随时可迁移
5. **标签受控**：避免标签膨胀和重复，保持分类一致性
6. **多 Agent 分工**：每个 Agent 职责清晰（记录→卡片→知识→洞察），流水线式处理
7. **结构自愈**：PkmAgent 主动检测和修复知识库的组织问题

## 方案局限

1. **流水线是全自动的**：用户发一条消息，CardAgent + PkmAgent + InsightAgent 全部自动跑一遍，用户无法控制哪些该记、哪些只是闲聊
2. **检索分散**：CardCache 服务 UI 浏览，PKM 靠文件搜索，两条路径不统一
3. **缺少对话式召回**：没有为"角色聊天中回忆信息"专门设计检索路径
4. **P.A.R.A. 对用户透明度低**：知识库的组织过程用户看不到也不需要看到，整理的价值主要体现在 AI 后续检索时
5. **标签词表需要用户维护**：新场景出现时需要手动添加标签

## 对 Here I Am 的启发

- fact_id 统一锚点的思路值得保留
- 卡片模板体系成熟，可以复用
- "用户控制写入"（记忆契约）是对全自动流水线的修正
- 知识归档层的价值需要重新评估：对于生活陪伴场景，P.A.R.A. 的归档能力是否还有用武之地，还是应该用其他方式组织记忆
- 检索能力需要统一和增强
