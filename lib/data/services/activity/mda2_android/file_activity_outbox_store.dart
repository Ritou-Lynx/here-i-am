import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'android_activity_normalizer.dart';
import 'activity_outbox_process_lease.dart';

const _formatVersion = 1;
const _maxSafeInteger = 9007199254740991;
const _maxDurationMs = 86400000;

enum DurableDeliveryState {
  neverSent('never_sent'),
  attemptedUnknown('attempted_unknown'),
  accepted('accepted'),
  duplicate('duplicate'),
  terminalRejected('terminal_rejected');

  const DurableDeliveryState(this.value);
  final String value;
}

enum ActivityCoreReceiptKind {
  accepted,
  duplicate,
  retryable,
  terminalRejected,
}

enum ActivityOutboxFaultPoint { afterJournal, afterState, afterAnchor }

enum ActivityOutboxOwnerReleaseOutcome { released, targetAbsent }

/// An in-memory, exact signed target. Never display or serialize this identity.
final class ActivityOutboxReleaseTarget {
  ActivityOutboxReleaseTarget._({
    required this.source,
    required this.bindingDigest,
    required String canonicalRoot,
    required SyntheticProbeBinding binding,
    required List<int> ownerBytes,
    required List<int> stateBytes,
    required List<int> anchorBytes,
  }) : _canonicalRoot = canonicalRoot,
       _binding = binding,
       _ownerBytes = List.unmodifiable(ownerBytes),
       _stateBytes = List.unmodifiable(stateBytes),
       _anchorBytes = List.unmodifiable(anchorBytes);

  final AndroidActivitySource source;
  final String bindingDigest;
  final String _canonicalRoot;
  final SyntheticProbeBinding _binding;
  final List<int> _ownerBytes;
  final List<int> _stateBytes;
  final List<int> _anchorBytes;
}

typedef ActivityOutboxAudit =
    void Function(String fixedCode, Map<String, int> nonSensitiveCounts);
typedef ActivityOutboxFaultInjector = void Function(ActivityOutboxFaultPoint);
typedef ActivityOutboxRecoveryCriticalSectionHook = void Function();
typedef ActivityOutboxOwnerDeletionForTest = void Function(File ownerFile);
typedef ActivityFixedByteTransport =
    Future<ActivityCoreReceipt> Function(Uint8List fixedWireBytes);

final class ActivityCoreReceipt {
  const ActivityCoreReceipt({
    required this.eventId,
    required this.kind,
    this.rejection,
  });

  final String eventId;
  final ActivityCoreReceiptKind kind;
  final ActivityRejection? rejection;
}

/// Signed local proof that the privacy-reduced observation was admitted no
/// later than 24 hours after its signal time. A3 must supply the trusted raw
/// collector boundary; this class never accepts or stores raw activity data.
final class ActivityAgeProof {
  const ActivityAgeProof({
    required this.source,
    required this.bindingDigest,
    required this.signalAtMs,
    required this.observedAtMs,
    required this.maxAgeMs,
    required this.mac,
  });

  final AndroidActivitySource source;
  final String bindingDigest;
  final int signalAtMs;
  final int observedAtMs;
  final int maxAgeMs;
  final String mac;
}

abstract interface class ActivityAgeProofProvider {
  ActivityAgeProof issue({
    required AndroidActivitySource source,
    required String bindingDigest,
    required int signalAtMs,
    required int observedAtMs,
  });
}

final class HmacActivityAgeProofProvider implements ActivityAgeProofProvider {
  HmacActivityAgeProofProvider({
    required List<int> integrityKey,
    this.maxAgeMs = _maxDurationMs,
  }) : _key = List<int>.unmodifiable(integrityKey) {
    if (_key.length < 32 || maxAgeMs < 1 || maxAgeMs > _maxDurationMs) {
      throw const AndroidActivityException('invalid_age_proof_authority');
    }
  }

  final List<int> _key;
  final int maxAgeMs;

  @override
  ActivityAgeProof issue({
    required AndroidActivitySource source,
    required String bindingDigest,
    required int signalAtMs,
    required int observedAtMs,
  }) {
    final body = _ageProofBody(
      source.wireValue,
      bindingDigest,
      signalAtMs,
      observedAtMs,
      maxAgeMs,
    );
    return ActivityAgeProof(
      source: source,
      bindingDigest: bindingDigest,
      signalAtMs: signalAtMs,
      observedAtMs: observedAtMs,
      maxAgeMs: maxAgeMs,
      mac: _hmac(_key, body),
    );
  }
}

final class ActivityOutboxRecoveryInspection {
  const ActivityOutboxRecoveryInspection({
    required this.source,
    required this.bindingDigest,
    required this.ownerId,
    required this.anchorGeneration,
    required this.anchorDigest,
  });

  final AndroidActivitySource source;
  final String bindingDigest;
  final String ownerId;
  final int anchorGeneration;
  final String anchorDigest;
}

/// Explicit authority for replacing one exact stale owner. It cannot authorize
/// another source, binding, anchor, or a newer owner discovered after issuance.
final class ActivityOutboxRecoveryAuthority {
  const ActivityOutboxRecoveryAuthority({
    required this.source,
    required this.bindingDigest,
    required this.expectedOwnerId,
    required this.expectedAnchorGeneration,
    required this.expectedAnchorDigest,
  });

  factory ActivityOutboxRecoveryAuthority.fromInspection(
    ActivityOutboxRecoveryInspection inspection,
  ) => ActivityOutboxRecoveryAuthority(
    source: inspection.source,
    bindingDigest: inspection.bindingDigest,
    expectedOwnerId: inspection.ownerId,
    expectedAnchorGeneration: inspection.anchorGeneration,
    expectedAnchorDigest: inspection.anchorDigest,
  );

  final AndroidActivitySource source;
  final String bindingDigest;
  final String expectedOwnerId;
  final int expectedAnchorGeneration;
  final String expectedAnchorDigest;
}

final class DurableOutboxRecord {
  const DurableOutboxRecord({
    required this.event,
    required this.delivery,
    required this.attempts,
    required this.ageProof,
    required this.releaseDeadlineMs,
    required this.attemptToken,
    required this.rejection,
  });

  final AndroidActivityEvent event;
  final DurableDeliveryState delivery;
  final int attempts;
  final ActivityAgeProof ageProof;
  final int releaseDeadlineMs;
  final String? attemptToken;
  final ActivityRejection? rejection;

  DurableOutboxRecord copyWith({
    DurableDeliveryState? delivery,
    int? attempts,
    String? attemptToken,
    bool clearAttemptToken = false,
    ActivityRejection? rejection,
  }) => DurableOutboxRecord(
    event: event,
    delivery: delivery ?? this.delivery,
    attempts: attempts ?? this.attempts,
    ageProof: ageProof,
    releaseDeadlineMs: releaseDeadlineMs,
    attemptToken: clearAttemptToken ? null : attemptToken ?? this.attemptToken,
    rejection: rejection ?? this.rejection,
  );
}

final class ActivityAttemptTicket {
  const ActivityAttemptTicket._({
    required this.ownerId,
    required this.eventId,
    required this.attemptToken,
    required this.fixedWireBytes,
  });

  final String ownerId;
  final String eventId;
  final String attemptToken;
  final Uint8List fixedWireBytes;
}

final class _StoreState {
  const _StoreState({
    required this.generation,
    required this.lastSequence,
    required this.lastSignalAtMs,
    required this.clockFloorMs,
    required this.frozenCode,
    required this.records,
  });

  final int generation;
  final int lastSequence;
  final int? lastSignalAtMs;
  final int clockFloorMs;
  final String? frozenCode;
  final List<DurableOutboxRecord> records;

  _StoreState copyWith({
    int? generation,
    int? lastSequence,
    int? lastSignalAtMs,
    bool clearLastSignalAt = false,
    int? clockFloorMs,
    String? frozenCode,
    bool clearFrozenCode = false,
    List<DurableOutboxRecord>? records,
  }) => _StoreState(
    generation: generation ?? this.generation,
    lastSequence: lastSequence ?? this.lastSequence,
    lastSignalAtMs: clearLastSignalAt
        ? null
        : lastSignalAtMs ?? this.lastSignalAtMs,
    clockFloorMs: clockFloorMs ?? this.clockFloorMs,
    frozenCode: clearFrozenCode ? null : frozenCode ?? this.frozenCode,
    records: records ?? this.records,
  );
}

