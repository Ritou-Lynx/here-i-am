import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:memex/data/memory_v3/services/life_insight_scheduler.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/view_models/ledger_view_model.dart';
import 'package:memex/ui/companion/widgets/insight_strip.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/result.dart';
import 'package:provider/provider.dart';

const _ledgerInk = Color(0xFF293025);
const _ledgerMuted = Color(0xFF667061);
const _ledgerOnRain = Color(0xFFF5EEE0);
const _ledgerAccent = Color(0xFF737B46);
const _ledgerIncome = Color(0xFF5F7658);
const _ledgerExpense = Color(0xFFA66F58);
const _ledgerTransfer = Color(0xFF9A8051);
const _ledgerFog = Color(0xEAF7F5ED);

enum _ViewMode { list, calendar }

class CompanionLedgerPanel extends StatefulWidget {
  const CompanionLedgerPanel({super.key});

  @override
  State<CompanionLedgerPanel> createState() => _CompanionLedgerPanelState();
}

class _CompanionLedgerPanelState extends State<CompanionLedgerPanel> {
  _ViewMode _viewMode = _ViewMode.list;

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<LedgerViewModel>();
    final isFirstLoad = viewModel.load.running && viewModel.overview.isEmpty;
    if (isFirstLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.load.error && viewModel.overview.isEmpty) {
      return _LoadError(onRetry: viewModel.load.execute);
    }

    return RefreshIndicator(
      onRefresh: viewModel.load.execute,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          InsightStrip(
            domain: 'finance',
            onRefresh: () => LifeInsightScheduler(db: AppDatabase.instance)
                .forceRunWeeklyAnalysis(),
          ),
          _Header(
            selectedMonth: viewModel.selectedMonth,
            viewMode: _viewMode,
            onViewModeChanged: (m) => setState(() => _viewMode = m),
            onPrevMonth: () => viewModel.changeMonth(-1),
            onNextMonth: () => viewModel.changeMonth(1),
            onAdd: () => _showEntrySheet(context),
          ),
          const SizedBox(height: 16),
          _CashSummary(overview: viewModel.overview),
          const SizedBox(height: 12),
          _SplitSummary(overview: viewModel.overview),
          const SizedBox(height: 22),
          if (_viewMode == _ViewMode.list) ...[
            const Text(
              '当月明细',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _ledgerOnRain,
                shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
              ),
            ),
            const SizedBox(height: 10),
            if (viewModel.entries.isEmpty)
              const _EmptyLedger()
            else
              ...viewModel.entries.map(_LedgerEntryTile.new),
          ] else
            _MonthCalendarSection(
              entries: viewModel.entries,
              selectedMonth: viewModel.selectedMonth,
            ),
        ],
      ),
    );
  }

  Future<void> _showEntrySheet(BuildContext context) async {
    final viewModel = context.read<LedgerViewModel>();
    final draft = await showModalBottomSheet<LedgerEntryDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _LedgerEntrySheet(),
    );
    if (draft == null || !context.mounted) return;

    await viewModel.addEntry.execute(draft);
    if (!context.mounted) return;
    switch (viewModel.addEntry.result) {
      case Ok<void>():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已记入账本')),
        );
      case Error<void>(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录失败：$error')),
        );
      case null:
        break;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.selectedMonth,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onAdd,
  });

  final String selectedMonth;
  final _ViewMode viewMode;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final parts = selectedMonth.split('-');
    final monthLabel =
        '${parts[0]}年${int.parse(parts[1])}月';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _MonthNavArrow(icon: Icons.chevron_left_rounded, onTap: onPrevMonth),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _ledgerOnRain,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
            ),
            _MonthNavArrow(icon: Icons.chevron_right_rounded, onTap: onNextMonth),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('记一笔'),
              style: FilledButton.styleFrom(
                backgroundColor: _ledgerAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _ledgerFog,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xB8FFFFFF), width: .8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _ViewTogglePill(
                  label: '明细',
                  selected: viewMode == _ViewMode.list,
                  onTap: () => onViewModeChanged(_ViewMode.list),
                ),
              ),
              Expanded(
                child: _ViewTogglePill(
                  label: '日历',
                  selected: viewMode == _ViewMode.calendar,
                  onTap: () => onViewModeChanged(_ViewMode.calendar),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthNavArrow extends StatelessWidget {
  const _MonthNavArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 26, color: _ledgerOnRain),
      ),
    );
  }
}

