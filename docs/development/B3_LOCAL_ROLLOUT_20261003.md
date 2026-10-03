# B3 本机部署结果（2026-10-03）

任务分支 `codex/b3-writeback-local-20261003`，B3 基线 `2d92a8d74828fa2513bf1a7cb5c4ab233e757f3a`。仅记录技术结果，不包含真实内容或凭据。未 push。

## 服务部署

| 项目 | 结果 |
| --- | --- |
| 读取层替换前核验 | 与 c8dd05b0 Git 原字节仅 LF/CRLF 差异，干净 Windows 检出哈希一致；用户接受后部署 |
| 受控运行文件 | memory 读取层及 remote 五份源码已复制并核对；现役核心采用下述固定包 |
| 本机 policy | messages.auto_share_origins 新增 claude_web，其余字段语义不变，openReadModel 成功 |
| i_core | schema 4 固定包仅移植 B3 八个权限补丁；新清单与启动器验证通过，旧固定包保留；用户确认切换并完成一次性配对 |
| 常驻权限 | 配对环境已清除；启动器持续清除 worker/reply 密钥；真实前端 feed 读取 403，worker 请求 401 拒绝 |
| remote MCP | CLI serve 保持既有 public URL，启用写回；停服期间 revoke-all 后重启，旧令牌撤销已加载 |
| OAuth 元数据 | 本机与公网均返回 scopes_supported=[i.read,i.write] |
| 公网边界 | Cloudflare ingress 只指向 47860；指标移至 47864，实际进程/loopback 核对通过；手机通道不经公网 |
| 手机通道 | 经用户现场确认保留 loopback 47862；Tailscale HTTPS :47863 → 47862，仅 tailnet，无新 Funnel，所有既有映射不变；无令牌请求 401 |
| 手机令牌 | 已签发，令牌原文仅本机窗口/内存二维码，未进文件或日志；phone-feed.json 仅哈希且无广泛读取 ACL；本机有效令牌认证探测 200，窗口仅显示一次后已关闭；用户确认保存并实测“已同步，暂无新记录”；首次失败因手机 Tailscale 未运行，连接后通过 |

## Flutter 候选

- 手机与桌面聊天显示 frontend: 来源为“网页端”，使用 created_at_ms 再 server_sequence 排序。
- 外部消息保留在本地聊天库与 Daily Dreaming，导入不创建用户 outbox、模型回复或核心回复请求。
- 设置提供“网页端记录通道”；URL、令牌、游标在安全存储中，应用前台周期同步，后台停止触发。
- upsert 直接调用既有 Organizer 成卡；来源为 claude_web_note/note_id，revision 修订走用户修正路径。删除仅清理该 note 的卡片，重复拉取不会复活旧版本。
- 卡片与 revision 回执同事务；成功后 ACK，ACK 成功后推进持久游标，失败不跳过。
- nullable 排序列由 schema 60→61 迁移；仅源定义变动后运行 build_runner，不手改生成代码。
- 专用安装脚本保留默认分支保护，绑定 codex 候选 HEAD/无未跟踪构建输入/现有 APK SHA256，并在任何手机操作前校验 APK 包名；签名文件留本机并忽略。
- 现有备份恢复流程替换数据库实例后需按页面提示重启 App，记录导入器随重启重新绑定数据库。

## 自动验证

| 范围 | 结果 |
| --- | --- |
| remote MCP / memory / core server Node 专项 | 67 + 35 + 23 = 125 项通过 |
| schema 4 写回固定包 | 25 项接口测试通过，9 组启动器断言通过 |
| Flutter 聊天、既有 persona 与桌面回归 | 22 项通过 |
| 网页记录与既有 Organizer 回归 | 30 项通过 |
| 记录设置 VM/Widget | 10 项通过 |
| schema 61 与既有身份迁移 | 2 项通过 |
| 相关 Dart 分析 | 新增 notes/设置/同步路径无诊断；最终 main/依赖分析零错误，main 25 项既有诊断（exit 2），新增同步块无诊断；聊天页面既有 lint 已区分 |
| 构建前关键修复检查 | 3/3 通过 |
| hereIAmV3 debug 构建 | JNI 独立 staging 修复后成功，package=com.memexlab.hereiam.v3 |
| 手机 HTTPS 拉取预检 | 用户确认“已同步，暂无新记录”；不等于记录成卡与六项真人 Gate |
| 真实手机安装 | 用户授权候选 3069115d 与既定 APK 哈希；专用脚本安装成功并启动，包存在且进程存活；未读取手机内容 |


APK：`build/app/outputs/flutter-apk/app-hereiamv3-debug.apk`，386,782,825 字节；SHA256 `0d34095ccc488d68d7058e2127baf78c40c34bee93b5c832032dc2597702eeee`。JNI CMake 输出已限定在任务构建目录，未修改全局缓存、NDK 或依赖版本。初次构建的共享 staging 写入失败不计通过；修复后构建 exit 0。安装已由专用脚本绑定源码候选 `3069115db605c579fe085ab6267ae68c12d7b46c` 及该产物哈希执行；本次后续提交只更新技术交接，不改变候选源码。

## Lynx 操作与真人验收

手机通道、安装完成后，claude.ai 断开并重新连接 connector，输入本机既有口令；四个工具设置为“始终允许”；Project 指令使用 `tools/i_remote_mcp/CLAUDE_PROJECT_INSTRUCTIONS.md` 的“指令正文”。

| 真人项目 | 结果 |
| --- | --- |
| claude.ai 新对话两三轮，手机顺序显示“网页端”且无重复 | 未执行 |
| 手机一句话后，claude.ai 下一轮接上 | 未执行 |
| 网页显式记录自动成为手机记忆卡，无需确认 | 未执行 |
| 网页删除后手机卡删除/归档，i_remember list 不再存在 | 未执行 |
| 含私密关键词的网页消息在另一对话不可读 | 未执行 |
| i_core 停止期间一轮，恢复后下一轮补交成功 | 未执行 |

真实验收只绑定此次候选提交与产物哈希；测试、构建、安装和六项真人结果分开记录。