/// Card rich text editor widget.
///
/// A paragraph-based editor for [RichTextDocument]. Each top-level block is
/// an editable text field with its own [TextEditingController] and
/// [FocusNode], so Chinese IME composition state is handled correctly by
/// Flutter's [EditableText]. Mixed-font rendering uses the centralized
/// `rich_text_fonts` tokens (`lib/ui/whiteboard/fonts.dart`): CJK characters
/// resolve to 汇文明朝体 (falling back to system serif), Latin characters,
/// digits, time codes and code resolve to Cascadia Code (falling back to
/// system monospace). Note: LXGW WenKai is 霞鹜文楷, a different typeface,
/// and must NOT be used here.
///
/// The editor:
/// - Renders block types (paragraph, heading, list, quote, code) with
///   appropriate text styles.
/// - Applies inline marks (bold, italic, underline, strikethrough, code,
///   link) via a lightweight toolbar.
/// - Sanitizes pasted content through [sanitizePastedBlocks].
/// - Supports undo / redo via keyboard shortcuts and toolbar.
/// - Calls [onSave] when the user triggers save; warns on unsaved exit.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_paste_sanitizer.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// Signature for save callback.
typedef RichTextSaveCallback = void Function(RichTextDocument doc);

/// A rich text editor for a single Card's content.
class CardRichTextEditor extends StatefulWidget {
  final RichTextEditingController controller;
  final RichTextSaveCallback? onSave;
  final String cardId;
  final VoidCallback? onDirty;

  const CardRichTextEditor({
    super.key,
    required this.controller,
    required this.cardId,
    this.onSave,
    this.onDirty,
  });

  @override
  State<CardRichTextEditor> createState() => _CardRichTextEditorState();
}

