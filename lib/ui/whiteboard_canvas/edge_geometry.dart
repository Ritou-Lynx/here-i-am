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

class CanvasEdgeGeometry {
  CanvasEdgeGeometry._();

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
