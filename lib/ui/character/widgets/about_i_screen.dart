import 'dart:async';

import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:memex/data/memory_v3/services/dreaming_orchestrator_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_recall_log_service.dart';
import 'package:memex/data/memory_v3/services/dreaming_scheduler_service.dart';
import 'package:memex/data/services/character_service.dart';
import 'package:memex/data/services/media_service.dart';
import 'package:memex/domain/models/character_model.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/companion/widgets/companion_life_space_screen.dart';
import 'package:memex/ui/memory/widgets/memory_v3_lab_screen.dart';
import 'package:memex/ui/core/themes/here_iam_theme_tokens.dart';
import 'package:memex/ui/core/widgets/agent_logo_loading.dart';
import 'package:memex/ui/core/widgets/avatar_picker.dart';
import 'package:memex/ui/core/widgets/character_avatar.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

/// User-facing companion profile and Dreaming health surface.
class AboutIScreen extends StatefulWidget {
  const AboutIScreen({super.key});

  @override
  State<AboutIScreen> createState() => _AboutIScreenState();
}

class _AboutIScreenState extends State<AboutIScreen> {
  static const _rain = 'assets/images/雨玻璃.jpg';
  static const _ink = Color(0xFF293025);
  static const _muted = Color(0xFF667061);
  static const _greenSurface = Color(0xFFF0F2E3);
  static const _accent = Color(0xFF737B46);

