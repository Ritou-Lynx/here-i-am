# P6 R7 Windows 隔离 helper 候选交接

日期：2026-09-11。基线：`v3-lab@bbb8025d` 加当前 R6/R7 未提交成果。此包仅新增 C# helper、其 Node 测试及本文；未碰 Git index、认证资料或生产 profile。

## v3 原生合成矩阵实际通过（独立历史证据）

主控实际执行 v3 attempt `894a20f9-2e05-466d-8459-445f25426ee5`，exit 0。只读核对 `tmp/p6-r7-review/native-synthetic-03.json` 及 SHA-256 `91AE0EABDCDA77A218230D4FC6D6278A877F3C5C851B8DD34BAB2D4B8BF97D8C`：TCP4/6 与 UDP4/6 正控通过；允许交换、错误 peer 拒绝、正确 peer 接纳、其他 TCP4/6 拒绝及子进程拒绝均通过；UDP4/6 收到数量均 0；进程退出和 Job active=0 均实际确认；清理完成，无遗留规则/profile，0 真实请求。

此矩阵只属于 v3 exe SHA-256 `7009C3A65DF9A5302A59DB686F359D1B9E11F9C4C09A8D702A47E10A2F09C9F7` / 当时 source SHA-256 `0E8F6687A54CB41D8CE76A067F3B477F87B4051AA2E4B6CAF7B3C73F7D17B6E8`。**不能用下方新 v4b source 继承这份矩阵通过结论。** v3 没有运行真实 Codex，生产与人工 Gate 仍 false。

## worker 原生规范化 API 对照 v10（当前，未 apply）

主控 v9 startup05 attempt `92f3015d-084d-4850-a617-db8a7c52a783`，报告 `tmp/p6-r7-review/native-cli-startup-05-profile-layout.json` SHA-256 `898C6D90DB37560FEE3EB0952CF5C905DD4A202EBC8A481023020352E198EADB`。主控回报 profile_folder_scope_verified/profile_storage_absent_verified 均 true，说明本机 API 实际符合 v9 目录范围及清理检查；但 CLI 仍 canonicalize os error 5、exit 1、0 HTTP/model。布局变更并未解决启动问题。

v10 只在 `--apply-synthetic` 的内置 worker 加只读 API 对照，复用既有本次 D/work/empty-write-probe 固定目录。目录打开参数严格为 `CreateFileW(access=0, share=7, OPEN_EXISTING=3, FILE_FLAG_BACKUP_SEMANTICS=0x02000000)`；对同一成功句柄依次调用 GetFinalPathNameByHandleW flags 0（NORMALIZED|DOS）、2（NORMALIZED|NT）、8（OPENED|DOS）。每步返回后立即取得 Win32 error；成功时不保留可能过期的 last-error。缓冲固定 32768 wchar，超限明确 buffer_limit；返回路径从不转成报告字符串，finally 实际关闭句柄并记录关闭状态。

结果写入同目录固定 `canonicalize-result.bin`，使用 FileMode.CreateNew（wx）；唯一内容是 52 字节 little-endian：固定 magic/version、完成标记、五个步骤的固定状态与 uint Win32 error。无路径、原文或自由 key。父进程只有在 WaitForSingleObject 确认 worker 已退出后读取，要求无 reparse、恰好 52 字节且无尾随内容、header/状态/错误关联有效，再重建 `worker_canonicalize_probe` 的固定诊断对象。not_observed、missing、unreadable、rejected、incomplete 都表示未知/不完整，绝非通过；写入异常不传播任意错误文本，部分文件也不接受。

API 成功/失败结果与已有 `worker_file_probe_passed`、TCP/UDP/peer/子进程矩阵分开。`synthetic_passed` 保持原文件/网络矩阵定义，**不表示 canonicalize 成功**；预期规范化错误不会抹掉已观测的网络通过。此探针只证明同模式 D 目录中内置 worker 的 API 行为，不是精确 CLI 令牌或 C 盘 profile 行为。所有 CLI 入口、环境、ACL/IL、Job、WFP、凭据/模型范围不变，无新增 IPC/impersonation。

