/// Immutable identity for a single voice-conversation turn.
///
/// Modeled after the Cove GPT-Live identity protocol: every async event (TTS
/// chunk, ASR result, model stream delta, barge-in callback, timer) carries a
/// [VoiceTurnIdentity] so stale results from a previous generation can be
/// rejected before mutating current state.
///
/// Four layers, outer-to-inner:
/// - [callSessionId] — one continuous voice session (e.g. one CallKit call).
/// - [turnId] — one user utterance (one ASR endpoint → one reply).
/// - [turnSequence] — monotonically increasing int within a call session.
/// - [generationId] — one generation attempt for this turn (retries or
///   fast-candidate fallbacks produce new generation ids).
///
/// Usage:
/// ```dart
/// final id = VoiceTurnIdentity.newTurn(callId: 'call_01');
/// // ... pass to TTS / model / barge-in ...
/// if (!id.isCurrent(activeIdentity)) return; // stale
/// ```
class VoiceTurnIdentity {
  const VoiceTurnIdentity({
    required this.callSessionId,
    required this.turnId,
    required this.turnSequence,
    required this.generationId,
  });

  /// One continuous voice session.
  final String callSessionId;

  /// A single user utterance.
  final String turnId;

  /// Monotonically increasing turn number within a call session.
  final int turnSequence;

  /// One generation attempt for this turn.
  final String generationId;

  /// Create a new turn identity within [callSessionId].
  factory VoiceTurnIdentity.newTurn({
    required String callSessionId,
    required int turnSequence,
  }) {
    return VoiceTurnIdentity(
      callSessionId: callSessionId,
      turnId: 'turn_${turnSequence.toString().padLeft(2, '0')}',
      turnSequence: turnSequence,
      generationId: 'gen_${turnSequence.toString().padLeft(2, '0')}_a',
    );
  }

  /// Create a new generation for the same turn (e.g. fast-candidate fallback).
  VoiceTurnIdentity newGeneration({String? suffix}) {
    final base = 'gen_${turnSequence.toString().padLeft(2, '0')}';
    final gen = suffix != null ? '${base}_$suffix' : '${base}_b';
    return VoiceTurnIdentity(
      callSessionId: callSessionId,
      turnId: turnId,
      turnSequence: turnSequence,
      generationId: gen,
    );
  }

  /// Returns true if [active] matches this identity on all four layers.
  ///
  /// Pass the current active identity and any event-carrying identity. If any
  /// layer differs, the event is stale and must be discarded.
  bool isCurrent(VoiceTurnIdentity? active) {
    if (active == null) return false;
    return callSessionId == active.callSessionId &&
        turnId == active.turnId &&
        turnSequence == active.turnSequence &&
        generationId == active.generationId;
  }

  /// Same call session (used for coarse checks that don't need turn-level).
  bool sameCall(VoiceTurnIdentity? other) {
    if (other == null) return false;
    return callSessionId == other.callSessionId;
  }

  /// Same turn (same user utterance), possibly different generation.
  bool sameTurn(VoiceTurnIdentity? other) {
    if (other == null) return false;
    return callSessionId == other.callSessionId &&
        turnId == other.turnId &&
        turnSequence == other.turnSequence;
  }

  @override
  String toString() =>
      'VoiceTurnIdentity($callSessionId/$turnId/$generationId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoiceTurnIdentity &&
          callSessionId == other.callSessionId &&
          turnId == other.turnId &&
          turnSequence == other.turnSequence &&
          generationId == other.generationId;

  @override
  int get hashCode => Object.hash(
        callSessionId,
        turnId,
        turnSequence,
        generationId,
      );
}

/// Generates monotonically increasing turn sequences for a call session.
class VoiceTurnSequencer {
  VoiceTurnSequencer(this.callSessionId);

  final String callSessionId;
  int _turnSequence = 0;

  /// The current turn sequence (last issued).
  int get currentSequence => _turnSequence;

  /// Issue the next turn identity.
  VoiceTurnIdentity nextTurn() {
    _turnSequence++;
    return VoiceTurnIdentity.newTurn(
      callSessionId: callSessionId,
      turnSequence: _turnSequence,
    );
  }

  /// Issue the next turn identity with an explicit sequence number (e.g.
  /// after recovering from a crash where the sequence was persisted).
  VoiceTurnIdentity turnAt(int sequence) {
    if (sequence > _turnSequence) _turnSequence = sequence;
    return VoiceTurnIdentity.newTurn(
      callSessionId: callSessionId,
      turnSequence: sequence,
    );
  }
}