import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/data/services/gpt_live/gpt_live_call.dart';
import 'package:memex/data/services/gpt_live/gpt_live_settings.dart';
import 'package:memex/ui/character/widgets/gpt_live_call/breathing_avatar.dart';
import 'package:memex/ui/character/widgets/gpt_live_call/call_background.dart';
import 'package:memex/ui/character/widgets/gpt_live_call/call_overlays.dart';
import 'package:memex/ui/character/widgets/gpt_live_call/transcript_panel.dart';

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
  static const _systemActions = MethodChannel(
    'com.memexlab.memex/system_actions',
  );

  late final GptLiveCall _call = widget.call ??
      GptLiveCall(
        characterId: widget.characterId,
        callReason: widget.callReason,
      );
  Timer? _ticker;
  Timer? _autoExit;
  bool _hangupInProgress = false;
  bool _exitScheduled = false;
  bool _replacing = false;

  /// 通话已结束（含接通后断线），正在显示结束卡片。
  bool _showEndCard = false;
  Duration _endedDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _call.addListener(_onChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _call.phase != GptLiveCallPhase.live) return;
      final max = widget.maxDuration;
      if (max != null && _elapsed >= max) {
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
      await _systemActions.invokeMethod('setShowWhenLocked', {
        'enabled': enabled,
      });
    } catch (_) {}
  }

  Duration get _elapsed {
    final start = _call.startedAt;
    if (start == null) return Duration.zero;
    final elapsed = DateTime.now().difference(start);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  Duration? get _remaining {
    final max = widget.maxDuration;
    if (max == null) return null;
    final remaining = max - _elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get _disconnected =>
      _call.phase == GptLiveCallPhase.failed && _call.startedAt != null;

  void _onChanged() {
    if (!mounted) return;
    if (_call.phase == GptLiveCallPhase.ended || _disconnected) {
      _beginEndCard();
      return;
    }
    setState(() {});
  }

  /// 显示结束卡片，2 秒后退出；重复调用只生效一次。
  void _beginEndCard() {
    if (!mounted || _showEndCard || _exitScheduled) return;
    setState(() {
      _showEndCard = true;
      _endedDuration = _elapsed;
    });
    _autoExit = Timer(const Duration(seconds: 2), _leave);
  }

  void _leave() {
    if (!mounted || _exitScheduled) return;
    _autoExit?.cancel();
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
    if (_hangupInProgress || _exitScheduled || _showEndCard) return;
    _hangupInProgress = true;
    await _call.hangUp(reason: reason);
    _beginEndCard();
  }

  void _retry() {
    if (_exitScheduled) return;
    _exitScheduled = true;
    _autoExit?.cancel();
    _replacing = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GptLiveCallScreen(
          characterId: widget.characterId,
          callReason: widget.callReason,
          maxDuration: widget.maxDuration,
          showWhenLocked: widget.showWhenLocked,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _autoExit?.cancel();
    if (widget.showWhenLocked && !_replacing) {
      unawaited(_setShowWhenLocked(false));
    }
    _call.removeListener(_onChanged);
    // 兜底：页面被直接移除时也挂断并写回
    if (_call.phase == GptLiveCallPhase.ended ||
        _call.phase == GptLiveCallPhase.failed) {
      _call.dispose();
    } else {
      unawaited(
        _call.hangUp(reason: 'screen_closed').whenComplete(_call.dispose),
      );
    }
    super.dispose();
  }

  String get _status {
    switch (_call.phase) {
      case GptLiveCallPhase.idle:
      case GptLiveCallPhase.connecting:
        return '正在接通…';
      case GptLiveCallPhase.live:
        return '${formatCallClock(_elapsed)}${_call.muted ? ' · 已静音' : ''}';
      case GptLiveCallPhase.ending:
        return '正在挂断…';
      case GptLiveCallPhase.ended:
        return '';
      case GptLiveCallPhase.failed:
        return '没接通';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _call.phase;
    // 接通后断线按“结束”处理（显示结束卡片后退出）；接通前失败才显示重拨。
    final ended =
        _showEndCard || phase == GptLiveCallPhase.ended || _disconnected;
    final failed = phase == GptLiveCallPhase.failed && !ended;
    final name = _call.characterName ?? '林埃';
    return PopScope(
      canPop: _exitScheduled || ended || (failed && !_hangupInProgress),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _exitScheduled = true;
          _autoExit?.cancel();
        } else {
          unawaited(_hangUpAndLeave());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121110),
        body: GptLiveCallBackground(
          avatar: _call.characterAvatar,
          name: name,
          child: SafeArea(
            child: Stack(
              children: [
                const Positioned(right: 18, top: 14, child: _SourceBadge()),
                if (!ended && !failed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(
                      children: [
                        if (widget.callReason.trim().isNotEmpty)
                          CallNudgeBanner(name: name, remaining: _remaining)
                        else
                          const SizedBox(height: 34),
                        const Spacer(flex: 2),
                        BreathingCallAvatar(
                          avatar: _call.characterAvatar,
                          name: name,
                          breathing: phase == GptLiveCallPhase.live,
                        ),
                        const SizedBox(height: 22),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 29,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _status,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 138,
                          child: GptLiveTranscriptPanel(
                            turns: _call.transcript.visibleTurns,
                          ),
                        ),
                        const Spacer(),
                        _CallControls(
                          muted: _call.muted,
                          speakerOn: _call.speakerOn,
                          onMute: () {
                            HapticFeedback.lightImpact();
                            unawaited(_call.setMuted(!_call.muted));
                          },
                          onHangUp: () {
                            HapticFeedback.mediumImpact();
                            unawaited(_hangUpAndLeave());
                          },
                          onSpeaker: () {
                            HapticFeedback.lightImpact();
                            unawaited(_call.setSpeaker(!_call.speakerOn));
                          },
                        ),
                      ],
                    ),
                  ),
                if (ended)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: CallEndCard(
                      duration: _endedDuration,
                      reason: GptLiveCallRecord.reasonTextFor(
                        _call.endReason ??
                            (_disconnected
                                ? 'failed:${_call.error ?? '未知错误'}'
                                : 'unknown'),
                      ),
                      onTap: _leave,
                    ),
                  ),
                if (failed)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: CallFailureCard(
                      reason: GptLiveCallRecord.reasonTextFor(
                        _call.endReason ?? 'failed:${_call.error ?? '未知错误'}',
                      ),
                      onRetry: _retry,
                      onBack: _leave,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          'GPT-Live',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ),
    );
  }
}

class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.muted,
    required this.speakerOn,
    required this.onMute,
    required this.onHangUp,
    required this.onSpeaker,
  });

  final bool muted;
  final bool speakerOn;
  final VoidCallback onMute;
  final VoidCallback onHangUp;
  final VoidCallback onSpeaker;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RoundButton(
          icon: muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
          label: muted ? '已静音' : '静音',
          active: muted,
          onTap: onMute,
        ),
        _RoundButton(
          icon: Icons.call_end_rounded,
          label: '挂断',
          color: const Color(0xFFD9534F),
          size: 76,
          iconSize: 34,
          onTap: onHangUp,
        ),
        _RoundButton(
          icon: speakerOn ? Icons.volume_up_rounded : Icons.hearing_rounded,
          label: speakerOn ? '扬声器' : '听筒',
          active: speakerOn,
          onTap: onSpeaker,
        ),
      ],
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
    this.size = 64,
    this.iconSize = 28,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final Color? color;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final background = color ??
        (active ? Colors.white.withValues(alpha: 0.86) : Colors.white12);
    final foreground = color != null
        ? Colors.white
        : (active ? const Color(0xFF1B1D1A) : Colors.white);
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: background,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(icon, color: foreground, size: iconSize),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
