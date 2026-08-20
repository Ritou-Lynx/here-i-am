/// Card rich text editor screen — the closed edit loop.
///
/// Loads an existing document from [RichTextStorage] (or starts empty),
/// lets the user edit it in [CardRichTextEditor], saves back to storage, and
/// intercepts unsaved exit via [confirmUnsavedExit]. This is the "entry →
/// persist → restart-recover" minimum closed loop for W2.
///
/// Media import: [CardRichTextEditor] asks this screen for asset refs; the
/// screen copies picked files into the [RichTextObjectStore] (relative
/// `objects/…` refs) and hands the stable refs back — the document JSON never
/// carries temporary source paths.
///
/// The screen is deliberately minimal and self-contained: no MemexRouter, no
/// Drift, no whiteboard canvas. It only needs a storage directory and a card
/// id, so it can be dropped into any future shell.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/rich_text_storage.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_page_title.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';
import 'package:memex/ui/whiteboard/editor/unsaved_exit_guard.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class CardRichTextEditorScreen extends StatefulWidget {
  final RichTextStorage storage;
  final String cardId;
  final RichTextDocument? initialDocument;
  final Future<void> Function(String cardId, RichTextDocument document)?
      onSaveDocument;
  final String? degradedMessage;

  /// Optional externally-owned controller. When provided, the screen uses it
  /// instead of creating its own (useful for tests and shell reuse).
  final RichTextEditingController? controller;

  /// Object store for imported media (defaults to one rooted at the
  /// storage base dir).
  final RichTextObjectStore? objectStore;

  /// Media import override (tests inject fakes; default uses FilePicker).
  final RichTextMediaImporter? mediaImporter;

  const CardRichTextEditorScreen({
    super.key,
    required this.storage,
    required this.cardId,
    this.initialDocument,
    this.onSaveDocument,
    this.degradedMessage,
    this.controller,
    this.objectStore,
    this.mediaImporter,
  });

  @override
  State<CardRichTextEditorScreen> createState() =>
      _CardRichTextEditorScreenState();
}

class _CardRichTextEditorScreenState extends State<CardRichTextEditorScreen> {
  late RichTextEditingController _controller;
  late RichTextObjectStore _objectStore;
  final FocusNode _saveFocusNode = FocusNode(debugLabel: 'editor-save');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = RichTextEditingController(RichTextDocument.empty());
    }
    _objectStore =
        widget.objectStore ?? RichTextObjectStore(widget.storage.baseDir);
    // Card documents are small local JSON files; synchronous load keeps the
    // closed loop simple and testable without a fake-async stall.
    final doc =
        widget.initialDocument ?? widget.storage.loadSync(widget.cardId);
    _controller.loadDocument(doc ?? RichTextDocument.empty());
    // Rebuild on controller changes so PopScope.canPop reflects the latest
    // dirty state (typing, save, undo/redo all notify).
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _saveFocusNode.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final document = _controller.flushToDocument();
      final save = widget.onSaveDocument;
      if (save != null) {
        await save(widget.cardId, document);
      } else {
        // Keep the injected standalone-storage seam synchronous: existing
        // widget tests and offline callers expect the file to exist as soon
        // as the button callback returns. Production Repository saves remain
        // awaited through [onSaveDocument].
        widget.storage.saveSync(widget.cardId, document);
      }
      _controller.markSaved();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<List<RichTextAssetRef>> _defaultMediaImporter(
      MediaImportKind kind) async {
    final result = await FilePicker.platform.pickFiles(
      type: kind == MediaImportKind.image ? FileType.image : FileType.any,
      allowMultiple: true,
    );
    if (result == null) return const [];
    final refs = <RichTextAssetRef>[];
    for (final file in result.files) {
      final path = file.path;
      if (path == null) continue; // Web only; desktop always has a path.
      final ref = await _objectStore.importFile(
        path,
        alt: file.name,
      );
      refs.add(ref);
    }
    return refs;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return PopScope(
      canPop: !_controller.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final choice = await confirmUnsavedExit(
          context,
          hasUnsavedChanges: _controller.isDirty,
          onSave: _save,
        );
        // A failed save deliberately keeps the controller dirty. Do not let
        // the confirmation path close the editor and lose those changes.
        if (choice == UnsavedExitChoice.save && _controller.isDirty) return;
        if (choice != UnsavedExitChoice.cancel && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: tokens.canvas,
        body: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DesktopPageTitle(
                title: '编辑卡片',
                meta: widget.cardId,
                onBack: () => Navigator.of(context).maybePop(),
                actions: [
                  _SaveStateIndicator(
                    isDirty: _controller.isDirty,
                    isSaving: _saving,
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const ValueKey('rich_text_save_button'),
                    focusNode: _saveFocusNode,
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 16),
                    label: Text(_saving ? '保存中' : '保存'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 36),
                      backgroundColor: tokens.action,
                      foregroundColor: tokens.canvas,
                      disabledBackgroundColor:
                          tokens.actionSoft.withValues(alpha: 0.42),
                      disabledForegroundColor: tokens.textMuted,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: whiteboardUiTextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.degradedMessage != null)
                _DegradedDocumentNotice(message: widget.degradedMessage!),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 640;
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 920),
                        child: Container(
                          key: const ValueKey('rich_text_editor_paper'),
                          margin: EdgeInsets.fromLTRB(
                            compact ? 12 : 24,
                            4,
                            compact ? 12 : 24,
                            compact ? 12 : 20,
                          ),
                          padding: EdgeInsets.all(compact ? 14 : 20),
                          decoration: BoxDecoration(
                            color: tokens.surfaceRaised,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: tokens.divider),
                          ),
                          child: CardRichTextEditor(
                            controller: _controller,
                            cardId: widget.cardId,
                            objectStore: _objectStore,
                            mediaImporter:
                                widget.mediaImporter ?? _defaultMediaImporter,
                            onSave: (_) => _save(),
                            markSavedAfterCallback: false,
                            showSaveInToolbar: false,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveStateIndicator extends StatelessWidget {
  const _SaveStateIndicator({
    required this.isDirty,
    required this.isSaving,
  });

  final bool isDirty;
  final bool isSaving;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final label = isSaving
        ? '正在保存'
        : isDirty
            ? '未保存'
            : '已保存';
    final color = isDirty || isSaving ? tokens.focus : tokens.textFaint;
    return Semantics(
      liveRegion: true,
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: whiteboardUiTextStyle(
              fontSize: 11,
              height: 1.35,
              color: color,
              fontWeight: isDirty ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _DegradedDocumentNotice extends StatelessWidget {
  const _DegradedDocumentNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.focus.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.focus.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.focus),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: whiteboardUiTextStyle(
                fontSize: 12,
                height: 1.5,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
