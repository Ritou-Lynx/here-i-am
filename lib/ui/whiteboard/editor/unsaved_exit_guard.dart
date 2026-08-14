/// Unsaved-changes exit guard for the card editor.
///
/// Wraps the editor and intercepts back-navigation while there are unsaved
/// changes, asking the user to save, discard, or cancel. Uses Flutter's
/// [PopScope] so the app bar back button, system back, and route pops are
/// all covered.
library;

import 'package:flutter/material.dart';

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
    builder: (context) => AlertDialog(
      title: const Text('尚未保存'),
      content: const Text('当前编辑尚未保存。要保存后退出，还是放弃更改？'),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(UnsavedExitChoice.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(UnsavedExitChoice.discard),
          child: const Text('放弃'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(UnsavedExitChoice.save),
          child: const Text('保存并退出'),
        ),
      ],
    ),
  );
  if (choice == UnsavedExitChoice.save) {
    await onSave();
    return UnsavedExitChoice.save;
  }
  return choice ?? UnsavedExitChoice.cancel;
}
