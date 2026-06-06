import 'package:uuid/uuid.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/db/daos/ai_finance_dao.dart';
import 'package:drift/drift.dart';
import 'package:synchronized/synchronized.dart';

class AiFinanceRecordResult {
  const AiFinanceRecordResult({
    required this.id,
    required this.created,
    this.duplicateOf,
  });

  final String id;
  final bool created;
  final String? duplicateOf;
}

class AiFinanceService {
  final AppDatabase _db;
  late final AiFinanceDao _dao = AiFinanceDao(_db);

  AiFinanceService({required AppDatabase db}) : _db = db;

  static const _uuid = Uuid();
  static final Lock _recordLock = Lock();
  static const _duplicateWindow = Duration(hours: 36);
  static const _bareAmountDuplicateWindow = Duration(minutes: 1);

  Future<String> recordEntry({
    required String characterId,
    required String entryType,
    required double totalAmount,
    required double aiAmount,
    double? contributionRatio,
    String? myContributionDesc,
    String? aiContributionDesc,
    String? purpose,
    String? linkedFactId,
    String? notes,
  }) async {
    final result = await recordEntryWithResult(
      characterId: characterId,
      entryType: entryType,
      totalAmount: totalAmount,
      aiAmount: aiAmount,
      contributionRatio: contributionRatio,
      myContributionDesc: myContributionDesc,
      aiContributionDesc: aiContributionDesc,
      purpose: purpose,
      linkedFactId: linkedFactId,
      notes: notes,
    );
    return result.id;
  }

  Future<AiFinanceRecordResult> recordEntryWithResult({
    required String characterId,
    required String entryType,
    required double totalAmount,
    required double aiAmount,
    double? contributionRatio,
    String? myContributionDesc,
    String? aiContributionDesc,
    String? purpose,
    String? linkedFactId,
    String? notes,
  }) async {
    return _recordLock.synchronized(() async {
      final id = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final normalizedEntryType = entryType.trim().toLowerCase();
      final duplicate = await _findDuplicateEntry(
        entryType: normalizedEntryType,
        totalAmount: totalAmount,
        aiAmount: aiAmount,
        contributionRatio: contributionRatio,
        myContributionDesc: myContributionDesc,
        aiContributionDesc: aiContributionDesc,
        purpose: purpose,
        linkedFactId: linkedFactId,
        notes: notes,
        nowEpoch: now,
      );
      if (duplicate != null) {
        return AiFinanceRecordResult(
          id: duplicate.id,
          created: false,
          duplicateOf: duplicate.id,
        );
      }

      await _dao.insertEntry(AiFinanceLedgerCompanion.insert(
        id: id,
        characterId: characterId,
        entryType: normalizedEntryType,
        totalAmount: totalAmount,
        aiAmount: aiAmount,
        contributionRatio: Value(contributionRatio),
        myContributionDesc: Value(_cleanNullableText(myContributionDesc)),
        aiContributionDesc: Value(_cleanNullableText(aiContributionDesc)),
        purpose: Value(_cleanNullableText(purpose)),
        linkedFactId: Value(_cleanNullableText(linkedFactId)),
        recordedAt: now,
        notes: Value(_cleanNullableText(notes)),
      ));
      return AiFinanceRecordResult(id: id, created: true);
    });
  }

