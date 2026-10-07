# W7 按记录存储及去重退役候选（2026-10-05）

## 基线与范围

基线为 v3-lab@8dde12b312ad83f7475df8bd99a359f1b2d782d6，任务分支 codex/hub-parallel-20261005。主窗实现本批 W7 三项前置中的逐记录持久化和切换前去重退役；未执行任何真实领域迁移、影子期、冻结切换或原库升级。area“未归类”的视图与筛选由 W5 保留，旧业务域回填及后续显式归类随逐域迁移验收。

## 存储与迁移

- 复用 kv_store：根/领域小元数据，canonical 记录、phone 覆盖记录及墓碑、隐藏 ID 墓碑、每个字段修正、每个 outbox 操作分别一行。installation 经 base64url 编码隔离；没有新增 Drift schema 或手改生成文件。
- DomainStore 聚合读取/transaction/visible/enqueue API 保持。差量比较只写变化行；单记录改动不会重写其他记录。feed/cursor、覆盖、回执仍同一 SQLite 事务；成功提交后发 Drift kv_store 通知。
- v1 整行状态在事务内转成 v2 行格式，保留 ID、稳定 op_id、sealed intent、顺序、修正、cursor、回执及额外根字段；成功提交删除旧整行，失败保留旧状态且不留半批新行。
- 混合格式、坏 JSON、重复行身份、孤儿或未知行类型失败关闭，不覆盖原始状态。物理格式没有自动降级/逆转实现，不能将事务失败恢复等同生产回滚。
- phone_quick 本机覆盖保留 provenance 和递增输入版本，删除留下无正文的正向墓碑；同事务清目标字段修正文，不影响其他 ID。保护过的 Memory V3 卡来源原话规则沿用既有决定。

## 去重

- configureRoute 切 shadow/core 前持久关闭该域本地 dedupe；disableLocalDedupe 可先关闭。旗标不随断连或凭据变化自动恢复，切回旧权威需独立流程。
- Organizer 的 task/schedule/plan 对应 plan_items，收支卡及 Finance 对应 ledger。冷启动批量清理、成卡局部判重、模型既有卡判重提示及账本写入判重均读取同一已提交旗标。
- 启动清理和账本 guard/write 放同一 DB transaction，避免与切换元数据竞态。尚未切换领域仍按原路径；其他自动派生功能和实际冻结旧写入不在本候选中。

## 验证与限制

- 原 PDH 协议/同步/应用接入71/71；去重5项 + 既有Organizer18及Finance14项37/37。强化PID/OS终止回执后，行存储14项与原同步61项组合75/75，含13处真实VM终止；相关静态分析无问题。最终跨W3/W4/W5组合仍以主窗本批验收为准。
- 行存储覆盖单行物理写入、旧状态原值迁移、失败恢复、binding 隔离、未知/混合格式拒绝、删除隐私和另一个 ID 修正保留。
- 新增迁移/feed四处以及原九处 OS-kill，测试启动父子 VM 后以 fixture 写入者 PID 和 Windows taskkill 的真实回执核对写入 VM 确已结束；不再仅杀 Dart 启动壳。临时目录在 systemTemp 范围内，Windows errno32仅有限清理重试，失败仍报红。
- 所有库与正文为合成夹具。未读/写真实生活数据、停服务、改线上配置、安装手机、自动启用 Core 或模型。
- 全量生产逆向迁移、逐域七天影子/冻结、生命周期保护卡及真实 App/三星侧键/提醒仍各有独立验收边界。
