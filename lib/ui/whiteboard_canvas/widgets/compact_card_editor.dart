/// Transient, board-local Card editor.
///
/// This surface edits the same [RichTextDocument] owned by
/// [UnifiedCardRepository]. The Card title is projected into a synthetic,
/// session-only first block so the embedded editor remains one continuous
/// rich-text surface without changing the persisted body document.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class InlineCardTextProjection {
  const InlineCardTextProjection({required this.title, required this.body});

  final String title;
  final String body;

  factory InlineCardTextProjection.fromText(String text) {
    final firstBreak = text.indexOf('\n');
    if (firstBreak < 0) {
      return InlineCardTextProjection(title: text, body: '');
    }
    return InlineCardTextProjection(
      title: text.substring(0, firstBreak),
      body: text.substring(firstBreak + 1),
    );
  }

  static String compose({required String title, required String body}) {
    if (body.isEmpty) return title;
    return '$title\n$body';
  }
}

class CompactCardEditorController {
  Object? _owner;
  Future<void> Function()? _saveAndClose;

  bool get isAttached => _saveAndClose != null;

  Future<void> saveAndClose() => _saveAndClose?.call() ?? Future<void>.value();

  void _attach(Object owner, Future<void> Function() saveAndClose) {
    _owner = owner;
    _saveAndClose = saveAndClose;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _saveAndClose = null;
  }
}

class CompactCardEditor extends StatefulWidget {
  const CompactCardEditor({
    super.key,
    required this.cardId,
    required this.repository,
    required this.onSaved,
    required this.onClose,
    required this.onExpand,
    this.controller,
    this.isReadonly = false,
    this.embedded = false,
  });

  final String cardId;
  final UnifiedCardRepository repository;
  final ValueChanged<CardContract> onSaved;
  final VoidCallback onClose;
  final ValueChanged<CardContract> onExpand;
  final CompactCardEditorController? controller;
  final bool isReadonly;
  final bool embedded;

  @override
  State<CompactCardEditor> createState() => _CompactCardEditorState();
}

class _CompactCardEditorState extends State<CompactCardEditor> {
  final FocusNode _surfaceFocusNode = FocusNode(
    debugLabel: 'whiteboard inline card editor',
  );
  RichTextEditingController? _richText;
  CardContract? _card;
  String? _error;
  bool _saving = false;
  bool _closing = false;
  int _loadGeneration = 0;

