import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/dev_agent/widgets/dev_project_settings_screen.dart';
import 'package:memex/ui/dev_agent/widgets/dev_run_screen.dart';
import 'package:memex/ui/dev_agent/widgets/dev_session_screen.dart';

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

  Future<void> _startSession(
    BuildContext context,
    DevProject project,
    DevAgentType agentType,
  ) async {
    final prompt = await _PromptDialog.show(context, agentType);
    if (prompt == null || prompt.trim().isEmpty) return;
    try {
      final firstLine = prompt.trim().split('\n').first.trim();
      final title = firstLine.length > 36
          ? '${firstLine.substring(0, 36)}...'
          : firstLine;
      final sessionId = await DevAgentBridgeService.instance.createSession(
        projectId: project.id,
        agentType: agentType,
        title: title.isEmpty ? 'Dev Session' : title,
        mode: project.permissionTier == 'read_only'
            ? 'read_only'
            : 'workspace_write',
      );
      await DevAgentBridgeService.instance.continueSession(
        sessionId: sessionId,
        message: prompt,
      );
      if (!context.mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DevSessionScreen(sessionId: sessionId),
        ),
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
      final result = await DevAgentBridgeService.instance
          .cleanupProjectWorktrees(project.id);
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
                onSessionClaude: () =>
                    _startSession(context, project, DevAgentType.claudeCode),
                onSessionCodex: () =>
                    _startSession(context, project, DevAgentType.codex),
                onCleanup: () => _cleanupProjectWorktrees(context, project),
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
    required this.onSessionClaude,
    required this.onSessionCodex,
    required this.onCleanup,
  });

  final DevProject project;
  final VoidCallback onEdit;
  final VoidCallback onSessionClaude;
  final VoidCallback onSessionCodex;
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
          if (project.permissionTier != 'read_only') ...[
            const SizedBox(height: 8),
            _GitStatusBar(project: project),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSessionClaude,
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Claude Code'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSessionCodex,
                  icon: const Icon(Icons.forum_outlined, size: 18),
                  label: const Text('Codex'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RecentSessions(projectId: project.id),
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
        style:
            TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
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
        final running = runs
            .where((r) => !{'done', 'failed', 'aborted'}.contains(r.status))
            .length;
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

class _GitStatusBar extends StatefulWidget {
  const _GitStatusBar({required this.project});

  final DevProject project;

  @override
  State<_GitStatusBar> createState() => _GitStatusBarState();
}

class _GitStatusBarState extends State<_GitStatusBar> {
  DevProjectGitStatus? _status;
  bool _loading = false;
  String? _error;
  bool _operating = false;
  bool _bridgeUnsupported = false;

  DevProject get _project => widget.project;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status =
          await DevAgentBridgeService.instance.getGitStatus(_project.id);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _bridgeUnsupported = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('Bridge does not support git')) {
        setState(() {
          _bridgeUnsupported = true;
          _loading = false;
        });
      } else {
        setState(() {
          _error = msg;
          _loading = false;
        });
      }
    }
  }

  Future<void> _pull() async {
    final status = _status;
    if (status == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('拉取远程代码'),
        content: Text(
          '将在 ${_project.rootPath} 执行：\n'
          'git fetch && git merge --ff-only\n'
          'origin/${_project.defaultBranch}\n\n'
          '预计快进合并 ${status.behind} 个 commit。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认拉取'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _operating = true);
    try {
      final result =
          await DevAgentBridgeService.instance.pullGit(_project.id);
      if (!mounted) return;
      if (result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message ?? '已拉取 ${status.behind} 个 commit。',
            ),
          ),
        );
        await _fetchStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? '拉取失败。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('拉取失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  Future<void> _push() async {
    final status = _status;
    if (status == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('推送到远程仓库'),
        content: Text(
          '将在 ${_project.rootPath} 执行：\n'
          'git push origin ${_project.defaultBranch}\n\n'
          '将推送 ${status.ahead} 个 commit。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认推送'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _operating = true);
    try {
      final result =
          await DevAgentBridgeService.instance.pushGit(_project.id);
      if (!mounted) return;
      if (result.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? '已推送 ${status.ahead} 个 commit。'),
          ),
        );
        await _fetchStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? '推送失败。'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('推送失败：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _operating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bridgeUnsupported) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.textTertiary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_loading && _status == null) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text(
            '检查 Git 状态...',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ],
      );
    }

    if (_error != null && _status == null) {
      return Row(
        children: [
          const Icon(Icons.error_outline, size: 14, color: Colors.red),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _error!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
          GestureDetector(
            onTap: _fetchStatus,
            child: const Icon(Icons.refresh, size: 16, color: AppColors.textTertiary),
          ),
        ],
      );
    }

    final status = _status;
    final showPull = status != null && status.behind > 0;
    final canPush = _project.permissionTier == 'release_ops';
    final showPush = status != null && status.ahead > 0 && canPush;

    if (status == null) return const SizedBox.shrink();
    if (!showPull && !showPush && status.ahead == 0 && status.behind == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 11),
            ),
          ),
        if (showPull || showPush)
          Row(
            children: [
              if (showPull) ...[
                Icon(Icons.cloud_download_outlined,
                    size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text(
                  '远程领先 ${status.behind} 个 commit',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (showPull && showPush) ...[
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 14,
                  color: AppColors.textTertiary.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 10),
              ],
              if (showPush) ...[
                const Icon(Icons.cloud_upload_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  '本地领先 ${status.ahead} 个 commit',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              if (_operating)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...[
                if (showPull)
                  TextButton.icon(
                    onPressed: _operating ? null : _pull,
                    icon: const Icon(Icons.download, size: 14),
                    label: const Text('拉取', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                if (showPush)
                  TextButton.icon(
                    onPressed: _operating ? null : _push,
                    icon: const Icon(Icons.upload, size: 14),
                    label: const Text('推送', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ],
          ),
        if (_loading && _status != null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevAgentSession>>(
      stream:
          DevAgentBridgeService.instance.watchSessions(projectId: projectId),
      builder: (context, snapshot) {
        final sessions = (snapshot.data ?? const []).take(2).toList();
        if (sessions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '最近会话',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            for (final session in sessions)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.forum_outlined, size: 20),
                title: Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${session.agentType} 路 ${session.status}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DevSessionScreen(sessionId: session.id),
                  ),
                ),
              ),
          ],
        );
      },
    );
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
