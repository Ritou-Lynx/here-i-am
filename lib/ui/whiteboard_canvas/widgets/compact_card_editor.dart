/// Transient, board-local Card editor.
///
/// This surface edits the same [RichTextDocument] owned by
/// [UnifiedCardRepository]. Ordinary linear Note Cards use one transient
/// title/body text projection while embedded in a BoardItem; save splits its
/// first line back to Card.title and the remainder back to the rich-text body.
/// Complex documents and non-embedded entry points keep [CardRichTextEditor].
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

class _InlineCardDocumentController extends TextEditingController {
  _InlineCardDocumentController({required String title, required String body})
      : super(
          text: InlineCardTextProjection.compose(title: title, body: body),
        ) {
    selection = TextSelection.collapsed(offset: title.length);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? richTextBodyTextStyle(fontSize: 14);
    final firstBreak = text.indexOf('\n');
    final titleEnd = firstBreak >= 0 ? firstBreak : text.length;
    final composing = value.composing;
    final boundaries = <int>{0, titleEnd, text.length};
    if (titleEnd < text.length) boundaries.add(titleEnd + 1);
    if (withComposing && composing.isValid && !composing.isCollapsed) {
      boundaries
        ..add(composing.start.clamp(0, text.length))
        ..add(composing.end.clamp(0, text.length));
    }
    final points = boundaries.toList()..sort();
    return TextSpan(
      style: base,
      children: [
        for (var index = 0; index < points.length - 1; index++)
          if (points[index] < points[index + 1])
            TextSpan(
              text: text.substring(points[index], points[index + 1]),
              style: (points[index] < titleEnd
                      ? base.copyWith(fontWeight: FontWeight.w600)
                      : base)
                  .copyWith(
                decoration: withComposing &&
                        composing.isValid &&
                        composing.start < points[index + 1] &&
                        composing.end > points[index]
                    ? TextDecoration.underline
                    : null,
              ),
            ),
      ],
    );
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
  final FocusNode _inlineFocusNode = FocusNode(
    debugLabel: 'whiteboard inline card document',
  );
  RichTextEditingController? _richText;
  TextEditingController? _title;
  _InlineCardDocumentController? _inlineDocument;
  CardContract? _card;
  String? _error;
  String _savedTitle = '';
  String _savedInlineText = '';
  bool _saving = false;
  bool _closing = false;
  int _loadGeneration = 0;

  bool get _dirty {
    final inlineDocument = _inlineDocument;
    if (inlineDocument != null) return inlineDocument.text != _savedInlineText;
    return (_richText?.isDirty ?? false) || (_title?.text ?? '') != _savedTitle;
  }

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
      final inlineDocument = widget.embedded &&
              record.card.cardKind == CardKind.note &&
              _supportsInlineDocument(document)
          ? (_InlineCardDocumentController(
              title: record.card.title,
              body: document.blocks.map((block) => block.text).join('\n'),
            )..addListener(_handleChanged))
          : null;
      setState(() {
        _card = record.card;
        _richText = richText;
        _title = title;
        _inlineDocument = inlineDocument;
        _savedTitle = record.card.title;
        _savedInlineText = inlineDocument?.text ?? '';
      });
      if (inlineDocument != null && !widget.isReadonly) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_inlineDocument, inlineDocument)) {
            _inlineFocusNode.requestFocus();
          }
        });
      }
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
    _inlineDocument?.removeListener(_handleChanged);
    _inlineDocument?.dispose();
    _richText = null;
    _title = null;
    _inlineDocument = null;
  }

  bool _supportsInlineDocument(RichTextDocument document) =>
      document.blocks.every((block) =>
          block.children.isEmpty &&
          block.type != BlockType.image &&
          block.type != BlockType.video &&
          block.type != BlockType.reference);

  List<RichTextBlock> _projectBodyBlocks(
    List<RichTextBlock> existing,
    String body,
  ) {
    final lines = body.split('\n');
    return [
      for (var index = 0; index < lines.length; index++)
        if (index < existing.length)
          existing[index].copyWith(
            text: lines[index],
            marks: existing[index]
                .marks
                .map((mark) => mark.clamp(lines[index].length))
                .whereType<RichTextMark>()
                .toList(),
          )
        else
          RichTextBlock(type: BlockType.paragraph, text: lines[index]),
    ];
  }

  @override
  void dispose() {
    _loadGeneration++;
    FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKeyEvent);
    widget.controller?._detach(this);
    _disposeControllers();
    _inlineFocusNode.dispose();
    _surfaceFocusNode.dispose();
    super.dispose();
  }

  Future<CardContract?> _save() async {
    if (widget.isReadonly) return null;
    final controller = _richText;
    final title = _title;
    if (controller == null || title == null || _saving) return _card;
    final inlineDocument = _inlineDocument;
    if (inlineDocument != null) {
      final projection = InlineCardTextProjection.fromText(inlineDocument.text);
      title.text = projection.title;
      controller.replaceContinuousBlocks(
        _projectBodyBlocks(controller.document.blocks, projection.body),
        coalesceHistory: false,
      );
    }
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
      _savedInlineText = inlineDocument?.text ?? '';
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
      final inlineDocument = _inlineDocument;
      if (inlineDocument != null) {
        return _buildInlineNoteSurface(
          tokens: tokens,
          controller: inlineDocument,
        );
      }
      return _buildEmbeddedBody(
        tokens: tokens,
        card: card,
        richText: richText,
        title: title,
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
                showToolbar: false,
                compact: true,
                readOnly: widget.isReadonly,
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

  Widget _buildInlineNoteSurface({
    required DesktopWorkspaceTokens tokens,
    required _InlineCardDocumentController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        key: const ValueKey('wb_inline_card_document'),
        controller: controller,
        focusNode: _inlineFocusNode,
        readOnly: widget.isReadonly,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: richTextBodyTextStyle(
          color: tokens.textPrimary,
          fontSize: 14,
          height: 1.55,
        ),
        cursorColor: tokens.action,
        decoration: null,
      ),
    );
  }

  Widget _buildEmbeddedBody({
    required DesktopWorkspaceTokens tokens,
    required CardContract card,
    required RichTextEditingController richText,
    required TextEditingController title,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('wb_compact_title'),
            controller: title,
            readOnly: widget.isReadonly,
            autofocus: !widget.isReadonly,
            maxLines: 2,
            minLines: 1,
            style: whiteboardUiTextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: '卡片标题',
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
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
                  showSaveInToolbar: false,
                  markSavedAfterCallback: false,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CloseChoice { save, discard, cancel }
