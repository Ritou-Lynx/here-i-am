import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/dev_agent/widgets/dev_session_screen.dart';

class DevSessionAddendumWidget extends StatefulWidget {
  const DevSessionAddendumWidget({
    super.key,
    required this.data,
    required this.isCharacterBubble,
    this.messageId,
  });

  final Map<String, dynamic> data;
  final bool isCharacterBubble;

  /// Row id of the hosting persona chat message. Used to persist the user's
  /// Accept / Discard decision back into attachmentsJson so the decision row
  /// doesn't reappear when the widget is rebuilt (chat refreshes every 2s,
  /// and the State would otherwise be lost).
  final int? messageId;

  @override
  State<DevSessionAddendumWidget> createState() =>
      _DevSessionAddendumWidgetState();
}

class _DevSessionAddendumWidgetState extends State<DevSessionAddendumWidget> {
  bool _deciding = false;
  String? _decisionResult;
  bool? _decisionAccepted;

  @override
  void initState() {
    super.initState();
    // Seed local state from persisted addendum data so a rebuilt widget
    // (chat refresh, navigation away and back) keeps showing the decision
    // outcome instead of re-offering Accept / Discard.
    final persisted = widget.data['decision'] as String?;
    if (persisted != null && persisted.isNotEmpty) {
      _decisionAccepted = true;
      _decisionResult = _persistedLabel(persisted);
    }
  }

  String _persistedLabel(String decision) {
    return switch (decision) {
      'apply' => '已合入默认分支',
      'discard' => '已丢弃工作区',
      'leave' => '已保留工作区',
      _ => decision,
    };
  }

  /// Write-mode runs offer Accept (merge worktree into default branch) /
  /// Discard (remove worktree). Read-only runs never have a worktree and
  /// the Bridge rejects those decisions with `no_worktree`.
  bool get _isWriteModeCandidate {
    final worktree = (widget.data['worktreePath'] as String?)?.trim();
    return worktree != null && worktree.isNotEmpty;
  }

  Future<void> _decide(String decision) async {
    final runId = (widget.data['runId'] as String?) ?? '';
    if (runId.isEmpty) return;
    if (!DevAgentBridgeService.isInitialized) return;
    setState(() {
      _deciding = true;
      _decisionResult = null;
      _decisionAccepted = null;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final result = await DevAgentBridgeService.instance.decideRun(
        runId,
        decision,
      );
      if (!mounted) return;
      setState(() {
        _decisionAccepted = result.accepted;
        _decisionResult = result.message ?? result.reason ?? '';
      });
      if (messenger != null) {
        final ok = result.accepted;
        final label = switch (decision) {
          'apply' => ok ? '已合入默认分支' : '合入失败',
          'discard' => ok ? '已丢弃工作区' : '丢弃失败',
          'leave' => '已保留工作区',
          _ => decision,
        };
        messenger.showSnackBar(
          SnackBar(content: Text(label), duration: const Duration(seconds: 2)),
        );
      }
      // Persist the decision into the hosting chat message so the card
      // doesn't re-offer the buttons after a chat refresh or re-navigation.
      // Only persist on accepted leave/apply/discard; rejected decisions
      // leave the row actionable.
      if (result.accepted && widget.messageId != null) {
        await PersonaChatService.instance.persistDevSessionDecision(
          messageId: widget.messageId!,
          runId: runId,
          decision: decision,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _decisionAccepted = false;
        _decisionResult = e.toString();
      });
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('决定提交失败：$e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = (widget.data['sessionId'] as String?) ?? '';
    if (sessionId.isEmpty) return const SizedBox.shrink();

    final title = (widget.data['title'] as String?)?.trim();
    final agentType = (widget.data['agentType'] as String?) ?? 'codex';
    final status = (widget.data['status'] as String?) ?? 'done';
    final branch = (widget.data['branch'] as String?)?.trim();
    final color = _statusColor(status);

    // Accept / Discard only make sense for terminal, write-mode runs that
    // still have a worktree. Read-only runs and in-progress runs skip the
    // action row entirely.
    final isTerminal = const {'done', 'failed', 'aborted'}.contains(status);
    final showDecisionRow =
        _isWriteModeCandidate && isTerminal && _decisionAccepted == null;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title?.isNotEmpty == true ? title! : 'Dev Session',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_agentLabel(agentType)} · ${_statusLabel(status)}'
            '${branch?.isNotEmpty == true ? ' · $branch' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (_decisionResult != null) ...[
            const SizedBox(height: 6),
            Text(
              _decisionResult!,
              style: TextStyle(
                color: _decisionAccepted == true
                    ? const Color(0xFF10B981)
                    : AppColors.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (showDecisionRow)
            Row(
              children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _deciding ? null : () => _decide('apply'),
                  icon: const Icon(Icons.check, size: 16),
                  label: const Text('Accept'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _deciding ? null : () => _decide('discard'),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Discard'),
                ),
              ),
              ],
            )
          else
            Align(
              alignment: widget.isCharacterBubble
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DevSessionScreen(sessionId: sessionId),
                  ),
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('查看 Dev Room'),
              ),
            ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'done' => const Color(0xFF10B981),
      'failed' => const Color(0xFFEF4444),
      'aborted' => const Color(0xFFF59E0B),
      _ => AppColors.primary,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'done' => '完成',
      'failed' => '失败',
      'aborted' => '已停止',
      _ => status,
    };
  }

  String _agentLabel(String agentType) {
    return switch (agentType) {
      'claude_code' => 'Claude Code',
      'opencode' => 'OpenCode',
      _ => 'Codex',
    };
  }
}
