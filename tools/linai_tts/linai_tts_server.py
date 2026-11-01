"""林埃英文语音服务：只监听本机，把一段英文合成为林埃的声音（Chatterbox-Turbo），返回 WAV。

手机经 `tailscale serve` 访问，另加 Bearer token。只用标准库做 HTTP；推理在 engine.py，
文本整理在 text_prep.py，二者都可替换，测试用假引擎。
"""
import hmac
import json
import os
import sys
import threading
import time
import uuid
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from audio import duration_ms, encode_wav  # noqa: E402
from text_prep import TextError, prepare_text  # noqa: E402

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 47870
MAX_BODY_BYTES = 16 * 1024
MIN_TOKEN_CHARS = 32


class ConfigError(ValueError):
    pass


def default_config_path():
    base = os.environ.get("LOCALAPPDATA") or str(Path.home() / ".local" / "share")
    return Path(base) / "HereIAm" / "linai-tts" / "config.json"


def load_config(path):
    path = Path(path)
    try:
        raw = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        raise ConfigError("config_not_found")
    except json.JSONDecodeError:
        raise ConfigError("config_not_json")
    token = raw.get("token")
    if not isinstance(token, str) or len(token) < MIN_TOKEN_CHARS:
        raise ConfigError("token_too_short")
    reference = raw.get("reference_wav")
    if not isinstance(reference, str) or not reference:
        raise ConfigError("reference_wav_missing")
    return {
        "token": token,
        "reference_wav": reference,
        "device": raw.get("device", "cuda"),
        "max_chars": int(raw.get("max_chars", 400)),
        "queue_timeout_s": float(raw.get("queue_timeout_s", 20)),
        "log_dir": str(path.parent / "logs"),
    }


class RequestLog:
    """每次请求一行 JSON，按天一个文件；不记原文和 token。"""

    def __init__(self, log_dir):
        self.log_dir = Path(log_dir) if log_dir else None
        self.lock = threading.Lock()
        if self.log_dir:
            self.log_dir.mkdir(parents=True, exist_ok=True)

    def write(self, **fields):
        if not self.log_dir:
            return
        now = datetime.now(timezone.utc)
        line = json.dumps({"time": now.isoformat(timespec="milliseconds"), **fields}, ensure_ascii=False)
        with self.lock, open(self.log_dir / f"linai-tts-{now:%Y-%m-%d}.log", "a", encoding="utf-8") as f:
            f.write(line + "\n")


