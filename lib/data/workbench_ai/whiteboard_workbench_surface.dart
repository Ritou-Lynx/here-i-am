library;

import 'dart:async';

typedef WhiteboardSurfaceFlush = Future<bool> Function();
typedef WhiteboardSurfaceReload = Future<void> Function();

class WhiteboardWorkbenchSurface {
  const WhiteboardWorkbenchSurface({
    required this.owner,
    required this.boardId,
    required this.selectedItemIds,
    required this.flush,
    required this.reload,
  });

  final Object owner;
  final String boardId;
  final Set<String> selectedItemIds;
  final WhiteboardSurfaceFlush flush;
  final WhiteboardSurfaceReload reload;

  WhiteboardWorkbenchSurface copyWith({Set<String>? selectedItemIds}) {
    return WhiteboardWorkbenchSurface(
      owner: owner,
      boardId: boardId,
      selectedItemIds:
          Set.unmodifiable(selectedItemIds ?? this.selectedItemIds),
      flush: flush,
      reload: reload,
    );
  }
}

/// Product-owned bridge between the visible whiteboard route and the global
/// desktop conversation. It carries stable ids and lifecycle callbacks only;
/// no widget, view-model, Drift handle, or provider session crosses the seam.
class WhiteboardWorkbenchSurfaceController {
  WhiteboardWorkbenchSurfaceController._();

  static final instance = WhiteboardWorkbenchSurfaceController._();

  WhiteboardWorkbenchSurface? _current;

  WhiteboardWorkbenchSurface? get current => _current;

  void attach({
    required Object owner,
    required String boardId,
    required Set<String> selectedItemIds,
    required WhiteboardSurfaceFlush flush,
    required WhiteboardSurfaceReload reload,
  }) {
    _current = WhiteboardWorkbenchSurface(
      owner: owner,
      boardId: boardId,
      selectedItemIds: Set.unmodifiable(selectedItemIds),
      flush: flush,
      reload: reload,
    );
  }

  void updateSelection(Object owner, Set<String> selectedItemIds) {
    final surface = _current;
    if (surface == null || !identical(surface.owner, owner)) return;
    _current = surface.copyWith(selectedItemIds: selectedItemIds);
  }

  void detach(Object owner) {
    if (identical(_current?.owner, owner)) _current = null;
  }
}
