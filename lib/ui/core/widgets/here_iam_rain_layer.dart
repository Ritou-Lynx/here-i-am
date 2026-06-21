import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/design_system.dart';

/// Static glass texture for the Dusky Rose Rain theme.
///
/// This is intentionally not an animation and does not use CustomPainter.
/// It is a non-interactive overlay made from ordinary widgets and gradients:
/// uneven droplets sitting behind a misted glass pane, not falling rain.
class HereIamRainLayer extends StatelessWidget {
  const HereIamRainLayer({
    super.key,
    this.opacity,
    this.microOpacity,
    this.dropletOpacity,
  });

  final double? opacity;
  final double? microOpacity;
  final double? dropletOpacity;

  @override
  Widget build(BuildContext context) {
    final tokens = context.hereIamTheme;
    return IgnorePointer(
      child: Opacity(
        opacity: opacity ?? tokens.rainOpacity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            if (width <= 0 || height <= 0) return const SizedBox.shrink();

            return Stack(
              fit: StackFit.expand,
              children: [
                _mistWash(tokens),
                Opacity(
                  opacity: dropletOpacity ?? tokens.rainStreakOpacity,
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 0.35, sigmaY: 0.35),
                    child: Stack(
                      fit: StackFit.expand,
                      children: _dropletField(tokens),
                    ),
                  ),
                ),
                Opacity(
                  opacity: microOpacity ?? tokens.rainMicroOpacity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: _microGrain(tokens),
                  ),
                ),
                ..._foregroundCondensation(tokens),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _mistWash(HereIamThemeTokens tokens) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-0.2, -0.35),
          radius: 1.18,
          colors: [
            Colors.white.withValues(alpha: 0.045),
            tokens.highlight.withValues(alpha: 0.018),
            Colors.transparent,
          ],
          stops: const [0, 0.52, 1],
        ),
      ),
    );
  }

  List<Widget> _dropletField(HereIamThemeTokens tokens) {
    const droplets = [
      _RainPoint(0.11, 0.16, 13.0, 0.34),
      _RainPoint(0.18, 0.23, 5.4, 0.46),
      _RainPoint(0.24, 0.18, 9.2, 0.42),
      _RainPoint(0.31, 0.32, 3.8, 0.34),
      _RainPoint(0.39, 0.18, 4.8, 0.30),
      _RainPoint(0.48, 0.27, 12.0, 0.32),
      _RainPoint(0.57, 0.15, 6.4, 0.38),
      _RainPoint(0.67, 0.22, 8.8, 0.42),
      _RainPoint(0.79, 0.13, 4.2, 0.28),
      _RainPoint(0.89, 0.25, 15.0, 0.30),
      _RainPoint(0.08, 0.39, 4.8, 0.34),
      _RainPoint(0.16, 0.48, 10.8, 0.36),
      _RainPoint(0.27, 0.43, 3.6, 0.30),
      _RainPoint(0.36, 0.55, 6.8, 0.42),
      _RainPoint(0.44, 0.41, 18.0, 0.26),
      _RainPoint(0.56, 0.47, 5.2, 0.34),
      _RainPoint(0.64, 0.58, 11.6, 0.32),
      _RainPoint(0.72, 0.39, 4.0, 0.28),
      _RainPoint(0.83, 0.50, 7.4, 0.40),
      _RainPoint(0.93, 0.42, 3.8, 0.30),
      _RainPoint(0.12, 0.68, 7.8, 0.42),
      _RainPoint(0.21, 0.76, 3.4, 0.30),
      _RainPoint(0.34, 0.71, 14.8, 0.30),
      _RainPoint(0.47, 0.83, 5.8, 0.40),
      _RainPoint(0.58, 0.70, 4.4, 0.32),
      _RainPoint(0.68, 0.78, 9.4, 0.36),
      _RainPoint(0.77, 0.66, 3.6, 0.28),
      _RainPoint(0.88, 0.82, 12.6, 0.32),
      _RainPoint(0.96, 0.72, 4.8, 0.34),
      _RainPoint(0.28, 0.91, 6.2, 0.34),
      _RainPoint(0.53, 0.94, 3.8, 0.28),
      _RainPoint(0.74, 0.92, 5.6, 0.32),
    ];

    return droplets
        .map(
          (point) => Align(
            alignment: Alignment(point.x * 2 - 1, point.y * 2 - 1),
            child: _GlassDroplet(
              size: point.size,
              color: tokens.rainBead.withValues(alpha: point.alpha),
            ),
          ),
        )
        .toList(growable: false);
  }

  List<Widget> _microGrain(HereIamThemeTokens tokens) {
    const points = [
      _RainPoint(0.08, 0.12, 1.2, 0.36),
      _RainPoint(0.31, 0.09, 1.0, 0.22),
      _RainPoint(0.54, 0.15, 1.2, 0.30),
      _RainPoint(0.82, 0.10, 1.0, 0.22),
      _RainPoint(0.16, 0.27, 1.0, 0.26),
      _RainPoint(0.39, 0.31, 1.2, 0.34),
      _RainPoint(0.72, 0.28, 1.0, 0.24),
      _RainPoint(0.93, 0.34, 1.2, 0.30),
      _RainPoint(0.05, 0.48, 1.0, 0.22),
      _RainPoint(0.27, 0.52, 1.2, 0.34),
      _RainPoint(0.49, 0.45, 1.0, 0.26),
      _RainPoint(0.68, 0.56, 1.2, 0.28),
      _RainPoint(0.87, 0.49, 1.0, 0.22),
      _RainPoint(0.14, 0.72, 1.2, 0.34),
      _RainPoint(0.36, 0.68, 1.0, 0.24),
      _RainPoint(0.61, 0.75, 1.2, 0.30),
      _RainPoint(0.79, 0.70, 1.0, 0.22),
      _RainPoint(0.95, 0.81, 1.2, 0.30),
      _RainPoint(0.22, 0.90, 1.0, 0.22),
      _RainPoint(0.47, 0.88, 1.2, 0.28),
      _RainPoint(0.74, 0.93, 1.0, 0.24),
    ];

    return points
        .map(
          (point) => Align(
            alignment: Alignment(point.x * 2 - 1, point.y * 2 - 1),
            child: Container(
              width: point.size,
              height: point.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: point.alpha),
              ),
            ),
          ),
        )
        .toList(growable: false);
  }

  List<Widget> _foregroundCondensation(HereIamThemeTokens tokens) {
    const beads = [
      _RainPoint(0.23, 0.18, 5.8, 0.62),
      _RainPoint(0.67, 0.22, 5.2, 0.48),
      _RainPoint(0.91, 0.58, 6.0, 0.52),
      _RainPoint(0.18, 0.64, 4.6, 0.40),
      _RainPoint(0.43, 0.78, 4.8, 0.34),
      _RainPoint(0.78, 0.83, 4.4, 0.32),
    ];

    return beads
        .map(
          (point) => Align(
            alignment: Alignment(point.x * 2 - 1, point.y * 2 - 1),
            child: _GlassDroplet(
              size: point.size,
              color: tokens.rainBead.withValues(alpha: point.alpha),
            ),
          ),
        )
        .toList(growable: false);
  }
}

class _GlassDroplet extends StatelessWidget {
  const _GlassDroplet({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size * 0.82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.32, -0.42),
          radius: 0.96,
          colors: [
            Colors.white.withValues(alpha: 0.16),
            color,
            color.withValues(alpha: 0.20),
            Colors.transparent,
          ],
          stops: const [0, 0.36, 0.72, 1],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.35,
        ),
      ),
    );
  }
}

class _RainPoint {
  const _RainPoint(this.x, this.y, this.size, this.alpha);

  final double x;
  final double y;
  final double size;
  final double alpha;
}
