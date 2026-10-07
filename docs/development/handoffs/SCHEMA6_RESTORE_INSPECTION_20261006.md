# Schema6 加密备份隔离还原与 Core 只读检查

日期：2026-10-06。Worker 基线 `9c6c34d6f7897114d1f65dff0205bbcd895597be`，主窗目标基线 `a3ce4c45f95819de75330d25f12aed3418fc6935`。

## 交付边界

- 增加 AES-256-GCM 外部 SHA 锚定后的两遍验证/提取：首次完整认证成功后才新建受保护目录，二次解密仍独立验证 tag、hash 和每个落盘文件；按 `<role>/<name>` 写入，绝不把 `source_path` 用作输出路径。拒绝已有目录、路径逃逸、Windows 别名、硬链接、符号链接、文件/目录前缀冲突和密文二次变更。
- 新目录留下 `.i-core-inspection.json`，普通 Core 入口发现该 marker 即拒绝 live 启动。还原不会执行备份中的启动器或配置，不写 role、lease、floor，不接管旧库。
- `createICoreServer({ databasePath, mode: 'inspection_read_only' })` 是 Core 明确的检查入口。`DatabaseSync` 使用 `readOnly:true`、URI `mode=ro&immutable=1`、`query_only=ON`；不创建 ICoreStore、迁移、租约、后台任务或邮件 relay。只监听 `127.0.0.1`，只开放 GET `/v1/core/health`，全部正常业务/配对/写路由拒绝 403。
- 还原编排真实启动此 Core listener，验证健康和拒绝路由、比较全部用户表的每行有类型摘要、设备整行摘要、schema/node 摘要，再关库确认文件字节及 identity 未变、没有 WAL/SHM/journal。最后再次认证密文及固定 release，才创建 `.inspection-ready.json`。中途失败仅清理本次创建的精确文件及空目录，不进行递归覆盖/删除。

## 接口与固定包装

`createRuntimeBackup()` 和固定 `Create` 包装的结果增加 `databaseInspection`（不改变原字段）；`databaseInspection.dataSha256` 是还原外部基线。它包含各表行数/摘要、设备计数/摘要及 ID 前缀，不返回正文、token、完整 node/device ID。行摘要保留 blob、bigint、NULL 和重复行，忽略无主键表的物理行顺序。

固定包装支持：

```powershell
& '<candidate>/tools/i_core/release_schema6/backup_bundle_schema6.ps1' `
  -Operation RestoreInspection `
  -ReleaseDirectory '<candidate>' -ManifestSha256 '<release anchor>' `
  -KeyDirectory '<existing CurrentUser DPAPI backup key directory>' `
  -ArtifactPath '<runtime.aes256gcm>' -ArtifactSha256 '<ciphertext anchor>' `
  -OutputDirectory '<new isolated directory>' `
  -ExpectedDatabaseFingerprintSha256 '<Create.databaseInspection.dataSha256>'
```

密钥仍经 CurrentUser DPAPI 和子进程 stdin 内存管道传递，不进入 argv、env、日志或明文文件。`RestoreInspection` 不接受 `CreateKey`，不提供通用生产 restore/overwrite。

新增固定运行库存（由主窗加入 `package.mjs`，此 worker 不提交 foreign package）：

- `tools/i_core/inspection_read_only.mjs`
- `tools/i_core/release_schema6/restore_inspection.mjs`

没有新增第三方依赖；Core 新依赖为静态 import。全部合成测试使用本机 Node v24.14.1。

## 验证与限制

- `node --test tools/i_core/release_schema6/restore_inspection.test.mjs tools/i_core/i_core_server.test.mjs`：31/31，含 schema4 完整备份还原及 schema6 不迁移的真实只读监听、SQL 写拒绝、wrong key、密文/路径/基线/已有输出负例、二次密文变更及最终 release 验证失败。
- `node --test tools/i_core/release_schema6/backup_bundle.test.mjs`：23/23，含实际固定候选打包与 DPAPI Create/Verify/RestoreInspection 往返、环境隔离和重复输出拒绝。
- 沙箱内首次测试因临时目录祖先 realpath 权限失败；经受支持的提升权限工具运行的仍仅是合成夹具与回环 listener，没有读取真实用户库或修改现役服务。
- 这是 inventory_only 的隔离检查还原；不证明生产备份完整性，不恢复 live 权威，未进行真实个人数据演练。实际授权副本演练、固定最终候选、全局状态、PR 和暂停由主窗负责。
- 报告限制为 60 KiB；超限拒绝发布 ready。每行仅保留哈希用于排序，但超大表可能受内存限制；失败不会发布 valid receipt。若外部并发破坏受保护输出，精确清理可能不完整，此时不发布 ready，并保留错误标记供主窗处理。
- 本次只提交拥有文件及本 handoff；foreign `cli.mjs`、`package.mjs`、`lifecycle/`、`recovery_adapter.mjs` 不 stage。集成主窗负责 DEVLOG/I_PROJECT_STATE，worker 单次提交使用已有 `SKIP_PROJECT_STATE=1` 例外并 finally 恢复环境。
