import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';

enum ModelAssignmentMode { tasks, agents }

/// High-frequency model switcher.
///
/// [ModelAssignmentMode.tasks] updates the active agents behind a user-facing
/// product task together. [ModelAssignmentMode.agents] provides precise
/// per-agent recovery when one API route or model path is unavailable.
class TaskModelAssignmentPage extends StatefulWidget {
  const TaskModelAssignmentPage({
    super.key,
    this.initialMode = ModelAssignmentMode.tasks,
  });

  final ModelAssignmentMode initialMode;

  @override
  State<TaskModelAssignmentPage> createState() =>
      _TaskModelAssignmentPageState();
}

class _TaskModelAssignmentPageState extends State<TaskModelAssignmentPage> {
  static const _inheritDefault = '__inherit_default__';
  static const _gameAgentId = 'game_agent';
  static const _backgroundAsset = 'assets/images/雨玻璃.jpg';
  static const _warmSurface = Color(0xFFF8F6EB);
  static const _warmControl = Color(0xFFEDE9D8);
  static const _text = Color(0xFF293025);
  static const _secondary = Color(0xFF74766E);
  static const _accent = Color(0xFF6E7541);
  static const _divider = Color(0x1F5B5843);

  static const _tasks = <_TaskModelDefinition>[
    _TaskModelDefinition(
      id: 'chat',
      title: '聊天与互动',
      description: '日常聊天、主动联系、澄清补全与游戏角色扮演',
      membersLabel: '林埃聊天 · 主动联系 · 澄清补全 · 游戏跟随此项',
      agentIds: [
        AgentDefinitions.companionAgent,
        AgentDefinitions.checkinAgent,
        AgentDefinitions.clarificationResolutionAgent,
      ],
    ),
    _TaskModelDefinition(
      id: 'memory',
      title: '记忆整理',
      description: '记录整理、Fragment、凝结与角色记忆摘要',
      membersLabel: '记录整理 · 角色记忆摘要',
      agentIds: [
        AgentDefinitions.recordOrganizerAgent,
        AgentDefinitions.profileAgent,
      ],
    ),
    _TaskModelDefinition(
      id: 'schedule',
      title: '日程分析',
      description: '日程识别与路由刷新',
      membersLabel: '日程整理 · 日程路由',
      agentIds: [
        AgentDefinitions.scheduleAggregatorAgent,
        AgentDefinitions.scheduleRefreshRouterAgent,
      ],
    ),
    _TaskModelDefinition(
      id: 'content',
      title: '内容分析',
      description: '媒体、跨记录洞察、生活洞察与语义检索',
      membersLabel: '媒体分析 · 跨记录洞察 · 生活洞察 · 语义检索',
      agentIds: [
        AgentDefinitions.analyzeAssets,
        AgentDefinitions.lifeInsightAgent,
        AgentDefinitions.embeddingAgent,
      ],
    ),
  ];

  /// Only agents that are still on live code paths. Frozen PKM/Card and the
  /// legacy Chat/Comment entries intentionally stay out of this list.
  static const _agentGroups = <_AgentGroupDefinition>[
    _AgentGroupDefinition(
      title: '高频路径',
      agents: [
        _AgentModelDefinition(
          id: AgentDefinitions.companionAgent,
          title: '林埃聊天',
          description: '主聊天、共读与悬浮球对话',
        ),
        _AgentModelDefinition(
          id: _gameAgentId,
          title: '游戏角色扮演',
          description: 'SillyTavern 与后续游戏会话',
          followsAgentId: AgentDefinitions.companionAgent,
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.recordOrganizerAgent,
          title: '记录整理',
          description: 'User-truth、Fragment 与记忆凝结',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.checkinAgent,
          title: '主动联系',
          description: '主动消息与陪伴判断',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.scheduleAggregatorAgent,
          title: '日程整理',
          description: '日程与任务聚合',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.scheduleRefreshRouterAgent,
          title: '日程路由',
          description: '识别需要刷新的日程路径',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.analyzeAssets,
          title: '媒体分析',
          description: '图片、语音与附件分析',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.lifeInsightAgent,
          title: '生活洞察',
          description: '节律、健康、财务与日程观察',
        ),
      ],
    ),
    _AgentGroupDefinition(
      title: '基础能力',
      agents: [
        _AgentModelDefinition(
          id: AgentDefinitions.profileAgent,
          title: '角色记忆摘要',
          description: '角色上下文压缩与记忆摘要',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.clarificationResolutionAgent,
          title: '澄清与补全',
          description: '处理需要进一步确认的内容',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.embeddingAgent,
          title: '语义检索',
          description: 'Embedding 与相似度召回',
        ),
      ],
    ),
  ];

  late ModelAssignmentMode _mode;
  List<LLMConfig> _configs = const [];
  Map<String, String?> _taskSelectedKeys = const {};
  Map<String, String?> _agentSelectedKeys = const {};
  Set<String> _mixedTaskIds = const {};
  String _defaultKey = LLMConfig.defaultClientKey;
  bool _loading = true;
  String? _savingId;