/// File-backed, one-source durable outbox. The directory is the injected local
/// persistence boundary; the integrity key and age-proof provider stay outside
/// it. No database, platform event, network, credential, timer, or scheduler is
/// accessed here.
final class FileActivityOutboxStore implements ActivityOutboxStore {
  FileActivityOutboxStore._({
    required this.directory,
    required this.binding,
    required this.capacity,
    required List<int> integrityKey,
    required ActivityAgeProofProvider ageProofProvider,
    required int Function() clockMs,
    required String ownerId,
    required _StoreState state,
    required bool restored,
    ActivityOutboxAudit? audit,
    ActivityOutboxFaultInjector? faultInjector,
    ActivityOutboxOwnerDeletionForTest? ownerDeletionForTest,
    ActivityOutboxProcessLease? processLease,
    void Function()? beforeOwnerDeleteForTesting,
  }) : _integrityKey = List<int>.unmodifiable(integrityKey),
       _ageProofProvider = ageProofProvider,
       _clockMs = clockMs,
       _ownerId = ownerId,
       _state = state,
       _restored = restored,
       _audit = audit,
       _faultInjector = faultInjector,
       _ownerDeletionForTest = ownerDeletionForTest,
       _processLease = processLease,
       _beforeOwnerDeleteForTesting = beforeOwnerDeleteForTesting;

  static FileActivityOutboxStore create({
    required Directory directory,
    required SyntheticProbeBinding binding,
    required int capacity,
    required List<int> integrityKey,
    required ActivityAgeProofProvider ageProofProvider,
    required int Function() clockMs,
    ActivityOutboxAudit? audit,
    ActivityOutboxFaultInjector? faultInjector,
    ActivityOutboxOwnerDeletionForTest? ownerDeletionForTest,
    ActivityOutboxProcessLease? processLease,
    void Function()? beforeOwnerDeleteForTesting,
  }) {
    _validateConstruction(capacity, integrityKey);
    if (directory.existsSync() && directory.listSync().isNotEmpty) {
      throw const AndroidActivityException('outbox_already_exists');
    }
    directory.createSync(recursive: true);
    binding.claimSequenceAuthority();
    final now = clockMs();
    _timestamp(now);
    final ownerId = _randomToken();
    final store = FileActivityOutboxStore._(
      directory: directory,
      binding: binding,
      capacity: capacity,
      integrityKey: integrityKey,
      ageProofProvider: ageProofProvider,
      clockMs: clockMs,
      ownerId: ownerId,
      state: _StoreState(
        generation: 1,
        lastSequence: 0,
        lastSignalAtMs: null,
        clockFloorMs: now,
        frozenCode: null,
        records: const [],
      ),
      restored: false,
      audit: audit,
      faultInjector: faultInjector,
      ownerDeletionForTest: ownerDeletionForTest,
      processLease: processLease,
      beforeOwnerDeleteForTesting: beforeOwnerDeleteForTesting,
    );
    try {
      store._createOwnerLock();
      final stateBytes = store._encodeState(store._state);
      final digest = _sha256Hex(stateBytes);
      _replaceFile(store._stateFile, store._stateEnvelope(stateBytes));
      _replaceFile(
        store._anchorFile,
        store._anchorEnvelope(store._state.generation, digest),
      );
      store._auditCode('outbox_created', {'records': 0});
      return store;
    } catch (_) {
      store._removeOwnLock();
      rethrow;
    }
  }

  static FileActivityOutboxStore open({
    required Directory directory,
    required SyntheticProbeBinding binding,
    required int capacity,
    required List<int> integrityKey,
    required ActivityAgeProofProvider ageProofProvider,
    required int Function() clockMs,
    ActivityOutboxRecoveryAuthority? recoveryAuthority,
    ActivityOutboxAudit? audit,
    ActivityOutboxFaultInjector? faultInjector,
    ActivityOutboxRecoveryCriticalSectionHook? recoveryCriticalSectionHook,
    ActivityOutboxOwnerDeletionForTest? ownerDeletionForTest,
    ActivityOutboxProcessLease? processLease,
    void Function()? beforeOwnerDeleteForTesting,
  }) {
    _validateConstruction(capacity, integrityKey);
    if (!directory.existsSync()) {
      throw const AndroidActivityException('outbox_missing');
    }
    binding.claimSequenceAuthority();
    final ownerId = _randomToken();
    final provisional = FileActivityOutboxStore._(
      directory: directory,
      binding: binding,
      capacity: capacity,
      integrityKey: integrityKey,
      ageProofProvider: ageProofProvider,
      clockMs: clockMs,
      ownerId: ownerId,
      state: const _StoreState(
        generation: 0,
        lastSequence: 0,
        lastSignalAtMs: null,
        clockFloorMs: 0,
        frozenCode: null,
        records: [],
      ),
      restored: true,
      audit: audit,
      faultInjector: faultInjector,
      ownerDeletionForTest: ownerDeletionForTest,
      processLease: processLease,
      beforeOwnerDeleteForTesting: beforeOwnerDeleteForTesting,
    );
    var ownsLock = false;
    try {
      provisional._acquireForOpen(
        recoveryAuthority,
        recoveryCriticalSectionHook: recoveryCriticalSectionHook,
      );
      ownsLock = true;
      provisional._recoverJournalIfPresent();
      provisional._state = provisional._readAndValidateState();
      final now = clockMs();
      _timestamp(now);
      if (now < provisional._state.clockFloorMs) {
        provisional._commit(
          provisional._state.copyWith(frozenCode: 'clock_regression'),
        );
      }
      provisional._auditCode('outbox_opened', {
        'records': provisional._state.records.length,
      });
      return provisional;
    } catch (error) {
      if (ownsLock) provisional._removeOwnLock();
      if (error is AndroidActivityException) rethrow;
      throw const AndroidActivityException('outbox_corrupt');
    }
  }

  static ActivityOutboxRecoveryInspection inspectRecovery({
    required Directory directory,
    required List<int> integrityKey,
  }) {
    _validateConstruction(1, integrityKey);
    final anchor = _decodeSignedJson(
      File('${directory.path}${Platform.pathSeparator}anchor.json'),
      integrityKey,
      'anchor-v1',
      'outbox_anchor_invalid',
    );
    final owner = _decodeSignedJson(
      File('${directory.path}${Platform.pathSeparator}owner.json'),
      integrityKey,
      'owner-v1',
      'owner_lock_invalid',
    );
    _expectKeys(anchor, const {'format_version', 'generation', 'state_digest'});
    _expectKeys(owner, const {
      'format_version',
      'owner_id',
      'source',
      'binding_digest',
    });
    if (_int(anchor, 'format_version') != _formatVersion ||
        _int(owner, 'format_version') != _formatVersion) {
      throw const AndroidActivityException('outbox_version_unsupported');
    }
    final source = AndroidActivitySource.values.singleWhere(
      (value) => value.wireValue == owner['source'],
      orElse: () => throw const AndroidActivityException('owner_lock_invalid'),
    );
    return ActivityOutboxRecoveryInspection(
      source: source,
      bindingDigest: _string(owner, 'binding_digest'),
      ownerId: _string(owner, 'owner_id'),
      anchorGeneration: _int(anchor, 'generation'),
      anchorDigest: _string(anchor, 'state_digest'),
    );
  }

