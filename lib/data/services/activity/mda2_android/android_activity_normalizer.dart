import 'dart:convert';

// Platform-local prototype types. The wire authority remains
// tools/i_core/activity_control_plane.mjs::normalizeActivityEvent, not this file.
const _maxSafeInteger = 9007199254740991;
const _maxDurationMs = 86400000;

enum AndroidActivitySource {
  usageEvents('android_usage_events'),
  screenState('android_screen_state');

  const AndroidActivitySource(this.wireValue);
  final String wireValue;
}

enum UsageAccess { unknown, denied, revoked, granted }

enum AndroidCoverage {
  unobserved,
  permissionUnavailable,
  recoveryPending,
  gap,
  fresh,
  stale,
  clockUncertain,
  lineageBlocked,
}

enum OutboxDelivery { pending, accepted, duplicate, terminalRejected }

/// Last attempted delivery only; never inferred from device activity or silence.
enum SyntheticCoreContact { unobserved, unreachable, reachable }

enum SimulatedReplyKind { accepted, duplicate, retryable, terminalRejected }

/// These are existing Core rejection codes, not a new response protocol.
enum ActivityRejection {
  ttlExpired('ttl_expired'),
  retainedOut('event_retained_out'),
  revoked('revoked_replay'),
  idempotencyConflict('idempotency_conflict'),
  scopeDenied('scope_denied'),
  bindingMismatch('source_binding_mismatch');

  const ActivityRejection(this.coreCode);
  final String coreCode;
}

final class AndroidActivityException implements Exception {
  const AndroidActivityException(this.code);
  final String code;
  @override
  String toString() => 'AndroidActivityException($code)';
}

/// A caller-injected, synthetic pairing result. This never pairs with a server,
/// generates a prefix, accepts credentials, or proves real issuance.
///
/// Each source needs its own binding. Only discrete_best_effort is supported.
/// Creating another object with the same prefix is NOT a recovery mechanism.
final class SyntheticProbeBinding {
  SyntheticProbeBinding({
    required this.deviceId,
    required this.probeId,
    required this.serverIssuedPrefix,
    required this.source,
    required this.reportIntervalMs,
    required this.expirySloMs,
    required String coverageMode,
    required Set<String> allowedKinds,
    required Set<String> capabilities,
  }) : allowedKinds = Set.unmodifiable(allowedKinds),
       capabilities = Set.unmodifiable(capabilities) {
    if (coverageMode != 'discrete_best_effort' || allowedKinds.isEmpty) {
      throw const AndroidActivityException('unsupported_binding');
    }
    for (final id in [deviceId, probeId]) {
      if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$').hasMatch(id) ||
          RegExp(
            r'bearer|token|secret|password|jwt|https?|url|stack',
            caseSensitive: false,
          ).hasMatch(id)) {
        throw const AndroidActivityException('invalid_binding');
      }
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{22,64}$').hasMatch(serverIssuedPrefix)) {
      throw const AndroidActivityException('invalid_binding');
    }
    _duration(reportIntervalMs);
    _duration(expirySloMs);
  }

  final String deviceId;
  final String probeId;
  final String serverIssuedPrefix;
  final AndroidActivitySource source;
  final int reportIntervalMs;
  final int expirySloMs;
  final Set<String> allowedKinds;
  final Set<String> capabilities;
  bool _claimed = false;

  void claimSequenceAuthority() {
    if (_claimed) {
      throw const AndroidActivityException('sequence_authority_required');
    }
    _claimed = true;
  }
}

/// Immutable bytes are materialized once per logical event, before any send.
final class AndroidActivityEvent {
  AndroidActivityEvent._(Map<String, Object?> wire)
    : json = jsonEncode(wire),
      eventId = wire['event_id']! as String,
      originSequence = wire['origin_sequence']! as int,
      signalAtMs = wire['signal_at_ms']! as int,
      ttlMs = wire['ttl_ms']! as int;

  final String json;
  final String eventId;
  final int originSequence;
  final int signalAtMs;
  final int ttlMs;

