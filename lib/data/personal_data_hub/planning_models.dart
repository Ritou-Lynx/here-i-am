import 'domain_protocol.dart';

const planningDomains = ['plan_days', 'plan_weeks', 'plan_items'];
const planningQueues = {
  'fixed': '定时事项',
  'deep': '深块',
  'long': '长块',
  'voice': '语音块',
  'extra': '有余力再做',
  'errands': '顺手清单',
};

enum PlanningConnection { unknown, offline, online }

enum PlanningStatusAction { complete, abandon }

extension PlanningStatusValue on PlanningStatusAction {
  String get value => this == PlanningStatusAction.complete ? '完成' : '放弃';
}

class PlanningOperation {
  const PlanningOperation(this.id, this.itemId, this.state, this.reason);
  final String id, itemId, state;
  final String? reason;
  bool get blocksAction => !['accepted', 'duplicate'].contains(state);
  String get label => switch (state) {
        'pending' => '待同步',
        'submitting' => '同步中',
        'accepted' || 'duplicate' => '已接受',
        'rejected' => '未接受，请在电脑端处理',
        'needs_resolution' => '需要拍板，请在电脑端处理',
        'expired' => '请求已过期，请在电脑端处理',
        _ => '同步状态未知',
      };
}

class PlanningItem {
  PlanningItem(Json record) : record = copyJson(record);
  final Json record;
  Json get data => jsonObject(record['data']);
  String get id => record['id'] as String;
  int get revision => record['revision'] as int;
  String get title => data['title'] as String;
  // Never assign an existing area to an unclassified item.
  String get area => data['area'] as String;
  String get status => data['status'] as String;
  String get note => data['note'] as String? ?? '';
  String? get blockKind => data['block_kind'] as String?;
  num? get blocks => data['blocks'] as num?;
  String? get dueDate => data['due_date'] as String?;
  DateTime? get scheduledAt =>
      DateTime.tryParse(data['scheduled_at'] as String? ?? '');
  DateTime? get remindAt =>
      DateTime.tryParse(data['remind_at'] as String? ?? '');
  bool get terminal => ['完成', '放弃', '被替代'].contains(status);
  bool get canChangeStatus => data['replaced_by'] == null && !terminal;
  bool get pending => record['sync_label'] == '未同步';
}

class PlanningDay {
  PlanningDay(Json record) : record = copyJson(record);
  final Json record;
  Json get data => jsonObject(record['data']);
  String get date => data['date'] as String;
  int get version => data['display_version'] as int;
  DateTime get generatedAt => DateTime.parse(data['generated_at'] as String);
  String get changes => data['change_summary'] as String;
  Json get capacity => jsonObject(data['capacity']);
  List<String> queue(String name) =>
      (data['queues'][name] as List).cast<String>();
  List<Json> get decisions =>
      (data['pending_decisions'] as List).map(jsonObject).toList();
  List<Json> get noted => (data['noted'] as List).map(jsonObject).toList();
  DateTime? get lightsOut =>
      DateTime.tryParse(data['lights_out_at'] as String? ?? '');
}

class PlanningWeek {
  PlanningWeek(Json record) : record = copyJson(record);
  final Json record;
  Json get data => jsonObject(record['data']);
  String get key => data['week_key'] as String;
  Json get expected => jsonObject(data['expected_capacity']);
  Json get actual => jsonObject(data['actual_capacity']);
  List<Json> get quotas =>
      (data['area_quotas'] as List).map(jsonObject).toList();
  List<Json> get debt => (data['debt'] as List).map(jsonObject).toList();
  List<Json> get days =>
      (data['daily_capacities'] as List).map(jsonObject).toList();
}

class PlanningSnapshot {
  const PlanningSnapshot(
      {this.day,
      this.week,
      this.items = const {},
      this.operations = const {},
      this.domainErrors = const {},
      this.connection = PlanningConnection.unknown,
      this.statusWritable = false});
  final PlanningDay? day;
  final PlanningWeek? week;
  final Map<String, PlanningItem> items;
  final Map<String, PlanningOperation> operations;
  final Map<String, String> domainErrors;
  final PlanningConnection connection;
  final bool statusWritable;
}

String planningDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String planningWeekKey(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  final thursday = day.add(Duration(days: DateTime.thursday - day.weekday));
  final jan4 = DateTime.utc(thursday.year, 1, 4);
  final first = jan4.add(Duration(days: DateTime.thursday - jan4.weekday));
  final week = 1 + thursday.difference(first).inDays ~/ 7;
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}
