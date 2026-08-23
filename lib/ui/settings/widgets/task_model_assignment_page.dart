import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memex/data/services/model_test_service.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/themes/spring_rain_ui_tokens.dart';
import 'package:memex/utils/user_storage.dart';

enum ModelAssignmentMode { tasks, agents }

/// Connectivity status for a single LLM config.
enum _ConnectivityStatus { idle, testing, ok, fail }

class _ConnectivityState {
  final _ConnectivityStatus status;
  final String? error;
  final Duration? responseTime;

  const _ConnectivityState({
    this.status = _ConnectivityStatus.idle,
    this.error,
    this.responseTime,
  });

  _ConnectivityState copyWith({
    _ConnectivityStatus? status,
    String? error,
    Duration? responseTime,
  }) {
    return _ConnectivityState(
      status: status ?? this.status,
      error: error,
      responseTime: responseTime ?? this.responseTime,
    );
  }
}

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
  static const _backgroundAsset = 'assets/images/闆ㄧ幓鐠?jpg';
  static const _warmSurface = SpringRainUiTokens.daylightCanvas;
  static const _warmControl = SpringRainUiTokens.daylightSurfaceMuted;
  static const _text = SpringRainUiTokens.daylightTextPrimary;
  static const _secondary = SpringRainUiTokens.daylightTextSecondary;
  static const _accent = SpringRainUiTokens.daylightAccent;
  static const _divider = SpringRainUiTokens.daylightDivider;

  static const _tasks = <_TaskModelDefinition>[
    _TaskModelDefinition(
      id: 'chat',
      title: '鑱婂ぉ涓庝簰鍔?,
      description: '鏃ュ父鑱婂ぉ銆佷富鍔ㄨ仈绯汇€佹緞娓呰ˉ鍏ㄤ笌娓告垙瑙掕壊鎵紨',
      membersLabel: '鏋楀焹鑱婂ぉ 路 涓诲姩鑱旂郴 路 婢勬竻琛ュ叏 路 娓告垙璺熼殢姝ら」',
      agentIds: [
        AgentDefinitions.companionAgent,
        AgentDefinitions.checkinAgent,
        AgentDefinitions.clarificationResolutionAgent,
      ],
    ),
    _TaskModelDefinition(
      id: 'memory',
      title: '璁板繂鏁寸悊',
      description: '璁板綍鏁寸悊銆丗ragment銆佸嚌缁撲笌瑙掕壊璁板繂鎽樿',
      membersLabel: '璁板綍鏁寸悊 路 瑙掕壊璁板繂鎽樿',
      agentIds: [
        AgentDefinitions.recordOrganizerAgent,
        AgentDefinitions.profileAgent,
      ],
    ),
    _TaskModelDefinition(
      id: 'schedule',
      title: '鏃ョ▼鍒嗘瀽',
      description: '鏃ョ▼璇嗗埆涓庤矾鐢卞埛鏂?,
      membersLabel: '鏃ョ▼鏁寸悊 路 鏃ョ▼璺敱',
      agentIds: [
        AgentDefinitions.scheduleAggregatorAgent,
        AgentDefinitions.scheduleRefreshRouterAgent,
      ],
    ),
    _TaskModelDefinition(
      id: 'content',
      title: '鍐呭鍒嗘瀽',
      description: '濯掍綋銆佽法璁板綍娲炲療銆佺敓娲绘礊瀵熶笌璇箟妫€绱?,
      membersLabel: '濯掍綋鍒嗘瀽 路 璺ㄨ褰曟礊瀵?路 鐢熸椿娲炲療 路 璇箟妫€绱?,
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
      title: '楂橀璺緞',
      agents: [
        _AgentModelDefinition(
          id: AgentDefinitions.companionAgent,
          title: '鏋楀焹鑱婂ぉ',
          description: '涓昏亰澶┿€佸叡璇讳笌鎮诞鐞冨璇?,
        ),
        _AgentModelDefinition(
          id: _gameAgentId,
          title: '娓告垙瑙掕壊鎵紨',
          description: 'SillyTavern 涓庡悗缁父鎴忎細璇?,
          followsAgentId: AgentDefinitions.companionAgent,
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.recordOrganizerAgent,
          title: '璁板綍鏁寸悊',
          description: 'User-truth銆丗ragment 涓庤蹇嗗嚌缁?,
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.checkinAgent,
          title: '涓诲姩鑱旂郴',
          description: '涓诲姩娑堟伅涓庨櫔浼村垽鏂?,
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.scheduleAggregatorAgent,
          title: '鏃ョ▼鏁寸悊',
          description: '鏃ョ▼涓庝换鍔¤仛鍚?,
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.scheduleRefreshRouterAgent,
          title: '鏃ョ▼璺敱',
          description: '璇嗗埆闇€瑕佸埛鏂扮殑鏃ョ▼璺緞',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.analyzeAssets,
          title: '濯掍綋鍒嗘瀽',
          description: '鍥剧墖銆佽闊充笌闄勪欢鍒嗘瀽',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.lifeInsightAgent,
          title: '鐢熸椿娲炲療',
          description: '鑺傚緥銆佸仴搴枫€佽储鍔′笌鏃ョ▼瑙傚療',
        ),
      ],
    ),
    _AgentGroupDefinition(
      title: '鍩虹鑳藉姏',
      agents: [
        _AgentModelDefinition(
          id: AgentDefinitions.profileAgent,
          title: '瑙掕壊璁板繂鎽樿',
          description: '瑙掕壊涓婁笅鏂囧帇缂╀笌璁板繂鎽樿',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.clarificationResolutionAgent,
          title: '婢勬竻涓庤ˉ鍏?,
          description: '澶勭悊闇€瑕佽繘涓€姝ョ‘璁ょ殑鍐呭',
        ),
        _AgentModelDefinition(
          id: AgentDefinitions.embeddingAgent,
          title: '璇箟妫€绱?,
          description: 'Embedding 涓庣浉浼煎害鍙洖',
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
  Map<String, _ConnectivityState> _connectivity = const {};

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
    // Kick off connectivity tests for all configured models after the
    // page is interactive. Staggered to avoid overwhelming the network.
    _testAllConnectivity();
  }

  Future<void> _testAllConnectivity() async {
    for (var i = 0; i < _configs.length; i++) {
      final config = _configs[i];
      if (!config.isValid) continue;
      // Stagger tests so they don't all hit the network at once.
      await Future.delayed(Duration(milliseconds: i * 200));
      if (!mounted) return;
      _testConnectivity(config.key);
    }
  }

  Future<void> _testConnectivity(String configKey) async {
    final config =
        _configs.where((c) => c.key == configKey).firstOrNull;
    if (config == null || !config.isValid) return;

    if (!mounted) return;
    setState(() {
      _connectivity = {
        ..._connectivity,
        configKey: const _ConnectivityState(
            status: _ConnectivityStatus.testing),
      };
    });

    final result = await ModelTestService.testConfig(config);

    if (!mounted) return;
    setState(() {
      _connectivity = {
        ..._connectivity,
        configKey: _ConnectivityState(
          status: result.success ? _ConnectivityStatus.ok : _ConnectivityStatus.fail,
          error: result.error,
          responseTime: result.responseTime,
        ),
      };
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
      _showSaved('${task.title}宸插垏鎹?);
    } catch (error) {
      _showError('鍒囨崲澶辫触锛?error');
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
      _showSaved('${agent.title}宸插垏鎹?);
    } catch (error) {
      _showError('鍒囨崲澶辫触锛?error');
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
    return model.isEmpty ? config.key : '${config.key} 路 $model';
  }

  String _effectiveModelLabel(String? selected) {
    final key = selected ?? _defaultKey;
    for (final config in _configs) {
      if (config.key == key) return _configLabel(config);
    }
    return '灏氭湭閰嶇疆';
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
        backgroundColor: HereIamThemeTokens.springRainDaydream.background,
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
                                      ? '鎸夌敤閫斾細鍚屾椂鍒囨崲杩欎竴鐢ㄩ€斾笅鐨勫叏閮?Agent銆傛父鎴忓缁堣窡闅忚亰澶╂ā鍨嬨€?
                                      : '杩欐槸鍚屼竴濂楅厤缃殑閫?Agent 瑙嗗浘锛涘彲鍗曠嫭瑕嗙洊鏌愭潯璺緞锛屼篃鍙湅瑙佹槑纭殑璺熼殢鍏崇郴銆?,
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
            color: SpringRainUiTokens.daylightTextOnAccent,
          ),
          const Expanded(
            child: Text(
              '妯″瀷鍒嗛厤',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SpringRainUiTokens.daylightTextOnAccent,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                shadows: [
                  Shadow(color: Color(0x73293025), blurRadius: 8),
                ],
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
            label: '鎸夌敤閫?,
            selected: _mode == ModelAssignmentMode.tasks,
            onTap: () => setState(() => _mode = ModelAssignmentMode.tasks),
          ),
          _ModeButton(
            label: '鎸?Agent',
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
          mixed ? '鍖呭惈鍗曠嫭閰嶇疆 路 ${task.membersLabel}' : task.membersLabel,
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
          followsAgentId == null ? agent.id : '${agent.id} 路 涓嶅崟鐙繚瀛樻ā鍨嬮厤缃?,
      saving: saving,
      child: followsAgentId != null
          ? _InheritedModelLabel(
              text: '璺熼殢鏋楀焹鑱婂ぉ 路 ${_effectiveModelLabel(selected)}',
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
    final effectiveKey = selected ?? _defaultKey;
    final connState = _connectivity[effectiveKey] ??
        const _ConnectivityState();
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
        suffixIcon: _ConnectivityBadge(
          state: connState,
          onTap: () => _testConnectivity(effectiveKey),
        ),
      ),
      items: [
        DropdownMenuItem(
          value: _inheritDefault,
          child: _DropdownItem(
            text: '缁ф壙榛樿 路 ${_effectiveModelLabel(null)}',
            status: _connectivity[_defaultKey]?.status ??
                _ConnectivityStatus.idle,
          ),
        ),
        for (final config in _configs)
          DropdownMenuItem(
            value: config.key,
            child: _DropdownItem(
              text: _configLabel(config),
              status:
                  _connectivity[config.key]?.status ?? _ConnectivityStatus.idle,
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

/// Small colored dot showing model connectivity status. Tappable to retest.
class _ConnectivityBadge extends StatelessWidget {
  const _ConnectivityBadge({required this.state, this.onTap});

  final _ConnectivityState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = state.status;
    final (color, label) = switch (status) {
      _ConnectivityStatus.ok => (
        const Color(0xFF5B8C5A),
        state.responseTime != null
            ? '鍙敤 ${_formatDuration(state.responseTime!)}'
            : '鍙敤'
      ),
      _ConnectivityStatus.fail => (
        const Color(0xFFC46B5A),
        _shortError(state.error) ?? '涓嶅彲鐢?
      ),
      _ConnectivityStatus.testing => (
        _TaskModelAssignmentPageState._accent,
        '娴嬭瘯涓?
      ),
      _ConnectivityStatus.idle => (
        _TaskModelAssignmentPageState._secondary,
        '鏈祴璇?
      ),
    };
    final dot = status == _ConnectivityStatus.testing
        ? SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: color,
            ),
          )
        : Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            dot,
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '${ms}ms';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  static String? _shortError(String? error) {
    if (error == null || error.trim().isEmpty) return null;
    var s = error.trim();
    // Common noise that doesn't help the user.
    s = s.replaceFirst(RegExp(r'^DioException:\s*'), '');
    s = s.replaceFirst(RegExp(r'^Exception:\s*'), '');
    if (s.length > 40) s = '${s.substring(0, 40)}鈥?;
    return s;
  }
}

/// Dropdown menu item with a connectivity dot beside the model label.
class _DropdownItem extends StatelessWidget {
  const _DropdownItem({required this.text, required this.status});

  final String text;
  final _ConnectivityStatus status;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (status) {
      _ConnectivityStatus.ok => const Color(0xFF5B8C5A),
      _ConnectivityStatus.fail => const Color(0xFFC46B5A),
      _ConnectivityStatus.testing => _TaskModelAssignmentPageState._accent,
      _ConnectivityStatus.idle => _TaskModelAssignmentPageState._secondary,
    };
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}
