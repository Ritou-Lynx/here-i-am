import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/voice_turn_identity.dart';

void main() {
  group('VoiceTurnIdentity', () {
    test('isCurrent returns true for identical identity', () {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      expect(id.isCurrent(id), isTrue);
    });

    test('isCurrent returns false for null', () {
      const id = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      expect(id.isCurrent(null), isFalse);
    });

    test('isCurrent returns false for different generation', () {
      const id1 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      const id2 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_b',
      );
      expect(id1.isCurrent(id2), isFalse);
    });

    test('isCurrent returns false for different turn', () {
      const id1 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      const id2 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_02',
        turnSequence: 2,
        generationId: 'gen_02_a',
      );
      expect(id1.isCurrent(id2), isFalse);
    });

    test('isCurrent returns false for different call session', () {
      const id1 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      const id2 = VoiceTurnIdentity(
        callSessionId: 'call_02',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      expect(id1.isCurrent(id2), isFalse);
    });

    test('sameCall returns true for same call session', () {
      const id1 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      const id2 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_02',
        turnSequence: 2,
        generationId: 'gen_02_a',
      );
      expect(id1.sameCall(id2), isTrue);
    });

    test('sameTurn returns true for same turn, different generation', () {
      const id1 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      const id2 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_b',
      );
      expect(id1.sameTurn(id2), isTrue);
    });

    test('newGeneration produces new generation id for same turn', () {
      final id = VoiceTurnIdentity.newTurn(
        callSessionId: 'call_01',
        turnSequence: 3,
      );
      final next = id.newGeneration();
      expect(next.callSessionId, id.callSessionId);
      expect(next.turnId, id.turnId);
      expect(next.turnSequence, id.turnSequence);
      expect(next.generationId, isNot(id.generationId));
    });

    test('equality and hashCode', () {
      const id1 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      const id2 = VoiceTurnIdentity(
        callSessionId: 'call_01',
        turnId: 'turn_01',
        turnSequence: 1,
        generationId: 'gen_01_a',
      );
      expect(id1 == id2, isTrue);
      expect(id1.hashCode == id2.hashCode, isTrue);
    });
  });

  group('VoiceTurnSequencer', () {
    test('nextTurn produces monotonically increasing sequences', () {
      final seq = VoiceTurnSequencer('call_01');
      final t1 = seq.nextTurn();
      final t2 = seq.nextTurn();
      final t3 = seq.nextTurn();
      expect(t1.turnSequence, 1);
      expect(t2.turnSequence, 2);
      expect(t3.turnSequence, 3);
      expect(t1.callSessionId, 'call_01');
      expect(t2.callSessionId, 'call_01');
    });

    test('nextTurn produces unique turn ids', () {
      final seq = VoiceTurnSequencer('call_01');
      final t1 = seq.nextTurn();
      final t2 = seq.nextTurn();
      expect(t1.turnId, isNot(t2.turnId));
    });

    test('turnAt advances sequence', () {
      final seq = VoiceTurnSequencer('call_01');
      seq.nextTurn(); // seq=1
      seq.nextTurn(); // seq=2
      final t5 = seq.turnAt(5);
      expect(t5.turnSequence, 5);
      expect(seq.currentSequence, 5);
    });

    test('turnAt does not decrease sequence', () {
      final seq = VoiceTurnSequencer('call_01');
      seq.nextTurn(); // seq=1
      seq.nextTurn(); // seq=2
      final t1 = seq.turnAt(1);
      expect(t1.turnSequence, 1);
      expect(seq.currentSequence, 2);
    });

    test('stale turn from previous sequencer is not current', () {
      final seq1 = VoiceTurnSequencer('call_01');
      final t1 = seq1.nextTurn();
      final seq2 = VoiceTurnSequencer('call_02');
      final t2 = seq2.nextTurn();
      expect(t1.isCurrent(t2), isFalse);
      expect(t1.sameCall(t2), isFalse);
    });
  });
}