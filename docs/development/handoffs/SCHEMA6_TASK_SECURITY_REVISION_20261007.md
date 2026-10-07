# 任务模板与最小权限修订验收（2026-10-07）

## 范围与门槛

用户已接受：模板显式 Unified=true；任务 DACL 为非 protected，仅本人、SYSTEM、Administrators 三类显式授权；注册输入与继承后预期分别批准和锁定。本轮仅源码、合成验证、CI和新固定候选，最终精确 XML/SDDL 交本人批准后才可重新进场。没有冻结/停启现役、Apply现役ACL、生产Prepare/注册、读原库、迁移/替换/head推进或手机操作。本机真实任务四次创建额度已用完，本轮不新增创建。

基线 v3-lab@72905f6f9bf5753de68b31b8f89d6ec7427db30a（已授权合并PR16）。独立分支 codex/core-cutover-20261007-r02，不把私人D目录历史带入GitHub。本轮新PR不自动合入主线；B独立源码窗口继续。

## 实现

- 固定47项中仅 lifecycle/prepare_login_schema6.ps1 的 XML 模板增加 `<UseUnifiedSchedulingEngine>true</UseUnifiedSchedulingEngine>`。其余设置及Actions/Principals/Triggers不变；会话启动器、Core、MCP运行字节不变。新模板使库存变化，必须新构建，不能沿用旧manifest。
- 新 task_security_policy.ps1 在固定runtime之外；从 registrationSddl 与已批准父SD独立推导 expectedRegisteredSddl：仅OI传播至非容器，继承标志ID，CO/CG映射至子owner/group，generic文件权限显式映射。拒绝不支持的ACE/flags/rights；actual绝不回填预期。
- 配置升为 schema6-maintenance-login-config-v2，本人审批升为 schema6-owner-gates-approved-v2；旧 approvedSddl/approved_sddl 一律拒绝。分别绑定注册输入、继承预期、父SD UTF8摘要、windows-file-oi-v1版本和只读主体明细。
- 注册回执同步升为 schema6-approved-login-registration-v3，准备回执升为 schema6-production-login-prepare-v3，精确绑定两份SDDL摘要、父SD、算法及只读披露。准备的PS与直接Node API、RegisterOnly都核实时父SD，CREATE前与回读后再次核验；任何漂移拒绝。
- CREATE仅提交registrationSddl，原有严格Compare只使用expectedRegisteredSddl；保留owner/group/P位/SID/flags/mask规则、同SID同flags allow合并、CREATE-only/零实例/无Run、现有文件身份/ACL/租约及冻结门槛。

## 最终有效权限

只读主体明细按SID与flags的Ordinal顺序、合并相同主体权限，固定为 `[{sid,flags:16,mask:8位大写hex}]`。其他主体只能拥有 FILE_GENERIC_READ=00120089 的子集；禁止FILE_EXECUTE、写数据/追加/写属性、删除child/对象、WRITE_DAC、WRITE_OWNER、未知权限及MAXIMUM_ALLOWED。显式外主体、保护DACL、漏报/重复/乱序/换mask均拒绝。

独审发现旧候选上限001200A9包含FILE_EXECUTE；任务的执行权限可调用Run/RunEx，故已收紧纯读至00120089，并补GX/FX/0x20/GR|GX拒绝测试。依据：[微软任务安全说明](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)。没有将执行权当“只读”提交用户批准。

公开回执仅披露其他主体数量；实际SID、完整SDDL/XML及父SD只进受保护本机审批目录，不入仓库、CI日志或PR正文。当前本机拟议父继承仅本人/SYSTEM/Administrators，最终是否仍为零个其他只读主体以新候选精确审批工件和进场前父SD重核为准，不能引用旧预览当新审批。

## 合成验证

真实模板AST提取、原设置保持、Windows COM NewTask内存检验3/3通过；没有Register/Run/Delete。纯权限fixture覆盖独立继承、非OI不传播、OI|IO/OI|NP、CO/CG、generic映射、原输入/期望分离、所有外SID非读位、披露完整性、父SD漂移与实际回读增权拒绝。

主窗专项首次12通过/0失败/1未执行，未执行的是需要显式opt-in的本机真实COM注册；不能写成全部执行。跨进程租约真实文件测试通过，worker的受限沙箱SetAccessControl失败已由主窗在合成目录重跑通过。完整本机回归与新增最终断言结果收尾后登记；不触发现役任务。

Hosted Windows原有真实COM夹具维持一次nonce绑定CREATE→readback→delete，禁用/无触发/安全cmd空动作；同时比较独立oracle和生产权限helper，再核实际最终权限。现有MaintenanceOnly自动发现maintenance_*.test.mjs，新增两文件无需放宽CI条件；完整job也纳入。全部检查以新PR精确head为准。

## 新固定候选与审批工件

从本轮已提交源码构建新固定候选，verifyRelease核47项hash/size。与旧1552e251固定包比较，预计只有prepare_login_schema6.ps1变化；逐项实测摘要收尾后登记。维护源码闭包新增task_security_policy.ps1且全量pin，审批仍需新维护闭包hash。

本人最终审阅包必须包含：新candidate source/manifest、完整XML及hash、registration SDDL原文/hash、expected SDDL原文/hash、父SD hash、算法版本、其他只读主体逐项明细（零时明确零）、Unified=true与原XML语义差异、新登录配置hash及现场新WindowId。所有路径只在本机私有包公开给本人。准备审批草稿不能把productionApproved设为true、不能生成尚不存在的freeze/ACL成功回执或未来hash。

先源码审核/CI全绿/新候选与本人精确批准，再按已有范围进入现场。PR16已合并不等于新修订已合并；新PR合并仍须明确授权，固定包源码与最终批准输入必须一一对应。真关机四项Gate仍待执行。
