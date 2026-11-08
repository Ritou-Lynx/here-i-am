import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:memex/data/personal_data_hub/food_connection.dart';
import 'package:memex/data/personal_data_hub/personal_data_hub.dart';
import 'package:memex/db/app_database.dart';
import 'package:uuid/uuid.dart';

import 'ai_finance_service.dart';

/// Projects Core `expense_entries` (written by expense_log on the AI web
/// frontends) into the shared ledger as expense rows.
///
/// Each Core record owns exactly one ledger row with a stable ID. The row is
/// (re)written only when the Core revision changes, so an edit or delete the
/// user makes in the ledger panel sticks until the AI changes that record
/// again. A voided or deleted Core record removes its row.
class CoreExpenseLedgerProjector {
  CoreExpenseLedgerProjector({required AppDatabase db}) : _db = db;

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const revisionsKey = 'ai_finance.core_expense_revisions';
  static const _bucket = 'ai_finance';
  static const _frontendLabels = {
    'claude_web': 'Claude',
    'chatgpt_web': 'ChatGPT',
    'gemini_web': 'Gemini',
    'antigravity': 'Antigravity',
  };

  static String entryIdFor(String recordId) =>
      _uuid.v5(Namespace.url.value, 'hereiam:core-expense:$recordId');

  /// [records] are the visible replica rows of `expense_entries`
  /// (DomainStore.visible). Returns how many ledger rows changed.
  Future<int> project(List<Map<String, dynamic>> records) =>
      _db.transaction(() async {
        final seen = await _readRevisions();
        final next = <String, int>{};
        var changed = 0;
        for (final record in records) {
          final id = record['id'];
          final revision = record['revision'];
          final data = record['data'];
          if (id is! String || id.isEmpty || revision is! int || data is! Map) {
            continue;
          }
          // Rows still waiting in the outbox are not Core facts yet.
          if (record['sync_label'] != null) continue;
          final entry = _ExpenseData.tryParse(data);
          if (entry == null) continue;
          final entryId = entryIdFor(id);
          if (entry.voided) {
            changed += await _deleteOwned(entryId);
            continue;
          }
          next[id] = revision;
          if (seen[id] == revision) continue;
          final existing = await (_db.select(_db.aiFinanceLedger)
                ..where((t) => t.id.equals(entryId)))
              .getSingleOrNull();
          if (existing != null &&
              !existing.characterId
                  .startsWith(AiFinanceService.coreExpenseOwnerPrefix)) {
            continue; // Never overwrite a row another writer owns.
          }
          await _db.into(_db.aiFinanceLedger).insertOnConflictUpdate(
                AiFinanceLedgerCompanion.insert(
                  id: entryId,
                  characterId:
                      '${AiFinanceService.coreExpenseOwnerPrefix}${entry.frontend}',
                  entryType: 'expense',
                  totalAmount: entry.amount,
                  aiAmount: entry.aiAmount,
                  contributionRatio: const Value(null),
                  myContributionDesc: const Value(null),
                  aiContributionDesc: const Value(null),
                  purpose: Value(entry.item),
                  linkedFactId: const Value(null),
                  transferDirection: const Value(null),
                  notes: Value(_notes(entry)),
                  recordedAt: entry.spentAt.millisecondsSinceEpoch ~/ 1000,
                ),
              );
          changed++;
        }
        // Records that left the replica (deleted in Core) lose their row.
        for (final id in seen.keys) {
          if (next.containsKey(id)) continue;
          if (records.any((r) => r['id'] == id && r['sync_label'] != null)) {
            next[id] = seen[id]!;
            continue;
          }
          changed += await _deleteOwned(entryIdFor(id));
        }
        await _writeRevisions(next);
        return changed;
      });

  String _notes(_ExpenseData entry) {
    final label = _frontendLabels[entry.frontend] ?? entry.frontend;
    final note = entry.note.trim();
    return note.isEmpty ? '经 $label 记账' : '$note（经 $label 记账）';
  }

  Future<int> _deleteOwned(String entryId) => (_db.delete(_db.aiFinanceLedger)
        ..where((t) =>
            t.id.equals(entryId) &
            t.characterId.like('${AiFinanceService.coreExpenseOwnerPrefix}%')))
      .go();

  Future<Map<String, int>> _readRevisions() async {
    final row = await (_db.select(_db.kvStore)
          ..where((t) => t.key.equals(revisionsKey)))
        .getSingleOrNull();
    try {
      final decoded = jsonDecode(row?.value ?? '{}');
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeRevisions(Map<String, int> value) =>
      _db.into(_db.kvStore).insertOnConflictUpdate(KvStoreCompanion.insert(
            key: revisionsKey,
            bucket: const Value(_bucket),
            value: Value(jsonEncode(value)),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          ));
}

/// Projects the expense replica after a foreground sync. Does nothing unless
/// that domain is attached and its last sync succeeded, so a failed or
/// not-yet-enabled ledger never removes rows.
Future<int?> projectCoreExpensesFromHub(PersonalDataHub hub) async {
  final store = hub.storeFor(expenseDomainName);
  if (store == null ||
      !hub.syncedDomains.contains(expenseDomainName) ||
      hub.lastSyncErrors.containsKey(expenseDomainName)) {
    return null;
  }
  final rows = await store.visible(expenseDomainName);
  final db = hub.db;
  return CoreExpenseLedgerProjector(db: db).project(rows);
}

class _ExpenseData {
  const _ExpenseData({
    required this.amount,
    required this.aiAmount,
    required this.item,
    required this.note,
    required this.frontend,
    required this.spentAt,
    required this.voided,
  });

  final double amount;
  final double aiAmount;
  final String item;
  final String note;
  final String frontend;
  final DateTime spentAt;
  final bool voided;

  static _ExpenseData? tryParse(Map<dynamic, dynamic> data) {
    final amount = data['amount_cny'];
    final aiAmount = data['ai_amount_cny'];
    final item = data['item'];
    final spentAt = DateTime.tryParse(data['spent_at']?.toString() ?? '');
    final frontend = data['source_frontend'];
    final voided = data['voided'];
    if (amount is! num ||
        !amount.isFinite ||
        amount <= 0 ||
        aiAmount is! num ||
        !aiAmount.isFinite ||
        aiAmount < 0 ||
        aiAmount > amount ||
        item is! String ||
        item.trim().isEmpty ||
        spentAt == null ||
        frontend is! String ||
        !RegExp(r'^[a-z_]{1,32}$').hasMatch(frontend) ||
        voided is! bool) {
      return null;
    }
    final note = data['note'];
    return _ExpenseData(
      amount: amount.toDouble(),
      aiAmount: aiAmount.toDouble(),
      item: item.trim(),
      note: note is String ? note : '',
      frontend: frontend,
      spentAt: spentAt,
      voided: voided,
    );
  }
}
