import 'package:flutter/material.dart';

import 'package:memex/data/services/app_update_service.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

class EarlyUpdateSettingsCard extends StatefulWidget {
  EarlyUpdateSettingsCard({
    super.key,
    AppUpdateService? service,
    this.forceVisible = false,
  }) : service = service ?? AppUpdateService.instance;

  final AppUpdateService service;
  final bool forceVisible;

  @override
  State<EarlyUpdateSettingsCard> createState() =>
      _EarlyUpdateSettingsCardState();
}

class _EarlyUpdateSettingsCardState extends State<EarlyUpdateSettingsCard> {
  AppUpdateSettings? _settings;
  AppUpdateInfo? _availableUpdate;
  bool _checking = false;
  bool _downloading = false;
  int _downloadPercent = 0;
  String? _statusText;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!widget.forceVisible && !widget.service.isSupported) return;
    final settings = await widget.service.loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _statusText = _lastCheckedText(settings);
    });
  }

  Future<void> _saveSettings(AppUpdateSettings settings) async {
    await widget.service.saveSettings(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  Future<void> _checkNow() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _statusText = UserStorage.l10n.earlyUpdateChecking;
    });

    try {
      final result = await widget.service.checkForUpdate(manual: true);
      if (!mounted) return;
      final latestSettings = await widget.service.loadSettings();
      setState(() {
        _checking = false;
        _settings = latestSettings;
        switch (result.status) {
          case AppUpdateCheckStatus.unsupported:
            _availableUpdate = null;
            _statusText = UserStorage.l10n.earlyUpdateUnsupported;
          case AppUpdateCheckStatus.skippedNotWifi:
            _availableUpdate = null;
            _statusText = UserStorage.l10n.earlyUpdateSkippedMobile;
          case AppUpdateCheckStatus.noUpdate:
            _availableUpdate = null;
            _statusText = UserStorage.l10n.earlyUpdateNoUpdate;
          case AppUpdateCheckStatus.updateAvailable:
            _availableUpdate = result.update;
            final update = result.update!;
            _statusText = UserStorage.l10n.earlyUpdateFound(
              update.versionName,
              update.buildNumber,
            );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _statusText = UserStorage.l10n.earlyUpdateCheckFailed(e);
      });
    }
  }

  Future<void> _downloadAndInstall() async {
    final update = _availableUpdate;
    if (update == null || _downloading) return;

    setState(() {
      _downloading = true;
      _downloadPercent = 0;
      _statusText = UserStorage.l10n.earlyUpdateDownloadingPercent(0);
    });

    try {
      final download = await widget.service.downloadUpdate(
        update,
        onProgress: (receivedBytes, totalBytes) {
          if (!mounted || totalBytes <= 0) return;
          final percent =
              ((receivedBytes / totalBytes) * 100).clamp(0, 100).round();
          setState(() {
            _downloadPercent = percent;
            _statusText =
                UserStorage.l10n.earlyUpdateDownloadingPercent(percent);
          });
        },
      );

      final install = await widget.service.installUpdate(download.apkPath);
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadPercent = 100;
        _statusText = switch (install.status) {
          AppUpdateInstallStatus.started =>
            UserStorage.l10n.earlyUpdateInstallStarted,
          AppUpdateInstallStatus.permissionRequired =>
            UserStorage.l10n.earlyUpdateInstallPermissionRequired,
          AppUpdateInstallStatus.unsupported =>
            UserStorage.l10n.earlyUpdateUnsupported,
        };
      });
    } catch (e) {
      if (!mounted) return;
      final statusText = e is AppUpdateWifiRequiredException
          ? UserStorage.l10n.earlyUpdateSkippedMobile
          : UserStorage.l10n.earlyUpdateCheckFailed(e);
      setState(() {
        _downloading = false;
        _statusText = statusText;
      });
      if (e is AppUpdateWifiRequiredException) {
        ToastHelper.showInfo(
            context, UserStorage.l10n.earlyUpdateSkippedMobile);
      } else {
        ToastHelper.showError(context, e);
      }
    }
  }

  String? _lastCheckedText(AppUpdateSettings settings) {
    final checkedAt = settings.lastCheckAt;
    if (checkedAt == null) return null;
    final local = checkedAt.toLocal();
    final formatted =
        '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
    return UserStorage.l10n.earlyUpdateLastChecked(formatted);
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    if (!widget.forceVisible && !widget.service.isSupported) {
      return const SizedBox.shrink();
    }

    final settings = _settings;
    final tokens = context.springRainUi;
    if (settings == null) {
      return _buildShell(
        child: const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return _buildShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.system_update_alt,
                color: tokens.accent,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UserStorage.l10n.earlyUpdateSettingsTitle,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      UserStorage.l10n.earlyUpdateSettingsDesc,
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildSwitch(
            title: UserStorage.l10n.earlyUpdateAutoCheckTitle,
            subtitle: UserStorage.l10n.earlyUpdateAutoCheckDesc,
            value: settings.autoCheckEnabled,
            onChanged: (value) =>
                _saveSettings(settings.copyWith(autoCheckEnabled: value)),
          ),
          _buildSwitch(
            title: UserStorage.l10n.earlyUpdateWifiOnlyTitle,
            subtitle: UserStorage.l10n.earlyUpdateWifiOnlyDesc,
            value: settings.wifiOnlyDownloads,
            onChanged: (value) =>
                _saveSettings(settings.copyWith(wifiOnlyDownloads: value)),
          ),
          _buildSwitch(
            title: UserStorage.l10n.earlyUpdateAutoInstallTitle,
            subtitle: UserStorage.l10n.earlyUpdateAutoInstallDesc,
            value: settings.autoDownloadAndInstall,
            onChanged: (value) => _saveSettings(
              settings.copyWith(autoDownloadAndInstall: value),
            ),
          ),
          if (_statusText != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusText!,
              style: TextStyle(
                fontSize: 13,
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: _downloadPercent <= 0 ? null : _downloadPercent / 100,
              color: tokens.accent,
              minHeight: 4,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _checking || _downloading ? null : _checkNow,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(UserStorage.l10n.earlyUpdateCheckNow),
              ),
              if (_availableUpdate != null)
                FilledButton.icon(
                  onPressed:
                      _checking || _downloading ? null : _downloadAndInstall,
                  icon: const Icon(Icons.download, size: 18),
                  label: Text(UserStorage.l10n.earlyUpdateDownloadAndInstall),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShell({required Widget child}) {
    final tokens = context.springRainUi;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(tokens.radius18),
        border: Border.all(color: tokens.divider),
      ),
      child: child,
    );
  }

  Widget _buildSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final tokens = context.springRainUi;
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: tokens.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: tokens.textSecondary,
            height: 1.35,
          ),
        ),
      ),
      value: value,
      onChanged: _checking || _downloading ? null : onChanged,
    );
  }
}
