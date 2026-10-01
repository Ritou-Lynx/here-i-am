import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memex/db/app_database.dart';
import 'package:memex/ui/desktop/desktop_workspace_tokens.dart';
import 'package:memex/ui/desktop/widgets/desktop_persona_chat_view.dart';

void main() {
  testWidgets('task result keeps all 2000 lines in text and actual layout',
      (tester) async {
    final lines = List.generate(2000, (index) => '${index + 1}');
    final result = lines.join('\n');
    expect(utf8.encode(result), hasLength(8892));
    await _pumpChat(tester, message: _message(result, taskRoomId: 'task-1'));

    final text =
        find.descendant(of: _messageFinder, matching: find.byType(Text));
    expect(text, findsOneWidget);
    expect(tester.widget<Text>(text).data, result);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: _messageFinder, matching: find.byType(RichText)),
    );
    expect(paragraph.text.toPlainText(), result);
    expect(paragraph.didExceedMaxLines, isFalse);

    Rect boxForLine(int line) {
      final offset =
          lines.take(line - 1).fold<int>(0, (n, text) => n + text.length + 1);
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(
            baseOffset: offset, extentOffset: offset + lines[line - 1].length),
      );
      expect(boxes, hasLength(1),
          reason: 'line $line stays on one visual line');
      return boxes.single.toRect();
    }

    final first = boxForLine(1);
    final lineStep = boxForLine(2).top - first.top;
    expect(lineStep, greaterThan(0));
    for (final line in [2, 3, 999, 1000, 1001, 1998, 1999, 2000]) {
      final box = boxForLine(line);
      expect(box.left, closeTo(first.left, 0.01));
      expect(box.top, closeTo(first.top + (line - 1) * lineStep, 0.1),
          reason: 'line $line retains its original row');
    }
    expect(boxForLine(2000).bottom, lessThanOrEqualTo(paragraph.size.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'task result retains outer whitespace, blank lines and action text',
      (tester) async {
    const result = '  \n1\n\n*轻轻笑了笑*\n[轻轻点头]\n  2  \n\n';
    await _pumpChat(tester, message: _message(result, taskRoomId: 'task-1'));
    final texts = _messageTexts(tester);
    expect(texts, [result]);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: _messageFinder, matching: find.byType(RichText)),
    );
    expect(paragraph.text.toPlainText(), result);
    expect(
        tester
            .widget<Text>(find.descendant(
              of: _messageFinder,
              matching: find.byType(Text),
            ))
            .style
            ?.fontStyle,
        FontStyle.normal);
  });

  testWidgets('task state notices retain their exact content', (tester) async {
    for (final notice in [
      '任务正在执行。',
      '任务已中断，等待你明确恢复。',
      '任务已取消。',
    ]) {
      await _pumpChat(tester, message: _message(notice, taskRoomId: 'task-1'));
      expect(_messageTexts(tester), [notice]);
    }
  });

  testWidgets('empty task body keeps attachment placeholder or remains hidden',
      (tester) async {
    for (final content in ['', '  \n  ']) {
      await _pumpChat(tester,
          message: _message(content,
              taskRoomId: 'task-1',
              attachmentsJson: '[{"type":"image","path":"test-image.png"}]'));
      expect(_messageTexts(tester), ['林埃发送了附件']);
      await _pumpChat(tester, message: _message(content, taskRoomId: 'task-1'));
      expect(_messageTexts(tester), isEmpty);
    }
  });

  testWidgets('ordinary replies still split for absent or blank task IDs',
      (tester) async {
    const reply = '第一句话需要保留。第二句话同样保留。';
    for (final taskId in <String?>[null, '', '   ']) {
      await _pumpChat(tester, message: _message(reply, taskRoomId: taskId));
      expect(_messageTexts(tester), ['第一句话需要保留。', '第二句话同样保留。']);
    }
  });

  testWidgets('task association does not change user or action presentation',
      (tester) async {
    await _pumpChat(tester,
        message: _message('  user text  ',
            taskRoomId: 'task-1', isFromCharacter: false));
    expect(_messageTexts(tester), ['user text']);
    await _pumpChat(tester,
        message: _message('  action text  ',
            taskRoomId: 'task-1', messageType: 'action'));
    expect(_messageTexts(tester), ['action text']);
    expect(
        tester
            .widget<Text>(find.descendant(
              of: _messageFinder,
              matching: find.byType(Text),
            ))
            .style
            ?.fontStyle,
        FontStyle.italic);
  });
}

final _messageFinder = find.byKey(const ValueKey('desktop_chat_message_1'));

List<String?> _messageTexts(WidgetTester tester) => tester
    .widgetList<Text>(
        find.descendant(of: _messageFinder, matching: find.byType(Text)))
    .map((text) => text.data)
    .toList();

PersonaChatMessage _message(
  String content, {
  String? taskRoomId,
  String? attachmentsJson,
  bool isFromCharacter = true,
  String messageType = 'chat',
}) =>
    PersonaChatMessage(
      id: 1,
      characterId: 'i',
      isFromCharacter: isFromCharacter,
      content: content,
      timestamp: DateTime(2026, 9, 17),
      isRead: true,
      messageType: messageType,
      taskRoomId: taskRoomId,
      attachmentsJson: attachmentsJson,
    );

Future<void> _pumpChat(WidgetTester tester,
    {required PersonaChatMessage message}) async {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final scrollController = ScrollController();
  addTearDown(controller.dispose);
  addTearDown(focusNode.dispose);
  addTearDown(scrollController.dispose);
  await tester.pumpWidget(MaterialApp(
    home: DesktopWorkspaceTheme(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 350,
          height: 480,
          child: DesktopPersonaChatView(
            loading: false,
            messagesNewestFirst: [message],
            isStreaming: false,
            streamingText: '',
            controller: controller,
            composerFocusNode: focusNode,
            scrollController: scrollController,
            onSend: () async {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}
