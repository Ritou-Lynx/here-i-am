import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:memex/agent/companion_agent/companion_agent.dart';
import 'package:memex/data/services/comic/comic_library_service.dart';
import 'package:memex/data/services/comic/comic_reading_progress_service.dart';
import 'package:memex/data/services/comic/comic_remote_service.dart';
import 'package:memex/data/services/persona_chat_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/ui/comic/comic_zoom_view.dart';
import 'package:memex/utils/user_storage.dart';

/// A page reference resolved from a chapter's pagesJson.
///
/// Two sources coexist on purpose:
///   * asset  — the bundled demo sample (works offline, no server needed)
///   * remote — a real crawled page, loaded through the Hermes image proxy
class _PageRef {
  final int pageNum;
  final String? assetPath;
  final String? remoteUrl;
  const _PageRef(this.pageNum, {this.assetPath, this.remoteUrl});
}

/// Manga reader. Webtoon-style: images fill the width and scroll vertically
/// (so text is legible — the old contain-fit made long strips tiny). Tap any
/// page for a full-screen pinch-zoom viewer. Scrolling updates reading
/// progress, which the companion injection in companion_agent.dart reads so
/// Lin Ai always knows the current page ("边看边聊").
class ComicReaderScreen extends StatefulWidget {
  final String mangaId;
  final String chapterId;