  /// Reads signed evidence only. This does not acquire a gate, recover a journal,
  /// claim sequence authority, or manufacture a new owner.
  static ActivityOutboxReleaseTarget inspectReleaseTarget({
    required Directory directory,
    required List<int> integrityKey,
    required SyntheticProbeBinding binding,
  }) {
    _validateConstruction(1, integrityKey);
    final canonicalRoot = _validateReleaseDirectory(directory);
    final inspection = inspectRecovery(
      directory: directory,
      integrityKey: integrityKey,
    );
    if (inspection.source != binding.source ||
        inspection.bindingDigest != _bindingDigest(binding) ||
        inspection.ownerId.isEmpty) {
      throw const AndroidActivityException('source_binding_mismatch');
    }
    final stateFile = File(
      '${directory.path}${Platform.pathSeparator}state.json',
    );
    final envelope = _decodeSignedJson(
      stateFile,
      integrityKey,
      'state-v1',
      'outbox_corrupt',
    );
    _expectKeys(envelope, const {'format_version', 'payload_b64'});
    final decoded = jsonDecode(
      utf8.decode(base64Decode(_string(envelope, 'payload_b64'))),
    );
    if (decoded is! Map) throw const AndroidActivityException('outbox_corrupt');
    final capacity = _int(Map<String, Object?>.from(decoded), 'capacity');
    _validateConstruction(capacity, integrityKey);
    // This validator has no file lease and never escapes this method.
    final validator = FileActivityOutboxStore._(
      directory: directory,
      binding: binding,
      capacity: capacity,
      integrityKey: integrityKey,
      ageProofProvider: HmacActivityAgeProofProvider(
        integrityKey: integrityKey,
      ),
      clockMs: () => 0,
      ownerId: inspection.ownerId,
      state: const _StoreState(
        generation: 0,
        lastSequence: 0,
        lastSignalAtMs: null,
        clockFloorMs: 0,
        frozenCode: null,
        records: [],
      ),
      restored: true,
    );
    validator._readAndValidateState();
    return ActivityOutboxReleaseTarget._(
      source: binding.source,
      bindingDigest: _bindingDigest(binding),
      canonicalRoot: canonicalRoot,
      binding: binding,
      ownerBytes: validator._ownerFile.readAsBytesSync(),
      stateBytes: stateFile.readAsBytesSync(),
      anchorBytes: validator._anchorFile.readAsBytesSync(),
    );
  }

  /// Caller must hold the native exact-terminal recovery permit and both source
  /// broker leases. This primitive only removes the frozen signed owner.
  static ActivityOutboxOwnerReleaseOutcome releaseExactOwner({
    required Directory directory,
    required List<int> integrityKey,
    required ActivityOutboxReleaseTarget target,
    required ActivityOutboxProcessLease processLease,
    ActivityOutboxRecoveryCriticalSectionHook? recoveryCriticalSectionHook,
  }) {
    _validateConstruction(1, integrityKey);
    final claimant = Object();
    processLease.claimFileAccess(claimant, target.source.wireValue);
    RandomAccessFile? gate;
    try {
      _verifyReleaseTarget(directory, integrityKey, target);
      processLease.verifyFileAccess(claimant, target.source.wireValue);
      gate = File(
        '${directory.path}${Platform.pathSeparator}owner.gate',
      ).openSync(mode: FileMode.append);
      try {
        gate.lockSync(FileLock.exclusive);
      } catch (_) {
        throw const AndroidActivityException('owner_still_active');
      }
      _verifyReleaseTarget(directory, integrityKey, target);
      recoveryCriticalSectionHook?.call();
      final present = _verifyReleaseTarget(directory, integrityKey, target);
      processLease.verifyFileAccess(claimant, target.source.wireValue);
      if (!present) return ActivityOutboxOwnerReleaseOutcome.targetAbsent;
      File('${directory.path}${Platform.pathSeparator}owner.json').deleteSync();
      return ActivityOutboxOwnerReleaseOutcome.released;
    } on AndroidActivityException {
      rethrow;
    } catch (_) {
      throw const AndroidActivityException('owner_release_failed');
    } finally {
      // close (without an unlock-before-close window) is the resource proof.
      // A close failure deliberately retains the claim and native lease.
      if (gate != null) {
        try {
          gate.closeSync();
        } catch (_) {
          throw const AndroidActivityException('owner_release_failed');
        }
      }
      processLease.releaseFileAccess(claimant);
    }
  }

  static bool verifyReleaseTarget({
    required Directory directory,
    required List<int> integrityKey,
    required ActivityOutboxReleaseTarget target,
  }) => _verifyReleaseTarget(directory, integrityKey, target);

  static bool _verifyReleaseTarget(
    Directory directory,
    List<int> key,
    ActivityOutboxReleaseTarget target,
  ) {
    if (_validateReleaseDirectory(directory) != target._canonicalRoot) {
      throw const AndroidActivityException('owner_release_target_changed');
    }
    for (final entry in {
      'state.json': target._stateBytes,
      'anchor.json': target._anchorBytes,
    }.entries) {
      if (!const ListEquality<int>().equals(
        File(
          '${directory.path}${Platform.pathSeparator}${entry.key}',
        ).readAsBytesSync(),
        entry.value,
      )) {
        throw const AndroidActivityException('owner_release_target_changed');
      }
    }
    final owner = File('${directory.path}${Platform.pathSeparator}owner.json');
    if (!owner.existsSync()) return false;
    if (!const ListEquality<int>().equals(
      owner.readAsBytesSync(),
      target._ownerBytes,
    )) {
      throw const AndroidActivityException('owner_release_target_changed');
    }
    final verified = inspectReleaseTarget(
      directory: directory,
      integrityKey: key,
      binding: target._binding,
    );
    if (!const ListEquality<int>().equals(
          verified._ownerBytes,
          target._ownerBytes,
        ) ||
        !const ListEquality<int>().equals(
          verified._stateBytes,
          target._stateBytes,
        ) ||
        !const ListEquality<int>().equals(
          verified._anchorBytes,
          target._anchorBytes,
        )) {
      throw const AndroidActivityException('owner_release_target_changed');
    }
    return true;
  }

  static String _validateReleaseDirectory(Directory directory) {
    const allowed = {
      'owner.json',
      'owner.gate',
      'state.json',
      'anchor.json',
      'journal.json',
    };
    try {
      final canonical = directory.resolveSymbolicLinksSync();
      String normalize(String path) =>
          Platform.isWindows ? path.toLowerCase() : path;
      if (normalize(canonical) != normalize(directory.absolute.path) ||
          FileSystemEntity.typeSync(directory.path, followLinks: false) !=
              FileSystemEntityType.directory) {
        throw const AndroidActivityException('owner_release_path_invalid');
      }
      final entries = directory.listSync(followLinks: false);
      for (final entry in entries) {
        final name = entry.path.replaceAll('\\', '/').split('/').last;
        if (entry is! File || !allowed.contains(name)) {
          throw const AndroidActivityException('owner_release_path_invalid');
        }
        if (name == 'journal.json') {
          throw const AndroidActivityException('owner_release_journal_present');
        }
      }
      for (final name in const ['owner.gate', 'state.json', 'anchor.json']) {
        if (FileSystemEntity.typeSync(
              '${directory.path}${Platform.pathSeparator}$name',
              followLinks: false,
            ) !=
            FileSystemEntityType.file) {
          throw const AndroidActivityException('owner_release_path_invalid');
        }
      }
      return canonical;
    } on AndroidActivityException {
      rethrow;
    } catch (_) {
      throw const AndroidActivityException('owner_release_path_invalid');
    }
  }

  final Directory directory;
  @override
  final SyntheticProbeBinding binding;
  @override
  final int capacity;
  final List<int> _integrityKey;
  final ActivityAgeProofProvider _ageProofProvider;
  final int Function() _clockMs;
  final ActivityOutboxAudit? _audit;
  final ActivityOutboxFaultInjector? _faultInjector;
  final ActivityOutboxOwnerDeletionForTest? _ownerDeletionForTest;
  final ActivityOutboxProcessLease? _processLease;
  final void Function()? _beforeOwnerDeleteForTesting;
  final String _ownerId;
  _StoreState _state;
  bool _restored;
  bool _collectorAttached = false;
  bool _closed = false;
  bool _poisoned = false;
  bool _sending = false;
  ActivityAttemptTicket? _activeTicket;
  RandomAccessFile? _leaseHandle;
  bool _fileClaimHeld = false;
  SyntheticCoreContact _lastContact = SyntheticCoreContact.unobserved;

