import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/ui/core/widgets/local_image.dart';

class GptLiveCallBackground extends StatelessWidget {
  const GptLiveCallBackground({
    super.key,
    required this.avatar,
    required this.name,
    required this.child,
  });

  final String? avatar;
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final value = avatar?.trim();
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: value != null && isImageAvatar(value)
              ? RepaintBoundary(
                  key: ValueKey(value),
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
                    child: Transform.scale(
                      scale: 1.35,
                      child: LocalImage(
                        url: value,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                )
              : SizedBox.expand(
                  key: ValueKey(value),
                ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xC45B4538), Color(0xEB292421), Color(0xFF121110)],
              stops: [0, 0.48, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}
