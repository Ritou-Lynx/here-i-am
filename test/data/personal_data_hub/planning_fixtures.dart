import 'package:memex/data/personal_data_hub/domain_protocol.dart';

const planningTestBinding = DomainBinding(
    coreInstanceId: 'planning-core',
    principalId: 'planning-phone',
    generation: 1,
    installationId: 'planning-install');
final planningTestNow = DateTime.utc(2026, 10, 5, 8);
Json planningItem(String id,
        {String title = '合成事项',
        String area = '未归类',
        String status = '待办',
        String? remindAt}) =>
    {
      'id': id,
      'domain': 'plan_items',
      'revision': 1,
      'core_instance_id': 'planning-core',
      'data': {
        'title': title,
        'area': area,
        'status': status,
        'level': '行动',
        'parent_id': null,
        'depends_on': <String>[],
        'replaced_by': null,
        'block_kind': '深块',
        'blocks': 1,
        'scheduled_at': null,
        'planned_date': '2026-10-05',
        'due_date': null,
        'completed_at': status == '完成' ? '2026-10-05T08:00:00.000Z' : null,
        'energy': null,
        'defer_count': 0,
        'source': '手打',
        'source_url': null,
        'note': '',
        'remind_at': remindAt
      },
    };
Json planningDay(
        {int version = 1,
        List<String> queue = const ['b', 'a'],
        String date = '2026-10-05'}) =>
    {
      'id': 'day',
      'domain': 'plan_days',
      'revision': version,
      'core_instance_id': 'planning-core',
      'data': {
        'date': date,
        'display_version': version,
        'generated_at': '2026-10-05T07:00:00.000Z',
        'change_summary': '先做重要的事',
        'pending_decisions': [
          {'item_id': 'a', 'reason': '容量不足', 'suggestion': '留到明天'}
        ],
        'capacity': {'deep': 2, 'long': null, 'voice': 1},
        'queues': {
          'fixed': <String>[],
          'deep': queue,
          'long': <String>[],
          'voice': <String>[],
          'extra': <String>[],
          'errands': <String>[]
        },
        'noted': [
          {'capture_id': null, 'text': '合成记下了'}
        ],
        'lights_out_at': '2026-10-05T15:00:00.000Z',
      },
    };
Json planningWeek() => {
      'id': 'week',
      'domain': 'plan_weeks',
      'revision': 1,
      'core_instance_id': 'planning-core',
      'data': {
        'week_key': '2026-W41',
        'expected_capacity': {'deep': 10, 'long': 2, 'voice': 3},
        'actual_capacity': {'deep': 2, 'long': null, 'voice': 1},
        'daily_capacities': <Json>[],
        'area_quotas': [
          {
            'area': '未归类',
            'block_kind': '深块',
            'minimum': 2,
            'target': 4,
            'maximum': null,
            'completed': 1,
            'remaining_scheduled': 2,
            'status': '落后'
          }
        ],
        'debt': [
          {
            'area': '未归类',
            'block_kind': '深块',
            'from_week': '2026-W40',
            'amount': 1,
            'rolled_weeks': 1
          }
        ],
      },
    };
Json planningPage(List<Json> records, [String cursor = 'cursor-1']) => {
      'records': records,
      'next_cursor': cursor,
      'policy_version': DomainPolicy.version,
    };
Json planningReceipt(String op, String id,
        {String outcome = 'accepted', int revision = 2}) =>
    {
      'domain_protocol_version': 1,
      'domain': 'plan_items',
      'op_id': op,
      'outcome': outcome,
      'reason': outcome == 'duplicate' ? 'idempotent_replay' : null,
      'receipt': {
        'receipt_id': 'receipt-$op',
        'core_instance_id': 'planning-core',
        'authority_mode': 'single_host',
        'epoch': null,
        'domain': 'plan_items',
        'accepted_op_id': op,
        'principal_id': 'planning-phone',
        'accepted_at': '2026-10-05T08:00:00.000Z',
        'policy_version': DomainPolicy.version,
        'targets': [
          {'id': id, 'revision': revision}
        ],
        'change_sequences': [revision],
        'receipt_auth': List.filled(64, 'a').join()
      },
    };
