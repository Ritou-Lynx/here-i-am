# A2-R1 `47adfbf6` W0 独立审计

日期：2026-09-13
结论：**独立复跑通过，语义审计拒绝选择性集成。**

## 固定对象与范围

- 候选：`47adfbf69baecea40e60bbeb8c8659ed4af32b1b`
- 父项：被拒首版 `7d0494436d55578d6388b12e69080a7741e4dc9d`
- 总基线：`b55386cfc896c98376a071009f349dcbc88dc84b`
- R1 仅修改 5 个 A2 文件；相对总基线仍仅新增 12 个允许路径。
- 工作树干净，`git diff --check` 通过；共享 Core、Android/Manifest、根依赖、DI/UI 和全局状态文件未改。
- 首版 CRLF 工作区 SHA 与 Git LF blob SHA 已在 manifest 中分栏，实体复核一致。

## W0 独立复跑

W0 从 Git 提交对象导出干净副本。首次离线依赖解析生成有效 `package_config.json` 后，因本机 Pub `active_roots` 路径故障退出；复用该离线映射执行候选提供的 `-NoResolve` 路径，得到：

- A1：`56/56`
- A2：`28/28`
- source analyze：无问题
- test analyze：无问题
- 导出副本内拥有 Dart 文件测试前后字节一致
- 现有 validator：`20/20`
- 全内存 `ActivityControlPlane`：`20/20 accepted`
- 诊断 unknown：6 项；隐私负例：7 项；duplicate/TTL：通过

这些结果只证明本地合成候选；没有设备、Android 进程、网络、真实 Core、真实数据库、APK、部署或真人 Gate。

## 新阻断项

`_removeOwnLock` 在持有 `owner.gate` 时删除 `owner.json`，之后才释放 gate。若删除因文件系统错误、共享冲突或权限问题抛出，释放步骤不会执行。`close()` 已经把实例设为 closed，进程仍存活时却会继续占有 gate；后续持精确恢复权威的新实例只能得到 `owner_still_active`。create/open 的异常清理也共用该路径。

该缺陷为 P1。修订必须确保无论 owner 解码或删除是否成功，都在 `finally` 中释放 gate；保留的 owner 证据仍要求后续精确 authority。还需用确定性故障注入证明删除失败不会遗留活锁，旧实例也不能继续写入。