  File get _stateFile =>
      File('${directory.path}${Platform.pathSeparator}state.json');
  File get _anchorFile =>
      File('${directory.path}${Platform.pathSeparator}anchor.json');
  File get _journalFile =>
      File('${directory.path}${Platform.pathSeparator}journal.json');
  File get _gateFile =>
      File('${directory.path}${Platform.pathSeparator}owner.gate');
  File get _ownerFile =>
      File('${directory.path}${Platform.pathSeparator}owner.json');
  String get bindingDigest => _bindingDigest(binding);
  bool get ownerLeaseReleased => _leaseHandle == null && !_fileClaimHeld;

  ActivityOutboxReleaseTarget inspectOwnReleaseTarget() {
    _verifyOwner();
    return inspectReleaseTarget(
      directory: directory,
      integrityKey: _integrityKey,
      binding: binding,
    );
  }

  List<DurableOutboxRecord> get durableRecords =>
      List<DurableOutboxRecord>.unmodifiable(_state.records);
  String? get frozenCode => _state.frozenCode;
  String? get gapCode =>
      _state.records.length >= capacity ? 'outbox_full' : null;

  @override
  int get lastAllocatedSequence => _state.lastSequence;
  @override
  int? get lastSignalAt => _state.lastSignalAtMs;
  @override
  bool get lineageBlocked => _closed || _poisoned || _state.frozenCode != null;
  @override
  bool get restored => _restored;
  @override
  bool get collectorAttached => _collectorAttached;
  @override
  set collectorAttached(bool value) => _collectorAttached = value;
  @override
  SyntheticCoreContact get lastContact => _lastContact;

  @override
  void assertOwned() => _verifyOwner();

  @override
  void acknowledgeRestartGap() {
    _verifyOwner();
    _restored = false;
  }

  @override
  AndroidActivityEvent enqueue({
    required String kind,
    required int atMs,
    required int ttlMs,
    required String confidence,
    Map<String, Object?> payload = const {},
  }) {
    final observedAtMs = _clockMs();
    final proof = _ageProofProvider.issue(
      source: binding.source,
      bindingDigest: bindingDigest,
      signalAtMs: atMs,
      observedAtMs: observedAtMs,
    );
    return _enqueueWithAgeProofAt(
      kind: kind,
      atMs: atMs,
      ttlMs: ttlMs,
      confidence: confidence,
      payload: payload,
      ageProof: proof,
      now: observedAtMs,
    );
  }

  AndroidActivityEvent enqueueWithAgeProof({
    required String kind,
    required int atMs,
    required int ttlMs,
    required String confidence,
    required ActivityAgeProof ageProof,
    Map<String, Object?> payload = const {},
  }) => _enqueueWithAgeProofAt(
    kind: kind,
    atMs: atMs,
    ttlMs: ttlMs,
    confidence: confidence,
    payload: payload,
    ageProof: ageProof,
    now: _clockMs(),
  );

  AndroidActivityEvent _enqueueWithAgeProofAt({
    required String kind,
    required int atMs,
    required int ttlMs,
    required String confidence,
    required ActivityAgeProof ageProof,
    required int now,
    Map<String, Object?> payload = const {},
  }) {
    _verifyOwner();
    if (_state.frozenCode != null || _state.lastSequence == _maxSafeInteger) {
      throw const AndroidActivityException('lineage_blocked');
    }
    if (_state.records.length >= capacity) {
      _auditCode('outbox_full', {'records': _state.records.length});
      throw const AndroidActivityException('outbox_full');
    }
    _timestamp(atMs);
    _duration(ttlMs);
    _timestamp(now);
    if (now < _state.clockFloorMs ||
        atMs > now ||
        atMs > _maxSafeInteger - ttlMs) {
      _freezeForClockRegression();
      throw const AndroidActivityException('clock_uncertain');
    }
    _validateScope(kind, payload);
    if (_state.lastSignalAtMs != null && atMs < _state.lastSignalAtMs!) {
      _freezeForClockRegression();
      throw const AndroidActivityException('clock_uncertain');
    }
    _verifyAgeProof(ageProof, atMs, now);
    final sequence = _state.lastSequence + 1;
    final event = AndroidActivityEvent.create(
      binding: binding,
      originSequence: sequence,
      kind: kind,
      signalAtMs: atMs,
      ttlMs: ttlMs,
      confidence: confidence,
      payload: payload,
    );
    _validateFixedWire(event, binding, sequence);
    final deadline = atMs + ageProof.maxAgeMs;
    final record = DurableOutboxRecord(
      event: event,
      delivery: DurableDeliveryState.neverSent,
      attempts: 0,
      ageProof: ageProof,
      releaseDeadlineMs: deadline,
      attemptToken: null,
      rejection: null,
    );
    _commit(
      _state.copyWith(
        lastSequence: sequence,
        lastSignalAtMs: atMs,
        clockFloorMs: now,
        records: [..._state.records, record],
      ),
    );
    return event;
  }

  void freeze(String fixedCode) {
    _verifyOwner();
    if (_state.frozenCode != null) return;
    if (!const {
      'scope_denied',
      'unregistered_diagnostic',
      'sequence_authority_lost',
      'permission_revoked',
      'raw_release_deadline_expired',
    }.contains(fixedCode)) {
      throw const AndroidActivityException('invalid_freeze_code');
    }
    _commit(_state.copyWith(frozenCode: fixedCode));
    _auditCode(fixedCode, {'pending': _unsettledCount});
  }

  ActivityAttemptTicket? beginNextAttempt() {
    _verifyOwner();
    if (_activeTicket != null) {
      throw const AndroidActivityException('attempt_in_progress');
    }
    if (_state.frozenCode != null) return null;
    final index = _state.records.indexWhere(
      (record) =>
          record.delivery == DurableDeliveryState.neverSent ||
          record.delivery == DurableDeliveryState.attemptedUnknown,
    );
    if (index < 0) return null;
    final now = _clockMs();
    _timestamp(now);
    if (now < _state.clockFloorMs) {
      _freezeForClockRegression();
      return null;
    }
    final record = _state.records[index];
    if (now > record.releaseDeadlineMs) {
      _commit(
        _state.copyWith(
          clockFloorMs: now,
          frozenCode: 'raw_release_deadline_expired',
        ),
      );
      _auditCode('raw_release_deadline_expired', {'pending': _unsettledCount});
      return null;
    }
    final attemptToken = _randomToken();
    final attempted = record.copyWith(
      delivery: DurableDeliveryState.attemptedUnknown,
      attempts: record.attempts + 1,
      attemptToken: attemptToken,
    );
    final records = [..._state.records]..[index] = attempted;
    _commit(_state.copyWith(clockFloorMs: now, records: records));
    final ticket = ActivityAttemptTicket._(
      ownerId: _ownerId,
      eventId: record.event.eventId,
      attemptToken: attemptToken,
      fixedWireBytes: Uint8List.fromList(utf8.encode(record.event.json)),
    );
    _activeTicket = ticket;
    return ticket;
  }

  bool settleAttempt(
    ActivityAttemptTicket ticket,
    ActivityCoreReceipt receipt,
  ) {
    _verifyTicket(ticket);
    final index = _state.records.indexWhere(
      (record) => record.event.eventId == ticket.eventId,
    );
    final record = index < 0 ? null : _state.records[index];
    final shapeValid =
        record != null &&
        record.delivery == DurableDeliveryState.attemptedUnknown &&
        record.attemptToken == ticket.attemptToken &&
        receipt.eventId == ticket.eventId &&
        ((receipt.kind == ActivityCoreReceiptKind.terminalRejected) ==
            (receipt.rejection != null));
    if (!shapeValid) {
      _activeTicket = null;
      _lastContact = SyntheticCoreContact.unreachable;
      _auditCode('receipt_invalid', {'attempted': 1});
      return false;
    }
    if (receipt.kind == ActivityCoreReceiptKind.retryable) {
      _activeTicket = null;
      _lastContact = SyntheticCoreContact.reachable;
      return false;
    }
    final delivery = switch (receipt.kind) {
      ActivityCoreReceiptKind.accepted => DurableDeliveryState.accepted,
      ActivityCoreReceiptKind.duplicate => DurableDeliveryState.duplicate,
      ActivityCoreReceiptKind.terminalRejected =>
        DurableDeliveryState.terminalRejected,
      ActivityCoreReceiptKind.retryable =>
        DurableDeliveryState.attemptedUnknown,
    };
    final settled = record.copyWith(
      delivery: delivery,
      clearAttemptToken: true,
      rejection: receipt.rejection,
    );
    final records = [..._state.records]..[index] = settled;
    _commit(
      _state.copyWith(
        records: records,
        frozenCode: delivery == DurableDeliveryState.terminalRejected
            ? receipt.rejection!.coreCode
            : _state.frozenCode,
      ),
    );
    _activeTicket = null;
    _lastContact = SyntheticCoreContact.reachable;
    return true;
  }

