/// Shared desktop buttons — primary (green fill) and quiet (outline) styles
/// mirroring `.hia-button.is-primary` and `.hia-button.is-quiet` from the web
/// MVP. Extracted so all desktop shell pages reuse the same button chrome.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/whiteboard/desktop/desktop_shell_tokens.dart';

/// Primary action button — mirrors `.hia-button.is-primary` (green fill).
class DesktopPrimaryButton extends StatelessWidget {
  const DesktopPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DesktopShellTokens.green,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: DesktopShellTokens.canvas),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  fontSize: DesktopShellTokens.content,
                  color: DesktopShellTokens.canvas,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quiet button — mirrors `.hia-button.is-quiet` (transparent, muted text).
class DesktopQuietButton extends StatelessWidget {
  const DesktopQuietButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: const BorderSide(color: DesktopShellTokens.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: DesktopShellTokens.content,
              color: DesktopShellTokens.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}