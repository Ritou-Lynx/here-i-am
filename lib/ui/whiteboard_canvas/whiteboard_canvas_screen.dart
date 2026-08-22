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

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart' as gestures;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HardwareKeyboard, LogicalKeyboardKey;

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

import 'engine/flutter_canvas_adapter.dart';
import 'edge_geometry.dart';
import 'interactions/lod.dart';
import 'interactions/ui_intent.dart';
import 'widgets/board_target_picker.dart';
import 'widgets/board_item_edit_surface.dart';
import 'widgets/compact_card_editor.dart';
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

class _EdgeDraft {
  const _EdgeDraft({required this.direction, required this.label});

  final EdgeDirection direction;
  final String label;
}

bool _supportsCompactEdit(CardKind kind) => switch (kind) {
      CardKind.note ||
      CardKind.annotation ||
      CardKind.reference ||
      CardKind.taskArtifact =>
        true,
      CardKind.source => false,
    };

/// The main full-screen whiteboard canvas widget.
class WhiteboardCanvasScreen extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
  final VoidCallback? onExit;
  final UnifiedCardRepository? cardRepository;
  final void Function(CardContract card)? onOpenCard;
  final Future<bool> Function()? onPersistSnapshot;
  final BoardItemEditSurfaceBuilder? cardEditSurfaceBuilder;

  const WhiteboardCanvasScreen({
    super.key,
    required this.viewModel,
    this.onExit,
    this.cardRepository,
    this.onOpenCard,
    this.onPersistSnapshot,
    this.cardEditSurfaceBuilder,
  });

  @override
  State<WhiteboardCanvasScreen> createState() => _WhiteboardCanvasScreenState();
}

class _WhiteboardCanvasScreenState extends State<WhiteboardCanvasScreen> {
  bool _navigationVisible = true;
  bool _toolsVisible = true;
  bool _showCardLibrary = false;

