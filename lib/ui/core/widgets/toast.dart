import 'package:flutter/material.dart';

/// Thin, non-intrusive toast that replaces the default black SnackBar.
///
/// Renders as a small rounded chip floating above the content, so it never
/// overlaps the input field.  Use [ScaffoldMessengerState.showToast].
extension ShowToast on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(
    String message, {
    Duration duration = const Duration(seconds: 1),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    hideCurrentSnackBar();
    return showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFFF6F0EF),
            fontSize: 13,
            height: 1.25,
          ),
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 116, left: 78, right: 78),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
          side: BorderSide(
            color: const Color(0xFFFFC6B5).withValues(alpha: 0.12),
          ),
        ),
        backgroundColor: const Color(0xFF241319).withValues(alpha: 0.88),
        elevation: 0,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: const Color(0xFFFFC6B5),
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}
