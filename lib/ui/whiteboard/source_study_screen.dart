/// Source study screen (占位 · W6 integration base).
///
/// Route: `/sources/:sourceId`. Parameter signature frozen; W4 will fill the
/// video reading surface (player / subtitles / anchors) and W2 the reading
/// views here — without touching router.dart.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Per-source consumption view (video study / reading).
class SourceStudyScreen extends StatelessWidget {
  final String sourceId;

  const SourceStudyScreen({super.key, required this.sourceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        title: const Text('研读'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_circle_outline,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              '研读视图（占位）\n由 W4 视频播放窗口填充',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              sourceId,
              style: const TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
