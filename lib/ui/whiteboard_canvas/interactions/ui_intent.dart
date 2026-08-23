/// UiIntent — user gesture semantics, resolved into serializable operations.
///
/// Huabu-style three-layer command architecture (see
/// `docs/development/WHITEBOARD_EXTERNAL_REFERENCE_HUABU.md` §1):
///
///   Web gesture → UiIntent → resolver (ViewModel) → WhiteboardOperation(s)
///   Agent response → (WhiteboardOperation[] directly, same executor)
///
/// [UiIntent]s are UI-transient: they may depend on selection, clipboard,
/// viewport or pointer state. They never mutate state themselves and never
/// own undo snapshots. The ViewModel resolves each intent into one or more
/// [WhiteboardOperation]s via the adapter — the single write path shared by
/// user gestures and future Lin Ai orchestration.
library;

import 'dart:math' as math;

/// Base class for all UI gesture intents.
sealed class UiIntent {
  const UiIntent();
}

/// Select a single item (replacing the current selection).
class SelectItemIntent extends UiIntent {
  final String itemId;

  const SelectItemIntent({required this.itemId});
}

/// Toggle an item in/out of the current selection.
class ToggleItemSelectionIntent extends UiIntent {
  final String itemId;

  const ToggleItemSelectionIntent({required this.itemId});
}

/// Select all items that intersect the given canvas rectangle (marquee).
class MarqueeSelectIntent extends UiIntent {
  final math.Rectangle<double> canvasRect;

  const MarqueeSelectIntent({required this.canvasRect});
}

/// Select every item on the board, optionally excluding some ids
/// (e.g. items hidden by a collapsed group).
class SelectAllIntent extends UiIntent {
  final Set<String> exclude;

  const SelectAllIntent({this.exclude = const {}});
}

/// Clear the current item selection.
class ClearSelectionIntent extends UiIntent {
  const ClearSelectionIntent();
}

/// Move the selected items by a canvas delta.
///
/// Gestures invoke this repeatedly during a drag; the gesture layer wraps
/// the whole drag in a single logical action so all these operations merge
/// into one undo step.
class MoveSelectionIntent extends UiIntent {
  final double dx;
  final double dy;

  const MoveSelectionIntent({required this.dx, required this.dy});
}

/// Keyboard nudge of the selection by a fixed canvas delta.
///
/// Unlike [MoveSelectionIntent], this always forms exactly one logical
/// action (one undo step) per key press.
class NudgeSelectionIntent extends UiIntent {
  final double dx;
  final double dy;

  const NudgeSelectionIntent({required this.dx, required this.dy});
}

/// Delete the current selection (items and/or a selected edge).
class DeleteSelectionIntent extends UiIntent {
  const DeleteSelectionIntent();
}

/// Rotate a single item to an absolute rotation in degrees.
class RotateItemIntent extends UiIntent {
  final String itemId;
  final double rotationDegrees;

  const RotateItemIntent({required this.itemId, required this.rotationDegrees});
}

/// Resize a single item to an absolute size (canvas units).
class ResizeItemIntent extends UiIntent {
  final String itemId;
  final double width;
  final double height;

  const ResizeItemIntent({
    required this.itemId,
    required this.width,
    required this.height,
  });
}

/// Toggle a group's collapsed state.
class ToggleGroupCollapsedIntent extends UiIntent {
  final String groupId;

  const ToggleGroupCollapsedIntent({required this.groupId});
}

/// Retarget one endpoint of an existing edge.
///
/// Exactly one of [fromItemId] / [toItemId] should be provided; the other
/// endpoint stays. Passing the same item for both endpoints is rejected by
/// the resolver (self-loop).
class RetargetEdgeIntent extends UiIntent {
  final String edgeId;
  final String? fromItemId;
  final String? toItemId;
  final Map<String, dynamic> stylePatch;

  const RetargetEdgeIntent({
    required this.edgeId,
    this.fromItemId,
    this.toItemId,
    this.stylePatch = const {},
  });
}

/// Select an edge (for endpoint editing / deletion).
class SelectEdgeIntent extends UiIntent {
  final String edgeId;

  const SelectEdgeIntent({required this.edgeId});
}

/// Clear the current edge selection.
class ClearEdgeSelectionIntent extends UiIntent {
  const ClearEdgeSelectionIntent();
}
