/// BoardTargetPicker — lightweight target-board popover for "放入白板".
///
/// Per `docs/design/whiteboard-component-spec.md` §5.1: a card-library
/// "put into board" action must open a target picker offering recent boards,
/// full-board search and "new board". Choosing a target only creates a new
/// `BoardItem` — it never copies the Card. When invoked from inside a board
/// context the primary action stays "put into current board" (drag or row
/// tap); this picker is the explicit target-switching path.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/board.dart';

import '../whiteboard_canvas_tokens.dart';
import '../whiteboard_canvas_view_model.dart';

/// The picker itself. The parent is responsible for placing it in the
/// overlay stack and for the click-outside barrier.
class BoardTargetPicker extends StatefulWidget {
  final WhiteboardCanvasViewModel? viewModel;
  final List<Board>? availableBoards;
  final String? currentBoardId;
  final FutureOr<bool> Function(Board board)? onPlaceRequested;
  final FutureOr<Board?> Function(String name)? onCreateRequested;
  final String cardId;
  final String cardTitle;
  final VoidCallback onClose;

  /// Called after the card was placed into a board; carries the target
  /// board name for user feedback.
  final void Function(String boardName) onPlaced;

  const BoardTargetPicker({
    super.key,
    required this.viewModel,
    required this.cardId,
    required this.cardTitle,
    required this.onClose,
    required this.onPlaced,
  })  : availableBoards = null,
        currentBoardId = null,
        onPlaceRequested = null,
        onCreateRequested = null;

  /// Reuses the same picker from the independent card library, where there
  /// is no live canvas ViewModel. The caller remains responsible for
  /// persisting exactly one BoardItem through the production board store.
  const BoardTargetPicker.external({
    super.key,
    required this.availableBoards,
    required this.cardId,
    required this.cardTitle,
    required this.onClose,
    required this.onPlaced,
    required this.onPlaceRequested,
    required this.onCreateRequested,
    this.currentBoardId,
  }) : viewModel = null;

  @override
  State<BoardTargetPicker> createState() => _BoardTargetPickerState();
}

