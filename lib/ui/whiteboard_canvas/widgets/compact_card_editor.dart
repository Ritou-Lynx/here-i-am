/// Transient, board-local Card editor.
///
/// This surface edits the same [RichTextDocument] owned by
/// [UnifiedCardRepository]. It deliberately reuses [CardRichTextEditor]
/// instead of maintaining a second plain-text representation, so opening a
/// Card on the canvas cannot flatten headings, marks, media, or attachments.
library;

import 'package:flutter/material.dart';

import 'package:memex/data/whiteboard/unified_card_repository.dart';
import 'package:memex/domain/whiteboard/card_contract.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/editor/card_rich_text_editor.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class CompactCardEditor extends StatefulWidget {
  const CompactCardEditor({
    super.key,
    required this.cardId,
    required this.repository,
    required this.onSaved,
    required this.onClose,
    required this.onExpand,
    this.isReadonly = false,
    this.embedded = false,
  });

  final String cardId;
  final UnifiedCardRepository repository;
  final ValueChanged<CardContract> onSaved;
  final VoidCallback onClose;
  final ValueChanged<CardContract> onExpand;
  final bool isReadonly;
  final bool embedded;

  @override
  State<CompactCardEditor> createState() => _CompactCardEditorState();
}

class _CompactCardEditorState extends State<CompactCardEditor> {
  RichTextEditingController? _richText;
  TextEditingController? _title;
  CardContract? _card;
  String? _error;
  String _savedTitle = '';
  bool _saving = false;
  int _loadGeneration = 0;

  bool get _dirty =>
      (_richText?.isDirty ?? false) || (_title?.text ?? '') != _savedTitle;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompactCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      final document = record.document ??
          RichTextDocument(
            blocks: [
              RichTextBlock(
                type: BlockType.paragraph,
                text: record.card.body,
              ),
            ],
          );
      final richText = RichTextEditingController(document)
        ..addListener(_handleChanged);
      final title = TextEditingController(text: record.card.title)
        ..addListener(_handleChanged);
      setState(() {
        _card = record.card;
        _richText = richText;
        _title = title;
        _savedTitle = record.card.title;
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
    _title?.removeListener(_handleChanged);
    _title?.dispose();
    _richText = null;
    _title = null;
  }

  @override
  void dispose() {
    _loadGeneration++;
    _disposeControllers();
    super.dispose();
  }

  Future<CardContract?> _save() async {
    if (widget.isReadonly) return null;
    final controller = _richText;
    final title = _title;
    if (controller == null || title == null || _saving) return _card;
    setState(() => _saving = true);
    try {
      final updated = await widget.repository.saveRichText(
        widget.cardId,
        controller.flushToDocument(),
        title: title.text,
      );
      if (!mounted) return updated;
      controller.markSaved();
      _savedTitle = updated.title;
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

  Future<void> _expand() async {
    CardContract? card = _card;
    if (_dirty) card = await _save();
    if (!mounted || card == null) return;
    widget.onExpand(card);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      key: const ValueKey('wb_compact_card_editor'),
      color: tokens.surfaceRaised,
      elevation: widget.embedded ? 0 : 10,
      shadowColor: tokens.textPrimary.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(widget.embedded ? 0 : 10),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.divider),
          borderRadius: BorderRadius.circular(widget.embedded ? 0 : 10),
        ),
        child: _buildBody(tokens),
      ),
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
    final title = _title;
    if (card == null || richText == null || title == null) {
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
        tokens: tokens,
        card: card,
        richText: richText,
        title: title,
        sourceCard: sourceCard,
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
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            key: const ValueKey('wb_compact_title'),
            controller: title,
            readOnly: widget.isReadonly,
            autofocus: !widget.isReadonly,
            style: whiteboardUiTextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: '卡片标题',
              filled: true,
              fillColor: tokens.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: tokens.divider),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: AbsorbPointer(
              absorbing: widget.isReadonly,
              child: CardRichTextEditor(
                controller: richText,
                cardId: card.cardId,
                objectStore: RichTextObjectStore(
                    widget.repository.richTextStorage.baseDir),
                onSave: (_) => _save(),
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
    required DesktopWorkspaceTokens tokens,
    required CardContract card,
    required RichTextEditingController richText,
    required TextEditingController title,
    required bool sourceCard,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 42,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('wb_compact_title'),
                  controller: title,
                  readOnly: widget.isReadonly,
                  autofocus: !widget.isReadonly,
                  style: whiteboardUiTextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '卡片标题',
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (_dirty)
                IconButton(
                  key: const ValueKey('wb_compact_editor_save'),
                  tooltip: _saving ? '保存中' : '保存',
                  onPressed: widget.isReadonly || _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded, size: 17),
                ),
              IconButton(
                key: const ValueKey('wb_compact_editor_expand'),
                tooltip: sourceCard ? '打开来源' : '全屏编辑',
                onPressed: _saving ? null : _expand,
                icon: Icon(
                  sourceCard ? Icons.open_in_new_rounded : Icons.fullscreen,
                  size: 17,
                ),
              ),
              IconButton(
                key: const ValueKey('wb_compact_editor_close'),
                tooltip: '关闭原位编辑',
                onPressed: _saving ? null : _requestClose,
                icon: const Icon(Icons.close_rounded, size: 17),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: tokens.divider),
        Expanded(
          child: AbsorbPointer(
            absorbing: widget.isReadonly,
            child: CardRichTextEditor(
              controller: richText,
              cardId: card.cardId,
              objectStore: RichTextObjectStore(
                widget.repository.richTextStorage.baseDir,
              ),
              onSave: (_) => _save(),
              showSaveInToolbar: false,
              markSavedAfterCallback: false,
            ),
          ),
        ),
      ],
    );
  }
}

enum _CloseChoice { save, discard, cancel }
