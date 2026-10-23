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

  const cases = <String?, String?>{
    'frontend:claude_web': 'Claude',
    'frontend:chatgpt_web': 'ChatGPT',
    'frontend:gemini_web': 'Gemini',
    'frontend:sesame': '网页端',
    'frontend:claude_web:extra': '网页端',
    'frontend:CLAUDE_WEB': '网页端',
    null: null,
    '': null,
    'frontend:': null, // An empty frontend name has no label.
    'Frontend:claude_web': null, // The prefix is case-sensitive too.
    'core-companion:i': null,
    'v3-history-synthetic': null,
    'synthetic-local-installation': null,
    'synthetic-other-phone-installation': null,
  };
  for (final entry in cases.entries) {
    test('source mapping for ${entry.key}', () {
      expect(chatSourceLabelFor(entry.key), entry.value);
    });
  }

  for (final source in ['frontend:claude_web', 'frontend:chatgpt_web']) {
    for (final fromCharacter in [true, false]) {
      testWidgets('$source label aligns for character=$fromCharacter', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatMessageSourceLabel(
              message: _message(origin: source, fromCharacter: fromCharacter),
            ),
          ),
        );
        final label = find.text(cases[source]!);
        expect(label, findsOneWidget);
        final align = tester.widget<Align>(
          find.ancestor(of: label, matching: find.byType(Align)).first,
        );
        expect(
          align.alignment,
          fromCharacter ? Alignment.centerLeft : Alignment.centerRight,
        );
        final labelRect = tester.getRect(label);
        final parentRect = tester.getRect(find.byType(ChatMessageSourceLabel));
        expect(
          fromCharacter ? labelRect.left : labelRect.right,
          fromCharacter ? parentRect.left : parentRect.right,
        );
      });
    }
  }

  testWidgets(
    'unlabelled origins render no Text even with frontend-like content',
    (tester) async {
      for (final entry in cases.entries.where((entry) => entry.value == null)) {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatMessageSourceLabel(
              message: _message(origin: entry.key),
              color: Colors.white,
            ),
          ),
        );
        expect(find.byType(Text), findsNothing);
        expect(
          find.descendant(
            of: find.byType(ChatMessageSourceLabel),
            matching: find.byType(SizedBox),
          ),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets('unknown frontend displays the web fallback', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatMessageSourceLabel(
          message: _message(origin: 'frontend:sesame'),
        ),
      ),
    );
    expect(find.text('网页端'), findsOneWidget);
  });

  testWidgets('source labels meet 4.5 contrast on the dark chat background', (
    tester,
  ) async {
    const chat = HereIamThemeTokens.springRainDaydream;
    for (final source in ['frontend:claude_web', 'frontend:chatgpt_web']) {
      for (final fromCharacter in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightThemeFor(chat),
            home: Scaffold(
              backgroundColor: chat.background,
              body: ChatMessageSourceLabel(
                message: _message(origin: source, fromCharacter: fromCharacter),
                color: chat.textSecondary,
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(ChatMessageSourceLabel),
            matching: find.byType(RichText),
          ),
        );
        final color = (paragraph.text as TextSpan).style!.color!;
        expect(color, chat.textSecondary);
        expect(
          _contrast(Color.alphaBlend(color, chat.background), chat.background),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });
}

PersonaChatMessage _message({String? origin, bool fromCharacter = false}) =>
    PersonaChatMessage(
      id: 1,
      characterId: 'synthetic-character',
      isFromCharacter: fromCharacter,
      content: 'frontend:chatgpt_web Claude',
      syncId: 'frontend:chatgpt_web:synthetic',
      attachmentsJson: '[{"source":"frontend:claude_web"}]',
      originDeviceId: origin,
      isRead: true,
      timestamp: DateTime(2026, 10, 23),
      messageType: 'chat',
    );

double _contrast(Color foreground, Color background) {
  final first = foreground.computeLuminance();
  final second = background.computeLuminance();
  return (math.max(first, second) + 0.05) / (math.min(first, second) + 0.05);
}
