import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/design_system.dart';

/// Figma back button: 36px white circle with shadow + chevron left arrow.
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
        decoration: const BoxDecoration(
          color: AppColors.cardBackground,
          shape: BoxShape.circle,
          boxShadow: [AppShadows.backButton],
        ),
        child: const Center(
          child: Icon(
            Icons.chevron_left,
            size: 22,
            color: AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