class _ViewTogglePill extends StatelessWidget {
  const _ViewTogglePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: selected
            ? BoxDecoration(
                color: _ledgerAccent,
                borderRadius: BorderRadius.circular(9),
              )
            : null,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _ledgerMuted,
          ),
        ),
      ),
    );
  }
}

class _CashSummary extends StatelessWidget {
  const _CashSummary({required this.overview});

  final Map<String, dynamic> overview;

  @override
  Widget build(BuildContext context) {
    final net = _number(overview['cash_net']);
    final allTimeNet = _number(overview['all_time_cash_net']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text('本月收支结余', style: TextStyle(color: _ledgerMuted)),
              const SizedBox(width: 10),
              Text(
                '总至今 ${_money(allTimeNet, signed: true)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: _ledgerMuted,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            _money(net, signed: true),
            style: TextStyle(
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: net >= 0 ? _ledgerIncome : _ledgerExpense,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '本月收入',
                  value: _money(_number(overview['external_income'])),
                  color: _ledgerIncome,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '本月支出',
                  value: _money(_number(overview['external_expense'])),
                  color: _ledgerExpense,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '记录',
                  value: '${overview['entry_count'] ?? 0} 笔',
                  color: _ledgerAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SplitSummary extends StatelessWidget {
  const _SplitSummary({required this.overview});

  final Map<String, dynamic> overview;

  @override
  Widget build(BuildContext context) {
    final aiBalance = _number(overview['ai_all_time_balance']);
    final aiLabel = aiBalance >= 0 ? 'i 的余额' : 'i 欠你的';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PersonCard(
            eyebrow: '我的部分',
            amount: _number(overview['all_time_my_allocated_net']),
            lines: [
              '收入分到 ${_money(_number(overview['my_income_share']))}',
              '支出承担 ${_money(_number(overview['my_expense_share']))}',
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PersonCard(
            eyebrow: aiLabel,
            amount: aiBalance.abs(),
            highlight: true,
            lines: [
              '收入分到 ${_money(_number(overview['ai_income_share']))}',
              '支出承担 ${_money(_number(overview['ai_expense_share']))}',
            ],
          ),
        ),
      ],
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    required this.eyebrow,
    required this.amount,
    required this.lines,
    this.highlight = false,
  });

  final String eyebrow;
  final double amount;
  final List<String> lines;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(
        color: highlight ? const Color(0xECEAEBD8) : _ledgerFog,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: const TextStyle(color: _ledgerMuted)),
          const SizedBox(height: 6),
          Text(
            _money(amount),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _ledgerInk,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _ledgerMuted),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: _ledgerMuted)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}

class _LedgerEntryTile extends StatelessWidget {
  const _LedgerEntryTile(this.entry);

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final type = entry['type'] as String? ?? '';
    final total = _number(entry['total_amount']);
    final aiAmount = _number(entry['ai_amount']);
    final transferDir = entry['transfer_direction'] as String?;
    final isInflow = type == 'income' ||
        type == 'reward' ||
        type == 'repayment' ||
        (type == 'transfer' && transferDir == 'ai_to_user');
    final date = DateTime.fromMillisecondsSinceEpoch(
      ((entry['recorded_at'] as num?)?.toInt() ?? 0) * 1000,
    );
    final splitText = switch (type) {
      'income' ||
      'cost' ||
      'expense' =>
        '我 ${_money(total - aiAmount)} · i ${_money(aiAmount)}',
      'reward' => 'i → 我',
      'penalty' => '我 → i',
      'loan' => '我先垫付给 i',
      'repayment' => 'i 归还给我',
      'transfer' => transferDir == 'user_to_ai' ? '我 → i' : 'i → 我',
      _ => '',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: _cardDecoration(),
      child: InkWell(
        onLongPress: () => _showEntryActions(context, entry),
        borderRadius: BorderRadius.circular(13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _entryColor(type).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(_entryIcon(type), size: 20, color: _entryColor(type)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (entry['purpose'] as String?)?.trim().isNotEmpty == true
                        ? entry['purpose'] as String
                        : _entryLabel(type),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.month}月${date.day}日 · $splitText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _ledgerMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${isInflow ? '+' : '-'}${_money(total)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isInflow ? _ledgerIncome : _ledgerInk,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEntryActions(
    BuildContext context,
    Map<String, dynamic> entry,
  ) async {
    final id = entry['id'] as String?;
    if (id == null) return;
    final action = await showModalBottomSheet<_EntryAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _EntryActionSheet(),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _EntryAction.edit:
        await _editEntry(context, entry);
      case _EntryAction.delete:
        await _confirmDelete(context, id);
    }
  }

  Future<void> _editEntry(
    BuildContext context,
    Map<String, dynamic> entry,
  ) async {
    final viewModel = context.read<LedgerViewModel>();
    final draft = await showModalBottomSheet<LedgerEntryDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LedgerEntrySheet(existingEntry: entry),
    );
    if (draft == null || !context.mounted) return;
    await viewModel.updateEntry.execute(draft);
    if (!context.mounted) return;
    switch (viewModel.updateEntry.result) {
      case Ok<void>():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已更新')),
        );
      case Error<void>(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新失败：$error')),
        );
      case null:
        break;
    }
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeleteConfirmSheet(),
    );
    if (confirmed != true || !context.mounted) return;
    final viewModel = context.read<LedgerViewModel>();
    await viewModel.deleteEntry.execute(id);
    if (!context.mounted) return;
    switch (viewModel.deleteEntry.result) {
      case Ok<void>():
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      case Error<void>(:final error):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      case null:
        break;
    }
  }
}

enum _EntryAction { edit, delete }

class _EntryActionSheet extends StatelessWidget {
  const _EntryActionSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('修改'),
            onTap: () => Navigator.pop(context, _EntryAction.edit),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppColors.danger),
            title: const Text('删除', style: TextStyle(color: AppColors.danger)),
            onTap: () => Navigator.pop(context, _EntryAction.delete),
          ),
        ],
      ),
    );
  }
}

