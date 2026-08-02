import 'package:flutter/material.dart';
import 'package:memex/data/services/current_context_service.dart';
import 'package:memex/data/memory_v3/services/topic_thread_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

const _topicInk = Color(0xFF293025);
const _topicMuted = Color(0xFF667061);
const _topicAccent = Color(0xFF737B46);
const _topicOnRain = Color(0xFFF5EEE0);
const _topicSurface = Color(0xEDE7E8D1);

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: _topicOnRain,
        title: const Text(
          '话题线索',
          style: TextStyle(
            color: _topicOnRain,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(color: Colors.black45, blurRadius: 5)],
          ),
        ),
        actions: [
          IconButton.filledTonal(
            style: IconButton.styleFrom(
              foregroundColor: _topicAccent,
              backgroundColor: _topicSurface,
            ),
            icon: const Icon(Icons.add_rounded),
            tooltip: '新建话题',
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: _topicOnRain,
                strokeWidth: 2,
              ),
            )
          : _threads.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  color: _topicAccent,
                  backgroundColor: _topicSurface,
                  onRefresh: _load,
                  child: ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _threads.length,
                    itemBuilder: (_, i) => _buildThreadCard(_threads[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bookmark_border, size: 48, color: _topicOnRain),
          SizedBox(height: 12),
          Text(
            '还没有话题线索',
            style: TextStyle(
              color: _topicOnRain,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black45, blurRadius: 5)],
            ),
          ),
          SizedBox(height: 8),
          Text('和我聊天时说"我想追踪这个话题"，\n或者点右上角 + 手动创建',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _topicOnRain,
                height: 1.5,
                shadows: [Shadow(color: Colors.black45, blurRadius: 5)],
              )),
        ],
      ),
    );
  }

  Widget _buildThreadCard(TopicThread thread) {
    final lastSeen = thread.lastDiscussedAt != null
        ? DateTime.fromMillisecondsSinceEpoch(thread.lastDiscussedAt!)
        : null;
    final dateStr =
        lastSeen != null ? '${lastSeen.month}/${lastSeen.day}' : '未讨论';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: _topicSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xA8FFFFFF), width: .8),
      ),
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
                      style: const TextStyle(
                        color: _topicInk,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      )),
                ),
                Text(dateStr,
                    style: const TextStyle(color: _topicMuted, fontSize: 11)),
              ]),
              if (thread.currentStage.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(thread.currentStage,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: _topicMuted, fontSize: 12, height: 1.45)),
              ],
              if (thread.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: thread.tags
                      .split(',')
                      .where((t) => t.trim().isNotEmpty)
                      .map((t) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDDE1CB),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(t.trim(),
                                style: const TextStyle(
                                    color: _topicAccent, fontSize: 11)),
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
        builder: (_) => SpringRainUiScope(
          child: _TopicThreadDetailScreen(
            thread: thread,
            service: _svc,
            onUpdated: _load,
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final titleCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => SpringRainUiScope(
        child: AlertDialog(
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
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, titleCtrl.text),
                child: const Text('创建')),
          ],
        ),
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
    final sessions = await widget.service.getSessions(_thread.id, limit: 30);
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
    final core = TopicThreadService.decodeListPublic(_thread.corePositionsJson);
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
                  Text(_thread.currentStage, style: theme.textTheme.bodyMedium),
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
            color: theme.colorScheme.primary, fontWeight: FontWeight.w600));
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
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
            const SizedBox(width: 8),
            Text('(${s.sourceType})',
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
          ]),
          const SizedBox(height: 4),
          Text(s.summary, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Future<void> _onMenuAction(String action) async {
    if (action == 'archive' || action == 'delete') {
      await widget.service.setStatus(threadId: _thread.id, status: 'archived');
      widget.onUpdated();
      if (mounted) Navigator.pop(context);
    }
  }
}
