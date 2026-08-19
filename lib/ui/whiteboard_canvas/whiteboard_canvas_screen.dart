/// Whiteboard canvas — full-screen canvas widget with no persistent top bar.
///
/// Renders cards, groups, edges, selection, viewport pan/zoom, marquee
/// selection, and hover/focus states. All tools and overlays are floating
/// and dismissable, per the spine contract.
///
/// Coordinate model:
///   screen = (canvas - viewportCenter) * zoom + screenCenter
///   canvas = (screen - screenCenter) / zoom + viewportCenter
///
/// Interaction architecture (Huabu §1): gestures produce [UiIntent]s, the
/// ViewModel resolves them into [WhiteboardOperation]s through the adapter —
/// the single write path shared with future Lin Ai orchestration. Long
/// gestures (drag / resize / rotate / edge retarget) are wrapped in logical
/// actions so one gesture = one undo step.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart' as gestures;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';

import 'engine/flutter_canvas_adapter.dart';
import 'interactions/lod.dart';
import 'interactions/ui_intent.dart';
import 'widgets/board_target_picker.dart';
import 'whiteboard_canvas_tokens.dart';
import 'whiteboard_canvas_view_model.dart';

/// Converts between screen and canvas coordinates.
class CanvasTransform {
  final BoardViewport viewport;
  final Offset screenCenter;

  const CanvasTransform({required this.viewport, required this.screenCenter});

  Offset canvasToScreen(Offset canvasPoint) {
    return Offset(
      (canvasPoint.dx - viewport.centerX) * viewport.zoom + screenCenter.dx,
      (canvasPoint.dy - viewport.centerY) * viewport.zoom + screenCenter.dy,
    );
  }

  Offset screenToCanvas(Offset screenPoint) {
    return Offset(
      (screenPoint.dx - screenCenter.dx) / viewport.zoom + viewport.centerX,
      (screenPoint.dy - screenCenter.dy) / viewport.zoom + viewport.centerY,
    );
  }

  Rect canvasToScreenRect(Rect canvasRect) {
    final tl = canvasToScreen(canvasRect.topLeft);
    final br = canvasToScreen(canvasRect.bottomRight);
    return Rect.fromPoints(tl, br);
  }

  /// The visible canvas rectangle for a given screen [size].
  ///
  /// Used for viewport culling: only board items intersecting this rect are
  /// materialized as widgets, so a 500-card board renders only the cards the
  /// user can actually see.
  Rect visibleCanvasRect(Size size) {
    final tl = screenToCanvas(Offset.zero);
    final br = screenToCanvas(Offset(size.width, size.height));
    return Rect.fromPoints(tl, br);
  }
}

/// Drag payload for card-library → canvas drag & drop.
class WhiteboardCardDragData {
  final String cardId;
  final String title;
  final Offset grabOffset;

  const WhiteboardCardDragData({
    required this.cardId,
    required this.title,
    required this.grabOffset,
  });
}

/// The main full-screen whiteboard canvas widget.
class WhiteboardCanvasScreen extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
  final VoidCallback? onExit;
  final UnifiedCardRepository? cardRepository;
  final void Function(CardContract card)? onOpenCard;

  const WhiteboardCanvasScreen({
    super.key,
    required this.viewModel,
    this.onExit,
    this.cardRepository,
    this.onOpenCard,
  });

  @override
  State<WhiteboardCanvasScreen> createState() => _WhiteboardCanvasScreenState();
}

class _WhiteboardCanvasScreenState extends State<WhiteboardCanvasScreen> {
  bool _topBarVisible = true;
  bool _sidePanelVisible = true;
  bool _showCardLibrary = false;

  /// Card currently being placed via the BoardTargetPicker.
  String? _pickerCardId;
  String _pickerCardTitle = '';

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onVmChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onVmChanged);
    super.dispose();
  }

  void _onVmChanged() {
    if (mounted) setState(() {});
  }

  // ── Keyboard shortcuts ─────────────────────────────────────────────

  void _handleEscape() {
    if (_pickerCardId != null) {
      setState(() => _pickerCardId = null);
      return;
    }
    widget.onExit?.call();
  }

  void _nudge(double dx, double dy) {
    widget.viewModel.handleIntent(NudgeSelectionIntent(dx: dx, dy: dy));
  }

  Map<ShortcutActivator, VoidCallback> _buildShortcuts() {
    final vm = widget.viewModel;
    final hidden = _hiddenItemIds(vm.boardState);
    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
          vm.undo(),
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () => vm.redo(),
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
          vm.redo(),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true): () =>
          vm.handleIntent(SelectAllIntent(exclude: hidden)),
      const SingleActivator(LogicalKeyboardKey.delete): () =>
          vm.handleIntent(const DeleteSelectionIntent()),
      const SingleActivator(LogicalKeyboardKey.backspace): () =>
          vm.handleIntent(const DeleteSelectionIntent()),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _nudge(0, -8),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _nudge(0, 8),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _nudge(-8, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _nudge(8, 0),
      const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
          _nudge(0, -32),
      const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
          _nudge(0, 32),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true): () =>
          _nudge(-32, 0),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true): () =>
          _nudge(32, 0),
      const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          vm.onSaveRequested?.call(),
    };
  }

  Set<String> _hiddenItemIds(CanvasBoardState boardState) {
    final hidden = <String>{};
    for (final group in boardState.groups) {
      if (!group.group.collapsed) continue;
      for (final member in group.members) {
        hidden.add(member.itemId);
      }
    }
    return hidden;
  }

  void _openBoardPicker(String cardId, String cardTitle) {
    setState(() {
      _pickerCardId = cardId;
      _pickerCardTitle = cardTitle;
    });
  }

  void _onPlacedInBoard(String boardName) {
    setState(() => _pickerCardId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: WhiteboardCanvasTokens.dark,
        content: Text(
          '已放入白板「$boardName」',
          style: const TextStyle(
            color: WhiteboardCanvasTokens.canvas,
            fontSize: WhiteboardCanvasTokens.metaSize,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      body: CallbackShortcuts(
        bindings: _buildShortcuts(),
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              WhiteboardCanvasArea(
                viewModel: vm,
                onOpenCard: widget.onOpenCard,
                onToggleTopBar: () =>
                    setState(() => _topBarVisible = !_topBarVisible),
                onToggleSidePanel: () =>
                    setState(() => _sidePanelVisible = !_sidePanelVisible),
              ),
              if (_topBarVisible)
                _FloatingTopBar(
                  viewModel: vm,
                  onExit: widget.onExit,
                  onToggleTopBar: () =>
                      setState(() => _topBarVisible = !_topBarVisible),
                  onToggleSidePanel: () =>
                      setState(() => _sidePanelVisible = !_sidePanelVisible),
                  onShowCardLibrary: () {
                    setState(() {
                      _showCardLibrary = !_showCardLibrary;
                      if (!_showCardLibrary) _pickerCardId = null;
                    });
                  },
                  cardLibraryVisible: _showCardLibrary,
                ),
              if (_showCardLibrary && _sidePanelVisible)
                _CardLibraryPanel(
                  viewModel: vm,
                  repository: widget.cardRepository,
                  onClose: () {
                    setState(() {
                      _showCardLibrary = false;
                      _pickerCardId = null;
                    });
                  },
                  onOpenBoardPicker: _openBoardPicker,
                ),
              if (_pickerCardId != null) ...[
                // Click-outside barrier for the popover.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () => setState(() => _pickerCardId = null),
                    child: const SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: 264,
                  top: 64,
                  child: BoardTargetPicker(
                    viewModel: vm,
                    cardId: _pickerCardId!,
                    cardTitle: _pickerCardTitle,
                    onClose: () => setState(() => _pickerCardId = null),
                    onPlaced: _onPlacedInBoard,
                  ),
                ),
              ],
              _FloatingBottomBar(viewModel: vm),
            ],
          ),
        ),
      ),
    );
  }
}

