# RELAY 2026-11-02：装 GPT-Live 备选通话版本到手机试用

在 #84（GPT-Live 备选通话）的代码上构建 Here I Am V3 debug APK，覆盖安装到手机。脚本与 #82 第 4 轮相同。

- 第 1 轮（write，需用户 👍）：`tools/relay_scripts/app/build-install-v3b.ps1`。
  - 把工作树源码镜像到本机固定构建目录，做增量构建，限时 16 分钟。没编完就报 `build_incomplete`，再跑一轮会接着编。
  - 从本机主仓库复制 debug 签名钥匙，保证签名一致。
  - 用 `adb install -r -d -t` 覆盖安装后启动 App。签名不一致就停下，绝不卸载。
- 输出不含路径、设备序列号、账号。

装好后：设置 → 语音播放 → 填 OpenAI API Key → 保存；聊天页右上角菜单 → 「GPT-Live 通话（备选）」。

本 PR 只用于装机试用，不合并；#84 实测通过后单独合并。
