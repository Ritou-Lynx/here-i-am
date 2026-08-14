/// Whiteboard canvas — full-screen canvas widget with no persistent top bar.
///
/// Renders cards, groups, edges, selection, viewport pan/zoom, marquee
/// selection, and hover/focus states. All tools and overlays are floating
/// and dismissable, per the spine contract.
///
/// Coordinate model:
///   screen = (canvas - viewportCenter) * zoom + screenCenter
///   canvas = (screen - screenCenter) / zoom + viewportCenter
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart' as gestures;
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/board.dart';

import 'engine/flutter_canvas_adapter.dart';
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

/// The main full-screen whiteboard canvas widget.
class WhiteboardCanvasScreen extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
  final VoidCallback? onExit;

  const WhiteboardCanvasScreen({
    super.key,
    required this.viewModel,
    this.onExit,
  });

  @override
  State<WhiteboardCanvasScreen> createState() => _WhiteboardCanvasScreenState();
}

class _WhiteboardCanvasScreenState extends State<WhiteboardCanvasScreen> {
  bool _topBarVisible = true;
  bool _sidePanelVisible = true;
  bool _showCardLibrary = false;

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

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      body: Stack(
        children: [
          WhiteboardCanvasArea(
            viewModel: vm,
            onToggleTopBar: () => setState(() => _topBarVisible = !_topBarVisible),
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
              onShowCardLibrary: () =>
                  setState(() => _showCardLibrary = !_showCardLibrary),
              cardLibraryVisible: _showCardLibrary,
            ),
          if (_showCardLibrary && _sidePanelVisible)
            _CardLibraryPanel(
              viewModel: vm,
              onClose: () => setState(() => _showCardLibrary = false),
            ),
          _FloatingBottomBar(viewModel: vm),
        ],
      ),
    );
  }
}

/// The canvas area — handles all gestures and renders the board.
class WhiteboardCanvasArea extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
  final VoidCallback onToggleTopBar;
  final VoidCallback onToggleSidePanel;

  const WhiteboardCanvasArea({
    super.key,
    required this.viewModel,
    required this.onToggleTopBar,
    required this.onToggleSidePanel,
  });

  @override
  State<WhiteboardCanvasArea> createState() => _WhiteboardCanvasAreaState();
}

class _WhiteboardCanvasAreaState extends State<WhiteboardCanvasArea> {
  // Pan gesture (view movement) — triggered by middle-mouse or space+drag
  bool _isPanning = false;
  Offset _lastPointerPosition = Offset.zero;

  // Marquee selection
  bool _isMarqueeing = false;
  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final boardState = vm.boardState;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final screenCenter =
            Offset(size.width / 2, size.height / 2);
        final transform = CanvasTransform(
          viewport: vm.viewport,
          screenCenter: screenCenter,
        );

