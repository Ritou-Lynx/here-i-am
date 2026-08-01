import 'package:flutter/material.dart';
import 'package:memex/data/services/current_context_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/db/app_database.dart';

/// 话题线索浏览页 — Memory V3 Topic Thread Browser.
///
/// Entry point: Life Space → 话题线索 tab (index 4).
/// Users can browse active topic threads, create new ones, and open details.
class TopicThreadBrowserScreen extends StatefulWidget {
  const TopicThreadBrowserScreen({super.key});

  @override
  State<TopicThreadBrowserScreen> createState() =>
      _TopicThreadBrowserScreenState();
}

class _TopicThreadBrowserScreenState extends State<TopicThreadBrowserScreen> {
  late final TopicThreadService _svc;
  List<TopicThread> _threads = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _svc = TopicThreadService(db: AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final threads = await _svc.getThreads();
    if (mounted) {
      setState(() {
        _threads = threads;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('话题线索', style: theme.textTheme.titleMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建话题',
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _threads.isEmpty
              ? _buildEmpty(theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: _threads.length,
                    itemBuilder: (_, i) =>
                        _buildThreadCard(_threads[i], theme),
                  ),
                ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text('还没有话题线索',
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
          const SizedBox(height: 8),
          Text('和我聊天时说"我想追踪这个话题"，\n或者点右上角 + 手动创建',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ],
      ),
    );
  }

  Widget _buildThreadCard(TopicThread thread, ThemeData theme) {
    final lastSeen = thread.lastDiscussedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(thread.lastDiscussedAt!)
        : null;
    final dateStr = lastSeen != null
        ? '${lastSeen.month}/${lastSeen.day}'
        : '未讨论';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: theme.colorScheme.surface.withValues(alpha: 0.7),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(thread),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(thread.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text(dateStr,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5))),
              ]),
              if (thread.currentStage.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(thread.currentStage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.7))),
              ],
              if (thread.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: thread.tags
                      .split(',')
                      .where((t) => t.trim().isNotEmpty)
                      .map((t) => Chip(
                            label: Text(t.trim(),
                                style: theme.textTheme.labelSmall),
                            padding: EdgeInsets.zero,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(TopicThread thread) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TopicThreadDetailScreen(
          thread: thread,
          service: _svc,
          onUpdated: _load,
        ),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建话题线索'),
        content: TextField(
          controller: titleCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '话题名称（2-10字）',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, titleCtrl.text),
              child: const Text('创建')),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await _svc.createThread(title: result.trim());
      await _load();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thread Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class _TopicThreadDetailScreen extends StatefulWidget {
  final TopicThread thread;
  final TopicThreadService service;
  final VoidCallback onUpdated;

  const _TopicThreadDetailScreen({
    required this.thread,
    required this.service,
    required this.onUpdated,
  });

  @override
  State<_TopicThreadDetailScreen> createState() =>
      _TopicThreadDetailScreenState();
}

class _TopicThreadDetailScreenState extends State<_TopicThreadDetailScreen> {
  late TopicThread _thread;
  List<TopicThreadSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _thread = widget.thread;
    CurrentContextService.push(CurrentPageContext(
      type: CurrentContextType.topicThread,
      id: _thread.id,
      title: _thread.title,
    ));
    _loadSessions();
  }

  @override
  void dispose() {
    CurrentContextService.pop(_thread.id);
    super.dispose();
  }

  Future<void> _loadSessions() async {
    final sessions =
        await widget.service.getSessions(_thread.id, limit: 30);
    if (mounted) {
      setState(() {
        _sessions = sessions;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final core =
        TopicThreadService.decodeListPublic(_thread.corePositionsJson);
    final openQ =
        TopicThreadService.decodeListPublic(_thread.openQuestionsJson);

    return Scaffold(
      appBar: AppBar(
        title: Text(_thread.title),
        actions: [
          PopupMenuButton<String>(
            onSelected: _onMenuAction,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'archive', child: Text('归档')),
              const PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_thread.currentStage.isNotEmpty) ...[
                  _sectionLabel(theme, '当前阶段'),
                  const SizedBox(height: 6),
                  Text(_thread.currentStage,
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                ],
                if (core.isNotEmpty) ...[
                  _sectionLabel(theme, '已确认洞察'),
                  const SizedBox(height: 6),
                  ...core.map((p) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('· '),
                            Expanded(child: Text(p)),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                ],
                if (openQ.isNotEmpty) ...[
                  _sectionLabel(theme, '还在想的问题'),
                  const SizedBox(height: 6),
                  ...openQ.map((q) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('· '),
                            Expanded(child: Text(q)),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                ],
                if (_sessions.isNotEmpty) ...[
                  _sectionLabel(theme, '讨论历史'),
                  const SizedBox(height: 8),
                  ..._sessions.map((s) => _buildSessionTile(s, theme)),
                ],
              ],
            ),
    );
  }

  Widget _sectionLabel(ThemeData theme, String label) {
    return Text(label,
        style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600));
  }

  Widget _buildSessionTile(TopicThreadSession s, ThemeData theme) {
    final date = DateTime.fromMillisecondsSinceEpoch(s.occurredAt);
    final dateStr = '${date.year}/${date.month}/${date.day}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(dateStr,
                style: theme.textTheme.labelSmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            const SizedBox(width: 8),
            Text('(${s.sourceType})',
                style: theme.textTheme.labelSmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.4))),
          ]),
          const SizedBox(height: 4),
          Text(s.summary, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _onMenuAction(String action) async {
    if (action == 'archive' || action == 'delete') {
      await widget.service
          .setStatus(threadId: _thread.id, status: 'archived');
      widget.onUpdated();
      if (mounted) Navigator.pop(context);
    }
  }
}
