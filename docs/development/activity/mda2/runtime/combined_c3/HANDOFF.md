# R3+M3 C3 本地源码候选交接

> 2026-09-12；W0；状态：隔离候选已验证，尚未提交、主线合入或部署。

本候选在基线 `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5` 上结合 M3 两份共享修复与 R3 持续运行入口。72 份源/fixture 的精确清单见 [SOURCE_COMPOSITION](SOURCE_COMPOSITION.json)，其中36份为拟合入可执行路径，其余36份来自固定基线。Node v24.14.1、六份Core来源、16份发布文件与固定hash见 [PACKAGE_MANIFEST](PACKAGE_MANIFEST.json)；此文件是包清单，不包含Node二进制或可直接部署的运行包。

## 本次修复及失败历史

Windows core.autocrlf=true 会改变已固定的源码字节。仅将三份原mixed-EOL输入转成LF，并对36条确切执行路径指定LF，证明Git存储和checkout两次转换均逐字节不变。两份共享Core的Git逻辑改动仍为 +11/-1；原冻结hash和规范化后hash分开记载。

C2完整R3曾20/21，持续运行提前退出，原日志 [保留](C2_R3_FAILURE.txt)。该次服务子收据随fixture清理，无法确证是哪一端触发；源码审查在父/子两处定位可选控制文件检查与读取的删除竞态。C3直接尝试读取，只将明确的文件不存在视为未收到请求；密钥、链接、访问及其他I/O错误继续拒绝。双端barrier只写入合成测试另造的运行包并生成独立manifest，未加入普通运行包。

C3首两轮R3均22/23，普通包持续运行均通过。首轮新测试的生成代码丢失const初始化，测试包未启动；第二轮的测试自身存在“判不存在后读到新请求”的竞态，缺少一个barrier并超时，未保留哪端缺失。[首次日志](C3_R3_FIXTURE_FAILURE.txt)、[第二次日志](C3_R3_FIXTURE_RACE_FAILURE.txt)与[精确测试修订](TEST_REVISION.json)保留。最终实际生成源码先做语法检查，握手改为两端armed后才创建请求、两端checked后才删除放行。修订后[窄验证](FOCUSED_BARRIER_RUN.txt)只有1项匹配测试，报告另外3项是无匹配的文件入口，不冒称4个独立场景；再跑下列完整23项。普通包manifest和其他71份输入不变。

M3首次沙箱执行的旧v4-pin回归被拒绝清理自有子进程，外层120秒超时后实际Job空/清理确认；[失败日志](C3_M3_SANDBOX_FAILURE.txt)与[收据](C3_M3_SANDBOX_CLEANUP.json)保留，最终四组在获准的沙箱外自有合成环境重新执行，未修改测试源码或访问真实库。

## 本次实际验证

- R3完整 **23/23**，普通包监听 **125026 ms** 后受保护停止、原路径重启；双端已观察close后删除仍健康，随后正常stop/clean-close；非ENOENT错误非零退出。最终实际test/监督器退出、Job归零、scratch删除均确认，无最终fallback终止。见 [R3日志](R3_RUN.txt) 与 [接受记录](ACCEPTANCE.json)。
- M3默认四组 **15/15、208 pass/1 skip、7/7、6/6**，本次C3重新执行，无resume；四份实际exit0/父身份/Job空/清理收据见 [回归](m3/regressions.json)。
- 4项来源/manifest负例通过；36条Git字节往返精确；并行文档的LF index/CRLF working分离模型通过。原始日志、命令exit与每份证据hash见 [EVIDENCE](EVIDENCE.json)。

## 支持边界与下一步

支持自有合成环境的持续loopback、显式停止及同一包原路径真实clean-close后重启。非零服务退出与是否实际完成资源关闭分开判断，不能从错误码单独生成或否定clean-close授权。

未证明现役兼容、真实库迁移、进程崩溃恢复、跨路径/跨候选恢复、guardian失联加父死亡的复合故障、真实relay发送、系统设备数据/手机/一晚真人验收。W2及其他采集包独立，MDA-2全阶段未完成。现役固定v4不变。

源码验证入口为固定Node下的 `tools/i_core/runtime_upgrade/r3/run_tests.mjs --synthetic` 和 `tools/i_core/migration_m3/run_tests.mjs --synthetic`；使用Windows PowerShell5.1内置模块路径。打包器仍需基线Git对象，显式 `--prepare` 创建新包后用返回manifest SHA做 `--verify`。M3的seal_delivery工具仅用于原worker交付，不是本候选入口。合入方法由W0外部的本地合入方案和精确INDEX.patch约束；授权执行后应另记真实commit，不提前把本交接改成落地收据。
