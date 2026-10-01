# A3-F 实际本地合入收据

日期：2026-09-16

- 来源：`5110ea19dd4e851eb8f620acdeb10d6e43149f93`，精确基线 `add2c1e6e06a8606fa6e6d58061f7540ca2fa958`；client task `90aa1164-ddc3-4f90-940e-c2965c77cd8a`，真实 thread ID 尚未由桌面索引解析。
- 本地源码提交：`v3-lab@3da91ebc6911d29b5af765b5ac6dfe5231d3eda7`。提交树 `f1edcafd1261898128735a5dbf4306d393d17301` 与来源候选完全一致；19 个交付路径选择性 cherry-pick，未合入主目录其他修改。
- W0 独立证据：Android 22/22、A3 18/18、A3-D 14/14、A1 56/56、A2 31/31、wire/Core 20/20；analyze、mirror identity、三组 static 与 diff check 均通过。见 [W0验收](W0_ACCEPTANCE.md)。
- 正式 App 源集补充任务：hereIAmV3Debug Kotlin/Java编译及Activity单元测试22/22、zero failure/error，723 tasks、exit0、BUILD SUCCESSFUL。仅在隔离测试副本补齐 package config、plugin metadata、local.properties 与 registrant，并排除产品未使用的 integration_test dev plugin；这些生成对象不属于候选源码，原产品源码/Manifest/Gradle/依赖声明未改。
- 全局状态仅暂存本包新增记录；主目录原有 58 项 tracked dirty 修改通过 SHA-256 保护，DEVLOG/I_PROJECT_STATE 原正文完整保留，其并行增量不进入本包提交。未 push、发布、部署或操作设备。

当前只完成默认关闭的本地源码集成。A3-F 尚无唯一 APK/hash；A3-D2 继续 FAIL，原正式 APK `E1B39E…EB37` 恢复事实不构成新候选验收。下一步从新的干净提交构建唯一 hereIAmV3 Debug 诊断 APK，再从零重跑真人设备矩阵。
