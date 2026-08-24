/// Desktop-only presentation for the primary Persona chat.
///
/// This widget deliberately owns no conversation state and performs no data
/// access. [PersonaChatScreen] supplies the real persisted messages, composer,
/// streaming state, and send callback; this file only renders them as the
/// frameless Web-prototype popover used by the desktop workspace.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:memex/data/services/persona_reply_sanitizer.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/workbench_action_card.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class DesktopPersonaChatView extends StatelessWidget {
  const DesktopPersonaChatView({
    super.key,
    required this.loading,
    required this.messagesNewestFirst,
    required this.isStreaming,
    required this.streamingText,
    required this.controller,
    required this.composerFocusNode,
    required this.scrollController,
    required this.onSend,
    this.onStop,
    this.temporaryContextLabel,
    this.canUndoWorkbenchAction,
    this.onUndoWorkbenchAction,
  });

  final bool loading;
  final List<PersonaChatMessage> messagesNewestFirst;
  final bool isStreaming;
  final String streamingText;
  final TextEditingController controller;
  final FocusNode composerFocusNode;
  final ScrollController scrollController;
  final Future<void> Function() onSend;
  final Future<void> Function()? onStop;
  final String? temporaryContextLabel;
  final bool Function(String actionId)? canUndoWorkbenchAction;
  final WorkbenchActionUndo? onUndoWorkbenchAction;

  @override
  Widget build(BuildContext context) {
    final contextLabel = temporaryContextLabel?.trim();
    final preferredHeight = _preferredPopoverHeight(
      loading: loading,
      messagesNewestFirst: messagesNewestFirst,
      isStreaming: isStreaming,
      streamingText: streamingText,
      hasContextLabel: contextLabel != null && contextLabel.isNotEmpty,
    );
    final content = Material(
      type: MaterialType.transparency,
      child: Semantics(
        key: const ValueKey('desktop_chat_conversation'),
        container: true,
        label: '林埃悬浮对话',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (contextLabel != null && contextLabel.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerRight,
                child: _DesktopContextChip(label: contextLabel),
              ),
              const SizedBox(height: 9),
            ],
            Expanded(
              child: _DesktopMessageList(
                loading: loading,
                messagesNewestFirst: messagesNewestFirst,
                isStreaming: isStreaming,
                streamingText: streamingText,
                scrollController: scrollController,
                canUndoWorkbenchAction: canUndoWorkbenchAction,
                onUndoWorkbenchAction: onUndoWorkbenchAction,
              ),
            ),
            const SizedBox(height: 9),
            _DesktopComposer(
              controller: controller,
              focusNode: composerFocusNode,
              enabled: !loading,
              isStreaming: isStreaming,
              onSend: onSend,
              onStop: onStop,
            ),
          ],
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : preferredHeight;
        return SizedBox(
          height: math.min(preferredHeight, maxHeight),
          child: content,
        );
      },
    );
  }
}

