import 'package:flutter_test/flutter_test.dart';
import 'package:memex/agent/skills/schedule_aggregation/schedule_aggregation_skill.dart';

void main() {
  group('deriveScheduleCardStatus', () {
    test('keeps newly-created task cards pending when is_completed is absent',
        () {
      expect(
        deriveScheduleCardStatus('task', <String, dynamic>{}),
        'pending',
      );
    });

    test('uses only task is_completed to mark schedule tasks completed', () {
      expect(
        deriveScheduleCardStatus(
          'task',
          <String, dynamic>{'is_completed': true},
        ),
        'completed',
      );
      expect(
        deriveScheduleCardStatus(
          'task',
          <String, dynamic>{'is_completed': 'completed'},
        ),
        'completed',
      );
      expect(
        deriveScheduleCardStatus(
          'task',
          <String, dynamic>{'is_completed': 'false'},
        ),
        'pending',
      );
      expect(
        deriveScheduleCardStatus(
          'task',
          <String, dynamic>{'is_completed': 0},
        ),
        'pending',
      );
    });

    test('does not treat card processing status as task completion', () {
      expect(
        deriveScheduleCardStatus(
          'event',
          <String, dynamic>{'status': 'completed'},
        ),
        'pending',
      );
      expect(
        deriveScheduleCardStatus(
          'task',
          <String, dynamic>{'status': 'completed'},
        ),
        'pending',
      );
    });
  });
}
