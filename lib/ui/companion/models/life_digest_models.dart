/// Models and calendar helpers for the read-only Life Digest & Long-Term
/// Profile viewer (`life_digest` MCP tool).
library;

enum LifeDigestTab {
  day('日'),
  week('周'),
  month('月'),
  todos('待办'),
  profile('档案');

  const LifeDigestTab(this.label);
  final String label;
}

enum LifeDigestFailureKind {
  notConnected,
  offline,
  unsupportedPeriod,
  error,
}

class LifeDigestFailure {
  const LifeDigestFailure({
    required this.kind,
    required this.message,
  });

  final LifeDigestFailureKind kind;
  final String message;
}

/// Ordered category keys and display labels for the long-term profile.
const List<String> profileCategoryOrder = <String>[
  'rhythm',
  'work_study',
  'health',
  'preferences',
  'us',
];

const Map<String, String> profileCategoryLabels = <String, String>{
  'rhythm': '基本与生活节奏',
  'work_study': '工作与学习主线',
  'health': '身体与健康关注',
  'preferences': '兴趣与偏好',
  'us': '我们之间',
};

String profileCategoryLabel(String key) =>
    profileCategoryLabels[key] ?? key;

/// Formats a local calendar date as `YYYY-MM-DD`.
String formatIsoDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Formats a local calendar month as `YYYY-MM`.
String formatIsoMonth(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$y-$m';
}

/// ISO-8601 week identifier (`YYYY-Www`).
class IsoWeek implements Comparable<IsoWeek> {
  const IsoWeek(this.year, this.week);

  final int year;
  final int week;

  factory IsoWeek.fromDate(DateTime date) {
    final local = DateTime(date.year, date.month, date.day);
    // ISO week belongs to the year containing its Thursday.
    final thursday = DateTime(
      local.year,
      local.month,
      local.day + (4 - local.weekday),
    );
    final jan1 = DateTime(thursday.year, 1, 1);
    final dayOfYear = DateTime.utc(thursday.year, thursday.month, thursday.day)
        .difference(DateTime.utc(jan1.year, jan1.month, jan1.day))
        .inDays;
    final weekNumber = 1 + (dayOfYear ~/ 7);
    return IsoWeek(thursday.year, weekNumber);
  }

  /// Monday of this ISO week.
  DateTime get monday {
    final jan4 = DateTime(year, 1, 4);
    final week1Monday = DateTime(year, 1, 4 - (jan4.weekday - 1));
    return DateTime(
      week1Monday.year,
      week1Monday.month,
      week1Monday.day + (week - 1) * 7,
    );
  }

  /// Sunday of this ISO week.
  DateTime get sunday {
    final start = monday;
    return DateTime(start.year, start.month, start.day + 6);
  }

  IsoWeek step(int deltaWeeks) {
    final start = monday;
    return IsoWeek.fromDate(
      DateTime(start.year, start.month, start.day + deltaWeeks * 7),
    );
  }

  String get formatted =>
      '${year.toString().padLeft(4, '0')}-W${week.toString().padLeft(2, '0')}';

  String get fallbackDateRange =>
      '${formatIsoDate(monday)} ~ ${formatIsoDate(sunday)}';

  @override
  int compareTo(IsoWeek other) {
    final y = year.compareTo(other.year);
    return y != 0 ? y : week.compareTo(other.week);
  }

  @override
  bool operator ==(Object other) =>
      other is IsoWeek && other.year == year && other.week == week;

  @override
  int get hashCode => Object.hash(year, week);

  @override
  String toString() => formatted;
}

class DigestBulletItem {
  const DigestBulletItem({
    required this.text,
    this.sources = const [],
    this.level,
  });

  final String text;
  final List<String> sources;
  final String? level;

  bool get isWarn {
    final normalized = level?.toLowerCase();
    return normalized == 'warn' ||
        normalized == 'warning' ||
        normalized == 'high' ||
        normalized == 'alert';
  }

  factory DigestBulletItem.fromJson(Object? raw) {
    if (raw is String) {
      return DigestBulletItem(text: raw.trim());
    }
    if (raw is Map) {
      return DigestBulletItem(
        text: _asTrimmedString(raw['text']) ?? '',
        sources: _asStringList(raw['sources']),
        level: _asTrimmedString(raw['level']),
      );
    }
    return const DigestBulletItem(text: '');
  }
}

class DigestMorningBroadcast {
  const DigestMorningBroadcast({
    required this.text,
    this.weather,
  });

  final String text;
  final String? weather;

  bool get isEmpty => text.isEmpty && (weather == null || weather!.isEmpty);

  factory DigestMorningBroadcast.fromJson(Object? raw) {
    if (raw is String) {
      return DigestMorningBroadcast(text: raw.trim());
    }
    if (raw is Map) {
      return DigestMorningBroadcast(
        text: _asTrimmedString(raw['text']) ?? '',
        weather: _asTrimmedString(raw['weather']),
      );
    }
    return const DigestMorningBroadcast(text: '');
  }
}