class _DeleteConfirmSheet extends StatelessWidget {
  const _DeleteConfirmSheet();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '删除这条账目？',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            '删除后不可恢复。如果只是金额或类型错了，建议用「修改」。',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13)),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    backgroundColor: AppColors.danger,
                  ),
                  child: const Text('删除'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
      decoration: _cardDecoration(),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 34, color: AppColors.textTertiary),
          SizedBox(height: 10),
          Text('还没有账目', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 4),
          Text('先记一笔制作收入、API 支出或你和 i 之间的往来。', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton.tonal(
          onPressed: onRetry, child: const Text('账本加载失败，重试')),
    );
  }
}

class _LedgerEntrySheet extends StatefulWidget {
  const _LedgerEntrySheet({this.existingEntry});

  /// When non-null, the sheet opens in edit mode pre-filled from this entry.
  final Map<String, dynamic>? existingEntry;

  @override
  State<_LedgerEntrySheet> createState() => _LedgerEntrySheetState();
}

class _LedgerEntrySheetState extends State<_LedgerEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _aiAmountController = TextEditingController(text: '0');
  final _purposeController = TextEditingController();
  final _notesController = TextEditingController();
  String _entryType = 'income';
  String _transferDirection = 'user_to_ai';
  DateTime _occurredAt = DateTime.now();

  bool get _isEditing => widget.existingEntry != null;
  bool get _isShared =>
      _entryType == 'income' || _entryType == 'cost' || _entryType == 'expense';
  bool get _isTransfer => _entryType == 'transfer';

  @override
  void initState() {
    super.initState();
    final e = widget.existingEntry;
    if (e != null) {
      _entryType = (e['type'] as String?) ?? 'income';
      _transferDirection = (e['transfer_direction'] as String?) ?? 'user_to_ai';
      _amountController.text = _formatForInput(_number(e['total_amount']));
      _aiAmountController.text = _formatForInput(_number(e['ai_amount']));
      _purposeController.text = (e['purpose'] as String?) ?? '';
      _notesController.text = (e['notes'] as String?) ?? '';
      final recordedAt = (e['recorded_at'] as num?)?.toInt();
      if (recordedAt != null && recordedAt > 0) {
        _occurredAt = DateTime.fromMillisecondsSinceEpoch(recordedAt * 1000);
      }
      // For legacy types that aren't "shared" (reward/penalty/loan/repayment),
      // mirror amount into aiAmount by default when editing.
      if (!_isShared && !_isTransfer) {
        _aiAmountController.text = _amountController.text;
      }
    }
  }

  String _formatForInput(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _aiAmountController.dispose();
    _purposeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEditing ? '修改账目' : '记一笔',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _entryType,
                decoration: const InputDecoration(
                    labelText: '类型', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'income', child: Text('制作 / 项目收入')),
                  DropdownMenuItem(value: 'expense', child: Text('日常支出 / 消费')),
                  DropdownMenuItem(value: 'transfer', child: Text('我和 i 之间转账')),
                  DropdownMenuItem(value: 'cost', child: Text('AI 套餐 / 共同支出')),
                  DropdownMenuItem(
                      value: 'reward', child: Text('i 转给我（奖励 / 补偿）')),
                  DropdownMenuItem(
                      value: 'penalty', child: Text('我转给 i（奖励 / 罚款）')),
                  DropdownMenuItem(value: 'loan', child: Text('我替 i 垫付')),
                  DropdownMenuItem(value: 'repayment', child: Text('i 归还垫款')),
                ],
                onChanged: (value) => setState(() {
                  _entryType = value!;
                  if (!_isShared && !_isTransfer) {
                    _aiAmountController.text = _amountController.text;
                  }
                }),
              ),
              if (_isTransfer) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _transferDirection,
                  decoration: const InputDecoration(
                      labelText: '方向', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'user_to_ai', child: Text('我 → i（我给 i 钱）')),
                    DropdownMenuItem(
                        value: 'ai_to_user', child: Text('i → 我（i 给我钱）')),
                  ],
                  onChanged: (value) =>
                      setState(() => _transferDirection = value!),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}'))
                      ],
                      decoration: const InputDecoration(
                          labelText: '总金额',
                          prefixText: '¥ ',
                          border: OutlineInputBorder()),
                      validator: _validatePositiveMoney,
                      onChanged: (value) {
                        if (!_isShared && !_isTransfer) {
                          _aiAmountController.text = value;
                        }
                      },
                    ),
                  ),
                  if (_isShared) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _aiAmountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'))
                        ],
                        decoration: const InputDecoration(
                            labelText: '其中 i 的份额',
                            prefixText: '¥ ',
                            border: OutlineInputBorder()),
                        validator: (value) {
                          final message = _validateNonNegativeMoney(value);
                          if (message != null) return message;
                          final aiAmount = double.parse(value!);
                          final total = double.tryParse(_amountController.text);
                          return total != null && aiAmount > total
                              ? '不能超过总金额'
                              : null;
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purposeController,
                decoration: const InputDecoration(
                    labelText: '事项',
                    hintText: '例如：7 月 API 套餐',
                    border: OutlineInputBorder()),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? '写一下这笔钱是什么' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: '备注（可选）', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined, size: 20),
                title: const Text('发生日期'),
                trailing: Text(DateFormat('yyyy年MM月dd日').format(_occurredAt)),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(_isEditing ? '保存修改' : '保存到共同账本'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    // Allow selecting dates up to 1 year in the future so entries whose
    // recorded_at landed in the future (LLM paidAt parsing drift) can be
    // corrected. Without this, showDatePicker silently fails when
    // initialDate > lastDate (DateTime.now()).
    final lastDate = DateTime.now().add(const Duration(days: 365));
    final initialDate = _occurredAt.isAfter(lastDate) ? lastDate : _occurredAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: lastDate,
    );
    if (date != null) setState(() => _occurredAt = date);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text);
    Navigator.pop(
      context,
      LedgerEntryDraft(
        id: _isEditing ? widget.existingEntry!['id'] as String? : null,
        entryType: _entryType,
        totalAmount: amount,
        aiAmount: _isShared ? double.parse(_aiAmountController.text) : amount,
        purpose: _purposeController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        transferDirection: _isTransfer ? _transferDirection : null,
        occurredAt: _occurredAt,
      ),
    );
  }
}

