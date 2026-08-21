import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_codec.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_projection.dart';
import 'package:memex/domain/workbench_ai/runtime/runtime_session_binding.dart';

void main() {
  group('RuntimeSessionBinding', () {
    test('round-trips product and opaque provider identities separately', () {
      final original = _binding();

      final restored = RuntimeSessionBindingCodec.decode(
        RuntimeSessionBindingCodec.encode(original),
      );

      expect(restored.toJson(), original.toJson());
      expect(restored.conversationId, 'conversation-product-1');
      expect(
        restored.providerSessionId,
        'opaque:runtime/thread?part=1#片段 / untouched',
      );
      expect(restored.providerSessionId, isNot(restored.conversationId));
    });

    test('rejects unsupported versions and unknown product fields', () {
      final unsupported = _binding().toJson()..['schema_version'] = 2;
      final leaked = _binding().toJson()..['raw_prompt'] = 'private';

      expect(
        () => RuntimeSessionBindingCodec.decode(jsonEncode(unsupported)),
        throwsFormatException,
      );
      expect(
        () => RuntimeSessionBindingCodec.decode(jsonEncode(leaked)),
        throwsFormatException,
      );
    });

    test('guards private fields in provider metadata at every depth', () {
      final privatePayloads = <Map<String, Object?>>[
        {'accessToken': 'must-not-enter'},
        {'api-key': 'must-not-enter'},
        {'user_email': 'private@example.com'},
        {'authorization_header': 'Bearer private'},
        {
          'nested': {'refresh-token': 'must-not-enter'},
        },
        {'raw log archive': 'private runtime output'},
      ];

      for (final payload in privatePayloads) {
        expect(() => ProviderMetadata(payload), throwsArgumentError);
      }
    });

    test('keeps metadata generic without defining provider-private fields', () {
      final metadata = ProviderMetadata({
        'runtime_version': '0.142.4',
        'auth_mode': 'chatgpt',
        'token_usage': 42,
        'capabilities': ['resume', 'approval'],
      });

      expect(
        metadata.toJson().keys,
        containsAll([
          'runtime_version',
          'auth_mode',
          'token_usage',
          'capabilities',
        ]),
      );
    });

    test('rejects illegal transitions while allowing interrupted recovery', () {
      final interrupted = _binding().transitionTo(
        RuntimeSessionStatus.interrupted,
        at: _time.add(const Duration(minutes: 1)),
      );
      final resumed = interrupted.transitionTo(
        RuntimeSessionStatus.active,
        at: _time.add(const Duration(minutes: 2)),
      );
      final closed = resumed.transitionTo(
        RuntimeSessionStatus.closed,
        at: _time.add(const Duration(minutes: 3)),
      );

      expect(resumed.status, RuntimeSessionStatus.active);
      expect(closed.closedAt, _time.add(const Duration(minutes: 3)));
      expect(
        () => closed.transitionTo(
          RuntimeSessionStatus.active,
          at: _time.add(const Duration(minutes: 4)),
        ),
        throwsStateError,
      );
    });

    test('rejects session transition timestamps before last activity', () {
      final interrupted = _binding().transitionTo(
        RuntimeSessionStatus.interrupted,
        at: _time.add(const Duration(minutes: 2)),
      );

      expect(
        () => interrupted.transitionTo(
          RuntimeSessionStatus.active,
          at: _time.add(const Duration(minutes: 1)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Runtime approval and error projections', () {
    test('requires explicit user evidence for high-risk approval', () {
      final approval = _pendingApproval(RuntimeApprovalRisk.high);

      expect(
        () => approval.resolve(
          decision: RuntimeApprovalStatus.approved,
          source: RuntimeApprovalDecisionSource.policy,
          at: _time.add(const Duration(minutes: 1)),
        ),
        throwsArgumentError,
      );

      final approved = approval.resolve(
        decision: RuntimeApprovalStatus.approved,
        source: RuntimeApprovalDecisionSource.user,
        at: _time.add(const Duration(minutes: 1)),
        authorizationMessageId: 'message-authorization-1',
      );
      expect(approved.status, RuntimeApprovalStatus.approved);
      expect(
        () => approved.resolve(
          decision: RuntimeApprovalStatus.denied,
          source: RuntimeApprovalDecisionSource.user,
          at: _time.add(const Duration(minutes: 2)),
          authorizationMessageId: 'message-authorization-2',
        ),
        throwsStateError,
      );
    });

    test('failed status requires a safe product error projection', () {
      expect(
        () => RuntimeTurnProjection(
          turnId: 'turn-1',
          runtimeSessionId: 'binding-1',
          userMessageId: 'message-user-1',
          contextManifestRef: 'manifest:turn-1',
          contextManifestHash: _manifestHash,
          status: RuntimeTurnStatus.failed,
          displayMessage: 'Not completed',
          createdAt: _time,
          updatedAt: _time,
          startedAt: _time,
          completedAt: _time,
        ),
        throwsArgumentError,
      );

      final failed = RuntimeTurnProjection(
        turnId: 'turn-1',
        runtimeSessionId: 'binding-1',
        userMessageId: 'message-user-1',
        contextManifestRef: 'manifest:turn-1',
        contextManifestHash: _manifestHash,
        status: RuntimeTurnStatus.failed,
        displayMessage: 'The runtime is temporarily unavailable.',
        error: RuntimeErrorProjection(
          code: 'runtime_unavailable',
          category: RuntimeErrorCategory.providerUnavailable,
          message: 'The runtime is temporarily unavailable.',
          retryable: true,
          evidenceRef: 'artifact:error-details-1',
        ),
        createdAt: _time,
        updatedAt: _time,
        startedAt: _time,
        completedAt: _time,
      );
      expect(failed.error!.retryable, isTrue);
      expect(failed.toJson(), isNot(contains('stack_trace')));
    });
  });

  group('RuntimeTurnProjection state machine and codec', () {
    test('round-trips an approval-resolved completion path', () {
      final queued = _queuedTurn();
      final running = queued.transitionTo(
        RuntimeTurnStatus.running,
        at: _time.add(const Duration(seconds: 1)),
        displayMessage: 'Reading selected cards',
        providerTurnId: 'opaque:turn/id?value=1#片段',
      );
      final pending = _pendingApproval(RuntimeApprovalRisk.elevated);
      final waiting = running.transitionTo(
        RuntimeTurnStatus.waitingApproval,
        at: _time.add(const Duration(seconds: 2)),
        displayMessage: 'Confirmation is required',
        approval: pending,
      );
      final resolved = pending.resolve(
        decision: RuntimeApprovalStatus.approved,
        source: RuntimeApprovalDecisionSource.user,
        at: _time.add(const Duration(seconds: 3)),
        authorizationMessageId: 'message-authorization-1',
      );
      final resumed = waiting.transitionTo(
        RuntimeTurnStatus.running,
        at: _time.add(const Duration(seconds: 3)),
        displayMessage: 'Continuing',
        approval: resolved,
      );
      final completed = resumed.transitionTo(
        RuntimeTurnStatus.completed,
        at: _time.add(const Duration(seconds: 4)),
        displayMessage: 'Completed',
        resultSummary: 'Completed with verified results',
        approval: resolved,
      );

      final restored = RuntimeTurnProjectionCodec.decode(
        RuntimeTurnProjectionCodec.encode(completed),
      );
      expect(restored.toJson(), completed.toJson());
      expect(restored.providerTurnId, 'opaque:turn/id?value=1#片段');
      expect(restored.userMessageId, 'message-user-1');
      expect(restored.contextManifestRef, 'manifest:turn-1');
      expect(restored.contextManifestHash, _manifestHash);
      expect(restored.displayMessage, 'Completed');
      expect(restored.resultSummary, 'Completed with verified results');
      expect(restored.status, RuntimeTurnStatus.completed);
      expect(restored.approval!.status, RuntimeApprovalStatus.approved);
    });

    test('rejects illegal and unresolved approval transitions', () {
      final queued = _queuedTurn();

      expect(
        () => queued.transitionTo(
          RuntimeTurnStatus.completed,
          at: _time.add(const Duration(seconds: 1)),
          displayMessage: 'Impossible',
        ),
        throwsStateError,
      );

      final running = queued.transitionTo(
        RuntimeTurnStatus.running,
        at: _time.add(const Duration(seconds: 1)),
        displayMessage: 'Running',
      );
      final waiting = running.transitionTo(
        RuntimeTurnStatus.waitingApproval,
        at: _time.add(const Duration(seconds: 2)),
        displayMessage: 'Waiting',
        approval: _pendingApproval(RuntimeApprovalRisk.low),
      );

      expect(
        () => waiting.transitionTo(
          RuntimeTurnStatus.running,
          at: _time.add(const Duration(seconds: 3)),
          displayMessage: 'Cannot silently continue',
        ),
        throwsStateError,
      );
    });

    test('rejects unsupported projection versions', () {
      final json = _queuedTurn().toJson()..['schema_version'] = 99;

      expect(
        () => RuntimeTurnProjectionCodec.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });

    test('rejects backward turn timestamps', () {
      final running = _queuedTurn().transitionTo(
        RuntimeTurnStatus.running,
        at: _time.add(const Duration(seconds: 2)),
        displayMessage: 'Running',
      );

      expect(
        () => running.transitionTo(
          RuntimeTurnStatus.waitingInput,
          at: _time.add(const Duration(seconds: 1)),
          displayMessage: 'Waiting for input',
        ),
        throwsArgumentError,
      );
    });

    test('rejects inconsistent timestamp ordering during restoration', () {
      final running = _queuedTurn().transitionTo(
        RuntimeTurnStatus.running,
        at: _time.add(const Duration(seconds: 2)),
        displayMessage: 'Running',
      );
      final updatedBeforeStarted = running.toJson()
        ..['updated_at'] =
            _time.add(const Duration(seconds: 1)).toIso8601String();

      final completed = _queuedTurn()
          .transitionTo(
            RuntimeTurnStatus.running,
            at: _time.add(const Duration(seconds: 1)),
            displayMessage: 'Running',
          )
          .transitionTo(
            RuntimeTurnStatus.completed,
            at: _time.add(const Duration(seconds: 3)),
            displayMessage: 'Completed',
            resultSummary: 'Verified result',
          );
      final updatedBeforeCompleted = completed.toJson()
        ..['updated_at'] =
            _time.add(const Duration(seconds: 2)).toIso8601String();

      expect(
        () => RuntimeTurnProjectionCodec.decode(
          jsonEncode(updatedBeforeStarted),
        ),
        throwsArgumentError,
      );
      expect(
        () => RuntimeTurnProjectionCodec.decode(
          jsonEncode(updatedBeforeCompleted),
        ),
        throwsArgumentError,
      );
    });

    test('strictly validates audit links, hash, result, and unknown fields',
        () {
      final invalidHash = _queuedTurn().toJson()
        ..['context_manifest_hash'] = 'not-a-sha256';
      final unknown = _queuedTurn().toJson()
        ..['context_manifest_json'] = {'raw_prompt': 'must-not-enter'};
      final oversizedMessageId = _queuedTurn().toJson()
        ..['user_message_id'] = List.filled(257, 'm').join();
      final completed = _queuedTurn()
          .transitionTo(
            RuntimeTurnStatus.running,
            at: _time.add(const Duration(seconds: 1)),
            displayMessage: 'Running',
          )
          .transitionTo(
            RuntimeTurnStatus.completed,
            at: _time.add(const Duration(seconds: 2)),
            displayMessage: 'Completed',
            resultSummary: 'A valid result',
          );
      final oversizedResult = completed.toJson()
        ..['result_summary'] = List.filled(4097, 'r').join();

      expect(
        () => RuntimeTurnProjectionCodec.decode(jsonEncode(invalidHash)),
        throwsArgumentError,
      );
      expect(
        () => RuntimeTurnProjectionCodec.decode(jsonEncode(unknown)),
        throwsFormatException,
      );
      expect(
        () => RuntimeTurnProjectionCodec.decode(jsonEncode(oversizedMessageId)),
        throwsArgumentError,
      );
      expect(
        () => RuntimeTurnProjectionCodec.decode(jsonEncode(oversizedResult)),
        throwsArgumentError,
      );
      expect(
        () => RuntimeTurnProjection(
          turnId: 'turn-1',
          runtimeSessionId: 'binding-1',
          userMessageId: 'message-user-1',
          contextManifestRef: 'manifest:turn-1',
          contextManifestHash: _manifestHash,
          displayMessage: 'Still running',
          resultSummary: 'Must not appear before a terminal state',
          createdAt: _time,
          updatedAt: _time,
        ),
        throwsArgumentError,
      );
    });
  });
}

final _time = DateTime.utc(2026, 8, 21, 9);
const _manifestHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

RuntimeSessionBinding _binding() {
  return RuntimeSessionBinding(
    id: 'binding-1',
    conversationId: 'conversation-product-1',
    provider: 'codex',
    providerSessionId: 'opaque:runtime/thread?part=1#片段 / untouched',
    profile: RuntimeProfile.workbench,
    scopeType: RuntimeScopeType.board,
    scopeId: 'board-1',
    providerMetadata: ProviderMetadata({
      'runtime_version': '0.142.4',
      'auth_mode': 'chatgpt',
    }),
    createdAt: _time,
    lastActiveAt: _time,
  );
}

RuntimeApprovalProjection _pendingApproval(RuntimeApprovalRisk risk) {
  return RuntimeApprovalProjection.pending(
    approvalId: 'approval-1',
    risk: risk,
    title: 'Confirm operation',
    summary: 'This operation needs deterministic permission evaluation.',
    requestedAt: _time,
  );
}

RuntimeTurnProjection _queuedTurn() {
  return RuntimeTurnProjection(
    turnId: 'turn-1',
    runtimeSessionId: 'binding-1',
    userMessageId: 'message-user-1',
    contextManifestRef: 'manifest:turn-1',
    contextManifestHash: _manifestHash,
    displayMessage: 'Queued',
    createdAt: _time,
    updatedAt: _time,
  );
}
