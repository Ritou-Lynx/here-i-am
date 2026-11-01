import http.client
import json
import shutil
import sys
import tempfile
import threading
import time
import unittest
import wave
from io import BytesIO
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from linai_tts_server import ConfigError, TtsState, create_server, load_config  # noqa: E402

TOKEN = "t" * 40
SECRET_TEXT = "Secret sentence for the log check."


class FakeEngine:
    gpu_name = "Fake GPU"

    def __init__(self, delay=0.0):
        self.delay = delay
        self.active = 0
        self.max_active = 0
        self.calls = []
        self.lock = threading.Lock()

    def load(self):
        pass

    def synthesize(self, text):
        with self.lock:
            self.active += 1
            self.max_active = max(self.max_active, self.active)
        self.calls.append(text)
        time.sleep(self.delay)
        with self.lock:
            self.active -= 1
        return np.zeros(2400, dtype=np.float32), 24000


class ServerTest(unittest.TestCase):
    def start(self, engine=None, queue_timeout_s=5.0, loaded=True):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        config = {"token": TOKEN, "device": "cuda", "max_chars": 400, "queue_timeout_s": queue_timeout_s,
                  "log_dir": str(Path(self.tmp) / "logs")}
        self.engine = engine or FakeEngine()
        self.state = TtsState(self.engine, config, {"power_throttling_off": True})
        if loaded:
            self.state.load_engine()
        self.server = create_server(self.state, "127.0.0.1", 0)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.port = self.server.server_address[1]

    def request(self, method, path, body=None, token=TOKEN):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        headers = {"Content-Type": "application/json"}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        data = json.dumps(body).encode() if body is not None else None
        conn.request(method, path, body=data, headers=headers)
        resp = conn.getresponse()
        payload = resp.read()
        conn.close()
        return resp, payload

    def log_text(self):
        logs = Path(self.tmp) / "logs"
        return "".join(p.read_text(encoding="utf-8") for p in logs.glob("*.log"))

    def test_health_without_token(self):
        self.start()
        resp, payload = self.request("GET", "/v1/tts/health", token=None)
        self.assertEqual(resp.status, 200)
        body = json.loads(payload)
        self.assertTrue(body["model_loaded"])
        self.assertEqual(body["gpu_name"], "Fake GPU")
        self.assertTrue(body["power_throttling_off"])
        self.assertNotIn(TOKEN, payload.decode())

    def test_missing_and_wrong_token(self):
        self.start()
        for token in [None, "wrong", TOKEN + "x"]:
            resp, payload = self.request("POST", "/v1/tts/speak", {"text": "Hi."}, token=token)
            self.assertEqual(resp.status, 401)
            self.assertNotIn(TOKEN, payload.decode())
        self.assertEqual(self.engine.calls, [])

    def test_speak_returns_wav(self):
        self.start()
        resp, payload = self.request("POST", "/v1/tts/speak", {"text": "Hey [laugh] you.", "request_id": "abc-1"})
        self.assertEqual(resp.status, 200)
        self.assertEqual(resp.getheader("Content-Type"), "audio/wav")
        self.assertEqual(resp.getheader("X-Request-Id"), "abc-1")
        self.assertEqual(resp.getheader("X-Audio-Ms"), "100")
        self.assertGreaterEqual(int(resp.getheader("X-Gen-Ms")), 0)
        with wave.open(BytesIO(payload)) as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()), (1, 2, 24000, 2400))
        self.assertEqual(self.engine.calls, ["Hey [laugh] you."])

    def test_empty_and_too_long(self):
        self.start()
        for text, code in [("  ", "empty_text"), ("a" * 401, "text_too_long"), ("*waves*", "empty_after_cleanup")]:
            resp, payload = self.request("POST", "/v1/tts/speak", {"text": text})
            self.assertEqual(resp.status, 400)
            self.assertEqual(json.loads(payload)["error"], code)

    def test_bad_json(self):
        self.start()
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        conn.request("POST", "/v1/tts/speak", body=b"{not json", headers={"Authorization": f"Bearer {TOKEN}"})
        self.assertEqual(conn.getresponse().status, 400)
        conn.close()

    def test_model_loading_returns_503(self):
        self.start(loaded=False)
        resp, _ = self.request("POST", "/v1/tts/speak", {"text": "Hi."})
        self.assertEqual(resp.status, 503)
        self.assertEqual(resp.getheader("Retry-After"), "5")

    def test_concurrent_requests_are_serialized(self):
        self.start(FakeEngine(delay=0.3))
        results = []
        threads = [threading.Thread(target=lambda: results.append(self.request("POST", "/v1/tts/speak", {"text": "Hi."})[0].status))
                   for _ in range(2)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(results, [200, 200])
        self.assertEqual(self.engine.max_active, 1)

    def test_queue_timeout_returns_503(self):
        self.start(FakeEngine(delay=1.0), queue_timeout_s=0.2)
        first = threading.Thread(target=lambda: self.request("POST", "/v1/tts/speak", {"text": "First."}))
        first.start()
        time.sleep(0.2)
        resp, payload = self.request("POST", "/v1/tts/speak", {"text": "Second."})
        first.join()
        self.assertEqual(resp.status, 503)
        self.assertEqual(resp.getheader("Retry-After"), "2")
        self.assertEqual(json.loads(payload)["error"], "busy")

    def test_logs_have_no_text_or_token(self):
        self.start()
        self.request("POST", "/v1/tts/speak", {"text": SECRET_TEXT})
        self.request("POST", "/v1/tts/speak", {"text": SECRET_TEXT}, token="wrong-token")
        log = self.log_text()
        self.assertIn('"status": 200', log)
        self.assertIn('"status": 401', log)
        self.assertNotIn(SECRET_TEXT, log)
        self.assertNotIn(TOKEN, log)
        self.assertNotIn("wrong-token", log)


class ConfigTest(unittest.TestCase):
    def write(self, data):
        d = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, d, True)
        p = Path(d) / "config.json"
        p.write_text(json.dumps(data), encoding="utf-8")
        return p

    def test_valid(self):
        cfg = load_config(self.write({"token": TOKEN, "reference_wav": "ref.wav"}))
        self.assertEqual((cfg["device"], cfg["max_chars"], cfg["queue_timeout_s"]), ("cuda", 400, 20.0))
        self.assertTrue(cfg["log_dir"].endswith("logs"))

    def test_short_token_rejected(self):
        with self.assertRaises(ConfigError):
            load_config(self.write({"token": "short", "reference_wav": "ref.wav"}))

    def test_missing_reference_rejected(self):
        with self.assertRaises(ConfigError):
            load_config(self.write({"token": TOKEN}))


if __name__ == "__main__":
    unittest.main()
