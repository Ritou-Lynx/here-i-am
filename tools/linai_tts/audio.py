"""WAV 编码只用标准库：新版 torchaudio 的读写依赖 torchcodec + FFmpeg DLL，后台环境里常加载失败。"""
import io
import wave

import numpy as np


def encode_wav(pcm, sample_rate):
    """float 波形（-1..1）→ 16 位单声道 WAV 字节。"""
    samples = np.asarray(pcm, dtype=np.float32).reshape(-1)
    pcm16 = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(sample_rate))
        w.writeframes(pcm16.tobytes())
    return buf.getvalue()


def duration_ms(pcm, sample_rate):
    return int(round(np.asarray(pcm).size * 1000 / int(sample_rate)))
