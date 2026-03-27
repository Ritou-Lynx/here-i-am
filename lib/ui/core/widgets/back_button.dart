import 'package:flutter/material.dart';

/// Figma back button: 36px white circle with shadow + chevron left arrow.
/// Original SVG is 54×54 (circle 36 + 9px shadow padding each side).
class AppBackButton extends StatelessWidget {
  final VoidCallback? onTap;

  const AppBackButton({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 9,
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.chevron_left,
            size: 22,
            color: Color(0xFF99A1AF),
          ),
        ),
      ),
    );
  }
}
