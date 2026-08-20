/// 林埃悬浮对话（spine-contract §3.5 / visual-rules §8.6）。
///
/// 收起态 = 中性悬浮球 + 小状态点；展开态 = 覆盖在首页之上的对话面板，
/// 复用与手机完全相同的 [PersonaChatScreen]（同一条关系主对话，不另造
/// 数据）。关闭后完整退场，不留下兜底侧栏。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_brand_mark.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class DesktopTaskStripData {
  const DesktopTaskStripData({
    required this.title,
    required this.statusLabel,
    this.needsAttention = false,
  });

  final String title;
  final String statusLabel;
  final bool needsAttention;
}

/// Task status stays outside [PersonaChatScreen] and never becomes a message.
class DesktopTaskStrip extends StatelessWidget {
  const DesktopTaskStrip({super.key, required this.data, required this.onTap});

  final DesktopTaskStripData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Material(
      key: const ValueKey('desktop_task_strip'),
      color: tokens.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: data.needsAttention ? tokens.focus : tokens.action,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: whiteboardUiTextStyle(
                    fontSize: 12,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                data.statusLabel,
                style: whiteboardUiTextStyle(
                  fontSize: 11,
                  color: data.needsAttention ? tokens.focus : tokens.textMuted,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: tokens.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 悬浮球：44px 中性圆 + 墨绿 `i`，小状态点表达空闲（无行为装饰）。
class DesktopFloatingBall extends StatelessWidget {
  const DesktopFloatingBall({super.key, required this.onTap, this.focusNode});

  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Tooltip(
      message: '与林埃对话',
      child: Material(
        color: tokens.surfaceRaised,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: tokens.textPrimary.withValues(alpha: 0.18),
        child: InkWell(
          key: const ValueKey('desktop_floating_ball'),
          focusNode: focusNode,
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const DesktopBrandMark(size: 28),
                Positioned(
                  right: 5,
                  top: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.action,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 展开态对话面板：右侧悬浮覆盖，关闭后回到悬浮球。
class DesktopChatPanel extends StatelessWidget {
  const DesktopChatPanel({
    super.key,
    required this.characterId,
    required this.initialVoiceMode,
    required this.onClose,
    this.focusNode,
    this.temporaryContextLabel,
    this.taskStrip,
    this.onOpenTasks,
  });

  final String characterId;
  final bool initialVoiceMode;
  final VoidCallback onClose;
  final FocusNode? focusNode;

  /// Display-only page context. It is never written to chat storage or
  /// User-truth by this shell.
  final String? temporaryContextLabel;
  final DesktopTaskStripData? taskStrip;
  final VoidCallback? onOpenTasks;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Focus(
      key: const ValueKey('desktop_chat_focus_scope'),
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          key: const ValueKey('desktop_chat_panel'),
          width: 400,
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: tokens.textPrimary.withValues(alpha: 0.14),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: tokens.action,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '林埃',
                            style: whiteboardUiTextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: tokens.textPrimary,
                              height: 1.35,
                            ),
                          ),
                          if (temporaryContextLabel != null)
                            Text(
                              '当前页面 · $temporaryContextLabel · 仅本次上下文',
                              key: const ValueKey(
                                'desktop_chat_temporary_context',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: whiteboardUiTextStyle(
                                fontSize: 11,
                                color: tokens.textFaint,
                                height: 1.35,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('desktop_chat_close'),
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: tokens.textMuted,
                      tooltip: '收起对话',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.divider),
              if (taskStrip != null && onOpenTasks != null) ...[
                DesktopTaskStrip(data: taskStrip!, onTap: onOpenTasks!),
                Divider(height: 1, color: tokens.divider),
              ],
              Expanded(
                child: PersonaChatScreen(
                  key: ValueKey('desktop-chat-$characterId'),
                  characterId: characterId,
                  embedded: true,
                  enableRichCapture: true,
                  initialVoiceMode: initialVoiceMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 悬浮对话整体：球 ↔ 面板 220ms 切换。
class DesktopChatOverlay extends StatefulWidget {
  const DesktopChatOverlay({
    super.key,
    required this.open,
    required this.characterId,
    required this.initialVoiceMode,
    required this.onOpen,
    required this.onClose,
    this.temporaryContextLabel,
    this.taskStrip,
    this.onOpenTasks,
  });

  final bool open;
  final String characterId;
  final bool initialVoiceMode;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final String? temporaryContextLabel;
  final DesktopTaskStripData? taskStrip;
  final VoidCallback? onOpenTasks;

  @override
  State<DesktopChatOverlay> createState() => _DesktopChatOverlayState();
}

class _DesktopChatOverlayState extends State<DesktopChatOverlay> {
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'desktop-chat-trigger',
  );
  final FocusNode _panelFocusNode = FocusNode(debugLabel: 'desktop-chat-panel');

  @override
  void didUpdateWidget(covariant DesktopChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.open) {
        _panelFocusNode.requestFocus();
      } else {
        _triggerFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    _panelFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: widget.open
          ? DesktopChatPanel(
              key: const ValueKey('panel'),
              characterId: widget.characterId,
              initialVoiceMode: widget.initialVoiceMode,
              onClose: widget.onClose,
              focusNode: _panelFocusNode,
              temporaryContextLabel: widget.temporaryContextLabel,
              taskStrip: widget.taskStrip,
              onOpenTasks: widget.onOpenTasks,
            )
          : Align(
              key: const ValueKey('ball'),
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DesktopFloatingBall(
                  onTap: widget.onOpen,
                  focusNode: _triggerFocusNode,
                ),
              ),
            ),
    );
  }
}
