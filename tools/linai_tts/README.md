# linai_tts：家用林埃英文语音服务

在家里电脑上用 Chatterbox-Turbo（ResembleAI，350M，MIT，仅英文）把一段英文合成为林埃的声音，返回 WAV。只监听 `127.0.0.1`，手机经 `tailscale serve` 的 HTTPS 访问，另加 Bearer token。App 侧接入见 V1b。

## 文件

| 文件 | 作用 |
|---|---|
| `linai_tts_server.py` | 标准库 HTTP 服务、鉴权、串行推理、日志 |
| `text_prep.py` | 只保留 Turbo 认识的副语言标签，删掉 `*动作*`、括号说明 |
| `engine.py` | `TurboEngine`：加载模型、缓存参考音色、预热、合成 |
| `power.py` | 关闭 Windows 对本进程的后台节能限速并提高优先级 |
| `audio.py` | 标准库 `wave` 编码 16 位单声道 WAV |
| `config.example.json` | 配置模板（真实配置不进仓库） |
| `requirements.txt` | chatterbox 以外的依赖（版本与 10-31 测速环境一致） |

## 安装（Windows，RTX 50 系）

```powershell
$dir = "$env:LOCALAPPDATA\HereIAm\linai-tts"
py -3.11 -m venv "$dir\venv"
& "$dir\venv\Scripts\python.exe" -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128
& "$dir\venv\Scripts\python.exe" -m pip install chatterbox-tts==0.1.7 --no-deps
& "$dir\venv\Scripts\python.exe" -m pip install -r tools\linai_tts\requirements.txt
```

- RTX 50 系（sm_120）需要 torch ≥ 2.7 + CUDA 12.8；`chatterbox-tts` 的依赖声明会把 torch 降回 2.6，所以必须 `--no-deps`。
- `setuptools<81`：水印库 perth 还在用 `pkg_resources`。
- 首次启动会从 Hugging Face 下载约 2 GB 权重。

## 配置

复制 `config.example.json` 到 `%LOCALAPPDATA%\HereIAm\linai-tts\config.json`（或用环境变量 `LINAI_TTS_CONFIG` 指定），填：

- `token`：至少 32 个字符的随机串，手机端填同一个。
- `reference_wav`：林埃参考音频，长于 5 秒、干净、有授权（目前用“声音 5”）。
- `device`（默认 `cuda`）、`max_chars`（默认 400）、`queue_timeout_s`（默认 20）。

日志在配置目录的 `logs\`，每次请求一行 JSON，不记原文和 token。

## 运行

```powershell
& "$env:LOCALAPPDATA\HereIAm\linai-tts\venv\Scripts\python.exe" tools\linai_tts\linai_tts_server.py
tailscale serve --https=8445 http://127.0.0.1:47870
```

默认端口 47870，可用 `LINAI_TTS_HOST` / `LINAI_TTS_PORT` 覆盖。加载模型约需半分钟，期间 `speak` 返回 503（`Retry-After: 5`）。

## 接口

- `GET /v1/tts/health`（无需 token）→ `{ok, model_loaded, device, gpu_name, uptime_s, requests, last_error, power_throttling_off}`
- `POST /v1/tts/speak`，`Authorization: Bearer <token>`，body `{"text": "...", "request_id": "可选"}` → `audio/wav`，响应头 `X-Gen-Ms`、`X-Audio-Ms`、`X-Request-Id`。
- 错误：401 token 不对；400 `empty_text` / `text_too_long` / `empty_after_cleanup` / `bad_json`；503 `model_loading` / `busy`（排队超时，`Retry-After: 2`）；500 `synthesis_failed`。

支持的标签：`[laugh] [chuckle] [sigh] [gasp] [cough] [clear throat] [crying] [sniff] [groan] [shush] [whispering] [happy] [angry] [sarcastic] [surprised] [fear] [dramatic]`。

## 性能（10-31 实测，RTX 5060 Laptop + i7-14650HX）

| | T3 每 token | RTF |
|---|---|---|
| 后台进程被 Windows 节能限速 | 70–110 ms | 1.8–3.1 |
| 关闭限速 + 高优先级（服务启动时自动做） | 11–14 ms | 0.31–0.40 |

RTF 0.35 即 1.8 秒的短句约 0.7 秒合成完。显存峰值约 3 GB。bf16 比 fp32 慢，保持 fp32。新版 torchaudio 的读写依赖 torchcodec + FFmpeg DLL，后台环境里会加载失败，所以 WAV 只用标准库写。

## 测试

```
python -m unittest discover -s tools/linai_tts/tests -v
```

用假引擎，不需要显卡和模型。

开机自启、计划任务不在这一版（V1c）。
