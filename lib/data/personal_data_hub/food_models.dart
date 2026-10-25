import 'domain_protocol.dart';

const foodDomain = 'food_entries';

const _meals = {'breakfast', 'lunch', 'dinner', 'snack', 'drink'};
const _inputKinds = {'photo', 'text', 'mixed', 'app'};
const _foodSources = {'model', 'label', 'personal', 'usda'};
const _bases = {'weighed', 'label', 'photo', 'described', 'model_guess'};
const _confidences = {'high', 'medium', 'low'};

class FoodTotals {
  const FoodTotals({
    required this.kcal,
    required this.kcalLow,
    required this.kcalHigh,
    required this.proteinG,
    required this.fatG,
    required this.carbG,
  });

  final double kcal, kcalLow, kcalHigh, proteinG, fatG, carbG;

  static FoodTotals parse(Object? raw) {
    final value = _object(raw, const {
      'kcal',
      'kcal_low',
      'kcal_high',
      'protein_g',
      'fat_g',
      'carb_g',
    });
    final totals = FoodTotals(
      kcal: _number(value['kcal'], min: 0),
      kcalLow: _number(value['kcal_low'], min: 0),
      kcalHigh: _number(value['kcal_high'], min: 0),
      proteinG: _number(value['protein_g'], min: 0),
      fatG: _number(value['fat_g'], min: 0),
      carbG: _number(value['carb_g'], min: 0),
    );
    if (totals.kcalLow > totals.kcalHigh) throw const FormatException();
    return totals;
  }

  static FoodTotals sum(Iterable<FoodTotals> values) {
    final list = values.toList();
    return FoodTotals(
      kcal: _round1(list.fold<double>(0, (sum, item) => sum + item.kcal)),
      kcalLow:
          _round1(list.fold<double>(0, (sum, item) => sum + item.kcalLow)),
      kcalHigh:
          _round1(list.fold<double>(0, (sum, item) => sum + item.kcalHigh)),
      proteinG:
          _round1(list.fold<double>(0, (sum, item) => sum + item.proteinG)),
      fatG: _round1(list.fold<double>(0, (sum, item) => sum + item.fatG)),
      carbG: _round1(list.fold<double>(0, (sum, item) => sum + item.carbG)),
    );
  }

  bool sameAs(FoodTotals other) =>
      kcal == other.kcal &&
      kcalLow == other.kcalLow &&
      kcalHigh == other.kcalHigh &&
      proteinG == other.proteinG &&
      fatG == other.fatG &&
      carbG == other.carbG;

  static const zero = FoodTotals(
    kcal: 0,
    kcalLow: 0,
    kcalHigh: 0,
    proteinG: 0,
    fatG: 0,
    carbG: 0,
  );
}

class FoodItem {
  const FoodItem({
    required this.name,
    required this.foodSource,
    required this.foodId,
    required this.grams,
    required this.gramsLow,
    required this.gramsHigh,
    required this.kcal,
    required this.proteinG,
    required this.fatG,
    required this.carbG,
    required this.basis,
    required this.confidence,
  });

  final String name, foodSource, basis, confidence;
  final String? foodId;
  final double grams, gramsLow, gramsHigh, kcal, proteinG, fatG, carbG;

  static FoodItem parse(Object? raw) {
    final value = _object(raw, const {
      'name',
      'food_ref',
      'grams',
      'grams_low',
      'grams_high',
      'kcal',
      'protein_g',
      'fat_g',
      'carb_g',
      'basis',
      'confidence',
    });
    final reference = _object(value['food_ref'], const {'source', 'id'});
    final name = _text(value['name'], maxLength: 100);
    final source = _enum(value['food_ref'] is Map ? reference['source'] : null,
        _foodSources);
    final id = reference['id'];
    if (id != null && id is! String) throw const FormatException();
    final grams = _number(value['grams'], minExclusive: 0, max: 5000);
    final gramsLow =
        _number(value['grams_low'], minExclusive: 0, max: 5000);
    final gramsHigh =
        _number(value['grams_high'], minExclusive: 0, max: 5000);
    if (gramsLow > grams || grams > gramsHigh) throw const FormatException();
    return FoodItem(
      name: name,
      foodSource: source,
      foodId: id as String?,
      grams: grams,
      gramsLow: gramsLow,
      gramsHigh: gramsHigh,
      kcal: _number(value['kcal'], min: 0, max: 10000),
      proteinG: _number(value['protein_g'], min: 0, max: 10000),
      fatG: _number(value['fat_g'], min: 0, max: 10000),
      carbG: _number(value['carb_g'], min: 0, max: 10000),
      basis: _enum(value['basis'], _bases),
      confidence: _enum(value['confidence'], _confidences),
    );
  }
}

class FoodEntry {
  const FoodEntry({
    required this.id,
    required this.eatenAt,
    required this.localDate,
    required this.meal,
    required this.title,
    required this.note,
    required this.inputKind,
    required this.items,
    required this.totals,
    required this.userCorrected,
    required this.voided,
    this.originDeviceId,
  });

  final String id, localDate, meal, title, note, inputKind;
  final DateTime eatenAt;
  final List<FoodItem> items;
  final FoodTotals totals;
  final bool userCorrected, voided;
  final String? originDeviceId;

  String get confidence {
    if (items.any((item) => item.confidence == 'low')) return 'low';
    if (items.any((item) => item.confidence == 'medium')) return 'medium';
    return 'high';
  }