  factory AndroidActivityEvent.create({
    required SyntheticProbeBinding binding,
    required int originSequence,
    required String kind,
    required int signalAtMs,
    required int ttlMs,
    required String confidence,
    Map<String, Object?> payload = const {},
  }) => AndroidActivityEvent._({
    'contract': 'device.activity.v1',
    'schema_version': 1,
    'event_id': '${binding.serverIssuedPrefix}.$originSequence',
    'device_id': binding.deviceId,
    'probe_id': binding.probeId,
    'origin_sequence': originSequence,
    'kind': kind,
    'signal_at_ms': signalAtMs,
    'ttl_ms': ttlMs,
    'confidence': confidence,
    'source': binding.source.wireValue,
    'coverage': {
      'mode': 'discrete_best_effort',
      'window_start_ms': signalAtMs,
      'window_end_ms': signalAtMs,
      'expected_report_interval_ms': binding.reportIntervalMs,
    },
    'payload': payload,
  });

  factory AndroidActivityEvent.fromFixedJson(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map) {
      throw const AndroidActivityException('invalid_persisted_event');
    }
    return AndroidActivityEvent._(Map<String, Object?>.from(decoded));
  }

  /// A detached copy; mutating it cannot change queued/retried bytes.
  Map<String, Object?> toJson() =>
      Map<String, Object?>.from(jsonDecode(json) as Map);

  // Core accepts at the exact TTL deadline, and checks duplicate before TTL.
  bool isPastTtl(int nowMs) => nowMs > signalAtMs + ttlMs;
}

final class OutboxRecord {
  const OutboxRecord._(
    this.event,
    this.delivery,
    this.attempts,
    this.rejection,
  );
  final AndroidActivityEvent event;
  final OutboxDelivery delivery;
  final int attempts;
  final ActivityRejection? rejection;
}

/// Test transport reply, deliberately not a wire response parser or receipt.
final class SimulatedDeliveryReply {
  const SimulatedDeliveryReply({
    required this.eventId,
    required this.kind,
    this.rejection,
  });
  final String eventId;
  final SimulatedReplyKind kind;
  final ActivityRejection? rejection;
}

typedef SyntheticActivitySender =
    Future<SimulatedDeliveryReply> Function(AndroidActivityEvent event);

/// Injected sequence and byte authority used by the normalizer. The durable
/// implementation lives in [file_activity_outbox_store.dart]; this interface
/// intentionally contains no transport, platform collector, or Core client.
abstract interface class ActivityOutboxStore {
  SyntheticProbeBinding get binding;
  int get capacity;
  int get lastAllocatedSequence;
  int? get lastSignalAt;
  bool get lineageBlocked;
  bool get restored;
  bool get collectorAttached;
  set collectorAttached(bool value);
  SyntheticCoreContact get lastContact;

  void assertOwned();
  void acknowledgeRestartGap();

  AndroidActivityEvent enqueue({
    required String kind,
    required int atMs,
    required int ttlMs,
    required String confidence,
    Map<String, Object?> payload = const {},
  });
}

/// Single-use ownership transfer for a simulated process restart. No disk I/O,
/// untrusted JSON restore, crash durability, rollback detection or persistence.
final class SyntheticOutboxSnapshot {
  SyntheticOutboxSnapshot._(
    this._binding,
    this._records,
    this._lastSequence,
    this._lastSignalAt,
    this._capacity,
    this._blocked,
  );
  final SyntheticProbeBinding _binding;
  final List<OutboxRecord> _records;
  final int _lastSequence;
  final int? _lastSignalAt;
  final int _capacity;
  final bool _blocked;
  bool _consumed = false;
}

/// Bounded, injected, in-memory outbox for ONE synthetic probe lineage.
/// No timer, HTTP, credential store or background send is provided.
final class MemoryActivityOutbox implements ActivityOutboxStore {
  MemoryActivityOutbox.forSyntheticPairing(
    this.binding, {
    this.capacity = 256,
  }) {
    if (capacity < 1) {
      throw const AndroidActivityException('sequence_authority_required');
    }
    binding.claimSequenceAuthority();
  }

