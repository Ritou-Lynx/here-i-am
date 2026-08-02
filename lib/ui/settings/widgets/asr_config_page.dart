import 'package:flutter/material.dart';
import 'package:memex/data/services/asr/asr_config.dart';
import 'package:memex/data/services/voice_session_router.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Configure Alibaba NLS credentials for voice input.
///
/// Stored in SharedPreferences via [AsrConfig]. No validation against the
/// service is performed here — first real recognition attempt surfaces auth
/// errors as a snackbar in the chat screen.
class AsrConfigPage extends StatefulWidget {
  const AsrConfigPage({super.key});

  @override
  State<AsrConfigPage> createState() => _AsrConfigPageState();
}

class _AsrConfigPageState extends State<AsrConfigPage> {
  final _accessKeyIdCtl = TextEditingController();
  final _accessKeySecretCtl = TextEditingController();
  final _appKeyCtl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _secretVisible = false;
  bool _useMediaKeys = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cfg = await AsrConfig.load();
    final useMediaKeys = await AsrConfig.getUseMediaKeys();
    if (!mounted) return;
    if (cfg != null) {
      _accessKeyIdCtl.text = cfg.accessKeyId;
      _accessKeySecretCtl.text = cfg.accessKeySecret;
      _appKeyCtl.text = cfg.appKey;
    }
    setState(() {
      _useMediaKeys = useMediaKeys;
      _loading = false;
    });
  }

  Future<void> _setUseMediaKeys(bool value) async {
    setState(() => _useMediaKeys = value);
    await AsrConfig.setUseMediaKeys(value);
    // 开关变化即时生效：开启时接管媒体键，关闭时释放。
    await VoiceSessionRouter.instance.syncFromSettings();
  }

  Future<void> _save() async {
    final id = _accessKeyIdCtl.text.trim();
    final secret = _accessKeySecretCtl.text.trim();
    final appKey = _appKeyCtl.text.trim();
    if (id.isEmpty || secret.isEmpty || appKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('三项都要填')),
      );
      return;
    }
    setState(() => _saving = true);
    await AsrConfig.save(
      accessKeyId: id,
      accessKeySecret: secret,
      appKey: appKey,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存')),
    );
  }

  Future<void> _clear() async {
    await AsrConfig.clear();
    if (!mounted) return;
    _accessKeyIdCtl.clear();
    _accessKeySecretCtl.clear();
    _appKeyCtl.clear();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清除')),
    );
  }

  @override
  void dispose() {
    _accessKeyIdCtl.dispose();
    _accessKeySecretCtl.dispose();
    _appKeyCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('语音输入（阿里 NLS）'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7E6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFE7B0)),
                    ),
                    child: const Text(
                      '在阿里云 NLS 控制台创建项目，获取 AppKey；在 RAM 控制台为账号创建 AccessKey（推荐子账号，赋予 AliyunNLSFullAccess）。',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _field(
                    label: 'AccessKey ID',
                    controller: _accessKeyIdCtl,
                  ),
                  const SizedBox(height: 16),
                  _field(
                    label: 'AccessKey Secret',
                    controller: _accessKeySecretCtl,
                    obscure: !_secretVisible,
                    trailing: IconButton(
                      icon: Icon(_secretVisible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _secretVisible = !_secretVisible),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _field(
                    label: 'AppKey（项目级）',
                    controller: _appKeyCtl,
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(_saving ? '保存中…' : '保存'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: _saving ? null : _clear,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _useMediaKeys,
                    onChanged: _setUseMediaKeys,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用媒体键语音对话'),
                    subtitle: const Text(
                      '开启后：聊天页内耳机中键 = 录音开关；离开聊天页或 App 退到后台后，点按耳机键开始录音、再点按发送并收到语音回复（半双工语音对话）。上一曲键取消。',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '提示：在 companion 聊天页输入框旁会出现麦克风按钮；蓝牙翻页器在「翻页模式」下用 PageDown 开启/结束录音，PageUp 取消。',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.5),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool obscure = false,
    Widget? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            suffixIcon: trailing,
          ),
        ),
      ],
    );
  }
}