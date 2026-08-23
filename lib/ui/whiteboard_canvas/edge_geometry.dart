/// Canvas-local BoardEdge endpoint geometry.
///
/// The stable relationship remains `from_item_id / to_item_id`. Optional
/// four-way anchor preferences are stored in the existing `BoardEdge.style`
/// extension map, never as screen pixels or a second relationship identity.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:memex/domain/whiteboard/board.dart';

enum CanvasAnchorSide { top, right, bottom, left }

class CanvasEdgeConnection {
  const CanvasEdgeConnection({
    required this.from,
    required this.to,
    required this.fromSide,
    required this.toSide,
  });

  final Offset from;
  final Offset to;
  final CanvasAnchorSide fromSide;
  final CanvasAnchorSide toSide;
}

/// The closest legal item anchor to a screen-space pointer.
///
/// [screenPoint] is deliberately retained in screen coordinates so callers
/// can snap previews and render feedback without re-applying zoom.
class CanvasAnchorCandidate {
  const CanvasAnchorCandidate({
    required this.itemId,
    required this.side,
    required this.screenPoint,
    required this.distance,
  });

  final String itemId;
  final CanvasAnchorSide side;
  final Offset screenPoint;
  final double distance;
}

/// Screen-space cubic used by both painting and hit-testing.
class CanvasEdgeCurve {
  const CanvasEdgeCurve({
    required this.from,
    required this.control1,
    required this.control2,
    required this.to,
  });

  final Offset from;
  final Offset control1;
  final Offset control2;
  final Offset to;

  Path toPath() => Path()
    ..moveTo(from.dx, from.dy)
    ..cubicTo(
      control1.dx,
      control1.dy,
      control2.dx,
      control2.dy,
      to.dx,
      to.dy,
    );

  Offset pointAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final inverse = 1 - clamped;
    return from * (inverse * inverse * inverse) +
        control1 * (3 * inverse * inverse * clamped) +
        control2 * (3 * inverse * clamped * clamped) +
        to * (clamped * clamped * clamped);
  }

  double distanceTo(Offset point, {int segments = 32}) {
    var best = double.infinity;
    var previous = from;
    for (var index = 1; index <= segments; index++) {
      final current = pointAt(index / segments);
      best = math.min(best, _distanceToSegment(point, previous, current));
      previous = current;
    }
    return best;
  }

  static double _distanceToSegment(Offset point, Offset from, Offset to) {
    final delta = to - from;
    final lengthSquared = delta.distanceSquared;
    if (lengthSquared == 0) return (point - from).distance;
    final projection =
        ((point - from).dx * delta.dx + (point - from).dy * delta.dy) /
            lengthSquared;
    final t = projection.clamp(0.0, 1.0);
    return (point - (from + delta * t)).distance;
  }
}

class CanvasEdgeGeometry {
  CanvasEdgeGeometry._();

  /// A forgiving target around each 14 px anchor handle. This value is in
  /// screen pixels, so zoom never makes connection creation harder.
  static const anchorSnapRadius = 28.0;

  static CanvasEdgeCurve curveBetween(Offset fromScreen, Offset toScreen) {
    final midX = (fromScreen.dx + toScreen.dx) / 2;
    return CanvasEdgeCurve(
      from: fromScreen,
      control1: Offset(midX, fromScreen.dy),
      control2: Offset(midX, toScreen.dy),
      to: toScreen,
    );
  }

  /// Stable keys in the existing BoardEdge `style` JSON extension point.
  static const fromAnchorStyleKey = 'from_anchor_side';
  static const toAnchorStyleKey = 'to_anchor_side';

  static const supportedStyleValues = <String>{
    'top',
    'right',
    'bottom',
    'left',
  };

  static CanvasEdgeConnection resolve({
    required BoardEdge edge,
    required BoardItem from,
    required BoardItem to,
  }) {
    final fallback = _fallbackSides(from, to);
    final fromSide = _parse(edge.style[fromAnchorStyleKey]) ?? fallback.$1;
    final toSide = _parse(edge.style[toAnchorStyleKey]) ?? fallback.$2;
    return CanvasEdgeConnection(
      from: pointForSide(from, fromSide),
      to: pointForSide(to, toSide),
      fromSide: fromSide,
      toSide: toSide,
    );
  }

  static Offset pointForSide(BoardItem item, CanvasAnchorSide side) {
    final center = Offset(
      item.x + item.width / 2,
      item.y + item.height / 2,
    );
    final local = switch (side) {
      CanvasAnchorSide.top => Offset(0, -item.height / 2),
      CanvasAnchorSide.right => Offset(item.width / 2, 0),
      CanvasAnchorSide.bottom => Offset(0, item.height / 2),
      CanvasAnchorSide.left => Offset(-item.width / 2, 0),
    };
    final radians = item.rotation * math.pi / 180;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return center +
        Offset(
          local.dx * cos - local.dy * sin,
          local.dx * sin + local.dy * cos,
        );
  }

  static CanvasAnchorSide nearestSide(BoardItem item, Offset canvasPoint) {
    var best = CanvasAnchorSide.top;
    var distance = double.infinity;
    for (final side in CanvasAnchorSide.values) {
      final candidate = pointForSide(item, side);
      final candidateDistance = (candidate - canvasPoint).distanceSquared;
      if (candidateDistance < distance) {
        distance = candidateDistance;
        best = side;
      }
    }
    return best;
  }

  static CanvasAnchorCandidate? nearestAnchorWithinScreenRadius({
    required Iterable<BoardItem> items,
    required Offset pointerScreen,
    required Offset Function(Offset canvasPoint) canvasToScreen,
    Set<String> excludedItemIds = const {},
    double radius = anchorSnapRadius,
  }) {
    CanvasAnchorCandidate? best;
    final maxDistanceSquared = radius * radius;
    for (final item in items) {
      if (excludedItemIds.contains(item.itemId)) continue;
      for (final side in CanvasAnchorSide.values) {
        final screenPoint = canvasToScreen(pointForSide(item, side));
        final distanceSquared = (screenPoint - pointerScreen).distanceSquared;
        if (distanceSquared > maxDistanceSquared) continue;
        if (best == null || distanceSquared < best.distance * best.distance) {
          best = CanvasAnchorCandidate(
            itemId: item.itemId,
            side: side,
            screenPoint: screenPoint,
            distance: math.sqrt(distanceSquared),
          );
        }
      }
    }
    return best;
  }

  static (CanvasAnchorSide, CanvasAnchorSide) _fallbackSides(
    BoardItem from,
    BoardItem to,
  ) {
    final dx = (to.x + to.width / 2) - (from.x + from.width / 2);
    final dy = (to.y + to.height / 2) - (from.y + from.height / 2);
    if (dx.abs() >= dy.abs()) {
      return dx >= 0
          ? (CanvasAnchorSide.right, CanvasAnchorSide.left)
          : (CanvasAnchorSide.left, CanvasAnchorSide.right);
    }
    return dy >= 0
        ? (CanvasAnchorSide.bottom, CanvasAnchorSide.top)
        : (CanvasAnchorSide.top, CanvasAnchorSide.bottom);
  }

  static CanvasAnchorSide? _parse(Object? raw) {
    if (raw is! String || !supportedStyleValues.contains(raw)) return null;
    return CanvasAnchorSide.values.firstWhere((side) => side.name == raw);
  }
}