  void abandonAttempt(ActivityAttemptTicket ticket) {
    _verifyTicket(ticket);
    _activeTicket = null;
    _lastContact = SyntheticCoreContact.unreachable;
    _auditCode('transport_ambiguous', {'attempted': 1});
  }

  Future<void> flush(ActivityFixedByteTransport transport) async {
    _verifyOwner();
    if (_sending) throw const AndroidActivityException('flush_in_progress');
    if (_state.frozenCode != null) return;
    _sending = true;
    final limit = _unsettledCount;
    try {
      for (var sent = 0; sent < limit; sent++) {
        if (_state.frozenCode != null) break;
        final ticket = beginNextAttempt();
        if (ticket == null) break;
        ActivityCoreReceipt receipt;
        try {
          receipt = await transport(Uint8List.fromList(ticket.fixedWireBytes));
        } catch (_) {
          abandonAttempt(ticket);
          break;
        }
        final settled = settleAttempt(ticket, receipt);
        if (!settled ||
            receipt.kind == ActivityCoreReceiptKind.terminalRejected) {
          break;
        }
      }
    } finally {
      _sending = false;
    }
  }

  void close() {
    _verifyOwner();
    if (_activeTicket != null || _sending) {
      throw const AndroidActivityException('attempt_in_progress');
    }
    _closed = true;
    _removeOwnLock();
    _auditCode('outbox_closed', {'records': _state.records.length});
  }

  /// Test-only process-death seam. Real process exit releases this OS lock.
  /// It intentionally does not delete or rewrite durable ownership evidence.
  void releaseProcessLeaseForTest() {
    _releaseLeaseOnly();
    _poisoned = true;
  }

  int get _unsettledCount => _state.records
      .where(
        (record) =>
            record.delivery == DurableDeliveryState.neverSent ||
            record.delivery == DurableDeliveryState.attemptedUnknown,
      )
      .length;

  void _freezeForClockRegression() {
    if (_state.frozenCode == null) {
      _commit(_state.copyWith(frozenCode: 'clock_regression'));
    }
    _auditCode('clock_regression', {'pending': _unsettledCount});
  }

  void _validateScope(String kind, Map<String, Object?> payload) {
    if (!binding.allowedKinds.contains(kind)) {
      _commit(_state.copyWith(frozenCode: 'scope_denied'));
      throw const AndroidActivityException('scope_denied');
    }
    if ((kind == 'probe.permission_changed' &&
            !binding.capabilities.contains(payload['capability'])) ||
        (kind == 'probe.error' &&
            !binding.capabilities.contains('probe_error.${payload['code']}'))) {
      _commit(_state.copyWith(frozenCode: 'unregistered_diagnostic'));
      throw const AndroidActivityException('unregistered_diagnostic');
    }
  }

  void _verifyAgeProof(ActivityAgeProof proof, int atMs, int now) {
    final expected = _hmac(
      _integrityKey,
      _ageProofBody(
        proof.source.wireValue,
        proof.bindingDigest,
        proof.signalAtMs,
        proof.observedAtMs,
        proof.maxAgeMs,
      ),
    );
    if (proof.source != binding.source ||
        proof.bindingDigest != bindingDigest ||
        proof.signalAtMs != atMs ||
        proof.observedAtMs != now ||
        proof.maxAgeMs < 1 ||
        proof.maxAgeMs > _maxDurationMs ||
        now < atMs ||
        now - atMs > proof.maxAgeMs ||
        !_constantTimeEquals(proof.mac, expected)) {
      throw const AndroidActivityException('age_proof_invalid');
    }
  }

  void _verifyTicket(ActivityAttemptTicket ticket) {
    _verifyOwner();
    if (_activeTicket == null ||
        ticket.ownerId != _ownerId ||
        ticket.attemptToken != _activeTicket!.attemptToken ||
        ticket.eventId != _activeTicket!.eventId) {
      throw const AndroidActivityException('stale_attempt_receipt');
    }
  }

  void _verifyOwner() {
    if (_closed || _poisoned || _leaseHandle == null) {
      throw const AndroidActivityException('sequence_authority_required');
    }
    _processLease?.verifyFileAccess(this, binding.source.wireValue);
    Map<String, Object?> owner;
    try {
      owner = _decodeSignedJson(
        _ownerFile,
        _integrityKey,
        'owner-v1',
        'sequence_authority_required',
      );
    } on AndroidActivityException {
      _poisoned = true;
      rethrow;
    }
    if (owner['owner_id'] != _ownerId ||
        owner['source'] != binding.source.wireValue ||
        owner['binding_digest'] != bindingDigest) {
      _poisoned = true;
      throw const AndroidActivityException('sequence_authority_required');
    }
  }

  void _createOwnerLock() {
    final lease = _acquireGate();
    _leaseHandle = lease;
    try {
      if (_ownerFile.existsSync()) {
        throw const AndroidActivityException('owner_already_active');
      }
      _writeOwnerRecord();
    } on AndroidActivityException {
      _releaseLeaseOnly();
      rethrow;
    } catch (_) {
      _releaseLeaseOnly();
      throw const AndroidActivityException('owner_lock_failed');
    }
  }

  RandomAccessFile _acquireGate() {
    if (Platform.isAndroid && _processLease == null) {
      throw const AndroidActivityException('diagnostic_outbox_lease_invalid');
    }
    _processLease?.claimFileAccess(this, binding.source.wireValue);
    _fileClaimHeld = _processLease != null;
    RandomAccessFile? lease;
    try {
      _processLease?.verifyFileAccess(this, binding.source.wireValue);
      lease = _gateFile.openSync(mode: FileMode.append);
      lease.lockSync(FileLock.exclusive);
      return lease;
    } catch (_) {
      try {
        lease?.closeSync();
      } catch (_) {
        _leaseHandle = lease;
        _poisoned = true;
        throw const AndroidActivityException('owner_lock_cleanup_failed');
      }
      if (_fileClaimHeld) _processLease!.releaseFileAccess(this);
      _fileClaimHeld = false;
      throw const AndroidActivityException('owner_still_active');
    }
  }

  void _writeOwnerRecord() {
    if (_leaseHandle == null) {
      throw const AndroidActivityException('sequence_authority_required');
    }
    _replaceFile(
      _ownerFile,
      _signedJson(
        {
          'format_version': _formatVersion,
          'owner_id': _ownerId,
          'source': binding.source.wireValue,
          'binding_digest': bindingDigest,
        },
        _integrityKey,
        'owner-v1',
      ),
    );
  }

  bool _authorityMatches(
    ActivityOutboxRecoveryAuthority authority,
    ActivityOutboxRecoveryInspection inspection,
  ) =>
      authority.source == binding.source &&
      authority.bindingDigest == bindingDigest &&
      authority.expectedOwnerId == inspection.ownerId &&
      authority.expectedAnchorGeneration == inspection.anchorGeneration &&
      authority.expectedAnchorDigest == inspection.anchorDigest;

