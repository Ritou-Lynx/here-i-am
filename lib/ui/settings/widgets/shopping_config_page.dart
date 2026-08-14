import 'package:flutter/material.dart';
import 'package:memex/data/services/ai_purchase_service.dart';
import 'package:memex/data/services/remote_task_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

/// Settings page for the autonomous shopping feature.
///
/// The user configures budget limits here. The AI cannot modify these values
/// via tools — they are user-only controls to maintain safety.
class ShoppingConfigPage extends StatefulWidget {
  const ShoppingConfigPage({super.key});

  @override
  State<ShoppingConfigPage> createState() => _ShoppingConfigPageState();
}

class _ShoppingConfigPageState extends State<ShoppingConfigPage> {
  late final AiPurchaseService _svc;
  late final RemoteTaskService _remoteSvc;

  bool _enabled = false;
  double _perTxLimit = 50.0;
  double _cumulativeLimit = 200.0;
  double _cumulativeSpent = 0.0;
  String _paymentMode = 'manual_approval';
  bool _loading = true;

  // Supabase bridge config
  String _supabaseUrl = '';
  String _supabaseKey = '';
  bool _obscureKey = true;
  bool _testingConnection = false;
  String? _connectionStatus; // null=untested, ''=ok, else=error

  final _perTxCtrl = TextEditingController();
  final _cumulativeCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _svc = AiPurchaseService(db: AppDatabase.instance);
    _remoteSvc = RemoteTaskService(db: AppDatabase.instance);
    _load();
  }

  @override
  void dispose() {
    _perTxCtrl.dispose();
    _cumulativeCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await _svc.getBudgetStatus();
    final remoteCfg = await _remoteSvc.getConfig();
    setState(() {
      _enabled = status['enabled'] as bool;
      _perTxLimit = status['per_tx_limit_cny'] as double;
      _cumulativeLimit = status['cumulative_limit_cny'] as double;
      _cumulativeSpent = status['cumulative_spent_cny'] as double;
      _paymentMode = status['payment_mode'] as String;
      _perTxCtrl.text = _perTxLimit.toStringAsFixed(0);
      _cumulativeCtrl.text = _cumulativeLimit.toStringAsFixed(0);
      _supabaseUrl = remoteCfg.baseUrl;
      _supabaseKey = remoteCfg.anonKey;
      _urlCtrl.text = _supabaseUrl;
      _keyCtrl.text = _supabaseKey;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final perTx = double.tryParse(_perTxCtrl.text) ?? _perTxLimit;
    final cum = double.tryParse(_cumulativeCtrl.text) ?? _cumulativeLimit;
    await Future.wait([
      _svc.configureBudget(
        enabled: _enabled,
        perTxLimitCny: perTx,
        cumulativeLimitCny: cum,
        paymentMode: _paymentMode,
      ),
      _remoteSvc.saveConfig(
        baseUrl: _urlCtrl.text.trim(),
        anonKey: _keyCtrl.text.trim(),
      ),
    ]);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
    await _load();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _connectionStatus = null;
    });
    // Save current input first so testConnection reads the latest values.
    await _remoteSvc.saveConfig(
      baseUrl: _urlCtrl.text.trim(),
      anonKey: _keyCtrl.text.trim(),
    );
    final err = await _remoteSvc.testConnection();
    if (mounted) {
      setState(() {
        _testingConnection = false;
        _connectionStatus = err ?? '';
      });
    }
  }

  Future<void> _resetSpent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置累计消费'),
        content: const Text('将累计已花费金额归零，相当于重新充值额度。确认？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认重置')),
        ],
      ),
    );
    if (confirm == true) {
      await _svc.resetCumulativeSpent();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpringRainUiTokens.daylightSurfaceMuted,
      appBar: AppBar(
        title: const Text('购物助手'),
        backgroundColor: SpringRainUiTokens.daylightSurface,
        foregroundColor: SpringRainUiTokens.daylightTextPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card([
                  _sectionTitle('功能开关'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用自主购物'),
                    subtitle: const Text('开启后 AI 伴侣可在你授权的预算内自主下单'),
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    activeColor: SpringRainUiTokens.daylightAccent,
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('预算限制'),
                  const SizedBox(height: 8),
                  _field(
                    label: '单笔上限（元）',
                    hint: '50',
                    controller: _perTxCtrl,
                    enabled: _enabled,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    label: '累计额度（元）',
                    hint: '200',
                    controller: _cumulativeCtrl,
                    enabled: _enabled,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('已花费：¥${_cumulativeSpent.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 14, color: SpringRainUiTokens.daylightTextTertiary)),
                            Text(
                                '剩余：¥${(_cumulativeLimit - _cumulativeSpent).clamp(0, double.infinity).toStringAsFixed(2)}',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: SpringRainUiTokens.daylightAccent,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _resetSpent,
                        child: const Text('重置额度'),
                      ),
                    ],
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('付款方式'),
                  _PaymentModeOption(
                    label: '审批式（推荐）',
                    subtitle: 'AI 生成收银台链接后推送给你，你点一次「授权付款」',
                    value: 'manual_approval',
                    selected: _paymentMode == 'manual_approval',
                    enabled: _enabled,
                    onTap: _enabled
                        ? () => setState(() => _paymentMode = 'manual_approval')
                        : null,
                  ),
                  _PaymentModeOption(
                    label: '惊喜式（coming soon）',
                    subtitle: '免密额度内自动放行，无需确认（支付宝免密支付开通后可用）',
                    value: 'auto_silent',
                    selected: _paymentMode == 'auto_silent',
                    enabled: false,
                    onTap: null,
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Hermes 桥接（自动下单）'),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '配置后，AI 伴侣下单时会把任务推送给电脑端 Hermes Agent，由它自动完成淘宝下单和支付宝收银台生成。\n'
                      '留空则退回到"你手动下单、把收银台链接发给我"的半自动模式。',
                      style: TextStyle(fontSize: 13, color: SpringRainUiTokens.daylightTextTertiary),
                    ),
                  ),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Supabase URL',
                      hintText: 'https://xxxx.supabase.co',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _connectionStatus = null),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: _obscureKey,
                    decoration: InputDecoration(
                      labelText: 'Supabase Anon Key',
                      hintText: 'eyJhbGci...',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    onChanged: (_) => setState(() => _connectionStatus = null),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _testingConnection ? null : _testConnection,
                        icon: _testingConnection
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('测试连接'),
                      ),
                      const SizedBox(width: 12),
                      if (_connectionStatus != null)
                        Expanded(
                          child: _connectionStatus!.isEmpty
                              ? const Row(children: [
                                  Icon(Icons.check_circle,
                                      color: SpringRainUiTokens.daylightSuccess, size: 16),
                                  SizedBox(width: 4),
                                  Text('连接成功',
                                      style: TextStyle(
                                          color: SpringRainUiTokens.daylightSuccess, fontSize: 13)),
                                ])
                              : Row(
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: SpringRainUiTokens.daylightError, size: 16),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        _connectionStatus!,
                                        style: const TextStyle(
                                            color: SpringRainUiTokens.daylightError, fontSize: 12),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                    ],
                  ),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SpringRainUiTokens.daylightSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: SpringRainUiTokens.daylightTextSecondary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: SpringRainUiTokens.daylightTextPrimary)),
      );

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool enabled,
  }) =>
      TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixText: '¥ ',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}

class _PaymentModeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final String value;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _PaymentModeOption({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Radio<bool>(
        value: true,
        groupValue: selected ? true : false,
        onChanged: enabled && onTap != null ? (_) => onTap!() : null,
        activeColor: SpringRainUiTokens.daylightAccent,
      ),
      title: Text(label, style: TextStyle(color: enabled ? null : SpringRainUiTokens.daylightTextTertiary)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: SpringRainUiTokens.daylightTextTertiary)),
      onTap: onTap,
    );
  }
}
