# “幸福”表情异常图片调查（2026-09-13）

## 结论

确认两项问题：`zhedog/幸福` 指向了一张汽车短视频截图；普通聊天的贴纸工具即时写入消息，而文字在整个回合完成后才写入，未落实提示词要求的先文字后贴纸。

初次调查只读取证。随后按用户要求，已删除 `zhedog/幸福` 清单条目和对应的 `zhedog_46.jpg` 素材，并于 2026-09-13 17:59:58 重新打包、覆盖安装手机；未修改提示词或发送流程。

## 打包与安装结果

- 在刚才已安装的隔离 check-in 修复候选上仅加入素材删除：基线 `1b6a2961ec9e9705273b8dbed3dd5a9ec5c121f5`，原 7 项修复输入哈希仍一致；未混入主目录其他进行中的代码修改。
- 构建前 critical fixes 3/3；`hereIAmV3` Debug 构建成功，临时 JNI 构建目录配置已恢复，依赖文件无变更。
- 新包 `com.memexlab.hereiam.v3` / `1.0.30 (113)`，SHA-256 `E1B39E9B14A8407BE54E9D0E26FBD99AF8F1B52CEC423041D0E93AE570F8EB37`，407429274 字节。
- 直接检查 APK：错误图片不存在，表情清单与删除后的源码一致，剩余 46 项素材全部存在。
- 安装至 SM-S9110 返回 Success；手机 base.apk 完整哈希与新包一致。覆盖安装保留数据，未使用降级参数，firstInstallTime 保持不变。
- 冷启动 Status ok / COLD / 2194 ms，进程持续存活且本次进程 crash buffer 为空；随后显示处于休眠状态，主 Activity 暂停，未把此时状态记为前台 resumed 或真人功能验收。
- 本机构建与安装收据：`.worktrees/checkin-off-fix/build/sticker-removal-build-20260913.json`、`.worktrees/checkin-off-fix/build/sticker-removal-install-20260913.json`。原 161B63AE 开头的 check-in 安装包收据为先前候选历史，新包已取代手机上的该版本。

## 设备消息证据

只读证据确认：用户文字之后，贴纸附件先写入，角色文字随后写入。消息标识和原始时刻仅保留本机。

附件指向 `stickerId: zhedog/幸福`、`assetPath: assets/stickers/zhedog/zhedog_46.jpg`，走预置贴纸路径。公开文档仅保留素材定位、发送顺序和相对延迟。

同时段后台 check-in 日志记录为 `silent` 后完成，没有贴纸或生图调用；不把同时发生的后台检查当作本次图片来源。

## 素材内容与来源

- 调查时的[素材清单](../../assets/stickers/manifest.json) 将 `zhedog/幸福` 的描述设为“幸福”，文件指向 `zhedog/zhedog_46.jpg`；该条目现已删除。
- 原素材 `assets/stickers/zhedog/zhedog_46.jpg` 是黑色奥迪 SUV、机械车库和人物的短视频截图，右侧带视频互动界面，与这狗包及“幸福”标签不符；原文件现已删除，可由下述 Git 历史核查。
- 当前手机安装包提取的对应素材与仓库文件 SHA-256 一致：`C87252584065BF6298D2A8DC3F8E743BCDDC21FAC47BAF8076F5F24691C18899`。
- 首次加入为 `455eaca28c6e6c368b2c0c47ce13fdce045a6d5d`（2026-08-17，表情库扩充）；该文件的初始与当前 Git blob 都是 `0d443bd838fe75459ebeab76df60fee657226840`。错误素材从导入时就存在。
- 当日 DEVLOG 记载批量素材来自 iili.io；仓库未留下该文件的确切来源 URL 或下载响应，不能进一步判断是源链接、下载响应还是导入选择出了错。

## 触发与发送顺序

1. [StickerLibrary](../../lib/data/services/sticker_library.dart) 读取内置 manifest，给模型提供 ID 和文字描述；此流程没有核验图像语义。
2. [聊天提示词](../../lib/agent/skills/companion_agent/companion_agent_skill.dart) 允许日常聊天使用贴纸表达情绪，并要求先文字后贴纸。本次落库记录选中了“幸福”；没有保留可证明更具体模型动机的证据。
3. [send_sticker](../../lib/agent/built_in_tools/send_sticker_tool.dart) 根据 ID 找到素材，立即调用 `addCharacterMessage`，正文为空、附加 sticker。它不下载新图、不读取相册、不调用生图工具。
4. [CompanionAgent.chat](../../lib/agent/companion_agent/companion_agent.dart) 等待 `agent.run` 完成后才产出最终文字；[聊天界面](../../lib/ui/character/widgets/persona_chat_screen.dart) 再保存文字消息。因此工具执行中的贴纸先入库，文字晚约 5 秒出现，与设备记录相符。

## 修复落点与验证边界

- 已按用户要求从源码表情库下架“幸福”条目并删除错误图片。其余素材尚未完成全库视觉审查。
- 删除后清单可解析，剩余 46 项文件全部存在且 ID 无重复；源码、测试和素材目录无旧 ID/文件引用，diff 检查通过。历史角色消息仍保留原附件路径；已有 `StickerAddendumWidget.errorBuilder` 会显示图片不可用占位，不会替换成其他贴纸。
- 将普通回合的贴纸暂存，在文字成功保存后按序发送；失败、取消和重复调用的行为也需要明确验证，不能仅依靠提示词保证顺序。
- 设备数据库只读查询，未修改消息或设置；临时设备查询程序已移除。最小原始证据保留在忽略的本地 build 目录，未复制整个数据库。
- 当前结论来自实际消息记录、素材哈希/视觉核验、Git 历史和源码调用链；未把静态诊断当作修复后的真人验收。
