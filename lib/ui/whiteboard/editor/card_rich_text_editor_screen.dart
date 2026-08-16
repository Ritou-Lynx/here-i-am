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
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';
import 'package:memex/ui/whiteboard/editor/unsaved_exit_guard.dart';

class CardRichTextEditorScreen extends StatefulWidget {
  final RichTextStorage storage;
  final String cardId;

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
    final doc = widget.storage.loadSync(widget.cardId);
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
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    widget.storage.saveSync(widget.cardId, _controller.flushToDocument());
    _controller.markSaved();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
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
    return PopScope(
      canPop: !_controller.isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final choice = await confirmUnsavedExit(
          context,
          hasUnsavedChanges: _controller.isDirty,
          onSave: _save,
        );
        if (choice != UnsavedExitChoice.cancel && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('卡片编辑 · ${widget.cardId}'),
          actions: [
            TextButton(
              onPressed: _save,
              child: const Text('保存'),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: CardRichTextEditor(
            controller: _controller,
            cardId: widget.cardId,
            objectStore: _objectStore,
            mediaImporter: widget.mediaImporter ?? _defaultMediaImporter,
            onSave: (_) => _save(),
          ),
        ),
      ),
    );
  }
}
