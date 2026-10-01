import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

// The same file is also verified in a byte-identical SDK-only test mirror.
// ignore: avoid_relative_lib_imports
import '../../../../../lib/data/services/activity/mda2_android/android_activity_normalizer.dart';

final class Rig {
  Rig({
    AndroidActivitySource source = AndroidActivitySource.usageEvents,
    int ttl = 100,
    int slo = 100,
    int capacity = 256,
    Set<String>? allowedKinds,
    Set<String>? capabilities,
  }) {
    binding = SyntheticProbeBinding(
      deviceId: 'synthetic-device',
      probeId: 'synthetic-${source.name}',
      serverIssuedPrefix: 'AAAAAAAAAAAAAAAAAAAAAA',
      source: source,
      reportIntervalMs: 10,
      expirySloMs: slo,
      coverageMode: 'discrete_best_effort',
      allowedKinds:
          allowedKinds ??
          {
            'app.category_active',
            'screen.interactive',
            'screen.non_interactive',
            'session.unlocked',
            'probe.permission_changed',
            'probe.error',
            'probe.heartbeat',
          },
      capabilities:
          capabilities ?? {'usage_events', 'probe_error.collection_failed'},
    );
    box = MemoryActivityOutbox.forSyntheticPairing(binding, capacity: capacity);
    collector = AndroidActivityNormalizer(
      outbox: box,
      clockMs: () => now,
      ttlMs: ttl,
    );
  }
  int now = 1000000;
  late final SyntheticProbeBinding binding;
  late final MemoryActivityOutbox box;
  late final AndroidActivityNormalizer collector;
  AndroidActivityEvent? permission(String state) =>
      collector.acceptSynthetic({'type': 'usage_permission', 'state': state});
  AndroidActivityEvent? category([String name = 'reading', int? at]) =>
      collector.acceptSynthetic({
        'type': 'usage_category',
        'category': name,
        'signal_at_ms': at ?? now,
      });
  AndroidActivityEvent? screen(String type, [int? at]) =>
      collector.acceptSynthetic({'type': type, 'signal_at_ms': at ?? now});
}

Matcher hasCode(String code) =>
    isA<AndroidActivityException>().having((e) => e.code, 'code', code);
Future<SimulatedDeliveryReply> accepted(AndroidActivityEvent e) async =>
    SimulatedDeliveryReply(
      eventId: e.eventId,
      kind: SimulatedReplyKind.accepted,
    );