class _DesktopContextChip extends StatelessWidget {
  const _DesktopContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return DecoratedBox(
      key: const ValueKey('desktop_chat_temporary_context'),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.divider),
        borderRadius: BorderRadius.circular(999),
        boxShadow: _desktopChatShadow(tokens),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '当前 · $label · 仅本次上下文',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: whiteboardUiTextStyle(
            fontSize: 11,
            color: tokens.textMuted,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _DesktopMessageList extends StatelessWidget {
  const _DesktopMessageList({
    required this.loading,
    required this.messagesNewestFirst,
    required this.isStreaming,
    required this.streamingText,
    required this.scrollController,
    this.canUndoWorkbenchAction,
    this.onUndoWorkbenchAction,
  });

  final bool loading;
  final List<PersonaChatMessage> messagesNewestFirst;
  final bool isStreaming;
  final String streamingText;
  final ScrollController scrollController;
  final bool Function(String actionId)? canUndoWorkbenchAction;
  final WorkbenchActionUndo? onUndoWorkbenchAction;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Row(
        children: [
          Flexible(
            child: _DesktopChatBubble(
              text: '正在连接林埃…',
              fromUser: false,
            ),
          ),
        ],
      );
    }

    final hasStreamingItem = isStreaming;
    final itemCount = messagesNewestFirst.length + (hasStreamingItem ? 1 : 0);
    if (itemCount == 0) {
      return const Row(
        children: [
          Flexible(
            child: _DesktopChatBubble(
              text: '开始和林埃对话',
              fromUser: false,
              muted: true,
            ),
          ),
        ],
      );
    }

    return ScrollConfiguration(
      behavior: const _DesktopChatScrollBehavior(),
      child: ListView.builder(
        key: const ValueKey('desktop_chat_message_list'),
        controller: scrollController,
        reverse: true,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (hasStreamingItem && index == 0) {
            final visible = streamingText.trim();
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: visible.isEmpty
                  ? const _DesktopTypingBubble()
                  : SelectionArea(
                      child: _DesktopCharacterTurn(text: visible),
                    ),
            );
          }
          final messageIndex = index - (hasStreamingItem ? 1 : 0);
          final message = messagesNewestFirst[messageIndex];
          final workbenchAction =
              _workbenchActionProjection(message.attachmentsJson);
          return Padding(
            key: ValueKey('desktop_chat_message_${message.id}'),
            padding: const EdgeInsets.only(bottom: 9),
            child: SelectionArea(
              child: workbenchAction != null
                  ? WorkbenchActionCard(
                      action: workbenchAction,
                      undoAvailable: canUndoWorkbenchAction
                              ?.call(workbenchAction.actionId) ??
                          false,
                      onUndo: onUndoWorkbenchAction,
                    )
                  : message.messageType == 'action'
                      ? _DesktopChatBubble(
                          text: message.content,
                          fromUser: false,
                          action: true,
                        )
                      : message.isFromCharacter
                          ? _DesktopCharacterTurn(
                              text: message.content,
                              hasAttachment:
                                  _hasAttachment(message.attachmentsJson),
                            )
                          : _DesktopChatBubble(
                              text: message.content.trim().isEmpty &&
                                      _hasAttachment(message.attachmentsJson)
                                  ? '已发送附件'
                                  : message.content,
                              fromUser: true,
                            ),
            ),
          );
        },
      ),
    );
  }
}

class _DesktopCharacterTurn extends StatelessWidget {
  const _DesktopCharacterTurn({required this.text, this.hasAttachment = false});

  final String text;
  final bool hasAttachment;

  @override
  Widget build(BuildContext context) {
    var segments = PersonaReplySanitizer.splitVisibleReply(
      text,
      characterName: '林埃',
      stripTtsTags: true,
    );
    if (segments.isEmpty && text.trim().isNotEmpty) {
      segments = [
        PersonaReplySegment(
          type: PersonaReplySegmentType.chat,
          text: text.trim(),
        ),
      ];
    }

    final bubbles = <Widget>[];
    for (final segment in segments) {
      if (segment.type == PersonaReplySegmentType.action) {
        if (segment.text.trim().isNotEmpty) {
          bubbles.add(
            _DesktopChatBubble(
              text: segment.text,
              fromUser: false,
              action: true,
            ),
          );
        }
        continue;
      }
      for (final chatBubble
          in PersonaReplySanitizer.splitChatIntoBubbles(segment.text)) {
        if (chatBubble.trim().isNotEmpty) {
          bubbles.add(
            _DesktopChatBubble(text: chatBubble, fromUser: false),
          );
        }
      }
    }
    if (hasAttachment && bubbles.isEmpty) {
      bubbles.add(
        const _DesktopChatBubble(text: '林埃发送了附件', fromUser: false),
      );
    }
    if (bubbles.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < bubbles.length; i++) ...[
          bubbles[i],
          if (i != bubbles.length - 1) const SizedBox(height: 7),
        ],
      ],
    );
  }
}

class _DesktopChatBubble extends StatelessWidget {
  const _DesktopChatBubble({
    required this.text,
    required this.fromUser,
    this.action = false,
    this.muted = false,
  });

