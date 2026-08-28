import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/user_storage.dart';

class HeartRateDeviceSettingsPage extends StatefulWidget {
  const HeartRateDeviceSettingsPage({super.key, this.gateway, this.userId});

  final BleHeartRateGateway? gateway;
  final String? userId;

  @override
  State<HeartRateDeviceSettingsPage> createState() =>
      _HeartRateDeviceSettingsPageState();
}

class _HeartRateDeviceSettingsPageState
    extends State<HeartRateDeviceSettingsPage> with WidgetsBindingObserver {
  late final BleHeartRateGateway _gateway;
  StreamSubscription<BleHeartRateGatewayEvent>? _subscription;
  BleHeartRateSnapshot _snapshot = BleHeartRateSnapshot.empty;
  Map<String, dynamic> _platformState = const {};
  final Map<String, BleHeartRateDevice> _devices = {};
  List<Map<String, dynamic>> _diagnostics = const [];
  String? _userId;
  String? _error;
  String _scanState = 'idle';
  bool _loading = true;
  bool _busy = false;
  bool _permissionRequestPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _gateway = widget.gateway ?? BleHeartRateGateway.instance;
    _subscription = _gateway.events.listen(
      _onEvent,
      onError: (Object error) {
        if (mounted) {
          setState(() => _error = '实时状态通道不可用：${_friendlyError(error)}');
        }
      },
    );
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAfterResume();
    }
  }

  Future<void> _refreshAfterResume() async {
    await _refresh();
    if (mounted && _permissionRequestPending) {
      setState(() => _permissionRequestPending = false);
    }
  }

  Future<void> _load() async {
    final userId = widget.userId ?? await UserStorage.getUserId();
    if (!mounted) return;
    if (userId == null || userId.isEmpty) {
      setState(() {
        _loading = false;
        _error = '尚未建立本机身份，暂时不能保存心率设备。';
      });
      return;
    }
    _userId = userId;
    await _refresh();
  }

  Future<void> _refresh() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final values = await Future.wait<dynamic>([
        _gateway.getSnapshot(userId),
        _gateway.getPlatformState(),
        _gateway.getRecentDiagnostics(userId),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = values[0] as BleHeartRateSnapshot;
        _platformState = values[1] as Map<String, dynamic>;
        _diagnostics = values[2] as List<Map<String, dynamic>>;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  void _onEvent(BleHeartRateGatewayEvent event) {
    if (!mounted) return;
    switch (event) {
      case BleHeartRateSnapshotEvent(:final snapshot):
        setState(() => _snapshot = snapshot);
        break;
      case BleHeartRateScanResultEvent(:final device):
        setState(() => _devices[device.deviceId] = device);
        break;
      case BleHeartRateScanStateEvent(:final state):
        setState(() => _scanState = state);
        break;
    }
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _permissionRequestPending = true;
      _error = null;
    });
    try {
      final opened = await _gateway.requestPermissions();
      if (!mounted) return;
      if (!opened) {
        setState(() => _permissionRequestPending = false);
        await _refresh();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _permissionRequestPending = false;
          _error = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _startScan() async {
    final userId = _userId;
    if (userId == null || _busy) return;
    setState(() {
      _devices.clear();
      _scanState = 'starting';
      _error = null;
    });
    try {
      await _gateway.startScan(userId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanState = 'failed';
          _error = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _select(BleHeartRateDevice device) async {
    final userId = _userId;
    if (userId == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await _gateway.selectAndEnable(userId, device);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final userId = _userId;
    if (userId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final snapshot = await _gateway.stop(userId);
      if (mounted) setState(() => _snapshot = snapshot);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget() async {
    final userId = _userId;
    if (userId == null || _busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('忘记这个心率设备？'),
        content: const Text('故我在会停止接收并移除本机保存的设备。系统蓝牙记录不会被修改。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止并忘记'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final snapshot = await _gateway.forget(userId);
      if (mounted) setState(() => _snapshot = snapshot);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    if (_scanState == 'scanning' || _scanState == 'starting') {
      unawaited(_gateway.stopScan());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.springRainUi;
    return Scaffold(
      key: const ValueKey('heart_rate_device_settings_page'),
      backgroundColor: tokens.canvas,
      appBar: AppBar(title: const Text('实时心率设备')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  tokens.space16,
                  tokens.space12,
                  tokens.space16,
                  tokens.space32,
                ),
                children: [
                  _statusCard(tokens),
                  if (_permissionRequestPending) ...[
                    SizedBox(height: tokens.space12),
                    _messageCard(
                      tokens,
                      '系统授权窗口已打开。返回故我在后会自动刷新；这里不会提前显示为已授权。',
                      Icons.hourglass_top_rounded,
                    ),
                  ],
                  if (_error != null) ...[
                    SizedBox(height: tokens.space12),
                    _messageCard(tokens, _error!, Icons.error_outline_rounded,
                        error: true),
                  ],
                  SizedBox(height: tokens.space20),
                  _actions(tokens),
                  SizedBox(height: tokens.space24),
                  _scanSection(tokens),
                  SizedBox(height: tokens.space24),
                  _diagnosticsSection(tokens),
                ],
              ),
            ),
    );
  }

  Widget _statusCard(SpringRainUiTokens tokens) {
    final sample = _snapshot.lastSample;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(tokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.favorite_rounded, color: tokens.error),
                SizedBox(width: tokens.space8),
                Expanded(
                  child: Text(
                    _snapshot.deviceName ?? '标准蓝牙心率设备',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _statusChip(tokens),
              ],
            ),
            SizedBox(height: tokens.space12),
            Text(
              sample == null ? _statusDescription : '${sample.bpm} BPM',
              key: const ValueKey('heart_rate_settings_primary_status'),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            SizedBox(height: tokens.space6),
            Text(
              sample == null
                  ? _statusDescription
                  : '最后样本 ${_formatTime(sample.timestamp)} · ${_snapshot.rrSeen ? '已收到 RR interval' : '尚未收到 RR interval'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_snapshot.notificationPermission == 'denied') ...[
              SizedBox(height: tokens.space8),
              Text(
                '通知权限未开启；Android 仍可能运行服务，但你看不到持续连接提示。',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(SpringRainUiTokens tokens) {
    final live = _snapshot.status == BleHeartRateStatus.live;
    return Container(
      key: const ValueKey('heart_rate_settings_status_chip'),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space8,
        vertical: tokens.space4,
      ),
      decoration: BoxDecoration(
        color: live ? tokens.successSoft : tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(tokens.radiusPill),
      ),
      child: Text(
        _statusLabel,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: live ? tokens.success : tokens.textSecondary,
            ),
      ),
    );
  }

  Widget _actions(SpringRainUiTokens tokens) {
    final permissionDenied = _platformState['permissionState'] != 'granted';
    final bluetoothOff = _platformState['bluetoothState'] == 'off';
    return Wrap(
      spacing: tokens.space8,
      runSpacing: tokens.space8,
      children: [
        if (permissionDenied)
          FilledButton.icon(
            key: const ValueKey('heart_rate_request_permission'),
            onPressed: _permissionRequestPending ? null : _requestPermissions,
            icon: const Icon(Icons.security_rounded),
            label: const Text('授权蓝牙'),
          ),
        if (bluetoothOff)
          OutlinedButton.icon(
            onPressed: _gateway.openBluetoothSettings,
            icon: const Icon(Icons.bluetooth_disabled_rounded),
            label: const Text('打开蓝牙设置'),
          ),
        if (_snapshot.configured && _snapshot.enabled)
          OutlinedButton.icon(
            onPressed: _busy ? null : _stop,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('停止接收'),
          ),
        if (_snapshot.configured)
          TextButton.icon(
            onPressed: _busy ? null : _forget,
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('忘记设备'),
          ),
        if (permissionDenied)
          TextButton(
            onPressed: _gateway.openAppSettings,
            child: const Text('应用权限设置'),
          ),
      ],
    );
  }

  Widget _scanSection(SpringRainUiTokens tokens) {
    final canScan = _platformState['supported'] == true &&
        _platformState['permissionState'] == 'granted' &&
        _platformState['bluetoothState'] == 'on';
    final scanning = _scanState == 'scanning' || _scanState == 'starting';
    final devices = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('附近的标准 HRS 设备',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('heart_rate_scan_button'),
              onPressed: canScan && !scanning && !_busy ? _startScan : null,
              icon: scanning
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bluetooth_searching_rounded),
              label: Text(scanning ? '扫描中' : '扫描 10 秒'),
            ),
          ],
        ),
        SizedBox(height: tokens.space8),
        Text(
          '只显示广播标准 Heart Rate Service（0x180D）的设备。扫描仅在你点击后进行。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_scanState == 'notFound') ...[
          SizedBox(height: tokens.space12),
          Text('未找到兼容设备。请唤醒臂带并保持在手机附近。',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
        for (final device in devices) ...[
          SizedBox(height: tokens.space8),
          Card(
            child: ListTile(
              key: ValueKey('heart_rate_device_${device.deviceId}'),
              leading: const Icon(Icons.favorite_border_rounded),
              title: Text(device.name),
              subtitle: Text('${device.deviceId} · ${device.rssi} dBm'),
              trailing: FilledButton(
                onPressed: _busy ? null : () => _select(device),
                child: const Text('选择并启用'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _diagnosticsSection(SpringRainUiTokens tokens) {
    return ExpansionTile(
      key: const ValueKey('heart_rate_recent_diagnostics'),
      tilePadding: EdgeInsets.zero,
      title: const Text('最近诊断'),
      subtitle: const Text('只含连接状态和原因，不含聊天或生活文本'),
      children: [
        if (_diagnostics.isEmpty)
          const ListTile(title: Text('暂无诊断记录'))
        else
          for (final item in _diagnostics.reversed.take(12))
            ListTile(
              dense: true,
              title: Text(item['status']?.toString() ?? 'unknown'),
              subtitle: Text(
                '${_formatTimestamp(item['timestampMs'])}${item['reason'] == null ? '' : ' · ${item['reason']}'}',
              ),
            ),
      ],
    );
  }

  Widget _messageCard(
    SpringRainUiTokens tokens,
    String message,
    IconData icon, {
    bool error = false,
  }) {
    return Container(
      padding: EdgeInsets.all(tokens.space12),
      decoration: BoxDecoration(
        color: error ? tokens.errorSoft : tokens.infoSoft,
        borderRadius: BorderRadius.circular(tokens.radius14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: error ? tokens.error : tokens.info),
          SizedBox(width: tokens.space8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }

  String get _statusLabel => switch (_snapshot.status) {
        BleHeartRateStatus.unconfigured => '未配置',
        BleHeartRateStatus.stopped => '已停止',
        BleHeartRateStatus.connecting => '连接中',
        BleHeartRateStatus.live => '实时',
        BleHeartRateStatus.stale => '陈旧',
        BleHeartRateStatus.reconnecting => '重连中',
        BleHeartRateStatus.disconnected => '已断开',
        BleHeartRateStatus.permissionDenied => '缺少权限',
        BleHeartRateStatus.bluetoothOff => '蓝牙关闭',
        BleHeartRateStatus.unsupported => '不支持',
        BleHeartRateStatus.malformedData => '数据异常',
        BleHeartRateStatus.unknown => '未知',
      };

  String get _statusDescription => switch (_snapshot.status) {
        BleHeartRateStatus.unconfigured => '尚未选择实时心率设备',
        BleHeartRateStatus.stopped => '实时接收已停止',
        BleHeartRateStatus.connecting => '正在连接并订阅标准心率服务',
        BleHeartRateStatus.live => '正在接收实时心率',
        BleHeartRateStatus.stale => '最后一条样本已超过 15 秒',
        BleHeartRateStatus.reconnecting => '连接中断，正在有界退避重连',
        BleHeartRateStatus.disconnected => '设备连接已断开',
        BleHeartRateStatus.permissionDenied => '需要蓝牙扫描与连接权限',
        BleHeartRateStatus.bluetoothOff => '手机蓝牙已关闭',
        BleHeartRateStatus.unsupported => '设备没有标准 Heart Rate Service',
        BleHeartRateStatus.malformedData => '收到的心率数据不完整',
        BleHeartRateStatus.unknown => '正在读取设备状态',
      };

  String _friendlyError(Object error) {
    if (error is PlatformException) {
      return switch (error.code) {
        'PERMISSION_DENIED' => '需要蓝牙权限后才能继续。',
        'BLUETOOTH_OFF' => '请先打开手机蓝牙。',
        'UNSUPPORTED' => '这台手机不支持蓝牙低功耗。',
        _ => error.message ?? error.code,
      };
    }
    return error.toString();
  }

  String _formatTimestamp(dynamic timestampMs) {
    final value = (timestampMs as num?)?.toInt();
    return value == null
        ? '时间未知'
        : _formatTime(DateTime.fromMillisecondsSinceEpoch(value));
  }

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}
