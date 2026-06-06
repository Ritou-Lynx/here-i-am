import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

import 'package:memex/data/services/custom_agent_config_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/data/services/weread_sync_service.dart';
import 'package:memex/domain/models/custom_agent_config.dart';
import 'package:memex/domain/models/system_event.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

class WereadConnectPage extends StatefulWidget {
  const WereadConnectPage({super.key});

  @override
  State<WereadConnectPage> createState() => _WereadConnectPageState();
}

class _WereadConnectPageState extends State<WereadConnectPage> {
  final _apiKeyCtrl = TextEditingController();

  bool _loading = true;
  bool _syncing = false;
  bool _configured = false;
  bool _hasCachedSummary = false;
  DateTime? _summaryUpdatedAt;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    setState(() {
      _loading = true;
      _error = null;
      _message = null;
    });

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        setState(() {
          _configured = false;
          _hasCachedSummary = false;
          _summaryUpdatedAt = null;
          _loading = false;
        });
        return;
      }

      final config = await _loadWereadConfig(userId);
      final key = _extractApiKey(config?.systemPrompt);
      final summaryFile = File(_summaryPath(userId));
      final hasSummary = await summaryFile.exists();
      final stat = hasSummary ? await summaryFile.stat() : null;

      setState(() {
        _apiKeyCtrl.text = key ?? '';
        _configured = key != null;
        _hasCachedSummary = hasSummary;
        _summaryUpdatedAt = stat?.modified;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '读取微信读书配置失败：$e';
        _loading = false;
      });
    }
  }

  Future<CustomAgentConfig?> _loadWereadConfig(String userId) async {
    final configs = await CustomAgentConfigService.instance.loadAll(userId);
    return configs.where((c) => c.agentName == 'weread').firstOrNull;
  }

  String? _extractApiKey(String? text) {
    if (text == null) return null;
    return RegExp(r'wrk-[A-Za-z0-9]+').firstMatch(text)?.group(0);
  }

  String _summaryPath(String userId) {
    return path.join(
      FileSystemService.instance.getUserSettingsPath(userId),
      'external_data',
      'weread',
      'reading_summary.md',
    );
  }

  Future<void> _saveAndSync() async {
    final key = _apiKeyCtrl.text.trim();
    if (!RegExp(r'^wrk-[A-Za-z0-9]+$').hasMatch(key)) {
      setState(() => _error = '请输入有效的微信读书 API Key（形如 wrk-...）');
      return;
    }

    setState(() {
      _syncing = true;
      _error = null;
      _message = null;
    });

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        setState(() => _error = '还没有当前用户，无法保存配置');
        return;
      }

      final existing = await _loadWereadConfig(userId);
      final systemPrompt = _buildSystemPrompt(
        key: key,
        previous: existing?.systemPrompt,
      );
      final config = (existing ??
              const CustomAgentConfig(
                agentName: 'weread',
                hostAgentType: HostAgentType.pure,
                skillDirectoryPath: '_UserSettings/skills/weread',
                workingDirectory: '',
                eventType: SystemEventTypes.userInputSubmitted,
                executionMode: ExecutionMode.async_,
                enabled: false,
                isCustom: true,
                systemPrompt: '',
              ))
          .copyWith(
        agentName: 'weread',
        systemPrompt: systemPrompt,
        enabled: false,
      );

      await CustomAgentConfigService.instance.saveAndReload(userId, config);
      final synced = await WereadSyncService.syncIfConfigured(userId);
      final summaryFile = File(_summaryPath(userId));
      final hasSummary = await summaryFile.exists();
      final stat = hasSummary ? await summaryFile.stat() : null;

      setState(() {
        _configured = true;
        _hasCachedSummary = hasSummary;
        _summaryUpdatedAt = stat?.modified;
        _message = synced ? '已连接并同步微信读书。' : '配置已保存，但同步没有成功；请稍后重试。';
      });
    } catch (e) {
      setState(() => _error = '保存或同步失败：$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  String _buildSystemPrompt({required String key, String? previous}) {
    final cleaned = previous == null
        ? ''
        : previous
            .replaceAll(RegExp(r'WEREAD_API_KEY\s*=\s*wrk-[A-Za-z0-9]+'), '')
            .replaceAll(RegExp(r'wrk-[A-Za-z0-9]+'), '')
            .trim();
    final base =
        cleaned.isEmpty ? '微信读书连接配置。此配置用于同步书架和阅读进度给 Here I Am。' : cleaned;
    return '$base\n\nWEREAD_API_KEY=$key';
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _error = null;
      _message = null;
    });
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        setState(() => _error = '还没有当前用户，无法同步');
        return;
      }
      final synced = await WereadSyncService.syncIfConfigured(userId);
      final summaryFile = File(_summaryPath(userId));
      final hasSummary = await summaryFile.exists();
      final stat = hasSummary ? await summaryFile.stat() : null;
      setState(() {
        _hasCachedSummary = hasSummary;
        _summaryUpdatedAt = stat?.modified;
        _message = synced ? '微信读书已同步。' : '同步没有成功，请检查 API Key。';
      });
    } catch (e) {
      setState(() => _error = '同步失败：$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() {
      _syncing = true;
      _error = null;
      _message = null;
    });
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      await CustomAgentConfigService.instance.deleteAndReload(userId, 'weread');
      final cacheDir = Directory(path.dirname(_summaryPath(userId)));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
      setState(() {
        _apiKeyCtrl.clear();
        _configured = false;
        _hasCachedSummary = false;
        _summaryUpdatedAt = null;
        _message = '已移除微信读书连接配置。';
      });
    } catch (e) {
      setState(() => _error = '移除配置失败：$e');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('微信读书')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildStatusCard(),
                const SizedBox(height: 16),
                _buildConfigCard(),
              ],
            ),
    );
  }

  Widget _buildStatusCard() {
    final updated = _summaryUpdatedAt == null
        ? '尚未同步'
        : DateFormat('yyyy-MM-dd HH:mm').format(_summaryUpdatedAt!);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _configured ? Icons.check_circle : Icons.menu_book_outlined,
                color: _configured ? Colors.green : AppColors.primary,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _configured ? '已连接微信读书' : '连接微信读书',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _hasCachedSummary
                ? '本地阅读摘要已生成，伴侣可以在主动问候时读取。'
                : '保存 API Key 后会同步书架和阅读进度，生成本地阅读摘要。',
            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text(
            '最近同步：$updated',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Text(_message!, style: const TextStyle(color: Colors.green)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'API Key',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKeyCtrl,
            decoration: const InputDecoration(
              hintText: 'wrk-...',
              border: OutlineInputBorder(),
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 10),
          Text(
            '这个 key 会保存在本机 Here I Am 的用户数据里，用于同步微信读书摘要。',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _syncing ? null : _saveAndSync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_configured ? '保存并同步' : '连接并同步'),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                tooltip: '立即同步',
                onPressed: _configured && !_syncing ? _syncNow : null,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: '移除连接',
                onPressed: _configured && !_syncing ? _disconnect : null,
                icon: const Icon(Icons.link_off),
              ),
            ],
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: AppColors.textSecondary.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}