/// The canvas area — handles all gestures and renders the board.
class WhiteboardCanvasArea extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
  final void Function(CardContract card)? onOpenCard;
  final VoidCallback onToggleTopBar;
  final VoidCallback onToggleSidePanel;

  const WhiteboardCanvasArea({
    super.key,
    required this.viewModel,
    this.onOpenCard,
    required this.onToggleTopBar,
    required this.onToggleSidePanel,
  });

  @override
  State<WhiteboardCanvasArea> createState() => _WhiteboardCanvasAreaState();
}

class _WhiteboardCanvasAreaState extends State<WhiteboardCanvasArea> {
  static const _doubleClickWindow = Duration(milliseconds: 400);

  // Pan gesture (view movement) — triggered by middle-mouse or space+drag
  bool _isPanning = false;
  Offset _lastPointerPosition = Offset.zero;

  // Marquee selection
  bool _isMarqueeing = false;
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  // Drag / resize / rotate / edge-retarget gesture state
  _CardDragState? _dragState;
  _ResizeState? _resizeState;
  _RotateState? _rotateState;
  _EdgeRetargetState? _edgeRetargetState;

  // LOD tier per item (transient render state, per Huabu §5)
  final Map<String, LodTier> _lodTiers = {};

  // Last computed transform, for drop-position math outside build().
  CanvasTransform? _lastTransform;
  final GlobalKey _canvasAreaKey = GlobalKey();
  String? _lastClickedItemId;
  DateTime? _lastClickAt;