  MemoryActivityOutbox.restoreSynthetic(SyntheticOutboxSnapshot snapshot)
    : binding = snapshot._binding,
      capacity = snapshot._capacity {
    if (snapshot._consumed) {
      throw const AndroidActivityException('sequence_authority_required');
    }
    snapshot._consumed = true;
    _records.addAll(snapshot._records);
    _lastSequence = snapshot._lastSequence;
    _lastSignalAt = snapshot._lastSignalAt;
    _blocked = snapshot._blocked;
    _restored = true;
  }

  @override
  final SyntheticProbeBinding binding;
  @override
  final int capacity;
  final List<OutboxRecord> _records = [];
  int _lastSequence = 0;
  int? _lastSignalAt;
  bool _blocked = false;
  bool _detached = false;
  bool _restored = false;
  bool _collectorAttached = false;
  bool _flushing = false;
  SyntheticCoreContact _lastContact = SyntheticCoreContact.unobserved;

  List<OutboxRecord> get records => List.unmodifiable(_records);
  @override
  int get lastAllocatedSequence => _lastSequence;
  @override
  int? get lastSignalAt => _lastSignalAt;
  @override
  bool get lineageBlocked => _blocked || _detached;
  @override
  bool get restored => _restored;
  @override
  bool get collectorAttached => _collectorAttached;
  @override
  set collectorAttached(bool value) => _collectorAttached = value;
  @override
  SyntheticCoreContact get lastContact => _lastContact;

  @override
  void assertOwned() {
    if (_detached) {
      throw const AndroidActivityException('sequence_authority_required');
    }
  }

  @override
  void acknowledgeRestartGap() => _restored = false;

  @override
  AndroidActivityEvent enqueue({
    required String kind,
    required int atMs,
    required int ttlMs,
    required String confidence,
    Map<String, Object?> payload = const {},
  }) {
    assertOwned();
    if (_blocked || _lastSequence == _maxSafeInteger) {
      throw const AndroidActivityException('lineage_blocked');
    }
    if (!binding.allowedKinds.contains(kind)) {
      _blocked = true;
      throw const AndroidActivityException('scope_denied');
    }
    if ((kind == 'probe.permission_changed' &&
            !binding.capabilities.contains(payload['capability'])) ||
        (kind == 'probe.error' &&
            !binding.capabilities.contains('probe_error.${payload['code']}'))) {
      _blocked = true;
      throw const AndroidActivityException('unregistered_diagnostic');
    }
    if (_records.length >= capacity) {
      throw const AndroidActivityException('outbox_full');
    }
    _timestamp(atMs);
    _duration(ttlMs);
    if (atMs > _maxSafeInteger - ttlMs ||
        (_lastSignalAt != null && atMs < _lastSignalAt!)) {
      throw const AndroidActivityException('clock_uncertain');
    }
    final sequence = _lastSequence + 1;
    final event = AndroidActivityEvent.create(
      binding: binding,
      originSequence: sequence,
      kind: kind,
      signalAtMs: atMs,
      ttlMs: ttlMs,
      confidence: confidence,
      payload: payload,
    );
    _records.add(OutboxRecord._(event, OutboxDelivery.pending, 0, null));
    _lastSequence = sequence;
    _lastSignalAt = atMs;
    return event;
  }

