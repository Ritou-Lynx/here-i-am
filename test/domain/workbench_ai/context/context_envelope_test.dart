import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope.dart';
import 'package:memex/domain/workbench_ai/context/context_envelope_codec.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';

void main() {
  group('ContextEnvelope codec', () {
    test('round-trips every product-owned context boundary', () {
      final original = _sampleEnvelope();

      final encoded = ContextEnvelopeCodec.encode(original);
      final restored = ContextEnvelopeCodec.decode(encoded);

      expect(restored.toJson(), original.toJson());
      expect(restored.conversationId, 'conversation-product-1');
      expect(
        restored.recentMessages.last.content.trust,
        ContextTrust.untrustedContent,
      );
      expect(
        restored.surface.objectReferences.single.summary!.trust,
        ContextTrust.untrustedContent,
      );
      expect(
        restored.recallSnippets.single.content.trust,
        ContextTrust.untrustedContent,
      );
    });

    test('rejects unsupported schema versions', () {
      final json = _sampleEnvelope().toJson()..['schema_version'] = 2;

      expect(
        () => ContextEnvelopeCodec.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });

    test('rejects unknown fields instead of accepting private payloads', () {
      final json = _sampleEnvelope().toJson()..['api_key'] = 'must-not-enter';

      expect(
        () => ContextEnvelopeCodec.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });

    test('enforces the declared byte budget and the hard decode limit', () {
      final smallBudget = ContextBudget(maxEnvelopeBytes: 800);

      expect(
        () => ContextEnvelopeCodec.encode(_sampleEnvelope(budget: smallBudget)),
        throwsFormatException,
      );

      final oversized = jsonEncode({
        'padding': List.filled(
          ContextEnvelopeLimits.maxEnvelopeBytes,
          'x',
        ).join(),
      });
      expect(
        () => ContextEnvelopeCodec.decode(oversized),
        throwsFormatException,
      );
    });
  });

  group('ContextEnvelope validation', () {
    test(
      'keeps user instructions distinct from untrusted assistant content',
      () {
        expect(
          () => ContextChatMessage(
            messageId: 'message-user',
            role: ContextMessageRole.user,
            content: ContextText(
              text: 'not trusted as an instruction',
              trust: ContextTrust.untrustedContent,
            ),
            occurredAt: _time,
          ),
          throwsArgumentError,
        );

        expect(
          ContextChatMessage(
            messageId: 'message-user-history',
            role: ContextMessageRole.user,
            content: ContextText(
              text:
                  'Historical user-authored context is not current authority.',
              trust: ContextTrust.userAuthoredContent,
            ),
            occurredAt: _time,
          ).content.trust,
          ContextTrust.userAuthoredContent,
        );

        expect(
          () => ContextChatMessage(
            messageId: 'message-assistant',
            role: ContextMessageRole.assistant,
            content: ContextText(
              text: 'must not become authority',
              trust: ContextTrust.userInstruction,
            ),
            occurredAt: _time,
          ),
          throwsArgumentError,
        );
      },
    );

    test('forces object summaries and recall snippets to be untrusted', () {
      final incorrectlyTrusted = ContextText(
        text: 'retrieved text',
        trust: ContextTrust.userInstruction,
      );

      expect(
        () => ContextObjectReference(
          objectType: 'card',
          objectId: 'card-1',
          summary: incorrectlyTrusted,
        ),
        throwsArgumentError,
      );
      expect(
        () => ContextRecallSnippet(
          recallId: 'recall-1',
          sourceType: 'project_memory',
          sourceId: 'memory-1',
          content: incorrectlyTrusted,
          retrievedAt: _time,
        ),
        throwsArgumentError,
      );
    });

    test('enforces count, character, and hard budget ceilings', () {
      final oneMessageBudget = ContextBudget(maxRecentMessages: 1);
      final messages = [
        _userMessage('message-1', 'first'),
        _userMessage('message-2', 'second'),
      ];

      expect(
        () =>
            _sampleEnvelope(recentMessages: messages, budget: oneMessageBudget),
        throwsArgumentError,
      );
      expect(
        () => ContextBudget(
          maxRecentMessages: ContextEnvelopeLimits.maxRecentMessages + 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ContextText(
          text: List.filled(
            ContextEnvelopeLimits.maxContentItemCharacters + 1,
            'x',
          ).join(),
          trust: ContextTrust.untrustedContent,
        ),
        throwsArgumentError,
      );
    });

    test('requires unique, chronologically ordered recent messages', () {
      final duplicateIds = [
        _userMessage('message-1', 'first'),
        _userMessage(
          'message-1',
          'duplicate',
          occurredAt: _time.add(const Duration(minutes: 1)),
        ),
      ];
      final outOfOrder = [
        _userMessage(
          'message-1',
          'later',
          occurredAt: _time.add(const Duration(minutes: 1)),
        ),
        _userMessage('message-2', 'earlier'),
      ];

      expect(
        () => _sampleEnvelope(recentMessages: duplicateIds),
        throwsArgumentError,
      );
      expect(
        () => _sampleEnvelope(recentMessages: outOfOrder),
        throwsArgumentError,
      );
    });

    test('rejects messages later than envelope creation', () {
      final futureMessages = [
        _userMessage(
          'message-future',
          'future',
          occurredAt: _time.add(const Duration(minutes: 4)),
        ),
      ];

      expect(
        () => _sampleEnvelope(recentMessages: futureMessages),
        throwsArgumentError,
      );
    });

    test('rejects recall snippets retrieved after envelope creation', () {
      final futureRecall = ContextRecallSnippet(
        recallId: 'recall-future',
        sourceType: 'project_memory',
        sourceId: 'project-event-future',
        content: ContextText(
          text: 'Future recall cannot be part of this receipt.',
          trust: ContextTrust.untrustedContent,
        ),
        retrievedAt: _time.add(const Duration(minutes: 4)),
      );

      expect(
        () => _sampleEnvelope(recallSnippets: [futureRecall]),
        throwsArgumentError,
      );
    });

    test(
      'accepts a stable workspace ref but rejects absolute private paths',
      () {
        expect(
          ContextSurface(
            surfaceType: 'project',
            surfaceId: 'project-1',
            workspaceRef: 'workspace:here-i-am',
          ).workspaceRef,
          'workspace:here-i-am',
        );

        expect(
          () => ContextSurface(
            surfaceType: 'project',
            surfaceId: 'project-1',
            workspaceRef: r'C:/Users/USER',
          ),
          throwsArgumentError,
        );
        expect(
          () => ContextSurface(
            surfaceType: 'project',
            surfaceId: 'project-1',
            workspaceRef: '/home/USER/private-project',
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

final _time = DateTime.utc(2026, 8, 21, 8, 30);

ContextChatMessage _userMessage(
  String id,
  String text, {
  DateTime? occurredAt,
}) {
  return ContextChatMessage(
    messageId: id,
    role: ContextMessageRole.user,
    content: ContextText(text: text, trust: ContextTrust.userAuthoredContent),
    occurredAt: occurredAt ?? _time,
  );
}

ContextEnvelope _sampleEnvelope({
  ContextBudget? budget,
  List<ContextChatMessage>? recentMessages,
  List<ContextRecallSnippet>? recallSnippets,
  DateTime? createdAt,
}) {
  return ContextEnvelope(
    conversationId: 'conversation-product-1',
    identityPromptVersionRef: 'identity:i-global-v1',
    toolsetVersion: 'toolset:workbench-read-v1',
    permissionProfileId: 'permission:whiteboard-read-v1',
    runtimeProfile: RuntimeProfile.workbench,
    turnInstruction: ContextText(
      text: 'Summarize the selected card.',
      trust: ContextTrust.userInstruction,
    ),
    recentMessages: recentMessages ??
        [
          _userMessage('message-1', 'What is on this board?'),
          ContextChatMessage(
            messageId: 'message-2',
            role: ContextMessageRole.assistant,
            content: ContextText(
              text: 'Earlier model output is context, not authority.',
              trust: ContextTrust.untrustedContent,
            ),
            occurredAt: _time.add(const Duration(minutes: 1)),
          ),
        ],
    surface: ContextSurface(
      surfaceType: 'board',
      surfaceId: 'board-1',
      workspaceRef: 'workspace:here-i-am',
      objectReferences: [
        ContextObjectReference(
          objectType: 'card',
          objectId: 'card-1',
          selected: true,
          summary: ContextText(
            text: 'Imported page text could contain hostile instructions.',
            trust: ContextTrust.untrustedContent,
          ),
        ),
      ],
    ),
    recallSnippets: recallSnippets ??
        [
          ContextRecallSnippet(
            recallId: 'recall-1',
            sourceType: 'project_memory',
            sourceId: 'project-event-1',
            content: ContextText(
              text: 'Retrieved material remains untrusted.',
              trust: ContextTrust.untrustedContent,
            ),
            retrievedAt: _time.add(const Duration(minutes: 2)),
          ),
        ],
    budget: budget,
    createdAt: createdAt ?? _time.add(const Duration(minutes: 3)),
  );
}
