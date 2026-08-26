import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:memex/agent/game_agent/game_agent.dart';
import 'package:memex/data/services/game/game_definition_import_service.dart';
import 'package:memex/data/services/game/game_session_service.dart';
import 'package:memex/data/services/game/turtle_soup_catalog.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';

class GameLibraryScreen extends StatefulWidget {
  const GameLibraryScreen({super.key});

  @override
  State<GameLibraryScreen> createState() => _GameLibraryScreenState();
}

class _GameLibraryScreenState extends State<GameLibraryScreen> {
  static const _rain = 'assets/images/雨玻璃.jpg';
  static const _ink = Color(0xFF293025);
  static const _muted = Color(0xFF667061);
  static const _accent = Color(0xFF737B46);
  static const _fog = Color(0xEAF7F5ED);

  List<GameDefinition> _definitions = const [];
  List<GameSession> _sessions = const [];
  bool _loading = true;
  bool _importing = false;
  bool _startingTurtleSoup = false;

  GameDefinitionImportService get _imports =>
      context.read<GameDefinitionImportService>();
  GameSessionService get _games => context.read<GameSessionService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _imports.listDefinitions(gameType: 'card_roleplay'),
        _games.listSessions(),
      ]);
      if (!mounted) return;
      setState(() {
        _definitions = values[0] as List<GameDefinition>;
        _sessions = values[1] as List<GameSession>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _definitions = const [];
        _sessions = const [];
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast('游戏库加载失败: $e');
      });
    }
  }

  Future<void> _importCard() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'json'],
    );
    final path = picked?.files.firstOrNull?.path;
    if (path == null) return;
    setState(() => _importing = true);
    try {
      final preview = await _imports.previewCardFromFile(path);
      if (!mounted) return;
      final accepted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => CharacterCardImportPreviewScreen(
            preview: preview,
            sourcePath: path,
          ),
        ),
      );
      if (accepted == true) {
        final definition = await _imports.importCardFromFile(path);
        _toast('已导入「${definition.title}」');
        await _load();
      }
    } catch (e) {
      _toast('角色卡无法导入：$e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openDefinition(GameDefinition definition) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameCharacterDetailScreen(definition: definition),
      ),
    );
    await _load();
  }

  Future<void> _openSession(GameSession session) async {
    final definition =
        _definitions.where((e) => e.id == session.definitionId).firstOrNull;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            GamePlayScreen(sessionId: session.id, definition: definition),
      ),
    );
    await _load();
  }

  Future<void> _startTurtleSoup() async {
    if (_startingTurtleSoup) return;
    setState(() => _startingTurtleSoup = true);
    try {
      final session = await _games.createTurtleSoupSession();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GamePlayScreen(sessionId: session.id),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('海龟汤开局失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _startingTurtleSoup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeSessions =
        _sessions.where((e) => e.status == 'active').toList();
    return Scaffold(
      backgroundColor: const Color(0xFF252A22),
      body: Stack(fit: StackFit.expand, children: [
        Image.asset(_rain, fit: BoxFit.cover),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
              child: Row(children: [
                _roundButton(Icons.arrow_back_ios_new_rounded,
                    () => Navigator.pop(context)),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('游戏',
                        style: TextStyle(
                            color: Color(0xFFF7F2E7),
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Colors.black45, blurRadius: 5)
                            ]))),
                TextButton.icon(
                  onPressed: _importing ? null : _importCard,
                  icon: _importing
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_rounded),
                  label: const Text('导入角色卡'),
                  style: TextButton.styleFrom(
                      backgroundColor: const Color(0xA8F5F1E7),
                      foregroundColor: _ink),
                ),
              ]),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: _accent,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 30),
                        children: [
                          if (activeSessions.isNotEmpty) ...[
                            _sectionTitle('继续游戏'),
                            const SizedBox(height: 9),
                            SizedBox(
                              height: 136,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: activeSessions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (_, i) {
                                  final session = activeSessions[i];
                                  final definition = _definitions
                                      .where(
                                          (e) => e.id == session.definitionId)
                                      .firstOrNull;
                                  return InkWell(
                                    onTap: () => _openSession(session),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Container(
                                      width: 240,
                                      padding: const EdgeInsets.all(12),
                                      decoration: _cardDecoration(),
                                      child: Row(children: [
                                        if (session.gameType == 'turtle_soup')
                                          const TurtleSoupCover(
                                              width: 78, height: 108)
                                        else
                                          GameCardImage(
                                              path: definition?.thumbnailPath,
                                              width: 78,
                                              height: 108),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                              Text(session.sessionTitle,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      color: _ink,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      height: 1.25)),
                                              const SizedBox(height: 8),
                                              Text(
                                                  _dateLabel(
                                                      session.lastPlayedAt),
                                                  style: const TextStyle(
                                                      color: _muted,
                                                      fontSize: 11)),
                                              const SizedBox(height: 10),
                                              const Text('继续',
                                                  style: TextStyle(
                                                      color: _accent,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12)),
                                            ])),
                                      ]),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 22),
                          ],
                          _sectionTitle('和林埃一起玩'),
                          const SizedBox(height: 9),
                          _turtleSoupCard(),
                          const SizedBox(height: 22),
                          _sectionTitle('角色卡'),
                          const SizedBox(height: 9),
                          if (_definitions.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: _cardDecoration(),
                              child: const Column(children: [
                                Icon(Icons.style_outlined,
                                    color: _accent, size: 34),
                                SizedBox(height: 10),
                                Text('导入 PNG 或 JSON 角色卡，开始一段独立故事',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: _muted)),
                              ]),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _definitions.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      crossAxisSpacing: 11,
                                      mainAxisSpacing: 12,
                                      childAspectRatio: .74),
                              itemBuilder: (_, i) {
                                final definition = _definitions[i];
                                return InkWell(
                                  onTap: () => _openDefinition(definition),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: _cardDecoration(),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                              child: GameCardImage(
                                                  path:
                                                      definition.thumbnailPath,
                                                  width: double.infinity,
                                                  height: double.infinity)),
                                          const SizedBox(height: 8),
                                          Text(definition.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  color: _ink,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 3),
                                          const Text('角色扮演',
                                              style: TextStyle(
                                                  color: _muted, fontSize: 11)),
                                        ]),
                                  ),
                                );
                              },
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

  Widget _roundButton(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
            backgroundColor: const Color(0xA8F5F1E7), foregroundColor: _ink),
      );

  Widget _sectionTitle(String title) => Text(title,
      style: const TextStyle(
          color: Color(0xFFF7F2E7),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          shadows: [Shadow(color: Colors.black45, blurRadius: 4)]));

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: _fog,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white70),
        boxShadow: const [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 14, offset: Offset(0, 5))
        ],
      );

  Widget _turtleSoupCard() => InkWell(
        onTap: _startingTurtleSoup ? null : _startTurtleSoup,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: _cardDecoration(),
          child: Row(children: [
            const TurtleSoupCover(width: 92, height: 104),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    Text('海龟汤',
                        style: TextStyle(
                            color: _ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                    SizedBox(width: 7),
                    _TinySticker(label: '是 / 不是'),
                  ]),
                  const SizedBox(height: 7),
                  const Text('林埃出汤面，你用提问一点点还原故事。汤面会一直钉在顶部，每一轮自动存档。',
                      style: TextStyle(color: _muted, height: 1.4)),
                  const SizedBox(height: 11),
                  Row(children: [
                    if (_startingTurtleSoup)
                      const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.play_arrow_rounded,
                          color: _accent, size: 18),
                    const SizedBox(width: 4),
                    Text(_startingTurtleSoup ? '正在盛汤…' : '新开一碗',
                        style: const TextStyle(
                            color: _accent, fontWeight: FontWeight.w700)),
                  ]),
                ],
              ),
            ),
          ]),
        ),
      );

  String _dateLabel(int seconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return '${dt.month}月${dt.day}日 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class CharacterCardImportPreviewScreen extends StatelessWidget {
  const CharacterCardImportPreviewScreen(
      {super.key, required this.preview, required this.sourcePath});
  final CharacterCardPreview preview;
  final String sourcePath;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF293025);
    const muted = Color(0xFF667061);
    final isPng = sourcePath.toLowerCase().endsWith('.png');
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2E7),
      appBar: AppBar(
          title: const Text('导入预览'), backgroundColor: const Color(0xFFF3F2E7)),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GameCardImage(
              path: isPng ? sourcePath : null, width: 112, height: 156),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(preview.name,
                    style: const TextStyle(
                        color: ink, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                    preview.spec == 'chara_card_v2'
                        ? 'SillyTavern V2'
                        : 'SillyTavern V1',
                    style: const TextStyle(color: muted)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final tag in preview.tags.take(6)) Chip(label: Text(tag))
                ]),
              ])),
        ]),
        const SizedBox(height: 22),
        _previewSection('角色描述', preview.description),
        _previewSection('开场白', preview.firstMessage),
        _previewSection(
            '世界书',
            preview.hasLorebook
                ? '${preview.lorebookEntryCount} 条（导入后保留；运行时动态召回尚未启用）'
                : '未包含世界书'),
        if (preview.creatorNotes?.isNotEmpty == true)
          _previewSection('创作者说明', preview.creatorNotes!),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认导入')),
        ),
      ),
    );
  }

  Widget _previewSection(String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  color: Color(0xFF737B46), fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(text.trim().isEmpty ? '无' : text,
              style: const TextStyle(color: Color(0xFF293025), height: 1.5)),
        ]),
      );
}

