import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'capture_consumer.dart';
import 'domain_protocol.dart';
import 'domain_store.dart';
import 'quick_capture_models.dart';

/// A host-authorized issuer must bind the reviewed UI action and the exact
/// final intent to Core's trusted authorization verifier. The request includes
/// the immutable op id, base revision and timestamps and never accepts an
/// arbitrary caller-supplied ref.
typedef QuickCaptureAuthorizationIssuer = Future<String> Function(
    Json authorizationRequest);

class QuickCaptureDomainAdapter {
  QuickCaptureDomainAdapter({
    required this.store,
    this.consumer,
    this.issueAuthorization,
  });
  final DomainStore store;
  final CaptureConsumer? consumer;
  final QuickCaptureAuthorizationIssuer? issueAuthorization;

  /// Called only by the send Command, after the user reviewed the text.
  Future<QuickCaptureResult> submit(QuickCaptureDraft draft) async {
    final id = draft.captureId;
    final text = draft.text.trim();
    if (id == null || id.isEmpty || text.isEmpty || text.length > 2000) {
      throw const DomainFailure('invalid_capture');
    }
    await store.db.transaction(() async {
      final state = await store.read();
      final domain = store.domain(state, 'captures');
      store.checkBinding(domain, 'captures');
      final current = (await store.visible(
        'captures',
      ))
          .where((r) => r['id'] == id)
          .firstOrNull;
      if (current?['data']?['text'] == text) return;
      // Never silently revive a deleted capture or change another source.
      if (current != null && current['data']?['source'] != 'phone_quick') {
        throw const DomainFailure('capture_source_mismatch');
      }
      final actionId = const Uuid().v4();
      final evidence = <String, dynamic>{
        'action_id': actionId,
        'domain': 'captures',
        'capture_id': id,
        'action': current == null ? 'create' : 'patch',
        'actor': 'user_direct',
        'surface': 'quick_capture_send',
        'text_sha256': sha256.convert(utf8.encode(text)).toString(),
        'occurred_at': store.clock().toUtc().toIso8601String(),
        'binding': store.binding.forDomain('captures'),
      };
      final route = domain['route'] as String;
      if (route != 'phone' && issueAuthorization == null) {
        throw const DomainFailure('capture_authorization_not_configured');
      }
      Json? signedRequest;
      String? signedRef;
      final opId = await store.enqueue(
        'captures',
        id: id,
        kind: current == null ? 'create' : 'patch',
        actor: 'user_direct',
        authorizationRef: route == 'phone' ? 'local-ui:$actionId' : null,
        authorizeIntent: route == 'phone'
            ? null
            : (intent) async {
                final request = <String, dynamic>{
                  ...evidence,
                  'intent': copyJson(intent),
                };
                final ref = await issueAuthorization!(copyJson(request));
                signedRequest = request;
                signedRef = ref;
                return ref;
              },
        fields: current == null
            ? {
                'data': {
                  'text': text,
                  'source': 'phone_quick',
                  'recorded_at': store.clock().toUtc().toIso8601String(),
                },
                'provenance': {
                  'source': 'phone_quick',
                  'source_refs': [],
                  'import_batch_id': null,
                },
              }
            : {
                'patch': {'text': text},
              },
      );
      final ref = signedRef ?? 'local-ui:$actionId';
      await store.db.customStatement(
        'INSERT INTO kv_store(key,value,bucket,updated_at) VALUES(?,?,?,?)',
        [
          'quick_capture_action.$actionId',
          jsonEncode({
            ...evidence,
            'authorization_ref': ref,
            'op_id': opId,
            if (signedRequest != null)
              'intent_sha256': domainDigest(signedRequest!['intent']),
          }),
          'quick_capture_authorization',
          store.clock().millisecondsSinceEpoch,
        ],
      );
    });
    return readResult(id);
  }

  Future<QuickCaptureResult> readResult(String id) async {
    final records = await store.visible('captures');
    final row = records.where((r) => r['id'] == id).firstOrNull;
    if (row == null) throw const DomainFailure('capture_unavailable');
    final state = await store.read();
    final route = store.domain(state, 'captures')['route'];
    final data = jsonObject(row['data']);
    final localResult = await consumer?.processingResult(id,
        expectedText: data['text'] as String);
    final problems = await store.problems();
    final issues =
        consumer == null ? <Json>[] : await consumer!.pendingIssues();
    final unsent = (state['outbox'] as List).any(
      (o) =>
          o['domain'] == 'captures' &&
          o['id'] == id &&
          !['accepted', 'duplicate'].contains(o['state']),
    );
    dynamic disposition(String p) =>
        p == 'organizer' && localResult != null ? localResult : data[p];
    String status(String processor) =>
        switch (disposition(processor)?['status']) {
          'done' => '已处理',
          'skipped' => '无需处理',
          _ => '待处理',
        };
    List<String> outputs(String p) =>
        (disposition(p)?['outputs'] as List? ?? [])
            .whereType<String>()
            .toList();
    return QuickCaptureResult(
      captureId: id,
      text: data['text'] as String,
      deliveryMessage: route == 'phone'
          ? '已保存在本机，尚未启用同步'
          : unsent
              ? '已保存在本机，待发送'
              : '已到电脑',
      organizerMessage: '生活记录：${status('organizer')}',
      plannerMessage: '待办与时间：${status('planner')}',
      organizerOutputs: outputs('organizer'),
      plannerOutputs: outputs('planner'),
      pendingIssues: [
        for (final p in problems.where((p) => p['id'] == id))
          p['reason'] == 'binding_changed'
              ? '连接信息已变更，请检查连接设置。'
              : '此条同步需要处理，请查看连接与同步设置。',
        for (final p in issues.where((p) => p['capture_id'] == id))
          p['message'] as String,
      ],
    );
  }

  Future<List<QuickCaptureResult>> recent() async {
    final rows = (await store.visible(
      'captures',
    ))
        .where((r) => r['data']?['source'] == 'phone_quick')
        .toList()
      ..sort(
        (a, b) => (b['data']['recorded_at'] as String).compareTo(
          a['data']['recorded_at'] as String,
        ),
      );
    return Future.wait(rows.take(3).map((r) => readResult(r['id'] as String)));
  }

  Future<Json?> authorizationEvidence(String ref) async {
    final rows = await store.db.customSelect(
      "SELECT value FROM kv_store WHERE bucket = ?",
      variables: [const Variable('quick_capture_authorization')],
    ).get();
    for (final row in rows) {
      final value = jsonObject(jsonDecode(row.read<String>('value')));
      if (value['authorization_ref'] == ref) return value;
    }
    return null;
  }
}