String? _validatePositiveMoney(String? value) {
  final parsed = double.tryParse(value ?? '');
  return parsed == null || parsed <= 0 ? '请输入大于 0 的金额' : null;
}

String? _validateNonNegativeMoney(String? value) {
  final parsed = double.tryParse(value ?? '');
  return parsed == null || parsed < 0 ? '请输入有效金额' : null;
}

BoxDecoration _cardDecoration({Color color = _ledgerFog}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xB8FFFFFF), width: .8),
      boxShadow: const [
        BoxShadow(
            color: Color(0x22000000), blurRadius: 16, offset: Offset(0, 5)),
      ],
    );

double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;

String _money(double value, {bool signed = false}) {
  final formatter =
      NumberFormat.currency(locale: 'zh_CN', symbol: '¥', decimalDigits: 2);
  final formatted = formatter.format(value.abs());
  if (!signed || value == 0) return formatted;
  return '${value > 0 ? '+' : '-'}$formatted';
}

String _entryLabel(String type) => switch (type) {
      'income' => '收入',
      'expense' => '支出',
      'cost' => 'AI 支出',
      'transfer' => '转账',
      'reward' => 'i 转给我',
      'penalty' => '我转给 i',
      'loan' => '替 i 垫付',
      'repayment' => 'i 归还垫款',
      _ => '账目',
    };

