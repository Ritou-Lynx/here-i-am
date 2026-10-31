"""关闭 Windows 对本进程的后台节能限速（EcoQoS）并提高优先级。

实测（RTX 5060 Laptop）：服务在后台运行时被限速，Turbo 的 T3 每 token 约 70–110 ms、RTF 约 2–3；
关闭后约 12 ms/token、RTF 约 0.35。只影响本进程，进程退出即失效。
"""
import os

_PROCESS_POWER_THROTTLING = 4
_EXECUTION_SPEED = 0x1
_IGNORE_TIMER_RESOLUTION = 0x4
_HIGH_PRIORITY_CLASS = 0x80


def disable_power_throttling():
    """返回 {"power_throttling_off": bool|None, "high_priority": bool|None}；非 Windows 为 None。"""
    if os.name != "nt":
        return {"power_throttling_off": None, "high_priority": None}
    import ctypes
    from ctypes import wintypes

    class PowerThrottlingState(ctypes.Structure):
        _fields_ = [("Version", wintypes.ULONG), ("ControlMask", wintypes.ULONG), ("StateMask", wintypes.ULONG)]

    k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    k32.GetCurrentProcess.restype = wintypes.HANDLE
    k32.SetProcessInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    k32.SetProcessInformation.restype = wintypes.BOOL
    k32.SetPriorityClass.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    k32.SetPriorityClass.restype = wintypes.BOOL

    handle = k32.GetCurrentProcess()
    # ControlMask 里列出的项由我们接管，StateMask=0 表示这些项都不限速
    state = PowerThrottlingState(1, _EXECUTION_SPEED | _IGNORE_TIMER_RESOLUTION, 0)
    throttle_off = bool(k32.SetProcessInformation(handle, _PROCESS_POWER_THROTTLING, ctypes.byref(state), ctypes.sizeof(state)))
    high_priority = bool(k32.SetPriorityClass(handle, _HIGH_PRIORITY_CLASS))
    return {"power_throttling_off": throttle_off, "high_priority": high_priority}
