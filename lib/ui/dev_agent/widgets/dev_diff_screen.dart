import 'package:flutter/material.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

class DevDiffScreen extends StatelessWidget {
  const DevDiffScreen({
    super.key,
    required this.artifact,
  });

  final DevAgentArtifact artifact;

  @override
  Widget build(BuildContext context) {
    final content = artifact.content ?? artifact.uri ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(artifact.title)),
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
    );
  }
}
