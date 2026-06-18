import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/services/buttplug_toy_controller.dart';
import 'package:memex/data/services/magic_motion_flamingo_controller.dart';
import 'package:memex/data/services/svakom_toy_controller.dart';
import 'package:memex/data/services/toy_controller.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:permission_handler/permission_handler.dart';

class ToyConfigPage extends StatefulWidget {
  const ToyConfigPage({super.key});

  @override
  State<ToyConfigPage> createState() => _ToyConfigPageState();
}

class _ToyConfigPageState extends State<ToyConfigPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController; // 3 tabs: Intiface, Svakom, Flamingo

  // ── Intiface tab state ──
  final _ipController = TextEditingController();
  bool _isTesting = false;
  String? _intifaceStatus;
  bool _intifaceOk = true;
  ToyConfig? _savedIntifaceConfig;

  // ── Svakom tab state ──
  bool _isScanningSvakom = false;
  List<SvakomScanResult> _foundSvakom = [];
  ({String id, String name})? _savedSvakom;
  StreamSubscription? _scanSubSvakom;
  String? _svakomStatus;
  bool _svakomStatusOk = true;

  // ── Flamingo tab state ──
  bool _isScanningFlamingo = false;
  List<FlamingoScanResult> _foundFlamingo = [];
  ({String id, String name})? _savedFlamingo;
  StreamSubscription? _scanSubFlamingo;
  String? _flamingoStatus;
  bool _flamingoStatusOk = true;
  bool _isTestingFlamingo = false;
  String? _flamingoTestResult;
  bool _flamingoTestOk = true;

  static const _defaultPort = '12345';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final intifaceConfig = await ToyConfig.load();
    final svakomDevice = await loadSvakomDevice();
    final flamingoDevice = await loadFlamingoDevice();
    if (!mounted) return;
    setState(() {
      _savedIntifaceConfig = intifaceConfig?.protocol == ToyProtocol.buttplug
          ? intifaceConfig
          : null;
      if (intifaceConfig != null &&
          intifaceConfig.protocol == ToyProtocol.buttplug) {
        final uri = Uri.tryParse(intifaceConfig.url);
        if (uri != null) _ipController.text = uri.host;
      }
      _savedSvakom = svakomDevice;
      _savedFlamingo = flamingoDevice;
    });
  }

  // ── Intiface ──────────────────────────────────────────────────────────────

  String _buildWsUrl(String ip) {
    final trimmed = ip.trim();
    if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
      return trimmed;
    }
    return 'ws://$trimmed:$_defaultPort';
  }

  Future<void> _testIntiface() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _intifaceOk = false;
        _intifaceStatus = '请输入电脑的局域网 IP 地址';
      });
      return;
    }
    final wsUrl = _buildWsUrl(ip);
    setState(() {
      _isTesting = true;
      _intifaceStatus = '正在连接 $wsUrl ...';
      _intifaceOk = true;
    });

    final controller = ButtplugToyController(wsUrl: wsUrl);
    try {
      await controller.connect().timeout(const Duration(seconds: 8));
      await ToyConfig.save(protocol: ToyProtocol.buttplug, url: wsUrl);
      await clearSvakomDevice();
      await clearFlamingoDevice();
      await _loadSaved();
      setState(() {
        _intifaceOk = true;
        _intifaceStatus = controller.isReady
            ? '连接成功，已发现设备 ✓\n回到聊天页即可使用'
            : '已连接 Intiface 服务器 ✓\n请确认玩具已开机且 Intiface 中能看到它';
      });
    } on TimeoutException {
      setState(() {
        _intifaceOk = false;
        _intifaceStatus =
            '连接超时\n请确认：\n1. Intiface 已开启 Start Server\n2. 手机和电脑在同一 WiFi\n3. IP 地址正确';
      });
    } catch (e) {
      setState(() {
        _intifaceOk = false;
        _intifaceStatus = '连接失败：$e';
      });
    } finally {
      controller.dispose();
      if (mounted) setState(() => _isTesting = false);
    }
  }

  Future<void> _clearIntiface() async {
    await ToyConfig.clear();
    _ipController.clear();
    setState(() {
      _savedIntifaceConfig = null;
      _intifaceStatus = null;
    });
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除')));
  }

  // ── Svakom BLE ────────────────────────────────────────────────────────────

  Future<void> _scanSvakom() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !connect.isGranted) {
      setState(() {
        _svakomStatusOk = false;
        _svakomStatus = '需要蓝牙权限，请在系统设置里允许「附近的设备」';
      });
      return;
    }
    setState(() {
      _isScanningSvakom = true;
      _foundSvakom = [];
      _svakomStatus = null;
    });
    _scanSubSvakom?.cancel();
    _scanSubSvakom = scanForSvakom(timeout: const Duration(seconds: 10)).listen(
      (results) {
        if (mounted) setState(() => _foundSvakom = results);
      },
      onDone: () {
        if (mounted)
          setState(() {
            _isScanningSvakom = false;
            if (_foundSvakom.isEmpty) {
              _svakomStatusOk = false;
              _svakomStatus = '没有找到 Svakom 设备\n请确认玩具已开机';
            }
          });
      },
      onError: (e) {
        if (mounted)
          setState(() {
            _isScanningSvakom = false;
            _svakomStatusOk = false;
            _svakomStatus = '扫描出错：$e';
          });
      },
    );
  }

  Future<void> _stopScanSvakom() async {
    _scanSubSvakom?.cancel();
    setState(() => _isScanningSvakom = false);
  }

  Future<void> _connectSvakom(SvakomScanResult result) async {
    await _stopScanSvakom();
    setState(() {
      _svakomStatusOk = true;
      _svakomStatus = '正在连接 ${result.name}…';
    });
    final ctrl =
        SvakomToyController(deviceId: result.deviceId, deviceName: result.name);
    try {
      await ctrl.connect().timeout(const Duration(seconds: 10));
      if (ctrl.isReady) {
        await saveSvakomDevice(result.deviceId, result.name);
        await ToyConfig.clear();
        await clearFlamingoDevice();
        await _loadSaved();
        setState(() {
          _svakomStatusOk = true;
          _svakomStatus = '已连接 ✓  回到聊天页即可使用';
        });
      } else {
        setState(() {
          _svakomStatusOk = false;
          _svakomStatus = '连接上了但找不到控制特征，可能型号不兼容';
        });
      }
    } catch (e) {
      setState(() {
        _svakomStatusOk = false;
        _svakomStatus = '连接失败：$e';
      });
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _clearSvakom() async {
    await clearSvakomDevice();
    setState(() {
      _savedSvakom = null;
      _foundSvakom = [];
      _svakomStatus = null;
    });
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除')));
  }

  // ── Flamingo BLE ──────────────────────────────────────────────────────────

  Future<void> _scanFlamingo() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !connect.isGranted) {
      setState(() {
        _flamingoStatusOk = false;
        _flamingoStatus = '需要蓝牙权限，请在系统设置里允许「附近的设备」';
      });
      return;
    }
    setState(() {
      _isScanningFlamingo = true;
      _foundFlamingo = [];
      _flamingoStatus = null;
    });
    _scanSubFlamingo?.cancel();
    _scanSubFlamingo =
        scanForFlamingo(timeout: const Duration(seconds: 10)).listen(
      (results) {
        if (mounted) setState(() => _foundFlamingo = results);
      },
      onDone: () {
        if (mounted)
          setState(() {
            _isScanningFlamingo = false;
            if (_foundFlamingo.isEmpty) {
              _flamingoStatusOk = false;
              _flamingoStatus = '没有找到 Flamingo 设备\n请确认玩具已开机';
            }
          });
      },
      onError: (e) {
        if (mounted)
          setState(() {
            _isScanningFlamingo = false;
            _flamingoStatusOk = false;
            _flamingoStatus = '扫描出错：$e';
          });
      },
    );
  }

  Future<void> _stopScanFlamingo() async {
    _scanSubFlamingo?.cancel();
    setState(() => _isScanningFlamingo = false);
  }

  Future<void> _connectFlamingo(FlamingoScanResult result) async {
    await _stopScanFlamingo();
    setState(() {
      _flamingoStatusOk = true;
      _flamingoStatus = '正在连接 ${result.name}…';
    });
    final ctrl = MagicMotionFlamingoController(
        deviceId: result.deviceId, deviceName: result.name);
    try {
      await ctrl.connect().timeout(const Duration(seconds: 10));
      if (ctrl.isReady) {
        await saveFlamingoDevice(result.deviceId, result.name);
        await ToyConfig.clear();
        await clearSvakomDevice();
        await _loadSaved();
        setState(() {
          _flamingoStatusOk = true;
          _flamingoStatus = '已连接 ✓  回到聊天页即可使用';
        });
      } else {
        setState(() {
          _flamingoStatusOk = false;
          _flamingoStatus = '连接上了但找不到控制特征';
        });
      }
    } catch (e) {
      setState(() {
        _flamingoStatusOk = false;
        _flamingoStatus = '连接失败：$e';
      });
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _clearFlamingo() async {
    await clearFlamingoDevice();
    setState(() {
      _savedFlamingo = null;
      _foundFlamingo = [];
      _flamingoStatus = null;
      _flamingoTestResult = null;
    });
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已清除')));
  }

  /// Directly tests BLE vibration — bypasses the AI, verifies command format.
  Future<void> _testFlamingo() async {
    final saved = _savedFlamingo;
    if (saved == null) return;
    setState(() {
      _isTestingFlamingo = true;
      _flamingoTestResult = '正在连接 ${saved.name}…';
      _flamingoTestOk = true;
    });
    final ctrl = MagicMotionFlamingoController(
      deviceId: saved.id,
      deviceName: saved.name,
    );
    try {
      await ctrl.connect().timeout(const Duration(seconds: 10));
      if (!ctrl.isReady) {
        setState(() {
          _flamingoTestOk = false;
          _flamingoTestResult = '连接成功但找不到写入特征';
        });
        return;
      }
      setState(() => _flamingoTestResult = '已连接，发送振动命令…');
      final ok = await ctrl.vibrate(10, durationSeconds: 2);
      if (ok) {
        await saveFlamingoDevice(saved.id, saved.name);
        await ToyConfig.clear();
        await clearSvakomDevice();
        await _loadSaved();
        setState(() {
          _flamingoTestOk = true;
          _flamingoTestResult = '✓ 振动命令已发送，玩具应该动了\n如果没动，请截图反馈（命令格式需调整）';
        });
        await Future.delayed(const Duration(seconds: 2));
        await ctrl.stop();
      } else {
        setState(() {
          _flamingoTestOk = false;
          _flamingoTestResult = '✗ 振动命令写入失败\n可能是命令格式或 BLE 写入权限问题';
        });
      }
    } on TimeoutException {
      setState(() {
        _flamingoTestOk = false;
        _flamingoTestResult = '连接超时，请确认玩具已开机且在蓝牙范围内';
      });
    } catch (e) {
      setState(() {
        _flamingoTestOk = false;
        _flamingoTestResult = '测试失败：$e';
      });
    } finally {
      ctrl.dispose();
      if (mounted) setState(() => _isTestingFlamingo = false);
    }
  }

  @override
  void dispose() {
    _scanSubSvakom?.cancel();
    _scanSubFlamingo?.cancel();
    _ipController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('玩具控制'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Intiface'),
            Tab(text: 'Svakom'),
            Tab(text: 'Flamingo'),
          ],
        ),
      ),
      backgroundColor: AppColors.background,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildIntifaceTab(),
          _buildSvakomTab(),
          _buildFlamingoTab(),
        ],
      ),
    );
  }

  // ── Intiface tab ──────────────────────────────────────────────────────────

  Widget _buildIntifaceTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_savedIntifaceConfig != null) ...[
          _card(
              child: Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('已配置',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(_savedIntifaceConfig!.url,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                          fontSize: 13)),
                ])),
            TextButton(
                onPressed: _clearIntiface,
                style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
                child: const Text('清除')),
          ])),
          const SizedBox(height: 16),
        ],
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('使用方法'),
          const SizedBox(height: 10),
          _step('1', '电脑上打开 Intiface Central，点 Start Server'),
          _step('2', '开机玩具，等 Intiface 扫描到设备'),
          _step('3', '在下方输入电脑的局域网 IP 地址'),
          _step('4', '点「测试连接」，成功后回到聊天页即可'),
        ])),
        const SizedBox(height: 20),
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('Intiface 服务器地址'),
          const SizedBox(height: 4),
          Text('手机和电脑需在同一 WiFi 下',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.textTertiary)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.textTertiary)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ])),
        const SizedBox(height: 16),
        if (_intifaceStatus != null) _statusBox(_intifaceStatus!, _intifaceOk),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testIntiface,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.wifi_tethering, size: 20),
              label: Text(_isTesting ? '连接中...' : '测试连接'),
            )),
        const SizedBox(height: 24),
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('兼容设备'),
          const SizedBox(height: 8),
          Text(
              '仅用于能被 Intiface Central 发现的设备。\nFlamingo Max 和 Svakom 请使用各自的直连标签页。',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
        ])),
      ],
    );
  }

  // ── Svakom tab ────────────────────────────────────────────────────────────

  Widget _buildSvakomTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_savedSvakom != null) ...[
          _card(
              child: Row(children: [
            const Icon(Icons.bluetooth_connected,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('已配对',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(_savedSvakom!.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ])),
            TextButton(
                onPressed: _clearSvakom,
                style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
                child: const Text('解除')),
          ])),
          const SizedBox(height: 16),
        ],
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('使用方法'),
          const SizedBox(height: 10),
          _step('1', '开机玩具（长按开关，指示灯闪烁）'),
          _step('2', '点「扫描设备」'),
          _step('3', '在列表里点你的设备配对'),
          _step('4', '配对成功后回到聊天页即可'),
        ])),
        const SizedBox(height: 16),
        if (_svakomStatus != null) _statusBox(_svakomStatus!, _svakomStatusOk),
        if (_foundSvakom.isNotEmpty) ...[
          Text('发现的设备',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          ..._foundSvakom
              .map((r) => _deviceTile(r.name, r.rssi, () => _connectSvakom(r))),
          const SizedBox(height: 12),
        ],
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanningSvakom ? _stopScanSvakom : _scanSvakom,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isScanningSvakom ? Colors.red[400] : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isScanningSvakom
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bluetooth_searching, size: 20),
              label: Text(_isScanningSvakom ? '停止扫描' : '扫描设备'),
            )),
        const SizedBox(height: 16),
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('兼容型号'),
          const SizedBox(height: 8),
          Text('司沃康（Svakom）全系列蓝牙产品\n直连无需 Intiface，延迟更低',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
        ])),
      ],
    );
  }

  Widget _buildFlamingoTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_savedFlamingo != null) ...[
          _card(
              child: Row(children: [
            const Icon(Icons.bluetooth_connected,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('已配对',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(_savedFlamingo!.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ])),
            TextButton(
                onPressed: _clearFlamingo,
                style: TextButton.styleFrom(foregroundColor: Colors.red[400]),
                child: const Text('解除')),
          ])),
          const SizedBox(height: 10),
          if (_flamingoTestResult != null)
            _statusBox(_flamingoTestResult!, _flamingoTestOk),
          SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isTestingFlamingo ? null : _testFlamingo,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                icon: _isTestingFlamingo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.vibration, size: 18),
                label: Text(_isTestingFlamingo ? '测试中…' : '测试振动（2秒）'),
              )),
          const SizedBox(height: 16),
        ],
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('使用方法'),
          const SizedBox(height: 10),
          _step('1', '开机 Flamingo Max（指示灯闪烁）'),
          _step('2', '点「扫描设备」'),
          _step('3', '在列表里点你的设备配对'),
          _step('4', '配对成功后回到聊天页即可'),
        ])),
        const SizedBox(height: 16),
        if (_flamingoStatus != null)
          _statusBox(_flamingoStatus!, _flamingoStatusOk),
        if (_foundFlamingo.isNotEmpty) ...[
          Text('发现的设备',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          ..._foundFlamingo.map(
              (r) => _deviceTile(r.name, r.rssi, () => _connectFlamingo(r))),
          const SizedBox(height: 12),
        ],
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _isScanningFlamingo ? _stopScanFlamingo : _scanFlamingo,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isScanningFlamingo ? Colors.red[400] : AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _isScanningFlamingo
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.bluetooth_searching, size: 20),
              label: Text(_isScanningFlamingo ? '停止扫描' : '扫描设备'),
            )),
        const SizedBox(height: 16),
        _card(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle('兼容型号'),
          const SizedBox(height: 8),
          Text('Magic Motion Flamingo / Flamingo Max\n直连 BLE，无需 Intiface',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.6)),
        ])),
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _deviceTile(String name, int rssi, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                    color: AppColors.textSecondary.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            const Icon(Icons.vibration, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary)),
                  Text('信号强度 $rssi dBm',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ])),
            Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 20),
          ]),
        ),
      );

  Widget _statusBox(String msg, bool ok) => Container(
        padding: const EdgeInsets.all(14),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: ok
              ? Colors.green.withValues(alpha: 0.08)
              : Colors.orange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: ok
                  ? Colors.green.withValues(alpha: 0.3)
                  : Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Text(msg,
            style: TextStyle(
                fontSize: 13,
                color: ok ? Colors.green[700] : Colors.orange[700],
                height: 1.5)),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: AppColors.textSecondary.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 2))
            ]),
        child: child,
      );

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
          fontSize: 14));

  Widget _step(String num, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 1, right: 10),
              decoration: const BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: Center(
                  child: Text(num,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)))),
          Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5))),
        ]),
      );
}