class GameCharacterDetailScreen extends StatefulWidget {
  const GameCharacterDetailScreen({super.key, required this.definition});
  final GameDefinition definition;

  @override
  State<GameCharacterDetailScreen> createState() =>
      _GameCharacterDetailScreenState();
}

class _GameCharacterDetailScreenState extends State<GameCharacterDetailScreen> {
  List<GameSession> _sessions = const [];

  GameSessionService get _games => context.read<GameSessionService>();
  GameDefinitionImportService get _imports =>
      context.read<GameDefinitionImportService>();

  Map<String, dynamic> get _data {
    try {
      final raw =
          jsonDecode(widget.definition.definitionJson) as Map<String, dynamic>;
      return raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : raw;
    } catch (_) {
      return const {};
    }
  }

  @override
  void initState() {
    super.initState();
    scheduleMicrotask(_load);
  }

  Future<void> _load() async {
    try {
      final sessions =
          await _games.listSessions(definitionId: widget.definition.id);
      if (mounted) setState(() => _sessions = sessions);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取故事列表失败：$e')),
      );
    }
  }

  Future<void> _start() async {
    try {
      final session = await _games.createSession(
        definitionId: widget.definition.id,
        gameType: widget.definition.gameType,
        definitionTitle: widget.definition.title,
        definitionSnapshotJson: widget.definition.definitionJson,
        firstMessage: _data['first_mes']?.toString(),
      );
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => GamePlayScreen(
                  sessionId: session.id, definition: widget.definition)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('开始故事失败：$e')),
      );
    }
  }

  Future<void> _remove() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除角色卡？'),
        content: const Text('已有故事会保留，但游戏库不再显示这张角色卡。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('移除')),
        ],
      ),
    );
    if (yes != true) return;
    await _imports.deleteDefinition(widget.definition.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF293025);
    const muted = Color(0xFF667061);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2E7),
      appBar: AppBar(
          title: Text(widget.definition.title),
          backgroundColor: const Color(0xFFF3F2E7),
          actions: [
            IconButton(
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '移除角色卡'),
          ]),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Center(
                child: GameCardImage(
                    path: widget.definition.thumbnailPath,
                    width: 172,
                    height: 238)),
            const SizedBox(height: 18),
            Text(widget.definition.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: ink, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(widget.definition.description,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, height: 1.5)),
            const SizedBox(height: 18),
            FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('新建故事')),
            if (_data['first_mes']?.toString().trim().isNotEmpty == true) ...[
              const SizedBox(height: 22),
              const Text('开场白',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text(_data['first_mes'].toString(),
                  style: const TextStyle(color: muted, height: 1.5)),
            ],
            if (_sessions.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('历史故事',
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
              for (final session in _sessions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(session.sessionTitle),
                  subtitle: Text(session.status == 'ended' ? '已结束' : '进行中'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GamePlayScreen(
                              sessionId: session.id,
                              definition: widget.definition))),
                ),
            ],
          ]),
    );
  }
}