  const ComicReaderScreen({
    super.key,
    required this.mangaId,
    required this.chapterId,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  late String _chapterId = widget.chapterId;

  ComicManga? _manga;
  ComicChapter? _chapter;
  List<_PageRef> _pages = const [];
  String _baseUrl = '';

  int _current = 1;
  int _resumePage = 1;
  late final List<GlobalKey> _keys;

  final ScrollController _scroll = ScrollController();
  Timer? _scrollThrottle;

  String _characterId = '';
  String _characterName = '';

  bool _chatOpen = false;
  bool _sending = false;
  String _reply = '';
  final TextEditingController _input = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  List<PersonaChatMessage> _messages = const [];

  List<Map<String, String>> _comments = const [];
  bool _commentsOpen = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _keys = [];
    _load();
  }

  @override
  void dispose() {
    _scrollThrottle?.cancel();
    _scroll.dispose();
    _input.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final lib = ComicLibraryService.instance;
      final manga = await lib.getManga(widget.mangaId);
      final chapter = await lib.getChapter(_chapterId);
      final cfg = await ComicRemoteService(db: AppDatabase.instance).getConfig();
      final progress = await ComicReadingProgressService.instance
          .getProgress(widget.mangaId);

      final pages = _parsePages(chapter, cfg.baseUrl);
      final resume = (progress != null && progress.chapterId == _chapterId)
          ? progress.page
          : 1;

      // Parse comments from chapter data
      List<Map<String, String>> comments = const [];
      if (chapter?.commentsJson != null && chapter!.commentsJson!.isNotEmpty) {
        try {
          final arr = jsonDecode(chapter.commentsJson!) as List<dynamic>;
          comments = arr
              .map((e) => {
                    'user': (e['user'] as String?) ?? '',
                    'text': (e['text'] as String?) ?? '',
                  })
              .where((c) => c['user']!.isNotEmpty && c['text']!.isNotEmpty)
              .toList();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _manga = manga;
        _chapter = chapter;
        _baseUrl = cfg.baseUrl;
        _pages = pages;
        _comments = comments;
        _keys
          ..clear()
          ..addAll(List.generate(pages.length, (_) => GlobalKey()));
        _current = resume.clamp(1, pages.length == 0 ? 1 : pages.length);
        _resumePage = _current;
        _characterId = manga?.characterId ?? '';
        _characterName = manga?.title ?? '';
      });

      await _loadMessages();

      if (pages.isNotEmpty) {
        await ComicReadingProgressService.instance.recordProgress(
          mangaId: widget.mangaId,
          chapterId: _chapterId,
          page: _current,
        );
        // Jump to the resumed page after the first layout.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final idx = _resumePage - 1;
          if (idx >= 0 && idx < _keys.length) {
            final ctx = _keys[idx].currentContext;
            if (ctx != null) Scrollable.ensureVisible(ctx);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '加载失败: $e');
    }
  }

  Future<void> _loadMessages() async {
    if (_characterId.isEmpty) return;
    try {
      final msgs = await PersonaChatService.instance
          .getMessages(_characterId, limit: 50);
      if (!mounted) return;
      setState(() {
        _messages = msgs.reversed.toList();
      });
      _scrollChatToBottom();
    } catch (_) {}
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScroll.hasClients && _chatScroll.positions.isNotEmpty) {
        _chatScroll.animateTo(
          _chatScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  List<_PageRef> _parsePages(ComicChapter? ch, String baseUrl) {
    if (ch == null || ch.pagesJson == null || ch.pagesJson!.isEmpty) {
      return const [];
    }
    final List<dynamic> arr = jsonDecode(ch.pagesJson!);
    final out = <_PageRef>[];
    for (final e in arr) {
      final m = e as Map<String, dynamic>;
      final pn = (m['page_num'] as num?)?.toInt() ?? 0;
      final src = m['src'] as String?;
      if (src != null && src.startsWith('asset://')) {
        out.add(_PageRef(pn, assetPath: src.substring('asset://'.length)));
      } else if (src != null && src.startsWith('http')) {
        out.add(_PageRef(pn, remoteUrl: src));
      } else {
        // Real crawled page: go through the Hermes image proxy.
        final url = baseUrl.isNotEmpty
            ? '$baseUrl/v1/comic/images/${ch.id}/$pn'
            : null;
        out.add(_PageRef(pn, remoteUrl: url));
      }
    }
    out.sort((a, b) => a.pageNum.compareTo(b.pageNum));
    return out;
  }

  void _onScroll() {
    if (_scrollThrottle?.isActive ?? false) return;
    _scrollThrottle = Timer(const Duration(milliseconds: 180), _recomputeCurrent);
  }

  void _recomputeCurrent() {
    if (_pages.isEmpty) return;
    final center = MediaQuery.of(context).size.height / 2;
    int cur = 1;
    for (int i = 0; i < _keys.length; i++) {
      final ctx = _keys[i].currentContext;
      if (ctx == null) continue;
      final obj = ctx.findRenderObject();
      if (obj is! RenderBox || !obj.attached) continue;
      final top = obj.localToGlobal(Offset.zero).dy;
      if (top <= center) {
        cur = i + 1;
      } else {
        break;
      }
    }
    if (cur != _current) {
      setState(() => _current = cur);
      ComicReadingProgressService.instance.recordProgress(
        mangaId: widget.mangaId,
        chapterId: _chapterId,
        page: cur,
      );
    }
  }

  Widget _buildImage(_PageRef p) {
    if (p.assetPath != null) {
      return Image.asset(p.assetPath!, fit: BoxFit.fitWidth, width: double.infinity);
    }
    if (p.remoteUrl == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('未配置漫画服务地址，无法加载图片')),
      );
    }
    return CachedNetworkImage(
      imageUrl: p.remoteUrl!,
      fit: BoxFit.fitWidth,
      width: double.infinity,
      memCacheWidth: 800,
      placeholder: (ctx, url) => const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (ctx, url, e) => SizedBox(
        height: 200,
        child: Center(child: Text('图片加载失败\n$e', textAlign: TextAlign.center)),
      ),
    );
  }

  void _openZoom(_PageRef p) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ComicZoomView(
          assetPath: p.assetPath,
          networkUrl: p.remoteUrl,
        ),
      ),
    );
  }

  Future<void> _pickChapter() async {
    final chapters = await ComicLibraryService.instance.getChapters(widget.mangaId);
    if (!mounted) return;
    final ready = chapters.where((c) => c.status == 'ready').toList();
    if (ready.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('还没有已就绪的章节')),
      );
      return;
    }
    final picked = await showModalBottomSheet<ComicChapter>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('选择章节', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final c in ready)
              ListTile(
                title: Text(c.chapterTitle ?? '第 ${c.chapterNumber} 话'),
                trailing: c.id == _chapterId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked.id != _chapterId) {
      setState(() => _chapterId = picked.id);
      _load();
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _characterId.isEmpty) return;
    _input.clear();
    setState(() => _sending = true);

    final userId = await UserStorage.getUserId();
    if (userId == null) {
      if (!mounted) return;
      setState(() => _sending = false);
      return;
    }

    final userMsg = PersonaChatMessage(
      id: -1,
      characterId: _characterId,
      isFromCharacter: false,
      content: text,
      factId: null,
      isRead: true,
      timestamp: DateTime.now(),
      messageType: 'chat',
      attachmentsJson: null,
    );
    setState(() {
      _messages = [..._messages, userMsg];
      _reply = '';
    });
    _scrollChatToBottom();

    try {
      final res = await UserStorage.getAgentLLMResources(
        AgentDefinitions.companionAgent,
        defaultClientKey: LLMConfig.defaultClientKey,
      );
      // The current page is NOT passed here - companion_agent.dart injects it
      // from reading progress automatically.
      String full = '';
      await for (final chunk in CompanionAgent.chat(
        client: res.client,
        modelConfig: res.modelConfig,
        userId: userId,
        characterId: _characterId,
        userMessage: text,
        debugErrorOutput: true,
      )) {
        if (!mounted) return;
        full = chunk;
        setState(() => _reply = chunk);
        _scrollChatToBottom();
      }
      // Persist user message then AI reply so they enter the shared chat
      // history (loaded by _loadChatHistoryTurns next round and extracted by
      // dreaming).
      await PersonaChatService.instance
          .addUserMessage(_characterId, text);
      if (full.trim().isNotEmpty) {
        await PersonaChatService.instance
            .addCharacterMessage(_characterId, full, isRead: true);
      }
      await _loadMessages();
      if (mounted) setState(() => _reply = '');
    } catch (e) {
      if (!mounted) return;
      setState(() => _reply = '[出错] $e');
      await _loadMessages();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _buildBubble(String text, bool fromCharacter) {
    return Align(
      alignment: fromCharacter ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: fromCharacter ? Colors.white : const Color(0xFFD8F5B4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(text),
      ),
    );
  }

  Widget _buildChatFooter() {
    if (_chatOpen) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.4,
        decoration: const BoxDecoration(
          color: Color(0xFFF4F4F6),
          border: Border(top: BorderSide(color: Color(0xFFDDDDDD))),
        ),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.expand_more),
                  onPressed: () => setState(() => _chatOpen = false),
                ),
                Expanded(
                  child: Text(
                    '和林埃聊 · 第 $_current 页',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView.builder(
                controller: _chatScroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: _messages.length + (_reply.isNotEmpty ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _messages.length) {
                    return _buildBubble(_reply, true);
                  }
                  final m = _messages[i];
                  return _buildBubble(m.content, m.isFromCharacter);
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: '就这一页说一句…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: () => setState(() => _chatOpen = true),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFFF4F4F6),
          border: Border(top: BorderSide(color: Color(0xFFDDDDDD))),
        ),
        child: Row(
          children: [
            const Icon(Icons.chat_bubble_outline),
            const SizedBox(width: 8),
            Text('和林埃聊这页（第 $_current 页）'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _manga?.title ?? '漫画';
    final chTitle = _chapter?.chapterTitle ?? '';

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        )),
      );
    }
    if (_chapter == null || _pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('$title · $chTitle · 第 $_current/${_pages.length} 页',
            style: const TextStyle(fontSize: 14)),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _comments.isNotEmpty,
              label: Text('${_comments.length}'),
              child: const Icon(Icons.comment_outlined),
            ),
            tooltip: _comments.isEmpty ? '评论' : '评论 (${_comments.length})',
            onPressed: _openComments,
          ),
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: '切换章节',
            onPressed: _pickChapter,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _onScroll();
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return KeyedSubtree(
                    key: _keys[i],
                    child: Stack(
                      children: [
                        _buildImage(p),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            color: Colors.black54,
                            child: Text(
                              '${p.pageNum}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          _buildChatFooter(),
        ],
      ),
    );
  }

  void _openComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.2,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '评论 (${_comments.length})',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _comments.length,
                  itemBuilder: (_, i) {
                    final c = _comments[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                c['user']!.characters.first.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['user']!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  c['text']!,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}