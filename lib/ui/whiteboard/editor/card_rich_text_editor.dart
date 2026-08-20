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
/// - List nesting: Tab / Shift-Tab indent / outdent list items (depth attr,
///   clamped 0–8); Enter on a list item continues the same list, Enter on an
///   empty item exits back to a paragraph.
/// - Quote blocks: Enter appends an editable child paragraph inside the
///   quote (rendered indented); Enter on an empty child removes it.
/// - Media: image / attachment import produces a stable
///   [RichTextAssetRef] (object ref), inserted as an image / reference block
///   and rendered from the object store.
/// - Calls [onSave] when the user triggers save; warns on unsaved exit.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/domain/whiteboard/rich_text_asset_ref.dart';
import 'package:memex/domain/whiteboard/rich_text_document.dart';
import 'package:memex/domain/whiteboard/rich_text_controller.dart';
import 'package:memex/domain/whiteboard/rich_text_object_store.dart';
import 'package:memex/domain/whiteboard/rich_text_paste_sanitizer.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// Signature for save callback.
typedef RichTextSaveCallback = void Function(RichTextDocument doc);

/// Media kinds the editor can import.
enum MediaImportKind { image, attachment }

/// Imports media into the object store and returns stable asset refs.
/// The editor inserts the corresponding blocks; it never touches the
/// filesystem directly (tests inject fakes here).
typedef RichTextMediaImporter = Future<List<RichTextAssetRef>> Function(
    MediaImportKind kind);

/// An editing position: a top-level block, or a child nested under one.
typedef RichTextEditPath = ({int block, int? child});

/// A rich text editor for a single Card's content.
class CardRichTextEditor extends StatefulWidget {
  final RichTextEditingController controller;
  final RichTextSaveCallback? onSave;
  final bool markSavedAfterCallback;
  final bool showSaveInToolbar;
  final String cardId;
  final VoidCallback? onDirty;

  /// Object store used to render imported media previews. When null, media
  /// blocks render as labeled chips without preview.
  final RichTextObjectStore? objectStore;

  /// Media import implementation. When null, media toolbar buttons are
  /// hidden.
  final RichTextMediaImporter? mediaImporter;

  const CardRichTextEditor({
    super.key,
    required this.controller,
    required this.cardId,
    this.onSave,
    this.markSavedAfterCallback = true,
    this.showSaveInToolbar = true,
    this.onDirty,
    this.objectStore,
    this.mediaImporter,
  });

  @override
  State<CardRichTextEditor> createState() => _CardRichTextEditorState();
}

class _CardRichTextEditorState extends State<CardRichTextEditor> {
  /// The most recently focused edit path. Desktop toolbars steal focus on
  /// tap (InkWell requests focus on tap-down), so toolbar handlers use this
  /// as a fallback when [_focusedPath] is already empty by the time the
  /// button's onTap runs.
  RichTextEditPath? _lastFocusedPath;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    // Track the last focused edit path across pure focus changes (taps
    // without typing), so desktop toolbar taps can target the right field.
    FocusManager.instance.addListener(_onGlobalFocusChanged);
    // Multiline EditableText consumes the Enter key before any ancestor
    // Focus can see it, so Enter-to-structure (list sibling / quote child)
    // must be intercepted before focus dispatch. The early handler is
    // scoped: it only acts while one of our fields is focused and has no
    // active IME composing region.
    FocusManager.instance.addEarlyKeyEventHandler(_onEarlyKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onEarlyKeyEvent);
    FocusManager.instance.removeListener(_onGlobalFocusChanged);
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onGlobalFocusChanged() {
    final path = _focusedPath(widget.controller);
    if (path != null) _lastFocusedPath = path;
  }