class GamePlayScreen extends StatefulWidget {
  const GamePlayScreen({super.key, required this.sessionId, this.definition});
  final String sessionId;
  final GameDefinition? definition;

  @override
  State<GamePlayScreen> createState() => _GamePlayScreenState();
}

class _GamePlayScreenState extends State<GamePlayScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  GameSession? _session;
  List<GameMessage> _messages = const [];
  List<GameMessage> _markers = const [];
  List<GameSession> _branches = const [];
  bool _ooc = false;
  bool _sending = false;

  GameSessionService get _games => context.read<GameSessionService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _games.getSession(widget.sessionId),
        _games.getMessages(widget.sessionId),
        _games.getSaveMarkers(widget.sessionId),
        _games.listSessions(includeArchived: true),
      ]);
      if (!mounted) return;
      final allSessions = values[3] as List<GameSession>;
      setState(() {
        _session = values[0] as GameSession?;
        _messages = values[1] as List<GameMessage>;
        _markers = values[2] as List<GameMessage>;
        _branches = allSessions
            .where((e) => e.parentSessionId == widget.sessionId)
            .toList();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages = const [];
        _markers = const [];
        _branches = const [];
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('游戏加载失败: $e')));
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    final session = _session;
    if (text.isEmpty ||
        session == null ||
        _sending ||
        session.status == 'ended') {
      return;
    }
    _controller.clear();
    final oldHistory = List<GameMessage>.from(_messages);
    await _games.appendMessage(
        sessionId: session.id,
        role: 'user',
        content: text,
        messageType: _ooc ? 'ooc' : 'normal');
    setState(() => _sending = true);
    await _load();
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final reply = await GameAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        session: session,
        history: oldHistory,
        userMessage: text,
        isOoc: _ooc,
      ).join();
      if (reply.trim().isNotEmpty) {
        await _games.appendMessage(
            sessionId: session.id, role: 'assistant', content: reply.trim());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('这一轮没有跑出来：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
      await _load();
    }
  }

  Future<void> _save() async {
    await _games.saveSession(widget.sessionId);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已快速存档')));
    }
  }

  Future<void> _branch(GameMessage marker) async {
    final session = await _games.branchFromSaveMarker(
        parentSessionId: widget.sessionId, savepointMessageId: marker.id);
    if (!mounted) return;
    Navigator.pop(context);
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => GamePlayScreen(
              sessionId: session.id, definition: widget.definition)),
    );
  }

  Future<void> _endGame() async {
    final session = _session;
    if (session == null || _sending) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本局？'),
        content: const Text('会整理一份明确标记为虚构的故事摘要；原始游戏对话不会进入林埃的聊天记忆。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续玩')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('整理并结束')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _sending = true);
    try {
      final resources = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      final summary = await GameAgent.chat(
        client: resources.client,
        modelConfig: resources.modelConfig,
        session: session,
        history: _messages,
        userMessage: '请用第三人称简洁总结本局已经发生的故事、关键选择和当前结局，只输出摘要。',
        isOoc: true,
      ).join();
      await _games.endSession(session.id,
          storySummary: summary.trim().isEmpty ? '本局故事已结束。' : summary.trim());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('摘要整理失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _revealTurtleSoup() async {
    final session = _session;
    final puzzle = _turtleSoupPuzzle;
    if (session == null || puzzle == null || _sending) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('揭晓汤底？'),
        content: const Text('揭晓后本局就会结束；问题和回答仍会保存在这份游戏记录里。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('再猜一会儿')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('揭晓汤底')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() => _sending = true);
    try {
      await _games.appendMessage(
        sessionId: session.id,
        role: 'assistant',
        content: '汤底：${puzzle.solution}',
        messageType: 'reveal',
      );
      await _games.endSession(
        session.id,
        storySummary: '汤面：${puzzle.surface}\n汤底：${puzzle.solution}',
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('揭晓汤底失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool get _isTurtleSoup => _session?.gameType == 'turtle_soup';

  TurtleSoupPuzzle? get _turtleSoupPuzzle {
    final session = _session;
    if (session == null || session.gameType != 'turtle_soup') return null;
    try {
      final raw = jsonDecode(session.definitionSnapshotJson);
      if (raw is Map) {
        return TurtleSoupPuzzle.fromJson(Map<String, dynamic>.from(raw));
      }
    } catch (_) {}
    return null;
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F2E7),
      endDrawer: _isTurtleSoup ? null : Drawer(child: _saveDrawer()),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F2E7),
        titleSpacing: 0,
        title: Row(children: [
          if (_isTurtleSoup)
            const TurtleSoupCover(width: 36, height: 36, circular: true)
          else
            GameCardImage(
                path: widget.definition?.thumbnailPath,
                width: 36,
                height: 36,
                circular: true),
          const SizedBox(width: 9),
          Expanded(
              child: Text(
                  _isTurtleSoup
                      ? '海龟汤 · 林埃出题'
                      : session?.definitionTitle ?? '游戏',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ]),
        actions: [
          if (!_isTurtleSoup) ...[
            IconButton(
                onPressed: _save,
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: '快速存档'),
            Builder(
                builder: (context) => IconButton(
                    onPressed: () => Scaffold.of(context).openEndDrawer(),
                    icon: const Icon(Icons.account_tree_outlined),
                    tooltip: '存档与分支')),
          ] else
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Tooltip(
                message: '每一轮都会自动存档',
                child: Icon(Icons.cloud_done_outlined, size: 21),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'end') {
                _isTurtleSoup ? _revealTurtleSoup() : _endGame();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'end', child: Text(_isTurtleSoup ? '揭晓汤底' : '结束本局')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        if (_isTurtleSoup && _turtleSoupPuzzle != null)
          PinnedTurtleSoupSurface(puzzle: _turtleSoupPuzzle!),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
            itemCount:
                _messages.where((e) => e.messageType != 'save_marker').length +
                    (_sending ? 1 : 0),
            itemBuilder: (_, index) {
              final visible = _messages
                  .where((e) => e.messageType != 'save_marker')
                  .toList();
              if (index == visible.length) {
                return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Row(children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ]));
              }
              final message = visible[index];
              final user = message.role == 'user';
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment:
                        user ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!user) ...[
                        if (_isTurtleSoup)
                          const TurtleSoupCover(
                              width: 34, height: 34, circular: true)
                        else
                          GameCardImage(
                              path: widget.definition?.thumbnailPath,
                              width: 34,
                              height: 34,
                              circular: true),
                        const SizedBox(width: 9),
                      ],
                      Flexible(
                          child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: user
                              ? const Color(0xFFDDE2CD)
                              : Colors.white.withValues(alpha: .82),
                          borderRadius: BorderRadius.circular(16),
                          border: message.messageType == 'ooc'
                              ? Border.all(color: const Color(0xFF9A8051))
                              : null,
                        ),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (message.messageType == 'ooc')
                                const Padding(
                                    padding: EdgeInsets.only(bottom: 4),
                                    child: Text('场外',
                                        style: TextStyle(
                                            color: Color(0xFF9A8051),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700))),
                              if (_isTurtleSoup &&
                                  message.role == 'assistant' &&
                                  const {'是', '不是', '是也不是'}
                                      .contains(message.content.trim()))
                                TurtleSoupVerdict(
                                    verdict: message.content.trim())
                              else
                                Text(message.content,
                                    style: const TextStyle(
                                        color: Color(0xFF293025),
                                        height: 1.45)),
                            ]),
                      )),
                    ]),
              );
            },
          ),
        ),
        if (session?.status == 'ended')
          Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              color: const Color(0xFFDDE2CD),
              child: Text(
                  _isTurtleSoup ? '汤底已经揭晓，这局的问答记录会留在这里。' : '本局已结束，故事摘要已经保存。',
                  textAlign: TextAlign.center))
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(children: [
                if (!_isTurtleSoup) ...[
                  ChoiceChip(
                      label: Text(_ooc ? '场外' : '剧情'),
                      selected: _ooc,
                      onSelected: (_) => setState(() => _ooc = !_ooc),
                      selectedColor: const Color(0xFFE4D6B5)),
                  const SizedBox(width: 8),
                ],
                Expanded(
                    child: TextField(
                  controller: _controller,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(
                      hintText: _isTurtleSoup
                          ? '问一个可以用是或不是判断的问题…'
                          : _ooc
                              ? '给角色和剧情的场外指令'
                              : '你要做什么？',
                      filled: true,
                      fillColor: Colors.white70,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide.none)),
                )),
                const SizedBox(width: 8),
                IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.arrow_upward_rounded)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _saveDrawer() => SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const Text('存档与分支',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.bookmark_add_outlined),
              label: const Text('快速存档')),
          const SizedBox(height: 18),
          const Text('存档点', style: TextStyle(fontWeight: FontWeight.w700)),
          if (_markers.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('还没有存档点')),
          for (final marker in _markers)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmark_outline_rounded),
              title: Text(marker.savepointLabel ?? marker.content),
              subtitle: const Text('从这里继续会创建新分支'),
              trailing: const Icon(Icons.fork_right_rounded),
              onTap: () => _branch(marker),
            ),
          if (_branches.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('已有分支', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final branch in _branches)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(branch.sessionTitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (_) => GamePlayScreen(
                              sessionId: branch.id,
                              definition: widget.definition)));
                },
              ),
          ],
        ]),
      );
}

