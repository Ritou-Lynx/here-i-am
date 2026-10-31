"""Chatterbox-Turbo 分段测速：找出 RTX 5060 Laptop 上比实时慢的原因。

用法（在测速目录的 venv 里）：
    python profile_turbo.py [--ref linai-ref-v5.wav]

只读本机状态、只写当前目录下的 profile.json 和 prof-*.wav，不碰仓库和任何服务。
"""
import argparse
import contextlib
import json
import os
import platform
import subprocess
import sys
import threading
import time

os.environ.setdefault("TQDM_DISABLE", "1")  # 关掉 T3 循环里的进度条，避免控制台输出拖慢

import torch
import torchaudio

SENTENCES = [
    ("short", "Mm, I'm here."),
    ("medium", "Aww... you didn't have to. [chuckle] It's so cute."),
    ("long", "Come here. You did so well today, and I'm really proud of you. Get some rest, okay?"),
]
REPEATS = 2
DEVICE = "cuda" if torch.cuda.is_available() else "cpu"


def sync():
    if DEVICE == "cuda":
        torch.cuda.synchronize()


def sh(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout.strip()
    except Exception as e:  # 只是采集环境信息，失败不影响测速
        return f"error: {e}"


def env_info():
    info = {
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "torch": torch.__version__,
        "cuda_available": torch.cuda.is_available(),
        "gpu": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
        "bf16_supported": torch.cuda.is_available() and torch.cuda.is_bf16_supported(),
        "nvidia_smi": sh(["nvidia-smi", "--query-gpu=driver_version,pstate,power.limit,clocks.max.sm,clocks.max.mem",
                          "--format=csv,noheader"]),
        "gpu_processes": sh(["nvidia-smi", "--query-compute-apps=pid,process_name,used_memory",
                             "--format=csv,noheader"]),
        "gpu_mem_used_total": sh(["nvidia-smi", "--query-gpu=memory.used,memory.total,utilization.gpu",
                                  "--format=csv,noheader"]),
        "cpu": sh(["powershell", "-NoProfile", "-Command",
                    "(Get-CimInstance Win32_Processor | Select-Object -First 1 | ForEach-Object { $_.Name + ' | cores ' + $_.NumberOfCores + ' | threads ' + $_.NumberOfLogicalProcessors + ' | maxMHz ' + $_.MaxClockSpeed })"]),
        "power_scheme": sh(["powercfg", "/getactivescheme"]),
        "on_ac_power": sh(["powershell", "-NoProfile", "-Command",
                           "(Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue).PowerOnline"]),
    }
    try:
        import chatterbox
        info["chatterbox"] = getattr(chatterbox, "__version__", "unknown")
    except Exception:
        pass
    return info


class GpuSampler:
    """生成期间每 200ms 采一次 GPU 利用率、频率、功耗。"""

    def __init__(self):
        self.rows, self.proc, self.thread = [], None, None
        self.cpu_rows, self.cpu_proc, self.cpu_thread = [], None, None

    def __enter__(self):
        try:
            self.proc = subprocess.Popen(
                ["nvidia-smi", "--query-gpu=utilization.gpu,clocks.sm,power.draw,pstate",
                 "--format=csv,noheader,nounits", "-lms", "200"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            self.thread = threading.Thread(target=self._read, daemon=True)
            self.thread.start()
        except Exception:
            self.proc = None
        if os.name == "nt":  # CPU 实际性能百分比（>100 表示睿频），约 1 秒一次
            try:
                # 用 WMI 英文类名（typeperf 计数器名在中文系统上是本地化的）
                loop = ("while($true){$p=Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation "
                        "-Filter \"Name='_Total'\";[Console]::Out.WriteLine(\"x,$($p.PercentProcessorPerformance),"
                        "$($p.PercentProcessorUtility)\");[Console]::Out.Flush();Start-Sleep -Milliseconds 800}")
                self.cpu_proc = subprocess.Popen(["powershell", "-NoProfile", "-Command", loop],
                                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
                self.cpu_thread = threading.Thread(target=self._read_cpu, daemon=True)
                self.cpu_thread.start()
            except Exception:
                self.cpu_proc = None
        return self

    def _read_cpu(self):
        for line in self.cpu_proc.stdout:
            parts = [p.strip().strip('"') for p in line.split(",")]
            if len(parts) == 3:
                try:
                    self.cpu_rows.append((float(parts[1]), float(parts[2])))
                except ValueError:
                    pass

    def _read(self):
        for line in self.proc.stdout:
            parts = [p.strip() for p in line.split(",")]
            if len(parts) == 4:
                self.rows.append(parts)

    def __exit__(self, *exc):
        if self.proc:
            self.proc.terminate()
            self.thread.join(timeout=2)
        if self.cpu_proc:
            self.cpu_proc.terminate()
            self.cpu_thread.join(timeout=2)

    def summary(self):
        def num(i):
            vals = []
            for r in self.rows:
                try:
                    vals.append(float(r[i]))
                except ValueError:
                    pass
            return vals
        util, clk, pwr = num(0), num(1), num(2)
        avg = lambda v: round(sum(v) / len(v), 1) if v else None
        return {"samples": len(self.rows), "util_avg": avg(util), "util_max": max(util) if util else None,
                "sm_clock_avg": avg(clk), "power_avg_w": avg(pwr),
                "pstates": sorted({r[3] for r in self.rows}),
                "cpu_perf_pct_avg": avg([c[0] for c in self.cpu_rows]),
                "cpu_utility_pct_avg": avg([c[1] for c in self.cpu_rows])}


class StageTimer:
    """给 generate() 里的三段（T3 出 token、S3Gen 出波形、水印）计时。"""

    def __init__(self, m):
        self.m, self.t = m, {}
        self.orig = (m.t3.inference_turbo, m.s3gen.inference, m.watermarker.apply_watermark)
        self.t3_dtype = None
        self.skip_watermark = False

        def timed(name, fn):
            def run(*a, **k):
                sync()
                t0 = time.perf_counter()
                with (torch.autocast(DEVICE, dtype=self.t3_dtype) if name == "t3" and self.t3_dtype
                      else contextlib.nullcontext()):
                    out = fn(*a, **k)
                sync()
                self.t[name] = time.perf_counter() - t0
                if name == "t3":
                    self.t["t3_tokens"] = int(out.numel())
                return out
            return run

        m.t3.inference_turbo = timed("t3", self.orig[0])
        m.s3gen.inference = timed("s3gen", self.orig[1])

        def watermark(wav, sample_rate):
            t0 = time.perf_counter()
            out = wav if self.skip_watermark else self.orig[2](wav, sample_rate=sample_rate)
            self.t["watermark"] = time.perf_counter() - t0
            return out
        m.watermarker.apply_watermark = watermark


def boost_process():
    """只对本进程生效：关掉 Windows 后台节能限速（EcoQoS），优先级调到高。进程退出即失效。"""
    if os.name != "nt":
        return "skipped (not windows)"
    import ctypes
    from ctypes import wintypes

    class PowerThrottlingState(ctypes.Structure):
        _fields_ = [("Version", wintypes.ULONG), ("ControlMask", wintypes.ULONG), ("StateMask", wintypes.ULONG)]

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.GetCurrentProcess.restype = wintypes.HANDLE
    h = k32.GetCurrentProcess()
    state = PowerThrottlingState(1, 0x1 | 0x4, 0)  # EXECUTION_SPEED | IGNORE_TIMER_RESOLUTION，StateMask=0 表示不限速
    ok_throttle = k32.SetProcessInformation(h, 4, ctypes.byref(state), ctypes.sizeof(state))  # ProcessPowerThrottling
    ok_prio = k32.SetPriorityClass(h, 0x80)  # HIGH_PRIORITY_CLASS
    return {"power_throttling_off": bool(ok_throttle), "high_priority": bool(ok_prio)}


def run_variant(m, timer, name, ref, t3_dtype=None, skip_watermark=False):
    timer.t3_dtype, timer.skip_watermark = t3_dtype, skip_watermark
    results = []
    for key, text in SENTENCES:
        for rep in range(REPEATS):
            timer.t = {}
            with GpuSampler() as gs:
                sync()
                t0 = time.perf_counter()
                wav = m.generate(text)
                sync()
                total = time.perf_counter() - t0
            audio = wav.shape[-1] / m.sr
            row = {"variant": name, "sentence": key, "rep": rep, "total_s": round(total, 3),
                   "audio_s": round(audio, 3), "rtf": round(total / audio, 2) if audio else None,
                   **{k: (round(v, 3) if isinstance(v, float) else v) for k, v in timer.t.items()},
                   "gpu": gs.summary()}
            if timer.t.get("t3_tokens") and timer.t.get("t3"):
                row["t3_ms_per_token"] = round(timer.t["t3"] * 1000 / timer.t["t3_tokens"], 2)
            row["other_s"] = round(total - sum(timer.t.get(k, 0) for k in ("t3", "s3gen", "watermark")), 3)
            results.append(row)
            print(json.dumps({k: v for k, v in row.items() if k != "gpu"}, ensure_ascii=False), flush=True)
            if rep == 0:
                torchaudio.save(f"prof-{name}-{key}.wav", wav, m.sr)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ref", help="林埃声音参考 wav（>5 秒），不传则用模型默认声音")
    ap.add_argument("--boost", action="store_true", help="本进程关闭后台节能限速并提高优先级")
    ap.add_argument("--only-baseline", action="store_true", help="只跑 baseline 变体")
    args = ap.parse_args()

    report = {"env": env_info()}
    if args.boost:
        report["boost"] = boost_process()
    print(json.dumps(report["env"], ensure_ascii=False, indent=1), flush=True)

    from chatterbox.tts_turbo import ChatterboxTurboTTS
    t0 = time.perf_counter()
    m = ChatterboxTurboTTS.from_pretrained(device=DEVICE)
    report["load_s"] = round(time.perf_counter() - t0, 2)
    report["t3_param_dtype"] = str(next(m.t3.parameters()).dtype)

    if args.ref:
        t0 = time.perf_counter()
        m.prepare_conditionals(args.ref)
        report["prepare_ref_s"] = round(time.perf_counter() - t0, 2)

    timer = StageTimer(m)
    for _ in range(2):  # 预热：CUDA kernel 首次编译不计入
        m.generate("Hey, I'm warming up.")

    rows = run_variant(m, timer, "baseline", args.ref)
    if not args.only_baseline:
        rows += run_variant(m, timer, "no_watermark", args.ref, skip_watermark=True)
    if not args.only_baseline and report["env"]["bf16_supported"] or os.environ.get("PROFILE_FORCE_BF16"):
        try:
            rows += run_variant(m, timer, "t3_bf16", args.ref, t3_dtype=torch.bfloat16, skip_watermark=True)
        except Exception as e:
            report["t3_bf16_error"] = repr(e)
    report["rows"] = rows
    if DEVICE == "cuda":
        report["max_mem_gb"] = round(torch.cuda.max_memory_allocated() / 1024 ** 3, 2)

    with open("profile.json", "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=1)

    print("\n== 汇总（每个变体取各句第 2 次） ==")
    for r in rows:
        if r["rep"] == REPEATS - 1:
            print(f'{r["variant"]:<13}{r["sentence"]:<7} RTF {r["rtf"]:<5} t3 {r.get("t3")}s '
                  f'({r.get("t3_ms_per_token")}ms/tok) s3gen {r.get("s3gen")}s wm {r.get("watermark")}s '
                  f'GPU {r["gpu"]["util_avg"]}% {r["gpu"]["sm_clock_avg"]}MHz {r["gpu"]["power_avg_w"]}W '
                  f'CPU perf {r["gpu"]["cpu_perf_pct_avg"]}%')
    print("已写入 profile.json")


if __name__ == "__main__":
    main()
