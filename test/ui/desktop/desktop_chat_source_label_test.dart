import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/workbench_ai/action/workbench_action_projection.dart';
import 'package:memex/ui/character/widgets/chat_message_source_label.dart';
import 'package:memex/ui/desktop/widgets/desktop_persona_chat_view.dart';
import 'package:memex/ui/desktop/widgets/workbench_action_card.dart';

void main() {
  setUp(() {
    final previous = GoogleFonts.config.allowRuntimeFetching;
    GoogleFonts.config.allowRuntimeFetching = false;
    addTearDown(() => GoogleFonts.config.allowRuntimeFetching = previous);
  });

  testWidgets(
    'desktop timeline labels frontend sources and keeps local unlabelled',
    (tester) async {
      await _pumpChat(tester, [
        _message(3, 'synthetic-local-installation'),
        _message(2, 'frontend:claude_web', fromCharacter: true),
        _message(1, 'frontend:chatgpt_web'),
      ]);
      expect(find.text('ChatGPT'), findsOneWidget);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('网页端'), findsNothing);
      expect(find.byType(ChatMessageSourceLabel), findsNWidgets(3));
      for (var id = 1; id <= 3; id++) {
        expect(
          find.byKey(ValueKey('desktop_chat_message_$id')),
          findsOneWidget,
        );
        expect(find.text('Synthetic desktop message $id'), findsOneWidget);
      }
      final local = find.byKey(const ValueKey('desktop_chat_message_3'));
      expect(
        find.descendant(of: local, matching: find.byType(Text)),
        findsOneWidget,
      );
      for (final label in ['Claude', 'ChatGPT']) {
        expect(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SelectionArea),
          ),
          findsNothing,
          reason: 'Source metadata must stay outside copied text.',
        );
      }
    },
  );

  testWidgets('desktop workbench action cards never display source labels', (
    tester,
  ) async {
    final at = DateTime.utc(2026, 10, 23);
    final action = WorkbenchActionProjection(
      actionId: 'synthetic-action',
      actionType: 'synthetic-type',
      title: 'Synthetic action',
      status: WorkbenchActionStatus.completed,
      boardId: 'synthetic-board',
      selectedItemCount: 1,
      summary: 'Synthetic summary',
      createdAt: at,
      updatedAt: at,
    );
    final message =
        _message(4, 'frontend:claude_web', fromCharacter: true).copyWith(
      attachmentsJson: Value(jsonEncode([
        {'type': 'workbench_action', 'action': action.toJson()},
      ])),
    );
    await _pumpChat(tester, [message]);
    expect(find.byType(WorkbenchActionCard), findsOneWidget);
    expect(find.byType(ChatMessageSourceLabel), findsNothing);
    expect(find.text('Claude'), findsNothing);
  });
}

Future<void> _pumpChat(
  WidgetTester tester,
  List<PersonaChatMessage> messages,
) async {
  final controller = TextEditingController();
  final focus = FocusNode();
  final scroll = ScrollController();
  addTearDown(controller.dispose);
  addTearDown(focus.dispose);
  addTearDown(scroll.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 600,
          child: DesktopPersonaChatView(
            loading: false,
            messagesNewestFirst: messages,
            isStreaming: false,
            streamingText: '',
            controller: controller,
            composerFocusNode: focus,
            scrollController: scroll,
            onSend: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

PersonaChatMessage _message(
  int id,
  String origin, {
  bool fromCharacter = false,
}) =>
    PersonaChatMessage(
      id: id,
      characterId: 'synthetic-character',
      isFromCharacter: fromCharacter,
      content: 'Synthetic desktop message $id',
      originDeviceId: origin,
      isRead: true,
      timestamp: DateTime(2026, 10, 23, 12, 0, id),
      messageType: 'chat',
    );