void main() {
  test(
    'unregistered permission/error diagnostics and disallowed kinds fail closed',
    () {
      final permission = Rig(capabilities: {});
      expect(
        () => permission.permission('denied'),
        throwsA(hasCode('unregistered_diagnostic')),
      );
      expect(permission.collector.status.permission, UsageAccess.denied);
      expect(permission.box.lineageBlocked, isTrue);
      final error = Rig(capabilities: {});
      expect(
        () => error.collector.markCollectionGap(),
        throwsA(hasCode('unregistered_diagnostic')),
      );
      final kind = Rig(allowedKinds: {'probe.heartbeat'});
      expect(
        () => kind.permission('granted'),
        throwsA(hasCode('scope_denied')),
      );
      expect(kind.box.lastAllocatedSequence, 0);
    },
  );
  test(
    'unobserved usage has no permission, no interaction and no Core contact',
    () {
      final r = Rig();
      expect(r.category(), isNull);
      expect(r.collector.status.permission, UsageAccess.unknown);
      expect(r.collector.status.coverage, AndroidCoverage.unobserved);
      expect(
        r.collector.status.lastCoreContact,
        SyntheticCoreContact.unobserved,
      );
      expect(r.box.records, isEmpty);
    },
  );

  for (final category in [
    'chat',
    'social',
    'video',
    'reading',
    'work',
    'other',
  ]) {
    test(
      'coarse category $category uses frozen payload and conservative confidence',
      () {
        final r = Rig();
        r.permission('granted');
        final wire = r.category(category)!.toJson();
        expect(wire['kind'], 'app.category_active');
        expect(wire['payload'], {'category': category});
        expect(wire['confidence'], 'medium');
        expect(wire['source'], 'android_usage_events');
        expect(wire.containsKey('received_at_ms'), isFalse);
        expect(wire['coverage'], {
          'mode': 'discrete_best_effort',
          'window_start_ms': r.now,
          'window_end_ms': r.now,
          'expected_report_interval_ms': 10,
        });
      },
    );
  }

  for (final entry in {
    'screen_interactive': 'screen.interactive',
    'screen_non_interactive': 'screen.non_interactive',
    'user_present': 'session.unlocked',
  }.entries) {
    test('${entry.key} has only the corresponding screen/unlock evidence', () {
      final r = Rig(source: AndroidActivitySource.screenState);
      final wire = r.screen(entry.key)!.toJson();
      expect(wire['kind'], entry.value);
      expect(wire['payload'], isEmpty);
      expect(wire['source'], 'android_screen_state');
      expect(
        wire['confidence'],
        entry.key == 'user_present' ? 'high' : 'medium',
      );
    });
  }

  test(
    'deny/revoke/recover emits permissions, suppresses gap history, needs NEW observation',
    () {
      final r = Rig();
      expect(r.permission('denied')!.toJson()['payload'], {
        'capability': 'usage_events',
        'available': false,
      });
      expect(r.permission('denied'), isNull);
      expect(r.category(), isNull);
      expect(
        r.collector.status.coverage,
        AndroidCoverage.permissionUnavailable,
      );
      r.now += 10;
      r.permission('granted');
      expect(r.collector.status.coverage, AndroidCoverage.recoveryPending);
      r.category();
      expect(r.collector.status.coverage, AndroidCoverage.fresh);
      r.now += 10;
      r.permission('revoked');
      expect(r.category(), isNull);
      expect(r.collector.status.lastObservationAtMs, isNull);
      r.now += 10;
      r.permission('granted');
      final before = r.box.lastAllocatedSequence;
      expect(r.category('chat', r.now - 5), isNull);
      expect(r.collector.status.coverage, AndroidCoverage.recoveryPending);
      expect(r.box.lastAllocatedSequence, before);
      r.now++;
      r.category();
      expect(r.collector.status.coverage, AndroidCoverage.fresh);
      expect(r.box.lastAllocatedSequence, before + 1);
    },
  );

  test('permission revoke fails closed even if the wall clock regresses', () {
    final r = Rig();
    r.permission('granted');
    r.category();
    r.now--;
    expect(() => r.permission('revoked'), throwsA(hasCode('clock_uncertain')));
    expect(r.collector.status.permission, UsageAccess.revoked);
    r.now += 2;
    expect(r.category(), isNull);
    expect(r.permission('revoked')!.toJson()['payload'], {
      'capability': 'usage_events',
      'available': false,
    });
    expect(r.collector.status.coverage, AndroidCoverage.permissionUnavailable);
  });

  test(
    'failed permission grant cannot reopen collection until its report is queued',
    () {
      final r = Rig();
      r.permission('denied');
      r.now--;
      expect(
        () => r.permission('granted'),
        throwsA(hasCode('clock_uncertain')),
      );
      r.now += 2;
      expect(r.category(), isNull);
      r.permission('granted');
      expect(r.category(), isNotNull);
    },
  );

  test(
    'gap stays unknown through heartbeat; late gap callbacks cannot restore coverage',
    () {
      final r = Rig(source: AndroidActivitySource.screenState);
      r.screen('user_present');
      r.now += 10;
      final gap = r.collector.markCollectionGap();
      expect(gap.toJson()['kind'], 'probe.error');
      expect(gap.toJson()['payload'], {'code': 'collection_failed'});
      r.collector.heartbeat();
      expect(r.collector.status.coverage, AndroidCoverage.gap);
      expect(r.screen('user_present', r.now - 5), isNull);
      r.now++;
      final fresh = r.screen('screen_interactive')!.toJson();
      expect(fresh['coverage'], containsPair('window_start_ms', r.now));
      expect(r.collector.status.coverage, AndroidCoverage.fresh);
    },
  );

  test(
    'TTL exact boundary is fresh; one millisecond later is stale despite heartbeat',
    () {
      final r = Rig(source: AndroidActivitySource.screenState);
      final event = r.screen('user_present')!;
      r.now += 100;
      expect(event.isPastTtl(r.now), isFalse);
      expect(r.collector.status.coverage, AndroidCoverage.fresh);
      r.now++;
      r.collector.heartbeat();
      expect(event.isPastTtl(r.now), isTrue);
      expect(r.collector.status.coverage, AndroidCoverage.stale);
      expect(r.collector.status.lastObservationAtMs, event.signalAtMs);
      expect(r.screen('user_present', event.signalAtMs), isNull);
    },
  );

  test('local freshness uses the lower of TTL and registered expiry SLO', () {
    final r = Rig(source: AndroidActivitySource.screenState, ttl: 100, slo: 40);
    r.screen('user_present');
    r.now += 41;
    expect(r.collector.status.coverage, AndroidCoverage.stale);
  });

  test('screen and usage lineages cannot impersonate each other', () {
    final usage = Rig();
    final screen = Rig(source: AndroidActivitySource.screenState);
    expect(
      () => usage.screen('user_present'),
      throwsA(hasCode('source_binding_mismatch')),
    );
    expect(
      () => screen.category(),
      throwsA(hasCode('source_binding_mismatch')),
    );
    expect(
      () => screen.permission('granted'),
      throwsA(hasCode('source_binding_mismatch')),
    );
    expect(usage.box.records, isEmpty);
    expect(screen.box.records, isEmpty);
  });

  for (final field in [
    'package_name',
    'packageName',
    'app_name',
    'applicationLabel',
    'message_body',
    'location',
    'ble_raw_packet',
    'heart_rate',
    'received_at_ms',
  ]) {
    test(
      'private/unexpected input $field is rejected atomically without echo',
      () {
        final r = Rig();
        r.permission('granted');
        final before = r.box.lastAllocatedSequence;
        final signal = <String, Object?>{
          'type': 'usage_category',
          'category': 'reading',
          'signal_at_ms': r.now,
          field: {'sensitive': 'PRIVATE_SYNTHETIC_VALUE'},
        };
        expect(
          () => r.collector.acceptSynthetic(signal),
          throwsA(hasCode('unknown_or_missing_signal_field')),
        );
        expect(r.box.lastAllocatedSequence, before);
        expect(
          r.box.records.map((e) => e.event.json).join(),
          isNot(contains('PRIVATE_SYNTHETIC_VALUE')),
        );
        expect(r.collector.status.coverage, AndroidCoverage.recoveryPending);
      },
    );
  }

  for (final category in <Object?>[
    'com.synthetic.chat',
    'Synthetic App',
    'chat body',
    '51.5,0.1',
    72,
    {'heart_rate': 72},
  ]) {
    test('non-dictionary category ${jsonEncode(category)} is rejected', () {
      final r = Rig();
      expect(
        () => r.collector.acceptSynthetic({
          'type': 'usage_category',
          'category': category,
          'signal_at_ms': r.now,
        }),
        throwsA(hasCode('invalid_category')),
      );
      expect(r.box.records, isEmpty);
    });
  }

  test(
    'unrecognized types and permission payload fields do not mutate state',
    () {
      final r = Rig();
      expect(
        () => r.collector.acceptSynthetic({'type': 'unknown'}),
        throwsA(hasCode('unsupported_signal')),
      );
      expect(
        () => r.collector.acceptSynthetic({
          'type': 'usage_permission',
          'state': 'granted',
          'app_name': 'private',
        }),
        throwsA(hasCode('unknown_or_missing_signal_field')),
      );
      expect(
        () => r.permission('perhaps'),
        throwsA(hasCode('invalid_permission')),
      );
      expect(r.collector.status.permission, UsageAccess.unknown);
    },
  );

  test(
    'each new logical event increments sequence; caller cannot mutate queued bytes',
    () {
      final r = Rig(source: AndroidActivitySource.screenState);
      final event = r.screen('user_present')!;
      final bytes = event.json;
      final copy = event.toJson();
      (copy['payload']! as Map)['message_body'] = 'PRIVATE';
      (copy['coverage']! as Map)['mode'] = 'continuous';
      expect(event.json, bytes);
      r.screen('screen_non_interactive');
      expect(r.box.records.map((r) => r.event.originSequence), [1, 2]);
      expect(
        r.box.records.last.event.eventId,
        '${r.binding.serverIssuedPrefix}.2',
      );
      expect(() => r.box.records.clear(), throwsUnsupportedError);
    },
  );

  test(
    'Core offline preserves immutable event; restore reconciles duplicate even past TTL',
    () async {
      final r = Rig(source: AndroidActivitySource.screenState);
      final first = r.screen('user_present')!;
      final attempted = <String>[];
      await r.box.flushSynthetic((e) async {
        attempted.add(e.json);
        throw StateError('PRIVATE_SYNTHETIC_TRANSPORT_ERROR');
      });
      expect(r.box.records.single.delivery, OutboxDelivery.pending);
      expect(
        r.collector.status.lastCoreContact,
        SyntheticCoreContact.unreachable,
      );
      r.now += 101;
      expect(r.collector.status.coverage, AndroidCoverage.stale);
      final snapshot = r.box.detachForSyntheticRestart();
      final restored = MemoryActivityOutbox.restoreSynthetic(snapshot);
      final collector = AndroidActivityNormalizer(
        outbox: restored,
        clockMs: () => r.now,
        ttlMs: 100,
      );
      expect(collector.status.coverage, AndroidCoverage.gap);
      expect(
        () => collector.heartbeat(),
        throwsA(hasCode('restart_gap_required')),
      );
      expect(
        () => collector.acceptSynthetic({
          'type': 'user_present',
          'signal_at_ms': r.now,
        }),
        throwsA(hasCode('restart_gap_required')),
      );
      expect(restored.lastAllocatedSequence, 1);
      // Restart itself is a new observed gap, not backfilled user interaction.
      collector.markCollectionGap();
      await restored.flushSynthetic((e) async {
        attempted.add(e.json);
        return SimulatedDeliveryReply(
          eventId: e.eventId,
          kind: e.originSequence == 1
              ? SimulatedReplyKind.duplicate
              : SimulatedReplyKind.accepted,
        );
      });
      expect(attempted.take(2), [first.json, first.json]);
      expect(restored.records.first.attempts, 2);
      expect(restored.records.first.delivery, OutboxDelivery.duplicate);
      expect(restored.records.last.event.originSequence, 2);
      expect(collector.status.coverage, AndroidCoverage.gap);
      expect(collector.status.lastCoreContact, SyntheticCoreContact.reachable);
      expect(
        () => r.collector.heartbeat(),
        throwsA(hasCode('sequence_authority_required')),
      );
      expect(
        () => MemoryActivityOutbox.restoreSynthetic(snapshot),
        throwsA(hasCode('sequence_authority_required')),
      );
      expect(
        () => MemoryActivityOutbox.forSyntheticPairing(r.binding),
        throwsA(hasCode('sequence_authority_required')),
      );
    },
  );

  for (final rejection in ActivityRejection.values) {
    test(
      'terminal ${rejection.coreCode} retains evidence and freezes lineage without renumbering',
      () async {
        final r = Rig(source: AndroidActivitySource.screenState);
        r.screen('user_present');
        r.screen('screen_non_interactive');
        var calls = 0;
        await r.box.flushSynthetic((e) async {
          calls++;
          return SimulatedDeliveryReply(
            eventId: e.eventId,
            kind: SimulatedReplyKind.terminalRejected,
            rejection: rejection,
          );
        });
        await r.box.flushSynthetic(accepted);
        expect(calls, 1);
        expect(r.box.records.first.rejection, rejection);
        expect(r.box.records.last.delivery, OutboxDelivery.pending);
        expect(r.box.lastAllocatedSequence, 2);
        expect(r.collector.status.coverage, AndroidCoverage.lineageBlocked);
        expect(
          () => r.collector.heartbeat(),
          throwsA(hasCode('lineage_blocked')),
        );
        final restored = MemoryActivityOutbox.restoreSynthetic(
          r.box.detachForSyntheticRestart(),
        );
        expect(restored.lineageBlocked, isTrue);
      },
    );
  }

  test(
    'retryable response stops FIFO delivery and later acceptance keeps original bytes',
    () async {
      final r = Rig(source: AndroidActivitySource.screenState);
      final first = r.screen('user_present')!;
      r.screen('screen_non_interactive');
      await r.box.flushSynthetic(
        (e) async => SimulatedDeliveryReply(
          eventId: e.eventId,
          kind: SimulatedReplyKind.retryable,
        ),
      );
      expect(r.box.records.map((r) => r.attempts), [1, 0]);
      await r.box.flushSynthetic(accepted);
      expect(
        r.box.records.map((r) => r.delivery),
        everyElement(OutboxDelivery.accepted),
      );
      expect(r.box.records.first.event.json, first.json);
    },
  );

  test(
    'mismatched reply and contradictory terminal shape do not acknowledge',
    () async {
      final r = Rig(source: AndroidActivitySource.screenState);
      r.screen('user_present');
      await r.box.flushSynthetic(
        (e) async => const SimulatedDeliveryReply(
          eventId: 'wrong',
          kind: SimulatedReplyKind.accepted,
        ),
      );
      await r.box.flushSynthetic(
        (e) async => SimulatedDeliveryReply(
          eventId: e.eventId,
          kind: SimulatedReplyKind.accepted,
          rejection: ActivityRejection.ttlExpired,
        ),
      );
      expect(r.box.records.single.delivery, OutboxDelivery.pending);
      expect(r.box.records.single.attempts, 2);
    },
  );

  for (final freezeCode in ['scope_denied', 'unregistered_diagnostic']) {
    test('concurrent $freezeCode settles only the in-flight event', () async {
      final r = Rig(
        source: AndroidActivitySource.screenState,
        allowedKinds: {
          'session.unlocked',
          'screen.non_interactive',
          'probe.error',
        },
        capabilities: {},
      );
      final first = r.screen('user_present')!;
      r.screen('screen_non_interactive');
      final inFlightReply = Completer<SimulatedDeliveryReply>();
      final sent = <int>[];
      final flushing = r.box.flushSynthetic((event) async {
        sent.add(event.originSequence);
        if (event.originSequence == 1) return inFlightReply.future;
        return accepted(event);
      });
      expect(sent, [1]);
      expect(
        () => freezeCode == 'scope_denied'
            ? r.collector.heartbeat()
            : r.collector.markCollectionGap(),
        throwsA(hasCode(freezeCode)),
      );
      expect(r.box.lineageBlocked, isTrue);
      expect(r.box.lastAllocatedSequence, 2);
      inFlightReply.complete(
        SimulatedDeliveryReply(
          eventId: first.eventId,
          kind: SimulatedReplyKind.accepted,
        ),
      );
      await flushing;
      expect(sent, [1]);
      expect(r.box.records.first.delivery, OutboxDelivery.accepted);
      expect(r.box.records.first.event.json, first.json);
      expect(r.box.records.last.delivery, OutboxDelivery.pending);
      expect(r.box.records.map((record) => record.attempts), [1, 0]);
      await r.box.flushSynthetic((event) async {
        sent.add(event.originSequence);
        return accepted(event);
      });
      expect(sent, [1]);
      expect(r.box.records.last.delivery, OutboxDelivery.pending);
    });
  }

  test(
    'concurrent flush/restart forbidden; new events wait for next flush',
    () async {
      final r = Rig(source: AndroidActivitySource.screenState);
      r.screen('user_present');
      final gate = Completer<SimulatedDeliveryReply>();
      final flushing = r.box.flushSynthetic((e) => gate.future);
      await expectLater(
        r.box.flushSynthetic(accepted),
        throwsA(hasCode('flush_in_progress')),
      );
      expect(
        () => r.box.detachForSyntheticRestart(),
        throwsA(hasCode('flush_in_progress')),
      );
      expect(
        () => r.box.loseSequenceAuthority(),
        throwsA(hasCode('flush_in_progress')),
      );
      r.screen('screen_non_interactive');
      gate.complete(
        SimulatedDeliveryReply(
          eventId: r.box.records.first.event.eventId,
          kind: SimulatedReplyKind.accepted,
        ),
      );
      await flushing;
      expect(r.box.records.map((r) => r.attempts), [1, 0]);
      await r.box.flushSynthetic(accepted);
      expect(r.box.records.last.delivery, OutboxDelivery.accepted);
    },
  );

  test('bounded outbox fails closed without spending a sequence', () {
    final r = Rig(capacity: 2);
    r.permission('granted');
    r.category();
    expect(() => r.permission('revoked'), throwsA(hasCode('outbox_full')));
    expect(r.collector.status.permission, UsageAccess.revoked);
    expect(r.collector.status.coverage, AndroidCoverage.gap);
    expect(r.category(), isNull);
    expect(r.box.lastAllocatedSequence, 2);
  });

  test(
    'lost sequence authority cannot create, send, or reset old lineage',
    () async {
      final r = Rig(source: AndroidActivitySource.screenState);
      r.screen('user_present');
      r.box.loseSequenceAuthority();
      expect(
        () => r.screen('user_present'),
        throwsA(hasCode('lineage_blocked')),
      );
      var sends = 0;
      await r.box.flushSynthetic((e) async {
        sends++;
        return accepted(e);
      });
      expect(sends, 0);
      expect(r.box.lastAllocatedSequence, 1);
    },
  );

  test(
    'wall-clock regression latches unknown until a fresh new observation',
    () {
      final r = Rig(source: AndroidActivitySource.screenState);
      r.screen('user_present');
      r.now += 50;
      expect(r.collector.status.coverage, AndroidCoverage.fresh);
      r.now--;
      expect(r.collector.status.coverage, AndroidCoverage.clockUncertain);
      r.now += 2;
      expect(r.collector.status.coverage, AndroidCoverage.clockUncertain);
      r.collector.heartbeat();
      expect(r.collector.status.coverage, AndroidCoverage.clockUncertain);
      r.screen('screen_interactive');
      expect(r.collector.status.coverage, AndroidCoverage.fresh);
    },
  );

  test('future signal is not clamped into invented current interaction', () {
    final r = Rig(source: AndroidActivitySource.screenState);
    expect(
      () => r.screen('user_present', r.now + 1),
      throwsA(hasCode('clock_uncertain')),
    );
    expect(r.box.records, isEmpty);
    expect(r.collector.status.coverage, AndroidCoverage.clockUncertain);
  });

  for (final ttl in [0, -1, 86400001]) {
    test('reject TTL $ttl outside existing Core bound', () {
      expect(() => Rig(ttl: ttl), throwsA(hasCode('invalid_duration')));
    });
  }

  test(
    'reject unsafe timestamp and deadline overflow without spending sequence',
    () {
      final r = Rig(source: AndroidActivitySource.screenState);
      expect(
        () => r.screen('user_present', -1),
        throwsA(hasCode('invalid_signal_time')),
      );
      expect(
        () => r.screen('user_present', 9007199254740992),
        throwsA(hasCode('invalid_signal_time')),
      );
      r.now = 9007199254740991;
      expect(
        () => r.screen('user_present'),
        throwsA(hasCode('clock_uncertain')),
      );
      expect(r.box.lastAllocatedSequence, 0);
    },
  );

  test('one collector per outbox prevents overlapping sequence writers', () {
    final r = Rig();
    expect(
      () => AndroidActivityNormalizer(
        outbox: r.box,
        clockMs: () => r.now,
        ttlMs: 100,
      ),
      throwsA(hasCode('collector_already_attached')),
    );
  });
}
