import 'dart:math';
import 'domain_protocol.dart';
import 'domain_store.dart';

class DomainSyncEngine {
  DomainSyncEngine(this.store, this.transport, {Random? random})
      : random = random ?? Random();
  final DomainStore store;
  final DomainTransport transport;
  final Random random;
  bool _running = false;

  Future<void> syncOnce(String domain) async {
    if (_running) return;
    _running = true;
    try {
      await store.runRetention();
      final state = await store.read();
      final d = store.domain(state, domain);
      store.checkBinding(d, domain);
      if (d['route'] == 'phone') return;
      // Ack only a previously committed local cursor, including after a crash.
      if (d['route'] == 'core' && d['cursor'] != null) {
        try {
          await transport.acknowledge(domain, d['cursor'],
              snapshotId: d['ack_snapshot_id']);
        } on DomainFailure catch (e) {
          if (e.code != 'resync_required') rethrow;
          await store.invalidateReplica(domain);
          await rebuild(domain);
        }
      }
      for (var i = 0; i < 100; i++) {
        final o = await store.prepare(domain);
        if (o == null) break;
        await store.fault('submit_after_local_commit');
        try {
          Json? result;
          String? targetState;
          if (o['query_first'] == true) {
            try {
              final lookup = await transport.operation(domain, o['op_id']);
              targetState = lookup['target_state'] as String?;
              result = lookup['transport_state'] == 'shadow_staged'
                  ? lookup
                  : jsonObject(lookup['result']);
            } on DomainFailure catch (e) {
              if (e.code != 'op_not_found') rethrow;
            }
          }
          if (result == null &&
              (o['lookup_only'] == true ||
                  o['payload_purged'] == true ||
                  o['payload_expired'] == true)) {
            throw const DomainFailure(
                'operation_not_found_after_payload_purge');
          }
          result ??= await transport.submit(domain, jsonObject(o['intent']));
          await store.fault('response_before_save');
          await store.complete(o['op_id'], result, targetState: targetState);
          await store.fault('receipt_after_commit');
        } on DomainFailure catch (e) {
          final temporary = e.retryable ||
              [
                'domain_off',
                'domain_frozen',
                'schema_not_ready',
                'domain_capacity_exceeded',
                'core_not_ready'
              ].contains(e.code);
          final seconds =
              min(300, 2 * pow(2, min(8, o['attempts'] as int)).toInt());
          final jitterDelay = Duration(
              milliseconds:
                  (seconds * 1000 * (0.8 + random.nextDouble() * 0.4)).round());
          final delay = e.retryAfter != null && e.retryAfter! > jitterDelay
              ? e.retryAfter!
              : jitterDelay;
          await store.defer(o['op_id'], e.code,
              requiresAction: !temporary, delay: delay);
          break;
        }
      }
      if (d['route'] == 'shadow') return;
      final cursor =
          store.domain(await store.read(), domain)['cursor'] as String?;
      try {
        final page = await transport.changes(domain, cursor);
        await store.applyPage(domain, page,
            expectedCursor: cursor, compareCursor: true);
        await transport.acknowledge(domain, page['next_cursor']);
      } on DomainFailure catch (e) {
        if (e.code != 'resync_required') rethrow;
        await rebuild(domain);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> rebuild(String domain) async {
    final initial = store.domain(await store.read(), domain);
    final expectedCursor = initial['cursor'] as String?;
    final expectedReplicaVersion = initial['replica_version'] as int? ?? 0;
    final records = <Json>[];
    Json? stableManifest;
    String? snapshotToken, pageToken, snapshotId;
    for (var pages = 0; pages < 4096; pages++) {
      final page = await transport.snapshot(domain,
          snapshotToken: snapshotToken, pageToken: pageToken);
      if (jsonBytes(page) > DomainPolicy.maxPageBytes) {
        throw const DomainFailure('invalid_page');
      }
      final manifest = jsonObject(page['manifest']);
      final pageRecords = (page['records'] as List).map(jsonObject).toList();
      for (final e in store.binding.forDomain(domain).entries) {
        if (manifest[e.key] != e.value) {
          throw const DomainFailure('snapshot_binding_mismatch');
        }
      }
      if (manifest['manifest_auth'] is! String ||
          (manifest['manifest_auth'] as String).isEmpty ||
          manifest['schema_version'] is! int ||
          manifest['policy_version'] != store.binding.policyVersion ||
          !store.clock().isBefore(DateTime.parse(manifest['expires_at']))) {
        throw const DomainFailure('snapshot_invalid');
      }
      if (page['page_digest'] != domainDigest(pageRecords)) {
        throw const DomainFailure('page_digest_mismatch');
      }
      snapshotId ??= page['snapshot_id'];
      snapshotToken ??= page['snapshot_token'];
      final stable = copyJson(manifest)
        ..remove('base_cursor')
        ..remove('manifest_auth');
      stableManifest ??= stable;
      if (page['snapshot_id'] != snapshotId ||
          manifest['snapshot_id'] != snapshotId ||
          canonicalJson(stable) != canonicalJson(stableManifest)) {
        throw const DomainFailure('snapshot_changed');
      }
      final seen = records.map((r) => r['id']).toSet();
      for (final r in pageRecords) {
        if (!seen.add(r['id'])) {
          throw const DomainFailure('snapshot_duplicate_record');
        }
        records.add(r);
      }
      if (jsonBytes(records) > 268435456) {
        throw const DomainFailure('snapshot_too_large');
      }
      if (page['has_more'] == false) {
        if (manifest['base_cursor'] is! String ||
            manifest['collection_digest'] != domainDigest(records)) {
          throw const DomainFailure('collection_digest_mismatch');
        }
        // Authentication is provided by configured TLS + opaque server tag.
        // The client never pretends to possess the Core HMAC signing secret.
        await store.replaceSnapshot(domain, records, manifest,
            expectedCursor: expectedCursor,
            compareCursor: true,
            expectedReplicaVersion: expectedReplicaVersion);
        await store.fault('snapshot_after_commit');
        try {
          await transport.acknowledge(domain, manifest['base_cursor'],
              snapshotId: snapshotId);
        } on DomainFailure catch (e) {
          if (e.code == 'resync_required') {
            await store.invalidateReplica(domain);
          }
          rethrow;
        }
        return;
      }
      final next = page['next_page_token'];
      if (next is! String || next == pageToken || pageRecords.isEmpty) {
        throw const DomainFailure('snapshot_missing_page');
      }
      pageToken = next;
    }
    throw const DomainFailure('snapshot_too_many_pages');
  }
}
