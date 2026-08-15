# Here I am V3 logo assets

这组资产由用户提供的 1254×1254 植物玻璃 `i` 原图拆分而来。六项原始交付共享同一轮廓；彩色前景保留原始植物、露珠和玻璃高光，没有用生成模型重绘。

`source_logo_reference.png` 是保留在项目内的原始设计母图；重新生成时可运行：

```powershell
python scripts/build_hereiam_logo_assets.py assets/branding/hereiam_v3_logo/source_logo_reference.png assets/branding/hereiam_v3_logo
```

## 原 6 项交付

1. `logo_foreground_1024.png` — 1024×1024 RGBA 透明前景；可见符号高 410 px（40.0%），居中且完整位于 Android Adaptive Icon 中央安全区。
2. `logo_background_color.txt` — 纯色背景：`#F8F6F1`。
3. `logo_monochrome_black_1024.png` / `logo_monochrome_black_1024.svg` — 黑色实体符号，透明背景，用于 Android 13 themed icon。
4. `ic_stat_here_i_am.xml` — 24×24 viewport 的 Android 白色通知图标；`notification_png/` 另含 mdpi 24、hdpi 36、xhdpi 48、xxhdpi 72、xxxhdpi 96 五档 PNG。
5. `logo_composite_512.png` — 512×512、`#F8F6F1` 纯色底的完整合成图。
6. `logo_composite_1024.png` — 1024×1024、`#F8F6F1` 纯色底的完整合成图。

## 新增墨绿色合成图

- `logo_composite_ink_green_1024.png` — 1024×1024、`#F8F6F1` 纯色底；`i` 保持与透明前景完全相同的轮廓，内部玻璃、植物和高光全部替换为纯墨绿色 `#485C50`。

## Android 接入映射

- Adaptive foreground：`logo_foreground_1024.png`
- Adaptive background：`#F8F6F1`
- Adaptive monochrome：`logo_monochrome_black_1024.svg`（或同名 PNG）
- Notification small icon：优先使用 `ic_stat_here_i_am.xml`；如必须使用位图，再按密度复制 `notification_png/` 下对应文件。
- Legacy launcher / store：从 `logo_composite_512.png` 或 `logo_composite_1024.png` 缩放。

本目录只提供完成验收的母版和 Android-ready 派生资产，尚未覆盖应用当前正在使用的 launcher / notification 资源。已有的 `simple` 文件是独立实验版本，构建脚本不会覆盖它们。