class TtsState:
    def __init__(self, engine, config, power=None):
        self.engine = engine
        self.config = config
        self.power = power or {}
        self.started = time.monotonic()
        self.infer_lock = threading.Lock()
        self.model_loaded = False
        self.requests = 0
        self.last_error = None
        self.counter_lock = threading.Lock()
        self.log = RequestLog(config.get("log_dir"))

    def load_engine(self):
        try:
            self.engine.load()
            self.model_loaded = True
        except Exception as e:  # 留在 health 里给手机端看，服务继续活着
            self.last_error = f"load_failed:{type(e).__name__}"
            self.log.write(event="load_failed", error=type(e).__name__)

    def health(self):
        return {
            "ok": True,
            "model_loaded": self.model_loaded,
            "device": self.config.get("device"),
            "gpu_name": getattr(self.engine, "gpu_name", None),
            "uptime_s": int(time.monotonic() - self.started),
            "requests": self.requests,
            "last_error": self.last_error,
            "power_throttling_off": self.power.get("power_throttling_off"),
        }


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        server_version = "linai-tts/1"
        sys_version = ""

        def log_message(self, *args):  # 默认会把请求行打到 stderr，统一走 RequestLog
            pass

        def _json(self, status, body, headers=None):
            data = json.dumps(body).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            for k, v in (headers or {}).items():
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path != "/v1/tts/health":
                return self._json(404, {"error": "not_found"})
            self._json(200, state.health())

        def do_POST(self):
            if self.path != "/v1/tts/speak":
                return self._json(404, {"error": "not_found"})
            meta = {"request_id": uuid.uuid4().hex[:12], "chars": None, "gen_ms": None, "audio_ms": None}
            try:
                status, error, send = self._speak(meta)
            except Exception as e:
                status, error = 500, f"internal:{type(e).__name__}"
                send = lambda: self._json(500, {"error": "internal"})  # noqa: E731
            with state.counter_lock:
                state.requests += 1
                if error and status >= 500:
                    state.last_error = error
            # 先记日志再回包，客户端收到响应时这一行已经落盘
            state.log.write(event="speak", status=status, error=error, **meta)
            send()

        def _reject(self, status, code, headers=None):
            return status, code, lambda: self._json(status, {"error": code}, headers)

        def _speak(self, meta):
            auth = self.headers.get("Authorization", "")
            given = auth[7:] if auth.startswith("Bearer ") else ""
            if not hmac.compare_digest(given.encode("utf-8"), state.config["token"].encode("utf-8")):
                return self._reject(401, "unauthorized")
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = -1
            if length <= 0 or length > MAX_BODY_BYTES:
                return self._reject(400, "bad_body_length")
            try:
                body = json.loads(self.rfile.read(length).decode("utf-8"))
                if not isinstance(body, dict):
                    raise ValueError
            except (ValueError, UnicodeDecodeError):
                return self._reject(400, "bad_json")
            rid = body.get("request_id")
            if isinstance(rid, str) and 0 < len(rid) <= 64 and rid.replace("-", "").replace("_", "").isalnum():
                meta["request_id"] = rid
            raw = body.get("text")
            meta["chars"] = len(raw) if isinstance(raw, str) else None
            try:
                text = prepare_text(raw, state.config["max_chars"])
            except TextError as e:
                return self._reject(400, e.code)
            if not state.model_loaded:
                return self._reject(503, "model_loading", {"Retry-After": "5"})
            if not state.infer_lock.acquire(timeout=state.config["queue_timeout_s"]):
                return self._reject(503, "busy", {"Retry-After": "2"})
            try:
                t0 = time.perf_counter()
                pcm, sr = state.engine.synthesize(text)
                meta["gen_ms"] = int((time.perf_counter() - t0) * 1000)
            except Exception as e:
                return 500, f"synthesis_failed:{type(e).__name__}", lambda: self._json(500, {"error": "synthesis_failed"})
            finally:
                state.infer_lock.release()
            data = encode_wav(pcm, sr)
            meta["audio_ms"] = duration_ms(pcm, sr)

            def send():
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("X-Gen-Ms", str(meta["gen_ms"]))
                self.send_header("X-Audio-Ms", str(meta["audio_ms"]))
                self.send_header("X-Request-Id", meta["request_id"])
                self.end_headers()
                self.wfile.write(data)
            return 200, None, send

    return Handler


def emit(**fields):
    """控制台一行 JSON；pythonw 下没有 stdout，直接跳过。"""
    if sys.stdout is not None:
        print(json.dumps(fields), flush=True)


def create_server(state, host=DEFAULT_HOST, port=DEFAULT_PORT):
    server = ThreadingHTTPServer((host, port), make_handler(state))
    server.daemon_threads = True
    return server


def main():
    from engine import TurboEngine
    from power import disable_power_throttling

    config_path = os.environ.get("LINAI_TTS_CONFIG") or default_config_path()
    try:
        config = load_config(config_path)
    except ConfigError as e:
        emit(event="config_error", error=str(e))
        RequestLog(Path(config_path).parent / "logs").write(event="config_error", error=str(e))
        return 2
    power = disable_power_throttling()
    state = TtsState(TurboEngine(config["reference_wav"], config["device"]), config, power)
    host = os.environ.get("LINAI_TTS_HOST", DEFAULT_HOST)
    port = int(os.environ.get("LINAI_TTS_PORT", DEFAULT_PORT))
    server = create_server(state, host, port)
    threading.Thread(target=state.load_engine, daemon=True).start()
    emit(event="listening", host=host, port=port, **power)
    state.log.write(event="start", port=port, **power)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
