import 'package:flutter/material.dart';
import 'package:memex/data/services/device_app_blocker_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

class DeviceAppBlockerSettingsPage extends StatefulWidget {
  const DeviceAppBlockerSettingsPage({super.key});

  @override
  State<DeviceAppBlockerSettingsPage> createState() =>
      _DeviceAppBlockerSettingsPageState();
}

class _DeviceAppBlockerSettingsPageState
    extends State<DeviceAppBlockerSettingsPage> {
  final _service = DeviceAppBlockerService.instance;
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  final _durationController = TextEditingController();
  final _packagesController = TextEditingController();

  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  bool _obscureToken = true;
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
    _urlController.dispose();
    _tokenController.dispose();
    _durationController.dispose();
    _packagesController.dispose();
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
      _urlController.text = config.webhookUrl;
      _tokenController.text = config.authToken;
      _durationController.text = config.defaultDurationMinutes.toString();
      _packagesController.text = config.blockedPackages.join('\n');
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
      webhookUrl: _urlController.text.trim(),
      authToken: _tokenController.text.trim(),
      defaultDurationMinutes: duration,
      blockedPackages: _parsePackages(_packagesController.text),
    ));
    if (!mounted || !showMessage) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Saved')));
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

  List<String> _parsePackages(String raw) {
    return raw
        .split(RegExp(r'[\n,]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  String _statusText() {
    if (_state.active) {
      final until = _state.until;
      if (until == null) return 'Active';
      return 'Active until ${TimeOfDay.fromDateTime(until).format(context)}';
    }
    if (_nativeFocusLockActive) return 'Native focus lock active';
    if (_state.lastError.isNotEmpty) return 'Last error: ${_state.lastError}';
    return 'Not active';
  }

  Future<void> _openNativeSettings() async {
    await _service.openNativeAccessibilitySettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Device App Blocker'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
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
                      color: AppColors.primary,
                    ),
                    title: const Text('Enable app blocker'),
                    subtitle: const Text(
                      'AI can send bounded focus lock/unlock commands only after this is enabled.',
                    ),
                    value: _enabled,
                    onChanged: (value) => setState(() => _enabled = value),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Native Android focus lock'),
                  Text(
                    _nativeAccessibilityEnabled
                        ? 'Accessibility service enabled'
                        : 'Accessibility service not enabled',
                    style: TextStyle(
                      fontSize: 13,
                      color: _nativeAccessibilityEnabled
                          ? Colors.green
                          : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _openNativeSettings,
                    icon: const Icon(Icons.accessibility_new, size: 18),
                    label: const Text('Open Accessibility settings'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Leave endpoint empty to use the built-in Accessibility lock. When active, leaving Here I am briefly returns you to this app.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('External endpoint fallback'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint (optional)',
                      hintText: 'Leave empty to use native Accessibility',
                      helperText:
                          'Optional: intent://com.memexlab.hereiam.APP_BLOCKER_COMMAND or webhook URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenController,
                    obscureText: _obscureToken,
                    decoration: InputDecoration(
                      labelText: 'Optional shared token',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: Icon(_obscureToken
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Lock profile'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Default duration (minutes)',
                      hintText: '45',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _packagesController,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Blocked package names',
                      hintText: 'com.xingin.xhs',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('Status'),
                  Text(
                    _statusText(),
                    style: TextStyle(
                      fontSize: 13,
                      color: _state.active ? Colors.green : Colors.grey[700],
                    ),
                  ),
                  if (_state.reason.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _state.reason,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed:
                            _busy ? null : () => _run(_service.testConnection),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Test'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => _service.sendCommand(
                                    action: 'lock',
                                    durationMinutes: 10,
                                    reason: 'Manual test from settings',
                                    source: 'settings',
                                  ),
                                ),
                        icon: const Icon(Icons.lock_clock, size: 18),
                        label: const Text('Lock 10 min'),
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
                const SizedBox(height: 16),
                _card([
                  _sectionTitle('How it works'),
                  const Text(
                    'Default mode uses Here I am\'s own Accessibility Service. Tasker is still supported if you provide an intent:// endpoint or webhook URL.',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ]),
              ],
            ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.textSecondary.withValues(alpha: 0.08),
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
          color: AppColors.textPrimary,
        ),
      );
}
