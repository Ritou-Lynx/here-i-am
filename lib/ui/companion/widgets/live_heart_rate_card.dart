import 'dart:async';

import 'package:flutter/material.dart';
import 'package:memex/data/services/ble_heart_rate_gateway.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/user_storage.dart';

class LiveHeartRateCard extends StatefulWidget {
  const LiveHeartRateCard({
    required this.onTap,
    super.key,
    this.gateway,
    this.userId,
  });

  final VoidCallback onTap;
  final BleHeartRateGateway? gateway;
  final String? userId;

  @override
  State<LiveHeartRateCard> createState() => _LiveHeartRateCardState();
}

class _LiveHeartRateCardState extends State<LiveHeartRateCard> {
  late final BleHeartRateGateway _gateway;
  StreamSubscription<BleHeartRateGatewayEvent>? _subscription;
  BleHeartRateSnapshot _snapshot = BleHeartRateSnapshot.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? BleHeartRateGateway.instance;
    _subscription = _gateway.events.listen(
      (event) {
        if (event is BleHeartRateSnapshotEvent && mounted) {
          setState(() {
            _snapshot = event.snapshot;
            _loading = false;
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
    _load();
  }

  Future<void> _load() async {
    final userId = widget.userId ?? await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final snapshot = await _gateway.getSnapshot(userId);
      if (mounted) {
        setState(() {
          _snapshot = snapshot;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sample = _snapshot.lastSample;
    final live = _snapshot.status == BleHeartRateStatus.live;
    return Material(
      key: const ValueKey('live_heart_rate_card'),
      color: SpringRainUiTokens.daylightAccentSoft,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: live
                      ? SpringRainUiTokens.daylightErrorSoft
                      : SpringRainUiTokens.daylightSurfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  live ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: live
                      ? SpringRainUiTokens.daylightError
                      : SpringRainUiTokens.daylightIcon,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _loading ? '正在读取实时心率' : _primaryText,
                      key: const ValueKey('live_heart_rate_primary'),
                      style: const TextStyle(
                        color: SpringRainUiTokens.daylightTextPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _loading ? '读取本机接收状态' : _secondaryText(sample),
                      key: const ValueKey('live_heart_rate_secondary'),
                      style: const TextStyle(
                        color: SpringRainUiTokens.daylightTextSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: SpringRainUiTokens.daylightIconMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _primaryText {
    final sample = _snapshot.lastSample;
    if (_snapshot.status == BleHeartRateStatus.live && sample != null) {
      return '${sample.bpm} BPM';
    }
    return switch (_snapshot.status) {
      BleHeartRateStatus.unconfigured => '未配置实时心率设备',
      BleHeartRateStatus.permissionDenied => '需要蓝牙权限',
      BleHeartRateStatus.bluetoothOff => '手机蓝牙已关闭',
      BleHeartRateStatus.connecting => '正在连接心率设备',
      BleHeartRateStatus.reconnecting => '正在重连心率设备',
      BleHeartRateStatus.stale => '心率样本已陈旧',
      BleHeartRateStatus.disconnected => '心率设备已断开',
      BleHeartRateStatus.stopped => '实时心率已停止',
      BleHeartRateStatus.unsupported => '设备不支持标准 HRS',
      BleHeartRateStatus.malformedData => '收到的心率数据异常',
      BleHeartRateStatus.live => '正在接收实时心率',
      BleHeartRateStatus.unknown => '实时心率状态未知',
    };
  }

  String _secondaryText(BleHeartRateSample? sample) {
    if (sample == null) {
      return _snapshot.deviceName == null
          ? '点此扫描并选择标准蓝牙心率设备'
          : '${_snapshot.deviceName} · 点此查看连接详情';
    }
    final time =
        '${sample.timestamp.hour.toString().padLeft(2, '0')}:${sample.timestamp.minute.toString().padLeft(2, '0')}:${sample.timestamp.second.toString().padLeft(2, '0')}';
    return '最后样本 $time · ${_snapshot.rrSeen ? 'RR 已出现' : '尚未收到 RR'}';
  }
}
