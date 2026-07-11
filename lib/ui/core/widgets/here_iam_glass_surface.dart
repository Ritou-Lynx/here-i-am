import 'dart:ui';

import 'package:flutter/material.dart';

enum HereIamGlassLevel { raised, hero, liquid }

class HereIamGlassSurface extends StatelessWidget {
  const HereIamGlassSurface({
    super.key,
    required this.child,
    this.level = HereIamGlassLevel.raised,
    this.shape = BoxShape.rectangle,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.width,
    this.height,
    this.constraints,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final HereIamGlassLevel level;
  final BoxShape shape;
  final BorderRadius borderRadius;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final spec = _GlassSpec.forLevel(level);
    final isCircle = shape == BoxShape.circle;
    final effectiveRadius = isCircle ? null : borderRadius;
    final circleExtent = _circleExtent(width, height);
    final shadowAlpha = isCircle ? spec.shadowAlpha * 0.46 : spec.shadowAlpha;
    final shadowBlur = isCircle ? spec.shadowBlur * 0.46 : spec.shadowBlur;
    final shadowOffset =
        isCircle ? spec.shadowOffset * 0.36 : spec.shadowOffset;
    final glowAlpha = isCircle ? spec.glowAlpha * 0.72 : spec.glowAlpha;
    final glowBlur = isCircle ? spec.glowBlur * 0.62 : spec.glowBlur;
    final bottomDepthAlpha =
        isCircle ? spec.bottomDepthAlpha * 0.28 : spec.bottomDepthAlpha;
    final bottomDepthHeight = isCircle
        ? (circleExtent * 0.28).clamp(8.0, 12.0)
        : spec.bottomDepthHeight;
    final outerDecoration = BoxDecoration(
      shape: shape,
      borderRadius: effectiveRadius,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: shadowAlpha),
          blurRadius: shadowBlur,
          offset: Offset(0, shadowOffset),
        ),
        BoxShadow(
          color: const Color(0xFFC86774).withValues(alpha: glowAlpha),
          blurRadius: glowBlur,
          offset: Offset.zero,
        ),
      ],
    );

    final filtered = BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: spec.blur,
        sigmaY: spec.blur,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: shape,
                borderRadius: effectiveRadius,
                color: const Color(0xFF1C0C13).withValues(
                  alpha: spec.baseAlpha,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: shape,
                borderRadius: effectiveRadius,
                gradient: RadialGradient(
                  center: spec.topGlowCenter,
                  radius: 1.08,
                  colors: [
                    const Color(0xFFFFECDD).withValues(
                      alpha: spec.topGlowAlpha,
                    ),
                    const Color(0xFFFFC4B5).withValues(
                      alpha: spec.warmWashAlpha,
                    ),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.38, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: shape,
                borderRadius: effectiveRadius,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFFECDD).withValues(
                      alpha: spec.mistAlpha,
                    ),
                    const Color(0xFFC86774).withValues(
                      alpha: spec.roseAlpha,
                    ),
                    Colors.black.withValues(alpha: spec.depthAlpha),
                  ],
                  stops: const [0, 0.52, 1],
                ),
              ),
            ),
          ),
          if (!isCircle)
            Positioned(
              left: 18,
              right: 18,
              top: 1,
              height: spec.topLineHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFFFFE2D6).withValues(
                        alpha: spec.edgeLightAlpha,
                      ),
                      const Color(0xFFFFBAAA).withValues(
                        alpha: spec.edgeWarmAlpha,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomDepthHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: shape,
                borderRadius: effectiveRadius,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: bottomDepthAlpha),
                  ],
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    return Container(
      width: width,
      height: height,
      constraints: constraints,
      decoration: outerDecoration,
      child: ClipPath(
        clipper: shape == BoxShape.circle
            ? const ShapeBorderClipper(shape: CircleBorder())
            : ShapeBorderClipper(
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
              ),
        child: filtered,
      ),
    );
  }

  double _circleExtent(double? width, double? height) {
    if (width != null && height != null) return width < height ? width : height;
    return width ?? height ?? 40;
  }
}

class _GlassSpec {
  const _GlassSpec({
    required this.blur,
    required this.baseAlpha,
    required this.mistAlpha,
    required this.roseAlpha,
    required this.depthAlpha,
    required this.topGlowAlpha,
    required this.warmWashAlpha,
    required this.edgeLightAlpha,
    required this.edgeWarmAlpha,
    required this.bottomDepthAlpha,
    required this.shadowAlpha,
    required this.shadowBlur,
    required this.shadowOffset,
    required this.glowAlpha,
    required this.glowBlur,
    required this.topLineHeight,
    required this.bottomDepthHeight,
    required this.topGlowCenter,
  });

  final double blur;
  final double baseAlpha;
  final double mistAlpha;
  final double roseAlpha;
  final double depthAlpha;
  final double topGlowAlpha;
  final double warmWashAlpha;
  final double edgeLightAlpha;
  final double edgeWarmAlpha;
  final double bottomDepthAlpha;
  final double shadowAlpha;
  final double shadowBlur;
  final double shadowOffset;
  final double glowAlpha;
  final double glowBlur;
  final double topLineHeight;
  final double bottomDepthHeight;
  final Alignment topGlowCenter;

  factory _GlassSpec.forLevel(HereIamGlassLevel level) {
    switch (level) {
      case HereIamGlassLevel.hero:
        return const _GlassSpec(
          blur: 26,
          baseAlpha: 0.54,
          mistAlpha: 0.13,
          roseAlpha: 0.15,
          depthAlpha: 0.24,
          topGlowAlpha: 0.25,
          warmWashAlpha: 0.11,
          edgeLightAlpha: 0.36,
          edgeWarmAlpha: 0.14,
          bottomDepthAlpha: 0.30,
          shadowAlpha: 0.52,
          shadowBlur: 34,
          shadowOffset: 13,
          glowAlpha: 0.22,
          glowBlur: 30,
          topLineHeight: 1.6,
          bottomDepthHeight: 24,
          topGlowCenter: Alignment(-0.45, -0.72),
        );
      case HereIamGlassLevel.liquid:
        return const _GlassSpec(
          blur: 30,
          baseAlpha: 0.48,
          mistAlpha: 0.16,
          roseAlpha: 0.18,
          depthAlpha: 0.28,
          topGlowAlpha: 0.30,
          warmWashAlpha: 0.14,
          edgeLightAlpha: 0.40,
          edgeWarmAlpha: 0.18,
          bottomDepthAlpha: 0.36,
          shadowAlpha: 0.56,
          shadowBlur: 42,
          shadowOffset: 16,
          glowAlpha: 0.24,
          glowBlur: 38,
          topLineHeight: 1.8,
          bottomDepthHeight: 28,
          topGlowCenter: Alignment(-0.34, -0.66),
        );
      case HereIamGlassLevel.raised:
        return const _GlassSpec(
          blur: 30,
          baseAlpha: 0.64,
          mistAlpha: 0.095,
          roseAlpha: 0.12,
          depthAlpha: 0.22,
          topGlowAlpha: 0.20,
          warmWashAlpha: 0.09,
          edgeLightAlpha: 0.32,
          edgeWarmAlpha: 0.11,
          bottomDepthAlpha: 0.34,
          shadowAlpha: 0.54,
          shadowBlur: 48,
          shadowOffset: 18,
          glowAlpha: 0.16,
          glowBlur: 32,
          topLineHeight: 1.6,
          bottomDepthHeight: 30,
          topGlowCenter: Alignment(-0.56, -0.76),
        );
    }
  }
}
