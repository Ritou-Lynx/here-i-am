# CLI 核对记录

2026-10-24，本机安装包版本 **1.0.98**。只运行了根目录、base、docs、whoami 和下表各命令的 `--help`，以及 CLI 内置的本地说明 `skills read/list`；没有执行 whoami 本体、联网 schema 查询或任何飞书 API。所有目标和返回示例都用占位符。帮助能确认命令与参数；返回字段依据随 CLI 分发的本地说明，真实租户的返回仍须合并后由用户试跑核验。

| 唯一出口的命令 | 固定参数与数据参数 | 读取的返回字段 |
| --- | --- | --- |
| `whoami` | `--as user` | 成功信封 `ok`、`identity` |
| `base +table-get` | `--as user --base-token <BASE> --table-id <TABLE> --format json` | 成功信封，确认指定表可读 |
| `base +field-list` | 同上 | `data.fields[]` 中的 `name/type/multiple/options[].name`；该具体容器需真人 check 核验，未知形状拒绝继续 |
| `base +record-list` | `--as user --base-token <BASE> --table-id <TABLE> --format ndjson --limit 2000 --offset <OFFSET> --output records.ndjson` | 临时 NDJSON 每行 `record_id` 和以字段名为 key 的单元格；同名 `.manifest.json` 的 `records_count/has_more/next_offset/rev/query_context` |
| `base +record-batch-create` | `--as user --base-token <BASE> --table-id <TABLE> --json @payload.json` | `data.record_id_list`；检查 `ignored_fields` |
| `base +record-batch-update` | 同上 | `data.ignored_fields`；成功响应不验证记录存在，因此还会读回核对 |
| `docs +fetch` | `--as user --doc <DOC> --doc-format markdown` | `data.document.document_id/content/reference_map`，原样保留 sidecar |
| `docs +create` | `--as user --doc-format markdown --content @content.md` | `data.document.document_id`、`data.warnings`；正文首行带学习单标题 |
| `docs +update` | `--as user --doc <OWNED_DOC> --doc-format markdown --command append --content @content.md` | 成功信封与 `data.warnings`；DOC 只能来自同步脚本自己的创建登记 |

JSON 成功信封是 `{ "ok": true, "identity": "user", "data": {} }`，不能用旧 OpenAPI 顶层 `code == 0` 判断成功。错误只返回本工具稳定的 snake_case 错误码，不向日志复制 CLI 原始输出。

与合同概括写法的差异 / 需要明确的细节：

- `+table-get` 和 `+field-list` 在这个版本均存在，因此都纳入读白名单；`--table-id` 同时接受 ID 和表名。
- record-list 默认是 NDJSON；选择已文档化的物理结构，并在临时目录读取 manifest，按 next_offset 分页。避免猜测 `--format json` 的 raw matrix 结构。
- 批量新增的 JSON 是 `{"create_records":[{ "<FIELD>": "<VALUE>" }]}`；更新是 `{"update_records":{"<RECORD_ID>":{"<FIELD>":"<VALUE>"}}}`。不是旧接口的 `records/fields` 包装。
- 单选 CellValue 是单元素数组；日期传 `YYYY-MM-DD 00:00`（Base 本地时区），有时间的练习记录传带时区的 RFC3339。来源用带标题的 Markdown 文档链接，字段类型为 `text`。
- `@file` 只能指向子进程 cwd 内的相对文件。同步脚本在 `os.tmpdir()` 中创建独占目录，将其设为 cwd，参数仅含 `@payload.json` / `@content.md`；finally 清理。不会传绝对 `@file`。
- npm 的 Windows `.cmd` 入口不能直接用 `shell:false` 启动；解析到同一包的原生 `bin/lark-cli.exe`，不借助 cmd/PowerShell。测试用 Node 脚本入口。
- 更新文档虽然 CLI 支持很多操作，本工具只生成 append；没有命令或参数透传入口。

本地说明依据：`lark-shared/references/lark-shared-output-contract.md`、`lark-base/SKILL.md`、`lark-base/references/lark-base-record-query-and-analysis-sop.md`、`lark-doc/references/lark-doc-fetch.md`、`lark-doc/references/lark-doc-create.md`。从内置说明只能确认部分返回结构，不把假 CLI 或未联网试跑说成真实飞书验收。