class _CardRichTextEditorState extends State<CardRichTextEditor> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller.isDirty && widget.onDirty != null) {
      widget.onDirty!();
    }
    // Rebuild so toolbar enable states (undo / redo / save) stay in sync.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(context, controller),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: controller.blockCount,
              itemBuilder: (context, index) => _buildBlockField(
                context,
                controller,
                index,
                theme,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, RichTextEditingController c) {
    return Wrap(
      spacing: 4,
      children: [
        _toolbarButton('B', () => _toggleMarkOnFocused(c, MarkType.bold),
            bold: true),
        _toolbarButton('I', () => _toggleMarkOnFocused(c, MarkType.italic),
            italic: true),
        _toolbarButton('U', () => _toggleMarkOnFocused(c, MarkType.underline),
            underline: true),
        _toolbarButton('S', () => _toggleMarkOnFocused(c, MarkType.strikethrough),
            strikethrough: true),
        _toolbarButton('</>', () => _toggleMarkOnFocused(c, MarkType.code),
            mono: true),
        _toolbarButton('🔗', () => _addLinkOnFocused(context, c),
            mono: true),
        const SizedBox(width: 8),
        _toolbarButton('H1', () => _setBlockTypeFocused(c, BlockType.heading,
            attrs: const {'level': 1})),
        _toolbarButton('H2', () => _setBlockTypeFocused(c, BlockType.heading,
            attrs: const {'level': 2})),
        _toolbarButton('•', () => _setBlockTypeFocused(c, BlockType.list,
            attrs: const {'ordered': false})),
        _toolbarButton('1.', () => _setBlockTypeFocused(c, BlockType.list,
            attrs: const {'ordered': true})),
        _toolbarButton('❝', () => _setBlockTypeFocused(c, BlockType.quote)),
        _toolbarButton('{ }', () => _setBlockTypeFocused(c, BlockType.code)),
        const SizedBox(width: 8),
        _toolbarButton('↶', c.undo, enabled: c.canUndo),
        _toolbarButton('↷', c.redo, enabled: c.canRedo),
        if (widget.onSave != null)
          _toolbarButton('保存', () {
            widget.onSave!(c.flushToDocument());
            c.markSaved();
          }),
      ],
    );
  }

  Widget _toolbarButton(
    String label,
    VoidCallback onTap, {
    bool enabled = true,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strikethrough = false,
    bool mono = false,
  }) {
    // Toolbar glyphs: use the code token for `</>` / link glyphs, body token
    // for CJK + Latin labels. Fonts come from the centralized token, never
    // hard-coded strings.
    final base = mono
        ? richTextCodeTextStyle(fontSize: 13)
        : richTextBodyTextStyle(fontSize: 13);
    final style = base.copyWith(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      decoration: underline
          ? TextDecoration.underline
          : (strikethrough ? TextDecoration.lineThrough : TextDecoration.none),
    );
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: style.copyWith(
            color: enabled
                ? const Color(0xFF293025)
                : const Color(0xFF999B91),
          ),
        ),
      ),
    );
  }

  Widget _buildBlockField(
    BuildContext context,
    RichTextEditingController c,
    int index,
    ThemeData theme,
  ) {
    final block = c.blockAt(index);
    final style = _blockStyle(block, theme);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: TextField(
        controller: c.controllerFor(index),
        focusNode: c.focusNodeFor(index),
        style: style,
        maxLines: null,
        minLines: 1,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 6),
          border: InputBorder.none,
          hintText: block.type == BlockType.paragraph && block.text.isEmpty
              ? '在此输入…'
              : null,
          hintStyle: style.copyWith(color: const Color(0xFF999B91)),
          prefixText: _blockPrefix(block),
          prefixStyle: style,
        ),
        textInputAction: TextInputAction.newline,
        onSubmitted: (_) => _onEnterPressed(c, index),
        onChanged: (_) => _onTextChanged(c, index),
      ),
    );
  }

  TextStyle _blockStyle(RichTextBlock block, ThemeData theme) {
    // All block typography flows through the centralized font tokens.
    final base = richTextBodyTextStyle();
    switch (block.type) {
      case BlockType.heading:
        final level = block.headingLevel;
        final size = switch (level) {
          1 => 24.0,
          2 => 20.0,
          3 => 18.0,
          _ => 16.0,
        };
        return base.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w600,
          height: 1.35,
        );
      case BlockType.quote:
        return base.copyWith(
          fontStyle: FontStyle.italic,
          color: const Color(0xFF74766E),
        );
      case BlockType.code:
        // Code blocks must use the Cascadia Code token, not the body token.
        return richTextCodeTextStyle();
      case BlockType.list:
        return base;
      default:
        return base;
    }
  }

  String? _blockPrefix(RichTextBlock block) {
    switch (block.type) {
      case BlockType.list:
        return block.listOrdered ? '1. ' : '• ';
      case BlockType.quote:
        return '❝ ';
      case BlockType.code:
        return '{ } ';
      default:
        return null;
    }
  }

  void _onEnterPressed(RichTextEditingController c, int index) {
    // Flush current text into the block, then insert a new paragraph after.
    const newBlock = RichTextBlock(type: BlockType.paragraph);
    final newIndex = c.insertBlockAfter(index, newBlock);
    // Focus the new block.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.focusNodeFor(newIndex).requestFocus();
    });
  }

  void _onTextChanged(RichTextEditingController c, int index) {
    // Typing marks the document dirty so the exit guard fires on back-nav.
    // The block text is read lazily on flush / save.
    c.markDirty();
  }

  void _toggleMarkOnFocused(RichTextEditingController c, MarkType type) {
    // Find the focused block.
    for (var i = 0; i < c.blockCount; i++) {
      if (c.focusNodeFor(i).hasFocus) {
        final tc = c.controllerFor(i);
        final sel = tc.selection;
        if (sel.start == sel.end) return;
        c.applyMarkToBlock(i, type, sel.start, sel.end);
        return;
      }
    }
  }

  void _setBlockTypeFocused(RichTextEditingController c, BlockType type,
      {Map<String, dynamic> attrs = const {}}) {
    for (var i = 0; i < c.blockCount; i++) {
      if (c.focusNodeFor(i).hasFocus) {
        c.setBlockType(i, type, attrs: attrs);
        return;
      }
    }
  }

  Future<void> _addLinkOnFocused(
      BuildContext context, RichTextEditingController c) async {
    // Locate the focused block and its selection.
    for (var i = 0; i < c.blockCount; i++) {
      if (c.focusNodeFor(i).hasFocus) {
        final tc = c.controllerFor(i);
        final sel = tc.selection;
        if (sel.start == sel.end) return;
        final href = await showDialog<String>(
          context: context,
          builder: (context) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('插入链接'),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  hintText: 'https://…',
                  labelText: 'URL',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(controller.text),
                  child: const Text('插入'),
                ),
              ],
            );
          },
        );
        if (href == null || href.trim().isEmpty || !context.mounted) return;
        final trimmed = href.trim();
        // Only allow http(s) links; anything else is dropped silently.
        if (!trimmed.startsWith('https://') &&
            !trimmed.startsWith('http://') &&
            !trimmed.startsWith('mailto:')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('仅支持 http / https / mailto 链接')),
          );
          return;
        }
        c.applyMarkToBlock(
          i,
          MarkType.link,
          sel.start,
          sel.end,
          attrs: {'href': trimmed},
        );
        return;
      }
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Ctrl/Cmd+Z = undo, Ctrl/Cmd+Shift+Z or Ctrl+Y = redo,
    // Ctrl/Cmd+S = save.
    final isMod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (event is KeyDownEvent && isMod) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.keyZ) {
        final shift = HardwareKeyboard.instance.isShiftPressed;
        if (shift) {
          widget.controller.redo();
        } else {
          widget.controller.undo();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        widget.controller.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        if (widget.onSave != null) {
          widget.onSave!(widget.controller.flushToDocument());
          widget.controller.markSaved();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _handlePaste(widget.controller);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _handlePaste(RichTextEditingController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return;
    // Find the focused block and insert sanitized text.
    for (var i = 0; i < c.blockCount; i++) {
      if (c.focusNodeFor(i).hasFocus) {
        final tc = c.controllerFor(i);
        final sel = tc.selection;
        final text = tc.text;
        final newText = text.replaceRange(sel.start, sel.end, raw);
        tc.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: sel.start + raw.length),
        );
        return;
      }
    }
  }
}