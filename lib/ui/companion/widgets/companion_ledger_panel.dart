import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:memex/ui/companion/view_models/ledger_view_model.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/result.dart';
import 'package:provider/provider.dart';

class CompanionLedgerPanel extends StatelessWidget {
  const CompanionLedgerPanel({super.key});

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
          _Header(onAdd: () => _showEntrySheet(context)),
          const SizedBox(height: 16),
          _CashSummary(overview: viewModel.overview),
          const SizedBox(height: 12),
          _SplitSummary(overview: viewModel.overview),
          const SizedBox(height: 22),
          const Text(
            '最近明细',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          if (viewModel.entries.isEmpty)
            const _EmptyLedger()
          else
            ...viewModel.entries.map(_LedgerEntryTile.new),
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
  const _Header({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '共同账本',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '真实收支是总账，i 的份额从同一笔记录中派生。',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('记一笔'),
        ),
      ],
    );
  }
}

class _CashSummary extends StatelessWidget {
  const _CashSummary({required this.overview});

  final Map<String, dynamic> overview;

  @override
  Widget build(BuildContext context) {
    final net = _number(overview['cash_net']);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('全部真实收支', style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 7),
          Text(
            _money(net, signed: true),
            style: TextStyle(
              fontSize: 34,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: net >= 0 ? AppColors.success : AppColors.danger,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '收入',
                  value: _money(_number(overview['external_income'])),
                  color: AppColors.success,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '支出',
                  value: _money(_number(overview['external_expense'])),
                  color: AppColors.danger,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '记录',
                  value: '${overview['entry_count'] ?? 0} 笔',
                  color: AppColors.primary,
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
        color: highlight ? AppColors.iconBgLight : AppColors.cardBackground,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Text(
            _money(amount),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
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
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
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
    final isInflow = type == 'income' || type == 'reward' || type == 'repayment';
    final date = DateTime.fromMillisecondsSinceEpoch(
      ((entry['recorded_at'] as num?)?.toInt() ?? 0) * 1000,
    );
    final splitText = switch (type) {
      'income' || 'cost' => '我 ${_money(total - aiAmount)} · i ${_money(aiAmount)}',
      'reward' => 'i → 我',
      'penalty' => '我 → i',
      'loan' => '我先垫付给 i',
      'repayment' => 'i 归还给我',
      _ => '',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: _cardDecoration(),
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
                  '${DateFormat('MM月dd日').format(date)} · $splitText',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${isInflow ? '+' : '-'}${_money(total)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isInflow ? AppColors.success : AppColors.textPrimary,
            ),
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
          Icon(Icons.receipt_long_outlined, size: 34, color: AppColors.textTertiary),
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
      child: FilledButton.tonal(onPressed: onRetry, child: const Text('账本加载失败，重试')),
    );
  }
}

class _LedgerEntrySheet extends StatefulWidget {
  const _LedgerEntrySheet();

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
  DateTime _occurredAt = DateTime.now();

  bool get _isShared => _entryType == 'income' || _entryType == 'cost';

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
                  const Expanded(
                    child: Text('记一笔', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _entryType,
                decoration: const InputDecoration(labelText: '类型', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'income', child: Text('制作 / 项目收入')),
                  DropdownMenuItem(value: 'cost', child: Text('AI 套餐 / 共同支出')),
                  DropdownMenuItem(value: 'reward', child: Text('i 转给我（奖励 / 补偿）')),
                  DropdownMenuItem(value: 'penalty', child: Text('我转给 i（奖励 / 罚款）')),
                  DropdownMenuItem(value: 'loan', child: Text('我替 i 垫付')),
                  DropdownMenuItem(value: 'repayment', child: Text('i 归还垫款')),
                ],
                onChanged: (value) => setState(() {
                  _entryType = value!;
                  if (!_isShared) _aiAmountController.text = _amountController.text;
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      decoration: const InputDecoration(labelText: '总金额', prefixText: '¥ ', border: OutlineInputBorder()),
                      validator: _validatePositiveMoney,
                      onChanged: (value) {
                        if (!_isShared) _aiAmountController.text = value;
                      },
                    ),
                  ),
                  if (_isShared) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _aiAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                        decoration: const InputDecoration(labelText: '其中 i 的份额', prefixText: '¥ ', border: OutlineInputBorder()),
                        validator: (value) {
                          final message = _validateNonNegativeMoney(value);
                          if (message != null) return message;
                          final aiAmount = double.parse(value!);
                          final total = double.tryParse(_amountController.text);
                          return total != null && aiAmount > total ? '不能超过总金额' : null;
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purposeController,
                decoration: const InputDecoration(labelText: '事项', hintText: '例如：7 月 API 套餐', border: OutlineInputBorder()),
                validator: (value) => value == null || value.trim().isEmpty ? '写一下这笔钱是什么' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注（可选）', border: OutlineInputBorder()),
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
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('保存到共同账本'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date != null) setState(() => _occurredAt = date);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amountController.text);
    Navigator.pop(
      context,
      LedgerEntryDraft(
        entryType: _entryType,
        totalAmount: amount,
        aiAmount: _isShared ? double.parse(_aiAmountController.text) : amount,
        purpose: _purposeController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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

BoxDecoration _cardDecoration({Color color = AppColors.cardBackground}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [BoxShadow(color: AppColors.shadowCard, blurRadius: 18, offset: Offset(0, 5))],
    );

double _number(dynamic value) => (value as num?)?.toDouble() ?? 0;

String _money(double value, {bool signed = false}) {
  final formatter = NumberFormat.currency(locale: 'zh_CN', symbol: '¥', decimalDigits: 2);
  final formatted = formatter.format(value.abs());
  if (!signed || value == 0) return formatted;
  return '${value > 0 ? '+' : '-'}$formatted';
}

String _entryLabel(String type) => switch (type) {
      'income' => '收入',
      'cost' => '支出',
      'reward' => 'i 转给我',
      'penalty' => '我转给 i',
      'loan' => '替 i 垫付',
      'repayment' => 'i 归还垫款',
      _ => '账目',
    };

IconData _entryIcon(String type) => switch (type) {
      'income' => Icons.south_west_rounded,
      'cost' => Icons.north_east_rounded,
      'reward' => Icons.card_giftcard_rounded,
      'penalty' => Icons.gavel_rounded,
      'loan' => Icons.handshake_outlined,
      'repayment' => Icons.replay_rounded,
      _ => Icons.receipt_long_outlined,
    };

Color _entryColor(String type) => switch (type) {
      'income' || 'reward' || 'repayment' => AppColors.success,
      'cost' => AppColors.danger,
      'penalty' => AppColors.warning,
      _ => AppColors.primary,
    };
