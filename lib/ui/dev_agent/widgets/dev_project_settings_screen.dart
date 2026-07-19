import 'package:flutter/material.dart';
import 'package:memex/data/services/dev_agent_bridge_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';

class DevProjectSettingsScreen extends StatefulWidget {
  const DevProjectSettingsScreen({
    super.key,
    this.project,
  });

  final DevProject? project;

  @override
  State<DevProjectSettingsScreen> createState() =>
      _DevProjectSettingsScreenState();
}

class _DevProjectSettingsScreenState extends State<DevProjectSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _rootPathController;
  late final TextEditingController _defaultBranchController;
  late final TextEditingController _bridgeUrlController;
  String _permissionTier = DevProjectPermissionTier.readOnly.value;
  // _modelController holds the resolved default model (provider/model
  // format). The dropdown lets the user pick from OpenCode's known model
  // list; the field is also editable so users can paste a model id
  // Bridge doesn't know about (older builds, custom providers, etc.).
  late final TextEditingController _modelController;
  // Dropdown options are loaded from Bridge on demand; empty means
  // "OpenCode wasn't reachable" and we fall back to free-form input.
  List<String> _modelChoices = const [];
  bool _loadingModels = false;
  String? _modelChoicesWarning;
  bool _saving = false;
  bool _checkingBridge = false;
  String? _bridgeStatus;

  @override
  void initState() {
    super.initState();
    final project = widget.project;
    _nameController = TextEditingController(text: project?.name ?? '');
    _rootPathController = TextEditingController(text: project?.rootPath ?? '');
    _defaultBranchController =
        TextEditingController(text: project?.defaultBranch ?? 'personal-lab');
    _bridgeUrlController =
        TextEditingController(text: project?.bridgeUrl ?? '');
    _modelController = TextEditingController(
      text: project?.defaultOpencodeModel ?? '',
    );
    _permissionTier =
        project?.permissionTier ?? DevProjectPermissionTier.readOnly.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rootPathController.dispose();
    _defaultBranchController.dispose();
    _bridgeUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DevAgentBridgeService.instance.saveProject(
        id: widget.project?.id,
        name: _nameController.text,
        rootPath: _rootPathController.text,
        defaultBranch: _defaultBranchController.text,
        bridgeUrl: _bridgeUrlController.text,
        permissionTier: _permissionTier,
        defaultOpencodeModel: _normalizeModel(_modelController.text),
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Trim and reject obvious garbage so we don't persist prose into a
  /// `provider/model` column. Returns null when the field is empty so the
  /// caller can clear the project default and fall back to
  /// opencode.jsonc.
  String? _normalizeModel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (!value.contains('/')) return value; // accept anything user typed
    return value;
  }

  Future<void> _loadOpencodeModels() async {
    if (_bridgeUrlController.text.trim().isEmpty) return;
    setState(() {
      _loadingModels = true;
      _modelChoicesWarning = null;
    });
    try {
      final result = await DevAgentBridgeService.instance
          .listOpencodeModels(_bridgeUrlController.text.trim());
      if (!mounted) return;
      final choices = result.models.toSet().toList(growable: false)..sort();
      // Always include the current value (e.g. a model the user picked
      // before Bridge became reachable, or one Bridge didn't return).
      final current = _modelController.text.trim();
      if (current.isNotEmpty && !choices.contains(current)) {
        choices.add(current);
      }
      setState(() {
        _modelChoices = choices;
        _modelChoicesWarning = result.warning;
      });
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _delete() async {
    final project = widget.project;
    if (project == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除项目?'),
        content: Text(
            '"${project.name}" 的所有 run 历史、事件、artifact 会一起被清掉。Bridge 端的 worktree 不会被动。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      await DevAgentBridgeService.instance.deleteProject(project.id);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _checkBridge() async {
    setState(() {
      _checkingBridge = true;
      _bridgeStatus = null;
    });
    try {
      final health = await DevAgentBridgeService.instance.checkBridgeHealth(
        _bridgeUrlController.text,
      );
      if (!mounted) return;
      final agents =
          health.agents.isEmpty ? '无代理列表' : health.agents.join(' / ');
      setState(() {
        _bridgeStatus = health.ok
            ? '${health.bridgeId} · ${health.version} · $agents'
            : 'Bridge 返回异常';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _bridgeStatus = e.toString());
    } finally {
      if (mounted) setState(() => _checkingBridge = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.project != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑 Dev 项目' : '新增 Dev 项目'),
        actions: [
          if (isEditing)
            IconButton(
              tooltip: '删除项目',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Field(
              controller: _nameController,
              label: '项目名',
              hint: 'Here I am',
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _rootPathController,
              label: '电脑上的项目路径',
              hint: r'D:\claude-workspace\memex',
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _defaultBranchController,
              label: '默认分支',
              hint: 'v3-lab',
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _bridgeUrlController,
              label: 'Bridge URL',
              hint: 'https://host.example.invalid',
              validator: (value) {
                return DevAgentBridgeService.validateBridgeUrlError(value);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _checkingBridge ? null : _checkBridge,
                  icon: _checkingBridge
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering_outlined, size: 18),
                  label: const Text('测试 Bridge'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _bridgeStatus ?? '保存前可以先确认 Bridge 是否在线。',
                    style: const TextStyle(
                      height: 1.35,
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _permissionTier,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: '权限档',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'read_only',
                  child: Text('只读'),
                ),
                DropdownMenuItem(
                  value: 'workspace_write',
                  child: Text('写入工作区'),
                ),
                DropdownMenuItem(
                  value: 'release_ops',
                  child: Text('发布操作'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _permissionTier = value);
              },
            ),
            const SizedBox(height: 14),
            _OpencodeModelField(
              controller: _modelController,
              choices: _modelChoices,
              loading: _loadingModels,
              warning: _modelChoicesWarning,
              onPick: (value) {
                _modelController.text = value;
                setState(() {});
              },
              onLoadChoices: _loadOpencodeModels,
              onClear: () {
                _modelController.clear();
                setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Combines an OpenCode model picker with a free-form text field. The
/// dropdown is for known models; the text field lets users paste a model
/// id Bridge didn't return (older Bridge, custom provider, etc.).
class _OpencodeModelField extends StatelessWidget {
  const _OpencodeModelField({
    required this.controller,
    required this.choices,
    required this.loading,
    required this.warning,
    required this.onPick,
    required this.onLoadChoices,
    required this.onClear,
  });

  final TextEditingController controller;
  final List<String> choices;
  final bool loading;
  final String? warning;
  final ValueChanged<String> onPick;
  final VoidCallback onLoadChoices;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '默认 OpenCode 模型',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        const Text(
          'OpenCode CLI 用 `provider/model` 格式调用。这个值会在 chat 里或自动跑 Dev Room 时作为默认值；留空走 opencode.jsonc / DEV_AGENT_OPENCODE_MODEL。',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        if (choices.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final model in choices)
                ChoiceChip(
                  label: Text(
                    model,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: controller.text.trim() == model,
                  onSelected: (_) => onPick(model),
                ),
            ],
          )
else if (!loading && warning != null)
          Text(
            'Bridge 没法拉取模型列表（${warning!}）。可以直接在下方框里填。',
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'opencode-go/qwen3.7-max',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null; // empty is OK (fall back)
                  // Loose validation — accept anything that has a `/`
                  // separator. Strict provider/model whitelist is checked
                  // by OpenCode itself when the run starts.
                  if (!text.contains('/')) {
                    return '应该是 provider/model 格式，例如 opencode-go/glm-5.2';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: loading ? null : onLoadChoices,
              icon: loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 18),
              label: const Text('拉取'),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: '清空（走 opencode.jsonc 默认）',
                onPressed: onClear,
                icon: const Icon(Icons.clear, size: 18),
              ),
          ],
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String value)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';
        if (text.isEmpty) return '不能为空';
        return validator?.call(text);
      },
    );
  }
}