  void _handleCardClick(CanvasCardNode node) {
    final now = DateTime.now();
    final isDoubleClick = _lastClickedItemId == node.itemId &&
        _lastClickAt != null &&
        now.difference(_lastClickAt!) <= _doubleClickWindow;
    widget.viewModel.handleIntent(SelectItemIntent(itemId: node.itemId));
    if (isDoubleClick && node.card != null && widget.onOpenCard != null) {
      _lastClickedItemId = null;
      _lastClickAt = null;
      widget.onOpenCard!(node.card!);
      return;
    }
    _lastClickedItemId = node.itemId;
    _lastClickAt = now;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final boardState = vm.boardState;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final screenCenter = Offset(size.width / 2, size.height / 2);
        final transform = CanvasTransform(
          viewport: vm.viewport,
          screenCenter: screenCenter,
        );
        _lastTransform = transform;

        return DragTarget<WhiteboardCardDragData>(
          onAcceptWithDetails: (details) =>
              _handleCardDrop(details.data, details.offset),
          builder: (context, candidates, rejected) {
            return Listener(
              key: _canvasAreaKey,
              behavior: HitTestBehavior.opaque,
              onPointerSignal: (event) {
                if (event is gestures.PointerScrollEvent) {
                  final factor = event.scrollDelta.dy < 0 ? 1.1 : 0.9;
                  vm.zoomViewport(
                    factor,
                    math.Point(event.localPosition.dx, event.localPosition.dy),
                  );
                }
              },
              onPointerDown: (event) {
                final buttons = event.buttons;
                if (buttons & gestures.kPrimaryMouseButton != 0) {
                  // Primary button: if over a card (or its chrome), the
                  // card's GestureDetector handles it; if over an edge, the
                  // edge becomes selected for endpoint editing; otherwise
                  // begin a marquee.
                  if (_isOverCardOrChrome(event.localPosition, transform)) {
                    return;
                  }
                  if (_selectEdgeAt(
                    event.localPosition,
                    boardState,
                    transform,
                  )) {
                    return;
                  }
                  setState(() {
                    _isMarqueeing = true;
                    _marqueeStart = event.localPosition;
                    _marqueeCurrent = event.localPosition;
                  });
                } else if (buttons & gestures.kMiddleMouseButton != 0) {
                  // Middle button: pan the viewport.
                  _isPanning = true;
                  _lastPointerPosition = event.localPosition;
                } else if (buttons & gestures.kSecondaryMouseButton != 0) {
                  // Right button: pan as well.
                  _isPanning = true;
                  _lastPointerPosition = event.localPosition;
                }
              },
              onPointerMove: (event) {
                if (_isMarqueeing && _marqueeStart != null) {
                  setState(() {
                    _marqueeCurrent = event.localPosition;
                  });
                } else if (_isPanning) {
                  final delta = event.localPosition - _lastPointerPosition;
                  vm.panViewport(delta.dx, delta.dy);
                  _lastPointerPosition = event.localPosition;
                }
              },
              onPointerUp: (event) {
                if (_isMarqueeing &&
                    _marqueeStart != null &&
                    _marqueeCurrent != null) {
                  _completeMarquee(transform);
                }
                setState(() {
                  _isMarqueeing = false;
                  _marqueeStart = null;
                  _marqueeCurrent = null;
                  _isPanning = false;
                });
              },
              child: CustomPaint(
                size: size,
                painter: _CanvasPainter(
                  boardState: boardState,
                  transform: transform,
                  selection: vm.selection.selectedItemIds,
                  marqueeRect: _isMarqueeing &&
                          _marqueeStart != null &&
                          _marqueeCurrent != null
                      ? Rect.fromPoints(_marqueeStart!, _marqueeCurrent!)
                      : null,
                  selectedEdgeId: vm.selectedEdgeId,
                  retargetPreview: _edgeRetargetState != null
                      ? (
                          from: _edgeRetargetState!.fixedPoint,
                          to: _edgeRetargetState!.currentPoint,
                        )
                      : null,
                  hiddenItemIds: _hiddenItemIds(boardState),
                ),
                child: _buildCardWidgets(boardState, transform, size),
              ),
            );
          },
        );
      },
    );
  }

  Set<String> _hiddenItemIds(CanvasBoardState boardState) {
    final hidden = <String>{};
    for (final group in boardState.groups) {
      if (!group.group.collapsed) continue;
      for (final member in group.members) {
        hidden.add(member.itemId);
      }
    }
    return hidden;
  }

  /// True when the pointer is over a card or its chrome (resize / rotate
  /// handles), so gestures there never start a marquee. Chrome is hit-tested
  /// precisely (handle rects) so marquees can still start right next to a
  /// card.
  bool _isOverCardOrChrome(Offset screenPos, CanvasTransform transform) {
    final boardState = widget.viewModel.boardState;
    final selection = widget.viewModel.selection;
    for (final node in boardState.nodes) {
      final item = node.item;
      final screenRect = transform.canvasToScreenRect(
        Rect.fromLTWH(item.x, item.y, item.width, item.height),
      );
      if (screenRect.contains(screenPos)) return true;
      if (!selection.isSelected(item.itemId)) continue;
      final rotateRect = Rect.fromCenter(
        center: Offset(screenRect.center.dx, screenRect.top - 17),
        width: 24,
        height: 24,
      );
      if (rotateRect.contains(screenPos)) return true;
      final resizeRect = Rect.fromCenter(
        center: Offset(screenRect.right + 7, screenRect.bottom + 7),
        width: 24,
        height: 24,
      );
      if (resizeRect.contains(screenPos)) return true;
    }
    return false;
  }

  /// Selects the edge whose segment is within 10 screen px of the pointer.
  bool _selectEdgeAt(
    Offset screenPos,
    CanvasBoardState boardState,
    CanvasTransform transform,
  ) {
    final edgeId = _edgeAt(screenPos, boardState, transform);
    if (edgeId == null) return false;
    widget.viewModel.handleIntent(SelectEdgeIntent(edgeId: edgeId));
    return true;
  }

  String? _edgeAt(
    Offset screenPos,
    CanvasBoardState boardState,
    CanvasTransform transform,
  ) {
    final itemMap = {for (final n in boardState.nodes) n.itemId: n.item};
    final hidden = _hiddenItemIds(boardState);
    String? best;
    var bestDist = 10.0;
    for (final edgeNode in boardState.edges) {
      if (hidden.contains(edgeNode.edge.fromItemId) ||
          hidden.contains(edgeNode.edge.toItemId)) {
        continue;
      }
      final from = itemMap[edgeNode.edge.fromItemId];
      final to = itemMap[edgeNode.edge.toItemId];
      if (from == null || to == null) continue;
      final a = transform.canvasToScreen(
        Offset(from.x + from.width / 2, from.y + from.height / 2),
      );
      final b = transform.canvasToScreen(
        Offset(to.x + to.width / 2, to.y + to.height / 2),
      );
      final d = _distanceToSegment(screenPos, a, b);
      if (d < bestDist) {
        bestDist = d;
        best = edgeNode.edgeId;
      }
    }
    return best;
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(
      0.0,
      1.0,
    );
    return (p - (a + ab * t)).distance;
  }

  /// Whether a canvas point lies inside an item, accounting for rotation.
  static bool _pointInItem(math.Point<double> p, BoardItem item) {
    final cx = item.x + item.width / 2;
    final cy = item.y + item.height / 2;
    final rad = item.rotation * math.pi / 180;
    final dx = p.x - cx;
    final dy = p.y - cy;
    final cos = math.cos(-rad);
    final sin = math.sin(-rad);
    final lx = dx * cos - dy * sin;
    final ly = dx * sin + dy * cos;
    return lx.abs() <= item.width / 2 && ly.abs() <= item.height / 2;
  }

  CanvasCardNode? _itemAtCanvas(math.Point<double> p) {
    for (final node in widget.viewModel.boardState.nodes) {
      if (_pointInItem(p, node.item)) return node;
    }
    return null;
  }

  void _completeMarquee(CanvasTransform transform) {
    final start = _marqueeStart;
    final current = _marqueeCurrent;
    if (start == null || current == null) return;
    final vm = widget.viewModel;

    final screenRect = Rect.fromPoints(start, current);
    final canvasTopLeft = transform.screenToCanvas(screenRect.topLeft);
    final canvasBottomRight = transform.screenToCanvas(screenRect.bottomRight);
    final canvasRect = math.Rectangle(
      canvasTopLeft.dx,
      canvasTopLeft.dy,
      canvasBottomRight.dx - canvasTopLeft.dx,
      canvasBottomRight.dy - canvasTopLeft.dy,
    );
    vm.handleIntent(MarqueeSelectIntent(canvasRect: canvasRect));
  }

  // ── Card-library drag & drop ────────────────────────────────────────

  void _handleCardDrop(WhiteboardCardDragData data, Offset globalPosition) {
    final vm = widget.viewModel;
    final box = _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final transform = _lastTransform;
    if (transform == null) return;
    final local = box.globalToLocal(globalPosition);
    final canvasPoint = transform.screenToCanvas(local);
    final zoom = vm.viewport.zoom;
    vm.placeCardOnBoard(
      cardId: data.cardId,
      boardId: vm.boardId,
      x: math.max(0, canvasPoint.dx - data.grabOffset.dx / zoom),
      y: math.max(0, canvasPoint.dy - data.grabOffset.dy / zoom),
    );
  }

  // ── Card gestures (drag / resize / rotate) ──────────────────────────

  void _onDragStart(String itemId, Offset position) {
    if (widget.viewModel.isReadonly) return;
    widget.viewModel.beginLogicalAction();
    _isPanning = false;
    _dragState = _CardDragState(itemId: itemId, lastPosition: position);
  }

  void _onDragUpdate(String itemId, Offset position) {
    if (_dragState?.itemId != itemId) return;
    final vm = widget.viewModel;
    final dx = (position.dx - _dragState!.lastPosition.dx) / vm.viewport.zoom;
    final dy = (position.dy - _dragState!.lastPosition.dy) / vm.viewport.zoom;
    // Dragging a selected card moves the whole selection; dragging an
    // unselected card moves just it.
    final ids = vm.selection.isSelected(itemId)
        ? vm.selection.selectedItemIds
        : {itemId};
    vm.moveItems({for (final id in ids) id: math.Point(dx, dy)});
    _dragState = _CardDragState(itemId: itemId, lastPosition: position);
  }

  void _onDragEnd() {
    if (_dragState == null) return;
    _dragState = null;
    widget.viewModel.endLogicalAction();
  }

  void _onResizeStart(String itemId, Offset cornerScreenPos) {
    if (widget.viewModel.isReadonly) return;
    final node = widget.viewModel.boardState.nodes
        .cast<CanvasCardNode?>()
        .firstWhere((n) => n?.itemId == itemId, orElse: () => null);
    if (node == null) return;
    widget.viewModel.beginLogicalAction();
    _resizeState = _ResizeState(
      itemId: itemId,
      startWidth: node.item.width,
      startHeight: node.item.height,
      startX: node.item.x,
      startY: node.item.y,
      lastPosition: cornerScreenPos,
    );
  }

  void _onResizeUpdate(String itemId, Offset cornerScreenPos) {
    if (_resizeState?.itemId != itemId) return;
    final vm = widget.viewModel;
    final dx =
        (cornerScreenPos.dx - _resizeState!.lastPosition.dx) / vm.viewport.zoom;
    final dy =
        (cornerScreenPos.dy - _resizeState!.lastPosition.dy) / vm.viewport.zoom;
    final newW = (_resizeState!.startWidth + dx).clamp(120.0, 3000.0);
    final newH = (_resizeState!.startHeight + dy).clamp(80.0, 3000.0);
    vm.handleIntent(
      ResizeItemIntent(itemId: itemId, width: newW, height: newH),
    );
  }

  void _onResizeEnd() {
    if (_resizeState == null) return;
    _resizeState = null;
    widget.viewModel.endLogicalAction();
  }

  void _onRotateStart(String itemId, Offset pointerScreenPos) {
    if (widget.viewModel.isReadonly) return;
    final node = widget.viewModel.boardState.nodes
        .cast<CanvasCardNode?>()
        .firstWhere((n) => n?.itemId == itemId, orElse: () => null);
    if (node == null) return;
    final transform = _lastTransform;
    if (transform == null) return;
    final item = node.item;
    final center = transform.canvasToScreen(
      Offset(item.x + item.width / 2, item.y + item.height / 2),
    );
    widget.viewModel.beginLogicalAction();
    _rotateState = _RotateState(
      itemId: itemId,
      centerScreen: center,
      lastPointer: pointerScreenPos,
    );
  }

  void _onRotateUpdate(String itemId, Offset pointerScreenPos) {
    if (_rotateState?.itemId != itemId) return;
    final center = _rotateState!.centerScreen;
    final angle = math.atan2(
      pointerScreenPos.dy - center.dy,
      pointerScreenPos.dx - center.dx,
    );
    var degrees = angle * 180 / math.pi;
    degrees = ((degrees % 360) + 360) % 360;
    widget.viewModel.handleIntent(
      RotateItemIntent(itemId: itemId, rotationDegrees: degrees),
    );
    _rotateState = _RotateState(
      itemId: itemId,
      centerScreen: center,
      lastPointer: pointerScreenPos,
    );
  }

  void _onRotateEnd() {
    if (_rotateState == null) return;
    _rotateState = null;
    widget.viewModel.endLogicalAction();
  }

  // ── Edge endpoint editing ───────────────────────────────────────────

  void _onEdgeHandleStart(
    String edgeId,
    bool isFrom,
    Offset fixedPoint,
    Offset pointerPos,
  ) {
    if (widget.viewModel.isReadonly) return;
    widget.viewModel.beginLogicalAction();
    setState(() {
      _edgeRetargetState = _EdgeRetargetState(
        edgeId: edgeId,
        isFrom: isFrom,
        fixedPoint: fixedPoint,
        currentPoint: pointerPos,
      );
    });
  }

  void _onEdgeHandleUpdate(Offset pointerPos) {
    final state = _edgeRetargetState;
    if (state == null) return;
    setState(() {
      _edgeRetargetState = _EdgeRetargetState(
        edgeId: state.edgeId,
        isFrom: state.isFrom,
        fixedPoint: state.fixedPoint,
        currentPoint: pointerPos,
      );
    });
  }

  void _onEdgeHandleEnd() {
    final state = _edgeRetargetState;
    if (state == null) return;
    final vm = widget.viewModel;
    final transform = _lastTransform;
    if (transform != null) {
      final canvasPoint = transform.screenToCanvas(state.currentPoint);
      final target = _itemAtCanvas(math.Point(canvasPoint.dx, canvasPoint.dy));
      if (target != null) {
        final ok = vm.handleIntent(
          RetargetEdgeIntent(
            edgeId: state.edgeId,
            fromItemId: state.isFrom ? target.itemId : null,
            toItemId: state.isFrom ? null : target.itemId,
          ),
        );
        if (!ok) vm.cancelLogicalAction();
      } else {
        // Dropped on empty canvas: no side effects.
        vm.cancelLogicalAction();
      }
    } else {
      vm.cancelLogicalAction();
    }
    vm.endLogicalAction();
    setState(() => _edgeRetargetState = null);
  }

  // ── Rendering ───────────────────────────────────────────────────────

  Widget _buildCardWidgets(
    CanvasBoardState boardState,
    CanvasTransform transform,
    Size size,
  ) {
    final vm = widget.viewModel;
    final hidden = _hiddenItemIds(boardState);

    final itemsByItemId = {
      for (final item in boardState.nodes) item.itemId: item.item,
    };

    // Viewport culling: only materialize cards intersecting the visible
    // canvas area (plus a margin, and always the selected items so a card
    // stays interactive while being dragged near the edge). Items hidden by
    // a collapsed group are never materialized.
    final visibleCanvas = transform.visibleCanvasRect(size).inflate(64.0);
    final visibleNodes = boardState.nodes.where((node) {
      if (hidden.contains(node.itemId)) return false;
      if (vm.selection.isSelected(node.itemId)) return true;
      final item = node.item;
      return visibleCanvas.overlaps(
        Rect.fromLTWH(item.x, item.y, item.width, item.height),
      );
    }).toList();

    // Semantic-zoom LOD (Huabu §5): per-card tier with 10px hysteresis.
    // Kept transient — never persisted into the snapshot.
    final liveIds = {for (final n in boardState.nodes) n.itemId};
    _lodTiers.removeWhere((id, _) => !liveIds.contains(id));
    for (final node in visibleNodes) {
      final screenWidth = node.item.width * vm.viewport.zoom;
      _lodTiers[node.itemId] = nextLodTier(
        current: _lodTiers[node.itemId] ?? LodTier.full,
        screenWidth: screenWidth,
      );
    }

    // Selected edge endpoint handles (drawn above cards).
    final selectedEdge = vm.selectedEdgeId != null
        ? boardState.edges.cast<CanvasEdgeNode?>().firstWhere(
              (e) => e?.edgeId == vm.selectedEdgeId,
              orElse: () => null,
            )
        : null;
    CanvasEdgeNode? visibleSelectedEdge;
    if (selectedEdge != null) {
      final from = itemsByItemId[selectedEdge.edge.fromItemId];
      final to = itemsByItemId[selectedEdge.edge.toItemId];
      if (from != null &&
          to != null &&
          !hidden.contains(from.itemId) &&
          !hidden.contains(to.itemId)) {
        visibleSelectedEdge = selectedEdge;
      }
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Groups (drawn below cards, above edges)
        for (final groupNode in boardState.groups)
          _GroupWidget(
            groupNode: groupNode,
            itemsByItemId: itemsByItemId,
            transform: transform,
            onToggle: () => vm.handleIntent(
              ToggleGroupCollapsedIntent(groupId: groupNode.groupId),
            ),
          ),
        // Cards (culled to viewport, LOD-tiered)
        for (final node in visibleNodes)
          _CardWidget(
            node: node,
            transform: transform,
            isSelected: vm.selection.isSelected(node.itemId),
            isReadonly: vm.isReadonly,
            lodTier: _lodTiers[node.itemId] ?? LodTier.full,
            onTap: () => _handleCardClick(node),
            onDragStart: (position) => _onDragStart(node.itemId, position),
            onDragUpdate: (position) => _onDragUpdate(node.itemId, position),
            onDragEnd: _onDragEnd,
          ),
        // Selection chrome: rotate + resize handles (siblings of the card
        // so they stay hit-testable outside the card bounds; positions
        // follow the card's rotation).
        if (!vm.isReadonly)
          for (final node in visibleNodes)
            if (vm.selection.isSelected(node.itemId))
              ..._buildSelectionHandles(node, transform),
        // Selected edge endpoint handles
        if (visibleSelectedEdge != null && !vm.isReadonly)
          ..._buildEdgeHandles(visibleSelectedEdge, itemsByItemId, transform),
        // Marquee selection box (on top)
        if (_isMarqueeing && _marqueeStart != null && _marqueeCurrent != null)
          Positioned(
            left: math.min(_marqueeStart!.dx, _marqueeCurrent!.dx),
            top: math.min(_marqueeStart!.dy, _marqueeCurrent!.dy),
            width: (_marqueeCurrent! - _marqueeStart!).dx.abs(),
            height: (_marqueeCurrent! - _marqueeStart!).dy.abs(),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: WhiteboardCanvasTokens.selectionBox,
                  border: Border.all(
                    color: WhiteboardCanvasTokens.selectionBoxBorder,
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _buildEdgeHandles(
    CanvasEdgeNode edgeNode,
    Map<String, BoardItem> itemsByItemId,
    CanvasTransform transform,
  ) {
    final from = itemsByItemId[edgeNode.edge.fromItemId]!;
    final to = itemsByItemId[edgeNode.edge.toItemId]!;
    final fromScreen = transform.canvasToScreen(
      Offset(from.x + from.width / 2, from.y + from.height / 2),
    );
    final toScreen = transform.canvasToScreen(
      Offset(to.x + to.width / 2, to.y + to.height / 2),
    );
    return [
      _EdgeEndpointHandle(
        key: Key('wb_edge_${edgeNode.edgeId}_from'),
        position: fromScreen,
        isFrom: true,
        edgeId: edgeNode.edgeId,
        fixedPoint: toScreen,
        onStart: _onEdgeHandleStart,
        onUpdate: _onEdgeHandleUpdate,
        onEnd: _onEdgeHandleEnd,
      ),
      _EdgeEndpointHandle(
        key: Key('wb_edge_${edgeNode.edgeId}_to'),
        position: toScreen,
        isFrom: false,
        edgeId: edgeNode.edgeId,
        fixedPoint: fromScreen,
        onStart: _onEdgeHandleStart,
        onUpdate: _onEdgeHandleUpdate,
        onEnd: _onEdgeHandleEnd,
      ),
    ];
  }

  /// Builds the rotate + resize handles for a selected card. Handle centers
  /// are computed in screen space, rotated with the card so they always sit
  /// on the card's own top-center / SE-corner.
  List<Widget> _buildSelectionHandles(
    CanvasCardNode node,
    CanvasTransform transform,
  ) {
    final item = node.item;
    final screenRect = transform.canvasToScreenRect(
      Rect.fromLTWH(item.x, item.y, item.width, item.height),
    );
    final center = screenRect.center;
    final rad = item.rotation * math.pi / 180;
    final sin = math.sin(rad);
    final cos = math.cos(rad);

    // Local offsets before rotation: rotate handle at (0, -(h/2+17)),
    // resize handle at (w/2+7, h/2+7).
    final rotateLocal = Offset(0, -(screenRect.height / 2 + 17));
    final resizeLocal = Offset(
      screenRect.width / 2 + 7,
      screenRect.height / 2 + 7,
    );
    Offset rotatePoint(Offset local) =>
        center +
        Offset(
          local.dx * cos - local.dy * sin,
          local.dx * sin + local.dy * cos,
        );

    return [
      Positioned(
        key: Key('wb_rotate_${item.itemId}'),
        left: rotatePoint(rotateLocal).dx - 9,
        top: rotatePoint(rotateLocal).dy - 9,
        child: _RotateHandle(
          onStart: (pos) => _onRotateStart(item.itemId, pos),
          onUpdate: (pos) => _onRotateUpdate(item.itemId, pos),
          onEnd: _onRotateEnd,
        ),
      ),
      Positioned(
        key: Key('wb_resize_${item.itemId}'),
        left: rotatePoint(resizeLocal).dx - 7,
        top: rotatePoint(resizeLocal).dy - 7,
        child: _ResizeHandle(
          onStart: (pos) => _onResizeStart(item.itemId, pos),
          onUpdate: (pos) => _onResizeUpdate(item.itemId, pos),
          onEnd: _onResizeEnd,
        ),
      ),
    ];
  }
}

class _CardDragState {
  final String itemId;
  final Offset lastPosition;
  const _CardDragState({required this.itemId, required this.lastPosition});
}

class _ResizeState {
  final String itemId;
  final double startWidth;
  final double startHeight;
  final double startX;
  final double startY;
  final Offset lastPosition;
  const _ResizeState({
    required this.itemId,
    required this.startWidth,
    required this.startHeight,
    required this.startX,
    required this.startY,
    required this.lastPosition,
  });
}

class _RotateState {
  final String itemId;
  final Offset centerScreen;
  final Offset lastPointer;
  const _RotateState({
    required this.itemId,
    required this.centerScreen,
    required this.lastPointer,
  });
}

class _EdgeRetargetState {
  final String edgeId;
  final bool isFrom;
  final Offset fixedPoint;
  final Offset currentPoint;
  const _EdgeRetargetState({
    required this.edgeId,
    required this.isFrom,
    required this.fixedPoint,
    required this.currentPoint,
  });
}

/// Custom painter for edges and grid.
class _CanvasPainter extends CustomPainter {
  final CanvasBoardState boardState;
  final CanvasTransform transform;
  final Set<String> selection;
  final Rect? marqueeRect;
  final String? selectedEdgeId;
  final ({Offset from, Offset to})? retargetPreview;
  final Set<String> hiddenItemIds;

  _CanvasPainter({
    required this.boardState,
    required this.transform,
    required this.selection,
    this.marqueeRect,
    this.selectedEdgeId,
    this.retargetPreview,
    this.hiddenItemIds = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawEdges(canvas);
    _drawRetargetPreview(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridSize = 40.0 * transform.viewport.zoom;
    if (gridSize < 8) return;

    final offsetX = transform.canvasToScreen(Offset.zero).dx % gridSize;
    final offsetY = transform.canvasToScreen(Offset.zero).dy % gridSize;

    final paint = Paint()
      ..color = const Color(0x0DB5B2A8)
      ..strokeWidth = 0.5;

    for (double x = offsetX; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = offsetY; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawEdges(Canvas canvas) {
    final itemMap = {for (final n in boardState.nodes) n.itemId: n.item};
    for (final edgeNode in boardState.edges) {
      if (hiddenItemIds.contains(edgeNode.edge.fromItemId) ||
          hiddenItemIds.contains(edgeNode.edge.toItemId)) {
        continue;
      }
      final from = itemMap[edgeNode.edge.fromItemId];
      final to = itemMap[edgeNode.edge.toItemId];
      if (from == null || to == null) continue;

      final isSelected = edgeNode.edgeId == selectedEdgeId;
      final fromCenter = Offset(
        from.x + from.width / 2,
        from.y + from.height / 2,
      );
      final toCenter = Offset(to.x + to.width / 2, to.y + to.height / 2);
      final fromScreen = transform.canvasToScreen(fromCenter);
      final toScreen = transform.canvasToScreen(toCenter);

      final paint = Paint()
        ..color = isSelected
            ? WhiteboardCanvasTokens.edgeSelected
            : WhiteboardCanvasTokens.edge
        ..strokeWidth = isSelected
            ? WhiteboardCanvasTokens.edgeWidthSelected
            : WhiteboardCanvasTokens.edgeWidth
        ..style = PaintingStyle.stroke;

      final midX = (fromScreen.dx + toScreen.dx) / 2;
      final path = Path()
        ..moveTo(fromScreen.dx, fromScreen.dy)
        ..cubicTo(
          midX,
          fromScreen.dy,
          midX,
          toScreen.dy,
          toScreen.dx,
          toScreen.dy,
        );
      canvas.drawPath(path, paint);

      if (edgeNode.edge.direction == EdgeDirection.directed) {
        _drawArrowHead(canvas, toScreen, fromScreen, paint);
      }

      final label = edgeNode.edge.label;
      if (label != null && label.isNotEmpty) {
        final labelPainter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: WhiteboardCanvasTokens.edgeLabel,
              fontSize: WhiteboardCanvasTokens.metaSize,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        labelPainter.paint(
          canvas,
          Offset(
            (fromScreen.dx + toScreen.dx) / 2 - labelPainter.width / 2,
            (fromScreen.dy + toScreen.dy) / 2 - labelPainter.height / 2,
          ),
        );
      }
    }
  }

  void _drawRetargetPreview(Canvas canvas) {
    final preview = retargetPreview;
    if (preview == null) return;
    final paint = Paint()
      ..color = WhiteboardCanvasTokens.edgeSelected
      ..strokeWidth = WhiteboardCanvasTokens.edgeWidthSelected
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(preview.from.dx, preview.from.dy)
      ..lineTo(preview.to.dx, preview.to.dy);
    canvas.drawPath(path, paint);

    canvas.drawCircle(
      preview.to,
      4,
      Paint()
        ..color = WhiteboardCanvasTokens.edgeSelected
        ..style = PaintingStyle.fill,
    );
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset from, Paint paint) {
    final angle = (tip - from).direction;
    const arrowSize = 8.0;
    final p1 = tip +
        Offset(
          -arrowSize * math.cos(angle - math.pi / 6),
          -arrowSize * math.sin(angle - math.pi / 6),
        );
    final p2 = tip +
        Offset(
          -arrowSize * math.cos(angle + math.pi / 6),
          -arrowSize * math.sin(angle + math.pi / 6),
        );

    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(path, paint..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.transform.viewport != transform.viewport ||
        oldDelegate.transform.screenCenter != transform.screenCenter ||
        oldDelegate.boardState != boardState ||
        oldDelegate.selection != selection ||
        oldDelegate.marqueeRect != marqueeRect ||
        oldDelegate.selectedEdgeId != selectedEdgeId ||
        oldDelegate.retargetPreview != retargetPreview ||
        !setEquals(oldDelegate.hiddenItemIds, hiddenItemIds);
  }
}

/// Card widget — renders a card preview on the canvas.
///
/// Selection chrome (resize / rotate handles) is NOT part of this widget:
/// it is rendered by the canvas area as siblings, because handles sit
/// outside the card's bounds and would not be hit-testable inside a
/// clipped/positioned subtree.
class _CardWidget extends StatelessWidget {
  final CanvasCardNode node;
  final CanvasTransform transform;
  final bool isSelected;
  final bool isReadonly;
  final LodTier lodTier;
  final VoidCallback onTap;
  final void Function(Offset position) onDragStart;
  final void Function(Offset position) onDragUpdate;
  final VoidCallback onDragEnd;

  const _CardWidget({
    required this.node,
    required this.transform,
    required this.isSelected,
    required this.isReadonly,
    required this.lodTier,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final item = node.item;
    final screenRect = transform.canvasToScreenRect(
      Rect.fromLTWH(item.x, item.y, item.width, item.height),
    );

    return Positioned(
      key: Key('wb_card_${item.itemId}'),
      left: screenRect.left,
      top: screenRect.top,
      width: screenRect.width,
      height: screenRect.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onPanStart: (details) {
          if (!isReadonly) onDragStart(details.globalPosition);
        },
        onPanUpdate: (details) {
          if (!isReadonly) onDragUpdate(details.globalPosition);
        },
        onPanEnd: (_) {
          if (!isReadonly) onDragEnd();
        },
        onPanCancel: () {
          if (!isReadonly) onDragEnd();
        },
        child: Transform.rotate(
          angle: item.rotation * math.pi / 180,
          alignment: Alignment.center,
          child: _CardContent(
            key: Key('wb_card_content_${item.itemId}_${lodTier.name}'),
            node: node,
            isSelected: isSelected,
            lodTier: lodTier,
          ),
        ),
      ),
    );
  }
}

/// Card content renderer — full preview or LOD-minimal (title only).
class _CardContent extends StatelessWidget {
  final CanvasCardNode node;
  final bool isSelected;
  final LodTier lodTier;

  const _CardContent({
    super.key,
    required this.node,
    required this.isSelected,
    required this.lodTier,
  });

  @override
  Widget build(BuildContext context) {
    final isOrphaned = node.isOrphaned;
    final card = node.card;

    if (lodTier == LodTier.minimal) {
      return Container(
        decoration: BoxDecoration(
          color: isOrphaned
              ? WhiteboardCanvasTokens.orphanedSurface
              : WhiteboardCanvasTokens.cardSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.cardRadius,
          ),
          border: Border.all(
            color: isOrphaned
                ? WhiteboardCanvasTokens.orphanedBorder
                : isSelected
                    ? WhiteboardCanvasTokens.cardBorderSelected
                    : WhiteboardCanvasTokens.cardBorder,
            width: isSelected
                ? WhiteboardCanvasTokens.cardBorderWidthSelected
                : WhiteboardCanvasTokens.cardBorderWidth,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            if (isOrphaned) ...[
              const Icon(
                Icons.broken_image_outlined,
                color: WhiteboardCanvasTokens.orphanedBorder,
                size: 14,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '失效引用',
                  style: TextStyle(
                    color: WhiteboardCanvasTokens.orphanedBorder,
                    fontSize: WhiteboardCanvasTokens.statusSize,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else ...[
              Expanded(
                child: Text(
                  card!.title,
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textPrimary,
                    fontSize: WhiteboardCanvasTokens.metaSize,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isOrphaned
            ? WhiteboardCanvasTokens.orphanedSurface
            : WhiteboardCanvasTokens.cardSurface,
        borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.cardRadius),
        border: Border.all(
          color: isOrphaned
              ? WhiteboardCanvasTokens.orphanedBorder
              : isSelected
                  ? WhiteboardCanvasTokens.cardBorderSelected
                  : WhiteboardCanvasTokens.cardBorder,
          width: isSelected
              ? WhiteboardCanvasTokens.cardBorderWidthSelected
              : WhiteboardCanvasTokens.cardBorderWidth,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOrphaned)
            Expanded(
              child: _OrphanedCardContent(
                itemId: node.itemId,
                cardId: node.cardId,
              ),
            )
          else ...[
            Text(
              card!.title,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textPrimary,
                fontSize: WhiteboardCanvasTokens.titleSize,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                card.body,
                style: const TextStyle(
                  color: WhiteboardCanvasTokens.textSecondary,
                  fontSize: WhiteboardCanvasTokens.bodySize,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (card.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: card.tags.take(4).map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: WhiteboardCanvasTokens.cardSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: WhiteboardCanvasTokens.divider,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          color: WhiteboardCanvasTokens.textFaint,
                          fontSize: WhiteboardCanvasTokens.statusSize,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Orphaned card content (dangling card reference).
class _OrphanedCardContent extends StatelessWidget {
  final String itemId;
  final String cardId;

  const _OrphanedCardContent({required this.itemId, required this.cardId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: WhiteboardCanvasTokens.orphanedBorder,
            size: 24,
          ),
          const SizedBox(height: 8),
          const Text(
            '失效卡片引用',
            style: TextStyle(
              color: WhiteboardCanvasTokens.orphanedBorder,
              fontSize: WhiteboardCanvasTokens.metaSize,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cardId,
            style: const TextStyle(
              color: WhiteboardCanvasTokens.textFaint,
              fontSize: WhiteboardCanvasTokens.statusSize,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

/// Group widget — renders a group rectangle computed from member bounds.
///
/// Tap toggles collapsed state. When collapsed, member cards are hidden and
/// the group renders as a compact header chip.
class _GroupWidget extends StatelessWidget {
  final CanvasGroupNode groupNode;
  final Map<String, BoardItem> itemsByItemId;
  final CanvasTransform transform;
  final VoidCallback onToggle;

  const _GroupWidget({
    required this.groupNode,
    required this.itemsByItemId,
    required this.transform,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final memberItems = <BoardItem>[];
    for (final member in groupNode.members) {
      final item = itemsByItemId[member.itemId];
      if (item != null) memberItems.add(item);
    }
    if (memberItems.isEmpty) return const SizedBox.shrink();

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final item in memberItems) {
      minX = math.min(minX, item.x);
      minY = math.min(minY, item.y);
      maxX = math.max(maxX, item.x + item.width);
      maxY = math.max(maxY, item.y + item.height);
    }

    const pad = 24.0;
    final collapsed = groupNode.group.collapsed;
    final Rect groupRect;
    if (collapsed) {
      final width = (maxX - minX + pad * 2).clamp(180.0, 320.0);
      groupRect = Rect.fromLTWH(minX - pad, minY - pad - 20, width, 46);
    } else {
      groupRect = Rect.fromLTRB(
        minX - pad,
        minY - pad - 20,
        maxX + pad,
        maxY + pad,
      );
    }
    final screenRect = transform.canvasToScreenRect(groupRect);

    return Positioned(
      key: Key('wb_group_${groupNode.groupId}'),
      left: screenRect.left,
      top: screenRect.top,
      width: screenRect.width,
      height: screenRect.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Container(
          decoration: BoxDecoration(
            color: collapsed
                ? WhiteboardCanvasTokens.groupRect
                : WhiteboardCanvasTokens.groupRect,
            borderRadius: BorderRadius.circular(
              WhiteboardCanvasTokens.groupRadius,
            ),
            border: Border.all(
              color: collapsed
                  ? WhiteboardCanvasTokens.actionSecondary
                  : WhiteboardCanvasTokens.groupBorder,
              width: collapsed ? 1.5 : 1,
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.only(top: 6, left: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: WhiteboardCanvasTokens.canvas,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    collapsed ? Icons.unfold_more : Icons.unfold_less,
                    size: 14,
                    color: collapsed
                        ? WhiteboardCanvasTokens.actionSecondary
                        : WhiteboardCanvasTokens.groupLabel,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    groupNode.group.name.isNotEmpty
                        ? groupNode.group.name
                        : '未命名分组',
                    style: const TextStyle(
                      color: WhiteboardCanvasTokens.groupLabel,
                      fontSize: WhiteboardCanvasTokens.metaSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (collapsed) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${groupNode.members.length} 张卡片',
                      style: const TextStyle(
                        color: WhiteboardCanvasTokens.actionSecondary,
                        fontSize: WhiteboardCanvasTokens.statusSize,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Resize handle (SE corner).
class _ResizeHandle extends StatelessWidget {
  final void Function(Offset screenPos) onStart;
  final void Function(Offset screenPos) onUpdate;
  final VoidCallback onEnd;

  const _ResizeHandle({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => onStart(details.globalPosition),
        onPanUpdate: (details) => onUpdate(details.globalPosition),
        onPanEnd: (_) => onEnd(),
        onPanCancel: () => onEnd(),
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: WhiteboardCanvasTokens.canvas,
            border: Border.all(
              color: WhiteboardCanvasTokens.cardBorderSelected,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

/// Rotation handle (top-center) — drag to set the card's rotation angle.
class _RotateHandle extends StatelessWidget {
  final void Function(Offset screenPos) onStart;
  final void Function(Offset screenPos) onUpdate;
  final VoidCallback onEnd;

  const _RotateHandle({
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => onStart(details.globalPosition),
        onPanUpdate: (details) => onUpdate(details.globalPosition),
        onPanEnd: (_) => onEnd(),
        onPanCancel: () => onEnd(),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: WhiteboardCanvasTokens.canvas,
            border: Border.all(
              color: WhiteboardCanvasTokens.cardBorderSelected,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(
            Icons.rotate_right,
            size: 12,
            color: WhiteboardCanvasTokens.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Edge endpoint handle — drag to retarget the edge's endpoint onto another
/// item.
class _EdgeEndpointHandle extends StatelessWidget {
  final Offset position;
  final bool isFrom;
  final String edgeId;
  final Offset fixedPoint;
  final void Function(
    String edgeId,
    bool isFrom,
    Offset fixedPoint,
    Offset pointerPos,
  ) onStart;
  final void Function(Offset pointerPos) onUpdate;
  final VoidCallback onEnd;

  const _EdgeEndpointHandle({
    super.key,
    required this.position,
    required this.isFrom,
    required this.edgeId,
    required this.fixedPoint,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx - 7,
      top: position.dy - 7,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) =>
              onStart(edgeId, isFrom, fixedPoint, details.globalPosition),
          onPanUpdate: (details) => onUpdate(details.globalPosition),
          onPanEnd: (_) => onEnd(),
          onPanCancel: () => onEnd(),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: WhiteboardCanvasTokens.panelSurface,
              border: Border.all(
                color: WhiteboardCanvasTokens.edgeSelected,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ),
      ),
    );
  }
}

/// Floating top bar — minimal, dismissable.
class _FloatingTopBar extends StatelessWidget {
  final WhiteboardCanvasViewModel viewModel;
  final VoidCallback? onExit;
  final VoidCallback onToggleTopBar;
  final VoidCallback onToggleSidePanel;
  final VoidCallback onShowCardLibrary;
  final bool cardLibraryVisible;

  const _FloatingTopBar({
    required this.viewModel,
    this.onExit,
    required this.onToggleTopBar,
    required this.onToggleSidePanel,
    required this.onShowCardLibrary,
    required this.cardLibraryVisible,
  });

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: WhiteboardCanvasTokens.panelSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.groupRadius,
          ),
          border: Border.all(
            color: WhiteboardCanvasTokens.cardBorder,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            _FloatingButton(
              icon: Icons.arrow_back,
              tooltip: '退出白板 (Esc)',
              onTap: onExit,
            ),
            const SizedBox(width: 8),
            Text(
              vm.boardState.board.name,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            _FloatingButton(
              icon: Icons.undo,
              tooltip: '撤销 (Ctrl+Z)',
              isEnabled: vm.canUndo && !vm.isReadonly,
              onTap: vm.canUndo && !vm.isReadonly ? () => vm.undo() : null,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.redo,
              tooltip: '重做 (Ctrl+Y)',
              isEnabled: vm.canRedo && !vm.isReadonly,
              onTap: vm.canRedo && !vm.isReadonly ? () => vm.redo() : null,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.delete_outline,
              tooltip: '删除选中 (Del)',
              isEnabled: vm.selection.isNotEmpty && !vm.isReadonly,
              onTap: vm.selection.isNotEmpty && !vm.isReadonly
                  ? () => vm.removeSelectedItems()
                  : null,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.layers,
              tooltip: '置顶',
              isEnabled: vm.selection.isNotEmpty && !vm.isReadonly,
              onTap: vm.selection.isNotEmpty && !vm.isReadonly
                  ? () => vm.bringSelectedItemToFront()
                  : null,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.create_new_folder_outlined,
              tooltip: '选中建组',
              isEnabled: vm.selection.length >= 2 && !vm.isReadonly,
              onTap: vm.selection.length >= 2 && !vm.isReadonly
                  ? () => vm.createGroupFromSelection()
                  : null,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.save_outlined,
              tooltip: '保存快照 (Ctrl+S)',
              isEnabled: !vm.isReadonly,
              onTap: !vm.isReadonly ? () => vm.onSaveRequested?.call() : null,
            ),
            const Spacer(),
            _FloatingButton(
              icon: cardLibraryVisible
                  ? Icons.collections_bookmark_outlined
                  : Icons.grid_view_outlined,
              tooltip: '卡片库',
              isEnabled: true,
              onTap: onShowCardLibrary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating bottom bar — zoom controls and status.
class _FloatingBottomBar extends StatelessWidget {
  final WhiteboardCanvasViewModel viewModel;

  const _FloatingBottomBar({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: WhiteboardCanvasTokens.panelSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.groupRadius,
          ),
          border: Border.all(
            color: WhiteboardCanvasTokens.cardBorder,
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            _FloatingButton(
              icon: Icons.zoom_out,
              tooltip: '缩小',
              onTap: () => viewModel.zoomViewport(0.8, const math.Point(0, 0)),
            ),
            const SizedBox(width: 4),
            Text(
              '${(viewModel.viewport.zoom * 100).round()}%',
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textSecondary,
                fontSize: WhiteboardCanvasTokens.metaSize,
              ),
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.zoom_in,
              tooltip: '放大',
              onTap: () => viewModel.zoomViewport(1.25, const math.Point(0, 0)),
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.center_focus_strong,
              tooltip: '重置视图',
              onTap: () => viewModel.resetViewport(),
            ),
            const SizedBox(width: 12),
            if (viewModel.selection.isNotEmpty)
              Text(
                '已选 ${viewModel.selection.length} 项',
                style: const TextStyle(
                  color: WhiteboardCanvasTokens.textSecondary,
                  fontSize: WhiteboardCanvasTokens.metaSize,
                ),
              ),
            const SizedBox(width: 12),
            const Text(
              '左键框选 · 中键/右键平移 · 滚轮缩放',
              style: TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: WhiteboardCanvasTokens.statusSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating card library panel — shows available cards to place.
class _CardLibraryPanel extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
  final UnifiedCardRepository? repository;
  final VoidCallback? onClose;

  /// Opens the BoardTargetPicker for a card (target-board switching).
  final void Function(String cardId, String cardTitle) onOpenBoardPicker;

  const _CardLibraryPanel({
    required this.viewModel,
    this.repository,
    this.onClose,
    required this.onOpenBoardPicker,
  });

  @override
  State<_CardLibraryPanel> createState() => _CardLibraryPanelState();
}

class _CardLibraryPanelState extends State<_CardLibraryPanel> {
  /// Grab offset of the pointer within the dragged row, captured on pointer
  /// down (used to land the dropped card under the cursor).
  Offset _grabOffset = Offset.zero;

  List<CardContract> _allCards = [];
  bool _loading = true;
  Object? _loadError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  @override
  void didUpdateWidget(covariant _CardLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _loadCards();
    }
  }

  Future<void> _loadCards() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final repository = widget.repository;
    if (repository == null) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _allCards = const [];
        _loading = false;
        _loadError = StateError('卡片仓库不可用');
      });
      return;
    }
    late final List<CardContract> cards;
    try {
      cards =
          (await repository.listCards()).map((record) => record.card).toList();
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _allCards = const [];
        _loading = false;
        _loadError = error;
      });
      return;
    }
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _allCards = cards;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cards = _allCards;
    final alreadyPlaced =
        widget.viewModel.boardState.nodes.map((n) => n.cardId).toSet();

    return Positioned(
      left: 12,
      top: 60,
      bottom: 60,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: WhiteboardCanvasTokens.panelSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.groupRadius,
          ),
          border: Border.all(
            color: WhiteboardCanvasTokens.cardBorder,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  const Text(
                    '卡片库',
                    style: TextStyle(
                      color: WhiteboardCanvasTokens.textPrimary,
                      fontSize: WhiteboardCanvasTokens.titleSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  _FloatingButton(
                    icon: Icons.close,
                    tooltip: '关闭',
                    onTap: widget.onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: WhiteboardCanvasTokens.divider),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: WhiteboardCanvasTokens.textSecondary,
                        strokeWidth: 2,
                      ),
                    )
                  : _loadError != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '卡片库没有读出来',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: WhiteboardCanvasTokens.textSecondary,
                                    fontSize: WhiteboardCanvasTokens.metaSize,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  key: const Key('wb_card_library_retry'),
                                  onPressed: _loadCards,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : cards.isEmpty
                          ? const Center(
                              child: Text(
                                '没有可放入的卡片',
                                style: TextStyle(
                                  color: WhiteboardCanvasTokens.textFaint,
                                  fontSize: WhiteboardCanvasTokens.metaSize,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: cards.length,
                              itemBuilder: (context, index) {
                                final card = cards[index];
                                final isPlaced =
                                    alreadyPlaced.contains(card.cardId);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Listener(
                                    key: Key('wb_lib_row_${card.cardId}'),
                                    onPointerDown: (event) {
                                      _grabOffset = event.localPosition;
                                    },
                                    child: Draggable<WhiteboardCardDragData>(
                                      data: WhiteboardCardDragData(
                                        cardId: card.cardId,
                                        title: card.title,
                                        grabOffset: _grabOffset,
                                      ),
                                      feedback: _DragCardFeedback(
                                        title: card.title,
                                        kindName: card.cardKind.name,
                                      ),
                                      childWhenDragging: Opacity(
                                        opacity: 0.35,
                                        child: _libraryRow(
                                          card.title,
                                          card.cardKind.name,
                                          isPlaced,
                                          card.cardId,
                                        ),
                                      ),
                                      child: _libraryRow(
                                        card.title,
                                        card.cardKind.name,
                                        isPlaced,
                                        card.cardId,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _libraryRow(
    String title,
    String kindName,
    bool isPlaced,
    String cardId,
  ) {
    final vm = widget.viewModel;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          final vp = vm.viewport;
          vm.placeCard(
            cardId: cardId,
            x: vp.centerX - 130,
            y: vp.centerY - 100,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: WhiteboardCanvasTokens.textPrimary,
                        fontSize: WhiteboardCanvasTokens.metaSize,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPlaced)
                    const Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: WhiteboardCanvasTokens.textFaint,
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(
                      Icons.space_dashboard_outlined,
                      size: 16,
                      color: WhiteboardCanvasTokens.actionSecondary,
                    ),
                    tooltip: '放入白板…',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => widget.onOpenBoardPicker(cardId, title),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                kindName,
                style: const TextStyle(
                  color: WhiteboardCanvasTokens.textFaint,
                  fontSize: WhiteboardCanvasTokens.statusSize,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Drag feedback for card-library drag & drop.
class _DragCardFeedback extends StatelessWidget {
  final String title;
  final String kindName;

  const _DragCardFeedback({required this.title, required this.kindName});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: WhiteboardCanvasTokens.panelSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.cardRadius,
          ),
          border: Border.all(
            color: WhiteboardCanvasTokens.cardBorderSelected,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2434322F),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textPrimary,
                fontSize: WhiteboardCanvasTokens.titleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kindName,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: WhiteboardCanvasTokens.statusSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating icon button.
class _FloatingButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isEnabled;

  const _FloatingButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(
              icon,
              size: 20,
              color: isEnabled
                  ? WhiteboardCanvasTokens.textPrimary
                  : WhiteboardCanvasTokens.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}
