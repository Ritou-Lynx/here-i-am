"""Chatterbox-Turbo 推理封装。服务通过依赖注入拿引擎，测试用假引擎，不在这里做 HTTP 或校验。"""
import numpy as np

WARMUP_TEXT = "Hey, I'm here."


class TurboEngine:
    def __init__(self, reference_wav, device="cuda"):
        self.reference_wav = reference_wav
        self.device = device
        self.model = None
        self.sample_rate = None
        self.gpu_name = None

    def load(self):
        """加载模型、缓存参考音色、预热一句。耗时数十秒，调用方在后台线程里调。"""
        import torch
        from chatterbox.tts_turbo import ChatterboxTurboTTS

        self.model = ChatterboxTurboTTS.from_pretrained(device=self.device)
        self.model.prepare_conditionals(self.reference_wav)
        self.sample_rate = self.model.sr
        if self.device == "cuda" and torch.cuda.is_available():
            self.gpu_name = torch.cuda.get_device_name(0)
        self.synthesize(WARMUP_TEXT)

    def synthesize(self, text):
        """英文文本 → (float32 波形, 采样率)。调用方负责串行。"""
        wav = self.model.generate(text)
        pcm = wav.squeeze().detach().cpu().numpy().astype(np.float32)
        return pcm, self.sample_rate
