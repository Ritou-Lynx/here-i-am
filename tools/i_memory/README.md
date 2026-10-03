# i_memory：记忆快照 + 出站策略 + 只读接口

B1.2 / B1.3 的实现，规格见 [B1/B2 接口约定](../../docs/development/CONTINUITY_B1_B2_CONTRACT.md)。只用 Node 22 内置模块，不依赖 npm，不修改 `tools/i_core/`。

| 文件 | 作用 |
|---|---|
| `import_v3_memory.mjs` | 把手机 V3 库的 `memory_cards`（含来源时间与结构化字段）单向快照导入 `i-memory.sqlite` |
| `i_memory_read.mjs` | `openReadModel(...)`：按出站策略过滤后的只读接口，供 `tools/i_remote_mcp/` 使用 |
| `policy.example.json` | 出站策略模板；真实配置放 `.state/policy.json`（已 gitignore） |

运行时文件都放在 `tools/i_memory/.state/`，不进仓库。

## 1. 导出手机 V3 库（Codex 在本机执行）

与 [i_continuity_gateway](../i_continuity_gateway/README.md) 的 ADB 读取方式相同：只支持 debug 包 `com.memexlab.hereiam.v3`，**先在手机上关闭 Here I am V3**，保证 SQLite 与 WAL 一致。`<user>` 是 App 内的用户目录名（与 Gateway 的 `I_VOICE_ANDROID_USER` 相同）。

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$pkg = 'com.memexlab.hereiam.v3'
$db  = 'app_flutter/memex_local_<user>.sqlite'
$out = 'tools/i_memory/.state/v3-export'
New-Item -ItemType Directory -Force $out | Out-Null
& $adb shell pidof $pkg   # 无输出才继续
cmd /c "`"$adb`" exec-out run-as $pkg cat $db > $out\v3.sqlite"
cmd /c "`"$adb`" exec-out run-as $pkg cat $db-wal > $out\v3.sqlite-wal"   # 不存在可忽略
cmd /c "`"$adb`" exec-out run-as $pkg cat $db-shm > $out\v3.sqlite-shm"   # 不存在可忽略
```

用 `cmd /c ... >` 是为了按二进制原样落盘（PowerShell 5 的 `>` 会转码）。多台设备时在 `$adb` 后加 `-s <serial>`。导出的副本是真实数据，只留在 `.state/`，用完可删除。

## 2. 导入记忆快照

```powershell
node tools/i_memory/import_v3_memory.mjs --source tools/i_memory/.state/v3-export/v3.sqlite --out tools/i_memory/.state/i-memory.sqlite          # dry-run
node tools/i_memory/import_v3_memory.mjs --source tools/i_memory/.state/v3-export/v3.sqlite --out tools/i_memory/.state/i-memory.sqlite --apply
```

- dry-run 输出卡片数、带结构化字段数、`would_add` / `would_remove`，不写文件。
- `--apply` 在一个事务里清空后整体写入：手机上删除的卡下次导入就会消失；重复导入结果相同。
- 源库只读打开；`integrity_check` 失败、缺表或缺列时报错退出（退出码 1）。
- 生成 FTS5 `trigram` 索引（`title`、`droplet_label`、`retrieval_text`），并在 `memory_metadata` 记录 `snapshot_at_ms`、`source_sha256`（主库文件）、`card_count`。
- 卡片的 `memory_scope` 原样保存但不过滤；桌面白板身份等 `type = note` 的卡如不想出站，请在策略里加入 `private_types`。

## 3. 配置出站策略

```powershell
Copy-Item tools/i_memory/policy.example.json tools/i_memory/.state/policy.json
```

填入林埃的 `character_id`。规则：

- 消息：只有 `shareable_character_ids` 中的角色可能出站；`private_message_types` 中的类型一律不出站。可选的 `messages.private_keywords`（不区分大小写）命中的消息也一律不出站——如果私密聊天和日常聊天是同一个角色，靠它屏蔽；它只能挡住含关键词的句子，挡不住整段语境，所以真正需要隔离的内容最好放在单独的角色或会话里。
- 记忆卡：`memory.default = "private"` 时全部不出站；否则命中 `private_types`、`private_structured_types`、`private_card_ids`，或 `private_keywords`（不区分大小写，检查 `title`、`retrieval_text`，并额外保守检查 `droplet_label` 与结构化字段 JSON）任一项即不出站。
- 可选的 `messages.private_message_ids` 按 `sync_id` 排除整条消息，省略等同于 `[]`。本机审核私密段落时，可把双方上下文的消息 ID 一并列入，避免只屏蔽关键词句子。
- 可选的 `messages.shareable_message_ids` 和 `memory.shareable_card_ids` 是审核放行清单。字段省略时保留旧行为；显式 `[]` 时对应类别全部不出站；非空时仅清单中的 ID 可能出站，且角色、类型、关键词、私密 ID 和 `memory.default` 等原有限制仍生效，私密排除优先。
- 可选的 `messages.shareable_message_hashes` / `memory.shareable_card_hashes` 将 ID 映射到已审核内容的 SHA-256（64 位十六进制）。省略时保留旧行为，显式 `{}` 时全部不放行；设置后 ID 和内容哈希都必须匹配，且仍须通过 ID 清单和所有私密规则。消息哈希为 UTF-8 `String(content)` 的 SHA-256；卡片哈希为 `JSON.stringify([type, title, droplet_label, retrieval_text, status ?? null, structured_type ?? null, fields_json ?? ''])` 的 SHA-256。导出的纯函数 `hashMessageContent(content)` / `hashMemoryCard(row)` 可供本机审核程序复用。
- 启用 ID 清单后新增 ID 默认不出站；再启用哈希映射，同 ID 内容修订也会拒绝出站。审核刷新时先停服务，更新快照和审核清单、验证后再重启（或重新打开 `ReadModel`）；策略不会热加载。关键词仍只是逐条子串匹配，不能视作色情语义或整段语境识别。
- 除上述可选字段及 `messages.private_keywords` 外，所有字段都必须存在且类型正确；各 ID 清单出现时必须是非空字符串组成的数组（允许空数组）；哈希映射出现时必须是对象（允许空对象），键为非空 ID，值为 64 位十六进制字符串。文件缺失或非法时 `openReadModel` 直接抛错（fail closed）。

## 4. 只读接口

```js
import { openReadModel } from './tools/i_memory/i_memory_read.mjs';
const model = openReadModel({
  coreDbPath: 'tools/i_core/.state/i-core.sqlite',
  memoryDbPath: 'tools/i_memory/.state/i-memory.sqlite',
  policyPath: 'tools/i_memory/.state/policy.json',
});
model.searchMemory({ query: '咖啡' });
model.close();
```

方法与返回结构见接口约定。补充说明：

- i_core 库与记忆库都以只读方式打开；记忆库不存在时记忆方法返回空数组，导入后无需重启即可读到（惰性打开）。
- `searchMemory`：每个检索词都 ≥3 个字符时走 FTS5 trigram（bm25 排序，多词为 OR）；有更短的词时退回 `LIKE`。
- `searchMessages`：i_core 只读且没有全文索引，按词子串匹配（命中词数、次数，再按时间新旧排序），附带约 80 字的 `snippet`。
- 上限：`recentMessages` 100 条，搜索 50 条，`getMemoryCards` 一次 100 个 id。

## 测试

```bash
node --test tools/i_memory/*.test.mjs
```

测试全部使用 `node:sqlite` 现场构造的合成 V3 库和 i_core 库，不读取真实数据。
