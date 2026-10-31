<!-- relay:contract v1 -->
# V1a 合同：家用林埃英文语音服务（Chatterbox-Turbo）

> 2026-10-31 用户同意；按用户要求由 Claude 直接实现（不派 Codex），本机验收走脚本轮 `tools/relay_scripts/linai_tts/accept-v1a.ps1`。方案见项目线程“林埃英文声音 V1”：第一阶段通话全英文；声音 5 作为固定参考音色；运行在用户电脑（RTX 5060 Laptop 8GB）上，手机经 Tailscale HTTPS 访问（与 comic_server 相同的信任模型），另加 Bearer token。

## 背景
- App 的所有语音出口都走 `TtsService`（`lib/data/services/tts_service.dart`），按 `tts_provider` 在 ElevenLabs / MiniMax 间分流；`StreamingTtsSession` 按句切分、≥8 字成批请求、逐段播放。V1b 会在 App 侧新增第三个 provider，调用本服务。
- Chatterbox-Turbo（ResembleAI，350M，MIT）只支持英文，支持的副语言标签：`[laugh] [chuckle] [sigh] [gasp] [cough] [clear throat] [crying] [sniff] [groan] [shush] [whispering] [happy] [angry] [sarcastic] [surprised] [fear] [dramatic]`。克隆参考音频必须长于 5 秒。
- RTX 50 系需要 torch ≥ 2.7（CUDA 12.8）；`chatterbox-tts` 的 pip 依赖会要求 torch 2.6，必须用 `--no-deps` 安装并逐个补依赖。
- 10-31 本机实测（RTX 5060 Laptop + i7-14650HX，声音 5 参考）：后台进程默认被 Windows 节能限速（EcoQoS），T3 每 token 约 70–110 ms、RTF 1.8–3.1；进程启动时关闭限速并调高优先级后，T3 约 11–14 ms/token、RTF 0.31–0.40（1.8 秒短句约 0.7 秒生成完），显存峰值约 3 GB。水印约 0.1 秒、S3Gen 约 0.2 秒；bf16 反而更慢，保持 fp32。
- 新版 torchaudio 的 `save/load` 依赖 torchcodec + FFmpeg DLL，后台环境里加载失败；WAV 编码用标准库 `wave`。

## 目标
新建 `tools/linai_tts/`：一个只监听 127.0.0.1 的 Python HTTP 服务，启动时把 Turbo 加载到显卡，按请求把一段英文文本合成为林埃的声音并返回 WAV；附带安装与运行说明。模型推理相关代码与 HTTP、鉴权、校验、标签过滤分开，后者全部可在无显卡、无模型的环境里单测。

## 完成标准

