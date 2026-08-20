/// Shared desktop page-title row.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

class DesktopPageTitle extends StatelessWidget {
  const DesktopPageTitle({
    super.key,
    required this.title,
    this.meta,
    this.actions = const [],
    this.onBack,
    this.backTooltip = '返回',
  });

  final String title;
  final String? meta;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final String backTooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = DesktopWorkspaceTokens.of(context);
    return Padding(
      key: const ValueKey('desktop_page_title'),
      padding: const EdgeInsets.fromLTRB(
        DesktopWorkspaceTokens.pageHorizontalPadding,
        20,
        DesktopWorkspaceTokens.pageHorizontalPadding,
        12,
      ),
      child: Row(
        children: [
          if (onBack != null) ...[
            IconButton(
              key: const ValueKey('desktop_page_back'),
              onPressed: onBack,
              tooltip: backTooltip,
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              color: tokens.textMuted,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            title,
            style: whiteboardUiTextStyle(
              fontSize: 24,
              height: 1.28,
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (meta != null) ...[
            const SizedBox(width: 16),
            Flexible(
              child: Text(
                meta!,
                overflow: TextOverflow.ellipsis,
                style: whiteboardUiTextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: tokens.textFaint,
                ),
              ),
            ),
          ],
          const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}