  KeyEventResult _onEarlyKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final hw = HardwareKeyboard.instance;
    if (hw.isShiftPressed ||
        hw.isControlPressed ||
        hw.isMetaPressed ||
        hw.isAltPressed) {
      // Shift+Enter = soft newline; modifiers leave to the field.
      return KeyEventResult.ignored;
    }
    final c = widget.controller;
    final path = _focusedPath(c);
    if (path == null) return KeyEventResult.ignored;
    final tc = path.child == null
        ? c.controllerFor(path.block)
        : c.childControllerFor(path.block, path.child!);
    if (tc.value.composing.isValid) {
      // IME composing: let EditableText commit the composition.
      return KeyEventResult.ignored;
    }
    _onEnterPressed(c, path);
    return KeyEventResult.handled;
  }

  void _onControllerChanged() {
    if (widget.controller.isDirty && widget.onDirty != null) {
      widget.onDirty!();
    }
    // Track the last focused edit path (typing implies a focused field).
    final focused = _focusedPath(widget.controller);
    if (focused != null) _lastFocusedPath = focused;
    // Rebuild so toolbar enable states (undo / redo / save) stay in sync.
    if (mounted) setState(() {});
  }

  /// The path toolbar actions should target: the currently focused field, or
  /// the last known one when a desktop button stole focus.
  RichTextEditPath? _actionPath(RichTextEditingController c) =>
      _focusedPath(c) ?? _lastFocusedPath;

  /// Returns the currently focused editing position, or null. Defensive:
  /// focus nodes may be mid-disposal when this runs from a global focus
  /// notification during [RichTextEditingController] state sync.
  RichTextEditPath? _focusedPath(RichTextEditingController c) {
    try {
      for (var i = 0; i < c.blockCount; i++) {
        if (c.focusNodeFor(i).hasFocus) return (block: i, child: null);
        for (var j = 0; j < c.childCount(i); j++) {
          if (c.childFocusNodeFor(i, j).hasFocus) {
            return (block: i, child: j);
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  RichTextBlock _blockAt(RichTextEditingController c, RichTextEditPath path) =>
      path.child == null
          ? c.blockAt(path.block)
          : c.childBlockAt(path.block, path.child!);

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Focus(
      onKeyEvent: _onKeyEvent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(context, controller),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: controller.blockCount,
              itemBuilder: (context, index) =>
                  _buildBlockItem(context, controller, index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, RichTextEditingController c) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Container(
      key: const ValueKey('rich_text_toolbar'),
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.divider),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _toolbarButton(
              tokens, 'B', '加粗', () => _toggleMarkOnFocused(c, MarkType.bold),
              bold: true),
          _toolbarButton(
              tokens, 'I', '斜体', () => _toggleMarkOnFocused(c, MarkType.italic),
              italic: true),
          _toolbarButton(tokens, 'U', '下划线',
              () => _toggleMarkOnFocused(c, MarkType.underline),
              underline: true),
          _toolbarButton(tokens, 'S', '删除线',
              () => _toggleMarkOnFocused(c, MarkType.strikethrough),
              strikethrough: true),
          _toolbarButton(tokens, '</>', '行内代码',
              () => _toggleMarkOnFocused(c, MarkType.code),
              mono: true),
          _toolbarIconButton(
            tokens,
            Icons.link_rounded,
            '插入链接',
            () => _addLinkOnFocused(context, c),
          ),
          const SizedBox(width: 4),
          _toolbarButton(
              tokens,
              'H1',
              '一级标题',
              () => _setBlockTypeFocused(c, BlockType.heading,
                  attrs: const {'level': 1})),
          _toolbarButton(
              tokens,
              'H2',
              '二级标题',
              () => _setBlockTypeFocused(c, BlockType.heading,
                  attrs: const {'level': 2})),
          _toolbarButton(
              tokens,
              '•',
              '无序列表',
              () => _setBlockTypeFocused(c, BlockType.list,
                  attrs: const {'ordered': false})),
          _toolbarButton(
              tokens,
              '1.',
              '有序列表',
              () => _setBlockTypeFocused(c, BlockType.list,
                  attrs: const {'ordered': true})),
          _toolbarIconButton(
            tokens,
            Icons.format_quote_rounded,
            '引用',
            () => _setBlockTypeFocused(c, BlockType.quote),
          ),
          _toolbarButton(tokens, '{ }', '代码块',
              () => _setBlockTypeFocused(c, BlockType.code),
              mono: true),
          const SizedBox(width: 4),
          _toolbarIconButton(
            tokens,
            Icons.format_indent_increase_rounded,
            '缩进',
            () => _indentOnFocused(c, outdent: false),
          ),
          _toolbarIconButton(
            tokens,
            Icons.format_indent_decrease_rounded,
            '减少缩进',
            () => _indentOnFocused(c, outdent: true),
          ),
          if (widget.mediaImporter != null) ...[
            const SizedBox(width: 4),
            _toolbarIconButton(
              tokens,
              Icons.image_outlined,
              '导入图片',
              () => _importMedia(c, MediaImportKind.image),
            ),
            _toolbarIconButton(
              tokens,
              Icons.attach_file_rounded,
              '导入附件',
              () => _importMedia(c, MediaImportKind.attachment),
            ),
          ],
          const SizedBox(width: 4),
          _toolbarIconButton(
            tokens,
            Icons.undo_rounded,
            '撤销',
            c.undo,
            enabled: c.canUndo,
          ),
          _toolbarIconButton(
            tokens,
            Icons.redo_rounded,
            '重做',
            c.redo,
            enabled: c.canRedo,
          ),
          if (widget.onSave != null && widget.showSaveInToolbar)
            _toolbarButton(tokens, '保存', '保存（Ctrl+S）', () {
              widget.onSave!(c.flushToDocument());
              if (widget.markSavedAfterCallback) c.markSaved();
            }),
        ],
      ),
    );
  }

  Widget _toolbarButton(
    DesktopWorkspaceTokens tokens,
    String label,
    String tooltip,
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
    return Tooltip(
      message: tooltip,
      child: TextButton(
        onPressed: enabled ? onTap : null,
        style: _toolbarControlStyle(tokens),
        child: Text(
          label,
          style: style.copyWith(
            color: enabled ? tokens.textPrimary : tokens.textFaint,
          ),
        ),
      ),
    );
  }

  Widget _toolbarIconButton(
    DesktopWorkspaceTokens tokens,
    IconData icon,
    String tooltip,
    VoidCallback onTap, {
    bool enabled = true,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      style: _toolbarControlStyle(tokens),
    );
  }

  ButtonStyle _toolbarControlStyle(DesktopWorkspaceTokens tokens) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(36, 36)),
      maximumSize: const WidgetStatePropertyAll(Size(96, 36)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return tokens.textFaint;
        return tokens.textPrimary;
      }),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return tokens.actionSoft.withValues(alpha: 0.34);
        }
        if (states.contains(WidgetState.hovered)) {
          return tokens.actionSoft.withValues(alpha: 0.18);
        }
        return Colors.transparent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(color: tokens.action, width: 1.5);
        }
        return BorderSide(color: tokens.divider);
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  /// A top-level block: its field, plus quote children rendered beneath.
  Widget _buildBlockItem(
    BuildContext context,
    RichTextEditingController c,
    int index,
  ) {
    final block = c.blockAt(index);
    final childCount = c.childCount(index);
    final children = <Widget>[
      _buildBlockField(context, c, index, null),
    ];
    if (block.type == BlockType.quote && childCount > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = 0; j < childCount; j++)
                _buildBlockField(context, c, index, j),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildBlockField(
    BuildContext context,
    RichTextEditingController c,
    int blockIndex,
    int? childIndex,
  ) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final block = childIndex == null
        ? c.blockAt(blockIndex)
        : c.childBlockAt(blockIndex, childIndex);
    if (block.type == BlockType.image ||
        block.type == BlockType.video ||
        block.type == BlockType.reference) {
      return _buildMediaBlock(context, c, blockIndex, childIndex, block);
    }
    final style = _blockStyle(block, tokens);
    return TextField(
      key: ValueKey('rich_text_block_${blockIndex}_${childIndex ?? 'root'}'),
      controller: childIndex == null
          ? c.controllerFor(blockIndex)
          : c.childControllerFor(blockIndex, childIndex),
      focusNode: childIndex == null
          ? c.focusNodeFor(blockIndex)
          : c.childFocusNodeFor(blockIndex, childIndex),
      style: style,
      cursorColor: tokens.action,
      maxLines: null,
      minLines: 1,
      decoration: InputDecoration(
        isDense: true,
        filled: block.type == BlockType.code,
        fillColor: block.type == BlockType.code ? tokens.surface : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: tokens.action, width: 1.5),
        ),
        hintText: block.type == BlockType.paragraph && block.text.isEmpty
            ? '在此输入…'
            : null,
        hintStyle: style.copyWith(color: tokens.textFaint),
        prefixText: _blockPrefix(block),
        prefixStyle: style,
      ),
      textInputAction: TextInputAction.newline,
      onSubmitted: (_) =>
          _onEnterPressed(c, (block: blockIndex, child: childIndex)),
      onChanged: (_) => c.markDirty(),
    );
  }

  /// Media / attachment block: preview (when resolvable) + label + delete.
  Widget _buildMediaBlock(
    BuildContext context,
    RichTextEditingController c,
    int blockIndex,
    int? childIndex,
    RichTextBlock block,
  ) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final ref = c.document.assetRefById(block.assetRefId ?? '');
    final isImage = block.type == BlockType.image;
    final label = isImage
        ? ((block.attrs['alt'] as String?)?.isNotEmpty == true
            ? block.attrs['alt'] as String
            : ((block.attrs['caption'] as String?)?.isNotEmpty == true
                ? block.attrs['caption'] as String
                : '图片'))
        : ((block.attrs['label'] as String?)?.isNotEmpty == true
            ? block.attrs['label'] as String
            : (block.text.isNotEmpty ? block.text : '附件'));

    Widget preview;
    final file = (ref != null && widget.objectStore != null)
        ? widget.objectStore!.resolveFile(ref)
        : null;
    if (isImage && file != null) {
      preview = SizedBox(
        width: 140,
        height: 92,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.broken_image_outlined,
              color: tokens.textFaint,
              size: 32,
            ),
          ),
        ),
      );
    } else {
      preview = Icon(
        isImage ? Icons.image_outlined : Icons.attach_file,
        size: 28,
        color: tokens.textMuted,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            preview,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: richTextBodyTextStyle(
                  fontSize: 13,
                  color: tokens.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => _deleteMediaBlock(c, blockIndex, childIndex),
              tooltip: isImage ? '删除图片' : '删除附件',
              icon: const Icon(Icons.close_rounded, size: 16),
              color: tokens.textMuted,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _deleteMediaBlock(
      RichTextEditingController c, int blockIndex, int? childIndex) {
    if (childIndex != null) {
      c.deleteChild(blockIndex, childIndex);
    } else {
      c.deleteBlock(blockIndex);
    }
  }

  TextStyle _blockStyle(
    RichTextBlock block,
    DesktopWorkspaceTokens tokens,
  ) {
    // All block typography flows through the centralized font tokens.
    final base = richTextBodyTextStyle(
      color: tokens.textPrimary,
      height: 1.65,
    );
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
          color: tokens.textMuted,
        );
      case BlockType.code:
        // Code blocks must use the Cascadia Code token, not the body token.
        return richTextCodeTextStyle(
          color: tokens.textPrimary,
          height: 1.55,
        );
      case BlockType.list:
        return base;
      default:
        return base;
    }
  }

  String? _blockPrefix(RichTextBlock block) {
    switch (block.type) {
      case BlockType.list:
        final marker = block.listOrdered ? '1. ' : '• ';
        final depthIndent = '  ' * block.listDepth;
        return '$depthIndent$marker';
      case BlockType.quote:
        return '“ ';
      case BlockType.code:
        return '{ } ';
      default:
        return null;
    }
  }

  void _onEnterPressed(RichTextEditingController c, RichTextEditPath path) {
    final isChild = path.child != null;
    final block = _blockAt(c, path);
    // Check the live field text (the state block may be stale mid-typing).
    final liveText = isChild
        ? c.childControllerFor(path.block, path.child!).text
        : c.controllerFor(path.block).text;
    if (isChild) {
      // Quote child: Enter continues the child list; Enter on an empty
      // child removes it (exit the quote).
      if (liveText.isEmpty) {
        c.deleteChild(path.block, path.child!);
        return;
      }
      final idx = c.insertChildAfter(
        path.block,
        path.child!,
        const RichTextBlock(type: BlockType.paragraph),
      );
      _focusChild(path.block, idx);
      return;
    }
    switch (block.type) {
      case BlockType.list:
        if (liveText.isEmpty) {
          // Empty list item + Enter exits the list back to a paragraph.
          c.setBlockType(path.block, BlockType.paragraph);
          return;
        }
        // Continue the same list with the same depth and marker.
        final idx = c.insertBlockAfter(
          path.block,
          RichTextBlock(
            type: BlockType.list,
            attrs: {'ordered': block.listOrdered, 'depth': block.listDepth},
          ),
        );
        _focusBlock(idx);
        break;
      case BlockType.quote:
        // Enter appends an editable child paragraph inside the quote.
        final idx = c.insertChildAfter(
          path.block,
          c.childCount(path.block) - 1,
          const RichTextBlock(type: BlockType.paragraph),
        );
        _focusChild(path.block, idx);
        break;
      default:
        final idx = c.insertBlockAfter(
          path.block,
          const RichTextBlock(type: BlockType.paragraph),
        );
        _focusBlock(idx);
    }
  }

  void _focusBlock(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.focusNodeFor(index).requestFocus();
    });
  }

  void _focusChild(int parentIndex, int childIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller
          .childFocusNodeFor(parentIndex, childIndex)
          .requestFocus();
    });
  }

  void _toggleMarkOnFocused(RichTextEditingController c, MarkType type) {
    final path = _actionPath(c);
    if (path == null) return;
    final tc = path.child == null
        ? c.controllerFor(path.block)
        : c.childControllerFor(path.block, path.child!);
    final sel = tc.selection;
    if (sel.start == sel.end) return;
    if (path.child == null) {
      c.applyMarkToBlock(path.block, type, sel.start, sel.end);
    } else {
      c.applyMarkToChild(path.block, path.child!, type, sel.start, sel.end);
    }
    // Desktop toolbars steal focus on tap; give the field back so the user
    // can keep typing (and Tab/Enter keep working on the block).
    _restoreFieldFocus(path);
  }

  void _setBlockTypeFocused(RichTextEditingController c, BlockType type,
      {Map<String, dynamic> attrs = const {}}) {
    final path = _actionPath(c);
    if (path == null) return;
    if (path.child == null) {
      c.setBlockType(path.block, type, attrs: attrs);
    } else {
      c.setChildBlockType(path.block, path.child!, type, attrs: attrs);
    }
    _restoreFieldFocus(path);
  }

  void _indentOnFocused(RichTextEditingController c, {required bool outdent}) {
    final path = _actionPath(c);
    if (path == null) return;
    if (outdent) {
      c.outdentListBlock(path.block, childIndex: path.child);
    } else {
      c.indentListBlock(path.block, childIndex: path.child);
    }
    _restoreFieldFocus(path);
  }

  /// Re-requests focus on the field at [path] after a toolbar action, so a
  /// desktop click that focused the button does not strand the user.
  void _restoreFieldFocus(RichTextEditPath path) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.controller;
      if (path.child == null) {
        if (path.block < c.blockCount) {
          c.focusNodeFor(path.block).requestFocus();
        }
      } else if (path.block < c.blockCount &&
          path.child! < c.childCount(path.block)) {
        c.childFocusNodeFor(path.block, path.child!).requestFocus();
      }
    });
  }

  Future<void> _addLinkOnFocused(
      BuildContext context, RichTextEditingController c) async {
    final tokens = DesktopWorkspaceTokens.of(context);
    final path = _actionPath(c);
    if (path == null) return;
    final tc = path.child == null
        ? c.controllerFor(path.block)
        : c.childControllerFor(path.block, path.child!);
    final sel = tc.selection;
    if (sel.start == sel.end) return;
    final linkController = TextEditingController();
    final href = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: tokens.surfaceRaised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            '插入链接',
            style: whiteboardUiTextStyle(
              fontSize: 18,
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: TextField(
            controller: linkController,
            autofocus: true,
            keyboardType: TextInputType.url,
            style: richTextCodeTextStyle(
              fontSize: 13,
              color: tokens.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'http(s)://',
              labelText: 'URL',
              filled: true,
              fillColor: tokens.surface,
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tokens.action, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: tokens.divider),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(linkController.text),
              style: FilledButton.styleFrom(
                backgroundColor: tokens.action,
                foregroundColor: tokens.canvas,
              ),
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
    if (path.child == null) {
      c.applyMarkToBlock(
        path.block,
        MarkType.link,
        sel.start,
        sel.end,
        attrs: {'href': trimmed},
      );
    } else {
      c.applyMarkToChild(
        path.block,
        path.child!,
        MarkType.link,
        sel.start,
        sel.end,
        attrs: {'href': trimmed},
      );
    }
  }

  Future<void> _importMedia(
      RichTextEditingController c, MediaImportKind kind) async {
    final importer = widget.mediaImporter;
    if (importer == null) return;
    final refs = await importer(kind);
    if (refs.isEmpty) return;
    final focused = _focusedPath(c);
    var insertAt = focused?.block ?? c.blockCount - 1;
    var lastIndex = insertAt;
    for (final ref in refs) {
      c.appendAssetRef(ref);
      final block = kind == MediaImportKind.image
          ? RichTextBlock(
              type: BlockType.image,
              attrs: {
                'asset_ref_id': ref.refId,
                'alt': ref.alt ?? '',
                if (ref.caption != null && ref.caption!.isNotEmpty)
                  'caption': ref.caption,
              },
            )
          : RichTextBlock(
              type: BlockType.reference,
              text: ref.alt ?? ref.caption ?? '附件',
              attrs: {
                'asset_ref_id': ref.refId,
                'label': ref.alt ?? ref.caption ?? '附件',
              },
            );
      lastIndex = c.insertBlockAfter(lastIndex, block);
    }
    _focusBlock(lastIndex);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // Ctrl/Cmd+Z = undo, Ctrl/Cmd+Shift+Z or Ctrl+Y = redo,
    // Ctrl/Cmd+S = save, Tab / Shift+Tab = list indent / outdent.
    final isMod = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (event is KeyDownEvent) {
      if (isMod) {
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
            if (widget.markSavedAfterCallback) {
              widget.controller.markSaved();
            }
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyV) {
          _handlePaste(widget.controller);
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        // Tab / Shift+Tab: nest / un-nest the focused list item. Only
        // intercepted when the focused block is a list; otherwise the event
        // is ignored so normal focus traversal still works.
        final c = widget.controller;
        final path = _focusedPath(c);
        if (path == null) return KeyEventResult.ignored;
        final block = _blockAt(c, path);
        if (block.type != BlockType.list) return KeyEventResult.ignored;
        final shift = HardwareKeyboard.instance.isShiftPressed;
        if (shift) {
          c.outdentListBlock(path.block, childIndex: path.child);
        } else {
          c.indentListBlock(path.block, childIndex: path.child);
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _handlePaste(RichTextEditingController c) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return;
    final sanitized = sanitizePastedBlocks([
      RichTextBlock(type: BlockType.paragraph, text: raw),
    ]).blocks.first.text;
    // Find the focused block and insert sanitized text.
    final path = _focusedPath(c);
    if (path == null) return;
    final tc = path.child == null
        ? c.controllerFor(path.block)
        : c.childControllerFor(path.block, path.child!);
    final sel = tc.selection;
    final text = tc.text;
    final newText = text.replaceRange(sel.start, sel.end, sanitized);
    tc.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + sanitized.length),
    );
  }
}
