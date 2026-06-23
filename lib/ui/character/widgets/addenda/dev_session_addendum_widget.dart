import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/dev_agent/widgets/dev_session_screen.dart';

class DevSessionAddendumWidget extends StatelessWidget {
  const DevSessionAddendumWidget({
    super.key,
    required this.data,
    required this.isCharacterBubble,
  });

  final Map<String, dynamic> data;
  final bool isCharacterBubble;

  @override
  Widget build(BuildContext context) {
    final sessionId = (data['sessionId'] as String?) ?? '';
    if (sessionId.isEmpty) return const SizedBox.shrink();

    final title = (data['title'] as String?)?.trim();
    final agentType = (data['agentType'] as String?) ?? 'codex';
    final status = (data['status'] as String?) ?? 'done';
    final branch = (data['branch'] as String?)?.trim();
    final color = _statusColor(status);

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
          const SizedBox(height: 10),
          Align(
            alignment: isCharacterBubble
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DevSessionScreen(sessionId: sessionId),
                ),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('打开 Dev Session'),
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
    return agentType == 'claude_code' ? 'Claude Code' : 'Codex';
  }
}
