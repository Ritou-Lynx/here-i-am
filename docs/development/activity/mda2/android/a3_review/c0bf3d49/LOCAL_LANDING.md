# A3-I 实际本地合入收据

日期：2026-09-14

- 源码提交：`fac2f4750898d513ab3ae938281c85b1e9b7127e`，分支 `v3-lab`；父提交 `c5d7cbfe559eb517b3b1110f27e07dc8308d6442`。
- 接受来源：A3-I R1 `c0bf3d49cf145cb2505750bd2d4e4d26e2e1eb9c`，task `01a099d5-e30d-7631-9ffc-2c3687f0975c`。最终 14 个候选路径与 Git commit blob 逐字节绑定；被拒的初交付 `5f54d5b4` 没有作为独立提交进入主线。
- W0 证据：A3 Dart `16/16`、Kotlin `12/12`、A1 `56/56`、A2 `30/30`、wire/Core `20/20`、双向 analyze、静态范围与完整 `hereIAmV3Debug` App 单元任务通过。完整 App 离线测试仅从临时生成元数据排除未使用且缺动态缓存清单的 `integration_test` dev plugin；候选源码未改。详见 [W0验收](W0_ACCEPTANCE.md) 和 [ACCEPTANCE.json](ACCEPTANCE.json)。
- 提交范围：23 个路径，包括最终 14 个候选文件、A3 计划、首轮拒绝与最终验收材料、四份项目状态增量和落地工具。落地时主目录已有 56 份 tracked 并行修改，均按工作区 SHA-256 保护；提交后 index 为空。
- 当前只完成默认关闭的本地源码集成。没有 APK、adb、真实 UsageEvents、真实 Core/网络/凭据/数据库、手机或 BLE 数据；没有 push 或部署。A3-D 的 Usage Access、屏幕、Doze、划掉任务、force-stop、重启、Keystore、BLE 共存和一晚 Gate 尚未执行。

下一步先冻结 `fac2f475` 为 A3-D 唯一源码起点，再单独规划 hereIAmV3 APK、哈希与短场景真机 Gate；未经 Lynx 授权不构建、安装或访问设备数据。
