/// 林埃悬浮对话（spine-contract §3.5 / visual-rules §8.6）。
///
/// 收起态 = 中性悬浮球 + 小状态点；展开态 = 覆盖在首页之上的对话面板，
/// 复用与手机完全相同的 [PersonaChatScreen]（同一条关系主对话，不另造
/// 数据）。关闭后完整退场，不留下兜底侧栏。
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/character/widgets/persona_chat_screen.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

/// 悬浮球：44px 中性圆 + 墨绿 `i`，小状态点表达空闲（无行为装饰）。
class DesktopFloatingBall extends StatelessWidget {
  const DesktopFloatingBall({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const tokens = SpringRainUiTokens.daylight;
    return Tooltip(
      message: '与林埃对话',
      child: Material(
        color: tokens.surfaceRaised,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: tokens.textPrimary.withValues(alpha: 0.18),
        child: InkWell(
          key: const ValueKey('desktop_floating_ball'),
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  'i',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: tokens.textPrimary,
                    height: 1.1,
                  ),
                ),
                Positioned(
                  right: 5,
                  top: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tokens.accent,
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
  });

  final String characterId;
  final bool initialVoiceMode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const tokens = SpringRainUiTokens.daylight;
    return Align(
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
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '林埃',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                      height: 1.35,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    key: const ValueKey('desktop_chat_close'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: tokens.textSecondary,
                    tooltip: '收起对话',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: SpringRainUiTokens.daylightDivider),
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
    );
  }
}

/// 悬浮对话整体：球 ↔ 面板 220ms 切换。
class DesktopChatOverlay extends StatelessWidget {
  const DesktopChatOverlay({
    super.key,
    required this.open,
    required this.characterId,
    required this.initialVoiceMode,
    required this.onOpen,
    required this.onClose,
  });

  final bool open;
  final String characterId;
  final bool initialVoiceMode;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: open
          ? DesktopChatPanel(
              key: const ValueKey('panel'),
              characterId: characterId,
              initialVoiceMode: initialVoiceMode,
              onClose: onClose,
            )
          : Align(
              key: const ValueKey('ball'),
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DesktopFloatingBall(onTap: onOpen),
              ),
            ),
    );
  }
}
