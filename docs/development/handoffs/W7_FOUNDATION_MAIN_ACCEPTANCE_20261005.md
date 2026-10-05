# W7 手机基础主窗源码验收（2026-10-05）

基于 W1 已合入 `dc29fd5e`，并仅快进到 W2 已验源码 `a00112e8c69d20971053845d02083e70fea1ab6d`（[PR #9](https://github.com/Ritou-Lynx/here-i-am/pull/9)）。原工作副本保留。此包交付 W7-0 的可用前置框架及明确入口接线；完整逐域业务迁移和页面仍按总规划验收。

## 最终有限证据

- 主窗冻结版本复跑 **114/114，零失败/跳过**：新目录 71、相邻原测试 43。19 个 worker 源/测试在测试前后字节一致。包括 9 个实际 OS-kill SQLite 子进程边界，以及真实 AppDatabase 的本地写、聊天队列和 Organizer 卡片/消费凭据/ack 同事务证明。
- 主窗 **5/5 真实 Dart↔Node HTTP 互通**：103 种子+提交记录、两页固定104项 snapshot；Unicode/嵌套/ECMAScript 浮点表达；接受后丢响应查询原 op；未变化 merge target 的稀疏回执及其排队后继；丢 merge 响应再通过 GET 恢复，source 隐藏而 target 存活；merge 已完成后才入队且 target 无缓存时，保留已验证 revision7，Core 接受为8；永久墓碑清理本地正文。执行真实 W2 domain_schema/domain_store/domain_http，只有内存合成库、回环端口和不可用于现役的合成 token。
- 最终相关路径及手动互通测试静态分析 **No issues found**。Flutter 实测在 Windows VM 上完成，不能继承为 Android 真机证据。
- [机器回执](W7_FOUNDATION_MAIN_ACCEPTANCE_20261005.json) 绑定21个当前源/测试原始字节、3个实际执行Core模块、日志摘要；Git staging blob 单独绑定并验证仅换行规范化差异。原始日志留本机非Git。

实际互通文件位于 `test/integration/personal_data_hub/client_core_interop.dart`（明确手动执行，不以 `_test.dart` 让普通CI隐式依赖Node24）；Node fixture在 `tools/personal_data_hub/node_core_domain_fixture.mjs`。显式设置 `I_CORE_TEST_REPOSITORY` 与 `I_CORE_TEST_NODE` 后执行 `flutter test --no-pub test/integration/personal_data_hub/client_core_interop.dart`。夹具不会打开运行库。跨平台 OS-kill 的 SDK 路径通过运行时/FLUTTER_ROOT 定位，找不到失败而不跳过；当前真实宿主为Windows，Linux执行由CI补证。

## 接线与复核

通用领域 outbox、绑定隔离的本地副本/cursor、phone/shadow/core、未同步覆盖和冲突队列复用AppDatabase kv_store，无Drift DDL或生成文件变化。领域凭据由owner分别注入；默认空Hub不联网。现有PersonaChat明确本机companion gate后，回复与原聊天队列同事务保存，发送不请求Core再生成回复；手机开关不替代服务端授权。

Organizer用户更正携actor，AI工具不自行升格；日程勾选明确user_direct；真实召回仅在owner允许域加“未同步”标记。显式CaptureConsumer只消费Core已接受claude_web，提取后核对text字段版本和墓碑，通过实际Organizer.persist与消费凭据/ack同事务写入，排除task/schedule/plan。

主窗及独立审核修复：UTC毫秒wire时间、跨语言数字/数值键canonical JSON、合法稀疏merge回执、正文/provenance/修订值清理、duplicate目标已删后的本地防回显、merge source删除范围、清正文后的原op只查不重发，以及旧回执不降低新base。最后补“merge完成后再入队”的版本下限；未接受/未绑定回执不能形成版本证据。未删除、弱化或跳过旧断言。

## 尚未完成的整张卡

本包没有开启真实业务域或迁移权威。各域旧写入、启动去重、判重删除和全部历史编辑入口仍需逐域adapter接入；没有全局关闭旧逻辑。W4/W5页面、待处理可见UI、widget/提醒、owner配置入口待实现。CaptureConsumer没有接入真实模型/自动触发；提取、原话编辑重处理、finance桥接及派生删除审计不以本包ack冒充完成。

七天影子对账、回滚演练、逐域冻结切换、生产配置/凭据、App构建安装、三星手机侧键/冷启动和Android后台/多进程Gate均未执行。现役Core仍固定v4，服务切换前先保全transcript/replay与外置配置。详细实现和边界见 [worker交接](W7_PHONE_FOUNDATION_20261005.md)；源码合入不等于上线。