class LifeDigestTodoItem {
  const LifeDigestTodoItem({
    required this.id,
    required this.text,
    this.quote,
    this.source,
    this.firstSeen,
    this.daysOpen = 0,
  });

  final String id;
  final String text;
  final String? quote;
  final String? source;
  final String? firstSeen;
  final int daysOpen;

  bool get isOverdue => daysOpen >= 7;

  factory LifeDigestTodoItem.fromJson(Object? raw) {
    if (raw is String) {
      return LifeDigestTodoItem(id: '', text: raw.trim());
    }
    if (raw is Map) {
      return LifeDigestTodoItem(
        id: _asTrimmedString(raw['id']) ?? '',
        text: _asTrimmedString(raw['text']) ?? '',
        quote: _asTrimmedString(raw['quote']),
        source: _asTrimmedString(raw['source']),
        firstSeen: _asTrimmedString(raw['first_seen']),
        daysOpen: _asInt(raw['days_open']) ?? 0,
      );
    }
    return const LifeDigestTodoItem(id: '', text: '');
  }
}

class DayDigestData {
  const DayDigestData({
    required this.available,
    required this.date,
    this.stage,
    this.stageLabel,
    this.generatedAt,
    this.morning,
    this.headline,
    this.yourDay = const [],
    this.us = const [],
    this.anomalies = const [],
    this.todos = const [],
    this.omitted = const [],
    this.note,
    this.failed = false,
  });

  final bool available;
  final String date;
  final String? stage;
  final String? stageLabel;
  final String? generatedAt;
  final DigestMorningBroadcast? morning;
  final String? headline;
  final List<DigestBulletItem> yourDay;
  final List<DigestBulletItem> us;
  final List<DigestBulletItem> anomalies;
  final List<LifeDigestTodoItem> todos;
  final List<String> omitted;
  final String? note;
  final bool failed;

  String? get displayStageLabel {
    if (stageLabel != null && stageLabel!.isNotEmpty) return stageLabel;
    return switch (stage?.toLowerCase()) {
      'morning' => '晨间版',
      'midday' || 'daytime' || 'noon' => '白天版',
      'final' || 'evening' || 'night' => '定稿',
      final other? when other.isNotEmpty => other,
      _ => null,
    };
  }

  bool get hasBodyContent =>
      (morning != null && !morning!.isEmpty) ||
      (headline != null && headline!.isNotEmpty) ||
      yourDay.isNotEmpty ||
      us.isNotEmpty ||
      anomalies.isNotEmpty;

  factory DayDigestData.fromJson(
    Map<String, dynamic> json, {
    String fallbackDate = '',
  }) {
    final morningRaw = json['morning'];
    final parsedMorning =
        morningRaw == null ? null : DigestMorningBroadcast.fromJson(morningRaw);
    return DayDigestData(
      available: _asBool(json['available']) ?? false,
      date: _asTrimmedString(json['date']) ?? fallbackDate,
      stage: _asTrimmedString(json['stage']),
      stageLabel: _asTrimmedString(json['stage_label']),
      generatedAt: _asTrimmedString(json['generated_at']),
      morning: (parsedMorning != null && !parsedMorning.isEmpty)
          ? parsedMorning
          : null,
      headline: _asTrimmedString(json['headline']),
      yourDay: _parseBullets(json['your_day']),
      us: _parseBullets(json['us']),
      anomalies: _parseBullets(json['anomalies']),
      todos: _parseTodos(json['todos']),
      omitted: _asStringList(json['omitted']),
      note: _asTrimmedString(json['note']),
      failed: _asBool(json['failed']) ?? false,
    );
  }
}

class WeekDigestData {
  const WeekDigestData({
    required this.available,
    required this.week,
    this.dateRange,
    this.generatedAt,
    this.sourceDays = const [],
    this.headline,
    this.highlights = const [],
    this.us = const [],
    this.moodRhythm,
    this.todosSummary,
    this.omitted = const [],
    this.note,
    this.failed = false,
  });

  final bool available;
  final String week;
  final String? dateRange;
  final String? generatedAt;
  final List<String> sourceDays;
  final String? headline;
  final List<DigestBulletItem> highlights;
  final List<DigestBulletItem> us;
  final String? moodRhythm;
  final String? todosSummary;
  final List<String> omitted;
  final String? note;
  final bool failed;

  bool get hasBodyContent =>
      (headline != null && headline!.isNotEmpty) ||
      highlights.isNotEmpty ||
      us.isNotEmpty ||
      (moodRhythm != null && moodRhythm!.isNotEmpty) ||
      (todosSummary != null && todosSummary!.isNotEmpty);

