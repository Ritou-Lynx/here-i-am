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
  });

  final String characterId;
  final String callReason;
  final Duration? maxDuration;
  final bool showWhenLocked;

  @override
  State<GptLiveCallScreen> createState() => _GptLiveCallScreenState();
}

class _GptLiveCallScreenState extends State<GptLiveCallScreen> {
  static const _systemActions = MethodChannel(
    'com.memexlab.memex/system_actions',
  );

  late final GptLiveCall _call = GptLiveCall(
    characterId: widget.characterId,
    callReason: widget.callReason,
  );
  Timer? _ticker;
  Timer? _autoExit;
  bool _hangingUp = false;
  bool _didLeave = false;
  bool _replacing = false;
  Duration _endedDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _call.addListener(_onChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _call.phase != GptLiveCallPhase.live) return;
      final max = widget.maxDuration;
      if (max != null && _elapsed >= max) {
        unawaited(_hangUp(reason: 'max_duration'));
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

  void _onChanged() {
    if (!mounted) return;
    if (_call.phase == GptLiveCallPhase.ended && _autoExit == null) {
      _endedDuration = _elapsed;
      _autoExit = Timer(const Duration(seconds: 2), _leaveOnce);
    }
    setState(() {});
  }

  Future<void> _hangUp({String reason = 'user'}) async {
    if (_hangingUp || _call.phase == GptLiveCallPhase.ended) return;
    _hangingUp = true;
    await _call.hangUp(reason: reason);
  }

  void _leaveOnce() {
    if (!mounted || _didLeave) return;
    _didLeave = true;
    _autoExit?.cancel();
    Navigator.of(context).pop();
  }

  void _retry() {
    if (_didLeave) return;
    _didLeave = true;
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
    final ended = phase == GptLiveCallPhase.ended;
    final failed = phase == GptLiveCallPhase.failed;
    final name = _call.characterName ?? '林埃';
    return PopScope(
      canPop: ended || failed || _didLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _didLeave = true;
        } else {
          unawaited(_hangUp());
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
                            unawaited(_hangUp());
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
                        _call.endReason ?? 'unknown',
                      ),
                      onTap: _leaveOnce,
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
                      onBack: _leaveOnce,
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
