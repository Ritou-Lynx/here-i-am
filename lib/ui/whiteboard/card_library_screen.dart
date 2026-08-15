/// Card library screen — the single card library (占位 · W6 integration base).
///
/// Route: `/cards`. Parameter signature is frozen; the parallel W2/W3
/// windows will replace the body of this screen without touching router.dart.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// The unique card library: browse / filter by type, source, tags, time and
/// board membership. Currently a minimal placeholder.
class CardLibraryScreen extends StatelessWidget {
  const CardLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        title: const Text('卡片库'),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            SizedBox(height: 12),
            Text(
              '卡片库（占位）\n由 W2 富文本 / W3 抓取窗口填充',
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