  void _acquireForOpen(
    ActivityOutboxRecoveryAuthority? authority, {
    ActivityOutboxRecoveryCriticalSectionHook? recoveryCriticalSectionHook,
  }) {
    if (!_ownerFile.existsSync()) {
      if (authority != null) {
        throw const AndroidActivityException('recovery_authority_invalid');
      }
      _createOwnerLock();
      return;
    }
    if (authority == null) {
      _auditCode('recovery_authority_required', {'locks': 1});
      throw const AndroidActivityException('recovery_authority_required');
    }

    // This first check only preserves the fixed invalid-authority result for an
    // obviously wrong token. It never authorizes a mutation.
    final beforeGate = inspectRecovery(
      directory: directory,
      integrityKey: _integrityKey,
    );
    if (!_authorityMatches(authority, beforeGate)) {
      throw const AndroidActivityException('recovery_authority_invalid');
    }

    final lease = _acquireGate();
    _leaseHandle = lease;
    try {
      // The actual authorization decision is repeated while the stable gate is
      // exclusively held. The gate remains held through owner replacement and
      // then becomes the new owner's lifetime lease.
      final insideGate = inspectRecovery(
        directory: directory,
        integrityKey: _integrityKey,
      );
      if (!_authorityMatches(authority, insideGate)) {
        throw const AndroidActivityException('recovery_authority_invalid');
      }
      recoveryCriticalSectionHook?.call();
      final immediatelyBeforeReplace = inspectRecovery(
        directory: directory,
        integrityKey: _integrityKey,
      );
      if (!_authorityMatches(authority, immediatelyBeforeReplace) ||
          immediatelyBeforeReplace.ownerId != insideGate.ownerId ||
          immediatelyBeforeReplace.anchorGeneration !=
              insideGate.anchorGeneration ||
          immediatelyBeforeReplace.anchorDigest != insideGate.anchorDigest) {
        throw const AndroidActivityException('recovery_authority_invalid');
      }
      _writeOwnerRecord();
      _auditCode('stale_owner_recovered', {'locks': 1});
    } on AndroidActivityException {
      _releaseLeaseOnly();
      rethrow;
    } catch (_) {
      _releaseLeaseOnly();
      throw const AndroidActivityException('owner_lock_failed');
    }
  }

  void _removeOwnLock() {
    final lease = _leaseHandle;
    if (lease == null) return;
    try {
      final owner = _decodeSignedJson(
        _ownerFile,
        _integrityKey,
        'owner-v1',
        'sequence_authority_required',
      );
      if (owner['owner_id'] != _ownerId ||
          owner['source'] != binding.source.wireValue ||
          owner['binding_digest'] != bindingDigest) {
        _poisoned = true;
        throw const AndroidActivityException('sequence_authority_required');
      }
      if (_ownerFile.existsSync()) {
        try {
          _beforeOwnerDeleteForTesting?.call();
          final injectedDeletion = _ownerDeletionForTest;
          if (injectedDeletion == null) {
            _ownerFile.deleteSync();
          } else {
            injectedDeletion(_ownerFile);
          }
        } catch (_) {
          _poisoned = true;
          throw const AndroidActivityException('owner_lock_cleanup_failed');
        }
      }
    } finally {
      // Owner evidence may remain after validation or deletion failure, but
      // this process must never strand the stable lifetime gate.
      _releaseLeaseOnly();
    }
  }

  void _releaseLeaseOnly() {
    final lease = _leaseHandle;
    if (lease == null) return;
    try {
      lease.closeSync();
    } catch (_) {
      _poisoned = true;
      throw const AndroidActivityException('owner_lock_cleanup_failed');
    }
    _leaseHandle = null;
    if (_fileClaimHeld) _processLease!.releaseFileAccess(this);
    _fileClaimHeld = false;
  }

  void _commit(_StoreState candidate) {
    _verifyOwner();
    final next = candidate.copyWith(generation: _state.generation + 1);
    final stateBytes = _encodeState(next);
    final stateDigest = _sha256Hex(stateBytes);
    final nextStateFile = _stateEnvelope(stateBytes);
    final nextAnchorFile = _anchorEnvelope(next.generation, stateDigest);
    final currentStateDigest = _sha256Hex(_readStatePayload());
    final journal = _signedJson(
      {
        'format_version': _formatVersion,
        'previous_generation': _state.generation,
        'previous_state_digest': currentStateDigest,
        'next_generation': next.generation,
        'next_state_digest': stateDigest,
        'next_state_file_b64': base64Encode(nextStateFile),
        'next_anchor_file_b64': base64Encode(nextAnchorFile),
      },
      _integrityKey,
      'journal-v1',
    );
    try {
      _replaceFile(_journalFile, journal);
      _faultInjector?.call(ActivityOutboxFaultPoint.afterJournal);
      _replaceFile(_stateFile, nextStateFile);
      _faultInjector?.call(ActivityOutboxFaultPoint.afterState);
      _replaceFile(_anchorFile, nextAnchorFile);
      _faultInjector?.call(ActivityOutboxFaultPoint.afterAnchor);
      _journalFile.deleteSync();
      _state = next;
    } catch (_) {
      _poisoned = true;
      _releaseLeaseOnly();
      _auditCode('transaction_interrupted', {
        'records': candidate.records.length,
      });
      throw const AndroidActivityException('transaction_interrupted');
    }
  }

  void _recoverJournalIfPresent() {
    if (!_journalFile.existsSync()) return;
    final journal = _decodeSignedJson(
      _journalFile,
      _integrityKey,
      'journal-v1',
      'outbox_journal_invalid',
    );
    _expectKeys(journal, const {
      'format_version',
      'previous_generation',
      'previous_state_digest',
      'next_generation',
      'next_state_digest',
      'next_state_file_b64',
      'next_anchor_file_b64',
    });
    if (!_stateFile.existsSync() || !_anchorFile.existsSync()) {
      _replaceFile(
        _stateFile,
        base64Decode(_string(journal, 'next_state_file_b64')),
      );
      _replaceFile(
        _anchorFile,
        base64Decode(_string(journal, 'next_anchor_file_b64')),
      );
      _journalFile.deleteSync();
      return;
    }
    final currentPayload = _readStatePayload();
    final currentDigest = _sha256Hex(currentPayload);
    final anchor = _readAnchor();
    final anchorGeneration = _int(anchor, 'generation');
    final anchorDigest = _string(anchor, 'state_digest');
    final previousGeneration = _int(journal, 'previous_generation');
    final previousDigest = _string(journal, 'previous_state_digest');
    final nextGeneration = _int(journal, 'next_generation');
    final nextDigest = _string(journal, 'next_state_digest');
    if (currentDigest == previousDigest &&
        anchorGeneration == previousGeneration &&
        anchorDigest == previousDigest) {
      _journalFile.deleteSync();
      return;
    }
    if (currentDigest == nextDigest &&
        anchorGeneration == previousGeneration &&
        anchorDigest == previousDigest) {
      _replaceFile(
        _anchorFile,
        base64Decode(_string(journal, 'next_anchor_file_b64')),
      );
      _journalFile.deleteSync();
      return;
    }
    if (currentDigest == nextDigest &&
        anchorGeneration == nextGeneration &&
        anchorDigest == nextDigest) {
      _journalFile.deleteSync();
      return;
    }
    throw const AndroidActivityException('outbox_recovery_invariant_failed');
  }