  final String text;
  final bool fromUser;
  final bool action;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    final message = text.trim();
    if (message.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: action ? 0.78 : 0.88,
        child: Align(
          alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: action
                  ? tokens.surfaceRaised.withValues(alpha: 0.9)
                  : fromUser
                      ? tokens.actionSoft.withValues(alpha: 0.18)
                      : tokens.surfaceRaised,
              border: Border.all(
                color: fromUser
                    ? tokens.action.withValues(alpha: 0.18)
                    : tokens.divider,
              ),
              borderRadius: BorderRadius.circular(13),
              boxShadow: _desktopChatShadow(tokens),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                message,
                style: whiteboardUiTextStyle(
                  fontSize: action ? 12 : 13,
                  fontStyle: action ? FontStyle.italic : FontStyle.normal,
                  color:
                      muted || action ? tokens.textMuted : tokens.textPrimary,
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopTypingBubble extends StatelessWidget {
  const _DesktopTypingBubble();

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        key: const ValueKey('desktop_chat_typing'),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.divider),
          borderRadius: BorderRadius.circular(13),
          boxShadow: _desktopChatShadow(tokens),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.action.withValues(alpha: 0.62),
                    shape: BoxShape.circle,
                  ),
                ),
                if (i != 2) const SizedBox(width: 4),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopComposer extends StatelessWidget {
  const _DesktopComposer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.isStreaming,
    required this.onSend,
    this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool isStreaming;
  final Future<void> Function() onSend;
  final Future<void> Function()? onStop;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return AnimatedBuilder(
      animation: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final canSend =
            enabled && !isStreaming && controller.text.trim().isNotEmpty;
        final canStop = enabled && isStreaming && onStop != null;
        return AnimatedContainer(
          key: const ValueKey('desktop_chat_input_surface'),
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border.all(
              color: focusNode.hasFocus
                  ? tokens.action.withValues(alpha: 0.52)
                  : tokens.divider,
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              if (focusNode.hasFocus)
                BoxShadow(
                  color: tokens.actionSoft.withValues(alpha: 0.18),
                  blurRadius: 0,
                  spreadRadius: 3,
                ),
              ..._desktopChatShadow(tokens),
            ],
          ),
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('desktop_chat_input'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  enabled: enabled && !isStreaming,
                  textInputAction: TextInputAction.send,
                  onSubmitted: canSend ? (_) => onSend() : null,
                  cursorColor: tokens.action,
                  style: whiteboardUiTextStyle(
                    fontSize: 13,
                    color: tokens.textPrimary,
                    height: 1.3,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    hintText: !enabled
                        ? '正在连接…'
                        : isStreaming
                            ? '林埃正在回复…'
                            : '输入要求…',
                    hintStyle: whiteboardUiTextStyle(
                      fontSize: 13,
                      color: tokens.textFaint,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: isStreaming ? '停止' : '发送',
                child: Material(
                  color: canSend || canStop ? tokens.action : tokens.actionSoft,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    key: ValueKey(
                      isStreaming ? 'desktop_chat_stop' : 'desktop_chat_send',
                    ),
                    onTap: canStop
                        ? () => onStop!()
                        : canSend
                            ? () => onSend()
                            : null,
                    borderRadius: BorderRadius.circular(9),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(
                        isStreaming ? Icons.stop_rounded : Icons.send_rounded,
                        size: 18,
                        color: tokens.canvas,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

List<BoxShadow> _desktopChatShadow(DesktopWorkspaceTokens tokens) => [
      BoxShadow(
        color: tokens.textPrimary.withValues(alpha: 0.13),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ];

bool _hasAttachment(String? attachmentsJson) {
  final value = attachmentsJson?.trim();
  return value != null && value.isNotEmpty && value != '[]';
}

WorkbenchActionProjection? _workbenchActionProjection(
  String? attachmentsJson,
) {
  final value = attachmentsJson?.trim();
  if (value == null || value.isEmpty) return null;
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return null;
    for (final attachment in decoded) {
      if (attachment is! Map || attachment['type'] != 'workbench_action') {
        continue;
      }
      final action = attachment['action'];
      if (action is! Map) return null;
      return WorkbenchActionProjection.fromJson(
        Map<String, dynamic>.from(action),
      );
    }
  } catch (_) {
    // Existing action messages and malformed addenda retain the legacy bubble.
  }
  return null;
}

double _preferredPopoverHeight({
  required bool loading,
  required List<PersonaChatMessage> messagesNewestFirst,
  required bool isStreaming,
  required String streamingText,
  required bool hasContextLabel,
}) {
  var messageHeight = 48.0;
  if (!loading && (messagesNewestFirst.isNotEmpty || isStreaming)) {
    messageHeight = 0;
    if (isStreaming) {
      messageHeight += _estimatedBubbleHeight(streamingText) + 9;
    }
    for (final message in messagesNewestFirst) {
      messageHeight += _estimatedBubbleHeight(message.content) + 9;
      if (messageHeight >= 320) break;
    }
    messageHeight = messageHeight.clamp(48, 320).toDouble();
  }
  final contextHeight = hasContextLabel ? 35.0 : 0.0;
  final gaps = hasContextLabel ? 18.0 : 9.0;
  const composerHeight = 50.0;
  return contextHeight + messageHeight + gaps + composerHeight;
}

double _estimatedBubbleHeight(String text) {
  final runeCount = text.trim().runes.length;
  final lines = math.max(1, math.min(6, (runeCount / 24).ceil()));
  return 24 + lines * 20;
}

class _DesktopChatScrollBehavior extends ScrollBehavior {
  const _DesktopChatScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
