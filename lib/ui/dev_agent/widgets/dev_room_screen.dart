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
  });

  final DevProject project;
  final VoidCallback onEdit;
  final VoidCallback onRunClaude;
  final VoidCallback onRunCodex;

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
              IconButton(
                tooltip: '编辑',
                onPressed: onEdit,
                icon: const Icon(Icons.settings_outlined),
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
          const SizedBox(height: 6),
          Text(
            '${project.permissionTier} · ${project.defaultBranch}',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
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