  _StoreState _readAndValidateState() {
    final payload = _readStatePayload();
    final digest = _sha256Hex(payload);
    final anchor = _readAnchor();
    if (_string(anchor, 'state_digest') != digest) {
      throw const AndroidActivityException('outbox_rollback_detected');
    }
    final decoded = jsonDecode(utf8.decode(payload));
    if (decoded is! Map) {
      throw const AndroidActivityException('outbox_corrupt');
    }
    final map = Map<String, Object?>.from(decoded);
    _expectKeys(map, const {
      'format_version',
      'binding',
      'binding_digest',
      'capacity',
      'generation',
      'last_sequence',
      'last_signal_at_ms',
      'clock_floor_ms',
      'frozen_code',
      'records',
    });
    if (_int(map, 'format_version') != _formatVersion) {
      throw const AndroidActivityException('outbox_version_unsupported');
    }
    if (_int(map, 'capacity') != capacity ||
        _string(map, 'binding_digest') != bindingDigest ||
        !_deepEquals(map['binding'], _bindingMap(binding))) {
      throw const AndroidActivityException('source_binding_mismatch');
    }
    final generation = _int(map, 'generation');
    if (_int(anchor, 'generation') != generation || generation < 1) {
      throw const AndroidActivityException('outbox_rollback_detected');
    }
    final rawRecords = map['records'];
    if (rawRecords is! List || rawRecords.length > capacity) {
      throw const AndroidActivityException('outbox_corrupt');
    }
    final records = <DurableOutboxRecord>[];
    for (var index = 0; index < rawRecords.length; index++) {
      final raw = rawRecords[index];
      if (raw is! Map) throw const AndroidActivityException('outbox_corrupt');
      records.add(_decodeRecord(Map<String, Object?>.from(raw), index + 1));
    }
    final lastSequence = _int(map, 'last_sequence');
    final lastSignal = map['last_signal_at_ms'];
    if (lastSequence != records.length ||
        lastSignal is! int? ||
        (records.isEmpty
            ? lastSignal != null
            : lastSignal != records.last.event.signalAtMs)) {
      throw const AndroidActivityException('outbox_sequence_invariant_failed');
    }
    final frozen = map['frozen_code'];
    if (frozen is! String?) {
      throw const AndroidActivityException('outbox_corrupt');
    }
    return _StoreState(
      generation: generation,
      lastSequence: lastSequence,
      lastSignalAtMs: lastSignal,
      clockFloorMs: _int(map, 'clock_floor_ms'),
      frozenCode: frozen,
      records: List.unmodifiable(records),
    );
  }

  DurableOutboxRecord _decodeRecord(Map<String, Object?> map, int sequence) {
    _expectKeys(map, const {
      'wire_b64',
      'delivery',
      'attempts',
      'attempt_token',
      'release_deadline_ms',
      'age_proof',
      'rejection',
    });
    final wireBytes = base64Decode(_string(map, 'wire_b64'));
    final wire = utf8.decode(wireBytes);
    final event = AndroidActivityEvent.fromFixedJson(wire);
    if (!const ListEquality<int>().equals(wireBytes, utf8.encode(event.json))) {
      throw const AndroidActivityException('outbox_event_bytes_invalid');
    }
    _validateFixedWire(event, binding, sequence);
    final deliveryRaw = _string(map, 'delivery');
    final delivery = DurableDeliveryState.values.singleWhere(
      (value) => value.value == deliveryRaw,
      orElse: () => throw const AndroidActivityException('outbox_corrupt'),
    );
    final attempts = _int(map, 'attempts');
    if (attempts < 0 ||
        (delivery == DurableDeliveryState.neverSent && attempts != 0) ||
        (delivery != DurableDeliveryState.neverSent && attempts < 1)) {
      throw const AndroidActivityException('outbox_attempt_invariant_failed');
    }
    final proofMap = map['age_proof'];
    if (proofMap is! Map) {
      throw const AndroidActivityException('outbox_corrupt');
    }
    final proof = _decodeAgeProof(Map<String, Object?>.from(proofMap));
    _verifyPersistedAgeProof(proof, event.signalAtMs);
    final deadline = _int(map, 'release_deadline_ms');
    if (deadline != event.signalAtMs + proof.maxAgeMs) {
      throw const AndroidActivityException('age_proof_invalid');
    }
    final token = map['attempt_token'];
    if (token is! String? ||
        (delivery == DurableDeliveryState.attemptedUnknown) !=
            (token != null)) {
      throw const AndroidActivityException('outbox_attempt_invariant_failed');
    }
    final rejectionRaw = map['rejection'];
    final rejection = rejectionRaw == null
        ? null
        : ActivityRejection.values.singleWhere(
            (value) => value.coreCode == rejectionRaw,
            orElse: () =>
                throw const AndroidActivityException('outbox_corrupt'),
          );
    if ((delivery == DurableDeliveryState.terminalRejected) !=
        (rejection != null)) {
      throw const AndroidActivityException('outbox_attempt_invariant_failed');
    }
    return DurableOutboxRecord(
      event: event,
      delivery: delivery,
      attempts: attempts,
      ageProof: proof,
      releaseDeadlineMs: deadline,
      attemptToken: token,
      rejection: rejection,
    );
  }

  ActivityAgeProof _decodeAgeProof(Map<String, Object?> map) {
    _expectKeys(map, const {
      'source',
      'binding_digest',
      'signal_at_ms',
      'observed_at_ms',
      'max_age_ms',
      'mac',
    });
    final source = AndroidActivitySource.values.singleWhere(
      (value) => value.wireValue == map['source'],
      orElse: () => throw const AndroidActivityException('age_proof_invalid'),
    );
    return ActivityAgeProof(
      source: source,
      bindingDigest: _string(map, 'binding_digest'),
      signalAtMs: _int(map, 'signal_at_ms'),
      observedAtMs: _int(map, 'observed_at_ms'),
      maxAgeMs: _int(map, 'max_age_ms'),
      mac: _string(map, 'mac'),
    );
  }

  void _verifyPersistedAgeProof(ActivityAgeProof proof, int signalAtMs) {
    final expected = _hmac(
      _integrityKey,
      _ageProofBody(
        proof.source.wireValue,
        proof.bindingDigest,
        proof.signalAtMs,
        proof.observedAtMs,
        proof.maxAgeMs,
      ),
    );
    if (proof.source != binding.source ||
        proof.bindingDigest != bindingDigest ||
        proof.signalAtMs != signalAtMs ||
        proof.maxAgeMs < 1 ||
        proof.maxAgeMs > _maxDurationMs ||
        proof.observedAtMs < signalAtMs ||
        proof.observedAtMs - signalAtMs > proof.maxAgeMs ||
        !_constantTimeEquals(proof.mac, expected)) {
      throw const AndroidActivityException('age_proof_invalid');
    }
  }

  Uint8List _encodeState(_StoreState state) => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format_version': _formatVersion,
        'binding': _bindingMap(binding),
        'binding_digest': bindingDigest,
        'capacity': capacity,
        'generation': state.generation,
        'last_sequence': state.lastSequence,
        'last_signal_at_ms': state.lastSignalAtMs,
        'clock_floor_ms': state.clockFloorMs,
        'frozen_code': state.frozenCode,
        'records': state.records
            .map(
              (record) => {
                'wire_b64': base64Encode(utf8.encode(record.event.json)),
                'delivery': record.delivery.value,
                'attempts': record.attempts,
                'attempt_token': record.attemptToken,
                'release_deadline_ms': record.releaseDeadlineMs,
                'age_proof': {
                  'source': record.ageProof.source.wireValue,
                  'binding_digest': record.ageProof.bindingDigest,
                  'signal_at_ms': record.ageProof.signalAtMs,
                  'observed_at_ms': record.ageProof.observedAtMs,
                  'max_age_ms': record.ageProof.maxAgeMs,
                  'mac': record.ageProof.mac,
                },
                'rejection': record.rejection?.coreCode,
              },
            )
            .toList(growable: false),
      }),
    ),
  );

  Uint8List _stateEnvelope(Uint8List payload) => _signedJson(
    {'format_version': _formatVersion, 'payload_b64': base64Encode(payload)},
    _integrityKey,
    'state-v1',
  );

  Uint8List _anchorEnvelope(int generation, String digest) => _signedJson(
    {
      'format_version': _formatVersion,
      'generation': generation,
      'state_digest': digest,
    },
    _integrityKey,
    'anchor-v1',
  );

  Uint8List _readStatePayload() {
    final envelope = _decodeSignedJson(
      _stateFile,
      _integrityKey,
      'state-v1',
      'outbox_corrupt',
    );
    _expectKeys(envelope, const {'format_version', 'payload_b64'});
    if (_int(envelope, 'format_version') != _formatVersion) {
      throw const AndroidActivityException('outbox_version_unsupported');
    }
    return base64Decode(_string(envelope, 'payload_b64'));
  }

  Map<String, Object?> _readAnchor() {
    final anchor = _decodeSignedJson(
      _anchorFile,
      _integrityKey,
      'anchor-v1',
      'outbox_anchor_invalid',
    );
    _expectKeys(anchor, const {'format_version', 'generation', 'state_digest'});
    if (_int(anchor, 'format_version') != _formatVersion) {
      throw const AndroidActivityException('outbox_version_unsupported');
    }
    return anchor;
  }

  void _auditCode(String code, Map<String, int> counts) {
    _audit?.call(code, Map<String, int>.unmodifiable(counts));
  }
}

