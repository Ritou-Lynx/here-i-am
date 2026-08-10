import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

class DevDiffScreen extends StatefulWidget {
  const DevDiffScreen({
    super.key,
    required this.artifact,
  });

  final DevAgentArtifact artifact;

  @override
  State<DevDiffScreen> createState() => _DevDiffScreenState();
}

class _DevDiffScreenState extends State<DevDiffScreen> {
  bool _submitting = false;

  Future<void> _decide(String decision) async {
    setState(() => _submitting = true);
    try {
      final result = await DevAgentBridgeService.instance.decideRun(
        widget.artifact.runId,
        decision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.accepted
                ? _successText(decision)
                : (result.message ??
                    '$decision 被 Bridge 拒绝：${result.reason ?? "unknown"}'),
          ),
        ),
      );
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
    final content = widget.artifact.content ?? widget.artifact.uri ?? '';
    return Scaffold(
      backgroundColor: SpringRainUiTokens.daylightCanvas,
      appBar: AppBar(
        title: Text(widget.artifact.title),
        backgroundColor: SpringRainUiTokens.daylightCanvas,
        foregroundColor: SpringRainUiTokens.daylightTextPrimary,
      ),
      body: content.isEmpty
          ? const Center(child: Text('这个 artifact 没有可显示内容。'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                content,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.45,
                  color: SpringRainUiTokens.daylightTextPrimary,
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _decide('discard'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SpringRainUiTokens.daylightTextPrimary,
                  side: const BorderSide(
                      color: SpringRainUiTokens.daylightDivider),
                ),
                child: const Text('丢弃'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _decide('leave'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: SpringRainUiTokens.daylightTextPrimary,
                  side: const BorderSide(
                      color: SpringRainUiTokens.daylightDivider),
                ),
                child: const Text('留着'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _submitting ? null : () => _decide('apply'),
                style: FilledButton.styleFrom(
                  backgroundColor: SpringRainUiTokens.daylightAccent,
                  foregroundColor: SpringRainUiTokens.daylightTextOnAccent,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _successText(String decision) {
    return switch (decision) {
      'discard' => '已请求丢弃。',
      'apply' => '已请求应用。',
      _ => '已保留。',
    };
  }
}