  static FoodEntry parse(Json record) {
    final id = record['id'];
    if (id is! String ||
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.:-]{0,199}$').firstMatch(id)?.group(0) !=
            id) {
      throw const FormatException();
    }
    final value = _object(record['data'], const {
      'eaten_at',
      'local_date',
      'meal',
      'title',
      'note',
      'input_kind',
      'items',
      'totals',
      'user_corrected',
      'voided',
    });
    final eatenAtText = value['eaten_at'];
    if (eatenAtText is! String || !_validBusinessTime(eatenAtText)) {
      throw const FormatException();
    }
    final eatenAt = DateTime.parse(eatenAtText);
    final localDate = _date(value['local_date']);
    final rawItems = value['items'];
    if (rawItems is! List || rawItems.isEmpty || rawItems.length > 40) {
      throw const FormatException();
    }
    final items = List<FoodItem>.unmodifiable(rawItems.map(FoodItem.parse));
    final totals = FoodTotals.parse(value['totals']);
    if (!totals.sameAs(_totalsForItems(items))) throw const FormatException();
    final corrected = value['user_corrected'], voided = value['voided'];
    if (corrected is! bool || voided is! bool) throw const FormatException();
    String? deviceId;
    final origin = record['origin'];
    if (origin != null) {
      if (origin is! Map) throw const FormatException();
      final rawDeviceId = origin['device_id'];
      if (rawDeviceId != null && rawDeviceId is! String) {
        throw const FormatException();
      }
      deviceId = rawDeviceId as String?;
    }
    return FoodEntry(
      id: id,
      eatenAt: eatenAt,
      localDate: localDate,
      meal: _enum(value['meal'], _meals),
      title: _text(value['title'], maxLength: 200),
      note: _text(value['note'], maxLength: 2000, allowEmpty: true),
      inputKind: _enum(value['input_kind'], _inputKinds),
      items: items,
      totals: totals,
      userCorrected: corrected,
      voided: voided,
      originDeviceId: deviceId,
    );
  }
}

class FoodDaySnapshot {
  const FoodDaySnapshot({
    required this.date,
    this.entries = const [],
    this.totals = FoodTotals.zero,
    this.invalidRecords = 0,
    this.error,
  });

  final String date;
  final List<FoodEntry> entries;
  final FoodTotals totals;
  final int invalidRecords;
  final String? error;
}

String foodDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

FoodTotals _totalsForItems(Iterable<FoodItem> items) {
  final list = items.toList();
  return FoodTotals(
    kcal: _round1(list.fold<double>(0, (sum, item) => sum + item.kcal)),
    kcalLow: _round1(list.fold<double>(
        0, (sum, item) => sum + item.kcal * item.gramsLow / item.grams)),
    kcalHigh: _round1(list.fold<double>(
        0, (sum, item) => sum + item.kcal * item.gramsHigh / item.grams)),
    proteinG:
        _round1(list.fold<double>(0, (sum, item) => sum + item.proteinG)),
    fatG: _round1(list.fold<double>(0, (sum, item) => sum + item.fatG)),
    carbG: _round1(list.fold<double>(0, (sum, item) => sum + item.carbG)),
  );
}

double _round1(num value) => (value * 10).round() / 10;

Json _object(Object? raw, Set<String> keys) {
  if (raw is! Map || raw.keys.any((key) => key is! String)) {
    throw const FormatException();
  }
  final value = Map<String, dynamic>.from(raw);
  if (value.keys.toSet().length != keys.length ||
      !value.keys.toSet().containsAll(keys)) {
    throw const FormatException();
  }
  return value;
}

String _text(Object? raw,
    {required int maxLength, bool allowEmpty = false}) {
  if (raw is! String ||
      raw.length > maxLength ||
      (!allowEmpty && raw.trim().isEmpty)) {
    throw const FormatException();
  }
  return raw;
}

String _enum(Object? raw, Set<String> values) {
  if (raw is! String || !values.contains(raw)) throw const FormatException();
  return raw;
}

double _number(Object? raw,
    {double? min, double? minExclusive, double? max}) {
  if (raw is! num || !raw.isFinite) throw const FormatException();
  final value = raw.toDouble();
  if ((min != null && value < min) ||
      (minExclusive != null && value <= minExclusive) ||
      (max != null && value > max)) {
    throw const FormatException();
  }
  return value;
}

String _date(Object? raw) {
  if (raw is! String) throw const FormatException();
  final match = RegExp(r'^\d{4}-\d{2}-\d{2}$').firstMatch(raw);
  if (match == null || match.group(0) != raw) {
    throw const FormatException();
  }
  final date = DateTime.tryParse('${raw}T00:00:00Z');
  if (date == null || foodDateKey(date) != raw) throw const FormatException();
  return raw;
}

bool _validBusinessTime(String raw) {
  final match = RegExp(
    r'^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{3})?(Z|[+-](\d{2}):(\d{2}))$',
  ).firstMatch(raw);
  if (match == null || match.group(0) != raw) return false;
  try {
    _date(match.group(1));
  } on FormatException {
    return false;
  }
  final hour = int.parse(match.group(2)!);
  final minute = int.parse(match.group(3)!);
  final second = int.parse(match.group(4)!);
  if (hour >= 24 || minute >= 60 || second >= 60) return false;
  if (match.group(5) != 'Z') {
    final offsetHour = int.parse(match.group(6)!);
    final offsetMinute = int.parse(match.group(7)!);
    if (offsetHour > 14 ||
        offsetMinute >= 60 ||
        (offsetHour == 14 && offsetMinute != 0)) {
      return false;
    }
  }
  return DateTime.tryParse(raw) != null;
}
