import 'package:flutter/material.dart';

import '../themes/here_iam_theme_tokens.dart';

/// Thin, non-intrusive toast that replaces the default black SnackBar.
///
/// The [SnackBar] itself is transparent and bottom-anchored (margin 116). The
/// visible chip lives inside the content as a [Builder] that reads
/// [MediaQuery.viewInsetsOf], so it is rebuilt when the keyboard opens/closes.
/// A spacer below the chip grows with the keyboard height, pushing the chip
/// above the input bar. Use via [ScaffoldMessengerState.showToast].
extension ShowToast on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showToast(
    String message, {
    Duration duration = const Duration(seconds: 1),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final tokens = HereIamThemeRuntime.current;
    final hasAction = actionLabel != null && onAction != null;
    hideCurrentSnackBar();
    return showSnackBar(
      SnackBar(
        content: Builder(
          builder: (context) {
            final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: ShapeDecoration(
                    color: tokens.background.withValues(alpha: 0.88),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                      side: BorderSide(color: tokens.glassStroke),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                        if (hasAction) ...[
                          const SizedBox(height: 2),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              hideCurrentSnackBar();
                              onAction();
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                actionLabel,
                                style: TextStyle(
                                  color: tokens.highlight,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(height: keyboardBottom),
              ],
            );
          },
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 116, left: 78, right: 78),
        padding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
    );
  }
}
