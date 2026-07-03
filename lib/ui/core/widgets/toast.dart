import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Thin, non-intrusive toast that replaces the default black SnackBar.
///
/// Renders as a small rounded chip floating above the content, so it never
/// overlaps the input field.  Use [ScaffoldMessengerState.showToast].
extension ShowToast on ScaffoldMessengerState {
  void showToast(
    String message, {
    Duration duration = const Duration(seconds: 1),
  }) {
    hideCurrentSnackBar();
    showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 96, left: 80, right: 80),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: AppColors.textPrimary.withAlpha(216),
        elevation: 0,
      ),
    );
  }
}