  factory WeekDigestData.fromJson(
    Map<String, dynamic> json, {
    String fallbackWeek = '',
  }) {
    return WeekDigestData(
      available: _asBool(json['available']) ?? false,
      week: _asTrimmedString(json['week']) ?? fallbackWeek,
      dateRange: _asDateRange(json['date_range']),
      generatedAt: _asTrimmedString(json['generated_at']),
      sourceDays: _asStringList(json['source_days']),
      headline: _asTrimmedString(json['headline']),
      highlights: _parseBullets(json['highlights']),
      us: _parseBullets(json['us']),
      moodRhythm: _asFlexibleText(json['mood_rhythm']),
      todosSummary: _asFlexibleText(json['todos_summary']),
      omitted: _asStringList(json['omitted']),
      note: _asTrimmedString(json['note']),
      failed: _asBool(json['failed']) ?? false,
    );
  }
}

class MonthDigestData {
  const MonthDigestData({
    required this.available,
    required this.month,
    this.dateRange,
    this.generatedAt,
    this.sourceWeeks = const [],
    this.sourceDays = const [],
    this.headline,
    this.themes = const [],
    this.us = const [],
    this.shifts = const [],
    this.milestones = const [],
    this.omitted = const [],
    this.note,
    this.failed = false,
  });

  final bool available;
  final String month;
  final String? dateRange;
  final String? generatedAt;
  final List<String> sourceWeeks;
  final List<String> sourceDays;
  final String? headline;
  final List<DigestBulletItem> themes;
  final List<DigestBulletItem> us;
  final List<DigestBulletItem> shifts;
  final List<DigestBulletItem> milestones;
  final List<String> omitted;
  final String? note;
  final bool failed;

  bool get hasBodyContent =>
      (headline != null && headline!.isNotEmpty) ||
      themes.isNotEmpty ||
      us.isNotEmpty ||
      shifts.isNotEmpty ||
      milestones.isNotEmpty;

  factory MonthDigestData.fromJson(
    Map<String, dynamic> json, {
    String fallbackMonth = '',
  }) {
    return MonthDigestData(
      available: _asBool(json['available']) ?? false,
      month: _asTrimmedString(json['month']) ?? fallbackMonth,
      dateRange: _asDateRange(json['date_range']),
      generatedAt: _asTrimmedString(json['generated_at']),
      sourceWeeks: _asStringList(json['source_weeks']),
      sourceDays: _asStringList(json['source_days']),
      headline: _asTrimmedString(json['headline']),
      themes: _parseBullets(json['themes']),
      us: _parseBullets(json['us']),
      shifts: _parseBullets(json['shifts']),
      milestones: _parseBullets(json['milestones']),
      omitted: _asStringList(json['omitted']),
      note: _asTrimmedString(json['note']),
      failed: _asBool(json['failed']) ?? false,
    );
  }
}

class LifeDigestTodosData {
  const LifeDigestTodosData({
    this.todos = const [],
    this.today,
    this.note,
  });

  final List<LifeDigestTodoItem> todos;
  final String? today;
  final String? note;

  factory LifeDigestTodosData.fromJson(Map<String, dynamic> json) {
    return LifeDigestTodosData(
      todos: _parseTodos(json['todos']),
      today: _asTrimmedString(json['today']),
      note: _asTrimmedString(json['note']),
    );
  }
}

class ProfileItem {
  const ProfileItem({
    required this.id,
    required this.category,
    required this.text,
    this.status = 'auto',
    this.sources = const [],
    this.updatedAt,
  });

  final String id;
  final String category;
  final String text;
  final String status;
  final List<String> sources;
  final String? updatedAt;

  bool get isPinned => status.toLowerCase() == 'pinned';

  factory ProfileItem.fromJson(
    Object? raw, {
    String fallbackCategory = '',
  }) {
    if (raw is String) {
      return ProfileItem(
        id: '',
        category: fallbackCategory,
        text: raw.trim(),
      );
    }
    if (raw is Map) {
      return ProfileItem(
        id: _asTrimmedString(raw['id']) ?? '',
        category: _asTrimmedString(raw['category']) ?? fallbackCategory,
        text: _asTrimmedString(raw['text']) ?? '',
        status: _asTrimmedString(raw['status']) ?? 'auto',
        sources: _asStringList(raw['sources']),
        updatedAt: _asTrimmedString(raw['updated_at']),
      );
    }
    return ProfileItem(id: '', category: fallbackCategory, text: '');
  }
}

class LongTermProfileData {
  const LongTermProfileData({
    required this.available,
    this.updatedAt,
    this.generatedAt,
    this.sourceMonths = const [],
    this.sourceWeeks = const [],
    this.categories = const {},
    this.items = const [],
    this.note,
    this.failed = false,
  });

