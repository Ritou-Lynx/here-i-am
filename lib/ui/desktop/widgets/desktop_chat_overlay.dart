/// 林埃桌面悬浮对话（spine-contract §3.5 / visual-rules §8.6）。
///
/// 收起态与展开态都保留右下角品牌球。展开时只在球上方浮出独立消息气泡
/// 和输入面，不绘制手机壳、标题栏或包住整个会话的矩形面板。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_brand_mark.dart';

class DesktopFloatingBall extends StatelessWidget {
  const DesktopFloatingBall({
    super.key,
    required this.onTap,
    required this.expanded,
    this.focusNode,
  });

  final VoidCallback onTap;
  final bool expanded;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Tooltip(
      message: expanded ? '收起林埃对话' : '与林埃对话',
      child: Semantics(
        button: true,
        expanded: expanded,
        label: expanded ? '收起林埃悬浮对话' : '打开林埃悬浮对话',
        child: Material(
          color: tokens.surfaceRaised,
          shape: CircleBorder(
            side: BorderSide(color: tokens.action.withValues(alpha: 0.38)),
          ),
          elevation: 3,
          shadowColor: tokens.textPrimary.withValues(alpha: 0.2),
          child: InkWell(
            key: const ValueKey('desktop_floating_ball'),
            focusNode: focusNode,
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 50,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const DesktopBrandMark(size: 30),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: tokens.action,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: tokens.surfaceRaised,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DesktopChatPopover extends StatelessWidget {
  const DesktopChatPopover({
    super.key,
    required this.characterId,
    required this.initialVoiceMode,
    required this.onClose,
    this.temporaryContextLabel,
  });

  final String characterId;
  final bool initialVoiceMode;
  final VoidCallback onClose;
  final String? temporaryContextLabel;

  @override
  Widget build(BuildContext context) {
    return Focus(
      key: const ValueKey('desktop_chat_popover'),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          onClose();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PersonaChatScreen(
        key: ValueKey('desktop-chat-$characterId'),
        characterId: characterId,
        initialVoiceMode: initialVoiceMode,
        presentation: PersonaChatPresentation.desktopFloating,
        temporaryContextLabel: temporaryContextLabel,
      ),
    );
  }
}

class DesktopChatOverlay extends StatefulWidget {
  const DesktopChatOverlay({
    super.key,
    required this.open,
    required this.characterId,
    required this.initialVoiceMode,
    required this.onOpen,
    required this.onClose,
    this.temporaryContextLabel,
  });

  final bool open;
  final String characterId;
  final bool initialVoiceMode;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final String? temporaryContextLabel;

  @override
  State<DesktopChatOverlay> createState() => _DesktopChatOverlayState();
}

class _DesktopChatOverlayState extends State<DesktopChatOverlay> {
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'desktop-chat-trigger',
  );

  @override
  void didUpdateWidget(covariant DesktopChatOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open && !widget.open) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _triggerFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _triggerFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = math.max(0.0, constraints.maxWidth - 36);
        final popoverWidth = math.min(350.0, availableWidth);
        final availableHeight = math.max(0.0, constraints.maxHeight - 104);
        final popoverHeight = math.min(480.0, availableHeight);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (widget.open && popoverWidth > 0 && popoverHeight > 0)
              Positioned(
                right: 18,
                bottom: 80,
                width: popoverWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: popoverHeight),
                  child: DesktopChatPopover(
                    key: const ValueKey('desktop_chat_popover_open'),
                    characterId: widget.characterId,
                    initialVoiceMode: widget.initialVoiceMode,
                    temporaryContextLabel: widget.temporaryContextLabel,
                    onClose: widget.onClose,
                  ),
                ),
              ),
            Positioned(
              right: 18,
              bottom: 18,
              child: DesktopFloatingBall(
                expanded: widget.open,
                onTap: widget.open ? widget.onClose : widget.onOpen,
                focusNode: _triggerFocusNode,
              ),
            ),
          ],
        );
      },
    );
  }
}