class GameCardImage extends StatelessWidget {
  const GameCardImage(
      {super.key,
      required this.path,
      required this.width,
      required this.height,
      this.circular = false});
  final String? path;
  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final filePath = path;
    Widget child;
    if (filePath != null &&
        filePath.isNotEmpty &&
        File(filePath).existsSync()) {
      child = Image.file(File(filePath),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder());
    } else {
      child = _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(circular ? 999 : 11),
      child: SizedBox(width: width, height: height, child: child),
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF9BA8A1),
        alignment: Alignment.center,
        child: const Icon(Icons.person_outline_rounded,
            color: Color(0xFFF7F4E9), size: 30),
      );
}

class PinnedTurtleSoupSurface extends StatelessWidget {
  const PinnedTurtleSoupSurface({super.key, required this.puzzle});

  final TurtleSoupPuzzle puzzle;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(13, 11, 13, 4),
        child: Stack(clipBehavior: Clip.none, children: [
          Transform.rotate(
            angle: -0.008,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFDF4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD9D0B5)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x250D1710),
                    blurRadius: 16,
                    offset: Offset(0, 7),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('汤面',
                        style: TextStyle(
                            color: Color(0xFF59623B),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    const SizedBox(width: 7),
                    _TinySticker(label: puzzle.difficulty),
                    const Spacer(),
                    const Text('已钉住',
                        style:
                            TextStyle(color: Color(0xFF8B836C), fontSize: 11)),
                    const SizedBox(width: 19),
                  ]),
                  const SizedBox(height: 9),
                  Text(
                    puzzle.surface,
                    style: const TextStyle(
                      color: Color(0xFF293025),
                      fontSize: 15.5,
                      height: 1.52,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 13,
            top: -9,
            child: Transform.rotate(
              angle: 0.13,
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E86B),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFF8F6D4), width: 2),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 7,
                        offset: Offset(0, 3)),
                  ],
                ),
                child: const Icon(Icons.push_pin_rounded,
                    color: Color(0xFF3F492D), size: 20),
              ),
            ),
          ),
        ]),
      );
}

