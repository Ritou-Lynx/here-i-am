import 'package:flutter/material.dart';

import 'package:memex/ui/core/widgets/character_avatar.dart';

class BreathingCallAvatar extends StatefulWidget {
  const BreathingCallAvatar({
    super.key,
    required this.avatar,
    required this.name,
    required this.breathing,
  });

  final String? avatar;
  final String name;
  final bool breathing;

  @override
  State<BreathingCallAvatar> createState() => _BreathingCallAvatarState();
}

class _BreathingCallAvatarState extends State<BreathingCallAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant BreathingCallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.breathing != widget.breathing) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.breathing) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final glow = 0.12 + (_controller.value * 0.16);
          return Container(
            width: 164,
            height: 164,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD1AD).withValues(alpha: glow),
                  blurRadius: 28 + (_controller.value * 18),
                  spreadRadius: 7 + (_controller.value * 8),
                ),
              ],
            ),
            child: child,
          );
        },
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: CharacterAvatar(
            key: ValueKey(widget.avatar),
            avatar: widget.avatar,
            name: widget.name,
            size: 136,
          ),
        ),
      ),
    );
  }
}
