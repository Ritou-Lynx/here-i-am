/// Whiteboard index screen (最小占位 · W6 v2 integration base).
///
/// Route: `/whiteboard`. Parameter signature frozen; the real board-list /
/// create surface belongs to Task S (desktop shell) and later product
/// windows, which fill this placeholder body without touching router.dart.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Board index — currently a minimal placeholder per the v2 pipeline scope.
class WhiteboardIndexScreen extends StatelessWidget {
  const WhiteboardIndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        title: const Text('白板'),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.space_dashboard_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            SizedBox(height: 12),
            Text(
              '白板索引（占位）\n由 Task S 外壳窗口填充',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
