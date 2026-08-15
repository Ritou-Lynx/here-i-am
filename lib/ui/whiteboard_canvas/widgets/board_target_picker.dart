/// BoardTargetPicker — lightweight target-board popover for "放入白板".
///
/// Per `docs/design/whiteboard-component-spec.md` §5.1: a card-library
/// "put into board" action must open a target picker offering recent boards,
/// full-board search and "new board". Choosing a target only creates a new
/// `BoardItem` — it never copies the Card. When invoked from inside a board
/// context the primary action stays "put into current board" (drag or row
/// tap); this picker is the explicit target-switching path.
library;

import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/board.dart';

import '../whiteboard_canvas_tokens.dart';
import '../whiteboard_canvas_view_model.dart';

/// The picker itself. The parent is responsible for placing it in the
/// overlay stack and for the click-outside barrier.
class BoardTargetPicker extends StatefulWidget {
  final WhiteboardCanvasViewModel viewModel;
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
  });

  @override
  State<BoardTargetPicker> createState() => _BoardTargetPickerState();
}

class _BoardTargetPickerState extends State<BoardTargetPicker> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _newName = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _search.dispose();
    _newName.dispose();
    super.dispose();
  }

  List<Board> get _boards {
    final vm = widget.viewModel;
    final boards = vm.snapshot.boards.toList()
      ..sort((a, b) {
        final at = a.updatedAt ?? a.createdAt;
        final bt = b.updatedAt ?? b.createdAt;
        return bt.compareTo(at);
      });
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return boards;
    return boards
        .where((b) => b.name.toLowerCase().contains(query))
        .toList();
  }

  void _place(Board board) {
    final vm = widget.viewModel;
    final vp = vm.viewport;
    vm.placeCardOnBoard(
      cardId: widget.cardId,
      boardId: board.boardId,
      x: vp.centerX - 130,
      y: vp.centerY - 100,
    );
    widget.onPlaced(board.name);
  }

  void _createAndPlace() {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    final vm = widget.viewModel;
    final board = vm.createBoard(name);
    _place(board);
  }

  static String _date(DateTime? dt) {
    final t = dt?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final boards = _boards;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: WhiteboardCanvasTokens.panelSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: WhiteboardCanvasTokens.cardBorder,
            width: 0.5,
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
              child: Row(
                children: [
                  const Text(
                    '放入白板',
                    style: TextStyle(
                      color: WhiteboardCanvasTokens.textPrimary,
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
                      style: const TextStyle(
                        color: WhiteboardCanvasTokens.textFaint,
                        fontSize: WhiteboardCanvasTokens.statusSize,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: WhiteboardCanvasTokens.textSecondary,
                    ),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onClose,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(
                  color: WhiteboardCanvasTokens.textPrimary,
                  fontSize: WhiteboardCanvasTokens.metaSize,
                ),
                decoration: InputDecoration(
                  hintText: '搜索白板',
                  hintStyle: const TextStyle(
                    color: WhiteboardCanvasTokens.textFaint,
                    fontSize: WhiteboardCanvasTokens.metaSize,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: WhiteboardCanvasTokens.textFaint,
                  ),
                  filled: true,
                  fillColor: WhiteboardCanvasTokens.canvas,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: WhiteboardCanvasTokens.divider,
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: WhiteboardCanvasTokens.actionSecondary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: boards.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '没有匹配的白板，新建一个吧',
                          style: TextStyle(
                            color: WhiteboardCanvasTokens.textFaint,
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
                          final isCurrent =
                              board.boardId == vm.boardId;
                          return InkWell(
                            onTap: () => _place(board),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.space_dashboard_outlined,
                                    size: 16,
                                    color: WhiteboardCanvasTokens
                                        .textSecondary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      board.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color:
                                            WhiteboardCanvasTokens.textPrimary,
                                        fontSize: WhiteboardCanvasTokens.metaSize,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _date(board.updatedAt ?? board.createdAt),
                                    style: const TextStyle(
                                      color:
                                          WhiteboardCanvasTokens.textFaint,
                                      fontSize: WhiteboardCanvasTokens.statusSize,
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
                                        color: WhiteboardCanvasTokens
                                            .actionSoft,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        '当前',
                                        style: TextStyle(
                                          color: WhiteboardCanvasTokens.action,
                                          fontSize: WhiteboardCanvasTokens
                                              .statusSize,
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
            const Divider(
              height: 1,
              color: WhiteboardCanvasTokens.divider,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: _creating
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newName,
                            autofocus: true,
                            onSubmitted: (_) => _createAndPlace(),
                            style: const TextStyle(
                              color: WhiteboardCanvasTokens.textPrimary,
                              fontSize: WhiteboardCanvasTokens.metaSize,
                            ),
                            decoration: InputDecoration(
                              hintText: '新白板名称',
                              hintStyle: const TextStyle(
                                color: WhiteboardCanvasTokens.textFaint,
                                fontSize: WhiteboardCanvasTokens.metaSize,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              filled: true,
                              fillColor: WhiteboardCanvasTokens.canvas,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: WhiteboardCanvasTokens.divider,
                                  width: 1,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: const BorderSide(
                                  color: WhiteboardCanvasTokens.actionSecondary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _createAndPlace,
                          style: TextButton.styleFrom(
                            foregroundColor:
                                WhiteboardCanvasTokens.action,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
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
                      onTap: () => setState(() => _creating = true),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              size: 16,
                              color: WhiteboardCanvasTokens.action,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '新建白板',
                              style: TextStyle(
                                color: WhiteboardCanvasTokens.action,
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