  bool get _dirty => _richText?.isDirty ?? false;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this, _saveAndClose);
    if (widget.embedded) {
      FocusManager.instance.addEarlyKeyEventHandler(_onEarlyKeyEvent);
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant CompactCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.embedded != widget.embedded) {
      if (widget.embedded) {
        FocusManager.instance.addEarlyKeyEventHandler(_onEarlyKeyEvent);
      } else {
        FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKeyEvent);
      }
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this, _saveAndClose);
    }
    if (oldWidget.cardId != widget.cardId ||
        !identical(oldWidget.repository, widget.repository)) {
      _disposeControllers();
      _card = null;
      _error = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      final record = await widget.repository.getCard(widget.cardId);
      if (!mounted || generation != _loadGeneration) return;
      if (record == null) {
        setState(() => _error = '卡片不存在或已经删除。');
        return;
      }
      final bodyDocument = record.document ??
          RichTextDocument(
            blocks: [
              RichTextBlock(
                type: BlockType.paragraph,
                text: record.card.body,
              ),
            ],
          );
      final richText = RichTextEditingController(
        _InlineCardDocument.combine(
          title: record.card.title,
          body: bodyDocument,
        ),
      )..addListener(_handleChanged);
      setState(() {
        _card = record.card;
        _richText = richText;
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '无法打开卡片：$error');
      }
    }
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  void _disposeControllers() {
    _richText?.removeListener(_handleChanged);
    _richText?.dispose();
    _richText = null;
  }

  @override
  void dispose() {
    _loadGeneration++;
    FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKeyEvent);
    widget.controller?._detach(this);
    _disposeControllers();
    _surfaceFocusNode.dispose();
    super.dispose();
  }

  Future<CardContract?> _save() async {
    if (widget.isReadonly) return null;
    final controller = _richText;
    if (controller == null || _saving) return _card;
    setState(() => _saving = true);
    try {
      final edit = _InlineCardDocument.split(controller.flushToDocument());
      final updated = await widget.repository.saveRichText(
        widget.cardId,
        edit.body,
        title: edit.title,
        preserveEmptyTitle: true,
      );
      if (!mounted) return updated;
      controller.markSaved();
      _card = updated;
      widget.onSaved(updated);
      setState(() {});
      return updated;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$error')),
        );
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestClose() async {
    if (!_dirty) {
      widget.onClose();
      return;
    }
    final choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存这次修改吗？'),
        content: const Text('卡片仍有未保存内容。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _CloseChoice.cancel),
            child: const Text('继续编辑'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _CloseChoice.discard),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _CloseChoice.save),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == _CloseChoice.cancel) return;
    if (choice == _CloseChoice.save && await _save() == null) return;
    widget.onClose();
  }

  Future<void> _saveAndClose() async {
    if (_closing) return;
    _closing = true;
    try {
      if (!widget.isReadonly && _dirty && await _save() == null) return;
      if (mounted) widget.onClose();
    } finally {
      _closing = false;
    }
  }

  Future<void> _expand() async {
    CardContract? card = _card;
    if (_dirty) card = await _save();
    if (!mounted || card == null) return;
    widget.onExpand(card);
  }

  KeyEventResult _onEarlyKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        _surfaceFocusNode.hasFocus) {
      unawaited(_saveAndClose());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final surface = Material(
      key: const ValueKey('wb_compact_card_editor'),
      type: widget.embedded ? MaterialType.transparency : MaterialType.canvas,
      color: widget.embedded ? null : tokens.surfaceRaised,
      elevation: widget.embedded ? 0 : 10,
      shadowColor: tokens.textPrimary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(widget.embedded ? 0 : 10),
      clipBehavior: Clip.antiAlias,
      child: widget.embedded
          ? _buildBody(tokens)
          : DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: tokens.divider),
                borderRadius: BorderRadius.circular(10),
              ),
              child: _buildBody(tokens),
            ),
    );
    if (!widget.embedded) return surface;
    return TapRegion(
      onTapOutside: (_) => unawaited(_saveAndClose()),
      child: Focus(focusNode: _surfaceFocusNode, child: surface),
    );
  }

  Widget _buildBody(DesktopWorkspaceTokens tokens) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: whiteboardUiTextStyle(color: tokens.error)),
            const SizedBox(height: 12),
            TextButton(onPressed: widget.onClose, child: const Text('关闭')),
          ],
        ),
      );
    }
    final card = _card;
    final richText = _richText;
    if (card == null || richText == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final sourceCard = card.cardKind == CardKind.source;
    if (widget.embedded) {
      return _buildEmbeddedBody(
        card: card,
        richText: richText,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 8),
          child: Row(
            children: [
              Text(
                sourceCard ? '编辑卡片备注' : '快捷编辑',
                style: whiteboardUiTextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              if (_dirty)
                Text(
                  _saving ? '保存中' : '未保存',
                  style: whiteboardUiTextStyle(
                    fontSize: 11,
                    color: tokens.focus,
                  ),
                ),
              IconButton(
                key: const ValueKey('wb_compact_editor_close'),
                tooltip: '关闭快捷编辑',
                onPressed: _saving ? null : _requestClose,
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.divider),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: AbsorbPointer(
              absorbing: widget.isReadonly,
              child: CardRichTextEditor(
                controller: richText,
                cardId: card.cardId,
                objectStore: RichTextObjectStore(
                    widget.repository.richTextStorage.baseDir),
                onSave: (_) => _save(),
                showToolbar: false,
                compact: true,
                readOnly: widget.isReadonly,
                autofocus: !widget.isReadonly,
                showSaveInToolbar: false,
                markSavedAfterCallback: false,
              ),
            ),
          ),
        ),
        Divider(height: 1, color: tokens.divider),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: const ValueKey('wb_compact_editor_expand'),
                onPressed: _saving ? null : _expand,
                icon: Icon(
                  sourceCard ? Icons.open_in_new_rounded : Icons.fullscreen,
                  size: 16,
                ),
                label: Text(sourceCard ? '打开来源' : '展开编辑'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const ValueKey('wb_compact_editor_save'),
                onPressed:
                    widget.isReadonly || _saving || !_dirty ? null : _save,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: Text(_saving ? '保存中' : '保存'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmbeddedBody({
    required CardContract card,
    required RichTextEditingController richText,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: ClipRect(
        child: AbsorbPointer(
          absorbing: widget.isReadonly,
          child: CardRichTextEditor(
            controller: richText,
            cardId: card.cardId,
            objectStore: RichTextObjectStore(
              widget.repository.richTextStorage.baseDir,
            ),
            onSave: (_) => _save(),
            showToolbar: false,
            compact: true,
            readOnly: widget.isReadonly,
            inlineSurface: true,
            autofocus: !widget.isReadonly,
            showSaveInToolbar: false,
            markSavedAfterCallback: false,
          ),
        ),
      ),
    );
  }
}

/// Session-only bridge between Card metadata and the one-surface editor.
///
/// The title boundary is explicit and stable for the lifetime of the editing
/// controller. It is never persisted in [RichTextDocument], so an existing
/// body H1 cannot be mistaken for the Card title and no synthetic block id is
/// created or churned across opens.
class _InlineCardDocument {
  static const _titleBoundaryKey = '_inline_card_title_boundary';

  static RichTextDocument combine({
    required String title,
    required RichTextDocument body,
  }) {
    return body.copyWith(
      blocks: [
        RichTextBlock(
          type: BlockType.heading,
          text: title,
          attrs: const {
            'level': 6,
            _titleBoundaryKey: true,
          },
        ),
        ...body.blocks,
      ],
    );
  }

  static ({String title, RichTextDocument body}) split(
    RichTextDocument combined,
  ) {
    final blocks = combined.blocks;
    if (blocks.isEmpty || blocks.first.attrs[_titleBoundaryKey] != true) {
      throw StateError('Inline Card title boundary is missing');
    }
    final bodyBlocks = blocks.skip(1).toList(growable: false);
    return (
      title: blocks.first.text,
      body: combined.copyWith(
        blocks: bodyBlocks.isEmpty
            ? const [RichTextBlock(type: BlockType.paragraph)]
            : bodyBlocks,
      ),
    );
  }
}

enum _CloseChoice { save, discard, cancel }
