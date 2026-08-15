# 白板生产字体占位目录（W6 集成基座）

本目录存放白板桌面端生产字体资产。**W6 只占目录与声明约定，实际 TTF/WOFF2
文件由 W2 富文本窗口放入**；pubspec.yaml 中的字体 family 声明已预留（注释态），
W2 放文件后取消注释即可，**不需要再改 pubspec 其他部分**。

## 字体清单与许可证

| 字体 | 用途 | 许可证 | 状态 |
|---|---|---|---|
| 汇文明朝体（Huiwen Mingchao） | 中文正文 / 页面标题 | CC0 1.0（可商用，无需署名） | 待 W2 放入子集化 TTF |
| Cascadia Code | 英文、数字、时间码、代码 | SIL Open Font License 1.1 | 待 W2 放入 TTF |

来源约定：
- 汇文明朝体：官方发布渠道（GitHub `Hanayoki/HuiwenMingchao` 或作者指定发布页），
  以 CC0 许可证文件随包留存。
- Cascadia Code：微软官方 GitHub 发布页（SIL OFL 1.1）。

## 子集化说明（生产资产落地时必须做）

1. **汇文明朝体必须子集化**：全字体库体积大，桌面包不得直接内嵌全量字体。
   推荐 `fonttools`（`pyftsubset`）按「产品用字 + 常用 3500 字 + 白板样例内容」
   生成子集：
   ```bash
   pyftsubset HuiwenMingChao-Regular.ttf \
     --text-file=whitelist.txt \
     --unicodes=U+0000-00FF,U+2000-206F,U+3000-303F,U+4E00-9FFF \
     --output-file=HuiwenMingChao-Subset.ttf \
     --layout-features='*' --flavor=
   ```
   `whitelist.txt` 由产品文案、样例卡片、常用词表导出。
2. **缺字检查**：子集化后必须跑覆盖检查（对全部生产 UI 文案 + 测试 fixture
   文本做字形覆盖扫描），缺字时扩充子集并重出。
3. **Cascadia Code 按需选择 weight**：生产只需 Regular（+ 可选的 Bold），
   不用全套 10 个 weight。
4. 子集化后每个文件 ≤ ~4MB（中文正文子集通常 2–4MB），并记录
   源文件 sha256、子集生成命令与日期到本 README。

## 落盘文件约定（W2 放置）

```
assets/fonts/whiteboard/HuiwenMingChao-Regular.ttf   （子集化后）
assets/fonts/whiteboard/CascadiaCode-Regular.ttf
assets/fonts/whiteboard/whitelist.txt                （子集字表，可追溯）
assets/fonts/whiteboard/README.md                    （更新：sha256 + 命令）
```

pubspec.yaml 预留声明（放文件后取消注释）：

```yaml
  fonts:
    # 白板生产字体（W6 占位声明，文件由 W2 落地后启用）
    # - family: HuiwenMingchao
    #   fonts:
    #     - asset: assets/fonts/whiteboard/HuiwenMingChao-Regular.ttf
    # - family: CascadiaCode
    #   fonts:
    #     - asset: assets/fonts/whiteboard/CascadiaCode-Regular.ttf
```

## 回退链（W2 实现要求）

缺字回退：HuiwenMingchao → LXGW WenKai（既有资产）→ 系统字体；
Cascadia Code → 'monospace' → 系统等宽。中英文混排时按
`docs/design/whiteboard-ui-spine-contract.md` 的字体规则。
