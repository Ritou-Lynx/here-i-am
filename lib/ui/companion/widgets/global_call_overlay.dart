import 'dart:async';

import 'package:flutter/material.dart';

import 'package:memex/data/services/call_voice_router.dart';
import 'package:memex/ui/core/widgets/local_image.dart';
import 'package:memex/utils/logger.dart';

/// Global in-call overlay shown while a companion call is active.
///
/// A real system-level call page is provided by CallKit (incoming ring +
/// ongoing notification); this overlay is the in-app mirror: avatar, name,
/// status, live transcript, call duration and a hang-up button. It lives in
/// the root navigator overlay so it sits above every screen, and it is driven
/// entirely by [CallVoiceRouter] state (the audio runs in the foreground-task
/// isolate, so this UI can even be re-shown after the engine comes back).
class GlobalCallOverlay {
  GlobalCallOverlay._();

  static final GlobalCallOverlay instance = GlobalCallOverlay._();

  static final _log = getLogger('GlobalCallOverlay');

  /// Provided by the app shell (main.dart) so this overlay can reach the root
  /// navigator without a circular import.
  NavigatorState? Function()? navigatorProvider;

  OverlayEntry? _entry;

  bool get isShowing => _entry != null;

  /// Show the overlay for the current active call (see [CallVoiceRouter]).
  void show() {
    if (_entry != null) return;
    final router = CallVoiceRouter.instance;
    if (!router.isActive()) {
      _log.warning('show ignored: no active call');
      return;
    }
    final overlay = _rootOverlay();
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (_) => _CallOverlayContent(router: router),
    );
    overlay.insert(_entry!);
    _log.info('overlay shown');
  }

  /// Hide the overlay (call ended or app navigated away).
  void hide() {
    _entry?.remove();
    _entry = null;
    _log.info('overlay hidden');
  }

  /// Re-show the overlay when the app returns to the foreground if a call is
  /// still active (the engine was suspended while backgrounded).
  void resumeCheck() {
    if (_entry != null) return;
    if (CallVoiceRouter.instance.isActive()) {
      show();
    }
  }

  OverlayState? _rootOverlay() {
    final navigator = navigatorProvider?.call();
    return navigator?.overlay;
  }
}

class _CallOverlayContent extends StatefulWidget {
  const _CallOverlayContent({required this.router});

  final CallVoiceRouter router;

  @override
  State<_CallOverlayContent> createState() => _CallOverlayContentState();
}

class _CallOverlayContentState extends State<_CallOverlayContent> {
  String _status = 'starting';
  String _transcript = '';
  bool _isReply = false;
  bool _muted = false;
  bool _speakerOn = true;
  DateTime _lastToggleAt = DateTime.fromMillisecondsSinceEpoch(0);
  late DateTime _startedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _muted = widget.router.micMuted;
    _speakerOn = widget.router.speakerOn;
    widget.router.onStatusChanged = _onStatus;
    widget.router.onCallEnded = (_) {
      if (mounted) GlobalCallOverlay.instance.hide();
    };
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _onStatus(CallVoiceStatus status) {
    if (!mounted) return;
    // Only setState on an actual change — otherwise every isolate status
    // echo re-renders the buttons and they appear to flash / double-tap.
    // NOTE: muted/speaker are NOT taken from isolate echoes: the isolate may
    // report a stale value (its status pushes race our optimistic flip),
    // which would bounce the button state back and forth. The local button
    // state (updated in _toggleMute/_toggleSpeaker) is the source of truth.
    final transcriptChanged = status.transcript.isNotEmpty &&
        status.transcript != _transcript;
    if (status.status == _status && !transcriptChanged) {
      return;
    }
    setState(() {
      _status = status.status;
      if (transcriptChanged) {
        _transcript = status.transcript;
        _isReply = status.isReply;
      }
    });
  }

  void _toggleMute() {
    // Debounce: repeated taps in quick succession would toggle many times
    // and fight the isolate's in-flight echo. 500ms window.
    final now = DateTime.now();
    if (now.difference(_lastToggleAt) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastToggleAt = now;
    final muted = !_muted;
    setState(() => _muted = muted);
    unawaited(widget.router.setMuted(muted));
  }

  void _toggleSpeaker() {
    final now = DateTime.now();
    if (now.difference(_lastToggleAt) < const Duration(milliseconds: 500)) {
      return;
    }
    _lastToggleAt = now;
    final speakerOn = !_speakerOn;
    setState(() => _speakerOn = speakerOn);
    unawaited(widget.router.setSpeakerphone(speakerOn));
  }

  String get _statusLabel {
    switch (_status) {
      case 'speaking':
        return '正在说话…';
      case 'listening':
        return '聆听中…';
      default:
        return '通话中…';
    }
  }

  String get _elapsed {
    final d = DateTime.now().difference(_startedAt);
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final router = widget.router;
    final name = router.activeCharacterName ?? '林埃';
    final avatar = router.activeCharacterAvatar;

    return Positioned.fill(
      child: Material(
        color: const Color(0xE60A0C10),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              _Avatar(avatar: avatar, name: name),
              const SizedBox(height: 20),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusLabel,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                _elapsed,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 20),
              if (_transcript.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    _transcript,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isReply ? Colors.white70 : Colors.white,
                      fontSize: 14,
                      fontStyle: _isReply ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              const Spacer(flex: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RoundButton(
                    icon: _muted ? Icons.mic_off : Icons.mic,
                    color: _muted ? const Color(0xFFE53935) : Colors.white24,
                    label: _muted ? '取消静音' : '静音',
                    onPressed: _toggleMute,
                  ),
                  const SizedBox(width: 56),
                  _HangUpButton(
                    onPressed: () {
                      router.hangUp();
                    },
                  ),
                  const SizedBox(width: 56),
                  _RoundButton(
                    icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                    color: _speakerOn ? const Color(0xFF4CAF50) : Colors.white24,
                    label: _speakerOn ? '外放' : '听筒',
                    onPressed: _toggleSpeaker,
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.avatar, required this.name});

  final String? avatar;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 44,
      backgroundColor: Colors.white12,
      child: Text(
        name.isEmpty ? 'i' : name.substring(0, 1),
        style: const TextStyle(color: Colors.white, fontSize: 32),
      ),
    );
    if (avatar == null || avatar!.isEmpty) return fallback;
    return ClipOval(
      child: SizedBox(
        width: 88,
        height: 88,
        child: LocalImage(
          url: avatar!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

class _HangUpButton extends StatelessWidget {
  const _HangUpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(36),
      child: Ink(
        width: 72,
        height: 72,
        decoration: const BoxDecoration(
          color: Color(0xFFE53935),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x66E53935),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.call_end, color: Colors.white, size: 32),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}