[官方 GetFinalPathNameByHandleW 文档](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfinalpathnamebyhandlew) 明确 flags 0/2/8 与失败/缓冲长度语义；其 SMB 特定说明不套用于已确认的本地 NTFS D 盘。[当前 Rust Windows 实现](https://github.com/rust-lang/rust/blob/main/library/std/src/sys/fs/windows.rs#L1570) 以 access=0 和 BACKUP_SEMANTICS 打开目录，随后默认 DOS 取路径；当前 main 亦有 NT fallback，但未证明固定 CLI 所用 Rust 构建与当前 main 相同，本候选不擅自加入修复。

专项 **33/33 passed，0 skipped**；固定 v10 exe `--self-test` **100 项 + ABI** 通过。新增 13 项纯解码检查覆盖成功/Win32 5 对照、错误 magic/version、非法状态/错误关联、未完成/缺步骤、缺失或多余字节；没有执行原生对照、apply/UAC、真实 CLI 或模型请求。

| v10 冻结候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.canonicalize-probe-v10.exe` | `4C018D016FACC29FE2E6A2F38CDC3F1967D8519F40AC370870437699E5BE4688` |
| C# source | `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8` |
| Node test | `3B30A568278284378BB75FB7024F3ED175FE289583B32AAA76C4E4FDDE261D0F` |

主控复核后使用 v10 exe 的 `--apply-synthetic`。旧 exe/原始报告保留，本候选尚无实际矩阵或 API 对照结果。

## 自有 profile 目录布局 v9（历史，已由主控 apply）

主控 v8 startup04 attempt `d958c0e3-5e03-4d95-aacf-8b937ce0b8bf` 报告 `tmp/p6-r7-review/native-cli-startup-04-excerpt.json` SHA-256 `604BFF1D1312B7D61B4C10E36E0987BBD4157C9895A8CB56EF1081B3063827B9`。主控回报完整脱敏链为两次 failed to canonicalize CODEX_HOME `<ATTEMPT>\work\empty-home`、os error 5：首次 arg0 告警，第二次致命退出。child exit 1、Jobzero/清理完成、0 HTTP/model。这定位到规范化访问，不是“文件写入必然失败”；D 盘已由主控确认本地 NTFS/Fixed，不套用 SMB 特定解释。

v9 仅改变无认证 CLI 的合成目录布局。新建本次随机 profile 后，使用其精确 SID 调用 [GetAppContainerFolderPath](https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-getappcontainerfolderpath)，输出内存在 finally 中用 `Marshal.FreeCoTaskMem` 释放。使用宿主 `SpecialFolder.LocalApplicationData`（不读取完整用户环境），只接受精确 `hostLocal\Packages\HereIAm.P6R7.<attemptN>\AC`；要求已存在且所有祖先无 reparse。不接受任意 journal 路径、其它 profile、SID 命名变体、路径前缀近似或额外子目录；真实 API 返回形状尚待主控运行，不符合即 `profile_folder_scope_rejected`，不自动放宽。

[Windows 官方启动示例](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer) 将 LOCALAPPDATA 指向该 `AC`，TEMP/TMP 指向 `AC\Temp`。v9 沿用此约定，并仅在本 profile 内创建 `empty-home`、`empty-workspace`、`Roaming`；它们必须此前不存在。CODEX_HOME=`AC\empty-home`，cwd=`AC\empty-workspace`，APPDATA=`AC\Roaming`，HOME/USERPROFILE=`AC`，TEMP/TMP=`AC\Temp`；CODEX_HOME 不在 TEMP 内。Temp 创建前后均检查无 reparse。未复制真实目录或资料，不设置额外 DACL/IL，也不调整 D 盘任何祖先；CLI exe 仍只复制到本次 D 根 RX，固定 pin/启动 args/config/网络 SID/Job/stdio/通过条件不变。

正常清理和恢复统一按规范 attempt 派生的原 name 调用 [DeleteAppContainerProfile](https://learn.microsoft.com/en-us/windows/win32/api/userenv/nf-userenv-deleteappcontainerprofile)，不自行递归删除任意目录。API 成功后，对固定 `hostLocal\Packages\name` 调用 GetAttributes，只有明确 FileNotFound/DirectoryNotFound 才报告 `profile_storage_absent_verified=true`；残留、访问错误或其它异常保持 cleanup_pending。目录校验失败也只调用本次 own profile 的删除 API，不删除返回的可疑路径。已有 child exit/Jobzero 顺序仍是前提；官方亦要求先关闭 profile 存储句柄以避免不完整删除。

CLI journal 仍为 **p6_r7_owned_cli_startup_v1**，report 才是 p6_r7_cli_startup_candidate_v1；Policy.OwnedImage 的固定 codex.exe/hash 约束和恢复严格 schema 均保留，没有新增路径字段。新增后置存储检查也用于恢复和内置 synthetic 的 own profile 清理；尚无 v9 实际清理证据。

专项最终 **33/33 passed，0 skipped**；固定 v9 exe `--self-test` **87 项 + ABI** 通过。新增十项纯检查覆盖精确 profile 范围、相邻 profile、额外层级、dot segment、错误根和 name 注入拒绝；现有环境检查更新为全部关键映射。只编译/self-test，未 apply/UAC/运行真实 CLI/账户/模型。

| v9 冻结候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.profile-layout-v9.exe` | `343708AE0ED2AD6BFE719624B00558AD53158632CED62A7DE4949F7676BA8D3B` |
| C# source | `17A028BC664E043C3DCA8E88CC4E51DB854B36C55E5CD27E52005F1D1757D26F` |
| Node test | `0B536BBBA0990677B4E23C9B77F0BB25C42E07BB24750170BC8BB48F94804DD1` |

主控复核后使用 v9 exe 的 `--apply-cli-startup-synthetic <verified-absolute-codex.exe>`。旧 exe/原始报告保留，历史通过结果不继承给此候选。

## 无认证 CLI 启动错误脱敏摘录 v8（历史，已由主控 apply）

仅在现有无认证 CLI 启动入口输出 `synthetic_startup_stderr_excerpt`；不扩固定关键词分类、不改启动参数/环境/ACL/IL/Job/WFP、不接生产响应诊断。输入仍为现有 stderr 的完整 EOF 缓冲，上限 256 KiB、严格 UTF-8，并要求对应固定 Root 下本次 32 位 hex attempt。没有新账户或 home 来源。

产物固定 schema 为 diagnostic_only=true、status、text、truncated、sensitive_lines_removed。先移除 ANSI 控制序列和控制/格式字符（保留规范化换行），再丢弃疑似 credential、authorization、cookie、token、header 或 key 值所在整行；随后将本 attempt 根路径替换为 `<ATTEMPT>`、Windows 用户目录路径替换为 `<WINDOWS_USER_PATH>`。最后按 UTF-8 完整字符截断至最多 4096 字节。错误正文经过这些处理后才允许写报告；普通 Error/os5 原样保留，不再仅凭固定分类猜根因。过滤是本入口的有限脱敏规则，**不是任意未知敏感文本的通用安全保证**；因此不得复用到真实 home、账户或生产 provider 响应。

专项最终 **33/33 passed，0 skipped**；固定 exe self-test **77 项 + ABI** 通过。新增八项纯测试覆盖三种 attempt 路径形式、用户路径、敏感整行拒绝、控制字符、中文 UTF-8 字节截断、无效 UTF-8、输入/目录范围拒绝及普通错误链保留。本轮未 apply/UAC，也未读取启动错误原文。首次专项因合成测试句出现旧静态扫描禁止的连续字面量而失败；仅拆分该测试句的源码字面量后重跑通过，实际被测内容和旧禁止断言均不变。

| v8 冻结候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.startup-excerpt-v8.exe` | `6BBBD0555A57FA7DCD4B397BC95299ED0BB2671D2DFE79D0CC13E5E3852C774C` |
| C# source | `B569E8264614B59D9AF5B16090EF9D08D5538C9732C917E4C5E1139344777DAD` |
| Node test | `84BBA548718721B70FA0AA5985267243947F531F7BFFD144B82D7654C9D41BFD` |

主控复核后使用 v8 exe 的 `--apply-cli-startup-synthetic <verified-absolute-codex.exe>`。旧报告及 exe 保留；没有继承 v7 的实测通过结论。

## 内置 worker 文件写能力 v7（历史，已实际通过）

主控实际执行 attempt `19f946d5-a830-41b1-a3ec-e3b2430bc10b`。本 worker 只读复核报告 `tmp/p6-r7-review/native-synthetic-04-file-probe.json` 及 SHA-256 `E2ACC347922D6DCB0730E4015AC40316F0719933B25CCDB1D92184BBDC163A52`：worker_file_probe_passed=true，五类文件失败位均 false；原 TCP/UDP 正负控、正确/错误 peer、子进程拒绝全部通过；process_exit_observed/job_zero_proven=true，cleanup_pending=false，无遗留 deny/profile，0 真实请求。只对下表 v7 source/exe 成立；这证明同样目录模式下内置 worker 实际文件操作可用，不能把当前 CLI 失败归咎于“此模式必然不可写”。

主控实际 v6 startup03 attempt `d2bf7c3b-7d88-494d-adca-8e30b6a9b2cc` 仍失败；报告 `tmp/p6-r7-review/native-cli-startup-03.json` SHA-256 `679F8CDA6CCE169B904428A34C7347242590132A483CF8B74C0019A5C5008572`。主控回报 exit 1、清理完成、0 HTTP/turn；九角色中仅 arg0_alias_warning=true，temp_root_refused=false。create_failed 可能仅来自非致命告警，不能当成致命创建失败位置。

v7 采用实际内置 AppContainer worker 文件探针，**不采用令牌 impersonation，不增加相关 API**。仅在 `--apply-synthetic` 下由父进程预建本 attempt 的 `work/empty-write-probe`，继承现有 work 的 SID Modify DACL；不设新 IL、不改权限、capabilities、Job 或 WFP。真实 CLI 启动入口行为保持原样。

worker 核验自己的 exe 所属目录为固定 Root 下 UUID attempt，且 cwd 精确等于该 attempt 的 work，拒绝 reparse 路径；只操作 `empty-write-probe/p6-r7-fixed-write.tmp`。使用 native `CreateFileW` 的 `CREATE_NEW`、GENERIC_WRITE、share=0；写固定公开字节 `P6_R7_FILE_OK` 且要求完整写入，再实际 CloseHandle、DeleteFileW。已有文件不打开、不读取、不覆盖、不删除；仅删除本轮确认创建且关闭的固定文件。无法关闭或删除时探针失败，可能留下这个固定合成文件，报告相应失败布尔；不会把网络/profile 清理完成说成磁盘目录全部删除。

worker 退出码新增 completion 位 256；create/write/close/delete 失败位分别为 16/32/64/128，scope 或 native exception 为 512。原网络/子进程位 1/2/4/8 保留。父进程只在实际退出且有 completion 标记、没有未知位时解读固定布尔，普通异常退出 0/3 或未知码不能冒充文件通过。`worker_file_probe_passed` 必须 completion 且所有文件失败位为零；新的 `synthetic_passed` 要求退出码精确 256 及全部原网络/进程条件。外层 helper 成功仍 exit 0。

此探针验证**同样目录 ACL 模式下，内置 worker 实际 AppContainer 令牌**的普通文件 create/write/close/delete 能力；不是 CLI 精确令牌验证，不证明 CLI 目录、管道或所有启动动作兼容。无论结果如何，不据此自动调整权限或签发生产/停止回执。

冻结时本地专项 **33/33 passed，0 skipped**；固定 v7 exe `--self-test` **69 项 + ABI** 通过。新增六项纯检查验证完成标记、五个文件失败位、异常退出码拒绝。worker 的本地测试只编译及调用惯有只读入口；后续主控的实际文件访问证据已列于本节开头。

| v7 冻结候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.file-probe-v7.exe` | `3125D7804960ECCD8DF69DC0179332A5AAFB623BC6F9B194591B0FEAD0B49BB8` |
| C# source | `9A5AEF5F7A584D3BC4961931B41724EE7D515192B4ABB878D7F74683A35205F2` |
| Node test | `3FD26922533EE1D459E338A8902BF8859045B737E395019A27D34A922BB37DC9` |

主控复核后的固定入口为 v7 exe 加 `--apply-synthetic`；不需要 CLI 路径。旧 exe 与原始报告保留；v3 历史矩阵通过不继承给 v7。

## 固定创建目标线索 v6（历史，已由主控 apply）

主控实际 v5b startup02 attempt `80318730-1f6f-4742-a399-510a5e9d40d2` 仍未通过；报告 `tmp/p6-r7-review/native-cli-startup-02.json` SHA-256 `2B81AEF372693AA38FE7FF918D61C755C197B80509F7C30E1670038FA8F57E68`。主控回报：初始化前实际退出码 1，stdout 0、stderr 374，固定分类 create_failed/access_denied、os error 5；退出、Jobzero、清理完成，0 HTTP/turn。原始报告保持不变。

v6 只在 `stderr_diagnostic.target_roles` 增加九个源内固定布尔：pipe、socketpair、socket、initial_log_file、log_directory、plugin_data_directory、private_app_server_socket_directory、arg0_alias_warning、arg0_temp_root_refused。前三类及日志/插件/私有 socket 目录短语来自主控对固定 CLI 公开二进制常量的只读核对，不能据“二进制包含短语”推断该路径本次已执行。arg0 两项另有版本匹配官方源码支持。所有角色始终存在；空输入/无效 UTF-8/超限时全 false；不输出原始文本、路径或任意输入键，socketpair 不会因前缀重叠误标 socket。命中只是文字线索，不是根因判定。

[官方 rust-v0.153.4 arg0 源码](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/arg0/src/lib.rs#L315) 在 release 模式拒绝把 helper aliases 建在系统临时目录内，但 [调用处](https://github.com/openai/codex/blob/rust-v0.153.4/codex-rs/arg0/src/lib.rs#L163) 对此只告警并继续。当前合成 CODEX_HOME 与 TEMP/TMP 相同，可能触发这条告警；这不证明它导致退出码 1。当前证据也不能从 os error 5、空 home、SID Modify DACL 推断是目录/MIC、内部 pipe/socketpair 或网络规则导致。版本匹配源码不等于已证明固定二进制与该源码构建完全一致。

本轮不改任何环境、启动参数、ACL、IL、Job、WFP、通过门槛或旧错误分类；不增加目录写探针。专项 **33/33 passed，0 skipped**；固定 v6 exe `--self-test` **63 项 + ABI** 通过。新增 11 项纯检查覆盖九角色独立匹配、未知目标不推断、无效 UTF-8、固定键/布尔及 PRIVATE/路径脱敏。未执行 apply/UAC/真实 CLI/账户/模型。

| v6 冻结候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.startup-diagnostic-v6.exe` | `233CEC56677D30D51651E46B209BAD2A3099E4AF8978BCB72657A05E4F8BF4B0` |
| C# source | `FFDD5F9C5090E916AC42EEF2902F1F47825A5C07579938D419B4CAB6146147BA` |
| Node test | `FBB614ADA52ABF3EE0AB8D697B4C1DEC4A7725316C6C96FF39D844C3B49E5076` |

主控审核后沿用 startup 命令，仅将 helper 改成 `.startup-diagnostic-v6.exe`；所有旧版本 exe 保留。本轮没有继承 v3 的实际矩阵通过结论，生产/人工 Gate 仍 false。

## CLI 初始化前退出的诊断候选 v5b（历史，已由主控 apply）

独立审计后的唯一收紧：未知 os error 只输出 `has_unknown_os_error` 布尔，不输出次数。v5 exe 保留；v5b 最终专项仍 33/33，self-test 52 项及 ABI 通过。

主控实际 v4b startup01 attempt `e027935c-1d0e-4139-837c-7af056e93477` 未通过。只读核对 `tmp/p6-r7-review/native-cli-startup-01.json`，hash `F1CAA9D1EC9FB10534024AD297638BDC817487A4F32F3AFC1FF8F557B9D9EE59`：CLI 已创建且 token/caps/hash/Job 检查通过，但 `cli_initialize` 阶段 `stdout_closed_before_reply`，stdout 0 字节、stderr 374 字节；0 HTTP/0 model，读线程 EOF、进程退出、实际 Jobzero 和清理完成。旧报告及各版本 exe 不改。

v5 只加诊断，不改权限、ACL、IL、启动参数、Job 或网络规则：

- `StopAndProveZero` 在任何 Terminate 调用之前，先检查持有的 CLI handle 是否已 signaled。只有此时成功取得的 DWORD 才报告 `child_exit_code_before_termination`，并设置 observed=true；仍运行时不把 cleanup 的终止码当成原始退出码。查询失败单列布尔。
- stderr 只在内存有界收集，完整 EOF 后匹配固定源内词表。报告仅含 `diagnostic_only`、固定 status/categories、固定已知 os error 数字集合和是否出现未知 os error 的布尔；不保存原始 stderr、任意键、路径、用户名、配置值或错误片段。字节副本使用后清零；不会把原文交给模型或写报告。
- 固定分类包括 access_denied、invalid_config、config_related、parse_failure、invalid_arguments、path_not_found、initialization_failed，以及分别的 create_failed/read_failed/open_failed/write_failed。它们只是关键字线索，**不是失败根因判定**。os error 只允许源内枚举 `2/3/5/13/32/50/87/203/740/1314`，未知数值不输出。
- 清理/读线程/broker 等次级故障单列 diagnostic 字段，不覆盖已有 `error_code`。原始 `stdout_closed_before_reply` 因而不会被 generic 读线程错误掩盖。其他通过/清理门槛保持不变。

本地专项 **33/33 passed，0 skipped**；固定 exe self-test **52 项 + ABI** 通过，包括 PRIVATE/路径/邮箱/未知数字不泄漏、分类区分、空 stderr、无效 UTF-8、超限和首个错误码保留。未 apply/UAC，未运行账户/模型。

| v5b 候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.startup-diagnostic-v5b.exe` | `5441BAD742880CC0C03D862DF4AF57829A07AF992D0408BF7CE395913A90A93D` |
| C# source | `17DCD751D696EC983906F7950599C573D910444D26F994528E24396A50D57230` |
| Node test | `6E8C46AE8762A8528174AAB4A25E72F35CA86FE54CF38733FD7AE839476C1151` |

主控审核后沿用下方 startup 命令，仅把 helper 路径换为 `.startup-diagnostic-v5b.exe`。原 v4b/v5 hash 不再对应当前源码。

调查边界：[GetExitCodeProcess](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getexitcodeprocess) 说明退出码可能来自正常返回、显式终止或异常，因此先观察 signaled 再采集、且在主动终止前记录。[MIC 文档](https://learn.microsoft.com/en-us/windows/win32/secauthz/mandatory-integrity-control) 表明完整性检查独立于 DACL，未标记对象通常按 Medium 对待；当前 source 只设置 DACL，没有显式设置低完整性标签。不过这不能从 374 字节计数推断失败原因：配置解析错误、路径读取/创建失败仍都可能。主控的只读检查发现 empty-home 无文件、SID Modify DACL、没有显式 ML 标签，尚不据此修改权限；等待 v5 的受限分类和退出码再定位。

## 真实 pinned CLI 启动候选 v4b（历史设计，实际结果见上）

新增固定入口 `--apply-cli-startup-synthetic <absolute-codex.exe>`，只接受 SHA-256 `3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004`。复制的唯一输入文件为该 exe；新 attempt 的 `work/empty-home` 和 `work/empty-workspace` 都为空。环境只用已知 Windows 目录和合成 home 派生，固定十键；不读/复制认证或用户环境。

可复用 `RedirectedStdio` 只把 stdin-read、stdout-write、stderr-write 三句柄列入 `PROC_THREAD_ATTRIBUTE_HANDLE_LIST`，相应 `bInheritHandles=true`、STARTF_USESTDHANDLES；父端先去掉继承位，Job及控制资源不在名单。原子 JOB_LIST、零 capabilities、Job active=1 保持不变。stdout/stderr 独立线程并行排空，限制总字节/行长度/队列数量，UTF-8 无效或读取线程错误都会使用例失败；stderr 只报字节数，不输出正文。

固定命令为 `app-server --listen stdio://` 及同步自 R6 `restrictions(false)` 的禁用参数；agents=false，provider 只向唯一回环 broker，`requires_openai_auth=false`，无 env_key/bearer/header 注入，重试和 websockets 禁用。唯一协议序列：`initialize(id=1)` → `initialized` → `config/read(id=2, includeLayers=true)` → stdin EOF。**没有 account、thread、turn 请求**。配置只输出匹配布尔；每个 serverRequest 都拒绝并使测试失败。本机 broker 只有拒绝响应，没有内置 fake provider、没有 C# 文字 gate；CLI 任何本地 HTTP 尝试也使此启动用例失败。

报告 schema 为 `p6_r7_cli_startup_candidate_v1`，`cli_startup_passed` 必须同时满足初始化/配置成功、stdin EOF 后 5 秒内进程退出、读线程完整结束无错误、实际 Jobzero 和清理成功。EOF 未退出仍强制清理，但**本用例不通过**。`synthetic_passed` 保持 false，不把未执行的 CLI TCP/UDP 负控混入旧矩阵。异常/超时使用同一 finally 的终止、进程关闭和 Jobzero gate；不能证明归零就留拒绝规则。

新 journal 固定 schema `p6_r7_owned_cli_startup_v1`，仅允许 `codex.exe` 且 hash 必须等于源内固定 pin；恢复不信任任意 journal 路径/hash。旧 schema 仅 `synthetic-worker.exe`，且 hash 必须是已知 v1/v2/v3 helper 或当前正在执行的 helper；不再信任自由填写的 helper hash。恢复仍只接受规范 UUID 派生目录，missing binding 保持 fail-closed。

本地专项 **33/33 passed，0 skipped**；v4b 固定 exe `--self-test` **44 项 + ABI** 通过。仅编译和只读测试；**未 apply/UAC，真实 CLI 的 stdio 继承、配置回显和正常退出兼容性尚待主控运行**。旧 v4 编译候选保留，但未作为正式候选执行。

| v4b 候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.cli-startup-v4b.exe` | `677B1197DA04F3FC938D8D7DAF980978BD6576E135C6BF7F27835A7C2473B74D` |
| C# source | `6746B4FA6C22439E961A0C08EAEA28E7BD5DC5A460294B6FF7F86720F1A635D8` |
| Node test | `8E86E03531B6DBEFC15DACA5255C903FF403B6925DE889103DB21F1F1C9ECAB8` |

主控审核后可用下式（worker 未运行；路径含空格时保留内层引号）：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.cli-startup-v4b.exe' -ArgumentList @('--apply-cli-startup-synthetic','"<verified-absolute-codex.exe>"') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
```

后续生产可复用 stdio/Job/peer 原语，但仍需独立实现跨 UAC IPC。`CodexAppServerClient` 的实际注入口是 `spawnImpl`（不是 spawnFactory），同步返回 ChildProcess-like；应先异步完成 native ready，再创建同步 adapter。UAC 的 ShellExecute/runas 不能直接与标准重定向混用，当前固定 C# 协议正是为避免提前引入桥接。未来建议唯一、拒绝远程、固定用户 ACL 的命名管道，握手绑定宿主 PID/创建时间；控制管道绝不传给 CLI。IPC close/helper exit 不能映射为 CLI close；只允许 native 精确退出+Jobzero 证据触发 adapter close。现有 `request()` 在 stdin.write 返回后立即调用 onDispatched，未来必须补 native-write ACK 才能把该回调作为真正 CLI 派发点；IPC 入队不能冒充 interrupt 已派发。

Node 双向文字门尚未接到这个入口。后续最短复用路线是 native broker 在读取请求前做 peer admission，经受控 IPC 交给现有 Node `exchangeTextOnly`；无认证首次 turn 可把上游固定为本机合成 provider，仍须走同一 Node 双门。仅内置假 SSE 只能证明 CLI 协议兼容，不能当成双门或生产隔离证据。新 CLI 应用 `workbench_text_task_runtime_pin.mjs` 的 pin；旧 R6 runtime pin 和必须有 chatgpt 账户的 live probe 主入口不能直接复用。

来源：[HANDLE_LIST 的继承契约](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)、[标准输出重定向要求 UseShellExecute=false](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.redirectstandardoutput?view=netframework-4.8.1)、[命名管道拒绝远程/首实例标志](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createnamedpipea)、[GetNamedPipeClientProcessId](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getnamedpipeclientprocessid)。

## Win32 203 后的最小环境候选 v3（历史设计，实际结果见上）

主控第二次 apply，attempt `44077d4d-3092-4ec4-99bb-a0bee92d3ea6`，复制证据 `tmp/p6-r7-review/native-synthetic-02.json` 已只读核对：`appcontainer_spawn_failed` / `win32_error=203`，未创建 child，全部本次资源清理完成，0 真实请求。旧报告及 v1/v2 exe 保留不改。

Microsoft [错误码表](https://learn.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-) 将 203 定义为 `ERROR_ENVVAR_NOT_FOUND`。[AppContainer 创建文档](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer) 说明 LOCALAPPDATA 及 TEMP/TMP 的 profile 作用。直接实现证据是 [Chromium 提交 e879db3b2fa4d06359ec4d6a7d9419d73e49838f](https://chromium.googlesource.com/chromium/src/+/e879db3b2fa4d06359ec4d6a7d9419d73e49838f)：其环境过滤说明 AppContainer 需要 LOCALAPPDATA、TEMP/TMP。

v2 已有 TEMP/TMP 而缺 LOCALAPPDATA，因此 v3 **只新增 `LOCALAPPDATA=<本 attempt 已有 work 目录>`**。完整白名单只含六键：LOCALAPPDATA、PATH、SystemRoot、TEMP、TMP、WINDIR，按名称排序；Windows 路径来自已有系统目录 API，三个可写路径均指向合成 work。没有读取/复制真实用户环境或凭据，没有新增目录、ACL、capability，没有改原子 Job/创建 flags。随后主控 v3 apply 成功，支持此最小修复；独立候选和报告 hash 见顶部，不能推及新 v4b。

专项 **31/31 passed，0 skipped**；固定产物 self-test **33 项 + ABI** 通过，包含精确六键、双 NUL 结尾、带空格合成路径、拒绝相对路径和嵌入 NUL 注入。测试不调用 apply/recover/worker；worker 未执行 UAC。

| 当前候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.new-v3.exe` | `7009C3A65DF9A5302A59DB686F359D1B9E11F9C4C09A8D702A47E10A2F09C9F7` |
| C# source | `0E8F6687A54CB41D8CE76A067F3B477F87B4051AA2E4B6CAF7B3C73F7D17B6E8` |
| Node test | `D9C7272D96C701F8E55FB00348733D1C3EAF16904F85E33A0E300AF2AA4CABB3` |

当前候选编译参数与下方相同，输出文件改为 `.new-v3.exe`；主控后续审核/提权须使用此版本及 hash。生产隔离、停止回执和人工 Gate 仍未通过。

## 首轮 apply 后的诊断候选 v2（历史）

主控执行 attempt `1ace587e-52c7-4191-8e8f-3d1f1abb6cd7` 后，worker 仅经只读权限核对其不可变 `report.json`：TCP4/6、UDP4/6 正控均成功，WFP transaction committed，loopback 两次写成功且无冲突；失败点为 `appcontainer_spawn_failed`，未创建 child；清理 pending=false，规则及 profile 均未保留。此证据不等于 AppContainer 创建/网络隔离验收通过。原报告和原 exe 均未修改。

当前最小改动：`CreateProcessW` 返回后立刻缓存 `Marshal.GetLastWin32Error()`，失败报告只增加 uint `win32_error`，不输出原错误消息、参数或路径；另外按官方契约把属性值内存保持至 `DeleteProcThreadAttributeList` 之后释放。后者发生在创建调用之后，**不能据此解释首轮 CreateProcess 返回失败**。未改 ACL、权限、capabilities、Job、创建 flags 或生产 profile。

当前验证：专项 **31/31 passed，0 skipped**，self-test 增至 **29 项**（新增成功时忽略 stale error、失败保留数字、普通异常消息脱敏），x64 ABI 断言通过。只编译和运行只读 self-test，worker 未执行下一次 apply/UAC。

| 当前候选 | SHA-256 |
| --- | --- |
| `D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.diagnostic-v2.exe` | `4986DC62DADF78CB6D9091069234C8FCB776219FED4A1D7356874952DE380A85` |
| C# source | `2A6BEE08D92EE8CF09F8C971453D90FE825D8CE93638150FC3FEC54B64805A68` |
| Node test | `596D76884107B12CF68597F91ECE25396BA56AD59EEFA08328F2F3FB06D70541` |

[CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw) 要求失败读 GetLastError、扩展属性使用 STARTUPINFOEX + EXTENDED_STARTUPINFO_PRESENT、Unicode 环境设置相应 flag；当前实现符合这些入口条件。[UpdateProcThreadAttribute](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute) 将 SECURITY_CAPABILITIES 与 JOB_LIST 均列为受支持属性，JOB_LIST 为 HANDLE 数组且 Win10+ 支持；没有找到官方禁止二者组合的规则。属性值必须存活至属性列表销毁。**没有原始 Win32 数字时不能在权限/路径访问、Job 关联条件、其他参数校验之间可靠排序，先保留约束取得错误码，不推测性修改权限。**

主控独立审核后若决定重跑，应使用上表 `.diagnostic-v2.exe` 路径及 hash；下方首包命令/哈希仅保留历史，不是当前候选。

## 首包冻结时证据（历史）

- 已用现有 Framework64 `csc.exe` 编译 x64；专项 `node --test tools/dev_agent_bridge/windows_text_gate_isolation_helper.test.mjs` **31/31 passed，0 skipped**（30 子项及外层）。测试只运行 plan、recovery-plan、参数拒绝及 self-test。
- `--self-test` 为 **26 项纯策略/tuple/cleanup 断言**及 x64 ABI size/offset 断言；不创建 AppContainer、Job、socket 或 WFP 对象。
- 固定产物再次执行 `--plan`、`--self-test` 成功。**没有执行 apply、recover、真实 CLI 或真实网络请求**。原生执行效果、崩溃恢复和生产接线均未验收。
- 所有报告保持 `production_isolation_passed=false`、`human_gate_passed=false`、`real_upstream_requests=0`，不签发 stop receipt。

固定产物：`D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.exe`

| 文件 | SHA-256 |
| --- | --- |
| 固定 exe | `0AA780F653B98D7993D9A317EC688131B9002DB6808A07097837D0F315A2B992` |
| C# source | `B1EA375FB7B705D9E2E6EEC14FBB51DC8831E8A5E89B3F7BD9330C1F9D6A99CD` |
| Node test | `B17BA531CE8293316022C4D632D47BEEEE5B696311C400C58D3E854AB61C20FE` |

Framework 编译产物可能因编译时间变化而改变 hash；提权时核对上面这一个产物，不沿用重新编译前的 hash。

## 最小边界及能力条件

威胁模型是受信宿主、受信且固定 hash 的 CLI，约束模型诱发的执行/联网路径。没有声称抵抗已被攻陷的同一用户、CLI、管理员或内核。父窗提供的新 CLI `0.153.4` / `7ac07f4ce733f89a` / hash `3d6ca7085c932b62ef4ee4877e92f15b050fb94b2eb8e6c10a346a06248c6004` 尚未在本 helper 内运行。

1. 每 attempt 随机 GUID 派生唯一 AppContainer profile/SID；token capability 数量为 0。只有新建合成目录给该 SID 权限，不修改普通 Codex 目录。
2. 创建 Job 后设置 active process limit=1、kill-on-close、无 breakaway；通过 `PROC_THREAD_ATTRIBUTE_JOB_LIST` **在 CreateProcess 时原子入 Job**，不存在创建后再 AssignJob 的空窗。进程先 suspended，核对 SID、空 capabilities、image、SHA-256、创建时间，再把绑定持久写入 journal，最后 Resume。
3. 私有 WFP sublayer，恰好三个按 package SID 的 ALE connect 过滤器：高权重允许唯一 IPv4 `127.0.0.1:brokerPort` TCP；低权重拒绝该 SID 其他 IPv4；拒绝该 SID 全部 IPv6。拒绝规则不按常规 Codex 路径匹配，不改其他应用规则。
4. WFP session 非 dynamic、filter 非 persistent：helper 崩溃不会因 session 关闭自动撤销拒绝；**BFE 重启/系统重启后的存续不保证**。没有安装驱动/SDK/服务。
5. broker 在读取任何请求字节前，同步 owner TCP table 检查 ESTABLISHED、完整反向四元组、唯一匹配 PID；持有的进程 handle/创建时间/SID 前后复核。表快照失败或抖动拒绝。未声称这是 socket 内核令牌；受信 CLI 主动转交 socket 或受攻击管理员不在当前假设内。

`RestrictedProcess`、`NetworkBoundary`、`PeerAdmission` 是可复用原语；当前公开命令只允许内置无认证 worker。**尚无实际 CLI stdio bridge、双向文字门 host 接线、真实停止回执或取消/执行/恢复产品验收。**

现有系统为 Windows 25H2 / build 26200，Framework64 编译器存在；真正 apply 需要 BFE/网络隔离 API 可用及管理员 WFP/loopback 权限。跨 sublayer 的外部 WFP 策略仍可能改变行为，必须依据本机正负控结果判定。

## 全部系统修改范围与 RMW 限制

显式 apply 的修改仅限：一个随机 AppContainer profile、一个 GUID 派生 WFP sublayer 和三个过滤器、loopback exemption **整表 RMW 中增删本 attempt SID**、新建 attempt/work 目录 ACL。另写合成 exe/journal/report 到固定 `D:\memex\tmp\p6-r7-isolation\<attempt N>`；报告只含合成标识、布尔/计数及稳定错误码。

NetworkIsolation 公共 API 只有 Get/Set 全表。私有 mutex 只协调同系列 helper。实现读取当前表、写前再次比较、写后全表比较；清理从最新表只删除 own SID，**从不恢复旧整表快照**。这能检测部分冲突，不能消除最后一次 read/set 之间的竞争，也不能阻止 verify 后外部覆盖。

因此 apply/recover 的条件是主控已确认的维护窗口：没有并行管理员或服务写网络隔离配置。**不承诺保留全部并发变更，不称为 CAS。** 检测到冲突或 post-verify 不一致后保留拒绝规则，报告 `cleanup_pending`，后续恢复也拒绝自动清除该冲突，需要人工对当前表核对。

## 只读、提权与恢复命令

复编译（不更改网络/权限）：

```powershell
$r7Build = 'D:\memex\tmp\p6-r7-helper'
New-Item -ItemType Directory -Force -Path $r7Build | Out-Null
& 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe' /nologo /target:exe /platform:x64 /optimize+ /reference:System.Web.Extensions.dll /out:"$r7Build\windows_text_gate_isolation_helper.exe" 'D:\memex\tools\dev_agent_bridge\windows_text_gate_isolation_helper.cs'
& "$r7Build\windows_text_gate_isolation_helper.exe" --plan
& "$r7Build\windows_text_gate_isolation_helper.exe" --self-test
Get-FileHash -Algorithm SHA256 -LiteralPath "$r7Build\windows_text_gate_isolation_helper.exe"
```

主控核实候选 hash、独立 review 和维护窗口后，最小提权调用（worker **未执行**）：

```powershell
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.exe' -ArgumentList '--apply-synthetic' -Verb RunAs -WindowStyle Hidden -Wait -PassThru
```

结果在固定 Root 的本次随机目录 `report.json`；manifest 为 `ownership.json`。未提供任意 workspace、worker、credential、provider 或外部 URL 参数。

恢复只接受实际报告/journal 中的规范小写 UUID-D，不接受任意 manifest 路径。先只读展示派生范围，再由主控提权运行（替换占位符；worker **未执行**）：

```powershell
& 'D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.exe' --recovery-plan '<attempt-uuid>'
Start-Process -FilePath 'D:\memex\tmp\p6-r7-helper\windows_text_gate_isolation_helper.exe' -ArgumentList @('--recover-synthetic','<attempt-uuid>') -Verb RunAs -WindowStyle Hidden -Wait -PassThru
```

恢复校验固定目录及祖先无 reparse；journal <=16 KiB、固定 schema/键/规范序列化、固定 image basename/hash/owner PID+creation；resource GUID/profile 全由 attempt 推导，不接受 journal 自由路径。原宿主 PID+创建时间仍存活时拒绝恢复。WFP 对象逐个读回验证 SID/layer/action/condition 范围后才可删除。

## 关闭与真实回收能力

正常结束先关闭 broker/listeners，再终止 Job、等待进程退出并实际查询 Job active=0，才去掉 own loopback exemption，再事务删除 own WFP keys，最后删除 own profile。未创建进程是独立的 `cleanup_no_child_created`，不包装成已测 Jobzero。若进程退出或 Jobzero 无法证明，则不移除拒绝。

崩溃恢复依赖原子 singleton Job 及持久绑定：精确 PID 已不存在、PID 已复用（不触碰替代进程）、或原进程已 signaled，均是原绑定关闭证据；仍存活则先验证 creation/image/SID/hash，再终止持有的精确 handle 并等待。恢复报告标注此证据来源，**不是原 Job 的实时查询结果**。

在 `creation_started=true` 写入后、PID/creation 绑定持久化前崩溃，Job kill-on-close 应限制悬挂进程，但恢复入口没有足够绑定证明，返回 `recovery_binding_missing` 并保留规则/待办。没有凭缺失记录推定归零。profile 尚未创建或已经被删除时的 DeleteProfile 返回差异也可能保守留下 pending；本包未做泛化删除或 own SID 全进程枚举。

若 WFP 读取未完成，恢复报告 `deny_rules_state=unverified`，不声称规则不存在。读/写冲突时不回滚旧表。生成的 attempt 目录与合成报告保留供审查，不递归删除。崩溃后实际恢复、重启/BFE 重启清理以及故障注入均待主控执行验证。

## 原生合成验收矩阵（分项实际状态）

| 项目 | 正控/拒绝与通过条件 | 实际状态 |
| --- | --- | --- |
| 本机目标可用 | 安装隔离前宿主实际 TCP4/6 connect + accept 清空；UDP4/6 send + recv 清空 | v3、v7 内置矩阵已通过 |
| 唯一 broker | 正确 peer 固定 marker/ACK；错误 peer 在读取 bytes 前拒绝 | v3、v7 已通过 |
| 其他 TCP4/6 | worker connect 失败，监听器无排队连接 | v3、v7 已通过 |
| UDP4/6 | 正控接收通过；容器发送后有界观察无数据 | v3、v7 已通过 |
| 子进程 | worker 尝试同 image leaf，Job active=1 阻止创建 | v3、v7 已通过 |
| 文件操作 | 相同目录模式下 worker 创建/写入/关闭/删除固定文件 | v7 已通过；非 CLI 精确令牌 |
| 正常关闭 | 进程退出、Job active=0、own exception/filters/profile 清理 | v3、v7 已通过 |
| 宿主强崩与恢复 | 创建前、创建/绑定间、Resume 后及清理中注入，未证归零不得删规则 | 尚未实测 |
| 配置冲突 | 模拟写前/写后不一致，pending、保留 deny、不恢复旧 snapshot | 尚未原生故障注入 |
| BFE/系统重启 | 验证中断及恢复；当前非 persistent 规则不保证重启后存续 | 尚未实测 |
| 非 loopback | 规则覆盖不等于公网阻断实测 | 尚未实测 |

## 主来源

- [AppContainer 实现](https://learn.microsoft.com/en-us/windows/win32/secauthz/implementing-an-appcontainer)；[UpdateProcThreadAttribute 的 JOB_LIST / SECURITY_CAPABILITIES](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-updateprocthreadattribute)。[官方 WinBase.h](https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/um/WinBase.h) 给出 JobList=13、INPUT=0x20000，因此常量为 0x2000d。
- [WFP 条件](https://learn.microsoft.com/en-us/windows/win32/fwp/filtering-condition-identifiers-)；[官方 fwpmu.h GUID](https://raw.githubusercontent.com/microsoft/win32metadata/main/generation/WinSDK/RecompiledIdlHeaders/um/fwpmu.h)；[过滤器仲裁](https://learn.microsoft.com/en-us/windows/win32/fwp/filter-arbitration)；[访问控制](https://learn.microsoft.com/en-us/windows/win32/fwp/access-control)；[session dynamic 生命周期](https://learn.microsoft.com/en-us/windows/win32/api/fwpmtypes/ns-fwpmtypes-fwpm_session0)。
- [GetAppContainerConfig](https://learn.microsoft.com/en-us/windows/win32/api/netfw/nf-netfw-networkisolationgetappcontainerconfig) 与 [SetAppContainerConfig](https://learn.microsoft.com/en-us/windows/win32/api/netfw/nf-netfw-networkisolationsetappcontainerconfig)：整表语义；Get 示例要求逐 SID 再数组 `HeapFree`。
- [GetExtendedTcpTable](https://learn.microsoft.com/en-us/windows/win32/api/iphlpapi/nf-iphlpapi-getextendedtcptable)；[MIB_TCPTABLE_OWNER_PID padding 警告](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcptable_owner_pid)；[六 DWORD row 定义](https://learn.microsoft.com/en-us/windows/win32/api/tcpmib/ns-tcpmib-mib_tcprow_owner_pid)。当前 x64 通过 Marshal 验证 count-to-row offset=4、row stride=24、PID offset=20，不假定指针大小就是表头大小。

这份候选只能进入主控的无认证 native synthetic 审核，不改变正式生产 profile 或完成 P6 人工 Gate。
