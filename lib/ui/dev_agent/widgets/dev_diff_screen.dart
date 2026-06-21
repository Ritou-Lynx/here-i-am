import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

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

  Future<void> _runAction(String action) async {
    setState(() => _submitting = true);
    try {
      await DevAgentBridgeService.instance.runAction(
        runId: widget.artifact.runId,
        action: action,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_successText(action))),
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
      appBar: AppBar(title: Text(widget.artifact.title)),
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
                  color: AppColors.textPrimary,
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _runAction('discard'),
                child: const Text('丢弃'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => _runAction('leave'),
                child: const Text('留着'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: _submitting ? null : () => _runAction('apply'),
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

  String _successText(String action) {
    return switch (action) {
      'discard' => '已请求丢弃。',
      'apply' => '已请求应用。',
      _ => '已保留。',
    };
  }
}