  final bool available;
  final String? updatedAt;
  final String? generatedAt;
  final List<String> sourceMonths;
  final List<String> sourceWeeks;
  final Map<String, List<ProfileItem>> categories;
  final List<ProfileItem> items;
  final String? note;
  final bool failed;

  /// Non-empty categories ordered by [profileCategoryOrder], followed by any
  /// additional categories returned by the server.
  List<MapEntry<String, List<ProfileItem>>> get orderedNonEmptyCategories {
    final buckets = <String, List<ProfileItem>>{};

    void addItem(String category, ProfileItem item) {
      if (item.text.isEmpty) return;
      final list = buckets.putIfAbsent(category, () => <ProfileItem>[]);
      if (item.id.isNotEmpty && list.any((e) => e.id == item.id)) return;
      list.add(item);
    }

    for (final entry in categories.entries) {
      for (final item in entry.value) {
        addItem(entry.key, item);
      }
    }
    for (final item in items) {
      final key = item.category.isNotEmpty ? item.category : 'other';
      addItem(key, item);
    }

    final ordered = <MapEntry<String, List<ProfileItem>>>[];
    final visited = <String>{};
    for (final key in profileCategoryOrder) {
      final list = buckets[key];
      if (list != null && list.isNotEmpty) {
        ordered.add(MapEntry(key, List.unmodifiable(list)));
        visited.add(key);
      }
    }
    for (final entry in buckets.entries) {
      if (visited.contains(entry.key) || entry.value.isEmpty) continue;
      ordered.add(MapEntry(entry.key, List.unmodifiable(entry.value)));
    }
    return ordered;
  }

  bool get hasAnyItems => orderedNonEmptyCategories.isNotEmpty;

  factory LongTermProfileData.fromJson(Map<String, dynamic> json) {
    final parsedCategories = <String, List<ProfileItem>>{};
    final rawCategories = json['categories'];
    if (rawCategories is Map) {
      for (final entry in rawCategories.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is List) {
          parsedCategories[key] = value
              .map((item) => ProfileItem.fromJson(item, fallbackCategory: key))
              .where((item) => item.text.isNotEmpty)
              .toList();
        }
      }
    }

    final parsedItems = <ProfileItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        final item = ProfileItem.fromJson(raw);
        if (item.text.isNotEmpty) parsedItems.add(item);
      }
    }

    return LongTermProfileData(
      available: _asBool(json['available']) ??
          (parsedCategories.values.any((l) => l.isNotEmpty) ||
              parsedItems.isNotEmpty),
      updatedAt: _asTrimmedString(json['updated_at']),
      generatedAt: _asTrimmedString(json['generated_at']),
      sourceMonths: _asStringList(json['source_months']),
      sourceWeeks: _asStringList(json['source_weeks']),
      categories: parsedCategories,
      items: parsedItems,
      note: _asTrimmedString(json['note']),
      failed: _asBool(json['failed']) ?? false,
    );
  }
}

// ---------------------------------------------------------------------------
// Defensive JSON parsing helpers
// ---------------------------------------------------------------------------

String? _asTrimmedString(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

bool? _asBool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim());
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is List) {
    return value
        .map((e) => _asTrimmedString(e))
        .whereType<String>()
        .toList();
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? const [] : <String>[trimmed];
  }
  return const [];
}

String? _asDateRange(Object? value) {
  if (value == null) return null;
  if (value is String) return _asTrimmedString(value);
  if (value is List && value.length >= 2) {
    final start = _asTrimmedString(value.first);
    final end = _asTrimmedString(value.last);
    if (start != null && end != null) return '$start ~ $end';
  }
  if (value is Map) {
    final start = _asTrimmedString(value['start'] ?? value['from']);
    final end = _asTrimmedString(value['end'] ?? value['to']);
    if (start != null && end != null) return '$start ~ $end';
  }
  return null;
}

String? _asFlexibleText(Object? value) {
  if (value == null) return null;
  if (value is String) return _asTrimmedString(value);
  if (value is List) {
    final parts = value
        .map((e) {
          if (e is Map) return _asTrimmedString(e['text']);
          return _asTrimmedString(e);
        })
        .whereType<String>()
        .toList();
    return parts.isEmpty ? null : parts.join('\n');
  }
  if (value is Map) {
    return _asTrimmedString(value['text'] ?? value['summary']);
  }
  return _asTrimmedString(value);
}

List<DigestBulletItem> _parseBullets(Object? value) {
  if (value is! List) return const [];
  return value
      .map(DigestBulletItem.fromJson)
      .where((item) => item.text.isNotEmpty)
      .toList();
}

List<LifeDigestTodoItem> _parseTodos(Object? value) {
  if (value is! List) return const [];
  return value
      .map(LifeDigestTodoItem.fromJson)
      .where((item) => item.text.isNotEmpty)
      .toList();
}
