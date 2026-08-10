import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/ui/dev_agent/widgets/dev_run_screen.dart';

class DevSessionScreen extends StatefulWidget {
  const DevSessionScreen({
    super.key,
    required this.sessionId,
  });

  final String sessionId;

  @override
  State<DevSessionScreen> createState() => _DevSessionScreenState();
}

class _DevSessionScreenState extends State<DevSessionScreen> {
  final _controller = TextEditingController();
  Timer? _pollTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final session =
        await DevAgentBridgeService.instance.getSession(widget.sessionId);
    if (session == null) return;
    await DevAgentBridgeService.instance
        .refreshActiveRuns(projectId: session.projectId);
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await DevAgentBridgeService.instance.continueSession(
        sessionId: widget.sessionId,
        message: text,
      );
      _controller.clear();
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DevAgentSession?>(
      stream: DevAgentBridgeService.instance.watchSession(widget.sessionId),
      builder: (context, snapshot) {
        final session = snapshot.data;
        return Scaffold(
          backgroundColor: SpringRainUiTokens.daylightCanvas,
          appBar: AppBar(
            title: session == null
                ? const Text('Dev Session')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.title),
                      Text(
                        '${_agentLabel(session.agentType)} · ${session.status}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
            backgroundColor: SpringRainUiTokens.daylightCanvas,
            foregroundColor: SpringRainUiTokens.daylightTextPrimary,
            actions: [
              IconButton(
                tooltip: '刷新',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: session == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (session.goal?.trim().isNotEmpty == true)
                      _GoalBanner(goal: session.goal!.trim()),
                    Expanded(
                      child: StreamBuilder<List<DevAgentSessionMessage>>(
                        stream: DevAgentBridgeService.instance
                            .watchSessionMessages(widget.sessionId),
                        builder: (context, messageSnapshot) {
                          final messages = messageSnapshot.data ?? const [];
                          if (messages.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  '直接追问、分配下一步，或让它继续检查项目。',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: SpringRainUiTokens.daylightTextSecondary,
                                  ),
                                ),
                              ),
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            itemCount: messages.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _SessionMessageTile(
                                message: messages[index],
                              );
                            },
                          );
                        },
                      ),
                    ),
                    _SessionComposer(
                      controller: _controller,
                      sending: _sending,
                      onSend: _send,
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _agentLabel(String agentType) {
    return switch (agentType) {
      'claude_code' => 'Claude Code',
      'opencode' => 'OpenCode',
      _ => 'Codex',
    };
  }
}

class _GoalBanner extends StatelessWidget {
  const _GoalBanner({required this.goal});

  final String goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SpringRainUiTokens.daylightAccentSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        goal,
        style: const TextStyle(
          color: SpringRainUiTokens.daylightTextSecondary,
          height: 1.35,
        ),
      ),
    );
  }
}

class _SessionMessageTile extends StatelessWidget {
  const _SessionMessageTile({required this.message});

  final DevAgentSessionMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isSystem = message.role == 'system';
    final color = isUser
        ? SpringRainUiTokens.daylightAccentSoft
        : isSystem
            ? SpringRainUiTokens.daylightSurfaceMuted
            : SpringRainUiTokens.daylightSurface;
    final alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: SpringRainUiTokens.daylightDivider,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _roleLabel(message.role),
                    style: const TextStyle(
                      color: SpringRainUiTokens.daylightTextTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(
                        message.createdAt * 1000,
                      ),
                    ),
                    style: const TextStyle(
                      color: SpringRainUiTokens.daylightTextTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                message.content,
                style: const TextStyle(
                  height: 1.42,
                  color: SpringRainUiTokens.daylightTextPrimary,
                ),
              ),
              if (message.linkedRunId != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          DevRunScreen(runId: message.linkedRunId!),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('查看关联任务'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SpringRainUiTokens.daylightAccent,
                    side: const BorderSide(
                        color: SpringRainUiTokens.daylightDivider),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _roleLabel(String role) {
    return switch (role) {
      'user' => '你',
      'character' => '角色',
      'agent' => 'Agent',
      _ => '系统',
    };
  }
}

class _SessionComposer extends StatelessWidget {
  const _SessionComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: SpringRainUiTokens.daylightSurface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: '继续追问或交代下一步',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: '发送',
                onPressed: sending ? null : onSend,
                style: IconButton.styleFrom(
                  backgroundColor: SpringRainUiTokens.daylightAccent,
                  foregroundColor: SpringRainUiTokens.daylightTextOnAccent,
                ),
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
