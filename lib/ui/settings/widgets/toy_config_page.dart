import 'package:flutter/material.dart';
import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/toy_control_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Settings page for Intiface Central (Buttplug.io) integration.
///
/// Supports Magic Motion, We-Vibe, Satisfyer, and dozens of other brands
/// available in China — anything Intiface Central can pair with.
class ToyConfigPage extends StatefulWidget {
  const ToyConfigPage({super.key});

  @override
  State<ToyConfigPage> createState() => _ToyConfigPageState();
}

class _ToyConfigPageState extends State<ToyConfigPage> {
  final _urlController = TextEditingController(text: 'ws://127.0.0.1:12345');
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ToyConfig.load();
    if (config != null && mounted) {
      setState(() => _urlController.text = config.url);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    await ToyConfig.save(
      protocol: ToyProtocol.buttplug,
      url: _urlController.text.trim(),
    );
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已保存')));
    }
  }

  Future<void> _test() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    final ctrl = ButtplugToyController(wsUrl: url);
    try {
      await ctrl.connect();
      if (ctrl.isReady) {
        setState(() {
          _testOk = true;
          _testResult = '连接成功！已检测到玩具，可以开始使用 🎉';
        });
      } else {
        setState(() {
          _testOk = true;
          _testResult = '连接成功，但暂未检测到玩具\n'
              '请确认：\n'
              '• 玩具已开机\n'
              '• 已在 Intiface Central 里扫描并连接';
        });
      }
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = '连接失败：$e\n\n请确认 Intiface Central 已经点击 Start Server';
      });
    } finally {
      ctrl.dispose();
      setState(() => _isTesting = false);
    }
  }

  Future<void> _clear() async {
    await ToyConfig.clear();
    _urlController.text = 'ws://127.0.0.1:12345';
    setState(() => _testResult = null);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除')));
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('玩具控制'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Step-by-step guide
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('使用前准备'),
                const SizedBox(height: 12),
                _step('1', '在手机安装 Intiface Central\n（Google Play 搜索，或下载 APK）'),
                _step('2', '打开玩具品牌官方 App（如 Magic Motion），完成蓝牙配对'),
                _step('3', '打开 Intiface Central → Start Server → 点扫描，玩具出现在列表'),
                _step('4', '回到这里，地址保持默认，点测试连接'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Supported brands
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionTitle('支持品牌（部分）'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    'Magic Motion',
                    'We-Vibe',
                    'Satisfyer',
                    'Lovense',
                    'Kiiroo',
                    'LELO',
                    'Hot Octopuss',
                    '及更多...',
                  ].map((name) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // URL input
          Text(
            'Intiface 地址',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '通常不需要修改，保持默认即可',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'ws://127.0.0.1:12345',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 16),

          // Test result
          if (_testResult != null)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _testOk
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _testOk
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  fontSize: 13,
                  color: _testOk ? Colors.green[700] : Colors.red[700],
                  height: 1.6,
                ),
              ),
            ),

          // Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isTesting ? null : _test,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('保存'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _clear,
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除配置'),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.textSecondary.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          fontSize: 14,
        ),
      );

  Widget _step(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              margin: const EdgeInsets.only(top: 1, right: 10),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  num,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      );
}
