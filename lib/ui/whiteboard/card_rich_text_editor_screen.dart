/// Card rich text editor screen — production entry for the frozen route
/// `/cards/:cardId` (W6 integration base).
///
/// The route signature (`cardId`) is frozen; this screen resolves the
/// production storage directory (app support dir) and delegates to the
/// storage-injected editor in `editor/`. The editor itself stays decoupled:
/// no MemexRouter, no Drift, no canvas.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor_screen.dart'
    as editor;
import 'package:memex/ui/whiteboard_canvas/whiteboard_canvas_tokens.dart';

/// Full-screen rich text editor for a card.
class CardRichTextEditorScreen extends StatefulWidget {
  final String cardId;

  const CardRichTextEditorScreen({super.key, required this.cardId});

  static RichTextStorage? _storageOverride;

  /// Test seam: overrides the storage resolved by [resolveStorage], mirroring
  /// `AppDatabase.setTestInstance` (the platform channel for path_provider is
  /// unavailable / hangs under `flutter test`).
  @visibleForTesting
  static void setStorageForTesting(RichTextStorage storage) {
    _storageOverride = storage;
  }

  /// Resolves the production rich-text storage directory: app support dir /
  /// `whiteboard/rich_text`. Shared with the card library search index.
  ///
  /// When the platform channel is unavailable (headless / widget tests), the
  /// storage falls back to a temp-dir location so the frozen route still
  /// opens a working editor.
  static Future<RichTextStorage> resolveStorage() async {
    final override = _storageOverride;
    if (override != null) return override;
    Directory dir;
    try {
      final support = await getApplicationSupportDirectory();
      dir = Directory(p.join(support.path, 'whiteboard', 'rich_text'));
    } catch (_) {
      dir = Directory(
          p.join(Directory.systemTemp.path, 'hereiam_whiteboard_rich_text'));
    }
    return RichTextStorage(dir);
  }

  @override
  State<CardRichTextEditorScreen> createState() =>
      _CardRichTextEditorScreenState();
}

class _CardRichTextEditorScreenState extends State<CardRichTextEditorScreen> {
  late final Future<RichTextStorage> _storageFuture =
      CardRichTextEditorScreen.resolveStorage();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RichTextStorage>(
      future: _storageFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: WhiteboardCanvasTokens.canvas,
            body: Center(
              child: Text(
                '正在加载…',
                style: TextStyle(color: WhiteboardCanvasTokens.textFaint),
              ),
            ),
          );
        }
        return editor.CardRichTextEditorScreen(
          storage: snapshot.data!,
          cardId: widget.cardId,
        );
      },
    );
  }
}
