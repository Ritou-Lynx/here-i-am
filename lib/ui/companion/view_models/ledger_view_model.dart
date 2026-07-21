import 'package:flutter/foundation.dart';
import 'package:memex/data/services/ai_finance_service.dart';
import 'package:memex/utils/command.dart';
import 'package:memex/utils/result.dart';

class LedgerEntryDraft {
  const LedgerEntryDraft({
    required this.entryType,
    required this.totalAmount,
    required this.aiAmount,
    required this.purpose,
    required this.occurredAt,
    this.notes,
    this.transferDirection,
  });

  final String entryType;
  final double totalAmount;
  final double aiAmount;
  final String purpose;
  final DateTime occurredAt;
  final String? notes;
  final String? transferDirection;
}

class LedgerViewModel extends ChangeNotifier {
  LedgerViewModel({required AiFinanceService service}) : _service = service {
    load = Command0<void>(_load);
    addEntry = Command1<void, LedgerEntryDraft>(_addEntry);
  }

  final AiFinanceService _service;
  late final Command0<void> load;
  late final Command1<void, LedgerEntryDraft> addEntry;

  Map<String, dynamic> overview = const {};
  List<Map<String, dynamic>> entries = const [];

  Future<Result<void>> _load() => runResultVoid(_refresh);

  Future<Result<void>> _addEntry(LedgerEntryDraft draft) {
    return runResultVoid(() async {
      final ratio = draft.entryType == 'income' && draft.totalAmount > 0
          ? draft.aiAmount / draft.totalAmount
          : null;
      await _service.recordEntry(
        characterId: 'manual:user',
        entryType: draft.entryType,
        totalAmount: draft.totalAmount,
        aiAmount: draft.aiAmount,
        contributionRatio: ratio,
        purpose: draft.purpose,
        notes: draft.notes,
        transferDirection: draft.transferDirection,
        occurredAt: draft.occurredAt,
      );
      await _refresh();
    });
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      _service.getLedgerOverview(),
      _service.getRecentEntries(limit: 100),
    ]);
    overview = results[0] as Map<String, dynamic>;
    entries = results[1] as List<Map<String, dynamic>>;
    notifyListeners();
  }

  @override
  void dispose() {
    load.dispose();
    addEntry.dispose();
    super.dispose();
  }
}