  CharacterModel? _character;
  List<MemoryFragment> _fragments = const [];
  List<MemoryEpisode> _episodes = const [];
  List<MemorySaga> _sagas = const [];
  List<DreamingRecallLogEntry> _recalls = const [];
  bool _loading = true;
  bool _busy = false;
  int _recentPage = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = await UserStorage.getUserId();
    final character = userId == null
        ? null
        : await CharacterService.instance.getPrimaryCompanion(userId);
    final db = AppDatabase.instance;
    final results = await Future.wait([
      (db.select(db.memoryFragments)
            ..where((t) => t.status.isNotIn(['deleted']))
            ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
            ..limit(30))
          .get(),
      (db.select(db.memoryEpisodes)
            ..where((t) => t.status.isNotIn(['deleted']))
            ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
            ..limit(20))
          .get(),
      (db.select(db.memorySagas)
            ..where((t) => t.status.isNotIn(['deleted']))
            ..orderBy([(t) => drift.OrderingTerm.desc(t.updatedAt)])
            ..limit(20))
          .get(),
      DreamingRecallLogService.readAll(),
    ]);
    if (!mounted) return;
    setState(() {
      _character = character;
      _fragments = results[0] as List<MemoryFragment>;
      _episodes = results[1] as List<MemoryEpisode>;
      _sagas = results[2] as List<MemorySaga>;
      _recalls = results[3] as List<DreamingRecallLogEntry>;
      _loading = false;
    });
  }

  Future<String?> _latestCharacterId() async {
    final row = await (AppDatabase.instance
            .select(AppDatabase.instance.personaChatMessages)
          ..orderBy([
            (t) => drift.OrderingTerm.desc(t.timestamp),
            (t) => drift.OrderingTerm.desc(t.id),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.characterId ?? _character?.id;
  }

  Future<void> _runMaintenance(_MemoryMaintenance action) async {
    if (_busy || !DreamingOrchestratorServiceV3.isInitialized) {
      if (!DreamingOrchestratorServiceV3.isInitialized && mounted) {
        _toast('记忆整理服务尚未初始化');
      }
      return;
    }
    setState(() => _busy = true);
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.recordOrganizerAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final orchestrator = DreamingOrchestratorServiceV3.instance;
      switch (action) {
        case _MemoryMaintenance.fragments:
          final characterId = await _latestCharacterId();
          if (characterId == null) throw StateError('还没有可以整理的聊天');
          final result = await orchestrator.runDailyFragmentBatch(
            characterId: characterId,
            client: resources.client,
            modelConfig: resources.modelConfig,
          );
          _toast(result.processedMessageCount == 0
              ? '没有新的聊天需要提取'
              : '已从 ${result.processedMessageCount} 条聊天提取 ${result.fragmentIds.length} 个碎片');
        case _MemoryMaintenance.episodes:
          final result = await orchestrator.runEpisodeConsolidation(
            client: resources.client,
            modelConfig: resources.modelConfig,
          );
          _toast(result.isEmpty
              ? '暂时没有足够的碎片可以凝结'
              : '已凝结 ${result.episodeIds.length} 段经历');
        case _MemoryMaintenance.sagas:
          final result = await orchestrator.runSagaWeaving(
            client: resources.client,
            modelConfig: resources.modelConfig,
            forceRun: true,
          );
          _toast(result.isEmpty ? '长期记忆暂时没有变化' : '长期记忆检查完成');
        case _MemoryMaintenance.all:
          final characterId = await _latestCharacterId();
          if (characterId == null) throw StateError('还没有可以整理的聊天');
          await DreamingSchedulerService.runDailyDreamingFromBackground(
            db: AppDatabase.instance,
            characterId: characterId,
            forceRun: true,
          );
          _toast('完整整理已完成');
      }
      await _load();
    } catch (e) {
      _toast('整理没有完成：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  List<_RecentMemoryItem> get _recentItems {
    final items = <_RecentMemoryItem>[
      ..._episodes
          .map((e) => _RecentMemoryItem('我们的经历', e.narrative, e.updatedAt)),
      ..._sagas.map((e) => _RecentMemoryItem('长期记忆', e.title, e.updatedAt)),
      ..._fragments
          .map((e) => _RecentMemoryItem('记忆碎片', e.content, e.createdAt)),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return items.take(3).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenSurface,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : Stack(children: [
              Positioned.fill(child: Image.asset(_rain, fit: BoxFit.cover)),
              SafeArea(
                bottom: false,
                child: Column(children: [
                  _topBar(),
                  const SizedBox(height: 16),
                  _identityHeader(),
                  const SizedBox(height: 22),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: _greenSurface,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(30)),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(18, 22, 18, 34),
                        children: [
                          _recentMemories(),
                          const SizedBox(height: 22),
                          _sectionTitle('记忆系统'),
                          const SizedBox(height: 8),
                          _memoryRow(
                              '记忆碎片',
                              'Fragment',
                              _fragments.length,
                              () => _showMemoryList('记忆碎片',
                                  _fragments.map((e) => e.content).toList())),
                          _memoryRow(
                              '我们的经历',
                              'Episode',
                              _episodes.length,
                              () => _showMemoryList('我们的经历',
                                  _episodes.map((e) => e.narrative).toList())),
                          _memoryRow(
                              '长期记忆',
                              'Saga',
                              _sagas.length,
                              () => _showMemoryList(
                                  '长期记忆',
                                  _sagas
                                      .map(
                                          (e) => '${e.title}\n${e.description}')
                                      .toList())),
                          _memoryRow(
                              '最近想起',
                              'Recall Log',
                              _recalls.length,
                              () => _showMemoryList(
                                  '最近想起',
                                  _recalls
                                      .map((e) => e.actualSummary)
                                      .toList())),
                          const SizedBox(height: 22),
                          _sectionTitle('手动整理'),
                          const SizedBox(height: 8),
                          _maintenanceGrid(),
                          const SizedBox(height: 18),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.water_drop_outlined,
                                color: _accent),
                            title: const Text('你主动记录的内容',
                                style: TextStyle(color: _ink)),
                            trailing: const Icon(Icons.chevron_right_rounded,
                                color: _muted),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) =>
                                        const CompanionLifeSpaceScreen())),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.science_outlined,
                                color: _muted),
                            title: const Text('高级记忆检查',
                                style: TextStyle(color: _ink)),
                            subtitle: const Text('原始数据、危险操作与完整日志',
                                style: TextStyle(color: _muted, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded,
                                color: _muted),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const MemoryV3LabScreen())),
                          ),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(children: [
          IconButton.filledTonal(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            style: IconButton.styleFrom(
                backgroundColor: const Color(0xA8F5F1E7),
                foregroundColor: _ink),
          ),
          const Expanded(
              child: Text('关于林埃',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Color(0xFFF7F2E7),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      shadows: [
                        Shadow(color: Colors.black45, blurRadius: 5)
                      ]))),
          TextButton(
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const _IEditScreen()));
              await _load();
            },
            style: TextButton.styleFrom(
                backgroundColor: const Color(0xA8F5F1E7),
                foregroundColor: _ink),
            child: const Text('编辑'),
          ),
        ]),
      );

  Widget _identityHeader() => Row(children: [
        const SizedBox(width: 24),
        CharacterAvatar(avatar: _character?.avatar, name: '林埃', size: 82),
        const SizedBox(width: 16),
        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('林埃',
              style: TextStyle(
                  color: Color(0xFFF7F2E7),
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 5)])),
          SizedBox(height: 4),
          Text('与你一起生活，也会重新想起',
              style: TextStyle(
                  color: Color(0xE8F7F2E7),
                  fontSize: 13,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 5)])),
        ]),
      ]);

  Widget _recentMemories() {
    final items = _recentItems;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('最近整理'),
      const SizedBox(height: 10),
      if (items.isEmpty)
        _softCard(const Text('还没有整理出的共同记忆', style: TextStyle(color: _muted)))
      else ...[
        SizedBox(
          // The previous 132px viewport was shorter than the padded three-line
          // memory card at Android's larger text scale and produced a bottom
          // RenderFlex overflow. Keep the horizontal carousel, but give the
          // card enough vertical room without clipping its content.
          height: 168,
          child: PageView.builder(
            controller: PageController(viewportFraction: .9),
            itemCount: items.length,
            onPageChanged: (value) => setState(() => _recentPage = value),
            itemBuilder: (_, index) {
              final item = items[index];
              return Padding(
                padding:
                    EdgeInsets.only(right: index == items.length - 1 ? 0 : 10),
                child: _softCard(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(item.type,
                            style: const TextStyle(
                                color: _accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${index + 1}/${items.length}',
                            style:
                                const TextStyle(color: _muted, fontSize: 11)),
                      ]),
                      const SizedBox(height: 10),
                      Text(item.text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: _ink, fontSize: 14, height: 1.45)),
                    ])),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < items.length; i++)
            AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _recentPage ? 14 : 5,
                height: 5,
                decoration: BoxDecoration(
                    color: i == _recentPage
                        ? _accent
                        : _accent.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(9))),
        ]),
      ],
    ]);
  }

  Widget _sectionTitle(String text) => Text(text,
      style: const TextStyle(
          color: _ink, fontSize: 16, fontWeight: FontWeight.w700));

  Widget _softCard(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xDDFBF9F1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white70)),
        child: child,
      );

  Widget _memoryRow(
          String title, String technical, int count, VoidCallback onTap) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title,
            style: const TextStyle(color: _ink, fontWeight: FontWeight.w600)),
        subtitle: Text(technical,
            style: const TextStyle(color: _muted, fontSize: 11)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$count', style: const TextStyle(color: _muted)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: _muted),
        ]),
        onTap: onTap,
      );

  Widget _maintenanceGrid() {
    final actions = [
      ('提取记忆碎片', Icons.scatter_plot_outlined, _MemoryMaintenance.fragments),
      ('凝结我们的经历', Icons.auto_awesome_outlined, _MemoryMaintenance.episodes),
      ('检查长期记忆', Icons.timeline_rounded, _MemoryMaintenance.sagas),
      ('完整整理一次', Icons.sync_rounded, _MemoryMaintenance.all),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.35,
      children: [
        for (final item in actions)
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _runMaintenance(item.$3),
            icon: _busy && item.$3 == _MemoryMaintenance.all
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(item.$2, size: 17),
            label: Text(item.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: Color(0x55737B46)),
                backgroundColor: const Color(0xB8FBF9F1),
                padding: const EdgeInsets.symmetric(horizontal: 10)),
          ),
      ],
    );
  }

  void _showMemoryList(String title, List<String> values) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7F6ED),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .72,
        maxChildSize: .92,
        builder: (context, controller) => Column(children: [
          const SizedBox(height: 10),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0x55737B46),
                  borderRadius: BorderRadius.circular(4))),
          Padding(
              padding: const EdgeInsets.all(18),
              child: Text(title,
                  style: const TextStyle(
                      color: _ink, fontSize: 18, fontWeight: FontWeight.w700))),
          Expanded(
              child: values.isEmpty
                  ? const Center(
                      child: Text('暂时没有内容', style: TextStyle(color: _muted)))
                  : ListView.separated(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      itemCount: values.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _softCard(Text(values[i],
                          style: const TextStyle(color: _ink, height: 1.45))))),
        ]),
      ),
    );
  }
}

