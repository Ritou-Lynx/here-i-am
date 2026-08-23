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
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/data/whiteboard/whiteboard_data_bootstrap.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/routing/routes.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_page_title.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor_screen.dart'
    as editor;
import 'package:memex/ui/whiteboard/fonts.dart';

/// Full-screen rich text editor for a card.
class CardRichTextEditorScreen extends StatefulWidget {
  final String cardId;

  const CardRichTextEditorScreen({super.key, required this.cardId});

  static RichTextStorage? _storageOverride;
  static UnifiedCardRepository? _repositoryOverride;

  /// Test seam: overrides the storage resolved by [resolveStorage], mirroring
  /// `AppDatabase.setTestInstance` (the platform channel for path_provider is
  /// unavailable / hangs under `flutter test`).
  @visibleForTesting
  static void setStorageForTesting(RichTextStorage storage) {
    _storageOverride = storage;
  }

  @visibleForTesting
  static void setRepositoryForTesting(UnifiedCardRepository? repository) {
    _repositoryOverride = repository;
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
        p.join(Directory.systemTemp.path, 'hereiam_whiteboard_rich_text'),
      );
    }
    return RichTextStorage(dir);
  }

  static Future<UnifiedCardRepository> resolveRepository() async {
    final override = _repositoryOverride;
    if (override != null) return override;
    return WhiteboardDataBootstrap.productionRepository();
  }

  @override
  State<CardRichTextEditorScreen> createState() =>
      _CardRichTextEditorScreenState();
}

class _EditorLoad {
  const _EditorLoad({
    required this.storage,
    this.repository,
    this.document,
    this.tags = const [],
    this.tagSuggestions = const [],
    this.message,
    this.error,
  });

  final RichTextStorage storage;
  final UnifiedCardRepository? repository;
  final RichTextDocument? document;
  final List<String> tags;
  final List<String> tagSuggestions;
  final String? message;
  final String? error;
}

class _CardRichTextEditorScreenState extends State<CardRichTextEditorScreen> {
  late final Future<_EditorLoad> _loadFuture = _load();

  Future<void> _exitEditor() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go(AppRoutes.cardLibrary);
    }
  }

  Future<_EditorLoad> _load() async {
    final testStorage = CardRichTextEditorScreen._storageOverride;
    if (testStorage != null &&
        CardRichTextEditorScreen._repositoryOverride == null) {
      return _EditorLoad(storage: testStorage);
    }
    try {
      final repository = await CardRichTextEditorScreen.resolveRepository();
      final record = await repository.getCard(widget.cardId);
      if (record == null) {
        return _EditorLoad(
          storage: repository.richTextStorage,
          repository: repository,
          error: '卡片不存在：${widget.cardId}',
        );
      }
      final tagSuggestions = await repository.listDistinctTags();
      switch (record.documentState) {
        case CardDocumentState.available:
          return _EditorLoad(
            storage: repository.richTextStorage,
            repository: repository,
            document: record.document,
            tags: record.card.tags,
            tagSuggestions: tagSuggestions,
          );
        case CardDocumentState.corrupt:
          return _EditorLoad(
            storage: repository.richTextStorage,
            repository: repository,
            document: _projectionDocument(record.card.body),
            tags: record.card.tags,
            tagSuggestions: tagSuggestions,
            message: '富文本文件已损坏，当前显示数据库中的可搜索正文投影。保存将生成新的有效文档。',
          );
        case CardDocumentState.missing:
          return _EditorLoad(
            storage: repository.richTextStorage,
            repository: repository,
            document: _projectionDocument(record.card.body),
            tags: record.card.tags,
            tagSuggestions: tagSuggestions,
            message: record.card.body.isEmpty ? null : '富文本文件缺失，当前已用数据库正文投影恢复。',
          );
      }
    } catch (error) {
      final storage = await CardRichTextEditorScreen.resolveStorage();
      return _EditorLoad(storage: storage, error: '存储不可用：$error');
    }
  }

  static RichTextDocument _projectionDocument(String body) => RichTextDocument(
    blocks: [RichTextBlock(type: BlockType.paragraph, text: body)],
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_EditorLoad>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _EditorRouteState(
            cardId: widget.cardId,
            message: '正在加载卡片…',
            loading: true,
            onBack: _exitEditor,
          );
        }
        final load = snapshot.data!;
        if (load.error != null) {
          return _EditorRouteState(
            cardId: widget.cardId,
            message: load.error!,
            isError: true,
            onBack: _exitEditor,
          );
        }
        return editor.CardRichTextEditorScreen(
          storage: load.storage,
          cardId: widget.cardId,
          initialDocument: load.document,
          initialTags: load.tags,
          tagSuggestions: load.tagSuggestions,
          degradedMessage: load.message,
          onExit: _exitEditor,
          onSaveDocument: load.repository == null
              ? null
              : (cardId, document) =>
                    load.repository!.saveRichText(cardId, document),
          onSaveTags: load.repository == null
              ? null
              : (cardId, tags) async {
                  await load.repository!.updateCardMetadata(cardId, tags: tags);
                },
        );
      },
    );
  }
}

class _EditorRouteState extends StatelessWidget {
  const _EditorRouteState({
    required this.cardId,
    required this.message,
    required this.onBack,
    this.loading = false,
    this.isError = false,
  });

  final String cardId;
  final String message;
  final VoidCallback onBack;
  final bool loading;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPageTitle(title: '编辑卡片', meta: cardId, onBack: onBack),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        loading
                            ? Icons.hourglass_empty_rounded
                            : isError
                            ? Icons.error_outline_rounded
                            : Icons.info_outline_rounded,
                        size: 24,
                        color: isError ? tokens.error : tokens.textMuted,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: whiteboardUiTextStyle(
                          fontSize: 13,
                          height: 1.55,
                          color: isError ? tokens.error : tokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