final class DurableActivityOutboxSender {
  DurableActivityOutboxSender(this.store);
  final FileActivityOutboxStore store;

  Future<void> flush(ActivityFixedByteTransport transport) =>
      store.flush(transport);
}

void _validateConstruction(int capacity, List<int> integrityKey) {
  if (capacity < 1 || integrityKey.length < 32) {
    throw const AndroidActivityException('invalid_outbox_configuration');
  }
  if (_sha256Hex(utf8.encode('abc')) !=
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' ||
      _hmac(
            utf8.encode('key'),
            'The quick brown fox jumps over the lazy dog',
          ) !=
          'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8') {
    throw const AndroidActivityException('integrity_primitive_failed');
  }
}

Map<String, Object?> _bindingMap(SyntheticProbeBinding binding) => {
  'device_id': binding.deviceId,
  'probe_id': binding.probeId,
  'event_id_prefix': binding.serverIssuedPrefix,
  'source': binding.source.wireValue,
  'coverage_mode': 'discrete_best_effort',
  'report_interval_ms': binding.reportIntervalMs,
  'expiry_slo_ms': binding.expirySloMs,
  'allowed_kinds': binding.allowedKinds.toList()..sort(),
  'capabilities': binding.capabilities.toList()..sort(),
};

String _bindingDigest(SyntheticProbeBinding binding) =>
    _sha256Hex(utf8.encode(jsonEncode(_bindingMap(binding))));

void _validateFixedWire(
  AndroidActivityEvent event,
  SyntheticProbeBinding binding,
  int sequence,
) {
  final wire = event.toJson();
  _expectKeys(wire, const {
    'contract',
    'schema_version',
    'event_id',
    'device_id',
    'probe_id',
    'origin_sequence',
    'kind',
    'signal_at_ms',
    'ttl_ms',
    'confidence',
    'source',
    'coverage',
    'payload',
  });
  if (wire['contract'] != 'device.activity.v1' ||
      wire['schema_version'] != 1 ||
      wire['event_id'] != '${binding.serverIssuedPrefix}.$sequence' ||
      wire['device_id'] != binding.deviceId ||
      wire['probe_id'] != binding.probeId ||
      wire['origin_sequence'] != sequence ||
      wire['source'] != binding.source.wireValue ||
      !binding.allowedKinds.contains(wire['kind']) ||
      !const {'low', 'medium', 'high'}.contains(wire['confidence'])) {
    throw const AndroidActivityException('source_binding_mismatch');
  }
  final signal = wire['signal_at_ms'];
  final ttl = wire['ttl_ms'];
  if (signal is! int || ttl is! int) {
    throw const AndroidActivityException('outbox_event_bytes_invalid');
  }
  _timestamp(signal);
  _duration(ttl);
  final coverage = wire['coverage'];
  if (coverage is! Map) {
    throw const AndroidActivityException('outbox_event_bytes_invalid');
  }
  final coverageMap = Map<String, Object?>.from(coverage);
  _expectKeys(coverageMap, const {
    'mode',
    'window_start_ms',
    'window_end_ms',
    'expected_report_interval_ms',
  });
  if (coverageMap['mode'] != 'discrete_best_effort' ||
      coverageMap['window_start_ms'] != signal ||
      coverageMap['window_end_ms'] != signal ||
      coverageMap['expected_report_interval_ms'] != binding.reportIntervalMs) {
    throw const AndroidActivityException('outbox_event_bytes_invalid');
  }
  final payload = wire['payload'];
  if (payload is! Map) {
    throw const AndroidActivityException('outbox_event_bytes_invalid');
  }
  final payloadMap = Map<String, Object?>.from(payload);
  switch (wire['kind']) {
    case 'app.category_active':
      _expectKeys(payloadMap, const {'category'});
      if (!const {
        'chat',
        'social',
        'video',
        'reading',
        'work',
        'other',
      }.contains(payloadMap['category'])) {
        throw const AndroidActivityException('outbox_event_bytes_invalid');
      }
    case 'probe.permission_changed':
      _expectKeys(payloadMap, const {'capability', 'available'});
      if (payloadMap['capability'] != 'usage_events' ||
          payloadMap['available'] is! bool) {
        throw const AndroidActivityException('outbox_event_bytes_invalid');
      }
    case 'probe.error':
      _expectKeys(payloadMap, const {'code'});
      if (payloadMap['code'] != 'collection_failed') {
        throw const AndroidActivityException('outbox_event_bytes_invalid');
      }
    default:
      if (payloadMap.isNotEmpty) {
        throw const AndroidActivityException('outbox_event_bytes_invalid');
      }
  }
}

String _ageProofBody(
  String source,
  String bindingDigest,
  int signalAtMs,
  int observedAtMs,
  int maxAgeMs,
) => '$source\n$bindingDigest\n$signalAtMs\n$observedAtMs\n$maxAgeMs';

Uint8List _signedJson(Map<String, Object?> body, List<int> key, String domain) {
  final payload = utf8.encode(jsonEncode(body));
  final bodyB64 = base64Encode(payload);
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'format_version': _formatVersion,
        'body_b64': bodyB64,
        'mac': _hmac(key, '$domain\n$_formatVersion\n$bodyB64'),
      }),
    ),
  );
}

Map<String, Object?> _decodeSignedJson(
  File file,
  List<int> key,
  String domain,
  String errorCode,
) {
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map || decoded.length != 3) {
      throw const FormatException();
    }
    final envelope = Map<String, Object?>.from(decoded);
    final version = envelope['format_version'];
    if (version != _formatVersion) {
      throw const AndroidActivityException('outbox_version_unsupported');
    }
    final bodyB64 = envelope['body_b64'];
    final mac = envelope['mac'];
    if (bodyB64 is! String ||
        mac is! String ||
        !_constantTimeEquals(mac, _hmac(key, '$domain\n$version\n$bodyB64'))) {
      throw const FormatException();
    }
    final body = jsonDecode(utf8.decode(base64Decode(bodyB64)));
    if (body is! Map) throw const FormatException();
    return Map<String, Object?>.from(body);
  } on AndroidActivityException {
    rethrow;
  } catch (_) {
    throw AndroidActivityException(errorCode);
  }
}

String _hmac(List<int> key, String value) =>
    Hmac(sha256, key).convert(utf8.encode(value)).toString();

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
bool _constantTimeEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}

void _replaceFile(File target, Uint8List bytes) {
  target.parent.createSync(recursive: true);
  final suffix = _randomToken();
  final temporary = File('${target.path}.$suffix.tmp');
  final previous = File('${target.path}.$suffix.previous');
  final sink = temporary.openSync(mode: FileMode.writeOnly);
  try {
    sink.writeFromSync(bytes);
    sink.flushSync();
  } finally {
    sink.closeSync();
  }
  try {
    if (target.existsSync()) target.renameSync(previous.path);
    temporary.renameSync(target.path);
    if (previous.existsSync()) previous.deleteSync();
  } catch (_) {
    if (!target.existsSync() && previous.existsSync()) {
      previous.renameSync(target.path);
    }
    if (temporary.existsSync()) temporary.deleteSync();
    rethrow;
  }
}

String _randomToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

void _expectKeys(Map<String, Object?> map, Set<String> expected) {
  if (map.length != expected.length ||
      map.keys.any((key) => !expected.contains(key))) {
    throw const AndroidActivityException('outbox_corrupt');
  }
}

String _string(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String) throw const AndroidActivityException('outbox_corrupt');
  return value;
}

int _int(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) throw const AndroidActivityException('outbox_corrupt');
  return value;
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

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    return left.keys.every(
      (key) => right.containsKey(key) && _deepEquals(left[key], right[key]),
    );
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_deepEquals(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

final class ListEquality<T> {
  const ListEquality();
  bool equals(List<T> left, List<T> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
