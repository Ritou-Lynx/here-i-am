import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/design_system.dart';

/// Static rose-mist glass wash for the companion chat surface.
///
/// This replaces the rain droplet exploration in the main chat: soft rose
/// haze, frosted depth, and no water beads or falling marks.
class HereIamRoseMistLayer extends StatelessWidget {
  const HereIamRoseMistLayer({
    super.key,
    this.opacity = 1,
  });

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.hereIamTheme;

    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.72, -0.82),
                  radius: 1.05,
                  colors: [
                    tokens.accentSoft.withValues(alpha: 0.16),
                    tokens.surfaceDeep.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.46, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.82, -0.18),
                  radius: 0.95,
                  colors: [
                    tokens.textPrimary.withValues(alpha: 0.10),
                    tokens.accentSoft.withValues(alpha: 0.045),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.42, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.045),
                    Colors.transparent,
                    tokens.accentSoft.withValues(alpha: 0.035),
                  ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tokens.backgroundSoft.withValues(alpha: 0.08),
                    Colors.transparent,
                    tokens.backgroundSoft.withValues(alpha: 0.22),
                  ],
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
