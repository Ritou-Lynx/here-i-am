import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/dev_agent/widgets/dev_diff_screen.dart';

class DevRunScreen extends StatefulWidget {
  const DevRunScreen({
    super.key,
    required this.runId,
  });

  final String runId;

  @override
  State<DevRunScreen> createState() => _DevRunScreenState();
}

class _DevRunScreenState extends State<DevRunScreen> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await DevAgentBridgeService.instance.refreshRun(widget.runId);
  }

  Future<void> _abort() async {
    await DevAgentBridgeService.instance.abort(widget.runId);
  }

  bool _isTerminal(String status) {
    return status == 'done' || status == 'failed' || status == 'aborted';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DevAgentRun?>(
      stream: DevAgentBridgeService.instance.watchRun(widget.runId),
      builder: (context, runSnapshot) {
        final run = runSnapshot.data;
        final status = run?.status ?? 'loading';
        if (_isTerminal(status)) {
          _pollTimer?.cancel();
          _pollTimer = null;
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(run == null ? 'Dev Run' : _agentLabel(run.agentType)),
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
              if (run != null && !_isTerminal(status))
                IconButton(
                  tooltip: '终止',
                  onPressed: _abort,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
            ],
          ),
          body: run == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _RunHeader(run: run),
                    _PendingApprovalBanner(runId: widget.runId),
                    _ArtifactsBar(runId: widget.runId),
                    Expanded(
                      child: StreamBuilder<List<DevAgentEvent>>(
                        stream: DevAgentBridgeService.instance
                            .watchEvents(widget.runId),
                        builder: (context, eventSnapshot) {
                          final events = eventSnapshot.data ?? const [];
                          if (events.isEmpty) {
                            return const Center(
                              child: Text('还没有事件。Bridge 接通后会在这里出现进度。'),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: events.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _EventTile(event: events[index]);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _PendingApprovalBanner extends StatelessWidget {
  const _PendingApprovalBanner({required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevAgentApproval>>(
      stream: DevAgentBridgeService.instance.watchPendingApprovals(runId),
      builder: (context, snapshot) {
        final approvals = snapshot.data ?? const [];
        if (approvals.isEmpty) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.deepPurple.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                color: Colors.deepPurple,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '有 ${approvals.length} 个操作等待审批',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _ApprovalSheet.show(context, approvals.first),
                child: const Text('查看'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ArtifactsBar extends StatelessWidget {
  const _ArtifactsBar({required this.runId});

  final String runId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DevAgentArtifact>>(
      stream: DevAgentBridgeService.instance.watchArtifacts(runId),
      builder: (context, snapshot) {
        final artifacts = snapshot.data ?? const [];
        if (artifacts.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 46,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: artifacts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final artifact = artifacts[index];
              return ActionChip(
                avatar: Icon(
                  artifact.kind == 'diff'
                      ? Icons.difference_outlined
                      : Icons.description_outlined,
                  size: 18,
                ),
                label: Text(artifact.title),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DevDiffScreen(artifact: artifact),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ApprovalSheet extends StatefulWidget {
  const _ApprovalSheet({required this.approval});

  final DevAgentApproval approval;

  static Future<void> show(
    BuildContext context,
    DevAgentApproval approval,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ApprovalSheet(approval: approval),
    );
  }

  @override
  State<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends State<_ApprovalSheet> {
  bool _submitting = false;

  Map<String, dynamic> get _description {
    try {
      final decoded = jsonDecode(widget.approval.descriptionJson);
      return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
    } catch (_) {
      return {'value': widget.approval.descriptionJson};
    }
  }

  Future<void> _respond(bool approved) async {
    setState(() => _submitting = true);
    try {
      await DevAgentBridgeService.instance.respondToApproval(
        approvalId: widget.approval.id,
        approved: approved,
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _description;
    final title = data['title']?.toString() ?? widget.approval.kind;
    final command = data['command']?.toString();
    final reason =
        data['reason']?.toString() ?? data['description']?.toString();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '审批请求',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                reason,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (command != null && command.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  command,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting ? null : () => _respond(false),
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting ? null : () => _respond(true),
                    child: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('批准'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunHeader extends StatelessWidget {
  const _RunHeader({required this.run});

  final DevAgentRun run;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              _StatusChip(status: run.status),
              const SizedBox(width: 8),
              Text(
                _agentLabel(run.agentType),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                DateFormat('HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(run.startedAt * 1000),
                ),
                style: const TextStyle(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            run.initialPrompt,
            style: const TextStyle(height: 1.4),
          ),
          if (run.summary != null && run.summary!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              run.summary!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'done' => Colors.green,
      'failed' => Colors.red,
      'aborted' => Colors.orange,
      'waiting_approval' => Colors.deepPurple,
      _ => AppColors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final DevAgentEvent event;

  @override
  Widget build(BuildContext context) {
    final payload = _payload();
    final title = _eventTitle(event.kind, payload);
    final detail = _eventDetail(payload);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_iconFor(event.kind), color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _payload() {
    try {
      final decoded = jsonDecode(event.payloadJson);
      return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
    } catch (_) {
      return {'value': event.payloadJson};
    }
  }
}

String _eventTitle(String kind, Map<String, dynamic> payload) {
  final text = payload['title'] ?? payload['name'] ?? payload['status'];
  if (text != null) return '$kind · $text';
  return kind;
}

String _eventDetail(Map<String, dynamic> payload) {
  for (final key in const ['text', 'message', 'summary', 'description']) {
    final value = payload[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }
  return '';
}

IconData _iconFor(String kind) {
  return switch (kind) {
    'tool_call' => Icons.build_outlined,
    'tool_result' => Icons.task_alt_outlined,
    'file_change' => Icons.description_outlined,
    'approval_request' => Icons.verified_user_outlined,
    'error' => Icons.error_outline,
    'status' => Icons.info_outline,
    _ => Icons.chat_bubble_outline,
  };
}

String _agentLabel(String agentType) {
  return switch (agentType) {
    'claude_code' => 'Claude Code',
    'codex' => 'Codex',
    _ => agentType,
  };
}
