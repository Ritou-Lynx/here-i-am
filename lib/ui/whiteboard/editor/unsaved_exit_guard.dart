/// Unsaved-changes exit guard for the card editor.
///
/// Wraps the editor and intercepts back-navigation while there are unsaved
/// changes, asking the user to save, discard, or cancel. Uses Flutter's
/// [PopScope] so the app bar back button, system back, and route pops are
/// all covered.
library;

import 'package:flutter/material.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

/// Result of the discard confirmation.
enum UnsavedExitChoice {
  save,
  discard,
  cancel,
}

/// Intercepts pop navigation when [hasUnsavedChanges] is true and asks the
/// caller what to do.
///
/// - Returns [UnsavedExitChoice.save] when the user picks "save first";
/// - Returns [UnsavedExitChoice.discard] when the user picks "discard";
/// - Returns [UnsavedExitChoice.cancel] when the user cancels and stays.
///
/// [onSave] is invoked before returning [UnsavedExitChoice.save].
Future<UnsavedExitChoice> confirmUnsavedExit(
  BuildContext context, {
  required bool hasUnsavedChanges,
  required Future<void> Function() onSave,
}) async {
  if (!hasUnsavedChanges) return UnsavedExitChoice.discard;
  final choice = await showDialog<UnsavedExitChoice>(
    context: context,
    builder: (context) {
      final tokens = DesktopWorkspaceTokens.of(context);
      return AlertDialog(
        backgroundColor: tokens.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        title: Row(
          children: [
            Icon(Icons.edit_note_rounded, size: 20, color: tokens.focus),
            const SizedBox(width: 8),
            Text(
              '尚未保存',
              style: whiteboardUiTextStyle(
                fontSize: 18,
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          '当前编辑尚未保存。要保存后退出，还是放弃更改？',
          style: whiteboardUiTextStyle(
            fontSize: 13,
            height: 1.55,
            color: tokens.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UnsavedExitChoice.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(UnsavedExitChoice.discard),
            style: TextButton.styleFrom(foregroundColor: tokens.error),
            child: const Text('放弃'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(UnsavedExitChoice.save),
            style: FilledButton.styleFrom(
              backgroundColor: tokens.action,
              foregroundColor: tokens.canvas,
              minimumSize: const Size(112, 36),
            ),
            child: const Text('保存并退出'),
          ),
        ],
      );
    },
  );
  if (choice == UnsavedExitChoice.save) {
    await onSave();
    return UnsavedExitChoice.save;
  }
  return choice ?? UnsavedExitChoice.cancel;
}
