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
  bool _saving = false;

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
    _permissionTier =
        project?.permissionTier ?? DevProjectPermissionTier.readOnly.value;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rootPathController.dispose();
    _defaultBranchController.dispose();
    _bridgeUrlController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.project != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑 Dev 项目' : '新增 Dev 项目'),
        actions: [
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
              hint: 'personal-lab',
            ),
            const SizedBox(height: 14),
            _Field(
              controller: _bridgeUrlController,
              label: 'Bridge URL',
              hint: 'https://host.example.invalid',
              validator: (value) {
                final uri = Uri.tryParse(value.trim());
                if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
                  return '必须是 HTTPS 地址';
                }
                return null;
              },
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
                  child: Text('写入工作区（后续）'),
                ),
                DropdownMenuItem(
                  value: 'release_ops',
                  child: Text('发布操作（后续）'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _permissionTier = value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              _permissionDescription(_permissionTier),
              style: const TextStyle(
                height: 1.35,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Phase 1 会强制以 read_only 启动远程任务。Token、GitHub 权限和代理进程都只放在 Bridge 端。',
                style: TextStyle(
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _permissionDescription(String tier) {
    return switch (tier) {
      'workspace_write' => '后续允许代理在隔离 worktree 里改文件；commit、网络等高风险动作仍要逐条审批。',
      'release_ops' => '后续允许进入发布流程；commit、push、PR 等动作仍要逐条审批。',
      _ => '当前只允许读取项目和汇报进度，不允许写文件、提交、推送或联网操作。',
    };
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
