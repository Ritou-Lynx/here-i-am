\# 开发备忘



\## 启动命令

flutter run -d RFCWC01PBKK --flavor globalDev



\## 路径

\- 项目：D:\\memex

\- Flutter SDK：D:\\flutter

\- Gradle 缓存：D:\\.gradle



\## ⚠️ 版本同步策略（重要，别忘）



我们在官方 Memex 基础上做了改动，需要定期同步官方更新。



\### 分支策略

\- origin/main = Memex 官方

\- 我们的改动全部在独立分支上，不直接改 main



\### 每次官方更新时执行

git fetch origin

git rebase origin/main

\# 有冲突就手动解决，改动集中所以冲突不多



\### 我们改动的文件清单（改一个就更新这里）

\- lib/agent/built\_in\_tools/http\_fetch\_tool.dart（新建）

\- lib/agent/memex\_skill\_host\_agent/memex\_skill\_host\_agent.dart（+2行）

\- lib/agent/pure\_skill\_host\_agent/pure\_skill\_host\_agent.dart（+2行）

\- 后续继续补充...



\### 为什么要这样做

改动量小（\~300行），rebase 通常自动过，偶尔手动解决1-2个冲突。

如果忘了同步、攒太久，冲突会叠加，那才真的麻烦。