class _BoardTargetPickerState extends State<BoardTargetPicker> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _newName = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    super.dispose();
  }

  List<Board> get _boards {
    final boards = (widget.availableBoards ??
            widget.viewModel?.snapshot.boards ??
            const <Board>[])
        .toList()
      ..sort((a, b) {
        final at = a.updatedAt ?? a.createdAt;
        final bt = b.updatedAt ?? b.createdAt;
        return bt.compareTo(at);
      });
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return boards.take(5).toList();
    return boards.where((b) => b.name.toLowerCase().contains(query)).toList();
  }

  Future<void> _place(Board board) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? placedBoardName;
    try {
      final placed = await _requestPlace(board);
      if (!mounted) return;
      if (!placed) {
        setState(() => _error = '没有放入成功，请重试。');
        return;
      }
      placedBoardName = board.name;
    } catch (error) {
      if (mounted) setState(() => _error = '放入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && placedBoardName != null) {
      widget.onPlaced(placedBoardName);
    }
  }

  Future<bool> _requestPlace(Board board) async {
    final externalPlace = widget.onPlaceRequested;
    return externalPlace != null
        ? await externalPlace(board)
        : _placeWithViewModel(board);
  }

  bool _placeWithViewModel(Board board) {
    final vm = widget.viewModel!;
    final vp = vm.viewport;
    return vm.placeCardOnBoard(
          cardId: widget.cardId,
          boardId: board.boardId,
          x: vp.centerX - 130,
          y: vp.centerY - 100,
        ) !=
        null;
  }

  Future<void> _createAndPlace() async {
    final name = _newName.text.trim();
    if (name.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? placedBoardName;
    try {
      final externalCreate = widget.onCreateRequested;
      final board = externalCreate != null
          ? await externalCreate(name)
          : widget.viewModel!.createBoard(name);
      if (!mounted) return;
      if (board == null) {
        setState(() => _error = '白板没有创建成功，请重试。');
        return;
      }
      final placed = await _requestPlace(board);
      if (!mounted) return;
      if (!placed) {
        setState(() => _error = '没有放入成功，请重试。');
        return;
      }
      placedBoardName = board.name;
    } catch (error) {
      if (mounted) setState(() => _error = '创建失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && placedBoardName != null) {
      widget.onPlaced(placedBoardName);
    }
  }

  static String _date(DateTime? dt) {
    final t = dt?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final boards = _boards;
    final searching = _search.text.trim().isNotEmpty;
    final currentBoardId = widget.currentBoardId ?? widget.viewModel?.boardId;
    final colors = WhiteboardCanvasTokens.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: colors.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.cardBorder,
            width: 0.5,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  Text(
                    '放入白板',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: WhiteboardCanvasTokens.titleSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textFaint,
                        fontSize: WhiteboardCanvasTokens.statusSize,
                      ),
                    ),
                  ),
                  if (_busy)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.action,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: _busy ? null : widget.onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                key: const ValueKey('board-target-search'),
                controller: _search,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: WhiteboardCanvasTokens.metaSize,
                ),
                decoration: InputDecoration(
                  hintText: '搜索白板',
                  hintStyle: TextStyle(
                    color: colors.textFaint,
                    fontSize: WhiteboardCanvasTokens.metaSize,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 16,
                    color: colors.textFaint,
                  ),
                  filled: true,
                  fillColor: colors.canvas,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colors.divider,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colors.actionSecondary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  searching ? '全部白板' : '最近白板',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: WhiteboardCanvasTokens.statusSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: boards.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '没有匹配的白板，新建一个吧',
                          style: TextStyle(
                            color: colors.textFaint,
                            fontSize: WhiteboardCanvasTokens.metaSize,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: boards.length,
                        itemBuilder: (context, index) {
                          final board = boards[index];
                          final isCurrent = board.boardId == currentBoardId;
                          return InkWell(
                            onTap: _busy ? null : () => _place(board),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.space_dashboard_outlined,
                                    size: 16,
                                    color: colors.textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      board.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.textPrimary,
                                        fontSize:
                                            WhiteboardCanvasTokens.metaSize,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _date(board.updatedAt ?? board.createdAt),
                                    style: TextStyle(
                                      color: colors.textFaint,
                                      fontSize:
                                          WhiteboardCanvasTokens.statusSize,
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.actionSoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '当前',
                                        style: TextStyle(
                                          color: colors.action,
                                          fontSize:
                                              WhiteboardCanvasTokens.statusSize,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            Divider(
              height: 1,
              color: colors.divider,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: colors.orphanedBorder,
                      fontSize: WhiteboardCanvasTokens.statusSize,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: _creating
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('board-target-new-name'),
                            controller: _newName,
                            enabled: !_busy,
                            autofocus: true,
                            onSubmitted:
                                _busy ? null : (_) => _createAndPlace(),
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: WhiteboardCanvasTokens.metaSize,
                            ),
                            decoration: InputDecoration(
                              hintText: '新白板名称',
                              hintStyle: TextStyle(
                                color: colors.textFaint,
                                fontSize: WhiteboardCanvasTokens.metaSize,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: colors.canvas,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colors.divider,
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colors.actionSecondary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy ? null : _createAndPlace,
                          style: TextButton.styleFrom(
                            foregroundColor: colors.action,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            '创建并放入',
                            style: TextStyle(
                              fontSize: WhiteboardCanvasTokens.metaSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    )
                  : InkWell(
                      onTap:
                          _busy ? null : () => setState(() => _creating = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              size: 16,
                              color: colors.action,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '新建白板',
                              style: TextStyle(
                                color: colors.action,
                                fontSize: WhiteboardCanvasTokens.metaSize,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