  Iterable<_AgentModelDefinition> get _agents sync* {
    for (final group in _agentGroups) {
      yield* group.agents;
    }
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _load();
  }

  Future<void> _load() async {
    final configs = await UserStorage.getLLMConfigs();
    final defaultKey = await UserStorage.getDefaultLLMConfigKey();
    final agentSelected = <String, String?>{};

    for (final agent in _agents) {
      if (agent.followsAgentId != null) continue;
      final config = await UserStorage.getAgentConfig(agent.id);
      agentSelected[agent.id] = config.llmConfigKey;
    }
    // Task-only agents are included even if a future UI group changes.
    for (final task in _tasks) {
      for (final agentId in task.agentIds) {
        if (agentSelected.containsKey(agentId)) continue;
        final config = await UserStorage.getAgentConfig(agentId);
        agentSelected[agentId] = config.llmConfigKey;
      }
    }

    final taskState = _deriveTaskState(agentSelected);
    if (!mounted) return;
    setState(() {
      _configs = configs;
      _defaultKey = defaultKey;
      _agentSelectedKeys = agentSelected;
      _taskSelectedKeys = taskState.selected;
      _mixedTaskIds = taskState.mixed;
      _loading = false;
    });
  }

  ({Map<String, String?> selected, Set<String> mixed}) _deriveTaskState(
    Map<String, String?> agentSelected,
  ) {
    final selected = <String, String?>{};
    final mixed = <String>{};
    for (final task in _tasks) {
      final keys = task.agentIds.map((id) => agentSelected[id]).toSet();
      selected[task.id] = keys.isEmpty ? null : keys.first;
      if (keys.length > 1) mixed.add(task.id);
    }
    return (selected: selected, mixed: mixed);
  }

