import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/dev_agent/widgets/dev_project_settings_screen.dart';
import 'package:memex/ui/dev_agent/widgets/dev_run_screen.dart';

class DevRoomScreen extends StatefulWidget {
  const DevRoomScreen({super.key});

  @override
  State<DevRoomScreen> createState() => _DevRoomScreenState();
}

class _DevRoomScreenState extends State<DevRoomScreen> {
  bool _refreshingRuns = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshActiveRuns();
    });
  }

  Future<void> _openProjectSettings(
    BuildContext context, {
    DevProject? project,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DevProjectSettingsScreen(project: project),
      ),
    );
  }

  Future<void> _startRun(
    BuildContext context,
    DevProject project,
    DevAgentType agentType,
  ) async {
    final prompt = await _PromptDialog.show(context, agentType);
    if (prompt == null || prompt.trim().isEmpty) return;
    try {
      final runId = await DevAgentBridgeService.instance.startRun(
        projectId: project.id,
        prompt: prompt,
        agentType: agentType,
      );
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DevRunScreen(runId: runId)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _cleanupProjectWorktrees(
    BuildContext context,
    DevProject project,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('清理 "${project.name}" 的 worktree?'),
        content: const Text(
          '会让 Bridge 删除该项目下所有已结束 run 残留的 worktree 和 dev-agent 分支。\n'
          'run 历史和事件不会被清——只清磁盘上的工作区。',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清理', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result =
          await DevAgentBridgeService.instance.cleanupProjectWorktrees(project.id);
      if (!context.mounted) return;
      final text = result.failed == 0
          ? '已清理 ${result.removed} 个 worktree'
          : '清理 ${result.removed} 个，${result.failed} 个失败';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _refreshActiveRuns({bool showResult = false}) async {
    if (_refreshingRuns) return;
    setState(() => _refreshingRuns = true);
    try {
      final count = await DevAgentBridgeService.instance.refreshActiveRuns();
      if (!mounted || !showResult) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(count == 0 ? '没有正在运行的任务。' : '已刷新 $count 个任务。')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _refreshingRuns = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dev Room'),
        actions: [
          IconButton(
            tooltip: '刷新任务',
            onPressed: _refreshingRuns
                ? null
                : () => _refreshActiveRuns(showResult: true),
            icon: _refreshingRuns
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProjectSettings(context),
        icon: const Icon(Icons.add),
        label: const Text('新增项目'),
      ),
      body: StreamBuilder<List<DevProject>>(
        stream: DevAgentBridgeService.instance.watchProjects(),
        builder: (context, snapshot) {
          final projects = snapshot.data ?? const [];
          if (projects.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: projects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final project = projects[index];
              return _ProjectCard(
                project: project,
                onEdit: () => _openProjectSettings(context, project: project),
                onRunClaude: () =>
                    _startRun(context, project, DevAgentType.claudeCode),
                onRunCodex: () =>
                    _startRun(context, project, DevAgentType.codex),
                onCleanup: () =>
                    _cleanupProjectWorktrees(context, project),
              );
            },
          );
        },
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onEdit,
    required this.onRunClaude,
    required this.onRunCodex,
    required this.onCleanup,
  });

  final DevProject project;
  final VoidCallback onEdit;
  final VoidCallback onRunClaude;
  final VoidCallback onRunCodex;
  final VoidCallback onCleanup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: AppColors.textTertiary.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _TierChip(tier: project.permissionTier),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'cleanup') onCleanup();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑 / 删除')),
                  PopupMenuItem(value: 'cleanup', child: Text('清理所有 worktree')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            project.rootPath,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            project.defaultBranch,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _ProjectRunsSummary(projectId: project.id),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRunClaude,
                  icon: const Icon(Icons.terminal_outlined, size: 18),
                  label: const Text('Claude Code'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRunCodex,
                  icon: const Icon(Icons.code_outlined, size: 18),
                  label: const Text('Codex'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RecentRuns(projectId: project.id),
        ],
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({required this.tier});

  final String tier;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (tier) {
      'workspace_write' => ('写入', const Color(0xFF10B981)),
      'release_ops' => ('发布', const Color(0xFFF43F5E)),
      _ => ('只读', const Color(0xFF3B82F6)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ProjectRunsSummary extends StatelessWidget {
  const _ProjectRunsSummary({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevAgentRun>>(
      stream: DevAgentBridgeService.instance.watchRuns(projectId: projectId),
      builder: (context, snapshot) {
        final runs = snapshot.data ?? const [];
        if (runs.isEmpty) {
          return const SizedBox.shrink();
        }
        final running = runs.where((r) => !{'done', 'failed', 'aborted'}.contains(r.status)).length;
        final done = runs.where((r) => r.status == 'done').length;
        final failed = runs.where((r) => r.status == 'failed').length;
        final latest = runs.first;
        final parts = <String>[];
        if (running > 0) parts.add('$running 跑中');
        if (done > 0) parts.add('$done 完成');
        if (failed > 0) parts.add('$failed 失败');
        parts.add('上次 ${_relativeTime(latest.startedAt)}');
        return Text(
          parts.join(' · '),
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
        );
      },
    );
  }

  static String _relativeTime(int epochSeconds) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = now - epochSeconds;
    if (diff < 60) return '刚刚';
    if (diff < 3600) return '${diff ~/ 60} 分钟前';
    if (diff < 86400) return '${diff ~/ 3600} 小时前';
    return '${diff ~/ 86400} 天前';
  }
}

class _RecentRuns extends StatelessWidget {
  const _RecentRuns({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevAgentRun>>(
      stream: DevAgentBridgeService.instance.watchRuns(projectId: projectId),
      builder: (context, snapshot) {
        final runs = (snapshot.data ?? const []).take(3).toList();
        if (runs.isEmpty) {
          return const Text(
            '还没有任务。',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          );
        }
        return Column(
          children: [
            for (final run in runs)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  run.initialPrompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${run.agentType} · ${run.status}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DevRunScreen(runId: run.id),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          '先添加一个开发项目。Dev Room 只保存控制数据，真正的 Claude Code / Codex 进程会跑在 Bridge 电脑上。',
          textAlign: TextAlign.center,
          style: TextStyle(
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({required this.agentType});

  final DevAgentType agentType;

  static Future<String?> show(
    BuildContext context,
    DevAgentType agentType,
  ) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(agentType: agentType),
    );
  }

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentName =
        widget.agentType == DevAgentType.codex ? 'Codex' : 'Claude Code';
    return AlertDialog(
      title: Text('交给 $agentName'),
      content: TextField(
        controller: _controller,
        minLines: 4,
        maxLines: 8,
        decoration: const InputDecoration(
          hintText: '例如：只读项目，告诉我当前 Dev Room 还缺哪些入口。',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('启动'),
        ),
      ],
    );
  }
}
