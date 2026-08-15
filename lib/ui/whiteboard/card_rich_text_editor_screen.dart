/// Card rich text editor screen (占位 · W6 integration base).
///
/// Route: `/cards/:cardId`. Parameter signature frozen; W2 will replace the
/// body with the full RichTextDocument editor — without touching router.dart.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Full-screen rich text editor for a card.
class CardRichTextEditorScreen extends StatelessWidget {
  final String cardId;

  const CardRichTextEditorScreen({super.key, required this.cardId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: WhiteboardCanvasTokens.canvas,
      appBar: AppBar(
        backgroundColor: WhiteboardCanvasTokens.canvas,
        foregroundColor: WhiteboardCanvasTokens.textPrimary,
        elevation: 0,
        title: const Text('编辑卡片'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.edit_note_outlined,
              color: WhiteboardCanvasTokens.textFaint,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              '富文本编辑器（占位）\n由 W2 富文本窗口填充',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WhiteboardCanvasTokens.textFaint,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              cardId,
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
