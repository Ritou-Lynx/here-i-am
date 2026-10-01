# A3F-R3 独立审查回执

2026-09-27；独审 `/root/r3_native_audit`，GPT-6 Astra / high。精确基线 `b2adc44b7c04983a931c39695b81491cd295084b`。审查者未参与 N/D/U 实现，本回执不代表 APK 或设备验收。

## 最终分包结论

| 包 | 已独立核对 | 结论与限制 |
|---|---|---|
| N 原包 | 六文件真实差异、原生终态 drain + onDestroy 双门、旧回执/后继隔离、跨 handler lease broker、H2 continuity 路径；七份 JUnit XML 74/74、镜像 SHA | 接受；其中 6 源码守门、68 JVM 逻辑/文件，不证明真实 Android 生命周期 |
| N 的 W0 幂等修正 | 最近成功 lease/end token，只有精确无后继可重试；旧 token 不移除后继；77/77 收据 | 接受；增加 3 个成功后丢回执/后继隔离测试，最终含 6 源码守门和 71 JVM 逻辑/文件测试 |
| D 最终包 | 九文件源码/镜像 manifest、实际 test-final 55/55、analyze-final；完整资源退休、七键 activation、初始化/stop/query 代际、有界已知 token 收口 | 接受；未重跑，U store 依赖不计作 D 成果 |
| U 最终包 | 最小 P2 修正、定向 RED/30 项 GREEN/分析日志、8 文件源码及镜像、3 日志 hash 与退出码 | 接受；早先 69/29 只有 tool 输出未单独落盘，不能作为已独立读取日志的证据 |

## 审查发现与实际修正

- N/D activation 必须保留 R2 六字段加 observation_status 的七键结构，不能用内部三键替身证明接线。
- 原生 release/end 成功但回执丢失后，原 broker 对同 token 重试 false。W0 补最近成功记录；新 acquire/begin 清旧记录，始终不加自动 TTL 或释放后继。
- Android/Dart 同进程文件锁不能排除第二 FD；所有 create/open/reset/release 路径必须先取得全进程 broker lease，再进入 OS gate。一次 lease 仅可认领一个文件对象，未知释放不能猜测成功。
- U 测试替身曾错误复用已消费 lease，已改 fresh lease 并补拒绝复用反例。H4 用真实 close 的删除前失败 seam，验证 FD 关闭后保留原数据。
- D/U 已闭环：活 attempt 退出后 close 重试，finally 后完整资源快照，未知 acquire/begin 接续原 Future，已知 release/end 有界等待且可显式同 token 重试，12 秒初始化等待保留 R2 原生 10 秒窗口。
- U 最后一个 P2：历史成功集合会在本次 primitive 拒绝后仍误报 complete。最终每轮清空成功证明、两类 primitive catch 删除当前 source；新反例在双源预检之后、claim 之前生成 successor 并拒绝，验证 partial、保留 collector、successor 字节不变。旧代码 RED exit 1，最终 UI 30/30 exit 0、analyze exit 0、diff check exit 0。

## U 最终冻结

- controller SHA-256 `A6F30102D139A0F4714A2C57ADA350442013D2A75A0506B5A3C15603D25F3571`。
- UI test SHA-256 `8CFD2D5430CE13C211791F64E1C1DB1FEF2117046147623350E2F47C06E24228`。
- owner test SHA-256 `3D7FE2EA3CD44C371CCB5A0F2207C549C730D1643E717DA9EB47A2F05BD6C3A6`。
- 最终 manifest：主工作区 `tmp/a3f-r3-w0/u-verification/evidence/u-final-p2-manifest.json`，SHA-256 `F569AFB7AC067B206564FD7B93F58A95560A12EC2D68113916366130101011A7`。
- 同目录三个实际日志均独立实读并匹配 manifest；不补造旧 69/29 收据。

## W0 组合与后续

W0 已实跑完整 Activity 七个 Flutter 测试文件，181/181、源码/测试 analyze、范围检查均 exit 0；17 输入与镜像逐字节一致。组合证据另见 W0 验证页；不能把分包数量与 181 重复相加为额外覆盖。

原生第二 engine/跨进程、真实 Service/通知时序与 H0–H6 仍待唯一 APK 的设备证据。N 已完成工作树可恢复归档；六源码与 344 镜像文件已保全，不等于 commit/push 授权。

## W0 组合绑定与 JNI 隔离独审

审查者逐一核对17组合输入、7测试文件、日志/hash/actual exit；确认181/181与分析、静态检查结果一致。构建清单1223项存在，12个改动的Android/Dart输入与W0及构建目录一致。

后续JNI缓存写入故障采用原字节路径隔离。独审逐一核对188原/副本输入；337包配置全对象比较仅JNI rootUri变化，生成插件路径指向本轮目录，pubspec/lock仍与原冻结值一致。接受此构建环境隔离，不把它解释为源码/依赖升级或设备通过。
