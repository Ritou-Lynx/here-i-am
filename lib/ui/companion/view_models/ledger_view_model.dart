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
    this.id,
  });

  /// When non-null, this draft is an edit of an existing ledger row with this id.
  /// When null, it is a new entry.
  final String? id;
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
    updateEntry = Command1<void, LedgerEntryDraft>(_updateEntry);
    deleteEntry = Command1<void, String>(_deleteEntry);
  }

  final AiFinanceService _service;
  late final Command0<void> load;
  late final Command1<void, LedgerEntryDraft> addEntry;
  late final Command1<void, LedgerEntryDraft> updateEntry;
  late final Command1<void, String> deleteEntry;

  Map<String, dynamic> overview = const {};
  List<Map<String, dynamic>> entries = const [];

  /// 当前选中月份 'YYYY-MM'。null 表示全部时间视图（兼容旧行为，UI 不主动使用）。
  String get selectedMonth => _selectedMonth;
  String _selectedMonth = _formatMonth(DateTime.now());

  static String _formatMonth(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  /// 切换到相邻月份：delta 为 -1 上月，+1 下月。
  void changeMonth(int delta) {
    final parts = _selectedMonth.split('-');
    final cur = DateTime(int.parse(parts[0]), int.parse(parts[1]));
    final next = DateTime(cur.year, cur.month + delta);
    final now = DateTime.now();
    // 不允许选到未来月份。
    if (next.isAfter(DateTime(now.year, now.month + 1))) return;
    final newMonth = _formatMonth(next);
    if (newMonth == _selectedMonth) return;
    _selectedMonth = newMonth;
    load.execute();
  }

  /// 跳到指定月份（'YYYY-MM'），或 null=当月。
  void setMonth(String? month) {
    final target = month ?? _formatMonth(DateTime.now());
    if (target == _selectedMonth) return;
    _selectedMonth = target;
    load.execute();
  }

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

  Future<Result<void>> _updateEntry(LedgerEntryDraft draft) {
    return runResultVoid(() async {
      final id = draft.id;
      if (id == null) {
        throw const FormatException(
            'LedgerEntryDraft for update must carry an existing entry id');
      }
      final ratio = draft.entryType == 'income' && draft.totalAmount > 0
          ? draft.aiAmount / draft.totalAmount
          : null;
      await _service.updateEntry(
        entryId: id,
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

  Future<Result<void>> _deleteEntry(String entryId) {
    return runResultVoid(() async {
      await _service.deleteEntry(entryId);
      await _refresh();
    });
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      _service.getLedgerOverview(month: _selectedMonth),
      _service.getRecentEntries(limit: 100, month: _selectedMonth),
    ]);
    overview = results[0] as Map<String, dynamic>;
    entries = results[1] as List<Map<String, dynamic>>;
    notifyListeners();
  }

  @override
  void dispose() {
    load.dispose();
    addEntry.dispose();
    updateEntry.dispose();
    deleteEntry.dispose();
    super.dispose();
  }
}
