/// Whiteboard index screen (Task S · desktop workbench shell).
///
/// Route: `/whiteboard`. Parameter signature frozen by W6; this body is the
/// Task S shell surface: real board list from Drift + create board. Boards
/// open the full-screen canvas (`/whiteboard/:boardId`).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/data/whiteboard/whiteboard_drift_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// Board index — real list backed by [WhiteboardDriftStore].
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
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _createBoard() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SpringRainUiTokens.daylightSurfaceRaised,
        title: Text(
          '新建白板',
          style: whiteboardUiTextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: SpringRainUiTokens.daylightTextPrimary,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '白板名称',
            hintStyle: TextStyle(
              fontSize: 14,
              color: SpringRainUiTokens.daylightTextTertiary,
            ),
          ),
          style: whiteboardUiTextStyle(fontSize: 14),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(dialogContext).pop(value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              '取消',
              style: whiteboardUiTextStyle(
                fontSize: 14,
                color: SpringRainUiTokens.daylightTextSecondary,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(dialogContext).pop(value);
            },
            style: FilledButton.styleFrom(
              backgroundColor: SpringRainUiTokens.daylightAccent,
              foregroundColor: SpringRainUiTokens.daylightTextOnAccent,
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              '创建',
              style: whiteboardUiTextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final boardId = await _store.createBoard(name: name);
      if (!mounted) return;
      context.go(AppRoutes.whiteboardCanvasPath(boardId));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const tokens = SpringRainUiTokens.daylight;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        backgroundColor: tokens.canvas,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          tooltip: '返回首页',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: Text(
          '白板',
          style: whiteboardUiTextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton.icon(
            key: const ValueKey('whiteboard_create_button'),
            onPressed: _createBoard,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('新建', style: whiteboardUiTextStyle(fontSize: 14)),
            style: TextButton.styleFrom(
              foregroundColor: tokens.accent,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(tokens),
    );
  }

  Widget _buildBody(SpringRainUiTokens tokens) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: SpringRainUiTokens.daylightAccent,
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
                color: SpringRainUiTokens.daylightTextSecondary,
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
                color: SpringRainUiTokens.daylightTextPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '点右上角「新建」创建第一张白板。',
              style: whiteboardUiTextStyle(
                fontSize: 12,
                color: SpringRainUiTokens.daylightTextTertiary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: _boards.length,
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: SpringRainUiTokens.daylightDivider,
      ),
      itemBuilder: (context, index) {
        final board = _boards[index];
        final updatedAt = board.updatedAt ?? board.createdAt;
        return InkWell(
          key: ValueKey('board_row_${board.boardId}'),
          onTap: () => context.go(AppRoutes.whiteboardCanvasPath(board.boardId)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.space_dashboard_outlined,
                  size: 20,
                  color: SpringRainUiTokens.daylightTextTertiary,
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
                          color: SpringRainUiTokens.daylightTextPrimary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '最近更新 ${_relativeDay(updatedAt)}',
                        style: whiteboardUiTextStyle(
                          fontSize: 12,
                          color: SpringRainUiTokens.daylightTextTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: SpringRainUiTokens.daylightTextTertiary,
                ),
              ],
            ),
          ),
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
