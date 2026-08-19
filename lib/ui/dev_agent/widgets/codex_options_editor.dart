import 'package:flutter/material.dart';
import 'package:memex/domain/models/dev_agent_codex_options.dart';

class CodexOptionsEditor extends StatefulWidget {
  const CodexOptionsEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.initiallyExpanded = false,
  });

  final DevAgentCodexOptions value;
  final ValueChanged<DevAgentCodexOptions> onChanged;
  final bool initiallyExpanded;

  @override
  State<CodexOptionsEditor> createState() => _CodexOptionsEditorState();
}

class _CodexOptionsEditorState extends State<CodexOptionsEditor> {
  late final TextEditingController _modelController;
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _modelController = TextEditingController(text: widget.value.model ?? '');
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(CodexOptionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextModel = widget.value.model ?? '';
    if (_modelController.text != nextModel) {
      _modelController.text = nextModel;
    }
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  void _applyPreset(DevAgentCodexOptions preset) {
    widget.onChanged(
      DevAgentCodexOptions(
        model: widget.value.model,
        reasoningEffort: preset.reasoningEffort,
        serviceTier: widget.value.serviceTier,
        verbosity: preset.verbosity,
      ),
    );
  }

  void _setModel(String? model) {
    widget.onChanged(widget.value.copyWith(
      model: model,
      clearModel: model == null || model.trim().isEmpty,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Codex 配置',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              widget.value.isEmpty
                  ? '当前全部继承电脑上的 Codex 设置'
                  : widget.value.summary,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('快速'),
                  onPressed: () => _applyPreset(DevAgentCodexOptions.quick),
                ),
                ActionChip(
                  label: const Text('均衡'),
                  onPressed: () => _applyPreset(DevAgentCodexOptions.balanced),
                ),
                ActionChip(
                  label: const Text('深入'),
                  onPressed: () => _applyPreset(DevAgentCodexOptions.deep),
                ),
                ActionChip(
                  label: const Text('全部继承'),
                  onPressed: () {
                    _modelController.clear();
                    widget.onChanged(DevAgentCodexOptions.inherited);
                  },
                ),
              ],
            ),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.tune, size: 18),
              label: Text(_expanded ? '收起高级设置' : '高级设置'),
            ),
            if (_expanded) ...[
              TextFormField(
                controller: _modelController,
                decoration: const InputDecoration(
                  labelText: '模型',
                  hintText: '留空继承，例如 gpt-5.6-terra',
                  border: OutlineInputBorder(),
                ),
                onChanged: _setModel,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final model in const [
                    'gpt-5.6-sol',
                    'gpt-5.6-terra',
                    'gpt-5.6-luna',
                  ])
                    InputChip(
                      label: Text(model.replaceFirst('gpt-', '')),
                      selected: widget.value.model == model,
                      onPressed: () {
                        _modelController.text = model;
                        _setModel(model);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey(
                    'reasoning-${widget.value.reasoningEffort ?? 'inherit'}'),
                initialValue: widget.value.reasoningEffort,
                decoration: const InputDecoration(
                  labelText: '思考深度',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('继承电脑设置')),
                  DropdownMenuItem(value: 'low', child: Text('低')),
                  DropdownMenuItem(value: 'medium', child: Text('中')),
                  DropdownMenuItem(value: 'high', child: Text('高')),
                  DropdownMenuItem(value: 'xhigh', child: Text('很高')),
                  DropdownMenuItem(value: 'max', child: Text('最大')),
                ],
                onChanged: (value) => widget.onChanged(widget.value.copyWith(
                  reasoningEffort: value,
                  clearReasoningEffort: value == null,
                )),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(
                    'verbosity-${widget.value.verbosity ?? 'inherit'}'),
                initialValue: widget.value.verbosity,
                decoration: const InputDecoration(
                  labelText: '回答详略',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('继承电脑设置')),
                  DropdownMenuItem(value: 'low', child: Text('简洁')),
                  DropdownMenuItem(value: 'medium', child: Text('标准')),
                  DropdownMenuItem(value: 'high', child: Text('详细')),
                ],
                onChanged: (value) => widget.onChanged(widget.value.copyWith(
                  verbosity: value,
                  clearVerbosity: value == null,
                )),
              ),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fast 加速通道'),
                subtitle: const Text('可用性和用量取决于当前 Codex 账户'),
                value: widget.value.serviceTier == 'fast',
                onChanged: (enabled) => widget.onChanged(
                  widget.value.copyWith(
                    serviceTier: enabled ? 'fast' : null,
                    clearServiceTier: !enabled,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
