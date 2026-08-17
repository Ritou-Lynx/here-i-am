/// Desktop page head — the title + kicker + actions row that tops every
/// desktop workspace page, mirroring the web MVP `.hia-page-head`.
///
/// Pages inside [DesktopShell] use this instead of a Material AppBar so the
/// shell has no persistent top bar, per the whiteboard spine contract.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard/desktop/desktop_shell_tokens.dart';

class DesktopPageHead extends StatelessWidget {
  const DesktopPageHead({
    super.key,
    required this.title,
    this.kicker,
    this.actions = const [],
  });

  final String title;
  final String? kicker;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: DesktopShellTokens.pageTitle,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: DesktopShellTokens.textPrimary,
                  ),
                ),
                if (kicker != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    kicker!,
                    style: const TextStyle(
                      fontSize: DesktopShellTokens.meta,
                      color: DesktopShellTokens.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Row(children: actions),
        ],
      ),
    );
  }
}