        return Listener(
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
              // Primary button: if over a card, the card's GestureDetector
              // handles selection; otherwise begin a marquee.
              if (_isOverCard(event.localPosition, transform)) return;
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
            if (_isMarqueeing && _marqueeStart != null && _marqueeCurrent != null) {
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
              marqueeRect: _isMarqueeing && _marqueeStart != null && _marqueeCurrent != null
                  ? Rect.fromPoints(_marqueeStart!, _marqueeCurrent!)
                  : null,
            ),
            child: _buildCardWidgets(boardState, transform, size),
          ),
        );
      },
    );
  }

  bool _isOverCard(Offset screenPos, CanvasTransform transform) {
    final boardState = widget.viewModel.boardState;
    for (final node in boardState.nodes) {
      final item = node.item;
      final screenRect = transform.canvasToScreenRect(
        Rect.fromLTWH(item.x, item.y, item.width, item.height),
      );
      if (screenRect.contains(screenPos)) return true;
    }
    return false;
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
    vm.selectInRect(canvasRect);
  }

  Widget _buildCardWidgets(
    CanvasBoardState boardState,
    CanvasTransform transform,
    Size size,
  ) {
    final vm = widget.viewModel;

    final itemsByItemId = {
      for (final item in boardState.nodes) item.itemId: item.item,
    };

    // Viewport culling: only materialize cards intersecting the visible
    // canvas area (plus a margin, and always the selected items so a card
    // stays interactive while being dragged near the edge).
    final visibleCanvas = transform.visibleCanvasRect(size).inflate(64.0);
    final visibleNodes = boardState.nodes.where((node) {
      if (vm.selection.isSelected(node.itemId)) return true;
      final item = node.item;
      return visibleCanvas.overlaps(
        Rect.fromLTWH(item.x, item.y, item.width, item.height),
      );
    }).toList();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Groups (drawn below cards, above edges)
        for (final groupNode in boardState.groups)
          _GroupWidget(
            groupNode: groupNode,
            itemsByItemId: itemsByItemId,
            transform: transform,
          ),
        // Cards (culled to viewport)
        for (final node in visibleNodes)
          _CardWidget(
            node: node,
            transform: transform,
            isSelected: vm.selection.isSelected(node.itemId),
            isReadonly: vm.isReadonly,
            onTap: () {
              vm.selectItem(node.itemId);
            },
            onDragStart: (position) {
              if (vm.isReadonly) return;
              _isPanning = false;
              _dragState = _CardDragState(
                itemId: node.itemId,
                lastPosition: position,
              );
            },
            onDragUpdate: (position) {
              if (_dragState?.itemId != node.itemId) return;
              final dx = (position.dx - _dragState!.lastPosition.dx) /
                  vm.viewport.zoom;
              final dy = (position.dy - _dragState!.lastPosition.dy) /
                  vm.viewport.zoom;
              vm.moveItems({node.itemId: math.Point(dx, dy)});
              _dragState = _CardDragState(
                itemId: node.itemId,
                lastPosition: position,
              );
            },
            onDragEnd: () {
              _dragState = null;
            },
            onResizeStart: (cornerScreenPos) {
              if (vm.isReadonly) return;
              _resizeState = _ResizeState(
                itemId: node.itemId,
                startWidth: node.item.width,
                startHeight: node.item.height,
                startX: node.item.x,
                startY: node.item.y,
                lastPosition: cornerScreenPos,
              );
            },
            onResizeUpdate: (cornerScreenPos) {
              if (_resizeState?.itemId != node.itemId) return;
              final dx = (cornerScreenPos.dx - _resizeState!.lastPosition.dx) /
                  vm.viewport.zoom;
              final dy = (cornerScreenPos.dy - _resizeState!.lastPosition.dy) /
                  vm.viewport.zoom;
              final newW =
                  (_resizeState!.startWidth + dx).clamp(120.0, 3000.0);
              final newH =
                  (_resizeState!.startHeight + dy).clamp(80.0, 3000.0);
              vm.resizeItem(
                itemId: node.itemId,
                width: newW,
                height: newH,
              );
            },
            onResizeEnd: () {
              _resizeState = null;
            },
          ),
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

  // Drag / resize state
  _CardDragState? _dragState;
  _ResizeState? _resizeState;
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

/// Custom painter for edges and grid.
class _CanvasPainter extends CustomPainter {
  final CanvasBoardState boardState;
  final CanvasTransform transform;
  final Set<String> selection;
  final Rect? marqueeRect;

  _CanvasPainter({
    required this.boardState,
    required this.transform,
    required this.selection,
    this.marqueeRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawEdges(canvas);
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
      final from = itemMap[edgeNode.edge.fromItemId];
      final to = itemMap[edgeNode.edge.toItemId];
      if (from == null || to == null) continue;

      final fromCenter = Offset(
        from.x + from.width / 2,
        from.y + from.height / 2,
      );
      final toCenter = Offset(
        to.x + to.width / 2,
        to.y + to.height / 2,
      );
      final fromScreen = transform.canvasToScreen(fromCenter);
      final toScreen = transform.canvasToScreen(toCenter);

      final paint = Paint()
        ..color = WhiteboardCanvasTokens.edge
        ..strokeWidth = WhiteboardCanvasTokens.edgeWidth
        ..style = PaintingStyle.stroke;

      final midX = (fromScreen.dx + toScreen.dx) / 2;
      final path = Path()
        ..moveTo(fromScreen.dx, fromScreen.dy)
        ..cubicTo(
          midX, fromScreen.dy,
          midX, toScreen.dy,
          toScreen.dx, toScreen.dy,
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

    canvas.drawPath(
      path,
      paint..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) {
    return oldDelegate.transform.viewport != transform.viewport ||
        oldDelegate.transform.screenCenter != transform.screenCenter ||
        oldDelegate.boardState != boardState ||
        oldDelegate.selection != selection ||
        oldDelegate.marqueeRect != marqueeRect;
  }
}

/// Card widget — renders a card preview on the canvas.
class _CardWidget extends StatelessWidget {
  final CanvasCardNode node;
  final CanvasTransform transform;
  final bool isSelected;
  final bool isReadonly;
  final VoidCallback onTap;
  final void Function(Offset position) onDragStart;
  final void Function(Offset position) onDragUpdate;
  final VoidCallback onDragEnd;
  final void Function(Offset cornerScreenPos) onResizeStart;
  final void Function(Offset cornerScreenPos) onResizeUpdate;
  final VoidCallback onResizeEnd;

  const _CardWidget({
    required this.node,
    required this.transform,
    required this.isSelected,
    required this.isReadonly,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final item = node.item;
    final screenRect = transform.canvasToScreenRect(
      Rect.fromLTWH(item.x, item.y, item.width, item.height),
    );

    return Positioned(
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _CardContent(node: node, isSelected: isSelected),
            if (isSelected && !isReadonly)
              Positioned(
                right: -6,
                bottom: -6,
                child: _ResizeHandle(
                  onStart: (pos) => onResizeStart(pos),
                  onUpdate: onResizeUpdate,
                  onEnd: onResizeEnd,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card content renderer.
class _CardContent extends StatelessWidget {
  final CanvasCardNode node;
  final bool isSelected;

  const _CardContent({required this.node, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    final isOrphaned = node.isOrphaned;
    final card = node.card;

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
class _GroupWidget extends StatelessWidget {
  final CanvasGroupNode groupNode;
  final Map<String, BoardItem> itemsByItemId;
  final CanvasTransform transform;

  const _GroupWidget({
    required this.groupNode,
    required this.itemsByItemId,
    required this.transform,
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

    // Add padding
    const pad = 24.0;
    final groupRect = Rect.fromLTRB(
      minX - pad,
      minY - pad - 20,
      maxX + pad,
      maxY + pad,
    );
    final screenRect = transform.canvasToScreenRect(groupRect);

    return Positioned(
      left: screenRect.left,
      top: screenRect.top,
      width: screenRect.width,
      height: screenRect.height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: WhiteboardCanvasTokens.groupRect,
            borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.groupRadius),
            border: Border.all(
              color: WhiteboardCanvasTokens.groupBorder,
              width: 1,
            ),
          ),
          child: groupNode.group.name.isNotEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    margin: const EdgeInsets.only(top: 6, left: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: WhiteboardCanvasTokens.canvas,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      groupNode.group.name,
                      style: const TextStyle(
                        color: WhiteboardCanvasTokens.groupLabel,
                        fontSize: WhiteboardCanvasTokens.metaSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                )
              : null,
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
          color: WhiteboardCanvasTokens.cardSurface,
          borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.groupRadius),
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
              tooltip: '保存快照',
              isEnabled: !vm.isReadonly,
              onTap: !vm.isReadonly
                  ? () => vm.onSaveRequested?.call()
                  : null,
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
          color: WhiteboardCanvasTokens.cardSurface,
          borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.groupRadius),
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
class _CardLibraryPanel extends StatelessWidget {
  final WhiteboardCanvasViewModel viewModel;
  final VoidCallback? onClose;

  const _CardLibraryPanel({required this.viewModel, this.onClose});

  @override
  Widget build(BuildContext context) {
    final cards = viewModel.snapshot.cards;
    final alreadyPlaced =
        viewModel.boardState.nodes.map((n) => n.cardId).toSet();

    return Positioned(
      left: 12,
      top: 60,
      bottom: 60,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: WhiteboardCanvasTokens.cardSurface,
          borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.groupRadius),
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
                    onTap: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: WhiteboardCanvasTokens.divider),
            Expanded(
              child: cards.isEmpty
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
                        final isPlaced = alreadyPlaced.contains(card.cardId);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Material(
                            color: isPlaced
                                ? WhiteboardCanvasTokens.cardSurface
                                : WhiteboardCanvasTokens.cardSurface,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () {
                                final vp = viewModel.viewport;
                                viewModel.placeCard(
                                  cardId: card.cardId,
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
                                            card.title,
                                            style: const TextStyle(
                                              color: WhiteboardCanvasTokens
                                                  .textPrimary,
                                              fontSize: WhiteboardCanvasTokens
                                                  .metaSize,
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
                                            color: WhiteboardCanvasTokens
                                                .textFaint,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      card.cardKind.name,
                                      style: const TextStyle(
                                        color:
                                            WhiteboardCanvasTokens.textFaint,
                                        fontSize:
                                            WhiteboardCanvasTokens.statusSize,
                                      ),
                                    ),
                                  ],
                                ),
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