import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/character/widgets/chat_message_source_label.dart';
import 'package:memex/ui/core/themes/app_theme.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';

void main() {
  setUp(() {
    final previous = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = previous);
  });

  testWidgets(
      'phone source label remains readable on dark chat under global daylight theme',
      (tester) async {
    const chat = HereIamThemeTokens.springRainDaydream;
    for (final fromCharacter in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightThemeFor(chat),
        themeMode: ThemeMode.light,
        home: Scaffold(
          backgroundColor: chat.background,
          body: ChatMessageSourceLabel(
            message: _message(fromCharacter: fromCharacter),
            color: chat.textSecondary,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(ChatMessageSourceLabel),
          matching: find.byType(RichText),
        ),
      );
      final renderedColor = (paragraph.text as TextSpan).style!.color!;
      expect(renderedColor, chat.textSecondary);
      final paintedColor = Color.alphaBlend(renderedColor, chat.background);
      expect(
          _contrast(paintedColor, chat.background), greaterThanOrEqualTo(4.5));

      final labelContext = tester.element(find.byType(ChatMessageSourceLabel));
      final defaultColor = Theme.of(labelContext).colorScheme.onSurfaceVariant;
      expect(
        _contrast(
            Color.alphaBlend(defaultColor, chat.background), chat.background),
        lessThan(4.5),
        reason:
            'The daylight default reproduces the old phone contrast failure.',
      );
    }
  });

  testWidgets('omitting the override preserves the surrounding theme color',
      (tester) async {
    const expected = Color(0xFF74726C);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        colorScheme: const ColorScheme.light(onSurfaceVariant: expected),
      ),
      home: ChatMessageSourceLabel(message: _message()),
    ));
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(ChatMessageSourceLabel),
        matching: find.byType(RichText),
      ),
    );
    expect((paragraph.text as TextSpan).style!.color, expected);
  });

  testWidgets('color override does not label non-frontend origins',
      (tester) async {
    for (final origin in <String?>[
      null,
      'phone',
      'claude_web',
      'core:primary'
    ]) {
      await tester.pumpWidget(MaterialApp(
        home: ChatMessageSourceLabel(
          message: _message(origin: origin),
          color: Colors.white,
        ),
      ));
      expect(find.text('网页端'), findsNothing);
    }
  });
}

PersonaChatMessage _message({
  String? origin = 'frontend:claude_web',
  bool fromCharacter = false,
}) =>
    PersonaChatMessage(
      id: 1,
      originDeviceId: origin,
      characterId: 'i',
      isFromCharacter: fromCharacter,
      content: 'Synthetic frontend message',
      isRead: true,
      timestamp: DateTime(2026, 10, 3),
      messageType: 'chat',
    );

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}
