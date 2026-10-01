# P6 R7 AppId matrix WFP drop evidence — frozen 01

主控后续实际集成结果：冻结events01未改动；runtime v5在`5019bbd0-3999-4b6a-9346-cd85f040d51b`完整通过有界八项矩阵，collection/enumeration/resources均true，八角色各有1条精确匹配drop，原始同步错误码门仍false。actual05报告SHA `BF9DD260E9A215977FBEF70054D3618871B7CF0D4A7DE15A90A77B1480B32402`，native exit0及完整回收另由runtime回执证明。该实测覆盖当前IPv4/IPv6 tuple匹配路径，不外推到其他候选或全窗口生产隔离。详见[Runtime当前实测](P6_R7_WINDOWS_APPID_MATRIX_RUNTIME_HANDOFF.md)。以下为本模块交付时的说明。

日期：2026-09-12。此包只新增受限只读事件层；运行层集成、普通 Medium / owned probe / UAC helper 的身份与真实退出证明由主控及 runtime worker 负责。本 worker 未执行 WFP engine open、事件枚举、UAC、socket、子进程或实际入口。没有改全局事件设置、系统审核、网络配置、合同 01、旧 runtime/native 或 Git 索引。

## 交付与冻结

| 文件 | SHA-256 |
| --- | --- |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_events.cs` | `C6AAC8A35CE163CB0D4D3760C069220A95628579434B9CE18D6D8F282854E2C8` |
| `tools/dev_agent_bridge/windows_text_gate_appid_matrix_events.test.mjs` | `67E1496F2C5902B3D31240074ECE1628549F2A3289D5E2153BB5B24EB4EC66CD` |
| `tmp/p6-r7-review/native-appid-matrix-events-01.cs` | `C6AAC8A35CE163CB0D4D3760C069220A95628579434B9CE18D6D8F282854E2C8` |
| `tmp/p6-r7-review/native-appid-matrix-events-01.test.mjs` | `67E1496F2C5902B3D31240074ECE1628549F2A3289D5E2153BB5B24EB4EC66CD` |

快照使用禁止覆盖的复制创建。源码和测试现已停止编辑。相对审计过的 source `176DE5D9FD41D32B430ADCE4C8B1D0AECF583780880612647EDF228BD608CF40`，最终源码只多两行 IPv4 整数序注释，无逻辑变化；测试只多 IPv4 地址与端口反字节序两个负例，断言 262 → 264。没有独立 actual exe；组合运行产物由主控冻结。冻结 test 是字节证据，运行验证使用工具目录中的同 hash 测试（相对依赖路径以该目录为准）。

## 同程序集 API / 接线约定

类型为 `HereIAm.R7.MatrixNetEvents`，Framework C# 5 / x64。因 `MatrixExpected` 为 internal，方法同样 internal，联合编译的 runtime 可调用：

- `InstallBinding(MatrixExpected e, ushort weight, Action prove)`：重读现有 own sublayer 和全部 3 个 own filters，验证正确 Filter200、INDEXED64 条件、actual weight、AppId blob、全部规则字段；记录两个 deny filter 的真实 filterId 与真实 layerId。只读。失败不得阻断 runtime 继续清理已安装规则。
- `Capture(e, weight, binding, object probes, Action prove)`：再次验证规则和 ID，读取日志是否已开启；若可用，仅按 own AppId AND CLASSIFY_DROP 与非空 FILETIME 区间枚举。结束前再次重读相同规则/ID并 prove。失败返回不完整结果，runtime 必须继续规则清理。
- `ValidateBinding(e, weight, binding)` / `ValidateCapture(e, weight, binding, probes, capture)`：纯 exact-schema 与 expected 绑定校验；后者合法但不足时返回 false，畸形时固定错误。不可把 Deserialize 成功当验证成功。
- `SafeSummary(e, weight, binding, probes, capture)`：先执行完整校验，再输出固定 6 keys：`collection_enabled, enumeration_complete, resources_closed, error_stage, api_status, roles`。没有 nonce、hash、filterId、AppId、地址、端口或 raw event。
- `RetryPendingCloseOnly()`：仅对本模块静态持有的失败句柄再做最多 2 轮关闭；不重开引擎、不重新枚举/证明、不修改已产生的通过结果。当前 runtime 不追加调用，`FinishSession` 自身已经执行有限重试。

Binding exact 11 keys：`schema=matrix_own_drop_binding_v1, attempt_id, scope_id, nonce, image_sha256, appid_blob_sha256, assigned_weight, deny4_filter_id, deny6_filter_id, deny4_layer_id, deny6_layer_id`。filter ID 用正数 canonical decimal string，layer ID 用非零 UInt16 整数。

Probes exact 8 行、合同固定 role 顺序，每行 exact 8 keys：`role, local_address, local_port, remote_address, remote_port, ip_protocol, started_filetime, finished_filetime`。地址为 canonical scoped 字符串，双方为相同本机 fixture 地址，端口不同且排除 broker，protocol 为对应 6/17；FILETIME 为 canonical 正整数字符串，开始不早于 owner creation，每行最多 5 秒、总跨度最多 30 秒、后行开始不早于前行结束。外层 runtime 还用持有的私有文件与实际 probe 时段进一步绑定；本模块不查询全系统地址或进程。

Capture exact 13 keys：`schema=matrix_own_drop_capture_v1, attempt_id, nonce, binding_sha256, probes_sha256, capture_complete, all_roles_matched, collection_enabled, enumeration_exhausted, resources_closed, error_code, api_status, roles`。两 hash 为 canonical `MatrixRecords.Json` UTF-8 SHA-256。`roles` 每项只含 `role, matched, matched_count`。这不是 helper 身份回执：runtime 外层必须另行验证 helper lease、actual exit、规则 cleanup receipt，才可采用此结果。

固定 error_code/error_stage：0 完整；1 输入/布局；2 引擎/初次 own-rule 验证；3 事件设置只读检查；4 枚举 handle 创建；5 分页/解析；6 末次 own-rule 验证；7 原生资源关闭。`api_status` 为相关失败原生 API 的非零 DWORD，无法取得则 null；不输出异常原文。未启用返回 collection_enabled=false；未知为 null；绝不调用 SetOption。

## 匹配、资源和结论边界

模板必须同时有 AppId 与 CLASSIFY_DROP 两个条件，且时间窗非空。每次最多 8 页、每页 32（总 256）；最后一页不足 32 才认定枚举耗尽，到上限仍满页则 incomplete。Header0 的协议/IP 版本/地址/双方端口/AppId flags 必须存在，非零 IPv6 scope 必须有 scope flag 且相等；逐项精确匹配 own deny filterId、layerId、AppId bytes、协议、地址、端口、scope、该行时间。缺字段、未知、日志缺失、权限不够或超过界限均不通过。原生分配只释放顶层 API 返回内存，不单独释放事件内指针；未输出任何不匹配事件资料。

枚举 handle 销毁失败不丢弃指针，也不关掉其 engine。失败 session 进入静态强引用列表，有限 close-only 重试后若仍未关闭，保留至 helper 实际退出。关闭 API 第一次失败粘滞：即使重试真实成功，`resources_closed` 仍 false；不得用 runtime 的其他 kernel handlesclose 字段覆盖。InstallBinding close 失败不返回 binding；Capture close 失败强制 stage 7 / incomplete。规则 cleanup 无论事件层结果如何均继续。静态保留不是跨进程恢复日志，helper 的实际退出由外层独立证明。

IPv4 按 WFP UINT32 主机整数语义解释（127.0.0.1 为 0x7f000001），IPv6 按 16 地址字节。Header0 专页并未明确 IPv4 字节序，此处是与既有 WFP 规则整数一致的推导，不是已核实的专门文档承诺；实现不接受双序 fallback，纯测试显式拒绝反序。下一次 actual 若不能满足全部字段，结果保持 false，不能仅因无接收或日志缺失放宽。

## 已执行的纯验证

```powershell
node --test tools/dev_agent_bridge/windows_text_gate_appid_matrix_events.test.mjs
```

实际 exit 0，Node **4/4、0 skip**，托管纯断言 **264**，SDK compile-only **36** 项 `static_assert`。测试覆盖每个匹配字段/必需 flag、exact schema 缺失与坏类型、过期/重叠/超长时间窗、端口别名、hash 绑定、合法 incomplete 汇总、坏 api_status、计数上限、固定字节缓冲越界/长度/克隆、fake enum close 先失败后成功与持续失败保留/重试/粘滞失败。Fake closer 不调用真实 WFP。

测试使用 Framework64 `v4.0.30319/csc.exe /platform:x64 /warnaserror+ /reference:System.Web.Extensions.dll` 联合 frozen v10/v11c/v15/contract01/current native，指定纯 harness Main；临时测试 exe 不含 actual 调用路径。SDK `10.0.26100.0` 与 MSVC `14.50.35717` 用 `cl /c /TP /W4 /WX`，只产 obj、不链接/不执行。核实 Header88/Event104/Drop16/Template32/Layer72/Filter200/Value16 的字段 offset 及相关 flags/type；测试结束只回收本次已核 canonical 的临时目录。

依赖固定：v10 `D22017641D9F8DF750F6DB7DB9319B8C1930A726A8575FF1FFABFDE0D5FFDCD8`；v11c `C777023495CCDBF3B52663F49683F5D84DCFD03A36B3D280A75C925F37B7A1EA`；v15 `C1F07E9487B8CE25D0ACC2D5BBB03B69C975CBB7E448698D288FF6263CFF9311`；contract01 `F70FFB86CE5EFEA2572532E1986F77DDE9622893AD4B90A74F9EC40DA5BA6774`；native `F2D3B35A1E6D1763930BA7F9A82AB8DBB595E02D5D720216A0161DBCE8A0D0AB`。本包纯测试不依赖当前 socket/runtime 源。

## 官方依据与未执行部分

- [事件枚举模板](https://learn.microsoft.com/en-us/windows/win32/api/fwpmtypes/ns-fwpmtypes-fwpm_net_event_enum_template0)：起止 FILETIME 与 AND 条件；[CreateEnum](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmneteventcreateenumhandle0) 要求事件容器 ENUM 权限且不能在事务内调用。
- [Enum0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmneteventenum0)：枚举 handle 的时间点快照、指针数组及顶层释放约定；[DestroyEnum](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmneteventdestroyenumhandle0) 状态必须检查。没有把 engine close 猜成 enum 销毁成功。
- [GetOption0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmenginegetoption0)：只读引擎设置，需要 READ 权限；返回的 FWP_UINT32 0/1 与分配需释放。本模块没有 global setter、subscription 或 audit 设置。
- [Header0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmtypes/ns-fwpmtypes-fwpm_net_event_header0)、[Event0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmtypes/ns-fwpmtypes-fwpm_net_event0)、[ClassifyDrop0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmtypes/ns-fwpmtypes-fwpm_net_event_classify_drop0)：本包使用版本 0 的固定字段，drop 给出 filterId/layerId；没有 PID，不能替代外层 held child 身份绑定。
- [Logging](https://learn.microsoft.com/en-us/windows/win32/fwp/logging)：环形历史日志约 100–150 事件，可能被覆盖；少事件不能推定没有拒绝，更不能当通过。[Displaying Net Events](https://learn.microsoft.com/en-us/windows/win32/fwp/displaying-net-events) 的 InitFilterConditions 是示意空实现，本包不照搬成无过滤查询。

此前 runtime01 actual 报告 `tmp/p6-r7-review/native-appid-matrix-runtime-actual-01.json` SHA `C648AAD15E7CAF83D1687198CA6EBFA8CFD603232E4435BA32C024236028F336` 为完整 cleanup、pending=false，但 8 行负测未通过。本包未改其结果。新的 own-filter drop gate 只在主控审计并实际运行当前组合后才有原生证据；不升级 contract01，不证明真实 CLI、账户、生产或真实模型请求。
