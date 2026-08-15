/// Link import screen (占位 · W6 integration base).
///
/// Route: `/import`. Parameter signature frozen; W3 will replace the body
/// with the paste-URL → ingest → four-state result → explicit card creation
/// flow — without touching router.dart.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Entry point for ordinary link ingestion.
class LinkImportScreen extends StatelessWidget {
  const LinkImportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        title: const Text('导入链接'),
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.link_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            SizedBox(height: 12),
            Text(
              '链接导入（占位）\n由 W3 抓取窗口填充',
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
