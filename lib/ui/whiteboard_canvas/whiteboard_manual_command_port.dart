library;

import 'dart:math' as math;

class WhiteboardManualCreateResult {
  const WhiteboardManualCreateResult({
    required this.cardId,
    required this.itemId,
  });

  final String cardId;
  final String itemId;
}

/// Semantic commit boundary used only by the production whiteboard route.
/// Tests and disposable canvas fixtures may omit it and keep their in-memory
/// adapter behavior; a real desktop route always supplies the Domain-backed
/// implementation.
abstract interface class WhiteboardManualCommandPort {
  Future<WhiteboardManualCreateResult?> createNote({
    required double x,
    required double y,
    double width = 260,
    double height = 200,
  });

  Future<bool> editCard({
    required String cardId,
    required String title,
    required String body,
  });

  Future<bool> setCardLabels({
    required String cardId,
    required List<String> labels,
  });

  Future<bool> movePlacements(
    Map<String, math.Point<double>> positions,
  );

  Future<bool> resizePlacement({
    required String itemId,
    required double width,
    required double height,
  });

  Future<bool> removePlacements(List<String> itemIds);
}