  /// Called explicitly with a fake sender. An exception is an ambiguous send:
  /// retain the SAME bytes and stop. Never store the exception or its content.
  /// Past-TTL events are still reconciled: Core may return duplicate for an
  /// already accepted send, or ttl_expired for one it has never accepted.
  Future<void> flushSynthetic(SyntheticActivitySender sender) async {
    assertOwned();
    if (_flushing) throw const AndroidActivityException('flush_in_progress');
    if (_blocked) return;
    _flushing = true;
    // Events added while awaiting transport are deferred to the next call.
    final limit = _records.length;
    try {
      for (var index = 0; index < limit; index++) {
        // A concurrent observation can freeze this lineage while a send awaits.
        // Settle that in-flight reply, then leave later records untouched.
        if (_blocked) break;
        final record = _records[index];
        if (record.delivery != OutboxDelivery.pending) continue;
        final attempted = OutboxRecord._(
          record.event,
          record.delivery,
          record.attempts + 1,
          null,
        );
        _records[index] = attempted;
        SimulatedDeliveryReply reply;
        try {
          reply = await sender(record.event);
        } catch (_) {
          _lastContact = SyntheticCoreContact.unreachable;
          break;
        }
        if (reply.eventId != record.event.eventId ||
            ((reply.kind == SimulatedReplyKind.terminalRejected) !=
                (reply.rejection != null))) {
          _lastContact = SyntheticCoreContact.unreachable;
          break;
        }
        _lastContact = SyntheticCoreContact.reachable;
        if (reply.kind == SimulatedReplyKind.retryable) break;
        final delivery = switch (reply.kind) {
          SimulatedReplyKind.accepted => OutboxDelivery.accepted,
          SimulatedReplyKind.duplicate => OutboxDelivery.duplicate,
          SimulatedReplyKind.terminalRejected =>
            OutboxDelivery.terminalRejected,
          SimulatedReplyKind.retryable => OutboxDelivery.pending,
        };
        _records[index] = OutboxRecord._(
          record.event,
          delivery,
          attempted.attempts,
          reply.rejection,
        );
        if (delivery == OutboxDelivery.terminalRejected) {
          // A hole cannot be repaired by renumbering or fabricating an event.
          // Hold this lineage for explicit resolution/new pairing by W0.
          _blocked = true;
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  SyntheticOutboxSnapshot detachForSyntheticRestart() {
    assertOwned();
    if (_flushing) throw const AndroidActivityException('flush_in_progress');
    _detached = true;
    return SyntheticOutboxSnapshot._(
      binding,
      List.unmodifiable(_records),
      _lastSequence,
      _lastSignalAt,
      capacity,
      _blocked,
    );
  }

  /// Simulates lost sequence authority. Recovery must not reset this prefix.
  void loseSequenceAuthority() {
    assertOwned();
    if (_flushing) throw const AndroidActivityException('flush_in_progress');
    _blocked = true;
  }
}

final class AndroidObservationStatus {
  const AndroidObservationStatus({
    required this.permission,
    required this.coverage,
    required this.lastCoreContact,
    required this.lastObservationAtMs,
  });
  final UsageAccess permission;
  final AndroidCoverage coverage;
  final SyntheticCoreContact lastCoreContact;
  final int? lastObservationAtMs;
  // Coverage is local collection freshness, not Core acceptance or person state.
}

/// A pure Dart consumer of already privacy-reduced synthetic signals.
/// It neither calls UsageEvents nor accepts package names to classify apps.
final class AndroidActivityNormalizer {
  AndroidActivityNormalizer({
    required this.outbox,
    required int Function() clockMs,
    required this.ttlMs,
  }) : _clockMs = clockMs {
    _duration(ttlMs);
    outbox.assertOwned();
    if (outbox.collectorAttached) {
      throw const AndroidActivityException('collector_already_attached');
    }
    final now = _clockMs();
    _timestamp(now);
    _barrierMs = now;
    _lastClockMs = now;
    _coverage = outbox.restored
        ? AndroidCoverage.gap
        : AndroidCoverage.unobserved;
    outbox.collectorAttached = true;
  }

  final ActivityOutboxStore outbox;
  final int Function() _clockMs;
  final int ttlMs;
  UsageAccess _permission = UsageAccess.unknown;
  bool _permissionNeedsReport = false;
  AndroidCoverage _coverage = AndroidCoverage.unobserved;
  int _barrierMs = 0;
  int _lastClockMs = 0;
  int? _lastObservationAtMs;

  AndroidObservationStatus get status {
    final now = _clockMs();
    final clockInvalid = now < _lastClockMs || now > _maxSafeInteger;
    if (clockInvalid) {
      _coverage = AndroidCoverage.clockUncertain;
      _barrierMs = _lastClockMs;
    } else {
      _lastClockMs = now;
    }
    var coverage = _coverage;
    if (outbox.lineageBlocked) {
      coverage = AndroidCoverage.lineageBlocked;
    } else if (clockInvalid) {
      coverage = AndroidCoverage.clockUncertain;
    } else if (coverage == AndroidCoverage.fresh &&
        now > _lastObservationAtMs! + _freshnessMs) {
      coverage = AndroidCoverage.stale;
    }
    return AndroidObservationStatus(
      permission: _permission,
      coverage: coverage,
      lastCoreContact: outbox.lastContact,
      lastObservationAtMs: _lastObservationAtMs,
    );
  }

  int get _freshnessMs =>
      ttlMs < outbox.binding.expirySloMs ? ttlMs : outbox.binding.expirySloMs;

  int _now() {
    final now = _clockMs();
    _timestamp(now);
    if (now < _lastClockMs) {
      _coverage = AndroidCoverage.clockUncertain;
      _barrierMs = _lastClockMs;
      throw const AndroidActivityException('clock_uncertain');
    }
    _lastClockMs = now;
    return now;
  }

  /// A delivery storage-capacity failure does not end authorization. Preserve
  /// the original subscription barrier so the same occurrence can be retried.
  AndroidActivityEvent? acceptDeliverySignal(Map<String, Object?> signal) {
    final authorizedBarrier = _barrierMs;
    try {
      return acceptSynthetic(signal);
    } on AndroidActivityException catch (error) {
      if (error.code == 'outbox_full') _barrierMs = authorizedBarrier;
      rethrow;
    }
  }

  /// Delivery lateness is not a wall-clock regression. Occurrence remains unchanged.
  String? deliveryRejectionAt(int at) {
    final now = _now();
    if (now - at > _freshnessMs) return 'expired_before_acceptance';
    if (outbox.lastSignalAt != null && at < outbox.lastSignalAt!) {
      return 'late_out_of_order';
    }
    if (at < _barrierMs) return 'before_subscription';
    return null;
  }

  /// A known delivery omission, not an authorization gap or a fabricated event.
  /// Keep the barrier intact so valid members of this same batch can be accepted.
  void noteDeliveryGap() {
    _coverage = AndroidCoverage.gap;
    _lastObservationAtMs = null;
  }

  /// Closed platform-local input shapes. Unknown fields are rejected before
  /// state mutation; never silently strip private data and accept the rest.
  AndroidActivityEvent? acceptSynthetic(Map<String, Object?> signal) {
    final type = signal['type'];
    if (type == 'usage_permission') {
      _keys(signal, const {'type', 'state'});
      final permission = switch (signal['state']) {
        'denied' => UsageAccess.denied,
        'revoked' => UsageAccess.revoked,
        'granted' => UsageAccess.granted,
        _ => throw const AndroidActivityException('invalid_permission'),
      };
      return _setPermission(permission);
    }
    final usage = type == 'usage_category';
    if (!usage &&
        !const {
          'screen_interactive',
          'screen_non_interactive',
          'user_present',
        }.contains(type)) {
      throw const AndroidActivityException('unsupported_signal');
    }
    _keys(
      signal,
      usage
          ? const {'type', 'signal_at_ms', 'category'}
          : const {'type', 'signal_at_ms'},
    );
    final category = signal['category'];
    if (usage &&
        !const {
          'chat',
          'social',
          'video',
          'reading',
          'work',
          'other',
        }.contains(category)) {
      throw const AndroidActivityException('invalid_category');
    }
    if (usage != (outbox.binding.source == AndroidActivitySource.usageEvents)) {
      throw const AndroidActivityException('source_binding_mismatch');
    }
    final at = signal['signal_at_ms'];
    if (at is! int) throw const AndroidActivityException('invalid_signal_time');
    _timestamp(at);
    final now = _now();
    if (at > now) {
      _coverage = AndroidCoverage.clockUncertain;
      _barrierMs = now;
      throw const AndroidActivityException('clock_uncertain');
    }
    if (usage &&
        (_permission != UsageAccess.granted || _permissionNeedsReport)) {
      return null;
    }
    // Do not replay an interaction from before subscription/recovery, or
    // refresh state using a late callback whose evidence is already stale.
    if (at < _barrierMs || now - at > _freshnessMs) return null;
    if (outbox.lastSignalAt != null && at < outbox.lastSignalAt!) {
      _coverage = AndroidCoverage.clockUncertain;
      _barrierMs = now;
      throw const AndroidActivityException('clock_uncertain');
    }
    final kind = switch (type) {
      'usage_category' => 'app.category_active',
      'screen_interactive' => 'screen.interactive',
      'screen_non_interactive' => 'screen.non_interactive',
      'user_present' => 'session.unlocked',
      _ => throw const AndroidActivityException('unsupported_signal'),
    };
    final event = _emit(
      kind,
      at,
      confidence: type == 'user_present' ? 'high' : 'medium',
      payload: usage ? {'category': category} : const {},
    );
    _lastObservationAtMs = at;
    _coverage = AndroidCoverage.fresh;
    return event;
  }

  AndroidActivityEvent? _setPermission(UsageAccess permission) {
    if (outbox.binding.source != AndroidActivitySource.usageEvents) {
      throw const AndroidActivityException('source_binding_mismatch');
    }
    if (_permission == permission && !_permissionNeedsReport) return null;
    // A failure to enqueue must still revoke local collection immediately.
    _permission = permission;
    _permissionNeedsReport = true;
    _lastObservationAtMs = null;
    _coverage = permission == UsageAccess.granted
        ? AndroidCoverage.recoveryPending
        : AndroidCoverage.permissionUnavailable;
    final now = _now();
    _barrierMs = now;
    final event = _emit(
      'probe.permission_changed',
      now,
      confidence: 'high',
      payload: {
        'capability': 'usage_events',
        'available': permission == UsageAccess.granted,
      },
    );
    _permissionNeedsReport = false;
    return event;
  }

  /// An observed collector interruption. Uses the existing registered error
  /// token; the coverage mode stays bound to the synthetic registration.
  AndroidActivityEvent markCollectionGap() {
    final now = _now();
    _barrierMs = now;
    _lastObservationAtMs = null;
    _coverage = AndroidCoverage.gap;
    return _emit(
      'probe.error',
      now,
      confidence: 'high',
      payload: const {'code': 'collection_failed'},
    );
  }

  /// Reports probe reachability only, never observation freshness/interaction.
  AndroidActivityEvent heartbeat() =>
      _emit('probe.heartbeat', _now(), confidence: 'low');

  AndroidActivityEvent _emit(
    String kind,
    int at, {
    required String confidence,
    Map<String, Object?> payload = const {},
  }) {
    try {
      if (outbox.restored && !outbox.lineageBlocked && kind != 'probe.error') {
        throw const AndroidActivityException('restart_gap_required');
      }
      final event = outbox.enqueue(
        kind: kind,
        atMs: at,
        ttlMs: ttlMs,
        confidence: confidence,
        payload: payload,
      );
      // Restoring bytes is not evidence that the collector ran in the gap.
      if (kind == 'probe.error') outbox.acknowledgeRestartGap();
      return event;
    } on AndroidActivityException catch (error) {
      if (error.code == 'outbox_full') {
        _coverage = AndroidCoverage.gap;
        _lastObservationAtMs = null;
        _barrierMs = _lastClockMs;
      }
      rethrow;
    }
  }
}

void _keys(Map<String, Object?> value, Set<String> allowed) {
  if (value.length != allowed.length ||
      value.keys.any((key) => !allowed.contains(key))) {
    throw const AndroidActivityException('unknown_or_missing_signal_field');
  }
}

void _timestamp(int value) {
  if (value < 0 || value > _maxSafeInteger) {
    throw const AndroidActivityException('invalid_signal_time');
  }
}

void _duration(int value) {
  if (value < 1 || value > _maxDurationMs) {
    throw const AndroidActivityException('invalid_duration');
  }
}
