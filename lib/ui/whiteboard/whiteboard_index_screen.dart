/// Whiteboard index — the production entry surface (W6 integration base).
///
/// Lists boards from the Drift-backed store, creates new boards, and opens
/// the full-screen canvas. Follows the gray-paper + Palm visual rules
/// (`WhiteboardCanvasTokens`) with no persistent top bar of its own.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Board index screen. [store] is injectable for tests; defaults to the
/// production Drift store lazily (never touches `AppDatabase.instance` during
/// construction).
class WhiteboardIndexScreen extends StatefulWidget {
  final WhiteboardDriftStore? store;

  /// Overridable open callback for tests; defaults to GoRouter push.
  final void Function(String boardId)? onOpenBoard;

  const WhiteboardIndexScreen({super.key, this.store, this.onOpenBoard});

  @override
  State<WhiteboardIndexScreen> createState() => _WhiteboardIndexScreenState();
}

class _WhiteboardIndexScreenState extends State<WhiteboardIndexScreen> {
  late final WhiteboardDriftStore _store =
      widget.store ?? WhiteboardDriftStore(AppDatabase.instance);

  bool _loading = true;
  String? _error;
  List<WhiteboardIndexEntry> _boards = const [];
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final boards = await _store.listBoards();
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载白板失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _createBoard() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WhiteboardCanvasTokens.cardSurface,
        title: const Text(
          '新建白板',
          style: TextStyle(color: WhiteboardCanvasTokens.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: WhiteboardCanvasTokens.textPrimary),
          decoration: const InputDecoration(
            hintText: '白板名称',
            hintStyle: TextStyle(color: WhiteboardCanvasTokens.textFaint),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消',
                style: TextStyle(color: WhiteboardCanvasTokens.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: WhiteboardCanvasTokens.action,
              foregroundColor: const Color(0xFFF0EFEB),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    setState(() => _creating = true);
    try {
      final boardId = await _store.createBoard(name: trimmed);
      if (!mounted) return;
      _openBoard(boardId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建白板失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openBoard(String boardId) {
    final onOpenBoard = widget.onOpenBoard;
    if (onOpenBoard != null) {
      onOpenBoard(boardId);
      return;
    }
    context.push(AppRoutes.whiteboardCanvasPath(boardId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '白板',
                    style: TextStyle(
                      color: WhiteboardCanvasTokens.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: WhiteboardCanvasTokens.action,
                      foregroundColor: const Color(0xFFF0EFEB),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _creating ? null : _createBoard,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建白板'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '你的空间画布 · 卡片只保存摆放，不复制内容',
                style: TextStyle(
                  color: WhiteboardCanvasTokens.textFaint,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: WhiteboardCanvasTokens.divider),
              const SizedBox(height: 8),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: WhiteboardCanvasTokens.action,
          strokeWidth: 2,
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.orphanedBorder,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _reload,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_boards.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.space_dashboard_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            SizedBox(height: 12),
            Text(
              '还没有白板\n点右上角「新建白板」开始',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: _boards.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: WhiteboardCanvasTokens.divider,
      ),
      itemBuilder: (context, index) {
        final entry = _boards[index];
        return InkWell(
          onTap: () => _openBoard(entry.boardId),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            child: Row(
              children: [
                const Icon(
                  Icons.dashboard_outlined,
                  color: WhiteboardCanvasTokens.action,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.name,
                    style: const TextStyle(
                      color: WhiteboardCanvasTokens.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  _formatUpdated(entry.updatedAt ?? entry.createdAt),
                  style: const TextStyle(
                    color: WhiteboardCanvasTokens.textFaint,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  color: WhiteboardCanvasTokens.textFaint,
                  size: 18,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String _formatUpdated(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    String two(int v) => v.toString().padLeft(2, '0');
    if (sameDay) return '今天 ${two(local.hour)}:${two(local.minute)}';
    return '${local.year}-${two(local.month)}-${two(local.day)}';
  }
}