enum _MemoryMaintenance { fragments, episodes, sagas, all }

class _RecentMemoryItem {
  const _RecentMemoryItem(this.type, this.text, this.timestamp);
  final String type;
  final String text;
  final int timestamp;
}

/// Editing is intentionally a separate route so the profile avatar and the
/// edit action do not perform the same operation.
class _IEditScreen extends StatefulWidget {
  const _IEditScreen();

  @override
  State<_IEditScreen> createState() => _IEditScreenState();
}

class _IEditScreenState extends State<_IEditScreen> {
  final _logger = getLogger('AboutIScreen');

  bool _isLoading = true;
  CharacterModel? _character;
  String? _avatarPreview;

  final _ttsVoiceIdController = TextEditingController();
  final _ttsVoiceIdFocusNode = FocusNode();
  Timer? _ttsVoiceIdSaveDebounce;
  String? _lastPersistedTtsVoiceId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final primary =
          await CharacterService.instance.getPrimaryCompanion(userId);
      if (!mounted) return;
      setState(() {
        _character = primary;
        _avatarPreview = primary?.avatar;
        _ttsVoiceIdController.text = primary?.ttsVoiceId ?? '';
        _lastPersistedTtsVoiceId = primary?.ttsVoiceId;
        _isLoading = false;
      });
    } catch (e, s) {
      _logger.severe('Failed to load I', e, s);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _ttsVoiceIdSaveDebounce?.cancel();
    if (_isTtsVoiceIdDirty()) {
      _flushTtsVoiceIdSave();
    }
    _ttsVoiceIdController.dispose();
    _ttsVoiceIdFocusNode.dispose();
    super.dispose();
  }

  bool _isTtsVoiceIdDirty() {
    final current = _ttsVoiceIdController.text.trim();
    final saved = _lastPersistedTtsVoiceId ?? '';
    return current != saved;
  }

  void _onTtsVoiceIdChanged(String _) {
    _ttsVoiceIdSaveDebounce?.cancel();
    _ttsVoiceIdSaveDebounce = Timer(
      const Duration(milliseconds: 600),
      _saveTtsVoiceId,
    );
  }

  void _flushTtsVoiceIdSave() {
    _ttsVoiceIdSaveDebounce?.cancel();
    if (_isTtsVoiceIdDirty()) {
      _saveTtsVoiceId();
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await showAvatarPicker(
      context,
      _avatarPreview ?? '',
      onPickGallery: _pickAvatarFromGallery,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (!CharacterService.isRelativeAvatarPath(picked)) {
        _avatarPreview = picked;
      }
    });
    await _persistField('avatar', picked);
  }

  Future<String?> _pickAvatarFromGallery() async {
    try {
      final pickedPath = await pickAvatarImageFromGallery();
      if (pickedPath == null) return null;
      final userId = await UserStorage.getUserId();
      if (userId == null) return null;
      final imported = await MediaService.instance.importImage(
        userId: userId,
        sourcePath: pickedPath,
      );
      if (!mounted) return null;
      setState(() => _avatarPreview = imported.absolutePath);
      return imported.relativePath;
    } catch (e, s) {
      _logger.warning('Failed to pick avatar', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.operationFailed(e.toString()),
        );
      }
      return null;
    }
  }

  Future<void> _saveTtsVoiceId() async {
    final value = _ttsVoiceIdController.text.trim();
    final next = value.isEmpty ? null : value;
    if ((_lastPersistedTtsVoiceId ?? '') == (next ?? '')) return;
    final character = _character;
    if (character == null) return;
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: character.id,
        updates: {'tts_voice_id': next},
      );
      if (!mounted) return;
      if (updated != null) {
        setState(() {
          _character = updated;
          _lastPersistedTtsVoiceId = next;
        });
      }
    } catch (e, s) {
      _logger.warning('Failed to persist tts_voice_id', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.saveFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _persistField(String key, dynamic value) async {
    final character = _character;
    if (character == null) return;
    try {
      final userId = await UserStorage.getUserId();
      if (userId == null) return;
      final updated = await CharacterService.instance.updateCharacter(
        userId: userId,
        characterId: character.id,
        updates: {key: value},
      );
      if (!mounted || updated == null) return;
      setState(() {
        _character = updated;
        _avatarPreview = updated.avatar;
      });
    } catch (e, s) {
      _logger.warning('Failed to persist $key', e, s);
      if (mounted) {
        ToastHelper.showError(
          context,
          UserStorage.l10n.saveFailed(e.toString()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const skin = HereIamThemeTokens.springRainDaydream;
    return Scaffold(
      backgroundColor: skin.background,
      appBar: AppBar(
        backgroundColor: skin.background,
        elevation: 0,
        centerTitle: true,
        title: Text(
          '编辑林埃',
          style: TextStyle(
            color: skin.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: IconThemeData(color: skin.textSecondary),
      ),
      body: _isLoading
          ? const Center(child: AgentLogoLoading())
          : _character == null
              ? Center(
                  child: Text(
                    '未初始化',
                    style: TextStyle(color: skin.textMuted),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 24,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _buildAvatar()),
                      const SizedBox(height: 32),
                      _sectionLabel('林埃的声音'),
                      const SizedBox(height: 4),
                      Text(
                        '使用“语音播放”中已经配置的服务，为林埃指定对应的声音标识。',
                        style: TextStyle(fontSize: 12, color: skin.textMuted),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _ttsVoiceIdController,
                        focusNode: _ttsVoiceIdFocusNode,
                        style: TextStyle(fontSize: 16, color: skin.textPrimary),
                        decoration: InputDecoration(
                          labelText: '声音标识',
                          hintText: '例如 Voice ID',
                          hintStyle: TextStyle(
                            color: skin.textMuted,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: skin.glassFill,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: skin.glassStroke),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: skin.glassStroke),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: skin.accent),
                          ),
                        ),
                        onChanged: _onTtsVoiceIdChanged,
                        onSubmitted: (_) => _flushTtsVoiceIdSave(),
                        onTapOutside: (_) => _flushTtsVoiceIdSave(),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _sectionLabel(String text) {
    const skin = HereIamThemeTokens.springRainDaydream;
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: skin.textMuted,
      ),
    );
  }

  Widget _buildAvatar() {
    const skin = HereIamThemeTokens.springRainDaydream;
    return GestureDetector(
      onTap: _pickAvatar,
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          CharacterAvatar(
            avatar: _avatarPreview,
            name: _character?.name ?? 'I',
            size: 120,
          ),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: skin.surfaceDeep,
              shape: BoxShape.circle,
              border: Border.all(color: skin.glassStroke),
            ),
            child: Icon(
              Icons.camera_alt_outlined,
              size: 16,
              color: skin.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

}
