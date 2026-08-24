import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/whiteboard/fonts.dart';

void main() {
  testWidgets('desktop theme is isolated from an indigo parent', (
    tester,
  ) async {
    const tokens = DesktopWorkspaceTokens.lieflatPalm;
    final parentScheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    late ThemeData scoped;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: parentScheme),
        home: DesktopWorkspaceTheme(
          child: Builder(
            builder: (context) {
              scoped = Theme.of(context);
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );

    final scheme = scoped.colorScheme;
    expect(scheme.primary, tokens.action);
    expect(scheme.secondary, tokens.actionSecondary);
    expect(scheme.tertiary, tokens.focus);
    expect(scheme.surface, tokens.canvas);
    expect(scheme.onSurface, tokens.textPrimary);
    expect(scheme.onSurfaceVariant, tokens.textMuted);
    expect(scheme.outline, tokens.textFaint);
    expect(scheme.outlineVariant, tokens.divider);
    expect(scheme.inverseSurface, tokens.dark);
    expect(scheme.inversePrimary, tokens.actionSoft);

    final scopedColors = <Color?>[
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primaryContainer,
      scheme.primaryFixed,
      scheme.primaryFixedDim,
      scheme.secondaryContainer,
      scheme.secondaryFixed,
      scheme.secondaryFixedDim,
      scheme.tertiaryContainer,
      scheme.tertiaryFixed,
      scheme.tertiaryFixedDim,
      scheme.surface,
      scheme.surfaceDim,
      scheme.surfaceBright,
      scheme.surfaceContainerLowest,
      scheme.surfaceContainerLow,
      scheme.surfaceContainer,
      scheme.surfaceContainerHigh,
      scheme.surfaceContainerHighest,
      scheme.outline,
      scheme.inversePrimary,
      scoped.focusColor,
      scoped.hoverColor,
      scoped.highlightColor,
      scoped.splashColor,
    ];
    expect(scopedColors, isNot(contains(parentScheme.primary)));
    expect(scopedColors, isNot(contains(parentScheme.secondary)));
    expect(scopedColors, isNot(contains(Colors.indigo)));
  });

  testWidgets('secondary Material surfaces consume desktop tokens and fonts', (
    tester,
  ) async {
    const tokens = DesktopWorkspaceTokens.lieflatPalm;
    late ThemeData scoped;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        ),
        home: DesktopWorkspaceTheme(
          child: Builder(
            builder: (context) {
              scoped = Theme.of(context);
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      ),
    );

    expect(scoped.snackBarTheme.backgroundColor, tokens.dark);
    expect(scoped.snackBarTheme.actionTextColor, tokens.actionSoft);
    expect(
      scoped.snackBarTheme.contentTextStyle?.fontFamily,
      richTextCjkFamily,
    );
    expect(scoped.snackBarTheme.contentTextStyle?.color, tokens.canvas);
    expect(scoped.inputDecorationTheme.fillColor, tokens.surfaceRaised);
    expect(scoped.inputDecorationTheme.prefixIconColor, tokens.textMuted);
    expect(scoped.inputDecorationTheme.filled, isTrue);
    expect(
      (scoped.inputDecorationTheme.disabledBorder as OutlineInputBorder)
          .borderSide
          .color,
      tokens.divider.withValues(alpha: 0.56),
    );
    expect(
      (scoped.inputDecorationTheme.focusedBorder as OutlineInputBorder)
          .borderSide
          .color,
      tokens.action,
    );
    expect(
      scoped.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
      tokens.action,
    );
    expect(
      scoped.outlinedButtonTheme.style?.side?.resolve({})?.color,
      tokens.actionSecondary,
    );
    expect(
      scoped.filledButtonTheme.style?.backgroundColor?.resolve({}),
      tokens.action,
    );
    expect(
      scoped.textButtonTheme.style?.foregroundColor?.resolve({}),
      tokens.action,
    );
    expect(
      scoped.iconButtonTheme.style?.foregroundColor?.resolve({}),
      tokens.textMuted,
    );
    expect(scoped.dialogTheme.backgroundColor, tokens.surfaceRaised);
    expect(scoped.dialogTheme.titleTextStyle?.fontFamily, richTextCjkFamily);
    expect(scoped.popupMenuTheme.color, tokens.surfaceRaised);
    expect(scoped.popupMenuTheme.textStyle?.color, tokens.textPrimary);
    expect(scoped.popupMenuTheme.textStyle?.fontFamily, richTextCjkFamily);
  });
}
