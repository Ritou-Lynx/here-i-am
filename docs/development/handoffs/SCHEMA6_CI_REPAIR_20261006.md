# PR14 CI 根因修复（2026-10-06）

基线：`0e04e1fb1d9ca0d1a15b457bc79b66f3f8c8243d`；工作分支 `codex/schema6-ci-fix-20261006`。本包只改 CI、合成测试及测试辅助脚本，不改生产 plainPath、链接、ACL、恢复、备份或生命周期检查；未访问真实库、服务、任务或手机。白板冻结总纲已完整读取，产品/共享契约只读。

## 两次 Windows 失败的证据和修复

- GitHub job `112111647626` 和 `112111349877` 都是 96 tests / 7 pass / 89 fail / 0 skip。原日志均显示 key custody 的路径含 `Users/RUNNER~1/AppData/Local/Temp`。release before-hook 与 recovery adapter 在 `package.mjs:39` 报 `input_missing_or_aliased`；backup/restore 分别报 `linked_path_rejected` / `inspection_link_rejected`，正向案例尚未进入被测业务行为。
- 四组夹具直接将 `tmpdir()` 拼入安全输入。新增非库存 test-only `synthetic_paths.mjs`，先 `realpathSync.native` 规范 TEMP，再创建并规范根；所有正向输入从这根派生，清理也比对 canonical parent。生产入口仍直接拒绝短路径、junction、symlink、hardlink，不替生产调用方规范输入。
- release 与 backup wrapper 的固定 Node 输入改为 `COPYFILE_EXCL` 创建独立文件，核验 `nlink=1` 与源字节 SHA256，生产 pinned hash 校验继续运行。工具缓存 Node 是否链接不是原日志已证明的独立根因；此变更消除夹具对工具缓存布局的依赖。
- 两个 job 的七项真实 lifecycle 案例还在 `Protect-NewDirectory` 报 `new_directory_owner_mismatch`。它们的路径已经是 `runneradmin` 长路径，与前述 alias 是不同原因。Hosted runner elevated token 的默认 owner 可为 Administrators，而生产要求当前用户 SID。CI 专用 `run_windows_tests.ps1` 仅调整测试父进程 token 的 default owner 为当前 SID，子进程继承；finally 恢复原 owner。没有更改机器策略、现役配置或生产 ACL 判定。新增 TAP artifact 保留同一次原始执行证据，无重试或忽略失败。

## Flutter 精确失败

job `112111647814` 唯一失败：`compact_card_editor_test.dart` 的“空标题与正文 H1 通过稳定 synthetic 边界无损编辑并重启恢复”，原第394行 `expect(closed, isTrue)`。测试只给真实磁盘 I/O 30×20ms（600ms）后即判失败，UI 虚拟 pump 不能代替磁盘保存完成。

测试改为真实 async zone 中创建的保存/关闭 Completer；保留 Escape 真入口，明确阻塞 save、推进2秒虚拟时间并验证编辑器仍打开，再放行真实 repository save，等待 onClose 事件后关闭/重开真实 SQLite 校验 H1 和空标题。10秒只是失败上限，不通过重试或提高固定睡眠预算隐藏失败。生产编辑器零修改。

## 本机验证

- Node v24.14.1：`node --test tools/i_core/release_schema6/release.test.mjs tools/i_core/release_schema6/backup_bundle.test.mjs tools/i_core/release_schema6/restore_inspection.test.mjs tools/i_core/release_schema6/recovery_adapter.test.mjs`：86/86，0 fail / 0 skip。
- `node --test tools/i_core/release_schema6/synthetic_paths.test.mjs`：3/3，0 skip；实际 NTFS 8.3 名已生成并验证生产拒绝，同时 junction TEMP 与 hardlinked cache 独立 copy 验证通过。
- `flutter pub get --enforce-lockfile` 成功；精确 `flutter test --no-pub test/whiteboard_canvas/compact_card_editor_test.dart --reporter expanded`：5/5。
- `flutter test --no-pub test/whiteboard_canvas --reporter failures-only --file-reporter json:build/ci/flutter-canvas.json`：195/195。
- CI token helper 已在独立 PowerShell 进程编译，并验证 current-user setter / 原 owner 恢复成功；本机 token 原本为用户 owner，Hosted elevated group-owner 分支仍需远端 CI 实证。
- 另以实际8.3 TEMP/TMP启动完整 `release_schema6/*.test.mjs` 和 `lifecycle/*.test.mjs` 回归正在完成，不能提前计为通过；主窗收到后续计数再收口。测试 TAP 保存于工作树忽略目录 `build/ci/schema6-short-temp.tap`。
- 未在本机运行 Linux；远端精确新提交的 Linux 和 Windows CI 仍是最终验证边界。无 Flutter build / 安装 / 真人 Gate。

本包提交使用获准 worker 单次 `SKIP_PROJECT_STATE=1`，finally 恢复；全局 DEVLOG/当前态由主窗集成时更新。不 push。