  Future<void> _saveTask(_TaskModelDefinition task, String value) async {
    if (_savingId != null) return;
    final savingId = 'task:${task.id}';
    setState(() => _savingId = savingId);
    final key = value == _inheritDefault ? null : value;

    try {
      final nextAgents = {..._agentSelectedKeys};
      for (final agentId in task.agentIds) {
        final current = await UserStorage.getAgentConfig(agentId);
        await UserStorage.saveAgentConfig(
          agentId,
          current.copyWith(llmConfigKey: key),
        );
        nextAgents[agentId] = key;
      }
      final taskState = _deriveTaskState(nextAgents);
      if (!mounted) return;
      setState(() {
        _agentSelectedKeys = nextAgents;
        _taskSelectedKeys = taskState.selected;
        _mixedTaskIds = taskState.mixed;
      });
      _showSaved('${task.title}已切换');
    } catch (error) {
      _showError('切换失败：$error');
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  Future<void> _saveAgent(_AgentModelDefinition agent, String value) async {
    if (_savingId != null || agent.followsAgentId != null) return;
    final savingId = 'agent:${agent.id}';
    setState(() => _savingId = savingId);
    final key = value == _inheritDefault ? null : value;

    try {
      final current = await UserStorage.getAgentConfig(agent.id);
      await UserStorage.saveAgentConfig(
        agent.id,
        current.copyWith(llmConfigKey: key),
      );
      final nextAgents = {..._agentSelectedKeys, agent.id: key};
      final taskState = _deriveTaskState(nextAgents);
      if (!mounted) return;
      setState(() {
        _agentSelectedKeys = nextAgents;
        _taskSelectedKeys = taskState.selected;
        _mixedTaskIds = taskState.mixed;
      });
      _showSaved('${agent.title}已切换');
    } catch (error) {
      _showError('切换失败：$error');
    } finally {
      if (mounted) setState(() => _savingId = null);
    }
  }

  void _showSaved(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _configLabel(LLMConfig config) {
    final model = config.modelId.trim();
    return model.isEmpty ? config.key : '${config.key} · $model';
  }

  String _effectiveModelLabel(String? selected) {
    final key = selected ?? _defaultKey;
    for (final config in _configs) {
      if (config.key == key) return _configLabel(config);
    }
    return '尚未配置';
  }

  String _dropdownValue(String? selected) {
    if (selected == null || !_configs.any((config) => config.key == selected)) {
      return _inheritDefault;
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: _warmSurface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF243029),
        body: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Image.asset(
                _backgroundAsset,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.2),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: Container(
                      key: const ValueKey('task_model_warm_surface'),
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: _warmSurface,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(color: _accent),
                            )
                          : ListView(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 18, 20, 32),
                              children: [
                                _buildModeSwitch(),
                                const SizedBox(height: 16),
                                Text(
                                  _mode == ModelAssignmentMode.tasks
                                      ? '按用途会同时切换这一用途下的全部 Agent。游戏始终跟随聊天模型。'
                                      : '这是同一套配置的逐 Agent 视图；可单独覆盖某条路径，也可看见明确的跟随关系。',
                                  style: const TextStyle(
                                    color: _secondary,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (_mode == ModelAssignmentMode.tasks)
                                  for (final task in _tasks) _buildTask(task)
                                else
                                  for (final group in _agentGroups) ...[
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        2,
                                        14,
                                        2,
                                        2,
                                      ),
                                      child: Text(
                                        group.title,
                                        style: const TextStyle(
                                          color: _secondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    for (final agent in group.agents)
                                      _buildAgent(agent),
                                  ],
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            color: const Color(0xFFF8FBF8),
          ),
          const Expanded(
            child: Text(
              '模型分配',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFF8FBF8),
                fontWeight: FontWeight.w600,
                fontSize: 17,
                shadows: [Shadow(color: Colors.black45, blurRadius: 8)],
              ),
            ),
          ),
          const SizedBox(width: 56),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    return Container(
      key: const ValueKey('model_assignment_mode_switch'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _warmControl,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _ModeButton(
            label: '按用途',
            selected: _mode == ModelAssignmentMode.tasks,
            onTap: () => setState(() => _mode = ModelAssignmentMode.tasks),
          ),
          _ModeButton(
            label: '按 Agent',
            selected: _mode == ModelAssignmentMode.agents,
            onTap: () => setState(() => _mode = ModelAssignmentMode.agents),
          ),
        ],
      ),
    );
  }

  Widget _buildTask(_TaskModelDefinition task) {
    final selected = _taskSelectedKeys[task.id];
    final saving = _savingId == 'task:${task.id}';
    final mixed = _mixedTaskIds.contains(task.id);
    return _AssignmentRow(
      title: task.title,
      description: task.description,
      technicalLabel:
          mixed ? '包含单独配置 · ${task.membersLabel}' : task.membersLabel,
      saving: saving,
      child: _buildDropdown(
        key: ValueKey('task-model-${task.id}-${_dropdownValue(selected)}'),
        selected: selected,
        enabled: _savingId == null,
        onChanged: (value) => _saveTask(task, value),
      ),
    );
  }

  Widget _buildAgent(_AgentModelDefinition agent) {
    final followsAgentId = agent.followsAgentId;
    final selected = _agentSelectedKeys[followsAgentId ?? agent.id];
    final saving = followsAgentId == null && _savingId == 'agent:${agent.id}';
    return _AssignmentRow(
      title: agent.title,
      description: agent.description,
      technicalLabel:
          followsAgentId == null ? agent.id : '${agent.id} · 不单独保存模型配置',
      saving: saving,
      child: followsAgentId != null
          ? _InheritedModelLabel(
              text: '跟随林埃聊天 · ${_effectiveModelLabel(selected)}',
            )
          : _buildDropdown(
              key: ValueKey(
                  'agent-model-${agent.id}-${_dropdownValue(selected)}'),
              selected: selected,
              enabled: _savingId == null,
              onChanged: (value) => _saveAgent(agent, value),
            ),
    );
  }

  Widget _buildDropdown({
    required Key key,
    required String? selected,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: key,
      initialValue: _dropdownValue(selected),
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: _warmControl,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      ),
      items: [
        DropdownMenuItem(
          value: _inheritDefault,
          child: Text('继承默认 · ${_effectiveModelLabel(null)}'),
        ),
        for (final config in _configs)
          DropdownMenuItem(
            value: config.key,
            child: Text(
              _configLabel(config),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled
          ? (value) {
              if (value != null) onChanged(value);
            }
          : null,
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? _TaskModelAssignmentPageState._warmSurface : null,
            borderRadius: BorderRadius.circular(9),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x145B5843),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? _TaskModelAssignmentPageState._text
                  : _TaskModelAssignmentPageState._secondary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  const _AssignmentRow({
    required this.title,
    required this.description,
    required this.saving,
    required this.child,
    this.technicalLabel,
  });

  final String title;
  final String description;
  final String? technicalLabel;
  final bool saving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _TaskModelAssignmentPageState._divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _TaskModelAssignmentPageState._text,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              if (saving)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _TaskModelAssignmentPageState._accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            description,
            style: const TextStyle(
              color: _TaskModelAssignmentPageState._secondary,
            ),
          ),
          if (technicalLabel != null) ...[
            const SizedBox(height: 2),
            Text(
              technicalLabel!,
              style: const TextStyle(
                color: _TaskModelAssignmentPageState._secondary,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InheritedModelLabel extends StatelessWidget {
  const _InheritedModelLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: _TaskModelAssignmentPageState._warmControl,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: _TaskModelAssignmentPageState._accent),
      ),
    );
  }
}

class _TaskModelDefinition {
  const _TaskModelDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.membersLabel,
    required this.agentIds,
  });

  final String id;
  final String title;
  final String description;
  final String membersLabel;
  final List<String> agentIds;
}

class _AgentGroupDefinition {
  const _AgentGroupDefinition({required this.title, required this.agents});

  final String title;
  final List<_AgentModelDefinition> agents;
}

class _AgentModelDefinition {
  const _AgentModelDefinition({
    required this.id,
    required this.title,
    required this.description,
    this.followsAgentId,
  });

  final String id;
  final String title;
  final String description;
  final String? followsAgentId;
}
