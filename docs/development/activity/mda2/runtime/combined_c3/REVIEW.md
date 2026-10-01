# C3 独立审查记录

2026-09-12，W0 汇总内部审查；不替代运行日志或实际落地收据。

## 运行时

`runtime_pin_dependency_audit` 对 C3 相对 C2 的五份输入进行了只读复核，W0 再核关键分支：

- `owned_job.ps1` 最终 SHA `a70f5e1c1a0368f7d02c5055483010c62d1de550b30563f4e0430df80ab91973`，直接读取 optional 控制文件，仅 `FileNotFoundException` 返回 null。
- `runtime_child.mjs` 最终 SHA `da1706eccc20babb49851ad65c17a16229e05fb0e33fccea63bad55ec9658f81`，仅目标读取的 `ENOENT` 返回 null；stop.key/HMAC 处于该 catch 外。两端前置 exists 的吞错风险已修复。
- `service.test.mjs` 最终 SHA `7ca10fcd07d7c0c2ad316093938ab40f38321bd25a8ff003e2d35cea401f365b`，仅临时重签名包加入双端有界 barrier；按精确 run token 校验，删除请求后无 child 收据且健康继续，再正常停止。此前旧注入锚点及重复 wx marker 问题在首次整组前修正；但首组仍22/23，新增测试实际生成文本丢失const初始化，测试包未启动。W0已补全赋值，并对实际生成文本先做语法守门；独立窄复核通过，精确before exit1/after exit0与普通包不变证据见TEST_REVISION.json，不把首轮标为通过。
- 认证仍为 stop.key 对 run token、manifest、请求名计算 HMAC；request_stop 仍核对指定绑定。package/combination 的后续变化仅为 C3 ID，不改两份已规范化的 M3 Core。

无未闭合的运行时 P1/P2。目录型非 ENOENT 测试证明全运行失败并回收 Job，但父端可能先终止子端，因此不声称该单测独立证明每端都先观察过该错误；两端错误分支另有静态依据。

第二轮新增测试仍因自身存在性预检与读取之间的请求创建窗口而缺barrier；不是再延长期限重跑。升级后的独立 `control_barrier_debug` 审查确认最终两阶段握手：父/子真实close-read前armed；双armed核token后才创建请求/start；双checked核token后同步删除/release；每端每gate最多30秒。静态路径和最终hash核对通过。窄实跑与完整整组分开记录，未把单次偶然通过当作消除竞态的依据。

W0 对审查摘要中的 clean-close 条件作了准确性校正：start_schema5 的 cleanExit 要求子退出已确认、真实资源关闭、guardian 成功、Job 空和无强停，并不要求 child exit code 为0。末尾“运行成功”才另要求 child exit0。保留既有资源关闭与运行成功的区别，没有因本次修复新增恢复能力。

## 合入范围和载荷工具

`scope_audit` 复核最小路径集、并行文档分离策略及准备工具。原路径约束意见已修复：72输入/36非基线执行路径唯一、严格仓库相对且精确等价；拒绝越界/链接及证据路径碰撞；准备器不再动态执行候选源码。

生成器只读检查 D 主目录的基线、空index、原文件干净、新路径不存在和并行文件指纹；在W0自有pending目录准备全部内容并通过cached apply只读检查后才改名为正式载荷。发生错误只留下明确pending目录，不写真实主目录。工具复核时 SHA `7543016d7bf173cf635ced0fb283633eff2cbb2bcc8368064619071d60c20321`，实际执行版本另由载荷生成记录固定。

UTF-8/CRLF 合成 Git 模型证明：index只包含MDA增量，working保留P6原字节，冲突由检查拒绝。正式执行使用before SHA保护的exact working复制，不依赖P6未改到某段文本上下文。实际载荷与最终只读检查结果由W0合入方案单独关联；本记录不表示已获真实主目录写入或提交授权。
