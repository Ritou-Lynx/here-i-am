import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/magic_motion_toy_controller.dart';
import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

/// Settings page for configuring toy control through Intiface Central.
///
/// Direct BLE writes are intentionally disabled here. Previous direct-control
/// experiments caused hardware damage, so unsupported devices should be
/// investigated through logs and vendor/protocol documentation before any app
/// code writes to BLE characteristics.
class ToyConfigPage extends StatefulWidget {
  const ToyConfigPage({super.key});

  @override
  State<ToyConfigPage> createState() => _ToyConfigPageState();
}

class _ToyConfigPageState extends State<ToyConfigPage> {
  final _ipController = TextEditingController();
  bool _isTesting = false;
  String? _statusMessage;
  bool _statusOk = true;
  ToyConfig? _savedConfig;
  bool _autoConnect = false;

  static const _defaultPort = '12345';

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final config = await ToyConfig.load();
    if (!mounted) return;

    if (config?.protocol == ToyProtocol.magicMotion) {
      await ToyConfig.clear();
      await clearMagicMotionDevice();
      setState(() {
        _savedConfig = null;
        _statusOk = false;
        _statusMessage = '已移除旧的蓝牙直连配置。这个入口已禁用，避免误写 BLE 控制通道。';
      });
      return;
    }

    if (config?.protocol == ToyProtocol.buttplug) {
      final uri = Uri.tryParse(config!.url);
      if (uri != null) _ipController.text = uri.host;
    }

    setState(() {
      _savedConfig = config;
      _autoConnect = config?.autoConnect ?? false;
    });
  }

  String _buildWsUrl(String ip) {
    final trimmed = ip.trim();
    if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
      return trimmed;
    }
    return 'ws://$trimmed:$_defaultPort';
  }

  Future<void> _testAndSaveIntiface() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _statusOk = false;
        _statusMessage = '请输入 Intiface 的局域网 IP 地址。';
      });
      return;
    }

    final wsUrl = _buildWsUrl(ip);
    final controller = ButtplugToyController(wsUrl: wsUrl);
    setState(() {
      _isTesting = true;
      _statusMessage = '正在连接 $wsUrl ...';
      _statusOk = true;
    });

    try {
      await controller.connect().timeout(const Duration(seconds: 8));
      await ToyConfig.save(
        protocol: ToyProtocol.buttplug,
        url: wsUrl,
        autoConnect: _autoConnect,
      );
      await clearMagicMotionDevice();
      await _loadSaved();

      var commandOk = false;
      if (controller.isReady) {
        commandOk = await controller
            .vibrate(6, durationSeconds: 1)
            .timeout(const Duration(seconds: 6), onTimeout: () => false);
        await Future.delayed(const Duration(milliseconds: 1300));
        await controller.stop().timeout(
              const Duration(seconds: 6),
              onTimeout: () => false,
            );
      }

      setState(() {
        _statusOk = controller.isReady;
        final diagnostic = '\n\n诊断信息：\n${controller.diagnosticSummary}';
        _statusMessage = controller.isReady
            ? commandOk
                ? 'Intiface 已连接，设备已暴露，ScalarCmd 已被服务器接受。\n'
                    '如果玩具仍然没动，问题在 Intiface 的设备协议/硬件映射，不在 Memex 到 Intiface 的连接。'
                    '$diagnostic'
                : 'Intiface 已连接并发现设备，但 ScalarCmd 没有被服务器确认。\n'
                    '请查看 Intiface 日志里的 Error / ScalarCmd 回包。'
                    '$diagnostic'
            : '已连接 Intiface，但它没有发现可控设备。\n'
                '这通常对应日志里的 No viable protocols：设备被扫描到，但没有匹配协议。'
                '请不要改用蓝牙直连；下一步应继续抓 Intiface/系统蓝牙日志。'
                '$diagnostic';
      });
    } on TimeoutException {
      setState(() {
        _statusOk = false;
        _statusMessage = '连接超时。请确认 Intiface 已点 Start Server，手机和电脑在同一网络。';
      });
    } catch (e) {
      setState(() {
        _statusOk = false;
        _statusMessage = '连接失败：$e';
      });
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _clear() async {
    await ToyConfig.clear();
    await clearMagicMotionDevice();
    _ipController.clear();
    setState(() {
      _savedConfig = null;
      _autoConnect = false;
      _statusMessage = null;
    });
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除')));
    }
  }

  @override
  void dispose() {
    _ipController.dispose();
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
          if (_savedConfig != null) ...[
            _currentConfigCard(),
            const SizedBox(height: 16),
          ],
          _safetyCard(),
          const SizedBox(height: 16),
          if (_statusMessage != null) ...[
            _statusBox(),
            const SizedBox(height: 16),
          ],
          _intifaceCard(),
          const SizedBox(height: 16),
          _diagnosticCard(),
        ],
      ),
    );
  }

  Widget _currentConfigCard() {
    return _card(
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已配置：Intiface',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _savedConfig!.url,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _isTesting ? null : _clear,
            style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  Widget _safetyCard() {
    return _card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '蓝牙直连已禁用。当前只通过 Intiface/Buttplug 发送控制命令。'
              '如果 Intiface 日志显示 No viable protocols，表示还没有安全可用的协议匹配，'
              '不应该继续尝试手动写 BLE 特征值。',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _intifaceCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Intiface 连接'),
          const SizedBox(height: 6),
          Text(
            '手机上的 App 只连接 Intiface。设备能不能动，取决于 Intiface 是否把它识别成可控设备。',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ipController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: '例：192.168.1.100',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              prefixText: 'ws://',
              prefixStyle:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14),
              suffixText: ':$_defaultPort',
              suffixStyle:
                  TextStyle(color: AppColors.textSecondary, fontSize: 14),
              filled: true,
              fillColor: AppColors.background,
              border: _inputBorder(),
              enabledBorder: _inputBorder(),
              focusedBorder: _inputBorder(color: AppColors.primary, width: 2),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _autoConnect,
            onChanged: _isTesting
                ? null
                : (value) async {
                    setState(() => _autoConnect = value);
                    final config = _savedConfig;
                    if (config == null) return;
                    await ToyConfig.save(
                      protocol: config.protocol,
                      url: config.url,
                      autoConnect: value,
                    );
                    await _loadSaved();
                  },
            contentPadding: EdgeInsets.zero,
            title: Text(
              '进入聊天时自动连接',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              '关闭后不会在聊天页自动启动 Intiface / 蓝牙扫描。',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testAndSaveIntiface,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.wifi_tethering, size: 18),
              label: Text(_isTesting ? '连接中...' : '测试 Intiface'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _statusOk
            ? Colors.green.withValues(alpha: 0.08)
            : Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _statusOk
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        _statusMessage!,
        style: TextStyle(
          fontSize: 13,
          color: _statusOk ? Colors.green[700] : Colors.orange[700],
          height: 1.5,
        ),
      ),
    );
  }

  Widget _diagnosticCard() {
    return _card(
      child: Text(
        '下一步诊断重点：Intiface 的协议匹配名、No viable protocols 的完整 specifier、'
        '以及系统蓝牙日志里的服务和特征值列表。只有确认协议后，才能安全地新增支持。',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
          height: 1.6,
        ),
      ),
    );
  }

  OutlineInputBorder _inputBorder({
    Color? color,
    double width = 1,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide:
          BorderSide(color: color ?? AppColors.textTertiary, width: width),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
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
}
