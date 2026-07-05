import 'package:flutter/material.dart';
import 'package:memex/data/services/location_context_service.dart';
import 'package:memex/domain/models/location_context_config.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

typedef CurrentLocationContextLoader = Future<CurrentLocationContext> Function(
    {bool forceRefresh, bool ignoreEnabled});

class LocationContextSettingsPage extends StatefulWidget {
  const LocationContextSettingsPage({super.key, this.loadCurrentContext});

  final CurrentLocationContextLoader? loadCurrentContext;

  @override
  State<LocationContextSettingsPage> createState() =>
      _LocationContextSettingsPageState();
}

class _LocationContextSettingsPageState
    extends State<LocationContextSettingsPage> {
  LocationContextConfig _config = const LocationContextConfig();
  late final TextEditingController _amapKeyController;
  bool _loading = true;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _amapKeyController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _amapKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await UserStorage.getLocationContextConfig();
    if (!mounted) return;
    setState(() {
      _config = config;
      _amapKeyController.text = config.amapApiKey;
      _loading = false;
    });
  }

  Future<void> _save(LocationContextConfig config) async {
    setState(() => _config = config);
    await UserStorage.saveLocationContextConfig(config);
  }

  Future<void> _testLocation() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final loader = widget.loadCurrentContext ??
          LocationContextService.instance.getCurrentContext;
      final context = await loader(forceRefresh: true, ignoreEnabled: true);
      if (!mounted) return;
      setState(() {
        _testResult = _formatLocationDebugResult(context);
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _testResult = UserStorage.l10n.locationTestFailed(e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  String _formatLocationDebugResult(CurrentLocationContext context) {
    final l10n = UserStorage.l10n;
    final address = context.address;
    final summary = address?.summary(context.granularity);
    final lines = <String>[
      '${l10n.locationDebugGps}: ${context.status}',
      '${l10n.locationDebugProvider}: ${_providerDebugLabel(context)}',
      '${l10n.locationDebugReverseGeocode}: '
          '${address == null ? l10n.locationDebugUnavailable : l10n.locationDebugOk}',
      '${l10n.locationDebugAgentContext}: '
          '${context.toAgentSystemReminderContent() == null ? l10n.locationDebugNotInjected : l10n.locationDebugInjected}',
    ];

    if (context.source.trim().isNotEmpty) {
      lines.add('${l10n.locationDebugSource}: ${context.source}');
    }
    if (summary != null && summary.isNotEmpty) {
      lines.add('${l10n.locationDebugAddressSummary}: $summary');
    }
    if (address?.fullAddress != null) {
      lines.add('${l10n.locationDebugFullAddress}: ${address!.fullAddress!}');
    }
    if (context.latitude != null && context.longitude != null) {
      lines.add(
        '${l10n.locationDebugCoordinates}: '
        '${context.latitude!.toStringAsFixed(6)}, '
        '${context.longitude!.toStringAsFixed(6)}',
      );
    }
    if (context.accuracyMeters != null) {
      lines.add(
        '${l10n.locationDebugAccuracy}: '
        '${context.accuracyMeters!.toStringAsFixed(1)}m',
      );
    }
    if (context.reason != null && context.reason!.trim().isNotEmpty) {
      lines.add(
        '${l10n.locationDebugReason}: ${_friendlyLocationReason(context.reason!)}',
      );
    }
    final hint = _locationDebugHint(context);
    if (hint != null) {
      lines.add('提示：$hint');
    }

    return lines.join('\n');
  }

  String _friendlyLocationReason(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('failed to get current device location')) {
      final details = reason.replaceFirst(
        RegExp(
          r'failed to get current device location:?\s*',
          caseSensitive: false,
        ),
        '',
      );
      if (details.trim().isEmpty) {
        return '手机这次没有返回当前 GPS 坐标。';
      }
      return '手机这次没有返回当前 GPS 坐标。原始原因：${details.trim()}';
    }
    if (lower.contains('using stale last known device location')) {
      return reason.replaceFirst(
        'using stale last known device location for diagnostics',
        '当前 GPS 没有成功返回，先显示系统最近一次定位用于诊断',
      );
    }
    if (lower.contains('using recent last known device location')) {
      return reason.replaceFirst(
        'using recent last known device location after current lookup failed',
        '当前 GPS 没有成功返回，先使用系统最近一次定位',
      );
    }
    if (lower.contains('openstreetmap reverse geocode failed') &&
        lower.contains('used amap fallback')) {
      return 'GPS 已可用；OpenStreetMap 地址解析失败，已使用高德兜底。';
    }
    if (lower.contains('amap fallback unavailable')) {
      return reason.replaceFirst(
        'Amap fallback unavailable',
        '高德兜底也不可用',
      );
    }
    return reason;
  }

  String? _locationDebugHint(CurrentLocationContext context) {
    final reason = context.reason?.toLowerCase() ?? '';
    if (context.status == 'disabled') {
      return '测试按钮可以临时读取一次位置；只有打开总开关后，聊天和提醒才会使用位置。';
    }
    if (reason.contains('failed to get current device location')) {
      return '定位权限已经有了，但手机这次没有拿到当前坐标。可以打开系统定位、稍等几秒，或到窗边/室外再试一次。';
    }
    if (reason.contains('used amap fallback')) {
      return null;
    }
    if (reason.contains('amap api key is empty')) {
      return '高级设置里选择了高德作为地点服务商，但高德 Key 为空。填入 Key，或把服务商切回 OpenStreetMap。';
    }
    if (reason.contains('openstreetmap') || reason.contains('nominatim')) {
      return 'OpenStreetMap 的逆地理编码在当前网络下可能不可达；如果已经有高德 Key，可以在高级设置里切到高德。';
    }
    if (reason.contains('permission')) {
      return '请检查系统里给「故我在 V3」的定位权限，然后再试一次。';
    }
    return null;
  }

  String _providerLabel(GeocodingProvider provider) {
    switch (provider) {
      case GeocodingProvider.openStreetMap:
        return 'OpenStreetMap / Nominatim';
      case GeocodingProvider.amap:
        return UserStorage.l10n.amapProviderName;
    }
  }

  String _providerDebugLabel(CurrentLocationContext context) {
    final configured = _providerLabel(_config.provider);
    final actualProvider = context.address?.provider;
    if (actualProvider == null || actualProvider.trim().isEmpty) {
      return configured;
    }

    final actual = switch (actualProvider) {
      'amap' => UserStorage.l10n.amapProviderName,
      'open_street_map' => 'OpenStreetMap / Nominatim',
      _ => actualProvider,
    };
    if (actual == configured) {
      return configured;
    }
    return '$configured（实际使用：$actual）';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('位置、地图与天气'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _recordLocationSection(l10n),
                const SizedBox(height: 16),
                _amapKeySection(),
                const SizedBox(height: 16),
                _transitCompanionSection(),
                const SizedBox(height: 16),
                _advancedSettingsSection(l10n),
              ],
            ),
    );
  }

  Widget _recordLocationSection(dynamic l10n) {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(
              Icons.my_location_outlined,
              color: AppColors.primary,
            ),
            title: const Text('让 I 知道你的位置'),
            subtitle: const Text(
              '用于聊天里的现实上下文、天气判断、出门提醒和记忆来源地点。默认只提供大致位置，不把精确门牌交给角色。',
            ),
            value: _config.enabled,
            onChanged: (value) => _save(_config.copyWith(enabled: value)),
          ),
        ],
      ),
    );
  }

  Widget _amapKeySection() {
    return _section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '高德 Key',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '用于路线规划、天气风险提醒、周边地点和路线陪跑。日常记忆地点仍可在高级设置里继续使用 OpenStreetMap。',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amapKeyController,
            decoration: const InputDecoration(
              labelText: '高德 Web 服务 Key',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                _save(_config.copyWith(amapApiKey: value.trim())),
          ),
        ],
      ),
    );
  }

  Widget _transitCompanionSection() {
    return _section(
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        secondary: const Icon(
          Icons.directions_transit_filled_outlined,
          color: AppColors.primary,
        ),
        title: const Text('路线陪跑提醒'),
        subtitle: const Text(
          '允许 I 在你明确要求“帮我盯路 / 别坐过站”时，为本次出行创建临时提醒。不会自动追踪位置；路线结束或超时后自动停止。',
        ),
        value: _config.transitCompanionEnabled,
        onChanged: (value) =>
            _save(_config.copyWith(transitCompanionEnabled: value)),
      ),
    );
  }

  Widget _advancedSettingsSection(dynamic l10n) {
    return _section(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 8),
        leading: const Icon(
          Icons.tune_outlined,
          color: AppColors.primary,
        ),
        title: const Text(
          '高级设置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('地点服务商、地点精度、新鲜度和定位诊断'),
        children: [
          _reverseGeocodingControls(l10n),
          const SizedBox(height: 18),
          _granularityControls(l10n),
          const SizedBox(height: 18),
          _freshnessControls(l10n),
          const SizedBox(height: 18),
          _testLocationControls(l10n),
        ],
      ),
    );
  }

  Widget _reverseGeocodingControls(dynamic l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.reverseGeocodingProvider,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          '用于把 GPS 转成城市、区县和街区。记忆来源地点建议保持轻量，不需要特别精确。',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<GeocodingProvider>(
          key: ValueKey(_config.provider),
          initialValue: _config.provider,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          selectedItemBuilder: (_) => [
            const Text('OpenStreetMap / Nominatim'),
            Text(l10n.amapProviderName),
          ],
          items: [
            const DropdownMenuItem(
              value: GeocodingProvider.openStreetMap,
              child: Text('OpenStreetMap / Nominatim'),
            ),
            DropdownMenuItem(
              value: GeocodingProvider.amap,
              child: Text(l10n.amapProviderName),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            _save(_config.copyWith(provider: value));
          },
        ),
        if (_config.provider == GeocodingProvider.amap) ...[
          const SizedBox(height: 8),
          Text(
            l10n.amapGcj02Note,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _granularityControls(dynamic l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.contextGranularity,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<LocationContextGranularity>(
          key: ValueKey(_config.granularity),
          initialValue: _config.granularity,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: LocationContextGranularity.city,
              child: Text(l10n.granularityCity),
            ),
            DropdownMenuItem(
              value: LocationContextGranularity.district,
              child: Text(l10n.granularityDistrict),
            ),
            DropdownMenuItem(
              value: LocationContextGranularity.neighborhood,
              child: Text(l10n.granularityNeighborhood),
            ),
            DropdownMenuItem(
              value: LocationContextGranularity.street,
              child: Text(l10n.granularityStreet),
            ),
            DropdownMenuItem(
              value: LocationContextGranularity.full,
              child: Text(l10n.granularityFullAddress),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            _save(_config.copyWith(granularity: value));
          },
        ),
      ],
    );
  }

  Widget _freshnessControls(dynamic l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.locationFreshness,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey(_config.ttlMinutes),
          initialValue: _config.ttlMinutes,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(value: 5, child: Text(l10n.minutesShort(5))),
            DropdownMenuItem(value: 15, child: Text(l10n.minutesShort(15))),
            DropdownMenuItem(value: 30, child: Text(l10n.minutesShort(30))),
            DropdownMenuItem(value: 60, child: Text(l10n.oneHour)),
          ],
          onChanged: (value) {
            if (value == null) return;
            _save(_config.copyWith(ttlMinutes: value));
          },
        ),
      ],
    );
  }

  Widget _testLocationControls(dynamic l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: _testing ? null : _testLocation,
          icon: _testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.location_searching),
          label: Text(l10n.testCurrentLocation),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          SelectableText(
            _testResult!,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }

  Widget _section({required Widget child}) {
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: AppColors.textSecondary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: child,
      ),
    );
  }
}
