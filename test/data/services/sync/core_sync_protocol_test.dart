import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/sync/core_sync_protocol.dart';

void main() {
  test('health response round-trips and identifies authority', () {
    const value = CoreHealthResponse(
      ok: true,
      nodeId: 'home-core',
      role: 'authority',
      protocolVersion: CoreSyncProtocol.version,
      minimumProtocolVersion: CoreSyncProtocol.version,
      schemaVersion: 55,
      serverTimeMs: 1786550400000,
      features: ['chat_submit', 'change_feed'],
    );

    final decoded = CoreHealthResponse.fromJson(
      jsonDecode(jsonEncode(value.toJson())) as Map<String, dynamic>,
    );

    expect(decoded.isAuthority, isTrue);
    expect(decoded.nodeId, 'home-core');
    expect(decoded.features, contains('change_feed'));
  });

  test('device pairing models use installation id and opaque cursor', () {
    const request = CoreDevicePairRequest(
      deviceId: 'device-a',
      displayName: '主力手机',
      platform: 'android',
      clientVersion: '1.0.0+1',
      pairingCode: '123456',
      capabilities: ['chat', 'share'],
    );
    const response = CoreDevicePairResponse(
      deviceId: 'device-a',
      deviceToken: 'secret-token',
      initialCursor: 'opaque:zero',
      coreNodeId: 'home-core',
      protocolVersion: CoreSyncProtocol.version,
    );

    expect(
        CoreDevicePairRequest.fromJson(request.toJson()).displayName, '主力手机');
    expect(
      CoreDevicePairResponse.fromJson(response.toJson()).initialCursor,
      'opaque:zero',
    );
  });

  test('chat submission round-trips without local database ids', () {
    final request = CoreChatSubmitRequest(
      deviceId: 'device-a',
      messages: const [
        CoreChatMessageWire(
          syncId: 'message-uuid',
          originDeviceId: 'device-a',
          originSequence: 42,
          characterId: 'lin-ai',
          sender: CoreMessageSender.user,
          content: '我到家了',
          createdAtMs: 1786550400000,
          assetRefs: [
            CoreAssetRef(
              assetId: 'asset-uuid',
              mimeType: 'image/webp',
              sha256: 'abc123',
              byteLength: 1234,
              fileName: 'share.webp',
            ),
          ],
          addenda: [
            {'type': 'shared_context', 'source': 'android_share'}
          ],
        ),
      ],
    );

    final json = request.toJson();
    final decoded = CoreChatSubmitRequest.fromJson(
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
    );

    expect(json.toString(), isNot(contains('local_id')));
    expect(decoded.messages.single.syncId, 'message-uuid');
    expect(decoded.messages.single.originSequence, 42);
    expect(decoded.messages.single.assetRefs.single.byteLength, 1234);
  });

  test('submit response preserves accepted and duplicate outcomes', () {
    const response = CoreChatSubmitResponse(
      results: [
        CoreChatSubmitResult(
          syncId: 'one',
          status: CoreSubmitStatus.accepted,
          serverSequence: 11,
        ),
        CoreChatSubmitResult(
          syncId: 'two',
          status: CoreSubmitStatus.duplicate,
          serverSequence: 9,
        ),
      ],
      nextCursor: 'opaque:11',
    );

    final decoded = CoreChatSubmitResponse.fromJson(response.toJson());

    expect(decoded.results.first.status, CoreSubmitStatus.accepted);
    expect(decoded.results.last.status, CoreSubmitStatus.duplicate);
    expect(decoded.nextCursor, 'opaque:11');
  });

  test('change feed keeps unknown future kinds forward compatible', () {
    final page = CoreChangePage.fromJson({
      'events': [
        {
          'event_id': 'event-1',
          'server_sequence': 12,
          'kind': 'whiteboard.future_kind',
          'entity_id': 'entity-1',
          'occurred_at_ms': 1786550400000,
          'payload': {'future': true},
        }
      ],
      'next_cursor': 'opaque:12',
      'has_more': false,
    });

    expect(page.events.single.kind, 'whiteboard.future_kind');
    expect(page.nextCursor, 'opaque:12');
  });

  test('cursor ack and API error round-trip', () {
    const ack = CoreCursorAckRequest(
      deviceId: 'device-a',
      cursor: 'opaque:12',
    );
    const error = CoreApiErrorBody(
      code: 'immutable_message_conflict',
      message: 'sync id already exists with different content',
      retryable: false,
      details: {'sync_id': 'message-uuid'},
    );

    expect(CoreCursorAckRequest.fromJson(ack.toJson()).cursor, 'opaque:12');
    expect(CoreApiErrorBody.fromJson(error.toJson()).retryable, isFalse);
  });

  test('invalid required fields and oversized batches are rejected', () {
    expect(
      () => CoreChatMessageWire.fromJson({
        'sync_id': '',
        'origin_device_id': 'device-a',
        'origin_sequence': 1,
        'character_id': 'lin-ai',
        'sender': 'user',
        'content': 'hello',
        'created_at_ms': 1,
        'message_type': 'chat',
      }),
      throwsFormatException,
    );
    expect(
      () => CoreChatSubmitRequest(deviceId: 'device-a', messages: const []),
      throwsArgumentError,
    );
    expect(
      () => CoreMessageSender.parse('unknown'),
      throwsFormatException,
    );
    expect(
      () => CoreChatSubmitRequest(
        deviceId: 'device-a',
        messages: const [
          CoreChatMessageWire(
            syncId: 'message-uuid',
            originDeviceId: 'device-b',
            originSequence: 1,
            characterId: 'lin-ai',
            sender: CoreMessageSender.user,
            content: 'hello',
            createdAtMs: 1,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
}