IconData _entryIcon(String type) => switch (type) {
      'income' => Icons.south_west_rounded,
      'expense' => Icons.north_east_rounded,
      'cost' => Icons.computer_rounded,
      'transfer' => Icons.swap_horiz_rounded,
      'reward' => Icons.card_giftcard_rounded,
      'penalty' => Icons.gavel_rounded,
      'loan' => Icons.handshake_outlined,
      'repayment' => Icons.replay_rounded,
      _ => Icons.receipt_long_outlined,
    };

Color _entryColor(String type) => switch (type) {
      'income' || 'reward' || 'repayment' => _ledgerIncome,
      'expense' || 'cost' => _ledgerExpense,
      'transfer' || 'penalty' => _ledgerTransfer,
      _ => _ledgerAccent,
    };

// ─────────────────── 月格日历 ───────────────────

class _MonthCalendarSection extends StatelessWidget {
  const _MonthCalendarSection({
    required this.entries,
    required this.selectedMonth,
  });

  final List<Map<String, dynamic>> entries;
  final String selectedMonth;

  @override
  Widget build(BuildContext context) {
    final byDay = _groupEntriesByDay(entries, selectedMonth);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: _MonthCalendarGrid(
        month: selectedMonth,
        dayEntries: byDay,
        onDaySelected: (day, dayList) =>
            _showDaySheet(context, day, dayList),
      ),
    );
  }

  Map<int, List<Map<String, dynamic>>> _groupEntriesByDay(
    List<Map<String, dynamic>> rows,
    String month,
  ) {
    final parts = month.split('-');
    final year = int.parse(parts[0]);
    final mon = int.parse(parts[1]);
    final map = <int, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final epoch = (r['recorded_at'] as num?)?.toInt() ?? 0;
      final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
      if (dt.year != year || dt.month != mon) continue;
      map.putIfAbsent(dt.day, () => []).add(r);
    }
    return map;
  }

  Future<void> _showDaySheet(
    BuildContext context,
    int day,
    List<Map<String, dynamic>> dayList,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DayEntriesSheet(day: day, entries: dayList),
    );
  }
}