**服务 `tools/linai_tts/linai_tts_server.py`**
- [ ] 只用 Python 标准库实现 HTTP（`http.server` + `ThreadingHTTPServer`），不引入 Web 框架。默认 `127.0.0.1:47870`，可用环境变量 `LINAI_TTS_HOST` / `LINAI_TTS_PORT` 覆盖。
- [ ] 配置从 `LINAI_TTS_CONFIG` 指向的 JSON 读取（默认 `%LOCALAPPDATA%\HereIAm\linai-tts\config.json`），字段：`token`（必填，≥32 字符）、`reference_wav`（必填，参考音频路径）、`device`（默认 `cuda`）、`max_chars`（默认 400）。配置文件、参考音频、日志都不进仓库；仓库只放 `config.example.json`（占位值）。
- [ ] `GET /v1/tts/health`：不需要 token；返回 `{ok, model_loaded, device, gpu_name, uptime_s, requests, last_error}`，不含任何路径和 token。
- [ ] `POST /v1/tts/speak`：需要 `Authorization: Bearer <token>`（常量时间比较），错误返回 401 且不回显 token。请求体 JSON `{text, request_id?}`；返回 `audio/wav`（16-bit PCM，模型原生采样率），响应头带 `X-Gen-Ms`（生成耗时）、`X-Audio-Ms`（音频时长）、`X-Request-Id`。
- [ ] 文本处理（纯函数 `prepare_text`，单独模块 `text_prep.py`）：去掉首尾空白；空文本 400；超过 `max_chars` 400；方括号标签只保留上面的白名单（大小写不敏感，统一成小写输出），其他方括号内容整体删除；`*动作*`、圆括号里的舞台说明删除；连续空白压成一个；处理后为空则 400。
- [ ] 推理串行：全局锁保证同一时间只跑一个生成；排队超过 `queue_timeout_s`（默认 20 秒）返回 503，`Retry-After: 2`。
- [ ] 引擎接口 `engine.py`：`class TurboEngine` 封装 `ChatterboxTurboTTS.from_pretrained(device)`、启动时 `prepare_conditionals(reference_wav)` 一次并缓存、`synthesize(text) -> (pcm: numpy.ndarray, sample_rate: int)`；预热一句再标记 `model_loaded=True`。服务通过依赖注入拿引擎，测试用假引擎。
- [ ] 性能：Windows 上服务启动时对本进程调用 `SetProcessInformation(ProcessPowerThrottling)` 关闭执行速度限速并设为高优先级（ctypes 必须声明 argtypes），结果写进 health 的 `power_throttling_off` 字段；非 Windows 跳过。
- [ ] WAV 编码只用标准库 `wave`（16 位单声道），不调用 torchaudio 的读写函数。
- [ ] 日志：每次请求一行 JSON（时间、request_id、字符数、gen_ms、audio_ms、状态码、错误类型），写到配置目录下的 `logs/`，按天一个文件，先写日志再回包；不记录请求原文和 token。

**说明文档 `tools/linai_tts/README.md`**
- [ ] 安装：在 `%LOCALAPPDATA%\HereIAm\linai-tts\venv` 用 Python 3.11 建 venv；`pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128`；`pip install chatterbox-tts==0.1.7 --no-deps` 后 `pip install -r tools/linai_tts/requirements.txt`（版本与 10-31 测速环境一致，含 `setuptools<81`）。
- [ ] 运行：`python tools/linai_tts/linai_tts_server.py`；暴露：`tailscale serve --https=8445 http://127.0.0.1:47870`。
- [ ] 手机端填写项：Tailscale 地址、token；说明参考音频要求（>5 秒、干净、有授权）。
- [ ] 开机自启、计划任务不在本合同内（V1c 再做）。

**测试 `tools/linai_tts/tests/`（`python -m unittest`，不需要显卡和模型）**
- [ ] `test_text_prep.py`：白名单标签保留并小写化、非白名单标签删除、动作与括号说明删除、超长与空文本报错、中英混合原样保留英文部分。
- [ ] `test_server.py`：用假引擎起服务（随机端口），覆盖 health、缺 token 401、错 token 401、合法请求返回合法 WAV 头与 `X-Gen-Ms`、空文本 400、超长 400、并发两请求被串行、排队超时 503；断言日志与响应里不出现 token 和请求原文。

## 允许修改的路径
- `tools/linai_tts/**`（新建）
- `tools/relay_scripts/linai_tts/**`（本机验收脚本）
- `docs/development/handoffs/RELAY_20261031_v1a-linai-tts-server.md`（只由 Claude 改）

## 不做 / 边界
- 不改 App（V1b）、不改 i_core / comic_server / 计划任务，不安装任何东西到本机，不下载模型，不连外网（测试全用假引擎）。
- 仓库里不出现 token、本机路径、Tailscale 域名、参考音频。
- 止损：同一测试名或同一错误在连续两个提交上失败即判 blocked；最多 3 轮。

## 验证命令
- `python -m unittest discover -s tools/linai_tts/tests -v`
- `python -m py_compile tools/linai_tts/*.py`
