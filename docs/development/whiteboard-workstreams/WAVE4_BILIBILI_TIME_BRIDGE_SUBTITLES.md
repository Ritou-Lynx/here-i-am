# Wave 4 — Bilibili 时间桥与字幕隔离包 handoff

> 分支：`codex/whiteboard-wave4-bilibili-bridge`
> 基线：`427086ae`
> 状态：隔离实现完成，待集成与 Windows 真人验收

## 1. 本轮闭环

1. Windows Bilibili 播放器改为应用内顶层 `bilibili.com/video/<BV>` 页面，
   仅在页面确认为该站视频页时注入窄 HTMLMediaElement bridge。
2. 时间能力不再静态承诺：bridge 必须先成功读取标准 `<video>` 的
   `currentTime / duration`，执行一次当前位置 no-op seek，再次读取并通过
   容差验证，才提升为可读时间、可 seek、可建时间 Anchor；任何握手、读取、
   写入或导航失败都会立即降级为“可播放 · 时间研读受限”。
3. bridge 只监听标准 `play / pause / timeupdate / loadedmetadata / seeking /
   seeked / durationchange` 事件，不读取 Cookie、媒体 URL、Bilibili 私有对象，
   不 fetch、不抽流、不处理 DRM。
4. 新增统一平台字幕 resolver。YouTube 继续使用既有公开网页轨道路径；
   Bilibili 仅预留公开 / 同源、短生命期文本返回接口，并支持 SRT / VTT 解析。
   默认未启用未经证明的私有字幕接口，也不持久化签名 URL 或 Cookie。
5. Bilibili 字幕失败细分为来源无效、无轨、地区 / 权限、网络、解析器失效、
   不支持；UI 始终保留 SRT / VTT 导入，不把未验证的线上轨道冒充完成。
6. 保留现有字幕 / 视频笔记双 Tab、点与区间 Annotation、无框连续编辑面。

## 2. 登录状态安全边界

- 本轮**没有**配置应用专用固定 WebView2 `userDataPath`，也没有新增清除
  Cookie / cache / 站点数据动作；这两项需要用户明确授权后另行实现。
- 登录入口只打开 Bilibili 官方登录页，沿用插件当前默认 WebView 会话。
  首次进入前明确提示：平台 WebView 可能保留登录状态，应用不读取或记录密码、
  Cookie；固定 profile 和清除站点数据尚未授权。
- 因为默认 WebView 会话的持久化行为由插件 / WebView2 决定，本轮不承诺
  “永不重登”，也不把测试开关作为隐藏的持久化默认值。

## 3. 共享契约与数据语义

- 未修改数据库 schema、依赖、`*.g.dart`、Card / Source / Anchor 数据语义。
- 未修改共享 `PlayerAdapter` 接口；Bilibili adapter 只在运行时返回经过读写
  验证的现有 `PlayerCapability` 集合。
- 时间 Anchor 仍由真实播放器当前位置产生，与字幕是否存在无关。动态能力提升
  后 ViewModel 会收到时间事件并立即开放建点 / 区间入口；降级后立即关闭。
- `BilibiliSameOriginSubtitleProbe` 的契约只返回短生命期字幕文本和失败分类，
  不允许 Cookie 或签名 URL 离开 WebView，也没有实现 `/x/player/wbi/v2`。
- 审计了 `codex/whiteboard-wave3-final-video@753f1f75+9eb87e7a`，未 cherry-pick。
  其中固定 unsupported UI 与当前 ContextDock 双 Tab 冲突，持久化草稿也越出
  本包边界；本轮只吸收了可独立证明的事务 / 失败分类测试思想。

## 4. 自动化证据

- bridge 领域测试覆盖：未验证降级、完整读写握手提升、失败回落、事件过滤、
  注入脚本边界。
- adapter 测试固定顶层 Bilibili URL；resolver 测试覆盖 SRT、VTT、无轨、
  地区 / 权限、网络、解析器失效、默认 unsupported 及 YouTube 分类映射。
- Widget 测试覆盖受限态、登录安全提示、没有清除动作、Bilibili 字幕失败与
  SRT / VTT 后路，以及运行时能力提升后无字幕时间 Anchor 入口出现。
- 定向回归：`87 / 87` 通过（bridge / resolver / adapter / video domain /
  video study widget / source study screen）。
- 定向 analyze：`No issues found!`。
- `git diff --check`：提交前通过。

## 5. Windows 真人验收清单

1. 打开真实 Bilibili 视频，确认顶层页面在 App 内播放；没有完成握手前只能显示
   “可播放 · 时间研读受限”。
2. 在可访问标准 `<video>` 的页面验证 current / duration / seek 往返；只有
   no-op seek 校验成功后才出现建点 / 区间入口，点击 Annotation 可回跳。
3. 导航离开视频页、刷新、登录或让 JS 执行失败，确认能力立即撤销而非沿用旧值。
4. 登录入口确认只进入官方页；实测默认 WebView 会话是否在重启后保留登录，
   但结果只记录为平台现状，不等同于产品保证。
5. Bilibili 自动字幕真实平台路径仍未闭环；确认默认诚实降级并可导入 SRT / VTT。

### 交叉审计返修补充

- URL 导航现同时核对 host、`/video/` 路径与原始 BV；同 BV 的 `?p=` 可继续，
  不同 BV、离页或加载错误会立即撤销时间能力、显示来源失效原因并清除未提交的
  区间选择 / Annotation 草稿，避免把另一视频时间挂到原 Source。
- 注入脚本持续用 `MutationObserver` 窄观察标准 `<video>`；清晰度或 SPA 替换
  元素时先解绑旧监听，再以 generation 宣告新 candidate。Dart 侧串行验证并保留
  飞行中 candidate，过期读写结果不能提升能力，成功 / 失败都会通知 UI。
- 每次顶层 URL 导航（包括同 BV 刷新）都会先撤销时间能力并重置页面 generation；
  消息携带仅存于当前文档的 token，新 candidate 完成读写握手前拒绝 time 事件。
- resolver、初始化后恢复均有 dispose / source epoch 守卫；同一 adapter 被新 Source
  复用时旧 ViewModel 只退订而不误销毁播放器。`play()` 现在等待真实 Promise，
  拒绝播放不会再被当作成功。
- 增量定向回归覆盖 URL 换 BV、元素替换、验证排队 / 失败通知、动态降级清草稿、
  resolver dispose 与 Source 切换迟到结果；本轮组合 `47 / 47` 通过，analyze clean。

## 6. 未完事项

- 固定应用 profile 与清除 Bilibili 站点数据：等待用户明确授权，当前未实现。
- 真实 Bilibili 页面能否暴露标准顶层 HTMLMediaElement、登录后页面是否仍满足
  bridge 边界，需要 Windows 联网真人验收；自动化只证明协商逻辑，不证明平台现状。
- Bilibili 没有已验证的公开 / 同源字幕 transport，因此默认 resolver 返回明确
  unsupported；后续若找到合规路径，必须继续遵守 Cookie 不出 WebView、签名 URL
  不持久化、可关闭和精细失败分类。
- 现有 transport 无响应体时，HTTP 403 等仍可能归为 network；地区 / 权限分类
  依赖可读取限制页，这是诚实边界。

## 7. 待集成提交

- 实现提交：本提交（完整 hash 由隔离窗口交接时回传）
