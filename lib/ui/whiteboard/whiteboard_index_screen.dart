/// Repository-backed desktop whiteboard index.
///
/// The screen renders a compact paper grid from the real Drift snapshot. It
/// never imports the HTML prototype's localStorage or seeded board data.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/whiteboard/board.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_page_title.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class WhiteboardIndexScreen extends StatefulWidget {
  const WhiteboardIndexScreen({super.key});

  @override
  State<WhiteboardIndexScreen> createState() => _WhiteboardIndexScreenState();
}

class _WhiteboardIndexScreenState extends State<WhiteboardIndexScreen> {
  late final WhiteboardDriftStore _store;
  bool _loading = true;
  Object? _error;
  List<WhiteboardIndexEntry> _boards = const [];
  Map<String, List<BoardItem>> _itemsByBoard = const {};

  @override
  void initState() {
    super.initState();
    _store = WhiteboardDriftStore(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await _store.listBoards();
      var itemsByBoard = const <String, List<BoardItem>>{};
      if (boards.isNotEmpty) {
        final loaded = await _store.load(boards.first.boardId);
        final snapshot = loaded.snapshot;
        if (snapshot != null) {
          final grouped = <String, List<BoardItem>>{};
          for (final item in snapshot.boardItems) {
            grouped.putIfAbsent(item.boardId, () => []).add(item);
          }
          itemsByBoard = grouped;
        }
      }
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _itemsByBoard = itemsByBoard;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _createBoard() async {
    final desktopTokens = Theme.of(context).extension<DesktopWorkspaceTokens>();
    const mobileTokens = SpringRainUiTokens.daylight;
    var draft = '';
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor:
            desktopTokens?.surfaceRaised ?? mobileTokens.surfaceRaised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '新建白板',
          style: whiteboardUiTextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: desktopTokens?.textPrimary ?? mobileTokens.textPrimary,
          ),
        ),
        content: TextField(
          key: const ValueKey('whiteboard_new_name'),
          autofocus: true,
          decoration: const InputDecoration(hintText: '白板名称'),
          style: whiteboardUiTextStyle(fontSize: 14),
          onChanged: (value) => draft = value,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final value = draft.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            style: FilledButton.styleFrom(
              backgroundColor: desktopTokens?.action ?? mobileTokens.accent,
              foregroundColor:
                  desktopTokens?.canvas ?? mobileTokens.textOnAccent,
            ),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final boardId = await _store.createBoard(name: name);
      if (!mounted) return;
      context.go(AppRoutes.whiteboardCanvasPath(boardId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$error')),
      );
    }
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktopTokens = Theme.of(context).extension<DesktopWorkspaceTokens>();
    if (desktopTokens == null) return _buildMobile();
    return _buildDesktop(desktopTokens);
  }

  Widget _buildDesktop(DesktopWorkspaceTokens tokens) {
    return Scaffold(
      key: const ValueKey('whiteboard_desktop_index'),
      backgroundColor: tokens.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageTitle(
            title: '白板',
            meta: _loading ? null : '${_boards.length} 张白板',
            onBack: _goBack,
            actions: [
              FilledButton.icon(
                key: const ValueKey('whiteboard_create_button'),
                onPressed: _createBoard,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新建白板'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  backgroundColor: tokens.action,
                  foregroundColor: tokens.canvas,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          Expanded(child: _buildBody(tokens)),
        ],
      ),
    );
  }

  Widget _buildMobile() {
    const tokens = SpringRainUiTokens.daylight;
    return Scaffold(
      key: const ValueKey('whiteboard_mobile_index'),
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          tooltip: '返回首页',
          onPressed: _goBack,
        ),
        title: Text(
          '白板',
          style: whiteboardUiTextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('whiteboard_create_button'),
            onPressed: _createBoard,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('新建', style: whiteboardUiTextStyle(fontSize: 14)),
            style: TextButton.styleFrom(foregroundColor: tokens.accent),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildMobileBody(tokens),
    );
  }

  Widget _buildMobileBody(SpringRainUiTokens tokens) {
    if (_loading) {
      return Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: tokens.accent,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '白板列表没有读出来，重试即可继续。',
              style: whiteboardUiTextStyle(
                fontSize: 14,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.accent,
                minimumSize: const Size(0, 36),
              ),
              child: Text('重试', style: whiteboardUiTextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
    }
    if (_boards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '还没有白板',
              style: whiteboardUiTextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点右上角「新建」创建第一张白板。',
              style: whiteboardUiTextStyle(
                fontSize: 12,
                color: tokens.textTertiary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      key: const ValueKey('whiteboard_mobile_list'),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: _boards.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: tokens.divider),
      itemBuilder: (context, index) {
        final board = _boards[index];
        return InkWell(
          key: ValueKey('board_row_${board.boardId}'),
          onTap: () =>
              context.go(AppRoutes.whiteboardCanvasPath(board.boardId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Icon(
                  Icons.space_dashboard_outlined,
                  size: 20,
                  color: tokens.textTertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        board.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: whiteboardUiTextStyle(
                          fontSize: 14,
                          color: tokens.textPrimary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '最近更新 ${_relativeDay(board.updatedAt ?? board.createdAt)}',
                        style: whiteboardUiTextStyle(
                          fontSize: 12,
                          color: tokens.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: tokens.textTertiary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody(DesktopWorkspaceTokens tokens) {
    if (_loading) {
      return Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: tokens.action,
          ),
        ),
      );
    }
    if (_error != null) {
      return _IndexMessage(
        title: '白板列表没有读出来，重试即可继续。',
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_boards.isEmpty) {
      return const _IndexMessage(
        title: '还没有白板',
        detail: '点「新建白板」创建第一张白板。',
      );
    }
    return GridView.builder(
      key: const ValueKey('whiteboard_grid'),
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 310,
        mainAxisExtent: 216,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _boards.length,
      itemBuilder: (context, index) {
        final board = _boards[index];
        final items = _itemsByBoard[board.boardId] ?? const <BoardItem>[];
        return _BoardTile(
          board: board,
          items: items,
          onOpen: () =>
              context.go(AppRoutes.whiteboardCanvasPath(board.boardId)),
          relativeDay: _relativeDay(board.updatedAt ?? board.createdAt),
        );
      },
    );
  }

  String _relativeDay(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${local.month} 月 ${local.day} 日';
  }
}

class _BoardTile extends StatelessWidget {
  const _BoardTile({
    required this.board,
    required this.items,
    required this.relativeDay,
    required this.onOpen,
  });

  final WhiteboardIndexEntry board;
  final List<BoardItem> items;
  final String relativeDay;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: tokens.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('board_row_${board.boardId}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _BoardPaperPreview(
                  key: ValueKey('whiteboard_preview_${board.boardId}'),
                  items: items,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                board.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: whiteboardUiTextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${items.length} 张卡片 · 最近更新 $relativeDay',
                style: whiteboardUiTextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: tokens.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardPaperPreview extends StatelessWidget {
  const _BoardPaperPreview({super.key, required this.items});

  final List<BoardItem> items;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: ColoredBox(
            color: tokens.surfaceRaised,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _PaperDotPainter(tokens.divider)),
                if (items.isEmpty)
                  Center(
                    child: Text(
                      '空白白板',
                      style: whiteboardUiTextStyle(
                        fontSize: 11,
                        color: tokens.textFaint,
                      ),
                    ),
                  )
                else
                  ..._miniItems(constraints.biggest, tokens),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _miniItems(Size size, DesktopWorkspaceTokens tokens) {
    final visible = (items.toList()
          ..sort((a, b) => a.zIndex.compareTo(b.zIndex)))
        .take(10)
        .toList();
    final minX = visible.map((item) => item.x).reduce(math.min);
    final minY = visible.map((item) => item.y).reduce(math.min);
    final maxX = visible.map((item) => item.x + item.width).reduce(math.max);
    final maxY = visible.map((item) => item.y + item.height).reduce(math.max);
    final spanX = math.max(1.0, maxX - minX);
    final spanY = math.max(1.0, maxY - minY);
    const inset = 10.0;
    final usableWidth = math.max(1.0, size.width - inset * 2);
    final usableHeight = math.max(1.0, size.height - inset * 2);
    return [
      for (var index = 0; index < visible.length; index++)
        Positioned(
          left: inset + (visible[index].x - minX) / spanX * usableWidth,
          top: inset + (visible[index].y - minY) / spanY * usableHeight,
          width: math.max(
            18.0,
            visible[index].width / spanX * usableWidth * .78,
          ),
          height: math.max(
            12.0,
            visible[index].height / spanY * usableHeight * .72,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: index == visible.length - 1
                  ? tokens.actionSoft.withValues(alpha: .22)
                  : tokens.surface,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: tokens.divider),
            ),
          ),
        ),
    ];
  }
}

class _PaperDotPainter extends CustomPainter {
  const _PaperDotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const gap = 18.0;
    for (var x = gap / 2; x < size.width; x += gap) {
      for (var y = gap / 2; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), .75, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PaperDotPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _IndexMessage extends StatelessWidget {
  const _IndexMessage({
    required this.title,
    this.detail,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: whiteboardUiTextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: whiteboardUiTextStyle(
                fontSize: 12,
                color: tokens.textFaint,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