  /// Card currently being placed via the BoardTargetPicker.
  String? _pickerCardId;
  String _pickerCardTitle = '';
  String? _editingItemId;
  bool _creatingCard = false;
  int _createGeneration = 0;
  String? _pendingCompensationCardId;
  Object? _pendingCompensationError;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onVmChanged);
  }

  @override
  void dispose() {
    _createGeneration++;
    widget.viewModel.removeListener(_onVmChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant WhiteboardCanvasScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.viewModel, widget.viewModel)) {
      oldWidget.viewModel.removeListener(_onVmChanged);
      widget.viewModel.addListener(_onVmChanged);
      _createGeneration++;
      _creatingCard = false;
    }
    if (!identical(oldWidget.cardRepository, widget.cardRepository)) {
      _createGeneration++;
      _creatingCard = false;
    }
  }

  void _onVmChanged() {
    if (!mounted) return;
    setState(() {
      if (widget.viewModel.isReadonly) {
        _editingItemId = null;
        _pickerCardId = null;
      }
    });
  }

  // ── Keyboard shortcuts ─────────────────────────────────────────────

  void _handleEscape() {
    if (_pickerCardId != null) {
      setState(() => _pickerCardId = null);
      return;
    }
    if (_showCardLibrary) {
      setState(() => _showCardLibrary = false);
      return;
    }
    if (_toolsVisible) {
      setState(() => _toolsVisible = false);
      return;
    }
    if (_navigationVisible) {
      setState(() => _navigationVisible = false);
      return;
    }
    widget.onExit?.call();
  }

  void _dismissNavigation() {
    setState(() {
      _navigationVisible = false;
      _toolsVisible = false;
      _showCardLibrary = false;
      _pickerCardId = null;
    });
  }

  void _nudge(double dx, double dy) {
    widget.viewModel.handleIntent(NudgeSelectionIntent(dx: dx, dy: dy));
  }

  Map<ShortcutActivator, VoidCallback> _buildShortcuts() {
    final vm = widget.viewModel;
    final hidden = _hiddenItemIds(vm.boardState);
    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () {
        if (!vm.isReadonly) vm.undo();
      },
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): () {
        if (!vm.isReadonly) vm.redo();
      },
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): () {
        if (!vm.isReadonly) vm.redo();
      },
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
      if (_editingItemId == null)
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
    if (widget.viewModel.isReadonly) return;
    setState(() {
      _pickerCardId = cardId;
      _pickerCardTitle = cardTitle;
    });
  }

  void _onPlacedInBoard(String boardName) {
    setState(() => _pickerCardId = null);
    final colors = WhiteboardCanvasTokens.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        backgroundColor: colors.dark,
        content: Text(
          '已放入白板「$boardName」',
          style: TextStyle(
            color: colors.canvas,
            fontSize: WhiteboardCanvasTokens.metaSize,
          ),
        ),
      ),
    );
  }

  void _toggleCardLibrary() {
    setState(() {
      _showCardLibrary = !_showCardLibrary;
      if (!_showCardLibrary) _pickerCardId = null;
    });
  }

  void _openCompactEditor(String itemId, CardContract card) {
    if (widget.viewModel.isReadonly) {
      widget.onOpenCard?.call(card);
      return;
    }
    if (!_supportsCompactEdit(card.cardKind) ||
        (widget.cardRepository == null &&
            widget.cardEditSurfaceBuilder == null)) {
      widget.onOpenCard?.call(card);
      return;
    }
    setState(() {
      _editingItemId = itemId;
    });
  }

  Future<void> _createNoteAt(Offset canvasPoint, Offset screenPoint) async {
    final repository = widget.cardRepository;
    final vm = widget.viewModel;
    if (repository == null || vm.isReadonly || _creatingCard) return;
    _creatingCard = true;
    final generation = ++_createGeneration;
    CardContract? card;
    var transactionStarted = false;
    try {
      card = await repository.createTextCard(title: '未命名卡片');
      if (!mounted ||
          generation != _createGeneration ||
          vm.isReadonly ||
          !identical(vm, widget.viewModel) ||
          !identical(repository, widget.cardRepository)) {
        await _compensateCreatedCard(repository, card.cardId);
        return;
      }
      vm.beginLogicalAction();
      transactionStarted = vm.isInLogicalAction;
      vm.upsertCardContent(card);
      final item = vm.placeCardOnBoard(
        cardId: card.cardId,
        boardId: vm.boardId,
        x: canvasPoint.dx - 130,
        y: canvasPoint.dy - 100,
      );
      if (item == null) throw StateError('无法把卡片放入当前白板');
      final persisted =
          await (widget.onPersistSnapshot?.call() ?? Future<bool>.value(true));
      if (!persisted) throw StateError('白板没有保存成功');
      vm.endLogicalAction();
      transactionStarted = false;
      if (!mounted || generation != _createGeneration) return;
      setState(() {
        _editingItemId = item.itemId;
      });
    } catch (error) {
      if (transactionStarted) {
        if (card != null) vm.removeCardContent(card.cardId);
        vm.cancelLogicalAction();
        transactionStarted = false;
      }
      if (card != null) {
        await _compensateCreatedCard(repository, card.cardId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新建卡片失败：$error')),
        );
      }
    } finally {
      if (generation == _createGeneration) _creatingCard = false;
    }
  }

  Future<bool> _compensateCreatedCard(
    UnifiedCardRepository repository,
    String cardId,
  ) async {
    try {
      final deleted = await repository.softDeleteCard(cardId);
      if (!deleted) {
        throw StateError('临时卡片没有被清理');
      }
      if (mounted && _pendingCompensationCardId == cardId) {
        setState(() {
          _pendingCompensationCardId = null;
          _pendingCompensationError = null;
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _pendingCompensationCardId = cardId;
          _pendingCompensationError = error;
        });
      }
      return false;
    }
  }

  Future<void> _retryPendingCompensation() async {
    final repository = widget.cardRepository;
    final cardId = _pendingCompensationCardId;
    if (repository == null || cardId == null) return;
    await _compensateCreatedCard(repository, cardId);
  }

  Future<bool> _persistEdgeMutation(bool Function() mutate) async {
    final vm = widget.viewModel;
    if (vm.isReadonly) return false;
    vm.beginLogicalAction();
    try {
      final changed = mutate();
      if (!changed) {
        vm.cancelLogicalAction();
        return true;
      }
      final persisted =
          await (widget.onPersistSnapshot?.call() ?? Future.value(true));
      if (!persisted) {
        vm.cancelLogicalAction();
        return false;
      }
      vm.endLogicalAction();
      return true;
    } catch (_) {
      vm.cancelLogicalAction();
      return false;
    }
  }

  Future<void> _createGroupFromSelection() async {
    final vm = widget.viewModel;
    if (vm.isReadonly || vm.selection.length < 2) return;
    var groupName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('wb_create_group_dialog'),
        title: const Text('建立分组'),
        content: TextField(
          key: const Key('wb_group_name_field'),
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名称',
            hintText: '例如：研究线索',
          ),
          onChanged: (value) => groupName = value,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('wb_confirm_create_group'),
            onPressed: () => Navigator.of(dialogContext).pop(groupName),
            child: const Text('建立分组'),
          ),
        ],
      ),
    );
    if (!mounted || name == null) return;
    vm.createGroupFromSelection(name: name.trim());
  }

  Future<void> _connectSelectedCards() async {
    final vm = widget.viewModel;
    if (vm.isReadonly || vm.selection.length != 2) return;
    final itemIds = vm.selection.selectedItemIds.toList(growable: false);
    var edgeLabel = '';
    var direction = EdgeDirection.undirected;
    final draft = await showDialog<_EdgeDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          key: const Key('wb_create_edge_dialog'),
          title: const Text('连接两张卡片'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<EdgeDirection>(
                  key: const Key('wb_edge_direction'),
                  segments: const [
                    ButtonSegment(
                      value: EdgeDirection.undirected,
                      label: Text('无向连线'),
                      icon: Icon(Icons.horizontal_rule),
                    ),
                    ButtonSegment(
                      value: EdgeDirection.directed,
                      label: Text('有向连线'),
                      icon: Icon(Icons.arrow_forward),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged: (selection) => setDialogState(
                    () => direction = selection.first,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('wb_edge_label_field'),
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '连线标签（可选）',
                    hintText: '例如：支持、反驳、来自',
                  ),
                  onChanged: (value) => edgeLabel = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const Key('wb_confirm_create_edge'),
              onPressed: () => Navigator.of(dialogContext).pop(
                _EdgeDraft(
                  direction: direction,
                  label: edgeLabel.trim(),
                ),
              ),
              child: const Text('创建连线'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || draft == null) return;
    vm.createEdge(
      fromItemId: itemIds.first,
      toItemId: itemIds.last,
      direction: draft.direction,
      label: draft.label.isEmpty ? null : draft.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final colors = WhiteboardCanvasTokens.of(context);
    return Scaffold(
      key: const Key('wb_fullscreen_canvas_shell'),
      backgroundColor: colors.canvas,
      body: CallbackShortcuts(
        bindings: _buildShortcuts(),
        child: Focus(
          autofocus: true,
          child: SizedBox.expand(
            key: const Key('wb_fullscreen_canvas'),
            child: Stack(
              children: [
                Positioned.fill(
                  child: WhiteboardCanvasArea(
                    viewModel: vm,
                    onOpenCard: widget.onOpenCard,
                    onEditCard: _openCompactEditor,
                    editingItemId: _editingItemId,
                    editSurfaceBuilder: (context, card) {
                      final request = BoardItemEditRequest(
                        cardId: card.cardId,
                        isReadonly: vm.isReadonly,
                        onSaved: vm.upsertCardContent,
                        onClose: () => setState(() => _editingItemId = null),
                        onExpand: (updated) {
                          setState(() => _editingItemId = null);
                          widget.onOpenCard?.call(updated);
                        },
                      );
                      final injected = widget.cardEditSurfaceBuilder;
                      if (injected != null) return injected(context, request);
                      final repository = widget.cardRepository;
                      if (repository == null) return const SizedBox.shrink();
                      return CompactCardEditor(
                        cardId: request.cardId,
                        repository: repository,
                        isReadonly: request.isReadonly,
                        embedded: true,
                        onSaved: request.onSaved,
                        onClose: request.onClose,
                        onExpand: request.onExpand,
                      );
                    },
                    onCreateCardAt: (canvasPoint, screenPoint) => unawaited(
                      _createNoteAt(canvasPoint, screenPoint),
                    ),
                  ),
                ),
                if (!_navigationVisible)
                  _CanvasChromeLauncher(
                    onTap: () => setState(() => _navigationVisible = true),
                  )
                else
                  _CanvasNavigationGroup(
                    boardName: vm.boardState.board.name,
                    onExit: widget.onExit,
                    onDismiss: _dismissNavigation,
                    toolsVisible: _toolsVisible,
                    onToggleTools: () =>
                        setState(() => _toolsVisible = !_toolsVisible),
                    cardLibraryVisible: _showCardLibrary,
                    onToggleCardLibrary: _toggleCardLibrary,
                  ),
                if (_toolsVisible)
                  _FloatingActionTools(
                    viewModel: vm,
                    cardLibraryVisible: _showCardLibrary,
                    onToggleCardLibrary: _toggleCardLibrary,
                    onCreateGroup: _createGroupFromSelection,
                    onCreateEdge: _connectSelectedCards,
                    onClose: () => setState(() => _toolsVisible = false),
                  ),
                if (_toolsVisible) _FloatingViewTools(viewModel: vm),
                if (_showCardLibrary)
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
                if (!vm.isReadonly && vm.selectedEdge != null)
                  _EdgeQuickEditor(
                    edge: vm.selectedEdge!,
                    onSave: (direction, label) async {
                      final edgeId = vm.selectedEdge!.edgeId;
                      return _persistEdgeMutation(
                        () => vm.updateEdge(
                          edgeId: edgeId,
                          direction: direction,
                          label: label,
                        ),
                      );
                    },
                    onDelete: () async {
                      final edgeId = vm.selectedEdge!.edgeId;
                      final ok = await _persistEdgeMutation(() {
                        vm.removeEdge(edgeId);
                        return vm.exportForSave().edges.every(
                              (edge) => edge.edgeId != edgeId,
                            );
                      });
                      if (!ok && context.mounted) {
                        vm.handleIntent(SelectEdgeIntent(edgeId: edgeId));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('连线没有删除成功')),
                        );
                      }
                      return ok;
                    },
                    onClose: () => vm.handleIntent(
                      const ClearEdgeSelectionIntent(),
                    ),
                  ),
                if (_pendingCompensationCardId != null)
                  Positioned(
                    key: const ValueKey('wb_pending_card_compensation'),
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: Material(
                      color: colors.panelSurface,
                      elevation: 8,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '白板创建已回滚，但临时卡片清理失败：'
                                '$_pendingCompensationError',
                              ),
                            ),
                            TextButton(
                              key: const ValueKey(
                                'wb_retry_card_compensation',
                              ),
                              onPressed: _retryPendingCompensation,
                              child: const Text('重试清理'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeQuickEditor extends StatefulWidget {
  const _EdgeQuickEditor({
    required this.edge,
    required this.onSave,
    required this.onDelete,
    required this.onClose,
  });

  final BoardEdge edge;
  final Future<bool> Function(EdgeDirection direction, String? label) onSave;
  final Future<bool> Function() onDelete;
  final VoidCallback onClose;

  @override
  State<_EdgeQuickEditor> createState() => _EdgeQuickEditorState();
}

class _EdgeQuickEditorState extends State<_EdgeQuickEditor> {
  late TextEditingController _label;
  late EdgeDirection _direction;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _syncFromEdge();
  }

  @override
  void didUpdateWidget(covariant _EdgeQuickEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edge.edgeId != widget.edge.edgeId) {
      _label.dispose();
      _syncFromEdge();
    }
  }

  void _syncFromEdge() {
    _label = TextEditingController(text: widget.edge.label ?? '');
    _direction = widget.edge.direction;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await widget.onSave(_direction, _label.text);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '连线已保存' : '连线没有保存成功')),
    );
  }

  Future<void> _delete() async {
    if (_saving) return;
    setState(() => _saving = true);
    final ok = await widget.onDelete();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '连线已删除' : '连线没有删除成功')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
    return Positioned(
      key: const ValueKey('wb_edge_quick_editor'),
      left: 0,
      right: 0,
      bottom: 14,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: _FloatingSurface(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<EdgeDirection>(
                key: const ValueKey('wb_edge_quick_direction'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: EdgeDirection.undirected,
                    icon: Icon(Icons.horizontal_rule, size: 16),
                    tooltip: '无向连线',
                  ),
                  ButtonSegment(
                    value: EdgeDirection.directed,
                    icon: Icon(Icons.arrow_forward_rounded, size: 16),
                    tooltip: '有向连线',
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: _saving
                    ? null
                    : (selection) =>
                        setState(() => _direction = selection.first),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 190,
                height: 36,
                child: TextField(
                  key: const ValueKey('wb_edge_quick_label'),
                  controller: _label,
                  enabled: !_saving,
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '连线标签（可选）',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: colors.divider),
                    ),
                  ),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: const ValueKey('wb_edge_quick_save'),
                tooltip: '保存连线',
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
              ),
              IconButton(
                key: const ValueKey('wb_edge_quick_delete'),
                tooltip: '删除连线',
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded, size: 18),
              ),
              IconButton(
                tooltip: '关闭连线编辑',
                onPressed: _saving ? null : widget.onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
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
  final void Function(String itemId, CardContract card)? onEditCard;
  final String? editingItemId;
  final Widget Function(BuildContext context, CardContract card)?
      editSurfaceBuilder;
  final void Function(Offset canvasPoint, Offset screenPoint)? onCreateCardAt;

  const WhiteboardCanvasArea({
    super.key,
    required this.viewModel,
    this.onOpenCard,
    this.onEditCard,
    this.editingItemId,
    this.editSurfaceBuilder,
    this.onCreateCardAt,
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
  _EdgeCreateState? _edgeCreateState;

  // LOD tier per item (transient render state, per Huabu §5)
  final Map<String, LodTier> _lodTiers = {};

  // Last computed transform, for drop-position math outside build().
  CanvasTransform? _lastTransform;
  final GlobalKey _canvasAreaKey = GlobalKey();
  String? _lastClickedItemId;
  DateTime? _lastClickAt;
  DateTime? _lastBlankClickAt;
  Offset? _lastBlankClickPosition;
  Offset? _primaryDownPosition;
  bool _primaryMoved = false;
  String? _hoveredItemId;
  Timer? _hoverExitTimer;

  Offset? _secondaryDownPosition;
  Offset? _secondaryLastPosition;
  bool _secondaryDragged = false;

  @override
  void dispose() {
    _hoverExitTimer?.cancel();
    super.dispose();
  }

  void _handleCardClick(CanvasCardNode node) {
    _clearPendingBlankClick();
    final now = DateTime.now();
    final keyboard = HardwareKeyboard.instance;
    final additiveSelection = keyboard.isControlPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed;
    if (additiveSelection) {
      widget.viewModel.handleIntent(
        ToggleItemSelectionIntent(itemId: node.itemId),
      );
      _lastClickedItemId = null;
      _lastClickAt = null;
      return;
    }
    final isDoubleClick = _lastClickedItemId == node.itemId &&
        _lastClickAt != null &&
        now.difference(_lastClickAt!) <= _doubleClickWindow;
    widget.viewModel.handleIntent(SelectItemIntent(itemId: node.itemId));
    if (isDoubleClick && node.card != null) {
      _lastClickedItemId = null;
      _lastClickAt = null;
      final transform = _lastTransform;
      if (!widget.viewModel.isReadonly &&
          transform != null &&
          widget.onEditCard != null &&
          _supportsCompactEdit(node.card!.cardKind)) {
        widget.onEditCard!(node.itemId, node.card!);
      } else {
        widget.onOpenCard?.call(node.card!);
      }
      return;
    }
    _lastClickedItemId = node.itemId;
    _lastClickAt = now;
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final boardState = vm.boardState;
    final colors = WhiteboardCanvasTokens.of(context);

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
          onWillAcceptWithDetails: (_) => !vm.isReadonly,
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
                  _primaryDownPosition = event.localPosition;
                  _primaryMoved = false;
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
                  // A short right-click opens a context menu. Crossing the
                  // movement threshold turns the same gesture into panning.
                  _secondaryDownPosition = event.localPosition;
                  _secondaryLastPosition = event.localPosition;
                  _secondaryDragged = false;
                }
              },
              onPointerMove: (event) {
                if (_isMarqueeing && _marqueeStart != null) {
                  if (_primaryDownPosition != null &&
                      (event.localPosition - _primaryDownPosition!).distance >
                          4) {
                    _primaryMoved = true;
                  }
                  setState(() {
                    _marqueeCurrent = event.localPosition;
                  });
                } else if (_secondaryDownPosition != null) {
                  if (!_secondaryDragged &&
                      (event.localPosition - _secondaryDownPosition!).distance >
                          5) {
                    _secondaryDragged = true;
                    _isPanning = true;
                  }
                  if (_secondaryDragged) {
                    final last = _secondaryLastPosition ?? event.localPosition;
                    final delta = event.localPosition - last;
                    vm.panViewport(delta.dx, delta.dy);
                    _secondaryLastPosition = event.localPosition;
                  }
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
                if (_isMarqueeing && !_primaryMoved) {
                  _handleBlankClick(event.localPosition, transform);
                }
                if (_secondaryDownPosition != null && !_secondaryDragged) {
                  unawaited(
                    _showContextMenu(
                      localPosition: event.localPosition,
                      globalPosition: event.position,
                      transform: transform,
                    ),
                  );
                }
                setState(() {
                  _isMarqueeing = false;
                  _marqueeStart = null;
                  _marqueeCurrent = null;
                  _isPanning = false;
                });
                _primaryDownPosition = null;
                _primaryMoved = false;
                _secondaryDownPosition = null;
                _secondaryLastPosition = null;
                _secondaryDragged = false;
              },
              onPointerCancel: (_) {
                setState(() {
                  _isMarqueeing = false;
                  _marqueeStart = null;
                  _marqueeCurrent = null;
                  _isPanning = false;
                });
                _primaryDownPosition = null;
                _secondaryDownPosition = null;
                _secondaryLastPosition = null;
                _secondaryDragged = false;
              },
              child: CustomPaint(
                size: size,
                painter: _CanvasPainter(
                  boardState: boardState,
                  transform: transform,
                  colors: colors,
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
                  createPreview: _edgeCreateState != null
                      ? (
                          from: _edgeCreateState!.startPoint,
                          to: _edgeCreateState!.currentPoint,
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
      if ((selection.isSelected(item.itemId) ||
          _hoveredItemId == item.itemId)) {
        final center = screenRect.center;
        final rad = item.rotation * math.pi / 180;
        final sin = math.sin(rad);
        final cos = math.cos(rad);
        Offset rotate(Offset local) =>
            center +
            Offset(
              local.dx * cos - local.dy * sin,
              local.dx * sin + local.dy * cos,
            );
        final connectionPoints = [
          rotate(Offset(0, -screenRect.height / 2)),
          rotate(Offset(screenRect.width / 2, 0)),
          rotate(Offset(0, screenRect.height / 2)),
          rotate(Offset(-screenRect.width / 2, 0)),
        ];
        if (connectionPoints.any(
          (point) => Rect.fromCenter(
            center: point,
            width: 20,
            height: 20,
          ).contains(screenPos),
        )) {
          return true;
        }
      }
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
      final connection = CanvasEdgeGeometry.resolve(
        edge: edgeNode.edge,
        from: from,
        to: to,
      );
      final a = transform.canvasToScreen(connection.from);
      final b = transform.canvasToScreen(connection.to);
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

  void _handleBlankClick(Offset screenPosition, CanvasTransform transform) {
    final now = DateTime.now();
    final isDoubleClick = _lastBlankClickAt != null &&
        _lastBlankClickPosition != null &&
        now.difference(_lastBlankClickAt!) <= _doubleClickWindow &&
        (screenPosition - _lastBlankClickPosition!).distance <= 8;
    widget.viewModel.handleIntent(const ClearEdgeSelectionIntent());
    if (isDoubleClick) {
      _lastBlankClickAt = null;
      _lastBlankClickPosition = null;
      if (!widget.viewModel.isReadonly) {
        final canvasPoint = transform.screenToCanvas(screenPosition);
        widget.onCreateCardAt?.call(canvasPoint, screenPosition);
      }
      return;
    }
    _lastBlankClickAt = now;
    _lastBlankClickPosition = screenPosition;
  }

  void _clearPendingBlankClick() {
    _lastBlankClickAt = null;
    _lastBlankClickPosition = null;
  }

  Future<void> _showContextMenu({
    required Offset localPosition,
    required Offset globalPosition,
    required CanvasTransform transform,
  }) async {
    if (!mounted) return;
    final canvasPoint = transform.screenToCanvas(localPosition);
    final node = _itemAtCanvas(math.Point(canvasPoint.dx, canvasPoint.dy));
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
      Offset.zero & overlay.size,
    );
    if (node != null && node.card != null) {
      final card = node.card!;
      final readonly = widget.viewModel.isReadonly;
      final compactEdit = !readonly && _supportsCompactEdit(card.cardKind);
      widget.viewModel.handleIntent(SelectItemIntent(itemId: node.itemId));
      final action = await showMenu<_CardMenuAction>(
        context: context,
        position: position,
        items: [
          if (compactEdit)
            const PopupMenuItem(
              value: _CardMenuAction.quickEdit,
              child: Text('快捷编辑'),
            ),
          PopupMenuItem(
            value: _CardMenuAction.open,
            child: Text(compactEdit ? '展开查看' : '打开来源'),
          ),
          if (!readonly) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _CardMenuAction.front,
              child: Text('置于顶层'),
            ),
            const PopupMenuItem(
              value: _CardMenuAction.remove,
              child: Text('从白板移除'),
            ),
          ],
        ],
      );
      if (!mounted || action == null) return;
      switch (action) {
        case _CardMenuAction.quickEdit:
          if (compactEdit) {
            widget.onEditCard?.call(node.itemId, card);
          } else {
            widget.onOpenCard?.call(card);
          }
        case _CardMenuAction.open:
          widget.onOpenCard?.call(card);
        case _CardMenuAction.front:
          widget.viewModel.bringSelectedItemToFront();
        case _CardMenuAction.remove:
          widget.viewModel.removeSelectedItems();
      }
      return;
    }

    final readonly = widget.viewModel.isReadonly;
    final action = await showMenu<_CanvasMenuAction>(
      context: context,
      position: position,
      items: [
        if (!readonly)
          const PopupMenuItem(
            value: _CanvasMenuAction.newCard,
            child: Text('新建文字卡片'),
          ),
        const PopupMenuItem(
          value: _CanvasMenuAction.resetView,
          child: Text('重置视图'),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _CanvasMenuAction.newCard:
        widget.onCreateCardAt?.call(canvasPoint, localPosition);
      case _CanvasMenuAction.resetView:
        widget.viewModel.resetViewport();
    }
  }

  // ── Card-library drag & drop ────────────────────────────────────────

  void _handleCardDrop(WhiteboardCardDragData data, Offset globalPosition) {
    final vm = widget.viewModel;
    if (vm.isReadonly) return;
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
    _clearPendingBlankClick();
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

  void _onCardEnter(String itemId) {
    _hoverExitTimer?.cancel();
    if (_hoveredItemId == itemId) return;
    setState(() => _hoveredItemId = itemId);
  }

  void _onCardExit(String itemId) {
    _hoverExitTimer?.cancel();
    _hoverExitTimer = Timer(const Duration(milliseconds: 140), () {
      if (mounted && _hoveredItemId == itemId && _edgeCreateState == null) {
        setState(() => _hoveredItemId = null);
      }
    });
  }

  void _onConnectionHandleStart(
    String itemId,
    CanvasAnchorSide side,
    Offset startPoint,
  ) {
    if (widget.viewModel.isReadonly) return;
    _hoverExitTimer?.cancel();
    setState(() {
      _hoveredItemId = itemId;
      _edgeCreateState = _EdgeCreateState(
        fromItemId: itemId,
        fromSide: side,
        startPoint: startPoint,
        currentPoint: startPoint,
      );
    });
  }

  void _onConnectionHandleUpdate(Offset globalPointerPos) {
    final state = _edgeCreateState;
    if (state == null) return;
    final box = _canvasAreaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPointerPos = box.globalToLocal(globalPointerPos);
    setState(() {
      _edgeCreateState = _EdgeCreateState(
        fromItemId: state.fromItemId,
        fromSide: state.fromSide,
        startPoint: state.startPoint,
        currentPoint: localPointerPos,
      );
    });
  }

  void _onConnectionHandleEnd() {
    final state = _edgeCreateState;
    if (state == null) return;
    final transform = _lastTransform;
    if (transform != null) {
      final canvasPoint = transform.screenToCanvas(state.currentPoint);
      final target = _itemAtCanvas(math.Point(canvasPoint.dx, canvasPoint.dy));
      if (target != null && target.itemId != state.fromItemId) {
        final targetSide = CanvasEdgeGeometry.nearestSide(
          target.item,
          canvasPoint,
        );
        widget.viewModel.createEdge(
          fromItemId: state.fromItemId,
          toItemId: target.itemId,
          style: {
            CanvasEdgeGeometry.fromAnchorStyleKey: state.fromSide.name,
            CanvasEdgeGeometry.toAnchorStyleKey: targetSide.name,
          },
        );
      }
    }
    setState(() => _edgeCreateState = null);
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
        final targetSide = CanvasEdgeGeometry.nearestSide(
          target.item,
          canvasPoint,
        );
        final ok = vm.handleIntent(
          RetargetEdgeIntent(
            edgeId: state.edgeId,
            fromItemId: state.isFrom ? target.itemId : null,
            toItemId: state.isFrom ? null : target.itemId,
            stylePatch: {
              state.isFrom
                  ? CanvasEdgeGeometry.fromAnchorStyleKey
                  : CanvasEdgeGeometry.toAnchorStyleKey: targetSide.name,
            },
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
    final colors = WhiteboardCanvasTokens.of(context);
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
            onToggle: () {
              _clearPendingBlankClick();
              vm.handleIntent(
                ToggleGroupCollapsedIntent(groupId: groupNode.groupId),
              );
            },
            onRemove:
                vm.isReadonly ? null : () => vm.removeGroup(groupNode.groupId),
          ),
        // Cards (culled to viewport, LOD-tiered)
        for (final node in visibleNodes)
          _CardWidget(
            node: node,
            transform: transform,
            isSelected: vm.selection.isSelected(node.itemId),
            isReadonly: vm.isReadonly,
            lodTier: _lodTiers[node.itemId] ?? LodTier.full,
            editSurface: widget.editingItemId == node.itemId &&
                    node.card != null &&
                    widget.editSurfaceBuilder != null
                ? widget.editSurfaceBuilder!(context, node.card!)
                : null,
            onTap: () => _handleCardClick(node),
            onEnter: () => _onCardEnter(node.itemId),
            onExit: () => _onCardExit(node.itemId),
            onDragStart: (position) => _onDragStart(node.itemId, position),
            onDragUpdate: (position) => _onDragUpdate(node.itemId, position),
            onDragEnd: _onDragEnd,
          ),
        // Selection chrome: rotate + resize handles (siblings of the card
        // so they stay hit-testable outside the card bounds; positions
        // follow the card's rotation).
        if (!vm.isReadonly)
          for (final node in visibleNodes)
            if (vm.selection.isSelected(node.itemId) &&
                widget.editingItemId != node.itemId)
              ..._buildSelectionHandles(node, transform),
        if (!vm.isReadonly)
          for (final node in visibleNodes)
            if ((vm.selection.isSelected(node.itemId) ||
                    _hoveredItemId == node.itemId) &&
                widget.editingItemId != node.itemId)
              ..._buildConnectionHandles(node, transform),
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
                  color: colors.selectionBox,
                  border: Border.all(
                    color: colors.selectionBoxBorder,
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
    final connection = CanvasEdgeGeometry.resolve(
      edge: edgeNode.edge,
      from: from,
      to: to,
    );
    final fromScreen = transform.canvasToScreen(connection.from);
    final toScreen = transform.canvasToScreen(connection.to);
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

  List<Widget> _buildConnectionHandles(
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
    Offset rotate(Offset local) =>
        center +
        Offset(
          local.dx * cos - local.dy * sin,
          local.dx * sin + local.dy * cos,
        );
    final points = <String, Offset>{
      'top': rotate(Offset(0, -screenRect.height / 2)),
      'right': rotate(Offset(screenRect.width / 2, 0)),
      'bottom': rotate(Offset(0, screenRect.height / 2)),
      'left': rotate(Offset(-screenRect.width / 2, 0)),
    };
    return [
      for (final entry in points.entries)
        Positioned(
          key: Key('wb_connect_${item.itemId}_${entry.key}'),
          left: entry.value.dx - 7,
          top: entry.value.dy - 7,
          child: _ConnectionHandle(
            onEnter: () => _onCardEnter(item.itemId),
            onExit: () => _onCardExit(item.itemId),
            onStart: () => _onConnectionHandleStart(
              item.itemId,
              CanvasAnchorSide.values.firstWhere(
                (side) => side.name == entry.key,
              ),
              entry.value,
            ),
            onUpdate: _onConnectionHandleUpdate,
            onEnd: _onConnectionHandleEnd,
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

enum _CardMenuAction { quickEdit, open, front, remove }

enum _CanvasMenuAction { newCard, resetView }

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

class _EdgeCreateState {
  const _EdgeCreateState({
    required this.fromItemId,
    required this.fromSide,
    required this.startPoint,
    required this.currentPoint,
  });

  final String fromItemId;
  final CanvasAnchorSide fromSide;
  final Offset startPoint;
  final Offset currentPoint;
}

/// Custom painter for edges and grid.
class _CanvasPainter extends CustomPainter {
  final CanvasBoardState boardState;
  final CanvasTransform transform;
  final WhiteboardCanvasColors colors;
  final Set<String> selection;
  final Rect? marqueeRect;
  final String? selectedEdgeId;
  final ({Offset from, Offset to})? retargetPreview;
  final ({Offset from, Offset to})? createPreview;
  final Set<String> hiddenItemIds;

  _CanvasPainter({
    required this.boardState,
    required this.transform,
    required this.colors,
    required this.selection,
    this.marqueeRect,
    this.selectedEdgeId,
    this.retargetPreview,
    this.createPreview,
    this.hiddenItemIds = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    _drawEdges(canvas);
    _drawRetargetPreview(canvas);
    _drawCreatePreview(canvas);
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridSize = 22.0 * transform.viewport.zoom;
    if (gridSize < 8) return;

    final offsetX = transform.canvasToScreen(Offset.zero).dx % gridSize;
    final offsetY = transform.canvasToScreen(Offset.zero).dy % gridSize;

    final paint = Paint()
      ..color = colors.gridDot
      ..strokeWidth = (1.15 * transform.viewport.zoom).clamp(0.65, 1.2)
      ..strokeCap = StrokeCap.round;

    final points = <Offset>[];
    for (double x = offsetX; x < size.width; x += gridSize) {
      for (double y = offsetY; y < size.height; y += gridSize) {
        points.add(Offset(x, y));
      }
    }
    canvas.drawPoints(ui.PointMode.points, points, paint);
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
      final connection = CanvasEdgeGeometry.resolve(
        edge: edgeNode.edge,
        from: from,
        to: to,
      );
      final fromScreen = transform.canvasToScreen(connection.from);
      final toScreen = transform.canvasToScreen(connection.to);

      final paint = Paint()
        ..color = isSelected ? colors.edgeSelected : colors.edge
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
            style: richTextBodyTextStyle(
              color: colors.edgeLabel,
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
      ..color = colors.edgeSelected
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
        ..color = colors.edgeSelected
        ..style = PaintingStyle.fill,
    );
  }

  void _drawCreatePreview(Canvas canvas) {
    final preview = createPreview;
    if (preview == null) return;
    final paint = Paint()
      ..color = colors.edgeSelected
      ..strokeWidth = WhiteboardCanvasTokens.edgeWidthSelected
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(preview.from, preview.to, paint);
    canvas.drawCircle(
      preview.to,
      4,
      Paint()
        ..color = colors.edgeSelected
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
        oldDelegate.createPreview != createPreview ||
        oldDelegate.colors != colors ||
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
  final Widget? editSurface;
  final VoidCallback onTap;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final void Function(Offset position) onDragStart;
  final void Function(Offset position) onDragUpdate;
  final VoidCallback onDragEnd;

  const _CardWidget({
    required this.node,
    required this.transform,
    required this.isSelected,
    required this.isReadonly,
    required this.lodTier,
    this.editSurface,
    required this.onTap,
    required this.onEnter,
    required this.onExit,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final item = node.item;
    final colors = WhiteboardCanvasTokens.of(context);
    final screenRect = transform.canvasToScreenRect(
      Rect.fromLTWH(item.x, item.y, item.width, item.height),
    );
    return Positioned(
      key: Key('wb_card_${item.itemId}'),
      left: screenRect.left,
      top: screenRect.top,
      width: screenRect.width,
      height: screenRect.height,
      child: MouseRegion(
        onEnter: (_) => onEnter(),
        onExit: (_) => onExit(),
        child: editSurface != null
            ? Transform.rotate(
                angle: item.rotation * math.pi / 180,
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.cardSurface,
                    borderRadius: BorderRadius.circular(
                      WhiteboardCanvasTokens.cardRadius,
                    ),
                    border: Border.all(
                      color: isSelected
                          ? colors.cardBorderSelected
                          : colors.cardBorder,
                      width: isSelected
                          ? WhiteboardCanvasTokens.cardBorderWidthSelected
                          : WhiteboardCanvasTokens.cardBorderWidth,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: colors.selectionFocus,
                              blurRadius: 0,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      WhiteboardCanvasTokens.cardRadius,
                    ),
                    child: KeyedSubtree(
                      key: Key('wb_card_edit_surface_${item.itemId}'),
                      child: editSurface!,
                    ),
                  ),
                ),
              )
            : GestureDetector(
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
                    key: Key(
                      'wb_card_content_${item.itemId}_${lodTier.name}',
                    ),
                    node: node,
                    isSelected: isSelected,
                    lodTier: lodTier,
                  ),
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
    final colors = WhiteboardCanvasTokens.of(context);

    if (lodTier == LodTier.minimal) {
      return Container(
        decoration: BoxDecoration(
          color: isOrphaned ? colors.orphanedSurface : colors.cardSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.cardRadius,
          ),
          border: Border.all(
            color: isOrphaned
                ? colors.orphanedBorder
                : isSelected
                    ? colors.cardBorderSelected
                    : colors.cardBorder,
            width: isSelected
                ? WhiteboardCanvasTokens.cardBorderWidthSelected
                : WhiteboardCanvasTokens.cardBorderWidth,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            if (isOrphaned) ...[
              Icon(
                Icons.broken_image_outlined,
                color: colors.orphanedBorder,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '失效引用',
                  style: whiteboardUiTextStyle(
                    color: colors.orphanedBorder,
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
                  style: richTextBodyTextStyle(
                    color: colors.textPrimary,
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
        color: isOrphaned ? colors.orphanedSurface : colors.cardSurface,
        borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.cardRadius),
        border: Border.all(
          color: isOrphaned
              ? colors.orphanedBorder
              : isSelected
                  ? colors.cardBorderSelected
                  : colors.cardBorder,
          width: isSelected
              ? WhiteboardCanvasTokens.cardBorderWidthSelected
              : WhiteboardCanvasTokens.cardBorderWidth,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: colors.selectionFocus,
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ]
            : null,
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
              style: richTextBodyTextStyle(
                color: colors.textPrimary,
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
                style: richTextBodyTextStyle(
                  color: colors.textSecondary,
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
                        color: colors.cardSurface,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: colors.divider,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: whiteboardUiTextStyle(
                          color: colors.textFaint,
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
    final colors = WhiteboardCanvasTokens.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.broken_image_outlined,
            color: colors.orphanedBorder,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            '失效卡片引用',
            style: whiteboardUiTextStyle(
              color: colors.orphanedBorder,
              fontSize: WhiteboardCanvasTokens.metaSize,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            cardId,
            style: richTextCodeTextStyle(
              color: colors.textFaint,
              fontSize: WhiteboardCanvasTokens.statusSize,
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
  final VoidCallback? onRemove;

  const _GroupWidget({
    required this.groupNode,
    required this.itemsByItemId,
    required this.transform,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
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
            color: colors.groupRect,
            borderRadius: BorderRadius.circular(
              WhiteboardCanvasTokens.groupRadius,
            ),
            border: Border.all(
              color: collapsed ? colors.actionSecondary : colors.groupBorder,
              width: collapsed ? 1.5 : 1,
            ),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              margin: const EdgeInsets.only(top: 6, left: 12),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.canvas,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    collapsed ? Icons.unfold_more : Icons.unfold_less,
                    size: 14,
                    color:
                        collapsed ? colors.actionSecondary : colors.groupLabel,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    groupNode.group.name.isNotEmpty
                        ? groupNode.group.name
                        : '未命名分组',
                    style: TextStyle(
                      color: colors.groupLabel,
                      fontSize: WhiteboardCanvasTokens.metaSize,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (collapsed) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${groupNode.members.length} 张卡片',
                      style: TextStyle(
                        color: colors.actionSecondary,
                        fontSize: WhiteboardCanvasTokens.statusSize,
                      ),
                    ),
                  ],
                  if (onRemove != null) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: '解散分组',
                      child: InkWell(
                        key: Key('wb_ungroup_${groupNode.groupId}'),
                        onTap: onRemove,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Icon(
                            Icons.folder_off_outlined,
                            size: 14,
                            color: colors.textFaint,
                          ),
                        ),
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
    final colors = WhiteboardCanvasTokens.of(context);
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
            color: colors.canvas,
            border: Border.all(
              color: colors.cardBorderSelected,
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
    final colors = WhiteboardCanvasTokens.of(context);
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
            color: colors.canvas,
            border: Border.all(
              color: colors.cardBorderSelected,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.rotate_right,
            size: 12,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Small, transient anchor used to create a new visual BoardEdge directly.
class _ConnectionHandle extends StatelessWidget {
  const _ConnectionHandle({
    required this.onEnter,
    required this.onExit,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onStart(),
        onPanUpdate: (details) => onUpdate(details.globalPosition),
        onPanEnd: (_) => onEnd(),
        onPanCancel: onEnd,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: colors.canvas,
            shape: BoxShape.circle,
            border: Border.all(color: colors.action, width: 1.5),
          ),
          child: Center(
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: colors.action,
                shape: BoxShape.circle,
              ),
            ),
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
    final colors = WhiteboardCanvasTokens.of(context);
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
              color: colors.panelSurface,
              border: Border.all(
                color: colors.edgeSelected,
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

/// A single compact affordance remains when every optional canvas surface has
/// retreated. It is intentionally not a bar: the board still occupies the full
/// window and the launcher never reserves layout space.
class _CanvasChromeLauncher extends StatelessWidget {
  const _CanvasChromeLauncher({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: const Key('wb_canvas_chrome_launcher'),
      top: 12,
      left: 12,
      child: _FloatingSurface(
        padding: const EdgeInsets.all(4),
        child: _FloatingButton(
          icon: Icons.space_dashboard_outlined,
          tooltip: '打开画布控件',
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Navigation and surface switches. Closing it also retreats every surface it
/// owns so the canvas returns to a single launcher.
class _CanvasNavigationGroup extends StatelessWidget {
  const _CanvasNavigationGroup({
    required this.boardName,
    required this.onExit,
    required this.onDismiss,
    required this.toolsVisible,
    required this.onToggleTools,
    required this.cardLibraryVisible,
    required this.onToggleCardLibrary,
  });

  final String boardName;
  final VoidCallback? onExit;
  final VoidCallback onDismiss;
  final bool toolsVisible;
  final VoidCallback onToggleTools;
  final bool cardLibraryVisible;
  final VoidCallback onToggleCardLibrary;

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
    return Positioned(
      key: const Key('wb_navigation_group'),
      top: 12,
      left: 12,
      child: _FloatingSurface(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FloatingButton(
              icon: Icons.arrow_back,
              tooltip: '退出白板 (Esc)',
              onTap: onExit,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                boardName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _FloatingButton(
              icon: cardLibraryVisible
                  ? Icons.collections_bookmark_outlined
                  : Icons.grid_view_outlined,
              tooltip: cardLibraryVisible ? '关闭卡片库' : '卡片库',
              onTap: onToggleCardLibrary,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: toolsVisible ? Icons.build : Icons.build_outlined,
              tooltip: toolsVisible ? '关闭画布工具' : '画布工具',
              onTap: onToggleTools,
            ),
            const SizedBox(width: 4),
            _FloatingButton(
              icon: Icons.close,
              tooltip: '收起画布控件',
              onTap: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit actions appear only when explicitly requested from the navigation
/// group. Keyboard shortcuts remain active while this surface is absent.
class _FloatingActionTools extends StatelessWidget {
  const _FloatingActionTools({
    required this.viewModel,
    required this.cardLibraryVisible,
    required this.onToggleCardLibrary,
    required this.onCreateGroup,
    required this.onCreateEdge,
    required this.onClose,
  });

  final WhiteboardCanvasViewModel viewModel;
  final bool cardLibraryVisible;
  final VoidCallback onToggleCardLibrary;
  final VoidCallback onCreateGroup;
  final VoidCallback onCreateEdge;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final vm = viewModel;
    return Positioned(
      key: const Key('wb_action_tools'),
      top: 64,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: _FloatingSurface(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingLabeledButton(
                key: const Key('wb_open_card_library_tool'),
                icon: Icons.add_card_outlined,
                label: cardLibraryVisible ? '收起卡片库' : '添加卡片',
                tooltip: cardLibraryVisible ? '关闭卡片库' : '从卡片库放入白板',
                onTap: onToggleCardLibrary,
              ),
              const SizedBox(width: 6),
              _FloatingLabeledButton(
                key: const Key('wb_create_group_tool'),
                icon: Icons.create_new_folder_outlined,
                label: '建组',
                tooltip: vm.selection.length >= 2
                    ? '将选中卡片建立分组'
                    : '先框选或 Shift+点击至少两张卡片',
                isEnabled: vm.selection.length >= 2 && !vm.isReadonly,
                onTap: vm.selection.length >= 2 && !vm.isReadonly
                    ? onCreateGroup
                    : null,
              ),
              const SizedBox(width: 4),
              _FloatingButton(
                key: const Key('wb_create_edge_tool'),
                icon: Icons.polyline_outlined,
                tooltip: vm.selection.length == 2
                    ? '备用：连接选中的两张卡片'
                    : '拖动卡片边缘连接点可直接连线',
                isEnabled: vm.selection.length == 2 && !vm.isReadonly,
                onTap: vm.selection.length == 2 && !vm.isReadonly
                    ? onCreateEdge
                    : null,
              ),
              const SizedBox(width: 10),
              Text(
                _selectionHint(vm.selection.length),
                key: const Key('wb_selection_hint'),
                style: TextStyle(
                  color: WhiteboardCanvasTokens.of(context).textSecondary,
                  fontSize: WhiteboardCanvasTokens.statusSize,
                ),
              ),
              const SizedBox(width: 10),
              _FloatingButton(
                icon: Icons.undo,
                tooltip: '撤销 (Ctrl+Z)',
                isEnabled: vm.canUndo && !vm.isReadonly,
                onTap: vm.canUndo && !vm.isReadonly ? vm.undo : null,
              ),
              const SizedBox(width: 4),
              _FloatingButton(
                icon: Icons.redo,
                tooltip: '重做 (Ctrl+Y)',
                isEnabled: vm.canRedo && !vm.isReadonly,
                onTap: vm.canRedo && !vm.isReadonly ? vm.redo : null,
              ),
              const SizedBox(width: 4),
              _FloatingButton(
                icon: Icons.delete_outline,
                tooltip: '删除选中 (Del)',
                isEnabled:
                    (vm.selection.isNotEmpty || vm.selectedEdgeId != null) &&
                        !vm.isReadonly,
                onTap: (vm.selection.isNotEmpty || vm.selectedEdgeId != null) &&
                        !vm.isReadonly
                    ? () => vm.handleIntent(const DeleteSelectionIntent())
                    : null,
              ),
              const SizedBox(width: 4),
              _FloatingButton(
                icon: Icons.layers,
                tooltip: '置顶',
                isEnabled: vm.selection.isNotEmpty && !vm.isReadonly,
                onTap: vm.selection.isNotEmpty && !vm.isReadonly
                    ? vm.bringSelectedItemToFront
                    : null,
              ),
              const SizedBox(width: 4),
              _FloatingButton(
                icon: Icons.save_outlined,
                tooltip: '保存快照 (Ctrl+S)',
                isEnabled: !vm.isReadonly,
                onTap: !vm.isReadonly ? vm.onSaveRequested : null,
              ),
              const SizedBox(width: 4),
              _FloatingButton(
                icon: Icons.close,
                tooltip: '关闭画布工具',
                onTap: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _selectionHint(int count) {
  if (count == 0) return '双击空白新建 · 拖动卡片连接点连线';
  if (count == 1) return '拖动连接点连线 · Shift+点击多选';
  return '已选 $count 张';
}

/// View controls share the tool visibility lifecycle; there is no permanent
/// status bar along the bottom edge.
class _FloatingViewTools extends StatelessWidget {
  const _FloatingViewTools({required this.viewModel});

  final WhiteboardCanvasViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
    return Positioned(
      key: const Key('wb_view_tools'),
      bottom: 12,
      right: 12,
      child: _FloatingSurface(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FloatingButton(
              icon: Icons.zoom_out,
              tooltip: '缩小',
              onTap: () => viewModel.zoomViewport(0.8, const math.Point(0, 0)),
            ),
            const SizedBox(width: 4),
            Text(
              '${(viewModel.viewport.zoom * 100).round()}%',
              style: TextStyle(
                color: colors.textSecondary,
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
              onTap: viewModel.resetViewport,
            ),
            if (viewModel.selection.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                '已选 ${viewModel.selection.length} 项',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: WhiteboardCanvasTokens.metaSize,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FloatingSurface extends StatelessWidget {
  const _FloatingSurface({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panelSurface,
        borderRadius: BorderRadius.circular(WhiteboardCanvasTokens.groupRadius),
        border: Border.all(color: colors.divider, width: 0.5),
        boxShadow: [
          BoxShadow(
            color: colors.floatingShadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
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
    final colors = WhiteboardCanvasTokens.of(context);
    final alreadyPlaced =
        widget.viewModel.boardState.nodes.map((n) => n.cardId).toSet();

    return Positioned(
      key: const Key('wb_card_library_panel'),
      left: 12,
      top: 60,
      bottom: 60,
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: colors.panelSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.groupRadius,
          ),
          border: Border.all(
            color: colors.cardBorder,
            width: 0.5,
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  Text(
                    '卡片库',
                    style: TextStyle(
                      color: colors.textPrimary,
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
            Divider(height: 1, color: colors.divider),
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.textSecondary,
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
                                Text(
                                  '卡片库没有读出来',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: colors.textSecondary,
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
                          ? Center(
                              child: Text(
                                '没有可放入的卡片',
                                style: TextStyle(
                                  color: colors.textFaint,
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
                                      maxSimultaneousDrags:
                                          widget.viewModel.isReadonly ? 0 : 1,
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
    final colors = WhiteboardCanvasTokens.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: vm.isReadonly
            ? null
            : () {
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
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: WhiteboardCanvasTokens.metaSize,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPlaced)
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: colors.textFaint,
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(
                      Icons.space_dashboard_outlined,
                      size: 16,
                      color: colors.actionSecondary,
                    ),
                    tooltip: '放入白板…',
                    visualDensity: VisualDensity.compact,
                    onPressed: vm.isReadonly
                        ? null
                        : () => widget.onOpenBoardPicker(cardId, title),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                kindName,
                style: TextStyle(
                  color: colors.textFaint,
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
    final colors = WhiteboardCanvasTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.panelSurface,
          borderRadius: BorderRadius.circular(
            WhiteboardCanvasTokens.cardRadius,
          ),
          border: Border.all(
            color: colors.cardBorderSelected,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.floatingShadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
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
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: WhiteboardCanvasTokens.titleSize,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              kindName,
              style: TextStyle(
                color: colors.textFaint,
                fontSize: WhiteboardCanvasTokens.statusSize,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating action with a visible label for primary canvas operations.
class _FloatingLabeledButton extends StatelessWidget {
  const _FloatingLabeledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.onTap,
    this.isEnabled = true,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
    final foreground = isEnabled ? colors.textPrimary : colors.textFaint;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEnabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: WhiteboardCanvasTokens.metaSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
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
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = WhiteboardCanvasTokens.of(context);
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
              color: isEnabled ? colors.textPrimary : colors.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}