  /// Returns a structured summary for the shared AI ledger.
  Future<Map<String, dynamic>> getSummary({
    String? month, // 'YYYY-MM', if null returns all-time
  }) async {
    int? sinceEpoch;
    int? untilEpoch;
    if (month != null) {
      final parts = month.split('-');
      final year = int.parse(parts[0]);
      final mon = int.parse(parts[1]);
      final start = DateTime(year, mon);
      final end = DateTime(year, mon + 1);
      sinceEpoch = start.millisecondsSinceEpoch ~/ 1000;
      untilEpoch = end.millisecondsSinceEpoch ~/ 1000 - 1;
    }

    final periodRows = _dedupeLedgerRows(await _dao.getSharedEntriesForPeriod(
      sinceEpoch: sinceEpoch,
      untilEpoch: untilEpoch,
    ));
    final sums = _sumRowsByType(periodRows);

    final income = sums['income'] ?? 0.0;
    final cost = sums['cost'] ?? 0.0;
    final loan = sums['loan'] ?? 0.0;
    final repayment = sums['repayment'] ?? 0.0;

    // balance = income + repayment - cost - loan
    final balance = income + repayment - cost - loan;

    // all-time totals for debt calculation
    final allSums = month != null
        ? _sumRowsByType(
            _dedupeLedgerRows(await _dao.getSharedEntriesForPeriod()),
          )
        : sums;
    final allIncome = allSums['income'] ?? 0.0;
    final allCost = allSums['cost'] ?? 0.0;
    final allLoan = allSums['loan'] ?? 0.0;
    final allRepayment = allSums['repayment'] ?? 0.0;
    final allBalance = allIncome + allRepayment - allCost - allLoan;

    return {
      'ledger_scope': 'shared_ai',
      'period': month ?? 'all_time',
      'income': income,
      'cost': cost,
      'loan': loan,
      'repayment': repayment,
      'period_net': balance,
      'all_time_balance': allBalance,
      // Positive all_time_balance = savings; negative = still owes user
      'savings': allBalance > 0 ? allBalance : 0.0,
      'owes_user': allBalance < 0 ? -allBalance : 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> getRecentEntries({
    int limit = 10,
  }) async {
    final rows = _dedupeLedgerRows(
      await _dao.getSharedEntries(limit: limit * 4 < 200 ? 200 : limit * 4),
    )..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return rows
        .take(limit)
        .map((r) => {
              'id': r.id,
              'source_character_id': r.characterId,
              'type': r.entryType,
              'total_amount': r.totalAmount,
              'ai_amount': r.aiAmount,
              'contribution_ratio': r.contributionRatio,
              'my_contribution': r.myContributionDesc,
              'ai_contribution': r.aiContributionDesc,
              'purpose': r.purpose,
              'linked_fact_id': r.linkedFactId,
              'recorded_at': r.recordedAt,
              'notes': r.notes,
            })
        .toList();
  }

  Future<AiFinanceLedgerData?> _findDuplicateEntry({
    required String entryType,
    required double totalAmount,
    required double aiAmount,
    required double? contributionRatio,
    required String? myContributionDesc,
    required String? aiContributionDesc,
    required String? purpose,
    required String? linkedFactId,
    required String? notes,
    required int nowEpoch,
  }) async {
    final normalizedFactId = _normalizeText(linkedFactId);
    if (normalizedFactId != null) {
      final linkedRows = await _dao.getSharedEntries(
        entryType: entryType,
        limit: 200,
      );
      for (final row in linkedRows) {
        if (_normalizeText(row.linkedFactId) == normalizedFactId) {
          return row;
        }
      }
    }

    final sinceEpoch = nowEpoch - _duplicateWindow.inSeconds;
    final recentRows = await _dao.getSharedEntries(
      entryType: entryType,
      sinceEpoch: sinceEpoch,
      limit: 200,
    );
    for (final row in recentRows) {
      if (!_sameMoney(row.totalAmount, totalAmount) ||
          !_sameMoney(row.aiAmount, aiAmount) ||
          !_sameRatio(row.contributionRatio, contributionRatio)) {
        continue;
      }

      final existingContext = _normalizedContext(
        row.purpose,
        row.notes,
        row.myContributionDesc,
        row.aiContributionDesc,
      );
      final newContext = _normalizedContext(
        purpose,
        notes,
        myContributionDesc,
        aiContributionDesc,
      );
      if (existingContext.isNotEmpty &&
          newContext.isNotEmpty &&
          existingContext == newContext) {
        return row;
      }
      if (existingContext.isEmpty &&
          newContext.isEmpty &&
          nowEpoch - row.recordedAt <= _bareAmountDuplicateWindow.inSeconds) {
        return row;
      }
    }
    return null;
  }
}

bool _sameMoney(double a, double b) => (a - b).abs() < 0.005;

bool _sameRatio(double? a, double? b) {
  if (a == null || b == null) return a == b;
  return (a - b).abs() < 0.0001;
}

String _normalizedContext(
  String? purpose,
  String? notes,
  String? myContributionDesc,
  String? aiContributionDesc,
) {
  return [
    _normalizeText(purpose),
    _normalizeText(notes),
    _normalizeText(myContributionDesc),
    _normalizeText(aiContributionDesc),
  ].whereType<String>().join('|');
}

String? _normalizeText(String? value) {
  final normalized = value?.trim().toLowerCase().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _cleanNullableText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

Map<String, double> _sumRowsByType(List<AiFinanceLedgerData> rows) {
  final sums = <String, double>{};
  for (final row in rows) {
    sums[row.entryType] = (sums[row.entryType] ?? 0.0) + row.aiAmount;
  }
  return sums;
}

List<AiFinanceLedgerData> _dedupeLedgerRows(
  List<AiFinanceLedgerData> rows,
) {
  final sorted = [...rows]
    ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  final kept = <AiFinanceLedgerData>[];
  for (final row in sorted) {
    if (kept.any((existing) => _isDuplicateLedgerRow(existing, row))) {
      continue;
    }
    kept.add(row);
  }
  return kept;
}

bool _isDuplicateLedgerRow(
  AiFinanceLedgerData existing,
  AiFinanceLedgerData candidate,
) {
  if (existing.entryType != candidate.entryType) return false;

  final existingFactId = _normalizeText(existing.linkedFactId);
  final candidateFactId = _normalizeText(candidate.linkedFactId);
  if (existingFactId != null && existingFactId == candidateFactId) {
    return true;
  }

  if (!_sameMoney(existing.totalAmount, candidate.totalAmount) ||
      !_sameMoney(existing.aiAmount, candidate.aiAmount) ||
      !_sameRatio(existing.contributionRatio, candidate.contributionRatio)) {
    return false;
  }

  final deltaSeconds = (candidate.recordedAt - existing.recordedAt).abs();
  final existingContext = _normalizedContext(
    existing.purpose,
    existing.notes,
    existing.myContributionDesc,
    existing.aiContributionDesc,
  );
  final candidateContext = _normalizedContext(
    candidate.purpose,
    candidate.notes,
    candidate.myContributionDesc,
    candidate.aiContributionDesc,
  );

  if (existingContext.isNotEmpty && candidateContext.isNotEmpty) {
    return existingContext == candidateContext &&
        deltaSeconds <= AiFinanceService._duplicateWindow.inSeconds;
  }
  return existingContext.isEmpty &&
      candidateContext.isEmpty &&
      deltaSeconds <= AiFinanceService._bareAmountDuplicateWindow.inSeconds;
}
