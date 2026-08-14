import 'package:flutter/material.dart';
import 'package:memex/data/services/device_app_blocker_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';

class DeviceAppBlockerSettingsPage extends StatefulWidget {
  const DeviceAppBlockerSettingsPage({super.key});

  @override
  State<DeviceAppBlockerSettingsPage> createState() =>
      _DeviceAppBlockerSettingsPageState();
}

class _DeviceAppBlockerSettingsPageState
    extends State<DeviceAppBlockerSettingsPage> {
  final _service = DeviceAppBlockerService.instance;
  final _durationController = TextEditingController();

  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  bool _nativeAccessibilityEnabled = false;
  bool _nativeFocusLockActive = false;
  DeviceAppBlockerState _state = const DeviceAppBlockerState();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await _service.getConfig();
    final state = await _service.getState();
    final nativeEnabled = await _service.isNativeAccessibilityServiceEnabled();
    final nativeActive = await _service.isNativeFocusLockActive();
    if (!mounted) return;
    setState(() {
      _enabled = config.enabled;
      _durationController.text = config.defaultDurationMinutes.toString();
      _state = state;
      _nativeAccessibilityEnabled = nativeEnabled;
      _nativeFocusLockActive = nativeActive;
      _loading = false;
    });
  }

  Future<void> _save({bool showMessage = true}) async {
    final duration = int.tryParse(_durationController.text.trim()) ?? 45;
    await _service.saveConfig(DeviceAppBlockerConfig(
      enabled: _enabled,
      defaultDurationMinutes: duration,
    ));
    if (!mounted || !showMessage) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved')),
    );
  }

  Future<void> _run(Future<DeviceAppBlockerResult> Function() action) async {
    setState(() => _busy = true);
    await _save(showMessage: false);
    final result = await action();
    final state = await _service.getState();
    final nativeEnabled = await _service.isNativeAccessibilityServiceEnabled();
    final nativeActive = await _service.isNativeFocusLockActive();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _state = state;
      _nativeAccessibilityEnabled = nativeEnabled;
      _nativeFocusLockActive = nativeActive;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _openNativeSettings() async {
    await _service.openNativeAccessibilitySettings();
  }

  String _lockSummary() {
    if (_nativeFocusLockActive || _state.active) {
      final until = _state.until;
      if (until == null) return 'Focus lock is active';
      return 'Focus lock is active until ${TimeOfDay.fromDateTime(until).format(context)}';
    }
    if (_state.lastError.isNotEmpty) return _state.lastError;
    return _nativeAccessibilityEnabled
        ? 'Ready'
        : 'Enable Android Accessibility access to use focus lock';
  }

  Color _summaryColor() {
    if (_nativeFocusLockActive || _state.active) return SpringRainUiTokens.daylightSuccess;
    if (_state.lastError.isNotEmpty) return SpringRainUiTokens.daylightError;
    return _nativeAccessibilityEnabled ? SpringRainUiTokens.daylightSuccess : SpringRainUiTokens.daylightTextSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpringRainUiTokens.daylightSurfaceMuted,
      appBar: AppBar(
        title: const Text('Device App Blocker'),
        backgroundColor: SpringRainUiTokens.daylightSurface,
        foregroundColor: SpringRainUiTokens.daylightTextPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _card([
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(
                      Icons.app_blocking_outlined,
                      color: SpringRainUiTokens.daylightAccent,
                    ),
                    title: const Text('Enable app blocker'),
                    subtitle: const Text(
                      'Allows authorized characters to start or stop a bounded focus lock.',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Android focus lock'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        _nativeAccessibilityEnabled
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _nativeAccessibilityEnabled
                            ? SpringRainUiTokens.daylightSuccess
                            : SpringRainUiTokens.daylightTextSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _nativeAccessibilityEnabled
                              ? 'Accessibility access enabled'
                              : 'Accessibility access needed',
                          style: TextStyle(
                            fontSize: 13,
                            color: _nativeAccessibilityEnabled
                                ? SpringRainUiTokens.daylightSuccess
                                : SpringRainUiTokens.daylightTextSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _lockSummary(),
                    style: TextStyle(fontSize: 13, color: _summaryColor()),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _openNativeSettings,
                    icon: const Icon(Icons.accessibility_new, size: 18),
                    label: const Text('Open Accessibility settings'),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Default lock duration'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Minutes',
                      hintText: '45',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Manual controls'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => _service.sendCommand(
                                    action: 'lock',
                                    reason: 'Manual test from settings',
                                    source: 'settings',
                                  ),
                                ),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.lock_clock, size: 18),
                        label: const Text('Lock now'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => _service.sendCommand(
                                    action: 'unlock',
                                    reason: 'Manual unlock from settings',
                                    source: 'settings',
                                  ),
                                ),
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: const Text('Unlock'),
                      ),
                    ],
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: SpringRainUiTokens.daylightSurface,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: SpringRainUiTokens.daylightTextSecondary.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: SpringRainUiTokens.daylightTextPrimary,
        ),
      );
}