class _MonthCalendarGrid extends StatelessWidget {
  const _MonthCalendarGrid({
    required this.month,
    required this.dayEntries,
    required this.onDaySelected,
  });

  final String month;
  final Map<int, List<Map<String, dynamic>>> dayEntries;
  final void Function(int day, List<Map<String, dynamic>> list) onDaySelected;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final parts = month.split('-');
    final year = int.parse(parts[0]);
    final mon = int.parse(parts[1]);
    final firstOfMonth = DateTime(year, mon, 1);
    // 周一=0 .. 周日=6
    int leadingBlanks;
    {
      final w = firstOfMonth.weekday; // Monday=1..Sunday=7
      leadingBlanks = w - 1;
    }
    final daysInMonth = DateTime(year, mon + 1, 0).day;
    final today = DateTime.now();
    final isCurrentMonth = today.year == year && today.month == mon;

    return Column(
      children: [
        Row(
          children: _weekdays
              .map((w) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        w,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: _ledgerMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 0.92,
            mainAxisSpacing: 4,
            crossAxisSpacing: 2,
          ),
          itemCount: leadingBlanks + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlanks) {
              return const SizedBox.shrink();
            }
            final day = index - leadingBlanks + 1;
            final list = dayEntries[day] ?? const [];
            final isToday =
                isCurrentMonth && day == today.day;
            return _CalendarDayCell(
              day: day,
              entries: list,
              isToday: isToday,
              onTap: list.isEmpty ? null : () => onDaySelected(day, list),
            );
          },
        ),
      ],
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.entries,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final List<Map<String, dynamic>> entries;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 当日净流：收入+返还-支出-转出
    double net = 0;
    for (final e in entries) {
      final type = e['type'] as String? ?? '';
      final total = _number(e['total_amount']);
      final dir = e['transfer_direction'] as String?;
      final isInflow = type == 'income' ||
          type == 'reward' ||
          type == 'repayment' ||
          (type == 'transfer' && dir == 'ai_to_user');
      net += isInflow ? total : -total;
    }
    final hasEntries = entries.isNotEmpty;
    final ink = net >= 0 ? _ledgerIncome : _ledgerExpense;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: hasEntries
              ? ink.withValues(alpha: 0.10)
              : (isToday ? _ledgerAccent.withValues(alpha: 0.10) : null),
          borderRadius: BorderRadius.circular(10),
          border: isToday
              ? Border.all(color: _ledgerAccent, width: 1.2)
              : null,
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$day',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                color: _ledgerInk,
              ),
            ),
            if (hasEntries) ...[
              const SizedBox(height: 1),
              Text(
                _money(net.abs(), signed: false).replaceAll('¥', ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DayEntriesSheet extends StatelessWidget {
  const _DayEntriesSheet({required this.day, required this.entries});

  final int day;
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    double net = 0;
    for (final e in entries) {
      final type = e['type'] as String? ?? '';
      final total = _number(e['total_amount']);
      final dir = e['transfer_direction'] as String?;
      final isInflow = type == 'income' ||
          type == 'reward' ||
          type == 'repayment' ||
          (type == 'transfer' && dir == 'ai_to_user');
      net += isInflow ? total : -total;
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$day日明细',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '当日 ${_money(net, signed: true)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: net >= 0 ? _ledgerIncome : _ledgerExpense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: entries.length,
              itemBuilder: (_, i) => _LedgerEntryTile(entries[i]),
            ),
          ),
        ],
      ),
    );
  }
}