class TurtleSoupVerdict extends StatelessWidget {
  const TurtleSoupVerdict({super.key, required this.verdict});

  final String verdict;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (verdict) {
      '是' => (Icons.check_rounded, const Color(0xFF66753E)),
      '不是' => (Icons.close_rounded, const Color(0xFF8A594E)),
      _ => (Icons.compare_arrows_rounded, const Color(0xFF87713F)),
    };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 6),
      Text(verdict,
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w800)),
    ]);
  }
}

class TurtleSoupCover extends StatelessWidget {
  const TurtleSoupCover({
    super.key,
    required this.width,
    required this.height,
    this.circular = false,
  });

  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(circular ? 999 : 14),
        child: Container(
          width: width,
          height: height,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF718073), Color(0xFF3E4A42)],
            ),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(Icons.ramen_dining_rounded,
                color: const Color(0xFFF4EDC7),
                size: (width < 45 ? width * .58 : width * .48)),
            Positioned(
              top: height * .12,
              right: width * .12,
              child: Container(
                width: width < 45 ? 10 : 18,
                height: width < 45 ? 10 : 18,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E86B),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(Icons.push_pin_rounded,
                    color: const Color(0xFF3F492D), size: width < 45 ? 8 : 13),
              ),
            ),
          ]),
        ),
      );
}

class _TinySticker extends StatelessWidget {
  const _TinySticker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFE7E99B),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0xFFC8CB72)),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Color(0xFF4F5733),
                fontSize: 9,
                fontWeight: FontWeight.w800)),
      );
}
