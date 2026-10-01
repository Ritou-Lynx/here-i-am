# 多设备源码协作

本项目使用一个 GitHub 仓库：<https://github.com/Ritou-Lynx/here-i-am>。默认集成分支为 `v3-lab`，独立工作使用 `codex/<任务名>` 分支。README 与作品演示材料随同一仓库维护。

## 新设备接入

在设备自己的开发磁盘中创建新目录。下面的命令适用于全新目录，不要在保留旧私人历史的目录中执行。

```powershell
git clone --branch v3-lab --single-branch https://github.com/Ritou-Lynx/here-i-am.git here-i-am
cd here-i-am
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/install_git_hooks.ps1
git status --short --branch
```

使用完整 clone，不加 `--filter=blob:none` 或浅克隆选项。每台设备使用自己的目录；文档中的旧本机路径只是历史验收来源。Windows 开发目录应放在 NTFS 磁盘；T7 归档继续保留。非 Windows 环境需要可运行现有提交检查的 PowerShell。

首次构建需要在设备上配置 Flutter/Dart、对应平台工具链并解析项目依赖。每次 Flutter build 前运行 `scripts/verify_critical_fixes.ps1`；Android 只构建 `hereIAmV3`。构建、设备安装与真人验收分别确认。

## 每次开始工作

先查看当前分支和改动。工作区干净时更新集成分支，再创建任务分支：

```powershell
git status --short --branch
git switch v3-lab
git fetch origin
git merge --ff-only origin/v3-lab
git switch -c codex/任务名
```

若已有改动，先按本任务范围提交和保存；不要为了同步执行 reset、清空目录或覆盖文件。`--ff-only` 失败表示有分歧，应比较双方改动，不能强推。

## 换设备与合入

在离开当前设备前，提交当前任务的源码及必要交接，并把任务分支推到原仓库：

```powershell
git add <本任务文件>
git commit -m "说明本次改动"
git push -u origin HEAD
```

另一台设备先检查工作区，然后 fetch 并继续同一个远端任务分支。首次接入该分支时使用 `git switch --track origin/codex/任务名`。同一任务分支避免两台设备同时写入；确需并行时分别创建任务分支，通过 Pull Request 合入 `v3-lab`。

提交遵守本 clone 的状态检查：实质成果更新 `DEVLOG.md` 与 `docs/development/I_PROJECT_STATE.md`。合入前复核差异和相应测试；换设备后重新更新本地 `v3-lab`。

## 旧版本与私人数据

旧私人谱系的工作目录、工作电脑归档和 T7 恢复点继续保留。旧目录不能直接 pull、强推或把 `.git` 复制到新 clone；需要的遗漏源码按文件比较后选择性迁入。其他历史远端分支保留，日常集成统一走 `v3-lab`。

GitHub 同步源码、必要项目文档和已审查的演示材料。真实聊天、数据库、账户密钥、签名资料、原始设备回执和本机迁移审计另行保全，不进入源码提交。项目目录中的数据库、运行状态和验证输出使用忽略规则；不要用 `git add -f` 绕过这些边界。

生产长任务仍关闭，活动诊断默认关闭；源码同步不改变这些执行边界。真实账户迁移、生产准备和新设备真人验收另行开展。
