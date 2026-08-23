import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// Explicit Card-tag editor backed by the Card metadata truth.
///
/// A tag is created only after the user presses Enter, chooses a suggestion,
/// or presses the add button. Body text containing `#...` is never scanned.
class CardTagField extends StatefulWidget {
  const CardTagField({
    super.key,
    required this.tags,
    required this.onChanged,
    this.suggestions = const [],
    this.enabled = true,
    this.label = '标签',
  });

  final List<String> tags;
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  final String label;

  @override
  State<CardTagField> createState() => _CardTagFieldState();
}

class _CardTagFieldState extends State<CardTagField> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode(debugLabel: 'card-tag-input');
  late List<String> _tags = _normalizeMany(widget.tags);

  @override
  void didUpdateWidget(covariant CardTagField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _normalizeMany(widget.tags);
    if (!_sameTags(_tags, next)) _tags = next;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _commit([String? value]) {
    if (!widget.enabled) return;
    final tag = _normalizeOne(value ?? _inputController.text);
    if (tag == null) {
      _inputController.clear();
      return;
    }
    if (_tags.any((existing) => _fold(existing) == _fold(tag))) {
      _inputController.clear();
      return;
    }
    setState(() {
      _tags = [..._tags, tag];
      _inputController.clear();
    });
    widget.onChanged(List.unmodifiable(_tags));
  }

  void _removeAt(int index) {
    if (!widget.enabled) return;
    setState(() => _tags = [..._tags]..removeAt(index));
    widget.onChanged(List.unmodifiable(_tags));
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _inputController.text.isNotEmpty) {
      _inputController.clear();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _inputController.text.isEmpty &&
        _tags.isNotEmpty) {
      _removeAt(_tags.length - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Iterable<String> _options(TextEditingValue value) {
    final needle = _fold(_normalizeOne(value.text) ?? '');
    final selected = _tags.map(_fold).toSet();
    final candidates = <String>[];
    final seen = <String>{};
    for (final raw in widget.suggestions) {
      final candidate = _normalizeOne(raw);
      if (candidate == null) continue;
      final folded = _fold(candidate);
      if (selected.contains(folded) || !seen.add(folded)) continue;
      if (needle.isEmpty || folded.contains(needle)) candidates.add(candidate);
    }
    candidates.sort((left, right) => _fold(left).compareTo(_fold(right)));
    return candidates.take(8);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Semantics(
      container: true,
      label: widget.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: whiteboardUiTextStyle(
                  color: tokens.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '输入后确认，不会从正文自动提取',
                style: whiteboardUiTextStyle(
                  color: tokens.textFaint,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (var index = 0; index < _tags.length; index++)
                  _TagChip(
                    tag: _tags[index],
                    enabled: widget.enabled,
                    onDeleted: () => _removeAt(index),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Focus(
            onKeyEvent: _handleKey,
            child: RawAutocomplete<String>(
              textEditingController: _inputController,
              focusNode: _inputFocusNode,
              optionsBuilder: _options,
              displayStringForOption: (option) => option,
              onSelected: _commit,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                    return TextField(
                      key: const ValueKey('card-tag-input'),
                      controller: controller,
                      focusNode: focusNode,
                      enabled: widget.enabled,
                      textInputAction: TextInputAction.done,
                      style: whiteboardUiTextStyle(
                        color: tokens.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '输入 #标签 或标签文字，按 Enter 确认',
                        hintStyle: whiteboardUiTextStyle(
                          color: tokens.textFaint,
                          fontSize: 12,
                        ),
                        filled: true,
                        fillColor: tokens.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        suffixIcon: IconButton(
                          key: const ValueKey('card-tag-add'),
                          tooltip: '添加标签',
                          onPressed: widget.enabled ? _commit : null,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          color: tokens.action,
                        ),
                        border: _border(tokens.divider),
                        enabledBorder: _border(tokens.divider),
                        focusedBorder: _border(tokens.action, width: 1.4),
                      ),
                      onSubmitted: (_) {
                        onFieldSubmitted();
                        if (_inputController.text.trim().isNotEmpty) _commit();
                      },
                    );
                  },
              optionsViewBuilder: (context, onSelected, options) {
                final values = options.toList();
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: tokens.surfaceRaised,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 360,
                        maxHeight: 220,
                      ),
                      child: ListView.builder(
                        key: const ValueKey('card-tag-options'),
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: values.length,
                        itemBuilder: (context, index) {
                          final value = values[index];
                          final highlighted =
                              AutocompleteHighlightedOption.of(context) ==
                              index;
                          return InkWell(
                            onTap: () => onSelected(value),
                            child: Container(
                              color: highlighted ? tokens.actionSoft : null,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              child: Text(
                                '#$value',
                                style: whiteboardUiTextStyle(
                                  color: tokens.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: color, width: width),
      );

  static String _fold(String value) => value.toLowerCase();

  static String? _normalizeOne(String value) {
    var normalized = value.trim();
    while (normalized.startsWith('#')) {
      normalized = normalized.substring(1).trimLeft();
    }
    normalized = normalized.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static List<String> _normalizeMany(Iterable<String> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      final normalized = _normalizeOne(value);
      if (normalized == null || !seen.add(_fold(normalized))) continue;
      result.add(normalized);
    }
    return result;
  }

  static bool _sameTags(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.enabled,
    required this.onDeleted,
  });

  final String tag;
  final bool enabled;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final keySuffix = tag.trim().toLowerCase();
    return Container(
      key: ValueKey('card-tag-chip-$keySuffix'),
      decoration: BoxDecoration(
        color: tokens.actionSoft,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: tokens.action.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.only(left: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$tag',
            style: whiteboardUiTextStyle(
              color: tokens.textPrimary,
              fontSize: 12,
            ),
          ),
          IconButton(
            key: ValueKey('card-tag-delete-$keySuffix'),
            tooltip: '删除标签 $tag',
            onPressed: enabled ? onDeleted : null,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close_rounded, size: 14),
            color: tokens.textMuted,
          ),
        ],
      ),
    );
  }
}
