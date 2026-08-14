# 白板画布 Lab runner

W1 白板画布与交互的可丢弃验证壳。它通过 path 依赖指向主仓库（`memex`），
只复用 `lib/ui/whiteboard_canvas/` 的画布实现，不引入 MemexRouter 或任何主 App 服务。

## 用途

在真实桌面 / 浏览器窗口中验证画布纵向闭环：

1. 打开一个真实 Board（加载 W0 fixture）
2. 渲染现有 Card 预览
3. 单选 / 框选 / 多选、拖动、缩放、置顶、建组、删除摆放
4. viewport 平移缩放
5. 撤销 / 重做
6. 保存快照并在重启后恢复

## 运行

```powershell
cd desktop\whiteboard_runner

# 桌面（Windows，需要开启系统 Developer Mode 以支持 plugin symlink）
flutter run -d windows

# 浏览器
flutter run -d chrome --web-port 8092
```

顶部工具栏可切换加载 fixture：标准 / 空白板 / 损坏快照 / 失效引用 / 500 卡性能。

## 已知平台限制

- Windows 原生构建要求系统开启 Developer Mode
  （`设置 → 隐私和安全性 → 开发者选项 → 开发人员模式`），
  否则 Flutter 报 `Building with plugins requires symlink support`。
- Web 模式无法读写本机文件，fixture 与持久化退化为内存数据。

## 边界

- 这是可丢弃验证壳，不是生产入口；生产持久化由 W0 集成工作流接入 Drift。
- 画布实现位于 `lib/ui/whiteboard_canvas/`，本目录只承载平台壳与验证入口。
