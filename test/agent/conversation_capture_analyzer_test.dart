import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/conversation_capture_agent/conversation_capture_analyzer.dart';
import 'package:memex/agent/conversation_capture_agent/prompt.dart';
import 'package:memex/data/services/shared_life_memory_service.dart';
import 'package:memex/data/services/task_handlers/conversation_capture_handler.dart';

void main() {
  test('parses fenced JSON and keeps structured destinations separate', () {
    final result = parseConversationCaptureAnalysis('''
```json
{
  "shared_operations": [
    {
      "operation_type": "create",
      "entity_id": null,
      "entity_type": "task",
      "title": "Book dentist",
      "patch": {"time": "next week", "tags": ["health", "appointment"]},
      "source_message_ids": [12]
    }
  ],
  "character_memory_operations": [
    {"label": "promise", "content": "Ask how the appointment went"}
  ],
  "ignored_message_ids": [13]
}
```
''');

    expect(result.sharedOperations, hasLength(1));
    expect(result.sharedOperations.single.title, 'Book dentist');
    expect(result.sharedOperations.single.patch['time'], 'next week');
    expect(
      result.sharedOperations.single.patch['tags'],
      ['health', 'appointment'],
    );
    expect(result.characterMemoryOperations, hasLength(1));
    expect(result.ignoredMessageIds, [13]);
  });

  test('prompt classifies records by real-world behavior, not task bias', () {
    final prompt = conversationCaptureSystemPrompt(const ['Work', 'Emotion']);

    expect(prompt, contains('real user-life information'));
    expect(prompt, contains('in-chat interaction'));
    expect(prompt, contains('There is only one topic label system'));
    expect(prompt, contains('patch.tags'));
    expect(prompt, contains('tags.md'));
    expect(prompt, contains('Do not invent new tags'));
    expect(prompt, contains('Do not translate tags'));
    expect(prompt, contains('what the user\'s statement means in real life'));
    expect(prompt, contains('controlled tag vocabulary'));
    expect(prompt, contains('user\'s topic label system'));
    expect(prompt, contains('Do not use'));
    expect(prompt, contains('task as a generic container'));
    expect(prompt, contains('ordinary games'));
    expect(prompt, contains('playing turtle soup'));
    expect(prompt, contains('I feel anxious today'));
    expect(prompt, contains('emotional/physical state snapshot'));
    expect(prompt, contains('received an offer'));
    expect(prompt, contains('is an event, not a task'));
    expect(prompt, contains('reply to Zuoyebang\'s offer tomorrow'));
    expect(prompt, contains('is a task'));
    expect(prompt, contains('"tags": ["Work"]'));
  });

  test('conversation capture keeps only canonical tags from tags.md', () {
    final operations = restrictOperationTagsToKnownTags(
      knownTags: const ['Work', 'Emotion'],
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'event',
          title: '接到作业帮 offer',
          patch: {
            'summary': '用户接到作业帮 offer',
            'tags': ['工作', 'work', 'Emotion', 'career'],
          },
          sourceMessageIds: [1],
        ),
      ],
    );

    expect(operations.single.patch['tags'], ['Work', 'Emotion']);
  });

  test('conversation capture omits tags when tags.md has no labels', () {
    final operations = restrictOperationTagsToKnownTags(
      knownTags: const [],
      operations: const [
        SharedLifeOperationDraft(
          operationType: 'create',
          entityType: 'event',
          title: '今天很焦虑',
          patch: {
            'summary': '用户今天感到焦虑',
            'tags': ['Emotion'],
          },
          sourceMessageIds: [1],
        ),
      ],
    );

    expect(operations.single.patch.containsKey('tags'), isFalse);
  });
}
