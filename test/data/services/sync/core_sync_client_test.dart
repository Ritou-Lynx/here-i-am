import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/core_sync_client.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';

/// Boots a throwaway i core via the Node harness. Returns base URL + process
/// so the test can terminate it.
Future<(String, Process)> _startCore() async {
  final process = await Process.start(
    'node',
    [
      'test/data/services/sync/_core_server_harness.mjs',
      '654321',
    ],
  );
  final url = await process.stdout
      .transform(utf8.decoder)
      .firstWhere((line) => line.trim().startsWith('http://'));
  return (url.trim(), process);
}

void main() {
  test('pair, submit, fetch changes and ack round-trip against a real core',
      () async {
    final (baseUrl, core) = await _startCore();
    try {
      // Pair a device.
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: const CoreDevicePairRequest(
          deviceId: 'dart-client-a',
          displayName: 'Dart test client',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
          capabilities: ['chat'],
        ),
      );
      expect(pair.coreNodeId, isNotEmpty);
      expect(pair.protocolVersion, CoreSyncProtocol.version);
      expect(pair.initialCursor, isNotEmpty);

      final client = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: pair.deviceToken,
      );

      // Health reports an authority core.
      final health = await client.health();
      expect(health.isAuthority, isTrue);
      expect(health.protocolVersion, CoreSyncProtocol.version);

      // Submit two messages; the second one duplicated is idempotent.
      final submit = await client.submitMessages(CoreChatSubmitRequest(
        deviceId: pair.deviceId,
        messages: [
          CoreChatMessageWire(
            syncId: 'msg-1',
            originDeviceId: pair.deviceId,
            originSequence: 1,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: '我到家了',
            createdAtMs: 1786550400000,
          ),
          CoreChatMessageWire(
            syncId: 'msg-2',
            originDeviceId: pair.deviceId,
            originSequence: 2,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: '晚饭想吃面',
            createdAtMs: 1786550460000,
          ),
        ],
      ));
      expect(submit.results, hasLength(2));
      expect(submit.results.every((r) => r.status == CoreSubmitStatus.accepted),
          isTrue);
      // server_sequence is strictly increasing by arrival order.
      expect(submit.results[0].serverSequence,
          lessThan(submit.results[1].serverSequence));

      final duplicate = await client.submitMessages(CoreChatSubmitRequest(
        deviceId: pair.deviceId,
        messages: [
          CoreChatMessageWire(
            syncId: 'msg-1',
            originDeviceId: pair.deviceId,
            originSequence: 1,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: '我到家了',
            createdAtMs: 1786550400000,
          ),
        ],
      ));
      expect(duplicate.results.single.status, CoreSubmitStatus.duplicate);

      // Change feed replays both messages in server order.
      var page = await client.fetchChanges(cursor: pair.initialCursor);
      final events = [...page.events];
      while (page.hasMore) {
        page = await client.fetchChanges(cursor: page.nextCursor);
        events.addAll(page.events);
      }
      expect(events.map((e) => e.kind), everyElement('chat.message.upsert'));
      expect(events.map((e) => e.entityId), containsAll(['msg-1', 'msg-2']));

      // Ack is accepted.
      await client.acknowledgeCursor(cursor: page.nextCursor);
    } finally {
      core.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('protocol failures surface as typed CoreSyncException', () async {
    final (baseUrl, core) = await _startCore();
    try {
      // Pair, then talk with a garbage token -> 401 unauthorized.
      final pair = await CoreSyncClient.pair(
        baseUrl: baseUrl,
        request: const CoreDevicePairRequest(
          deviceId: 'dart-client-b',
          displayName: 'Dart test client B',
          platform: 'test',
          clientVersion: '0.1',
          pairingCode: '654321',
        ),
      );
      final bad = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: 'not-a-real-token',
      );
      // health is public; use an authenticated endpoint to exercise 401.
      await expectLater(
        bad.fetchChanges(cursor: pair.initialCursor),
        throwsA(isA<CoreSyncException>()
            .having((e) => e.code, 'code', 'unauthorized')
            .having((e) => e.retryable, 'retryable', isFalse)),
      );

      // Wrong protocol version -> 426 protocol_mismatch (authenticated
      // endpoint; health is public and skips protocol negotiation).
      final wrongProtocol = CoreSyncClient(
        baseUrl: baseUrl,
        deviceId: pair.deviceId,
        deviceToken: pair.deviceToken,
        protocolVersion: '9.9',
      );
      await expectLater(
        wrongProtocol.fetchChanges(cursor: pair.initialCursor),
        throwsA(isA<CoreSyncException>()
            .having((e) => e.code, 'code', 'protocol_mismatch')),
      );
    } finally {
      core.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
