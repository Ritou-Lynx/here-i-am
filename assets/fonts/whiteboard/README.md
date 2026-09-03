# 白板生产字体资产

本目录保存 Whiteboard Desktop 随应用分发的生产字体。Flutter 注册族名必须与
`lib/ui/whiteboard/fonts.dart` 完全一致，业务页面只使用集中式字体 token。

## 当前资产

| 字体 | 用途 | 许可证 | 当前状态 |
|---|---|---|---|
| 霞鹜文楷（LXGW WenKai） | 中文正文 / 页面标题 | SIL Open Font License 1.1 | 复用 `assets/fonts/LXGWWenKai-Regular.ttf`；许可副本位于上级目录 |
| Cascadia Code 2407.24 Regular | 英文、数字、时间码、代码 | SIL Open Font License 1.1 | 已接入并由 Flutter / Windows 产物验证 |

### Cascadia Code 可追溯信息

- 官方项目：`https://github.com/microsoft/cascadia-code`
- 官方发行：`v2407.24`，下载包 `CascadiaCode-2407.24.zip`
- ZIP SHA-256：`E67A68EE3386DB63F48B9054BD196EA752BC6A4EBB4DF35ADCE6733DA50C8474`
- 提取路径：`ttf/static/CascadiaCode-Regular.ttf`
- TTF SHA-256：`C33EF522CDFEFF99907FB54F3E97152BB18BFB9B56EC2FEF4D4CEEC51C8974A4`
- TTF 长度：`598060` bytes
- 字体内部 family：`Cascadia Code`
- 许可副本：`CascadiaCode-OFL.txt`，来自同一官方 tag 的 `LICENSE`

只打包静态 Regular，不引入其余字重、Italic、Powerline、Nerd Font、OTF、
WOFF2 或可变字体。当前文件是 Microsoft 原始发行文件，未修改、未子集化，
因此可以保留 Reserved Font Name `Cascadia Code`。

## Flutter 注册

```yaml
  fonts:
    - family: LXGW WenKai
      fonts:
        - asset: assets/fonts/LXGWWenKai-Regular.ttf
    - family: Cascadia Code
      fonts:
        - asset: assets/fonts/whiteboard/CascadiaCode-Regular.ttf
```

`Cascadia Code` 中的空格不能删除；它必须与字体内部 family 以及
`richTextCodeFamily` 一致。缺字回退顺序继续由 `fonts.dart` 控制。

## 中文字体边界

白板复用应用已注册的霞鹜文楷原始文件。若未来对子集或字形做修改，必须重新
核对 SIL OFL、Reserved Font Name、内部 family、生成命令、文件哈希与桌面端
标点 / 缺字表现。
