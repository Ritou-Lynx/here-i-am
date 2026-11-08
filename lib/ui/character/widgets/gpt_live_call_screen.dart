import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/data/services/gpt_live/gpt_live_call.dart';

/// GPT-Live 备选通话页：进页面就拨，挂断或返回就收尾（写回转写）再退出。
class GptLiveCallScreen extends StatefulWidget {
  const GptLiveCallScreen({
    super.key,
    required this.characterId,
    this.callReason = '',
    this.maxDuration,
    this.showWhenLocked = false,
    this.call,
  });

  final String characterId;

  /// 催睡来电的起因；非空时她会先开口。
  final String callReason;

  /// 通话满这么久自动挂断（催睡来电防止聊太久）；null 不限。
  final Duration? maxDuration;

  /// 锁屏接听时让通话页直接显示在锁屏上方（只在这一页期间开启）。
  final bool showWhenLocked;

  /// 通话页拥有此实例的生命周期；测试可替换外部通话连接。
  @visibleForTesting
  final GptLiveCall? call;

  @override
  State<GptLiveCallScreen> createState() => _GptLiveCallScreenState();
}

class _GptLiveCallScreenState extends State<GptLiveCallScreen> {
  static const _systemActions =
      MethodChannel('com.memexlab.memex/system_actions');

  late final GptLiveCall _call = widget.call ??
      GptLiveCall(
        characterId: widget.characterId,
        callReason: widget.callReason,
      );
  Timer? _ticker;
  bool _hangupInProgress = false;
  bool _exitScheduled = false;

  @override
  void initState() {
    super.initState();
    _call.addListener(_onChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _call.phase != GptLiveCallPhase.live) return;
      final max = widget.maxDuration;
      final start = _call.startedAt;
      if (max != null &&
          start != null &&
          DateTime.now().difference(start) >= max) {
        unawaited(_hangUpAndLeave(reason: 'max_duration'));
        return;
      }
      setState(() {});
    });
    if (widget.showWhenLocked) unawaited(_setShowWhenLocked(true));
    unawaited(_call.start());
  }

  static Future<void> _setShowWhenLocked(bool enabled) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _systemActions
          .invokeMethod('setShowWhenLocked', {'enabled': enabled});
    } catch (_) {}
  }

  void _onChanged() {
    if (!mounted) return;
    final ended = _call.phase == GptLiveCallPhase.ended;
    final disconnected =
        _call.phase == GptLiveCallPhase.failed && _call.startedAt != null;
    if ((ended || disconnected) && !_hangupInProgress) {
      _leave();
      return;
    }
    setState(() {});
  }

  void _leave() {
    if (!mounted || _exitScheduled) return;
    final route = ModalRoute.of(context);
    setState(() => _exitScheduled = true);
    // 等 PopScope 放行后再退出，避免被上一帧的 canPop=false 拦住。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || route == null || !route.isActive) return;
      final navigator = route.navigator;
      if (route.isCurrent) {
        navigator?.pop();
      } else {
        // 结束时若有其他页面盖在上方，只移除本通话页。
        navigator?.removeRoute(route);
      }
    });
  }

  Future<void> _hangUpAndLeave({String reason = 'user'}) async {
    if (_hangupInProgress || _exitScheduled) return;
    _hangupInProgress = true;
    await _call.hangUp(reason: reason);
    _leave();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (widget.showWhenLocked) unawaited(_setShowWhenLocked(false));
    _call.removeListener(_onChanged);
    // 兜底：页面被直接移除时也挂断并写回
    if (_call.phase == GptLiveCallPhase.ended ||
        _call.phase == GptLiveCallPhase.failed) {
      _call.dispose();
    } else {
      unawaited(
          _call.hangUp(reason: 'screen_closed').whenComplete(_call.dispose));
    }
    super.dispose();
  }

  String get _status {
    switch (_call.phase) {
      case GptLiveCallPhase.idle:
      case GptLiveCallPhase.connecting:
        return '正在接通…';
      case GptLiveCallPhase.live:
        final start = _call.startedAt;
        if (start == null) return '通话中';
        final d = DateTime.now().difference(start);
        final m = d.inMinutes.toString().padLeft(2, '0');
        final s = (d.inSeconds % 60).toString().padLeft(2, '0');
        return '$m:$s';
      case GptLiveCallPhase.ending:
        return '正在挂断…';
      case GptLiveCallPhase.ended:
        return '已挂断';
      case GptLiveCallPhase.failed:
        return '没接通：${_call.error ?? '未知错误'}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _call.phase == GptLiveCallPhase.failed;
    return PopScope(
      canPop: _exitScheduled || (failed && !_hangupInProgress),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_hangUpAndLeave());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1B1D1A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                const SizedBox(height: 40),
                Text(
                  _call.characterName ?? '林埃',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'GPT-Live 备选通话',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: failed ? const Color(0xFFE8A0A0) : Colors.white70,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                Text(
                  _call.subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, height: 1.5),
                ),
                const Spacer(),
                if (failed)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _RoundButton(
                        icon: _call.muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_none_rounded,
                        label: _call.muted ? '已静音' : '静音',
                        active: _call.muted,
                        onTap: () => _call.setMuted(!_call.muted),
                      ),
                      _RoundButton(
                        icon: Icons.call_end_rounded,
                        label: '挂断',
                        color: const Color(0xFFD9534F),
                        onTap: _hangUpAndLeave,
                      ),
                      _RoundButton(
                        icon: _call.speakerOn
                            ? Icons.volume_up_rounded
                            : Icons.hearing_rounded,
                        label: _call.speakerOn ? '扬声器' : '听筒',
                        active: _call.speakerOn,
                        onTap: () => _call.setSpeaker(!_call.speakerOn),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color ??
        (active ? Colors.white.withValues(alpha: 0.85) : Colors.white12);
    final fg = color != null
        ? Colors.white
        : (active ? const Color(0xFF1B1D1A) : Colors.white);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: bg,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 68,
              child: Icon(icon, color: fg, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ],
    );
  }
}
