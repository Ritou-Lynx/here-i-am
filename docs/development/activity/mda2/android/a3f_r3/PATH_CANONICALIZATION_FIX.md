# A3F-R3 Android 路径别名窄修复

2026-09-27。原候选854F341E…BAD8658设备H0失败，根因及失败/回退收据见 DEVICE_GATE.md；本页记录同一Goal内的最小返修，不继承旧APK真人结果。

## 实证与修复

当前设备上，原生Context返回/data/user/0形式的no-backup诊断根，Dart解析同一目录为/data/data形式。纯只读Debug断点在UI第956行证明strict比较因此返回diagnostic_reset_scope_invalid。shell realpath保留各自spelling，Java canonicalFile未验证；不能用其他运行时结果推定Dart行为。

仅真实MethodChannel getOutboxRoot桥接增加Dart路径规范化：精确原生字段/作用域、绝对路径、无点段、no_backup/mda2_activity固定后缀；appData和no_backup本体必须是非链接目录。只规范化可信父边界，要求canonical(no_backup)精确等于canonical(appData)/no_backup，再拼固定mda2_activity。已有诊断根仍要求本体非链接且raw/canonical类型与解析一致；缺失根可返回但不创建。重复获取重新校验并固定首次规范根，后继不同根拒绝。解析/类型失败固定拒绝，无原始路径回退。

UI/FileStore的严格等值与反链接检查保留；collector、清理、窄释放使用同一规范路径。没有lease/key/sequence/数据写入或采集副作用，没有native/wire/schema/BLE/生产入口/依赖修改；broker-before-gate不变。可注入的文件系统seam只含两个只读方法，真实入口默认Dart IO；不按非Android分支跳过校验来通过测试。

## 精确变化与验证

- 运行源码仅android_activity_signal_platform.dart，SHA256 `9BFDD427CB8D5D79B878DFBC2511A43601CB6E5E5E1B82A4369078510C08FB99`。
- observation_collector_test仅调整Rig到真实no_backup/mda2_activity布局及清理，SHA256 `0D3C288C66FE6CCC4F62202AC87D284EFA2F4543DCC45B82ABA0681CDFB06C42`。
- observation_platform_test新增11个边界场景，最终SHA256 `490B832BA537CC5C5CE09AA2178FC07404D98E0C9F1A4025BB52D35677FB8DF3`。alias缺失/已有根、两次一致、换另一合法根拒绝；非法scope/结构/缺失父、no_backup逃逸/类型及真实父/root链接拒绝。原生只读方法调用断言保留。
- 原行为RED exit1；中间64/64及Windows分隔符修正的失败历史保留；最终D **66/66**、定向分析无问题、9文件逐字节绑定。
- W0中间 **190/190** 保留；补齐两例后最终 **192/192**、七测试文件/17输入逐字节一致，分析无问题，actual exit0。
- 独审核对实际diff、9文件/日志、真实链接测试与补齐的已有根/换根断言，未见阻断。alias正例仍是受控只读替身；Android实际已有根清理必须由新APK真人Gate证明。
- 静态检查只额外放行本轮三个精确证据文档名称及既有Goal；源码/保护区规则未放宽。它不属于运行时输入，不证明行为。

本机收据：`tmp/a3f-r3-dart-verification/r3-pathfix-final-{green.log,analyze.log,source-manifest.json}`；`tmp/a3f-r3-pathfix/combined-final-{result.json,source-manifest.json}`与`combined-final.log`。新运行输入1223文件，SHA256 `4D4667AFC0E39D5AB17E942241CA76ECF3BC9F47156940E899B2BD8E45044C4E`；JNI188输入与旧候选一致。APK身份以CANDIDATE_MANIFEST_PATHFIX.json为准。20:24新APK真人显式清理成功，key backing不变，H0随后通知/锁解查询通过，实际Android路径修复已验证；后续独立的UI动作提示缺陷导致R3完整Gate未通过，不能以路径修复成功宣称Goal完成。
