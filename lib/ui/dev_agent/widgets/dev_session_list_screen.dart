import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/dev_agent/widgets/dev_session_screen.dart';

class DevSessionListScreen extends StatelessWidget {
  const DevSessionListScreen({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  final String projectId;
  final String projectName;

  @override
  Widget build(BuildContext context) {
    return SpringRainUiScope(
      child: Scaffold(
        backgroundColor: SpringRainUiTokens.daylightCanvas,
        appBar: AppBar(
          title: Text('$projectName · 全部会话'),
          backgroundColor: SpringRainUiTokens.daylightCanvas,
          foregroundColor: SpringRainUiTokens.daylightTextPrimary,
        ),
        body: StreamBuilder<List<DevAgentSession>>(
          stream: DevAgentBridgeService.instance
              .watchSessions(projectId: projectId),
          builder: (context, snapshot) {
            final sessions = snapshot.data ?? const [];
            if (sessions.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    '还没有会话。',
                    style: TextStyle(
                      color: SpringRainUiTokens.daylightTextSecondary,
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final session = sessions[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.forum_outlined,
                    size: 20,
                    color: SpringRainUiTokens.daylightIcon,
                  ),
                  title: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SpringRainUiTokens.daylightTextPrimary,
                    ),
                  ),
                  subtitle: Text(
                    '${_agentLabel(session.agentType)} · ${session.status} · ${_relativeTime(session.updatedAt)}',
                    style: const TextStyle(
                      color: SpringRainUiTokens.daylightTextSecondary,
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: SpringRainUiTokens.daylightIconMuted,
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DevSessionScreen(sessionId: session.id),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  static String _agentLabel(String agentType) {
    return switch (agentType) {
      'claude_code' => 'Claude Code',
      'opencode' => 'OpenCode',
      _ => 'Codex',
    };
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
